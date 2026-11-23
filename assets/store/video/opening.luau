--# selene: allow(global_usage)
-- Ouverture de la vidéo de présentation (#225), Studio seulement : à coller dans le MCP Studio (execute_luau, contexte
-- Client, en Play) après camera.luau, avatar habillé par server.luau. Définit _G.FadOpening :
--   _G.FadOpening.setup()  pose le Crash Dummy debout sur le podium de l'appareil d'entraînement de la place 1 et place
--                          l'avatar à son point de départ ;
--   _G.FadOpening.run()    joue la prise (repère magenta, marche, coups, gros coup, chute, traîné par la cheville
--                          jusqu'à la bande), caméras comprises : environ 11 s ;
--   _G.FadOpening.clear()  retire le mannequin et rend l'avatar.
-- L'avatar est le personnage du joueur (marche et repos du jeu) ; ses gestes sont des clips au format de
-- Shared.AnimationData, enregistrés dans Studio (KeyframeSequenceProvider). Le mannequin est construit comme en jeu
-- (Shared.DummyShape), ancré, posé pièce par pièce à chaque image.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationData = require(Shared.AnimationData)
local DummyShape = require(Shared.DummyShape)
local Sounds = require(Shared.Sounds)
local ThrowDummies = require(Shared.ThrowDummies)

local O = _G.FadOpening or {}
_G.FadOpening = O

local SCALE = 0.78 -- mannequin à hauteur de l'avatar
local FEET = 3.82 -- du centre du torse au bas des pieds, échelle 1 (Shared.DummyShape)
local PODIUM = 1.6 -- dessus du podium d'entraînement (pastille comprise)
local DUMMY_AT = Vector3.new(-60, PODIUM, -50) -- pieds du mannequin, au centre du podium de la place 1
local TOWARD = Vector3.new(1, 0, 0) -- l'avatar arrive par la droite du podium (vu de la bande)
local AVATAR_SPOT = DUMMY_AT + TOWARD * 2.6 + Vector3.new(0, 1.5, 0) -- poing au contact du mannequin
local START = Vector3.new(-47, 3, -38)
local DRAG_TO = Vector3.new(-52, 3, -24)
local UP = Vector3.yAxis

-- Rotules des membres du mannequin (Shared.DummyShape.JOINTS), à l'échelle 1
local LIMBS = {
	{ name = "Head", pivot = Vector3.new(0, 1.28, 0) },
	{ name = "LeftUpperArm", pivot = Vector3.new(-1.45, 1.05, 0) },
	{ name = "LeftLowerArm", pivot = Vector3.new(-1.45, -0.01, 0), parent = "LeftUpperArm" },
	{ name = "RightUpperArm", pivot = Vector3.new(1.45, 1.05, 0) },
	{ name = "RightLowerArm", pivot = Vector3.new(1.45, -0.01, 0), parent = "RightUpperArm" },
	{ name = "LeftUpperLeg", pivot = Vector3.new(-0.5, -1.2, 0) },
	{ name = "LeftLowerLeg", pivot = Vector3.new(-0.5, -2.51, 0), parent = "LeftUpperLeg" },
	{ name = "RightUpperLeg", pivot = Vector3.new(0.5, -1.2, 0) },
	{ name = "RightLowerLeg", pivot = Vector3.new(0.5, -2.51, 0), parent = "RightUpperLeg" },
}

-- Gestes de l'avatar (repère du personnage : X à droite, Y en haut, -Z devant ; bras : +X lève le bras devant)
local GUARD = {
	UpperTorso = { 4, 0, 0 },
	RightUpperArm = { 50, 0, -12 },
	RightLowerArm = { 95, 0, 0 },
	LeftUpperArm = { 50, 0, 12 },
	LeftLowerArm = { 95, 0, 0 },
	Head = { 0, 0, 0 },
}
local function jab(side: string): AnimationData.Clip
	local right = side == "R"
	local hit = {
		UpperTorso = { 6, if right then 28 else -28, 0 },
		RightUpperArm = if right then { 92, 0, -8 } else { 45, 0, -10 },
		RightLowerArm = if right then { 0, 0, 0 } else { 100, 0, 0 },
		LeftUpperArm = if right then { 45, 0, 10 } else { 92, 0, 8 },
		LeftLowerArm = if right then { 100, 0, 0 } else { 0, 0, 0 },
		Head = { 0, if right then -10 else 10, 0 },
	}
	return {
		name = "VidJab" .. side,
		length = 0.34,
		loop = false,
		priority = "Action",
		markers = { Hit = 0.09 },
		keyframes = {
			{ t = 0, ease = "CubicV2", dir = "Out", poses = GUARD },
			{ t = 0.09, ease = "CubicV2", dir = "InOut", poses = hit },
			{ t = 0.34, ease = "CubicV2", dir = "InOut", poses = GUARD },
		},
	}
end

local CLIPS: { AnimationData.Clip } = {
	{
		name = "VidGuard",
		length = 0.6,
		loop = true,
		priority = "Action",
		markers = {},
		keyframes = { { t = 0, poses = GUARD }, { t = 0.6, poses = GUARD } },
	},
	jab("R"),
	jab("L"),
	{
		name = "VidHaymaker",
		length = 0.9,
		loop = false,
		priority = "Action",
		markers = { Hit = 0.42 },
		keyframes = {
			{ t = 0, ease = "CubicV2", dir = "InOut", poses = GUARD },
			{
				t = 0.3,
				ease = "CubicV2",
				dir = "In",
				poses = {
					LowerTorso = { 0, -20, 0, 0.2, -0.15, 0.35 },
					UpperTorso = { -6, -38, 0 },
					RightUpperArm = { 20, 0, 55 },
					RightLowerArm = { 70, 0, 0 },
					LeftUpperArm = { 60, 0, 20 },
					LeftLowerArm = { 80, 0, 0 },
					Head = { 0, 30, 0 },
				},
			},
			{
				t = 0.42,
				ease = "CubicV2",
				dir = "Out",
				poses = {
					LowerTorso = { 0, 22, 0, -0.1, -0.3, -0.5 },
					UpperTorso = { 14, 42, 0 },
					RightUpperArm = { 115, 0, -12 },
					RightLowerArm = { 5, 0, 0 },
					LeftUpperArm = { -20, 0, 25 },
					LeftLowerArm = { 40, 0, 0 },
					Head = { -6, -30, 0 },
				},
			},
			{
				t = 0.9,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					LowerTorso = { 0, 8, 0, 0, -0.1, -0.2 },
					UpperTorso = { 6, 14, 0 },
					RightUpperArm = { 40, 0, -6 },
					RightLowerArm = { 30, 0, 0 },
					LeftUpperArm = { 10, 0, 10 },
					LeftLowerArm = { 30, 0, 0 },
					Head = { 0, -10, 0 },
				},
			},
		},
	},
	{
		name = "VidLaugh", -- mains sur le ventre, tête en arrière, secousses
		length = 0.36,
		loop = true,
		priority = "Action",
		markers = {},
		keyframes = {
			{
				t = 0,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					LowerTorso = { 0, 0, 0, 0, 0, 0 },
					UpperTorso = { -16, 0, 0 },
					Head = { -22, 0, 0 },
					RightUpperArm = { 22, 0, -28 },
					RightLowerArm = { 80, 0, 0 },
					LeftUpperArm = { 22, 0, 28 },
					LeftLowerArm = { 80, 0, 0 },
				},
			},
			{
				t = 0.18,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					LowerTorso = { 0, 0, 0, 0, -0.08, 0 },
					UpperTorso = { -6, 0, 0 },
					Head = { -8, 0, 0 },
					RightUpperArm = { 18, 0, -24 },
					RightLowerArm = { 88, 0, 0 },
					LeftUpperArm = { 18, 0, 24 },
					LeftLowerArm = { 88, 0, 0 },
				},
			},
			{
				t = 0.36,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					LowerTorso = { 0, 0, 0, 0, 0, 0 },
					UpperTorso = { -16, 0, 0 },
					Head = { -22, 0, 0 },
					RightUpperArm = { 22, 0, -28 },
					RightLowerArm = { 80, 0, 0 },
					LeftUpperArm = { 22, 0, 28 },
					LeftLowerArm = { 80, 0, 0 },
				},
			},
		},
	},
	{
		name = "VidPoint", -- montre le mannequin du doigt en riant
		length = 0.4,
		loop = true,
		priority = "Action",
		markers = {},
		keyframes = {
			{
				t = 0,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					UpperTorso = { -12, 10, 0 },
					Head = { -14, -8, 0 },
					RightUpperArm = { 85, 0, -5 },
					RightLowerArm = { 5, 0, 0 },
					LeftUpperArm = { 20, 0, 30 },
					LeftLowerArm = { 85, 0, 0 },
				},
			},
			{
				t = 0.2,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					UpperTorso = { -4, 10, 0 },
					Head = { -4, -8, 0 },
					RightUpperArm = { 80, 0, -5 },
					RightLowerArm = { 8, 0, 0 },
					LeftUpperArm = { 16, 0, 26 },
					LeftLowerArm = { 92, 0, 0 },
				},
			},
			{
				t = 0.4,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					UpperTorso = { -12, 10, 0 },
					Head = { -14, -8, 0 },
					RightUpperArm = { 85, 0, -5 },
					RightLowerArm = { 5, 0, 0 },
					LeftUpperArm = { 20, 0, 30 },
					LeftLowerArm = { 85, 0, 0 },
				},
			},
		},
	},
	{
		name = "VidReach", -- se penche pour attraper la cheville
		length = 0.4,
		loop = false,
		priority = "Action",
		markers = {},
		keyframes = {
			{ t = 0, ease = "CubicV2", dir = "InOut", poses = GUARD },
			{
				t = 0.4,
				ease = "CubicV2",
				dir = "Out",
				poses = {
					LowerTorso = { 0, 0, 0, 0, -0.5, 0 },
					UpperTorso = { 38, 0, 0 },
					Head = { -10, 0, 0 },
					RightUpperArm = { 55, 0, 4 },
					RightLowerArm = { 10, 0, 0 },
					LeftUpperArm = { 20, 0, 12 },
					LeftLowerArm = { 30, 0, 0 },
				},
			},
		},
	},
	{
		name = "VidChuckle", -- glousse sur la bande, mannequin tenu (tête et buste seulement, au-dessus du tenu du jeu)
		length = 0.32,
		loop = true,
		priority = "Action2",
		markers = {},
		keyframes = {
			{ t = 0, ease = "CubicV2", dir = "InOut", poses = { UpperTorso = { -10, 0, 0 }, Head = { -20, 0, 0 } } },
			{ t = 0.16, ease = "CubicV2", dir = "InOut", poses = { UpperTorso = { -2, 0, 0 }, Head = { -6, 0, 0 } } },
			{ t = 0.32, ease = "CubicV2", dir = "InOut", poses = { UpperTorso = { -10, 0, 0 }, Head = { -20, 0, 0 } } },
		},
	},
	{
		name = "VidDrag", -- tire le mannequin derrière lui, bras droit en arrière, regard par-dessus l'épaule
		length = 0.8,
		loop = true,
		priority = "Action",
		markers = {},
		keyframes = {
			{
				t = 0,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					UpperTorso = { 16, -8, 0 },
					Head = { -6, -35, 0 },
					RightUpperArm = { -38, 0, 22 },
					RightLowerArm = { 6, 0, 0 },
					LeftUpperArm = { 30, 0, 12 },
					LeftLowerArm = { 40, 0, 0 },
				},
			},
			{
				t = 0.4,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					UpperTorso = { 20, -10, 0 },
					Head = { -8, -40, 0 },
					RightUpperArm = { -34, 0, 20 },
					RightLowerArm = { 8, 0, 0 },
					LeftUpperArm = { -10, 0, 12 },
					LeftLowerArm = { 30, 0, 0 },
				},
			},
			{
				t = 0.8,
				ease = "CubicV2",
				dir = "InOut",
				poses = {
					UpperTorso = { 16, -8, 0 },
					Head = { -6, -35, 0 },
					RightUpperArm = { -38, 0, 22 },
					RightLowerArm = { 6, 0, 0 },
					LeftUpperArm = { 30, 0, 12 },
					LeftLowerArm = { 40, 0, 0 },
				},
			},
		},
	},
}

