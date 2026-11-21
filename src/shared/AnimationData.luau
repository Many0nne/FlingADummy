-- Animations R15 de l'avatar (source) : mannequin tenu, entraînement, lancer. Chaque clip est une liste de keyframes
-- dont les poses donnent la rotation (degrés, convention CFrame.Angles) et le décalage éventuel (studs) appliqués à la
-- jointure qui porte la pièce nommée (LowerTorso = Root, UpperTorso = Waist, RightUpperArm = RightShoulder…).
-- `tools/build-anims.luau` en fait des KeyframeSequence (.rbxm) publiées ; les ids sont dans Shared.Assets.
-- Repère du personnage : X à droite, Y en haut, -Z devant. Bras : +X lève le bras devant, +Z l'écarte (bras droit).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

export type JointPose = { number } -- { rx, ry, rz } en degrés, puis { px, py, pz } en studs (optionnel)
export type Keyframe = {
	t: number,
	ease: string?, -- PoseEasingStyle vers la keyframe suivante (Linear, CubicV2, Elastic, Bounce, Constant)
	dir: string?, -- PoseEasingDirection (In, Out, InOut)
	poses: { [string]: JointPose },
}
export type Clip = {
	name: string,
	length: number,
	loop: boolean,
	priority: string, -- AnimationPriority
	markers: { [string]: number },
	keyframes: { Keyframe },
}

local AnimationData = {}

-- Mannequin posé sur les mains (Client.CharacterPoser) : demi-épaisseur de la main sous le mannequin couché, et hauteur
-- du centre du mannequin au-dessus de la paume par unité d'échelle (studs)
AnimationData.PALM_GAP = 0.3
AnimationData.LIFT_OFFSET = 0.55

-- Parent de chaque pièce dans la hiérarchie des poses R15
AnimationData.PARENT = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
}

-- Mannequin tenu : bras droit tendu au-dessus de la tête, paume à plat sous le mannequin couché ; bras gauche écarté
-- pour l'équilibre, buste un peu cambré. Respiration lente pour que la pose vive. Les jambes restent libres (marche).
local HOLD_A = {
	UpperTorso = { 6, 0, 0 },
	Head = { 8, 0, 0 },
	RightUpperArm = { 172, 0, 12 },
	RightLowerArm = { 14, 0, 0 },
	RightHand = { 0, 0, 0 },
	LeftUpperArm = { 15, 0, -32 },
	LeftLowerArm = { 25, 0, 0 },
	LeftHand = { 0, 0, 0 },
}
local HOLD_B = {
	UpperTorso = { 9, 0, 0 },
	Head = { 10, 0, 0 },
	RightUpperArm = { 168, 0, 14 },
	RightLowerArm = { 20, 0, 0 },
	RightHand = { 0, 0, 0 },
	LeftUpperArm = { 12, 0, -36 },
	LeftLowerArm = { 30, 0, 0 },
	LeftHand = { 0, 0, 0 },
}

AnimationData.HOLD = {
	name = "Hold",
	length = 1.6,
	loop = true,
	priority = "Action",
	markers = {},
	keyframes = {
		{ t = 0, ease = "CubicV2", dir = "InOut", poses = HOLD_A },
		{ t = 0.8, ease = "CubicV2", dir = "InOut", poses = HOLD_B },
		{ t = 1.6, ease = "CubicV2", dir = "InOut", poses = HOLD_A },
	},
} :: Clip

