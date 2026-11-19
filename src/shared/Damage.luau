-- Dégâts du mannequin : os cassés par choc et teinte des membres.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Damage = {}

-- Teinte d'un membre selon son nombre d'os cassés (1, 2, 3 et plus)
Damage.TINTS = {
	Color3.fromRGB(255, 140, 30),
	Color3.fromRGB(225, 40, 30),
	Color3.fromRGB(110, 10, 15),
}

-- Cette méthode permet de compter les os cassés par un choc lorsque la vitesse d'un membre varie de `dv` en une frame.
function Damage.bonesForImpact(dv: number): number
	if dv >= GameConfig.DOUBLE_BONE_DV then
		return 2
	elseif dv >= GameConfig.BONE_IMPACT_DV then
		return 1
	end
	return 0
end

-- Cette méthode permet de donner la couleur d'un membre lorsque `bones` de ses os sont cassés (jaune → rouge sombre).
function Damage.tint(baseColor: Color3, bones: number): Color3
	if bones <= 0 then
		return baseColor
	end
	return Damage.TINTS[math.min(bones, #Damage.TINTS)]
end

return Damage
