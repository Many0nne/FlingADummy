-- Économie du lancer : vitesse selon la Throw Power, et CHANCE gagnée pendant le vol (zones traversées, os cassés,
-- objets détruits) qui pousse le tirage du mannequin de collection. Le lancer ne rapporte aucun argent : l'argent vient
-- seulement du revenu des mannequins posés dans la base (Shared.Collection).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Zones = require(Shared:WaitForChild("Zones"))

local Economy = {}

export type Stats = {
	distance: number,
	bones: number,
	smashed: number,
	luck: number?, -- multiplicateur du mannequin lancé (Shared.ThrowDummies), 1 par défaut
	rebirth: number?, -- multiplicateur des renaissances du lanceur (Shared.Rebirth.luck), 1 par défaut
	boost: number?, -- multiplicateur de la boutique Robux (passe, potions, chance du serveur, lancer chanceux : Shared.Store.luck), 1 par défaut
}

export type Chance = {
	distance: number, -- mètres, arrondis vers le bas
	zone: number, -- indice de la zone atteinte
	zoneChance: number, -- chance due à la distance (zones traversées)
	bonesBonus: number, -- part ajoutée par les os cassés (0,03 = + 3 %)
	smashBonus: number, -- part ajoutée par les objets détruits
	luck: number, -- multiplicateur du mannequin lancé
	rebirth: number, -- multiplicateur des renaissances
	boost: number, -- multiplicateur de la boutique Robux
	total: number, -- chance finale, arrondie au centième
}

-- Cette méthode permet de calculer la vitesse de lancer (studs/s, jauge pleine) lorsque le joueur a `power` de Throw
-- Power ; courbe logarithmique (la puissance explose, la distance monte régulièrement), moins pentue au-delà de
-- SPEED_KNEE_POWER (#157 : le bout de piste arrive vers la fin des équipements, le premier kilomètre ne change pas).
function Economy.launchSpeed(power: number): number
	local p = math.max(power, GameConfig.START_POWER)
	local knee = GameConfig.SPEED_KNEE_POWER
	local near = math.log(math.min(p, knee) / GameConfig.START_POWER)
	local far = math.log(math.max(p, knee) / knee)
	return GameConfig.SPEED_BASE + GameConfig.SPEED_PER_LOG * near + GameConfig.SPEED_PER_LOG_FAR * far
end

-- Cette méthode permet de donner la chance due à la distance lorsque le mannequin est à `distance` mètres : celle de
-- la zone atteinte, qui monte en continu vers celle de la zone suivante (bannière qui grimpe pendant le vol).
function Economy.zoneChance(distance: number): number
	local d = math.max(0, distance)
	local index = Zones.indexAt(d)
	local zone = Zones.LIST[index]
	local nextZone = Zones.LIST[index + 1]
	local finish = if nextZone then nextZone.start else GameConfig.COURSE_LENGTH
	local target = if nextZone then nextZone.chance else Zones.FINAL_CHANCE
	local t = math.clamp((d - zone.start) / math.max(finish - zone.start, 1), 0, 1)
	return zone.chance + (target - zone.chance) * t
end

-- Cette méthode permet d'arrondir une chance au centième lorsqu'on l'affiche ou la garde (« 1.36X »).
function Economy.round(chance: number): number
	return math.floor(chance * 100 + 0.5) / 100
end

-- Cette méthode permet de calculer la CHANCE d'un lancer (et son détail pour l'écran de résultat) lorsque le
-- mannequin vole ou s'est arrêté : chance des zones × (1 + bonus des os + bonus de la casse) × multiplicateur du
-- mannequin lancé × multiplicateur des renaissances × multiplicateur de la boutique Robux.
function Economy.chance(stats: Stats): Chance
	local distance = math.max(0, math.floor(stats.distance))
	local zoneChance = Economy.zoneChance(stats.distance)
	local bonesBonus = math.max(0, stats.bones) * GameConfig.CHANCE_PER_BONE
	local smashBonus = math.max(0, stats.smashed) * GameConfig.CHANCE_PER_SMASH
	local luck = math.max(1, stats.luck or 1)
	local rebirth = math.max(1, stats.rebirth or 1)
	local boost = math.max(1, stats.boost or 1)
	return {
		distance = distance,
		zone = Zones.indexAt(distance),
		zoneChance = Economy.round(zoneChance),
		bonesBonus = bonesBonus,
		smashBonus = smashBonus,
		luck = luck,
		rebirth = rebirth,
		boost = boost,
		total = Economy.round(zoneChance * (1 + bonesBonus + smashBonus) * luck * rebirth * boost),
	}
end

return Economy