-- Cette méthode permet de convertir un triplet de degrés en rotation lorsque l'on pose un membre.
local function angles(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

-- Cette méthode permet de mettre une direction à plat (sans composante verticale) lorsque l'on oriente un modèle.
local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, 1)
end

-- Cette méthode permet de jouer un son du jeu (Shared.Sounds) à une position lorsque un coup porte.
local function sound(name: string, at: Vector3, volume: number?, pitch: number?)
	local def = Sounds[name]
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = Workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = (volume or 1) * def.volume
	s.PlaybackSpeed = pitch or 1
	s.RollOffMinDistance = 40
	s.Parent = holder
	s:Play()
	task.delay(4, function()
		holder:Destroy()
	end)
end

-- État du mannequin (une seule prise à la fois)
local dummy: Model? = nil
local base: { [BasePart]: CFrame } = {}
local owner: { [BasePart]: string } = {}
local state = {
	mode = "stand", -- stand | fall | lying | grab | drag
	tilt = 0, -- inclinaison vers l'arrière (rad)
	spin = 0, -- vitesse d'inclinaison (rad/s)
	grabbed = 0, -- instant du début de la prise par la cheville
	from = CFrame.identity, -- repère du mannequin au début de la prise
	t = 0,
}

-- Cette méthode permet de calculer la transformation (repère du torse) de chaque membre pour une pose
-- `{ [membre] = Vector3 degrés }` lorsque l'on pose le mannequin.
local function transforms(pose: { [string]: Vector3 }): { [string]: CFrame }
	local out = { Torso = CFrame.identity }
	for _, limb in LIMBS do
		local pivot = limb.pivot * SCALE
		local own = CFrame.new(pivot) * angles(pose[limb.name] or Vector3.zero) * CFrame.new(-pivot)
		out[limb.name] = if limb.parent then out[limb.parent] * own else own
	end
	return out
