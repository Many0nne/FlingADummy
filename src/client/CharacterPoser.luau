-- Animations des avatars (R15) et mannequins décoratifs : le joueur local joue les clips de Shared.AnimationData
-- (tenu, entraînement, lancer) sur son Animator, qui les réplique et pilote aussi bien les Motor6D que les
-- AnimationConstraint des avatars récents. Chaque client pose, pour tous les joueurs, le mannequin tenu sur la main
-- droite ou le poids d'entraînement sur les deux mains, d'après les attributs et la position des mains.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationData = require(Shared:WaitForChild("AnimationData"))
local Assets = require(Shared:WaitForChild("Assets"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Training = require(Shared:WaitForChild("Training"))

local HELD_SCALE = 0.6
local PALM_GAP = 0.3 -- demi-épaisseur de la main sous le mannequin couché (studs)
local FADE = 0.2 -- fondu d'entrée et de sortie des clips (s)
local THROW_FADE = 0.08
local RELEASE_GRACE = 0.25 -- lâcher de secours après le marqueur (clip absent ou en retard, s)
local THROW_TIMEOUT = 3 -- fin forcée d'un lancer local (s)
local FLY_TIME = 0.6 -- vol du mannequin décoratif lâché, en attendant le mannequin du serveur (s)
local FLY_SPIN = Vector3.new(7, 0, 2) -- rotation du mannequin décoratif lâché (rad/s)

type State = { visual: Model?, key: string? }
type Throw = {
	start: number,
	released: boolean,
	release: () -> (),
	velocity: Vector3,
	track: AnimationTrack?,
}
type Flying = { model: Model, velocity: Vector3, born: number }

local CharacterPoser = {}

local localPlayer = Players.LocalPlayer
local states: { [Player]: State } = {}
local animations: { [string]: Animation } = {}
local tracks: { character: Model?, byName: { [string]: AnimationTrack } } = { character = nil, byName = {} }
local throw: Throw? = nil
local flying: Flying? = nil

local CLIPS: { [string]: AnimationData.Clip } = {}
for _, clip in AnimationData.CLIPS do
	CLIPS[clip.name] = clip
end

-- Cette méthode permet de donner l'Animation d'un clip lorsque l'on le charge : asset publié, ou dans Studio le
-- clip construit à la volée (KeyframeSequenceProvider) tant qu'il n'est pas publié ; nil sinon.
local function animationFor(clip: AnimationData.Clip): Animation?
	local cached = animations[clip.name]
	if cached then
		return cached
	end
	local uri = Assets.uri(Assets.ANIMATIONS[clip.name])
	if not uri and RunService:IsStudio() then
		local ok, result = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(AnimationData.buildSequence(clip))
		end)
		uri = if ok then result else nil
	end
	if not uri then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = clip.name
	animation.AnimationId = uri
	animations[clip.name] = animation
	return animation
end

-- Cette méthode permet de donner la piste d'un clip sur le personnage du joueur local (chargée une fois par
-- personnage) lorsque l'on la joue ou l'arrête ; nil sans Animator ou sans animation.
local function trackFor(name: string): AnimationTrack?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	if tracks.character ~= character then
		tracks = { character = character, byName = {} }
	end
	local existing = tracks.byName[name]
	if existing then
		return existing
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animation = animationFor(CLIPS[name])
	if not animator or not animation then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end
	tracks.byName[name] = track
	return track
end

-- Cette méthode permet de jouer ou d'arrêter un clip en boucle du joueur local lorsque son action change ;
-- l'entraînement est calé sur REP_TIME et démarre au sommet, là où le serveur compte la répétition.
local function setLooping(name: string, on: boolean)
	local track = if on then trackFor(name) else tracks.byName[name]
	if not track then
		return
	end
	if on and not track.IsPlaying then
		track:Play(FADE)
		if name == "Train" then
			local clip = CLIPS.Train
			track:AdjustSpeed(clip.length / GameConfig.REP_TIME)
			track.TimePosition = clip.markers.Top
		end
	elseif not on and track.IsPlaying then
		track:Stop(FADE)
	end
end

