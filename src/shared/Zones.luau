-- Zones (thèmes) de la piste : chaque zone traversée fait monter la CHANCE du tirage (bannière « 1.36X CHANCE » en vol)
-- et a son identité, comme les zones de *Throw a Seed* : couleur du sol en damier, des parois en gradins, de l'herbe
-- (ou neige, sable…) qui coiffe les gradins, son décor voxel, ses obstacles cassables (Server.ThemeObstacles) et son
-- piège signature (Shared.Traps). Thèmes courts au début (un changement tous les 60 à 150 m sur les 1 000 premiers
-- mètres, là où vole un joueur débutant), plus longs ensuite (#33).
local Zones = {}

export type Zone = {
	start: number, -- distance (m) où la zone commence
	name: string,
	color: Color3, -- bannière, panneaux, cadres des vitres
	chance: number, -- CHANCE en entrant dans la zone (elle monte vers celle de la suivante pendant la traversée)
	ground: Color3, -- sol du canyon (le damier assombrit un carreau sur deux)
	wall: Color3, -- parois en gradins
	top: Color3, -- couverture des gradins (herbe, sable, neige…)
	props: { string }, -- décor posé sur les gradins et au pied des parois (Server.Props)
	obstacles: { string }, -- obstacles cassables de la zone, posés à tour de rôle (Server.ThemeObstacles)
	trap: string, -- piège signature (Shared.Traps.KINDS)
}

-- Chance à l'entrée de chaque zone : celle de l'ancienne courbe (8 zones, v0.3) à la même distance, arrondie, pour
-- que l'économie (#15) ne bouge pas : ≈ 1.4X au premier lancer (145 m), ×5 à 1 km, 18 au bout de la piste.
-- stylua: ignore
Zones.LIST = {
	{ start = 0,    name = "Meadow",       chance = 1,    color = Color3.fromRGB(95, 215, 50),
	  ground = Color3.fromRGB(90, 240, 35),   wall = Color3.fromRGB(128, 92, 60),   top = Color3.fromRGB(95, 245, 35),
	  props = { "tree", "tree", "bush", "flowers", "rock" },
	  obstacles = { "HayBales", "Crates", "Sign" },          trap = "Trampoline" },
	{ start = 60,   name = "Farm",         chance = 1.15, color = Color3.fromRGB(225, 70, 50),
	  ground = Color3.fromRGB(235, 195, 80),  wall = Color3.fromRGB(150, 105, 75),  top = Color3.fromRGB(120, 225, 50),
	  props = { "haystack", "haystack", "silo", "tree", "bush" },
	  obstacles = { "Tractor", "Fence", "HayBales" },        trap = "Fan" },
	{ start = 135,  name = "Forest",       chance = 1.35, color = Color3.fromRGB(40, 160, 70),
	  ground = Color3.fromRGB(60, 200, 50),   wall = Color3.fromRGB(110, 80, 60),   top = Color3.fromRGB(50, 185, 50),
	  props = { "pine", "pine", "tree", "mushroom", "bush" },
	  obstacles = { "Logs", "Beehives" },                    trap = "SwingLog" },
	{ start = 220,  name = "Beach",        chance = 1.5,  color = Color3.fromRGB(40, 200, 230),
	  ground = Color3.fromRGB(255, 240, 190), wall = Color3.fromRGB(200, 150, 105), top = Color3.fromRGB(250, 225, 150),
	  props = { "palm", "palm", "parasol", "beachball", "rock" },
	  obstacles = { "Sandcastle", "Surfboards" },            trap = "Wave" },
	{ start = 315,  name = "Desert",       chance = 1.8,  color = Color3.fromRGB(240, 185, 70),
	  ground = Color3.fromRGB(250, 215, 120), wall = Color3.fromRGB(225, 140, 70),  top = Color3.fromRGB(175, 185, 70),
	  props = { "palm", "cactus", "cactus", "rock", "drybush" },
	  obstacles = { "Barrels", "Cactus" },                   trap = "Twister" },
	{ start = 420,  name = "Construction", chance = 2.1,  color = Color3.fromRGB(255, 170, 30),
	  ground = Color3.fromRGB(255, 200, 45),  wall = Color3.fromRGB(205, 95, 50),   top = Color3.fromRGB(110, 200, 55),
	  props = { "cone", "cone", "barrier", "girders", "tree" },
	  obstacles = { "Scaffolding", "Wall", "Cones" },        trap = "Press" },
	{ start = 535,  name = "Junkyard",     chance = 2.5,  color = Color3.fromRGB(205, 110, 50),
	  ground = Color3.fromRGB(150, 140, 125), wall = Color3.fromRGB(125, 90, 65),   top = Color3.fromRGB(125, 165, 70),
	  props = { "tirestack", "tirestack", "wreck", "rock" },
	  obstacles = { "Car", "Tires" },                        trap = "Magnet" },
	{ start = 660,  name = "Snowfield",    chance = 3,    color = Color3.fromRGB(120, 200, 255),
	  ground = Color3.fromRGB(225, 240, 255), wall = Color3.fromRGB(120, 175, 235), top = Color3.fromRGB(250, 252, 255),
	  props = { "snowpine", "snowpine", "snowman", "icerock" },
	  obstacles = { "Snowmen", "IceWall" },                  trap = "SkiJump" },
	{ start = 800,  name = "Volcano",      chance = 3.8,  color = Color3.fromRGB(255, 85, 40),
	  ground = Color3.fromRGB(215, 85, 45),   wall = Color3.fromRGB(95, 60, 60),    top = Color3.fromRGB(255, 120, 30),
	  props = { "lavarock", "lavarock", "deadtree", "rock" },
	  obstacles = { "LavaRocks", "BasaltWall" },             trap = "Lava" },
	{ start = 950,  name = "Candy Land",   chance = 4.7,  color = Color3.fromRGB(255, 110, 200),
	  ground = Color3.fromRGB(255, 165, 215), wall = Color3.fromRGB(190, 110, 235), top = Color3.fromRGB(120, 240, 200),
	  props = { "lollipop", "lollipop", "candycane", "gumdrop" },
	  obstacles = { "CandyCanes", "MarshmallowWall" },       trap = "Cannon" },
	{ start = 1250, name = "Toy Town",     chance = 7,    color = Color3.fromRGB(255, 75, 75),
	  ground = Color3.fromRGB(90, 175, 255),  wall = Color3.fromRGB(255, 200, 50),  top = Color3.fromRGB(255, 95, 95),
	  props = { "toyblocks", "toyblocks", "teddy", "beachball" },
	  obstacles = { "ToyBlocks", "ToySoldiers" },            trap = "JackBox" },
	{ start = 1650, name = "Moon Base",    chance = 10,   color = Color3.fromRGB(170, 120, 255),
	  ground = Color3.fromRGB(185, 175, 230), wall = Color3.fromRGB(95, 75, 165),   top = Color3.fromRGB(215, 205, 250),
	  props = { "crystal", "crystal", "crater", "rocket" },
	  obstacles = { "Satellites", "Rover" },                 trap = "Booster" },
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
