-- Économie : vitesse de lancer, multiplicateur de valeur, prix des améliorations et calcul des gains d'un lancer.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Economy = {}

export type UpgradeKind = "Power" | "Value"

export type Stats = {
	distance: number,
	bones: number,
	smashed: number,
	perfect: boolean,
}

export type Payout = {
	total: number,
	distance: number,
	bones: number,
	smashed: number,
	distanceMoney: number,
	bonesMoney: number,
	smashMoney: number,
	multiplier: number,
	perfect: boolean,
}

-- Cette méthode permet de calculer la vitesse de sortie du canon (studs/s) lorsque la jauge est pleine.
function Economy.launchSpeed(powerLevel: number): number
	return GameConfig.BASE_LAUNCH_SPEED * GameConfig.POWER_GROWTH ^ (powerLevel - 1)
end

-- Cette méthode permet de calculer le multiplicateur de gains lorsque le mannequin est au niveau de valeur donné.
function Economy.valueMultiplier(valueLevel: number): number
	return 1 + GameConfig.VALUE_STEP * (valueLevel - 1)
end

-- Cette méthode permet de donner le niveau maximal d'une amélioration lorsque l'interface ou le serveur le vérifie.
function Economy.maxLevel(kind: UpgradeKind): number
	return if kind == "Power" then GameConfig.POWER_MAX_LEVEL else GameConfig.VALUE_MAX_LEVEL
end

-- Cette méthode permet de donner le prix pour passer du niveau `level` au suivant lorsque l'amélioration n'est pas
-- au maximum ; renvoie nil au niveau maximal.
function Economy.upgradeCost(kind: UpgradeKind, level: number): number?
	if level >= Economy.maxLevel(kind) then
		return nil
	end
	local base, growth
	if kind == "Power" then
		base, growth = GameConfig.POWER_BASE_COST, GameConfig.POWER_COST_GROWTH
	else
		base, growth = GameConfig.VALUE_BASE_COST, GameConfig.VALUE_COST_GROWTH
	end
	return math.floor(base * growth ^ (level - 1) + 0.5)
end

-- Cette méthode permet de calculer les gains d'un lancer (total arrondi et détail) lorsque le mannequin s'est arrêté.
function Economy.payout(stats: Stats, valueLevel: number): Payout
	local distance = math.max(0, math.floor(stats.distance))
	local distanceMoney = distance * GameConfig.MONEY_PER_METER
	local bonesMoney = stats.bones * GameConfig.MONEY_PER_BONE
	local smashMoney = stats.smashed * GameConfig.MONEY_PER_SMASH
	local multiplier = Economy.valueMultiplier(valueLevel) * (if stats.perfect then GameConfig.PERFECT_BONUS else 1)
	return {
		total = math.floor((distanceMoney + bonesMoney + smashMoney) * multiplier + 0.5),
		distance = distance,
		bones = stats.bones,
		smashed = stats.smashed,
		distanceMoney = distanceMoney,
		bonesMoney = bonesMoney,
		smashMoney = smashMoney,
		multiplier = multiplier,
		perfect = stats.perfect,
	}
end

return Economy
