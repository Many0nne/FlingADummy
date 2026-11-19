-- Fabrique du mannequin physique : 10 pièces articulées par des rotules à butées, sans Humanoid (gabarit dans
-- Shared.DummyShape).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DummyShape = require(ReplicatedStorage.Shared.DummyShape)
local CollisionGroups = require(script.Parent.CollisionGroups)

-- Mannequin lourd (densité, frottement, rebond) : il garde son élan à travers les obstacles
local PHYSICS = PhysicalProperties.new(1.5, 0.3, 0.3)
local TWIST_LIMIT = 30

local DummyFactory = {}

-- Cette méthode permet de créer un attachement au point `world` (repère du mannequin) d'une pièce, axe X sur `axis`,
-- lorsque l'on articule deux pièces.
local function attach(partInstance: BasePart, world: Vector3, axis: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	local up = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	attachment.CFrame = CFrame.new(partInstance.Position):ToObjectSpace(CFrame.fromMatrix(world, axis, up))
	attachment.Parent = partInstance
	return attachment
end

-- Cette méthode permet de construire un mannequin neuf, debout, centre du torse à l'origine, lorsqu'un lancer part ;
-- l'appelant le place (PivotTo) puis le parente au monde.
function DummyFactory.build(): Model
	local model = Instance.new("Model")
	model.Name = "Dummy"
	local parts: { [string]: BasePart } = {}
	for _, piece in DummyShape.PIECES do
		local p = Instance.new("Part")
		p.Name = piece.name
		p.Size = piece.size
		p.Position = piece.position
		p.Color = piece.color
		p.Shape = piece.shape or Enum.PartType.Block
		p.Material = Enum.Material.SmoothPlastic
		p.CustomPhysicalProperties = PHYSICS
		p:SetAttribute("BaseColor", piece.color)
		p:SetAttribute("Bones", 0)
		p.Parent = model
		parts[piece.name] = p
	end
	DummyShape.addTarget(parts.Torso, Enum.NormalId.Front)
	DummyShape.addTarget(parts.Torso, Enum.NormalId.Back)
	for _, joint in DummyShape.JOINTS do
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
