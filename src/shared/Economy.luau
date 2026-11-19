-- Économie : vitesse de lancer selon la Throw Power, valeur du mannequin, calcul des gains d'un lancer.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Economy = {}

export type Stats = {
	distance: number,
	bones: number,
	smashed: number,
	perfect: boolean,
	zoneMultiplier: number,
}

export type Payout = {
	total: number,
	distance: number,
	bones: number,
	smashed: number,
	distanceMoney: number,
	bonesMoney: number,
	smashMoney: number,
	zoneMultiplier: number,
	valueMultiplier: number,
	perfect: boolean,
}

-- Cette méthode permet de calculer la vitesse de lancer (studs/s, jauge pleine) lorsque le joueur a `power` de Throw
-- Power ; courbe logarithmique : la puissance explose, la distance monte régulièrement.
function Economy.launchSpeed(power: number): number
	local ratio = math.max(power, GameConfig.START_POWER) / GameConfig.START_POWER
	return GameConfig.SPEED_BASE + GameConfig.SPEED_PER_LOG * math.log(ratio)
end

-- Cette méthode permet de calculer le multiplicateur de gains lorsque le mannequin est au niveau de valeur donné.
function Economy.valueMultiplier(valueLevel: number): number
	return 1 + GameConfig.VALUE_STEP * (valueLevel - 1)
end

-- Cette méthode permet de donner le prix du niveau de valeur suivant lorsque le joueur est au niveau `level` ;
-- nil au niveau maximal.
function Economy.valueCost(level: number): number?
	if level >= GameConfig.VALUE_MAX_LEVEL then
		return nil
	end
	return math.floor(GameConfig.VALUE_BASE_COST * GameConfig.VALUE_COST_GROWTH ^ (level - 1) + 0.5)
end

-- Cette méthode permet de calculer les gains d'un lancer (total arrondi et détail) lorsque le mannequin s'est arrêté.
function Economy.payout(stats: Stats, valueLevel: number): Payout
	local distance = math.max(0, math.floor(stats.distance))
	local distanceMoney = distance * GameConfig.MONEY_PER_METER
	local bonesMoney = stats.bones * GameConfig.MONEY_PER_BONE
	local smashMoney = stats.smashed * GameConfig.MONEY_PER_SMASH
	local valueMultiplier = Economy.valueMultiplier(valueLevel)
	local multiplier = stats.zoneMultiplier * valueMultiplier * (if stats.perfect then GameConfig.PERFECT_BONUS else 1)
	return {
		total = math.floor((distanceMoney + bonesMoney + smashMoney) * multiplier + 0.5),
		distance = distance,
		bones = stats.bones,
		smashed = stats.smashed,
		distanceMoney = distanceMoney,
		bonesMoney = bonesMoney,
		smashMoney = smashMoney,
		zoneMultiplier = stats.zoneMultiplier,
		valueMultiplier = valueMultiplier,
		perfect = stats.perfect,
	}
end

return Economy
