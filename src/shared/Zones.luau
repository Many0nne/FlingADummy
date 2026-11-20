-- Zones de la piste : chaque zone traversée fait monter la CHANCE du tirage (bannière « 1.36X CHANCE » en vol) et a son
-- identité visuelle, comme les zones de *Throw a Seed* : couleur du sol en damier, des parois en gradins, de l'herbe
-- (ou neige, sable…) qui coiffe les gradins, et ses éléments de décor voxel.
local Zones = {}

export type Zone = {
	start: number, -- distance (m) où la zone commence
	name: string,
	color: Color3, -- bannière, panneaux
	chance: number, -- CHANCE en entrant dans la zone (elle monte vers celle de la suivante pendant la traversée)
	ground: Color3, -- sol du canyon (le damier assombrit un carreau sur deux)
	wall: Color3, -- parois en gradins
	top: Color3, -- couverture des gradins (herbe, sable, neige…)
	props: { string }, -- décor posé sur les gradins et au pied des parois (Server.Props)
}

-- stylua: ignore
Zones.LIST = {
	{ start = 0,    name = "Meadow",       chance = 1,    color = Color3.fromRGB(95, 215, 50),
	  ground = Color3.fromRGB(90, 240, 35),   wall = Color3.fromRGB(128, 92, 60),   top = Color3.fromRGB(95, 245, 35),
	  props = { "tree", "tree", "bush", "flowers", "rock" } },
	{ start = 100,  name = "Forest",       chance = 1.25, color = Color3.fromRGB(40, 160, 70),
	  ground = Color3.fromRGB(60, 200, 50),   wall = Color3.fromRGB(110, 80, 60),   top = Color3.fromRGB(50, 185, 50),
	  props = { "pine", "pine", "tree", "mushroom", "bush" } },
	{ start = 250,  name = "Desert",       chance = 1.6,  color = Color3.fromRGB(240, 185, 70),
	  ground = Color3.fromRGB(250, 215, 120), wall = Color3.fromRGB(225, 140, 70),  top = Color3.fromRGB(175, 185, 70),
	  props = { "palm", "cactus", "cactus", "rock", "drybush" } },
	{ start = 450,  name = "Construction", chance = 2.2,  color = Color3.fromRGB(255, 170, 30),
	  ground = Color3.fromRGB(255, 200, 45),  wall = Color3.fromRGB(205, 95, 50),   top = Color3.fromRGB(110, 200, 55),
	  props = { "cone", "cone", "barrier", "girders", "tree" } },
	{ start = 700,  name = "Snowfield",    chance = 3.2,  color = Color3.fromRGB(120, 200, 255),
	  ground = Color3.fromRGB(225, 240, 255), wall = Color3.fromRGB(120, 175, 235), top = Color3.fromRGB(250, 252, 255),
	  props = { "snowpine", "snowpine", "snowman", "icerock" } },
	{ start = 1000, name = "Volcano",      chance = 5,    color = Color3.fromRGB(255, 85, 40),
	  ground = Color3.fromRGB(215, 85, 45),   wall = Color3.fromRGB(95, 60, 60),    top = Color3.fromRGB(255, 120, 30),
	  props = { "lavarock", "lavarock", "deadtree", "rock" } },
	{ start = 1400, name = "Candy Land",   chance = 8,    color = Color3.fromRGB(255, 110, 200),
	  ground = Color3.fromRGB(255, 165, 215), wall = Color3.fromRGB(190, 110, 235), top = Color3.fromRGB(120, 240, 200),
	  props = { "lollipop", "lollipop", "candycane", "gumdrop" } },
	{ start = 1900, name = "Moon Base",    chance = 12,   color = Color3.fromRGB(170, 120, 255),
	  ground = Color3.fromRGB(185, 175, 230), wall = Color3.fromRGB(95, 75, 165),   top = Color3.fromRGB(215, 205, 250),
	  props = { "crystal", "crystal", "crater", "rocket" } },
} :: { Zone }

Zones.FINAL_CHANCE = 18 -- CHANCE au bout de la piste

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
