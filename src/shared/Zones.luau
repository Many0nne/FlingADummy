-- Zones (thèmes) de la piste : chaque zone traversée fait monter la CHANCE du tirage (bannière « 1.36X CHANCE » en vol)
-- et a son identité, comme les zones de *Throw a Seed* : couleur du sol en damier, des parois en gradins, de l'herbe
-- (ou neige, sable…) qui coiffe les gradins, son décor voxel, ses obstacles cassables (Server.ThemeObstacles) et son
-- piège signature (Shared.Traps). Thèmes courts au début (un changement tous les 60 à 150 m sur les 1 000 premiers
-- mètres, là où vole un joueur débutant), plus longs ensuite (#33), puis un tous les 600 m de 2,4 à 6 km (#97).
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
	obstacles: { string }, -- obstacles cassables de la zone, posés à tour de rôle (Server.ThemeObstacles)
	trap: string, -- piège signature (Shared.Traps.KINDS)
	night: boolean?, -- ciel de nuit étoilé quand la caméra y est (Client.ZoneSky) : la Galaxy (#97)
}

-- Chance à l'entrée de chaque zone : celle de l'ancienne courbe (8 zones, v0.3) à la même distance, arrondie ; entre
-- deux entrées la courbe reste linéaire, d'où de petits écarts (+5 % au plus vers 1,9 km) : ≈ 1.4X au premier lancer
-- (145 m), ×5 à 1 km, 18 à 2,4 km (fin de la Moon Base), 60 au bout de la piste (6 km, #97).
-- stylua: ignore
Zones.LIST = {
	{ start = 0,    name = "Meadow",       chance = 1,    color = Color3.fromRGB(95, 215, 50),
	  ground = Color3.fromRGB(90, 240, 35),   wall = Color3.fromRGB(128, 92, 60),   top = Color3.fromRGB(95, 245, 35),
	  props = { "tree", "tree", "bush", "flowers", "rock" },
	  obstacles = { "HayBales", "Crates" },                  trap = "Trampoline" },
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
	  obstacles = { "Car", "Tires", "Sign" },                trap = "Magnet" },
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
	-- Piste prolongée (#97) : un thème tous les 600 m, CHANCE en progression géométrique (× 1,22 par thème : 27 à 3,6 km,
	-- 40 à 4,8 km, 60 au bout) ; rien ne bouge avant 2,4 km
	{ start = 2400, name = "Mars",           chance = 18, color = Color3.fromRGB(235, 95, 45),
	  ground = Color3.fromRGB(215, 105, 60),  wall = Color3.fromRGB(150, 65, 45),   top = Color3.fromRGB(240, 150, 85),
	  props = { "marsrock", "marsrock", "marscrater", "radar" },
	  obstacles = { "MarsRocks", "Lander" },                 trap = "Geyser" },
	{ start = 3000, name = "Crystal Cave",   chance = 22, color = Color3.fromRGB(165, 90, 255),
	  ground = Color3.fromRGB(105, 75, 185),  wall = Color3.fromRGB(70, 50, 125),   top = Color3.fromRGB(95, 235, 245),
	  props = { "bigcrystal", "bigcrystal", "crystal", "stalagmite" },
	  obstacles = { "CrystalClusters", "AmethystWall" },     trap = "Bumper" },
	{ start = 3600, name = "Neon City",      chance = 27, color = Color3.fromRGB(255, 50, 190),
	  ground = Color3.fromRGB(55, 55, 95),    wall = Color3.fromRGB(45, 40, 80),    top = Color3.fromRGB(255, 70, 200),
	  props = { "skyscraper", "skyscraper", "neonsign", "streetlamp" },
	  obstacles = { "Taxis", "ArcadeCabinets" },             trap = "Laser" },
	{ start = 4200, name = "Sky Kingdom",    chance = 33, color = Color3.fromRGB(80, 190, 255),
	  ground = Color3.fromRGB(150, 215, 255), wall = Color3.fromRGB(240, 245, 255), top = Color3.fromRGB(115, 230, 85),
	  props = { "cloud", "cloud", "rainbow", "floatisland" },
	  obstacles = { "CloudPuffs", "HotAirBalloons" },        trap = "Rainbow" },
	{ start = 4800, name = "Haunted Castle", chance = 40, color = Color3.fromRGB(255, 140, 30),
	  ground = Color3.fromRGB(95, 85, 110),   wall = Color3.fromRGB(60, 55, 75),    top = Color3.fromRGB(125, 185, 70),
	  props = { "pumpkin", "pumpkin", "gravestone", "deadtree", "spiderweb" },
	  obstacles = { "Pumpkins", "Coffins" },                 trap = "Ghost" },
	{ start = 5400, name = "Galaxy",         chance = 49, color = Color3.fromRGB(120, 80, 255),
	  ground = Color3.fromRGB(45, 40, 120),   wall = Color3.fromRGB(30, 25, 70),    top = Color3.fromRGB(160, 100, 255),
	  props = { "planet", "star", "star", "asteroid" },
	  obstacles = { "Asteroids", "UFOs" },                   trap = "Wormhole",  night = true },
} :: { Zone }

Zones.FINAL_CHANCE = 60 -- CHANCE au bout de la piste (6 km)

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

Zones.NIGHT_LEAD = 120 -- la nuit tombe un peu avant l'entrée d'une zone de nuit (m) : on la voit arriver

-- Cette méthode permet de savoir si le ciel doit être de nuit lorsque la caméra est à `distance` mètres sur la piste
-- (zone de nuit atteinte, ou à moins de NIGHT_LEAD de son entrée).
function Zones.isNight(distance: number): boolean
	return Zones.at(distance + Zones.NIGHT_LEAD).night == true
end

-- Cette méthode permet de donner où finit la zone `index` (début de la suivante, ou `courseLength` pour la dernière)
-- lorsque l'on construit son tronçon de piste.
function Zones.finish(index: number, courseLength: number): number
	local nextZone = Zones.LIST[index + 1]
	return if nextZone then math.min(nextZone.start, courseLength) else courseLength
end

return Zones