end

-- Cette méthode permet de poser chaque pièce du mannequin (torse en `root`, membres en `pose`) lorsque une image est
-- rendue.
local function place(root: CFrame, pose: { [string]: Vector3 })
	local tf = transforms(pose)
	for part, offset in base do
		part.CFrame = root * (tf[owner[part]] or CFrame.identity) * offset
	end
end

-- Cette méthode permet de construire le Crash Dummy (mannequin à lancer de départ) ancré, pièces détachées les unes
-- des autres, et de noter pour chaque pièce son membre porteur lorsque la prise est préparée.
local function build(): Model
	local model = DummyShape.buildVisual(SCALE, ThrowDummies.variant(1))
	model.Name = "FadOpeningDummy"
	local pieces = {}
	for _, limb in LIMBS do
		pieces[limb.name] = true
	end
	pieces.Torso = true
	base, owner = {}, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local name = part.Name
			if not pieces[name] then
				-- Pièce ajoutée (visage, cible) : portée par la pièce à laquelle elle est soudée
				name = "Torso"
				for _, joint in part:GetChildren() do
					if joint:IsA("WeldConstraint") or joint:IsA("JointInstance") then
						local other = if (joint :: any).Part0 == part
							then (joint :: any).Part1
							else (joint :: any).Part0
						if other and pieces[other.Name] then
							name = other.Name
						end
					end
				end
			end
			owner[part] = name
			base[part] = part.CFrame -- modèle construit torse à l'origine
		end
	end
	for _, joint in model:GetDescendants() do
		if joint:IsA("WeldConstraint") or joint:IsA("JointInstance") then
			joint:Destroy()
		end
	end
	for part in base do
		part.Anchored = true
	end
	model.Parent = Workspace
	return model
