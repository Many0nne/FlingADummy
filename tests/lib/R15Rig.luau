-- Cinématique directe d'un avatar R15 type (échelle 1, articulations relevées sur un avatar à AnimationConstraint
-- dans Studio) : position des pièces dans le repère de HumanoidRootPart pour une keyframe de Shared.AnimationData.
-- Pièce = parent * C0 * Transform * C1⁻¹, Transform = CFrame de la pose (comme Motor6D et AnimationConstraint).
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local R15Rig = {}

-- Articulation de chaque pièce : parent, C0 (dans le parent), C1 (dans la pièce)
local JOINTS = {
	LowerTorso = { "HumanoidRootPart", Vector3.new(0, -1.036, 0), Vector3.new(0, -0.315, 0.1) },
	UpperTorso = { "LowerTorso", Vector3.new(0, 0.085, 0.1), Vector3.new(0, -0.744, 0.044) },
	Head = { "UpperTorso", Vector3.new(0, 0.856, 0.044), Vector3.new(0, -0.586, 0.006) },
	RightUpperArm = { "UpperTorso", Vector3.new(0.911, 0.474, 0.044), Vector3.new(-0.282, 0.294, -0.019) },
	RightLowerArm = { "RightUpperArm", Vector3.new(0.037, -0.305, 0.123), Vector3.new(-0.08, 0.266, 0.04) },
	RightHand = { "RightLowerArm", Vector3.new(0.127, -0.263, 0.04), Vector3.new(0.054, 0.432, 0.14) },
	LeftUpperArm = { "UpperTorso", Vector3.new(-0.911, 0.474, 0.044), Vector3.new(0.281, 0.294, -0.019) },
	LeftLowerArm = { "LeftUpperArm", Vector3.new(-0.038, -0.305, 0.123), Vector3.new(0.079, 0.266, 0.04) },
	LeftHand = { "LeftLowerArm", Vector3.new(-0.127, -0.263, 0.04), Vector3.new(-0.055, 0.432, 0.14) },
}

-- Cette méthode permet de calculer la CFrame d'une pièce (repère de HumanoidRootPart) lorsqu'un test vérifie une
-- pose ; `toCFrame` convertit une pose de Shared.AnimationData, `poses` donne les poses de la keyframe.
function R15Rig.partFrame(name: string, poses, toCFrame): any
	if name == "HumanoidRootPart" then
		return CFrame.new()
	end
	local joint = JOINTS[name]
	assert(joint, "articulation inconnue : " .. name)
	local parent = R15Rig.partFrame(joint[1], poses, toCFrame)
	local pose = poses[name]
	local transform = if pose then toCFrame(pose) else CFrame.new()
	return parent * CFrame.new(joint[2]) * transform * CFrame.new(joint[3]):Inverse()
end

-- Cette méthode permet de donner la position de la main droite (repère de HumanoidRootPart : X droite, Y haut,
-- -Z devant) lorsqu'un test vérifie le geste de lancer.
function R15Rig.rightHand(poses, toCFrame): any
	return R15Rig.partFrame("RightHand", poses, toCFrame).Position
end

return R15Rig
