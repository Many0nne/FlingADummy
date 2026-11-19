-- Poses procédurales des avatars (R15), vues par chaque client pour tous les joueurs d'après leurs attributs :
-- mannequin tenu au-dessus de la tête sur la zone de lancer, soulevé en boucle à l'entraînement, élan du lancer
-- (joueur local). Les articulations sont écrasées dans Stepped, après les animations par défaut.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Training = require(Shared:WaitForChild("Training"))

local HELD_SCALE = 0.6
local HELD_LIFT = GameConfig.THROW_HEIGHT - 0.7 -- mannequin posé sur les mains levées (studs au-dessus du torse)
local FOLLOW_THROUGH = 0.3 -- durée du geste après le lâcher (s)

type Pose = { shoulder: number, elbow: number, waist: number, lift: number, reach: number }

type State = {
	visual: Model?,
	key: string?,
	lastRep: number,
	lastPower: number,
}

local CharacterPoser = {}

local states: { [Player]: State } = {}
local throwStart: number? = nil
local released = false
local onRelease: (() -> ())? = nil

-- Cette méthode permet de mélanger deux valeurs lorsque l'on interpole une pose.
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Cette méthode permet de calculer la pose d'entraînement lorsque la répétition en est à `phase` (0-1) : bras à la
-- poitrine, puis au-dessus de la tête au milieu de la répétition.
local function liftPose(phase: number): Pose
	local s = 0.5 - 0.5 * math.cos(2 * math.pi * phase)
	return {
		shoulder = lerp(1.2, 2.95, s),
		elbow = lerp(1.7, 0.15, s),
		waist = lerp(0.12, -0.05, s),
		lift = lerp(0.7, HELD_LIFT, s),
		reach = lerp(-1.3, -0.3, s),
	}
end

-- Cette méthode permet de calculer la pose de l'élan lorsque le lancer en est à `t` secondes : penché en arrière
-- puis projeté vers l'avant au lâcher.
local function throwPose(t: number): Pose
	local windUp = GameConfig.WIND_UP_TIME
	if t < windUp * 0.7 then
		local k = t / (windUp * 0.7)
		return {
			shoulder = lerp(2.9, 3.4, k),
			elbow = lerp(0.3, 0.9, k),
			waist = lerp(0, -0.4, k),
			lift = HELD_LIFT,
			reach = lerp(-0.3, 1.2, k),
		}
	end
	local k = math.clamp((t - windUp * 0.7) / (windUp * 0.3 + FOLLOW_THROUGH), 0, 1)
	return {
		shoulder = lerp(3.4, 1.4, math.min(k * 2, 1)),
		elbow = lerp(0.9, 0.1, k),
		waist = lerp(-0.4, 0.35, math.min(k * 2, 1)),
		lift = HELD_LIFT,
		reach = lerp(1.2, -2, k),
	}
end

-- Cette méthode permet d'appliquer une pose aux articulations R15 d'un personnage lorsque Stepped tourne : on écrase
-- Transform après l'animateur (Motor6D, ou AnimationConstraint des avatars récents) ; sans pose, l'animateur reprend
-- la main à la frame suivante.
local function applyPose(character: Model, pose: Pose)
	local function set(partName: string, jointName: string, rotation: CFrame)
		local limb = character:FindFirstChild(partName)
		local joint = limb and limb:FindFirstChild(jointName)
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			(joint :: any).Transform = rotation
		end
	end
	set("RightUpperArm", "RightShoulder", CFrame.Angles(pose.shoulder, 0, -0.15))
	set("LeftUpperArm", "LeftShoulder", CFrame.Angles(pose.shoulder, 0, 0.15))
	set("RightLowerArm", "RightElbow", CFrame.Angles(pose.elbow, 0, 0))
	set("LeftLowerArm", "LeftElbow", CFrame.Angles(pose.elbow, 0, 0))
	set("UpperTorso", "Waist", CFrame.Angles(pose.waist, 0, 0))