end

-- Cette méthode permet de calculer le repère du mannequin debout, incliné de `tilt` vers l'arrière autour de ses pieds,
-- face à l'avatar, lorsque il encaisse ou tombe.
local function standFrame(tilt: number): CFrame
	local axis = TOWARD:Cross(UP)
	local turn = CFrame.fromAxisAngle(axis, tilt)
	local face = CFrame.lookAt(Vector3.zero, TOWARD)
	return CFrame.new(DUMMY_AT) * turn * CFrame.new(0, FEET * SCALE, 0) * face
end

-- Cette méthode permet de calculer le repère du mannequin traîné par la cheville (pieds dans la main droite de
-- l'avatar, couché sur le dos, tête au sol derrière lui) lorsque l'avatar le tire.
local function dragFrame(): CFrame
	local character = Players.LocalPlayer.Character :: Model
	local hand = (character:FindFirstChild("RightHand") :: BasePart).Position - Vector3.new(0, 0.25, 0)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local behind = -flat(root.CFrame.LookVector)
	local length = 7.4 * SCALE
	local ground = if math.abs(hand.X - DUMMY_AT.X) < 5 and math.abs(hand.Z - DUMMY_AT.Z) < 5 then PODIUM else 0
	local along = (behind * length + Vector3.new(0, ground + 0.6 - hand.Y, 0)).Unit
	local faceUp = (UP - along * along:Dot(UP)).Unit
	local back = -faceUp
	local right = along:Cross(back)
	local center = hand + along * (FEET - 0.45) * SCALE
	return CFrame.fromMatrix(center, right, along, back)
end

-- Cette méthode permet d'animer le mannequin à chaque image (ressort quand il encaisse, chute, couché, traîné)
-- lorsque la prise tourne.
local function step(dt: number)
	if not dummy then
		return
	end
	state.t += dt
	local s = state
	local wob = math.clamp(-s.spin * 10, -45, 45)
	if s.mode == "stand" then
		-- Ressort amorti : il se redresse en oscillant
		s.spin += (-90 * s.tilt - 7 * s.spin) * dt
		s.tilt += s.spin * dt
		place(standFrame(s.tilt), {
			Head = Vector3.new(wob * 0.5, 0, 0),
			LeftUpperArm = Vector3.new(wob, 0, -8),
			RightUpperArm = Vector3.new(wob, 0, 8),
			LeftLowerArm = Vector3.new(wob * 0.4, 0, 0),
			RightLowerArm = Vector3.new(wob * 0.4, 0, 0),
		})
	elseif s.mode == "fall" or s.mode == "lying" then
		if s.mode == "fall" then
			s.spin += (12 * math.sin(math.max(s.tilt, 0.15))) * dt
			s.tilt += s.spin * dt
			local rest = math.rad(88)
			if s.tilt >= rest then
				s.tilt = rest
				s.spin = -s.spin * 0.28
				if math.abs(s.spin) < 0.6 then
					s.mode = "lying"
					s.spin = 0
				end
			end
		end
		local flop = if s.mode == "fall" then math.clamp(s.tilt * 70, 0, 120) else 120
		place(standFrame(s.tilt), {
			Head = Vector3.new(-15, 0, 0),
			LeftUpperArm = Vector3.new(0, 0, -flop),
			RightUpperArm = Vector3.new(0, 0, flop),
			LeftUpperLeg = Vector3.new(0, 0, -10),
			RightUpperLeg = Vector3.new(0, 0, 10),
		})
	elseif s.mode == "grab" or s.mode == "drag" then
		local k = math.clamp((state.t - s.grabbed) / 0.35, 0, 1)
		k = k * k * (3 - 2 * k)
		local target = dragFrame()
		local frame = if s.mode == "grab" and k < 1 then s.from:Lerp(target, k) else target
		if k >= 1 then
			s.mode = "drag"
		end
		local sway = math.sin(state.t * 9) * 12
		place(frame, {
			Head = Vector3.new(-20 + sway * 0.4, 0, 0),
			LeftUpperArm = Vector3.new(0, 0, -150 - sway),
			RightUpperArm = Vector3.new(0, 0, 150 + sway),
			LeftLowerArm = Vector3.new(20, 0, 0),
			RightLowerArm = Vector3.new(20, 0, 0),
			LeftUpperLeg = Vector3.new(0, 0, -25 + sway * 0.5),
			LeftLowerLeg = Vector3.new(-25, 0, 0),
		})
	end
end

local tracks: { [string]: AnimationTrack } = {}

-- Cette méthode permet d'enregistrer et charger les gestes de l'avatar (clips de Studio) lorsque la prise est
-- préparée.
local function loadTracks()
	local character = Players.LocalPlayer.Character :: Model
	local animator = (character:FindFirstChildOfClass("Humanoid") :: Humanoid):FindFirstChildOfClass(
			"Animator"
		) :: Animator
	tracks = {}
	for _, clip in CLIPS do
		local animation = Instance.new("Animation")
		animation.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(AnimationData.buildSequence(clip))
		tracks[clip.name] = animator:LoadAnimation(animation)
	end
end

-- Cette méthode permet de jouer un seul geste à la fois (fondu `fade`) lorsque la prise l'enchaîne.
local function play(name: string?, fade: number?, speed: number?)
	for key, track in tracks do
		if key ~= name and track.IsPlaying then
			track:Stop(fade or 0.08)
		end
	end
	if name then
		tracks[name]:Play(fade or 0.08, 1, speed or 1)
	end
end

-- Cette méthode permet de donner un coup au mannequin debout (impulsion d'inclinaison `force`, son) lorsque le poing
-- de l'avatar arrive.
local function hit(force: number, pitch: number?)
	state.spin += force
	sound("Thud", DUMMY_AT + Vector3.new(0, 3, 0), 1, pitch)
end

-- Cette méthode permet d'orienter l'avatar vers `point` (à plat) lorsque il doit faire face au mannequin.
local function faceTo(point: Vector3)
	local character = Players.LocalPlayer.Character :: Model
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat(point - root.Position))
end

-- Cette méthode permet de préparer la prise (mannequin debout, avatar au départ, gestes chargés) lorsque l'on
-- s'apprête à filmer.
function O.setup(): string
	O.clear()
	dummy = build()
	state.mode, state.tilt, state.spin, state.t = "stand", 0, 0, 0
	place(standFrame(0), {})
	loadTracks()
	local character = Players.LocalPlayer.Character :: Model
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root.CFrame = CFrame.lookAt(START, AVATAR_SPOT)
	if O.conn then
		O.conn:Disconnect()
	end
	O.conn = RunService.RenderStepped:Connect(step)
	return "prête"
end

-- Cette méthode permet de faire glousser l'avatar `seconds` secondes (sans toucher au mannequin tenu) lorsque la prise
-- de réaction sur la bande tourne ; les gestes sont rechargés si l'avatar a changé.
function O.chuckle(seconds: number)
	if not tracks.VidChuckle then
		loadTracks()
	end
	local track = tracks.VidChuckle
	track:Play(0.12)
	task.delay(seconds, function()
		track:Stop(0.2)
	end)
end

-- Cette méthode permet de retirer le mannequin et d'arrêter les gestes lorsque la séance se termine.
function O.clear()
	if O.conn then
		O.conn:Disconnect()
		O.conn = nil
	end
	if dummy then
		dummy:Destroy()
		dummy = nil
	end
	play(nil)
end

-- Cadrages de la prise (caméra en `from`, visée `at`), relatifs au mannequin
local CAM = {
	wide = { from = DUMMY_AT + Vector3.new(-7, 3.2, 13), at = DUMMY_AT + Vector3.new(3.5, 2.6, 0), fov = 50 },
	-- Coups vus de derrière le mannequin : poings et visage de l'avatar
	side = { from = DUMMY_AT + Vector3.new(-3.2, 3.6, 8.2), at = DUMMY_AT + Vector3.new(1.5, 2.9, 0), fov = 44 },
	-- Gros coup en contre-plongée, assez large pour voir le mannequin couché
	low = { from = DUMMY_AT + Vector3.new(-0.5, 1.6, 9.5), at = DUMMY_AT + Vector3.new(-1.2, 2.4, 0), fov = 58 },
}
local DRAG_OFFSET = Vector3.new(-7.5, 2.4, 8) -- caméra devant l'avatar, du côté du mannequin traîné
local DRAG_LOOK = Vector3.new(-1.5, -0.6, -2)

-- Cette méthode permet de poser un cadrage fixe de la table CAM lorsque la prise change de plan.
local function cut(name: string)
	local c = CAM[name]
	_G.FadCam.fixed(c.from, c.at, c.fov)
end

-- Cette méthode permet de suivre l'avatar de face pendant qu'il traîne le mannequin (caméra qui recule devant lui)
-- lorsque la prise arrive au traîné.
local function followDrag()
	local character = Players.LocalPlayer.Character :: Model
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local pos: Vector3? = nil
	_G.FadCam.shot = function(dt: number)
		local p = root.Position
		local target = p + DRAG_OFFSET
		pos = if pos then pos:Lerp(target, 1 - math.exp(-4 * dt)) else target
		return CFrame.lookAt(pos :: Vector3, p + DRAG_LOOK), 50
	end
end

-- Cette méthode permet de jouer toute la prise d'ouverture (repère, caméras, gestes, sons) lorsque l'enregistrement
-- tourne ; elle rend la main tout de suite, la prise se joue dans un fil à part.
function O.run(): string
	local character = Players.LocalPlayer.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	task.spawn(function()
		cut("wide")
		_G.FadCam.flash()
		task.wait(0.4)
		-- Arrivée
		humanoid.WalkSpeed = 12
		humanoid:MoveTo(AVATAR_SPOT)
		humanoid.MoveToFinished:Wait()
		faceTo(DUMMY_AT)
		play("VidGuard", 0.15)
		task.wait(0.35)
		cut("side")
		-- Deux petits coups, le mannequin tangue
		play("VidJabR")
		task.wait(0.09)
		hit(-2.2, 1.1)
		task.wait(0.35)
		play("VidJabL")
		task.wait(0.09)
		hit(-2.6, 0.95)
		task.wait(0.3)
		-- Il trouve ça drôle
		play("VidPoint", 0.12)
		task.wait(1.0)
		play("VidGuard", 0.1)
		task.wait(0.15)
		-- Rafale
		for i, side in { "R", "L", "R", "L" } do
			play("VidJab" .. side, 0.05, 1.3)
			task.wait(0.07)
			hit(-2 - i * 0.4, 1 + i * 0.05)
			task.wait(0.19)
		end
		-- Gros coup : le mannequin tombe à la renverse
		cut("low")
		play("VidHaymaker", 0.06)
		task.wait(0.42)
		sound("Whack", DUMMY_AT + Vector3.new(0, 3, 0), 1.2)
		sound("Bone", DUMMY_AT + Vector3.new(0, 3, 0), 0.9)
		state.mode = "fall"
		state.spin = 4.5
		task.wait(0.75)
		sound("Thud", DUMMY_AT, 1.2, 0.8)
		play("VidLaugh", 0.12)
		task.wait(1.1)
		-- Il l'attrape par la cheville et l'emmène vers la bande
		play("VidReach", 0.1)
		task.wait(0.35)
		state.from = standFrame(state.tilt)
		state.grabbed = state.t
		state.mode = "grab"
		task.wait(0.3)
		followDrag()
		play("VidDrag", 0.2)
		humanoid.WalkSpeed = 8
		humanoid:MoveTo(DRAG_TO)
		task.wait(3.2)
		_G.FadCam.flash()
		print("[opening] fin de prise")
	end)
	return "prise lancée"
end

return O
