-- Zones de la piste : chaque zone franchie augmente le multiplicateur de gains (bannière affichée en vol) et a son
-- identité visuelle, comme les zones de *Throw a Seed* : couleur du sol en damier, des parois en gradins, de l'herbe
-- (ou neige, sable…) qui coiffe les gradins, et ses éléments de décor voxel.
local Zones = {}

export type Zone = {
	start: number, -- distance (m) où la zone commence
	name: string,
	color: Color3, -- bannière, panneaux
	multiplier: number,
	ground: Color3, -- sol du canyon (le damier assombrit un carreau sur deux)
	wall: Color3, -- parois en gradins
	top: Color3, -- couverture des gradins (herbe, sable, neige…)
	props: { string }, -- décor posé sur les gradins et au pied des parois (Server.Props)
}

-- stylua: ignore
Zones.LIST = {
	{ start = 0,    name = "Meadow",       multiplier = 1,   color = Color3.fromRGB(95, 215, 50),
	  ground = Color3.fromRGB(105, 225, 45),  wall = Color3.fromRGB(160, 100, 55),  top = Color3.fromRGB(95, 215, 50),
	  props = { "tree", "tree", "bush", "flowers", "rock" } },
	{ start = 100,  name = "Forest",       multiplier = 1.5, color = Color3.fromRGB(40, 160, 70),
	  ground = Color3.fromRGB(60, 185, 60),   wall = Color3.fromRGB(125, 80, 45),   top = Color3.fromRGB(45, 160, 60),
	  props = { "pine", "pine", "tree", "mushroom", "bush" } },
	{ start = 250,  name = "Desert",       multiplier = 2.2, color = Color3.fromRGB(240, 185, 70),
	  ground = Color3.fromRGB(250, 215, 120), wall = Color3.fromRGB(225, 140, 70),  top = Color3.fromRGB(175, 185, 70),
	  props = { "palm", "cactus", "cactus", "rock", "drybush" } },
	{ start = 450,  name = "Construction", multiplier = 3.3, color = Color3.fromRGB(255, 170, 30),
	  ground = Color3.fromRGB(255, 200, 45),  wall = Color3.fromRGB(205, 95, 50),   top = Color3.fromRGB(110, 200, 55),
	  props = { "cone", "cone", "barrier", "girders", "tree" } },
	{ start = 700,  name = "Snowfield",    multiplier = 5,   color = Color3.fromRGB(120, 200, 255),
	  ground = Color3.fromRGB(225, 240, 255), wall = Color3.fromRGB(120, 175, 235), top = Color3.fromRGB(250, 252, 255),
	  props = { "snowpine", "snowpine", "snowman", "icerock" } },
	{ start = 1000, name = "Volcano",      multiplier = 7.5, color = Color3.fromRGB(255, 85, 40),
	  ground = Color3.fromRGB(215, 85, 45),   wall = Color3.fromRGB(95, 60, 60),    top = Color3.fromRGB(255, 120, 30),
	  props = { "lavarock", "lavarock", "deadtree", "rock" } },
	{ start = 1400, name = "Candy Land",   multiplier = 11,  color = Color3.fromRGB(255, 110, 200),
	  ground = Color3.fromRGB(255, 165, 215), wall = Color3.fromRGB(190, 110, 235), top = Color3.fromRGB(120, 240, 200),
	  props = { "lollipop", "lollipop", "candycane", "gumdrop" } },
	{ start = 1900, name = "Moon Base",    multiplier = 16,  color = Color3.fromRGB(170, 120, 255),
	  ground = Color3.fromRGB(185, 175, 230), wall = Color3.fromRGB(95, 75, 165),   top = Color3.fromRGB(215, 205, 250),
	  props = { "crystal", "crystal", "crater", "rocket" } },
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

-- Cette méthode permet de donner où finit la zone `index` (début de la suivante, ou `courseLength` pour la dernière)
-- lorsque l'on construit son tronçon de piste.
function Zones.finish(index: number, courseLength: number): number
	local nextZone = Zones.LIST[index + 1]
	return if nextZone then math.min(nextZone.start, courseLength) else courseLength
end

return Zones