end

-- Cette méthode permet de remplacer le mannequin décoratif d'un personnage lorsque ce qu'il tient change (`key`) ;
-- nil le retire.
local function setVisual(state: State, key: string?, build: (() -> Model)?)
	if state.key == key then
		return
	end
	if state.visual then
		state.visual:Destroy()
		state.visual = nil
	end
	state.key = key
	if build then
		local model = build()
		local primary = model.PrimaryPart :: BasePart
		primary.Anchored = true
		model.Parent = workspace
		state.visual = model
	end
end

-- Cette méthode permet de poser le mannequin décoratif au-dessus des mains (couché en travers des épaules)
-- lorsque la pose est appliquée.
local function placeVisual(state: State, root: BasePart, pose: Pose)
	if state.visual then
		local frame = root.CFrame * CFrame.new(0, pose.lift, pose.reach) * CFrame.Angles(0, 0, math.rad(90))
		state.visual:PivotTo(frame)
	end
end

-- Cette méthode permet de mettre à jour la pose et le mannequin décoratif d'un joueur lorsque Stepped tourne.
local function update(player: Player, state: State, now: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		setVisual(state, nil)
		return
	end
	local action = player:GetAttribute("Action")
	local isLocalThrow = player == Players.LocalPlayer and throwStart ~= nil
	if isLocalThrow then
		local t = now - (throwStart :: number)
		local pose = throwPose(t)
		applyPose(character, pose)
		if not released and t >= GameConfig.WIND_UP_TIME then
			released = true
			setVisual(state, nil)
			if onRelease then
				onRelease()
			end
		end
		if not released then
			placeVisual(state, root, pose)
		end
		if t >= GameConfig.WIND_UP_TIME + FOLLOW_THROUGH then
			throwStart = nil
		end
	elseif action == "Holding" then
		setVisual(state, "Holding", function()
			return DummyShape.buildVisual(HELD_SCALE)
		end)
		local pose = { shoulder = 2.9, elbow = 0.3, waist = 0, lift = HELD_LIFT, reach = -0.3 }
		applyPose(character, pose)
		placeVisual(state, root, pose)
	elseif action == "Training" then
		local tier = (player:GetAttribute("GearTier") :: number?) or 1
		setVisual(state, "Training" .. tier, function()
			local gear = Training.gear(tier)
			return DummyShape.buildVisual(gear.scale, gear.color, gear.material)
		end)
		local phase = ((now - state.lastRep) / GameConfig.REP_TIME + 0.5) % 1
		local pose = liftPose(phase)
		applyPose(character, pose)
		placeVisual(state, root, pose)
	else
		setVisual(state, nil)
	end
end

-- Cette méthode permet de suivre un joueur (rythme des répétitions d'après sa Throw Power) lorsqu'il est présent.
local function track(player: Player)
	local state: State = { visual = nil, key = nil, lastRep = os.clock(), lastPower = 0 }
	states[player] = state
	player:GetAttributeChangedSignal("ThrowPower"):Connect(function()
		state.lastRep = os.clock()
	end)
end

-- Cette méthode permet de lancer l'élan du joueur local lorsque la jauge est arrêtée ; `release` est appelé au
-- moment où le mannequin quitte ses mains.
function CharacterPoser.playThrow(release: () -> ())
	throwStart = os.clock()
	released = false
	onRelease = release
end

-- Cette méthode permet de savoir si l'élan du joueur local est en cours lorsque l'interface doit ignorer un clic.
function CharacterPoser.isThrowing(): boolean
	return throwStart ~= nil
end

-- Cette méthode permet de brancher le suivi des joueurs et la boucle des poses lorsque le client démarre.
function CharacterPoser.init()
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			setVisual(state, nil)
			states[player] = nil
		end
	end)
	RunService.Stepped:Connect(function()
		local now = os.clock()
		for player, state in states do
			update(player, state, now)
		end
	end)
end

return CharacterPoser