-- Cette méthode permet de calculer où poser le mannequin tenu (couché sur la paume droite, dos contre la main, tête
-- vers l'avant du personnage) lorsque le personnage le porte ou le lance ; suit le bras pendant tout le geste.
local function palmFrame(character: Model, root: BasePart, scale: number): CFrame
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	local arm = character:FindFirstChild("RightUpperArm") :: BasePart?
	local fallback = root.CFrame * CFrame.new(0, GameConfig.THROW_HEIGHT, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	if not hand or not arm then
		return fallback
	end
	local reach = hand.Position - arm.Position
	if reach.Magnitude < 0.1 then
		return fallback
	end
	local up = reach.Unit
	local forward = root.CFrame.LookVector
	local head = forward - up * forward:Dot(up)
	if head.Magnitude < 0.05 then
		head = -root.CFrame.UpVector
	end
	head = head.Unit
	local back = -up
	local center = hand.Position + up * (PALM_GAP + 0.55 * scale) + head * (0.5 * scale)
	return CFrame.fromMatrix(center, head:Cross(back), head, back)
end

-- Cette méthode permet de calculer où poser le poids d'entraînement (couché en travers des deux mains, à plat)
-- lorsque le personnage s'entraîne.
local function liftFrame(character: Model, root: BasePart, scale: number): CFrame
	local left = character:FindFirstChild("LeftHand") :: BasePart?
	local right = character:FindFirstChild("RightHand") :: BasePart?
	local up = root.CFrame.UpVector
	if not left or not right then
		return root.CFrame * CFrame.new(0, GameConfig.THROW_HEIGHT, 0) * CFrame.Angles(-math.pi / 2, 0, -math.pi / 2)
	end
	local across = right.Position - left.Position
	across -= up * across:Dot(up)
	across = if across.Magnitude > 0.05 then across.Unit else root.CFrame.RightVector
	local center = (left.Position + right.Position) / 2 + up * (PALM_GAP + 0.55 * scale)
	local back = -up
	return CFrame.fromMatrix(center, across:Cross(back), across, back)
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
		model.Parent = Workspace
		state.visual = model
	end
end

-- Cette méthode permet de lâcher le mannequin du joueur local lorsque l'animation de lancer atteint son marqueur
-- Release (ou le délai de secours) : le mannequin décoratif part sur sa lancée et le lancer est envoyé au serveur.
local function release()
	local current = throw
	if not current or current.released then
		return
	end
	current.released = true
	local state = states[localPlayer]
	if state and state.visual then
		if flying then
			flying.model:Destroy()
		end
		flying = { model = state.visual, velocity = current.velocity, born = os.clock() }
		state.visual = nil
		state.key = nil
	end
	current.release()
end

-- Cette méthode permet d'avancer le mannequin décoratif lâché (balistique, en vrille) lorsque Heartbeat tourne ; il
-- disparaît quand le mannequin du serveur arrive (handOff) ou après FLY_TIME.
local function updateFlying(now: number, dt: number)
	local current = flying
	if not current then
		return
	end
	if now - current.born > FLY_TIME or not current.model.Parent then
		current.model:Destroy()
		flying = nil
		return
	end
	current.velocity -= Vector3.new(0, Workspace.Gravity * dt, 0)
	local spin = CFrame.Angles(FLY_SPIN.X * dt, FLY_SPIN.Y * dt, FLY_SPIN.Z * dt)
	local pivot = current.model:GetPivot()
	current.model:PivotTo((pivot + current.velocity * dt) * spin)
end

-- Cette méthode permet de jouer les clips en boucle du joueur local selon son action et de clore son lancer
-- lorsque Heartbeat tourne.
local function updateLocal(action: any, now: number)
	local current = throw
	if current then
		local playing = current.track ~= nil and current.track.IsPlaying
		if now - current.start > THROW_TIMEOUT or (current.released and not playing) then
			throw = nil
			current = nil
		end
	end
	setLooping("Hold", action == "Holding" and current == nil)
	setLooping("Train", action == "Training")
end

-- Cette méthode permet de mettre à jour le mannequin décoratif d'un joueur lorsque Heartbeat tourne.
local function update(player: Player, state: State)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		setVisual(state, nil)
		return
	end
	local action = player:GetAttribute("Action")
	local releasedHere = player == localPlayer and throw ~= nil and throw.released
	if action == "Holding" and not releasedHere then
		setVisual(state, "Holding", function()
			return DummyShape.buildVisual(HELD_SCALE)
		end)
		if state.visual then
			state.visual:PivotTo(palmFrame(character, root, HELD_SCALE))
		end
	elseif action == "Training" then
		local tier = (player:GetAttribute("GearTier") :: number?) or 1
		local gear = Training.gear(tier)
		setVisual(state, "Training" .. tier, function()
			return DummyShape.buildVisual(gear.scale, { color = gear.color, material = gear.material })
		end)
		if state.visual then
			state.visual:PivotTo(liftFrame(character, root, gear.scale))
		end
	else
		setVisual(state, nil)
	end
end

-- Cette méthode permet de lancer le geste du joueur local lorsque la jauge est arrêtée : clip de lancer, puis
-- `onRelease` au marqueur Release ; `velocity` est la vitesse de départ du mannequin (vol du décoratif).
function CharacterPoser.playThrow(onRelease: () -> (), velocity: Vector3)
	local current: Throw = { start = os.clock(), released = false, release = onRelease, velocity = velocity }
	throw = current
	setLooping("Hold", false)
	local track = trackFor("Throw")
	if track then
		current.track = track
		track:GetMarkerReachedSignal("Release"):Once(release)
		track:Play(THROW_FADE)
	end
	task.delay(GameConfig.THROW_RELEASE_TIME + RELEASE_GRACE, function()
		if throw == current then
			release()
		end
	end)
end

-- Cette méthode permet de savoir si le geste du joueur local est en cours lorsque l'interface doit ignorer un clic.
function CharacterPoser.isThrowing(): boolean
	return throw ~= nil
end

-- Cette méthode permet de retirer le mannequin décoratif lâché lorsque le mannequin du serveur prend le relais.
function CharacterPoser.handOff()
	if flying then
		flying.model:Destroy()
		flying = nil
	end
end

-- Cette méthode permet de brancher le suivi des joueurs et la boucle des animations lorsque le client démarre.
function CharacterPoser.init()
	local function track(player: Player)
		states[player] = { visual = nil, key = nil }
	end
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
	-- Heartbeat : après la simulation, les mains sont à leur place animée de la frame
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		updateLocal(localPlayer:GetAttribute("Action"), now)
		for player, state in states do
			update(player, state)
		end
		updateFlying(now, dt)
	end)
end

return CharacterPoser
