-- Fabrique du mannequin de crash-test : 10 pièces articulées par des rotules à butées, sans Humanoid.
-- Gabarit en studs, debout, centre du torse à l'origine (cf. docs/prototype-v0.md).
local CollisionGroups = require(script.Parent.CollisionGroups)

local YELLOW = Color3.fromRGB(255, 205, 40)
local DARK = Color3.fromRGB(60, 62, 70)

local ARM = Vector3.new(0.8, 1.2, 0.8)
local LEG = Vector3.new(0.95, 1.3, 0.95)
-- Mannequin lourd (densité, frottement, rebond) : il garde son élan à travers les obstacles
local PHYSICS = PhysicalProperties.new(1.5, 0.3, 0.3)

-- name, taille, position du centre, couleur, forme
local PIECES = {
	{ "Torso", Vector3.new(2, 2.4, 1.1), Vector3.new(0, 0, 0), YELLOW },
	{ "Head", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 2.1, 0), YELLOW, Enum.PartType.Ball },
	{ "LeftUpperArm", ARM, Vector3.new(-1.45, 0.6, 0), YELLOW },
	{ "LeftLowerArm", ARM, Vector3.new(-1.45, -0.62, 0), DARK },
	{ "RightUpperArm", ARM, Vector3.new(1.45, 0.6, 0), YELLOW },
	{ "RightLowerArm", ARM, Vector3.new(1.45, -0.62, 0), DARK },
	{ "LeftUpperLeg", LEG, Vector3.new(-0.5, -1.85, 0), YELLOW },
	{ "LeftLowerLeg", LEG, Vector3.new(-0.5, -3.17, 0), DARK },
	{ "RightUpperLeg", LEG, Vector3.new(0.5, -1.85, 0), YELLOW },
	{ "RightLowerLeg", LEG, Vector3.new(0.5, -3.17, 0), DARK },
}

-- parent, enfant, position de la rotule, demi-angle du cône (degrés), sens du membre (axe des attachements)
local JOINTS = {
	{ "Torso", "Head", Vector3.new(0, 1.28, 0), 40, Vector3.yAxis },
	{ "Torso", "LeftUpperArm", Vector3.new(-1.45, 1.05, 0), 110, -Vector3.yAxis },
	{ "LeftUpperArm", "LeftLowerArm", Vector3.new(-1.45, -0.01, 0), 100, -Vector3.yAxis },
	{ "Torso", "RightUpperArm", Vector3.new(1.45, 1.05, 0), 110, -Vector3.yAxis },
	{ "RightUpperArm", "RightLowerArm", Vector3.new(1.45, -0.01, 0), 100, -Vector3.yAxis },
	{ "Torso", "LeftUpperLeg", Vector3.new(-0.5, -1.2, 0), 80, -Vector3.yAxis },
	{ "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.5, -2.51, 0), 100, -Vector3.yAxis },
	{ "Torso", "RightUpperLeg", Vector3.new(0.5, -1.2, 0), 80, -Vector3.yAxis },
	{ "RightUpperLeg", "RightLowerLeg", Vector3.new(0.5, -2.51, 0), 100, -Vector3.yAxis },
}

local TWIST_LIMIT = 30

local DummyFactory = {}

DummyFactory.LIMB_NAMES = table.create(#PIECES)
for i, piece in PIECES do
	DummyFactory.LIMB_NAMES[i] = piece[1]
end

-- Cette méthode permet de créer un attachement au point `world` (repère du mannequin) d'une pièce, axe X sur `axis`,
-- lorsque l'on articule deux pièces.
local function attach(partInstance: BasePart, world: Vector3, axis: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	local up = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local frame = CFrame.fromMatrix(world, axis, up)
	attachment.CFrame = CFrame.new(partInstance.Position):ToObjectSpace(frame)
	attachment.Parent = partInstance
	return attachment
end

-- Cette méthode permet de construire un mannequin neuf, debout, centre du torse à l'origine, lorsqu'un lancer part ;
-- l'appelant le place (PivotTo) puis le parente au monde.
function DummyFactory.build(): Model
	local model = Instance.new("Model")
	model.Name = "Dummy"
	local parts: { [string]: BasePart } = {}
	for _, piece in PIECES do
		local p = Instance.new("Part")
		p.Name = piece[1]
		p.Size = piece[2]
		p.Position = piece[3]
		p.Color = piece[4]
		p.Shape = piece[5] or Enum.PartType.Block
		p.Material = Enum.Material.SmoothPlastic
		p.CustomPhysicalProperties = PHYSICS
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p:SetAttribute("BaseColor", piece[4])
		p.Parent = model
		parts[piece[1]] = p
	end
	for _, joint in JOINTS do
		local parentPart, childPart = parts[joint[1]], parts[joint[2]]
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = joint[2] .. "Joint"
		socket.Attachment0 = attach(parentPart, joint[3], joint[5])
		socket.Attachment1 = attach(childPart, joint[3], joint[5])
		socket.LimitsEnabled = true
		socket.UpperAngle = joint[4]
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -TWIST_LIMIT
		socket.TwistUpperAngle = TWIST_LIMIT
		socket.Parent = childPart
	end
	model.PrimaryPart = parts.Torso
	CollisionGroups.assign(model, CollisionGroups.DUMMY)
	return model
end

return DummyFactory