-- Entraînement (une répétition, développé) : le mannequin d'entraînement couché en travers des deux mains reste
-- au-dessus de la tête ; en bas, coudes pliés devant, mains au ras du haut de la tête et genoux fléchis ; au sommet
-- (mi-clip), bras tendus et jambes droites. Les mains ne descendent pas plus bas : le mannequin traverserait la tête.
local TRAIN_LOW = {
	LowerTorso = { 0, 0, 0, 0, -0.5, 0 },
	UpperTorso = { 4, 0, 0 },
	Head = { -2, 0, 0 },
	RightUpperArm = { 152, 0, 4 },
	RightLowerArm = { 20, 0, 0 },
	RightHand = { 0, 0, 0 },
	LeftUpperArm = { 152, 0, -4 },
	LeftLowerArm = { 20, 0, 0 },
	LeftHand = { 0, 0, 0 },
	RightUpperLeg = { 50, 0, 6 },
	RightLowerLeg = { -90, 0, 0 },
	RightFoot = { 40, 0, 0 },
	LeftUpperLeg = { 50, 0, -6 },
	LeftLowerLeg = { -90, 0, 0 },
	LeftFoot = { 40, 0, 0 },
}
local TRAIN_HIGH = {
	LowerTorso = { 0, 0, 0, 0, 0.05, 0 },
	UpperTorso = { 2, 0, 0 },
	Head = { 8, 0, 0 },
	RightUpperArm = { 178, 0, 4 },
	RightLowerArm = { 4, 0, 0 },
	RightHand = { 0, 0, 0 },
	LeftUpperArm = { 178, 0, -4 },
	LeftLowerArm = { 4, 0, 0 },
	LeftHand = { 0, 0, 0 },
	RightUpperLeg = { 2, 0, 6 },
	RightLowerLeg = { -3, 0, 0 },
	RightFoot = { 1, 0, 0 },
	LeftUpperLeg = { 2, 0, -6 },
	LeftLowerLeg = { -3, 0, 0 },
	LeftFoot = { 1, 0, 0 },
}

AnimationData.TRAIN = {
	name = "Train",
	length = 1,
	loop = true,
	priority = "Action",
	markers = { Top = 0.5 },
	keyframes = {
		{ t = 0, ease = "CubicV2", dir = "InOut", poses = TRAIN_LOW },
		{ t = 0.5, ease = "CubicV2", dir = "InOut", poses = TRAIN_HIGH },
		{ t = 1, ease = "CubicV2", dir = "InOut", poses = TRAIN_LOW },
	},
} :: Clip

