-- Fabrique du mannequin physique : 10 pièces (maillées, collision en boîte) articulées par des rotules à butées, sans
-- Humanoid (gabarit dans Shared.DummyShape).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DummyShape = require(ReplicatedStorage.Shared.DummyShape)
local ThrowDummies = require(ReplicatedStorage.Shared.ThrowDummies)
local CollisionGroups = require(script.Parent.CollisionGroups)

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
-- `variant` le décline (couleur, matériau, accessoires), `physics` règle ses pièces (mannequin à lancer équipé,
-- Shared.ThrowDummies ; le Crash Dummy par défaut). L'appelant le place (PivotTo) puis le parente au monde.
function DummyFactory.build(variant: DummyShape.Variant?, physics: ThrowDummies.Physics?): Model
	local model = Instance.new("Model")
	model.Name = "Dummy"
	local parts = DummyShape.buildPieces(model, 1, variant)
	local spec = physics or ThrowDummies.LIST[1].physics
	local properties =
		PhysicalProperties.new(spec.density, spec.friction, spec.elasticity, spec.frictionWeight, spec.elasticityWeight)
	for _, p in parts do
		p.CustomPhysicalProperties = properties
		p:SetAttribute("BaseColor", p.Color)
		p:SetAttribute("Bones", 0)
	end
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
	DummyShape.addAccessories(model, parts, 1, variant)
	model.PrimaryPart = parts.Torso
	CollisionGroups.assign(model, CollisionGroups.DUMMY)
	return model
end

return DummyFactory
