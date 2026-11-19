-- Zones de la piste : chaque zone franchie augmente le multiplicateur de gains (bannière affichée en vol).
local Zones = {}

export type Zone = { start: number, name: string, color: Color3, multiplier: number }

-- start : distance (m) où la zone commence
Zones.LIST = {
	{ start = 0, name = "Test Track", color = Color3.fromRGB(150, 155, 165), multiplier = 1 },
	{ start = 100, name = "Parking Lot", color = Color3.fromRGB(70, 150, 235), multiplier = 1.5 },
	{ start = 250, name = "Warehouse", color = Color3.fromRGB(240, 140, 40), multiplier = 2.2 },
	{ start = 450, name = "Highway", color = Color3.fromRGB(250, 205, 40), multiplier = 3.3 },
	{ start = 700, name = "Construction Site", color = Color3.fromRGB(235, 90, 50), multiplier = 5 },
	{ start = 1000, name = "Junkyard", color = Color3.fromRGB(140, 110, 80), multiplier = 7.5 },
	{ start = 1400, name = "Airfield", color = Color3.fromRGB(80, 200, 140), multiplier = 11 },
	{ start = 1900, name = "Rocket Range", color = Color3.fromRGB(170, 90, 230), multiplier = 16 },
} :: { Zone }

-- Cette méthode permet de donner l'indice de la zone atteinte lorsque le mannequin est à `distance` mètres.
function Zones.indexAt(distance: number): number
	local index = 1
	for i, zone in Zones.LIST do
		if distance >= zone.start then
			index = i
		end
	end
	return index
end

-- Cette méthode permet de donner la zone atteinte lorsque le mannequin est à `distance` mètres.
function Zones.at(distance: number): Zone
	return Zones.LIST[Zones.indexAt(distance)]
end

return Zones