-- Mannequin de collection porté (outil du Backpack, #54) : tenu debout devant la poitrine, les deux mains sur ses
-- flancs, avant-bras pliés devant ; buste un peu en arrière pour le poids, respiration lente. Haut du corps seulement :
-- les jambes gardent la marche et le saut.
AnimationData.CARRY_SCALE = 0.42 -- échelle du mannequin porté, taille normale (× échelle de sa taille)
AnimationData.CARRY_LIFT = 0.2 -- hauteur du centre du torse au-dessus du milieu des mains, par unité d'échelle
AnimationData.CARRY_GRIP = 0.25 -- les mains prennent le mannequin de flanc, à tant de studs de son dos
local DUMMY_HALF_DEPTH = 0.55 -- demi-épaisseur du torse du mannequin, échelle 1 (Shared.DummyShape)
local DUMMY_FEET = 3.82 -- du centre du torse au bas des pieds, échelle 1

local CARRY_A = {
	UpperTorso = { 5, 0, 0 },
	Head = { -4, 0, 0 },
	RightUpperArm = { 30, 0, -50 },
	RightLowerArm = { 80, 0, 0 },
	RightHand = { 0, 0, 0 },
	LeftUpperArm = { 30, 0, 50 },
	LeftLowerArm = { 80, 0, 0 },
	LeftHand = { 0, 0, 0 },
}
local CARRY_B = {
	UpperTorso = { 7, 0, 0 },
	Head = { -3, 0, 0 },
	RightUpperArm = { 27, 0, -50 },
	RightLowerArm = { 83, 0, 0 },
	RightHand = { 0, 0, 0 },
	LeftUpperArm = { 27, 0, 50 },
	LeftLowerArm = { 83, 0, 0 },
	LeftHand = { 0, 0, 0 },
}

AnimationData.CARRY = {
	name = "Carry",
	length = 2,
	loop = true,
	priority = "Action",
	markers = {},
	keyframes = {
		{ t = 0, ease = "CubicV2", dir = "InOut", poses = CARRY_A },
		{ t = 1, ease = "CubicV2", dir = "InOut", poses = CARRY_B },
		{ t = 2, ease = "CubicV2", dir = "InOut", poses = CARRY_A },
	},
} :: Clip

-- Lancer : depuis la pose tenue, élan (jambe avant levée, buste tourné et cambré, bras droit armé derrière la tête),
-- puis fouetté (bassin et buste pivotent, bras droit projette vers l'avant et le haut), lâcher au marqueur Release,
-- accompagnement (bras qui retombe en travers), retour.
local RELEASE = GameConfig.THROW_RELEASE_TIME

AnimationData.THROW = {
	name = "Throw",
	length = 1.35,
	loop = false,
	priority = "Action4",
	markers = { Release = RELEASE },
	keyframes = {
		{
			t = 0,
			ease = "CubicV2",
			dir = "InOut",
			poses = {
				LowerTorso = { 0, 0, 0, 0, 0, 0 },
				UpperTorso = { 6, 0, 0 },
				Head = { 8, 0, 0 },
				RightUpperArm = { 172, 0, 12 },
				RightLowerArm = { 14, 0, 0 },
				RightHand = { 0, 0, 0 },
				LeftUpperArm = { 15, 0, -32 },
				LeftLowerArm = { 25, 0, 0 },
				LeftHand = { 0, 0, 0 },
				RightUpperLeg = { 0, 0, 0 },
				RightLowerLeg = { 0, 0, 0 },
				RightFoot = { 0, 0, 0 },
				LeftUpperLeg = { 0, 0, 0 },
				LeftLowerLeg = { 0, 0, 0 },
				LeftFoot = { 0, 0, 0 },
			},
		},
		-- Élan : poids sur la jambe arrière (droite), genou avant levé, épaule droite reculée, main au-dessus et derrière
		-- la tête (les bras R15 sont courts : coude peu fléchi, sinon la main retombe dans le dos)
		{
			t = 0.42,
			ease = "CubicV2",
			dir = "InOut",
			poses = {
				LowerTorso = { 0, -25, 0, 0.1, -0.15, 0.25 },
				UpperTorso = { 6, -30, 4 },
				Head = { -6, 40, 0 },
				RightUpperArm = { 165, 0, 20 },
				RightLowerArm = { 30, 0, 0 },
				RightHand = { 10, 0, 0 },
				LeftUpperArm = { 82, 18, -12 },
				LeftLowerArm = { 12, 0, 0 },
				LeftHand = { 0, 0, 0 },
				RightUpperLeg = { -8, 24, 6 },
				RightLowerLeg = { -28, 0, 0 },
				RightFoot = { 18, 0, 0 },
				LeftUpperLeg = { 62, 18, -6 },
				LeftLowerLeg = { -78, 0, 0 },
				LeftFoot = { 10, 0, 0 },
			},
		},
		-- Tension maximale juste avant le fouetté
		{
			t = 0.56,
			ease = "CubicV2",
			dir = "In",
			poses = {
				LowerTorso = { 0, -28, 0, 0.12, -0.2, 0.3 },
				UpperTorso = { 6, -34, 5 },
				Head = { -10, 44, 0 },
				RightUpperArm = { 170, 0, 22 },
				RightLowerArm = { 32, 0, 0 },
				RightHand = { 14, 0, 0 },
				LeftUpperArm = { 88, 22, -10 },
				LeftLowerArm = { 8, 0, 0 },
				LeftHand = { 0, 0, 0 },
				RightUpperLeg = { -10, 28, 6 },
				RightLowerLeg = { -32, 0, 0 },
				RightFoot = { 20, 0, 0 },
				LeftUpperLeg = { 58, 20, -6 },
				LeftLowerLeg = { -70, 0, 0 },
				LeftFoot = { 8, 0, 0 },
			},
		},
		-- Fouetté : bras droit devant et en haut (lâcher), jambe avant plantée, bassin ouvert vers la piste
		{
			t = RELEASE + 0.04,
			ease = "CubicV2",
			dir = "Out",
			poses = {
				LowerTorso = { 0, 18, 0, -0.05, -0.45, -0.55 },
				UpperTorso = { -20, 30, -4 },
				Head = { -14, -26, 0 },
				RightUpperArm = { 168, 0, 10 },
				RightLowerArm = { 6, 0, 0 },
				RightHand = { -12, 0, 0 },
				LeftUpperArm = { -28, 0, -38 },
				LeftLowerArm = { 30, 0, 0 },
				LeftHand = { 0, 0, 0 },
				RightUpperLeg = { -34, -10, 6 },
				RightLowerLeg = { -24, 0, 0 },
				RightFoot = { 30, 0, 0 },
				LeftUpperLeg = { 38, -12, -4 },
				LeftLowerLeg = { -26, 0, 0 },
				LeftFoot = { -8, 0, 0 },
			},
		},
		-- Accompagnement : bras droit qui retombe en travers du corps, buste penché
		{
			t = 0.98,
			ease = "CubicV2",
			dir = "InOut",
			poses = {
				LowerTorso = { 0, 24, 0, -0.1, -0.4, -0.6 },
				UpperTorso = { -30, 38, -6 },
				Head = { 4, -30, 0 },
				RightUpperArm = { 46, -20, -28 },
				RightLowerArm = { 30, 0, 0 },
				RightHand = { 0, 0, 0 },
				LeftUpperArm = { -34, 0, -30 },
				LeftLowerArm = { 34, 0, 0 },
				LeftHand = { 0, 0, 0 },
				RightUpperLeg = { -20, -12, 6 },
				RightLowerLeg = { -40, 0, 0 },
				RightFoot = { 30, 0, 0 },
				LeftUpperLeg = { 34, -14, -4 },
				LeftLowerLeg = { -22, 0, 0 },
				LeftFoot = { -10, 0, 0 },
			},
		},
		-- Retour vers la pose de repos (l'animation par défaut reprend ensuite)
		{
			t = 1.35,
			ease = "Linear",
			dir = "In",
			poses = {
				LowerTorso = { 0, 6, 0, 0, -0.1, -0.2 },
				UpperTorso = { -6, 8, 0 },
				Head = { 0, -6, 0 },
				RightUpperArm = { 10, 0, 6 },
				RightLowerArm = { 10, 0, 0 },
				RightHand = { 0, 0, 0 },
				LeftUpperArm = { -6, 0, -8 },
				LeftLowerArm = { 10, 0, 0 },
				LeftHand = { 0, 0, 0 },
				RightUpperLeg = { -6, 0, 0 },
				RightLowerLeg = { -8, 0, 0 },
				RightFoot = { 6, 0, 0 },
				LeftUpperLeg = { 8, 0, 0 },
				LeftLowerLeg = { -8, 0, 0 },
				LeftFoot = { 0, 0, 0 },
			},
		},
	},
} :: Clip

AnimationData.CLIPS = { AnimationData.HOLD, AnimationData.TRAIN, AnimationData.THROW, AnimationData.CARRY }

-- Cette méthode permet de calculer où poser le mannequin porté (debout, tourné comme le personnage, centre du torse
-- un peu au-dessus du milieu des mains, dos contre les mains) lorsque le personnage le porte ; `ground` (hauteur du sol
-- sous le personnage) relève les grands mannequins pour que leurs pieds ne s'y enfoncent pas.
function AnimationData.carryFrame(hands: Vector3, forward: Vector3, scale: number, ground: number?): CFrame
	local flat = Vector3.new(forward.X, 0, forward.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local center = hands
		+ Vector3.new(0, AnimationData.CARRY_LIFT * scale, 0)
		+ flat * (DUMMY_HALF_DEPTH * scale - AnimationData.CARRY_GRIP)
	if ground then
		local lowest = ground + DUMMY_FEET * scale + 0.1
		if center.Y < lowest then
			center = Vector3.new(center.X, lowest, center.Z)
		end
	end
	local up = Vector3.new(0, 1, 0)
	return CFrame.fromMatrix(center, flat:Cross(up), up) -- face avant (-Z) vers `flat`
end

-- Cette méthode permet de construire la CFrame d'une pose (rotation en degrés, décalage en studs) lorsque l'on
-- génère une KeyframeSequence.
function AnimationData.toCFrame(pose: JointPose): CFrame
	local offset = CFrame.new(pose[4] or 0, pose[5] or 0, pose[6] or 0)
	return offset * CFrame.Angles(math.rad(pose[1]), math.rad(pose[2]), math.rad(pose[3]))
end

-- Cette méthode permet de donner les pièces animées par un clip (union des poses de ses keyframes) lorsque l'on
-- construit la hiérarchie des poses.
function AnimationData.animatedParts(clip: Clip): { [string]: boolean }
	local parts = {}
	for _, keyframe in clip.keyframes do
		for name in keyframe.poses do
			parts[name] = true
		end
	end
	return parts
end

-- Cette méthode permet de compléter les poses d'un clip lorsqu'une keyframe n'en précise qu'une partie : une pièce
-- absente garde la valeur de la keyframe précédente (zéro à la première).
function AnimationData.filledKeyframes(clip: Clip): { Keyframe }
	local parts = AnimationData.animatedParts(clip)
	local last: { [string]: JointPose } = {}
	local out = {}
	for _, keyframe in clip.keyframes do
		local poses = {}
		for name in parts do
			poses[name] = keyframe.poses[name] or last[name] or { 0, 0, 0 }
			last[name] = poses[name]
		end
		table.insert(out, { t = keyframe.t, ease = keyframe.ease, dir = keyframe.dir, poses = poses })
	end
	return out
end

-- Cette méthode permet de créer (ou retrouver) la pose d'une pièce et la chaîne de ses parents jusqu'à
-- HumanoidRootPart lorsque l'on remplit une keyframe ; les parents non animés gardent un poids nul.
local function poseFor(keyframe: Instance, cache: { [string]: Instance }, name: string): Instance
	local existing = cache[name]
	if existing then
		return existing
	end
	local pose = Instance.new("Pose")
	pose.Name = name
	pose.Weight = 0
	local parentName = AnimationData.PARENT[name]
	pose.Parent = if parentName then poseFor(keyframe, cache, parentName) else keyframe
	cache[name] = pose
	return pose
end

-- Cette méthode permet de construire la KeyframeSequence d'un clip lorsque l'outil de build l'exporte (Lune) ou
-- que Studio joue un clip pas encore publié (KeyframeSequenceProvider) ; les marqueurs sont portés par une keyframe
-- sans pose à l'instant voulu.
function AnimationData.buildSequence(clip: Clip): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = clip.name
	sequence.Loop = clip.loop
	sequence.Priority = (Enum.AnimationPriority :: any)[clip.priority]
	for _, data in AnimationData.filledKeyframes(clip) do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = data.t
		local cache = {}
		for name, values in data.poses do
			local pose: any = poseFor(keyframe, cache, name)
			pose.Weight = 1
			pose.CFrame = AnimationData.toCFrame(values)
			pose.EasingStyle = (Enum.PoseEasingStyle :: any)[data.ease or "Linear"]
			pose.EasingDirection = (Enum.PoseEasingDirection :: any)[data.dir or "In"]
		end
		keyframe.Parent = sequence
	end
	for name, time in clip.markers do
		local holder = Instance.new("Keyframe")
		holder.Name = "Marker_" .. name
		holder.Time = time
		local marker = Instance.new("KeyframeMarker")
		marker.Name = name
		marker.Value = ""
		marker.Parent = holder
		holder.Parent = sequence
	end
	return sequence
end

return AnimationData
