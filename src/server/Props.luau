-- Décor voxel au style des jeux de référence (01 / 09) : arbres et rochers en blocs à tenons, végétation et objets de
-- chaque zone, barrières en blocs, stands à auvents rayés, panneaux. Chaque élément est posé au repère `at` (au sol,
-- face avant vers -Z de `at`) et ne contient que des blocs ancrés.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local Build = require(script.Parent.Build)

local Props = {}

type Builder = (parent: Instance, at: CFrame, rng: Random, solid: boolean) -> ()

local rgb = Color3.fromRGB
local TRUNK = rgb(125, 80, 40)
local LEAF = rgb(95, 205, 55)
local LEAF_DARK = rgb(55, 160, 50)
local STONE = rgb(160, 160, 170)
local WHITE = rgb(250, 250, 250)
local WOOD = rgb(230, 185, 120)
local WOOD_DARK = rgb(185, 130, 75)
local DUMMY_YELLOW = rgb(255, 205, 40)

-- Cette méthode permet de poser un bloc à la position locale `offset` (repère `at`), avec une rotation locale en
-- degrés, lorsque l'on assemble un élément voxel.
local function put(
	parent: Instance,
	at: CFrame,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	solid: boolean,
	rotation: Vector3?
): Part
	local cframe = at * CFrame.new(offset)
	if rotation then
		cframe *= CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	end
	return Build.block(parent, size, cframe, color, solid)
end

-- Cette méthode permet de donner un multiple aléatoire de `step` entre `low` et `high` lorsque l'on varie la taille
-- d'un élément sans casser la grille des tenons.
local function snap(rng: Random, low: number, high: number, step: number): number
	return math.floor(rng:NextNumber(low, high) / step + 0.5) * step
end

local builders: { [string]: Builder } = {}

-- Cette méthode permet de construire un arbre feuillu (tronc carré, houppier en cubes de deux verts, 09 : Prairie) lorsque l'on habille une zone.
builders.tree = function(parent, at, rng, solid)
	local s = snap(rng, 0.8, 1.4, 0.2)
	put(parent, at, Vector3.new(2, 7, 2) * s, Vector3.new(0, 3.5 * s, 0), TRUNK, solid)
	put(parent, at, Vector3.new(8, 4, 8) * s, Vector3.new(0, 8 * s, 0), LEAF_DARK, solid)
	put(parent, at, Vector3.new(6, 4, 6) * s, Vector3.new(0, 11.5 * s, 0), LEAF, solid)
	for _ = 1, 3 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local offset = Vector3.new(math.cos(angle) * 3.5, rng:NextNumber(7, 11), math.sin(angle) * 3.5) * s
		put(parent, at, Vector3.new(3, 3, 3) * s, offset, if rng:NextNumber() < 0.5 then LEAF else LEAF_DARK, solid)
	end
end

-- Cette méthode permet de construire un sapin en étages, coiffé de neige si `snowy`, lorsque l'on habille la forêt
-- ou le champ de neige.
local function pine(parent: Instance, at: CFrame, rng: Random, solid: boolean, snowy: boolean)
	local s = snap(rng, 0.8, 1.5, 0.2)
	put(parent, at, Vector3.new(1.6, 4, 1.6) * s, Vector3.new(0, 2 * s, 0), TRUNK, solid)
	local widths = { 8, 6, 4, 2 }
	for i, width in widths do
		local y = (3.5 + (i - 1) * 3) * s
		put(parent, at, Vector3.new(width, 3, width) * s, Vector3.new(0, y, 0), rgb(40, 140, 55), solid)
		if snowy then
			put(
				parent,
				at,
				Vector3.new(width - 0.4, 0.6, width - 0.4) * s,
				Vector3.new(0, y + 1.6 * s, 0),
				WHITE,
				solid
			)
		end
	end
end

-- Cette méthode permet de construire un sapin en étages lorsque l'on habille une zone.
builders.pine = function(parent, at, rng, solid)
	pine(parent, at, rng, solid, false)
end

-- Cette méthode permet de construire un sapin en étages coiffé de neige lorsque l'on habille une zone.
builders.snowpine = function(parent, at, rng, solid)
	pine(parent, at, rng, solid, true)
end

-- Cette méthode permet de construire un buisson de deux ou trois cubes verts lorsque l'on habille une zone.
builders.bush = function(parent, at, rng, solid)
	for i = 1, rng:NextInteger(2, 3) do
		local size = snap(rng, 2.5, 4, 0.5)
		local offset = Vector3.new((i - 2) * 2.2, size / 2, rng:NextNumber(-1, 1))
		put(parent, at, Vector3.one * size, offset, if i % 2 == 0 then LEAF else LEAF_DARK, solid)
	end
end

-- Cette méthode permet de construire un massif de fleurs colorées sur tiges (toujours traversable) lorsque l'on habille une zone.
builders.flowers = function(parent, at, rng)
	local colors = { rgb(255, 70, 70), rgb(255, 220, 40), WHITE, rgb(255, 120, 200), rgb(150, 110, 255) }
	for _ = 1, rng:NextInteger(3, 6) do
		local offset = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		put(parent, at, Vector3.new(0.4, 1.6, 0.4), offset + Vector3.new(0, 0.8, 0), LEAF_DARK, false)
		put(
			parent,
			at,
			Vector3.new(1, 1, 1),
			offset + Vector3.new(0, 1.9, 0),
			colors[rng:NextInteger(1, #colors)],
			false
		)
	end
end

-- Cette méthode permet d'empiler deux ou trois blocs de roche d'une couleur donnée lorsque l'on pose un rocher.
local function boulder(parent: Instance, at: CFrame, rng: Random, solid: boolean, color: Color3, glow: Color3?)
	local base = snap(rng, 4, 7, 1)
	put(parent, at, Vector3.new(base, base * 0.7, base * 0.9), Vector3.new(0, base * 0.35, 0), color, solid)
	put(
		parent,
		at,
		Vector3.new(base * 0.6, base * 0.5, base * 0.6),
		Vector3.new(base * 0.2, base * 0.9, 0),
		Build.shade(color, 0.85),
		solid
	)
	if glow then
		local vein =
			put(parent, at, Vector3.new(base * 0.9, 0.5, 0.6), Vector3.new(0, base * 0.4, -base * 0.46), glow, false)
		vein.Material = Enum.Material.Neon
	end
end

-- Cette méthode permet de construire un rocher gris en blocs lorsque l'on habille une zone.
builders.rock = function(parent, at, rng, solid)
	boulder(parent, at, rng, solid, STONE)
end

-- Cette méthode permet de construire un rocher de glace en blocs lorsque l'on habille une zone.
builders.icerock = function(parent, at, rng, solid)
	boulder(parent, at, rng, solid, rgb(170, 225, 255))
end

-- Cette méthode permet de construire un rocher de basalte à veine de lave lorsque l'on habille une zone.
builders.lavarock = function(parent, at, rng, solid)
	boulder(parent, at, rng, solid, rgb(70, 50, 55), rgb(255, 120, 20))
end

-- Cette méthode permet de construire un champignon géant rouge à pois blancs (09 : Forêt) lorsque l'on habille une zone.
builders.mushroom = function(parent, at, rng, solid)
	local s = snap(rng, 0.8, 1.4, 0.2)
	put(parent, at, Vector3.new(2, 5, 2) * s, Vector3.new(0, 2.5 * s, 0), rgb(245, 235, 215), solid)
	put(parent, at, Vector3.new(8, 2, 8) * s, Vector3.new(0, 6 * s, 0), rgb(230, 40, 40), solid)
	put(parent, at, Vector3.new(5, 1.4, 5) * s, Vector3.new(0, 7.6 * s, 0), rgb(230, 40, 40), solid)
	for _, offset in { Vector3.new(2.5, 7.05, 2.5), Vector3.new(-2.5, 7.05, -1.5), Vector3.new(0.5, 8.35, -0.5) } do
		put(parent, at, Vector3.new(1.2, 0.2, 1.2) * s, offset * s, WHITE, false)
	end
end

-- Cette méthode permet de construire un palmier à tronc en segments et palmes en lattes (01 / 09 : désert) lorsque l'on habille une zone.
builders.palm = function(parent, at, rng, solid)
	local lean = rng:NextNumber(-0.4, 0.4)
	local top = Vector3.zero
	for i = 0, 4 do
		top = Vector3.new(lean * i, 1.5 + i * 3, 0)
		put(parent, at, Vector3.new(1.6, 3, 1.6), top, if i % 2 == 0 then TRUNK else rgb(150, 100, 55), solid)
	end
	for i = 0, 4 do
		local yaw = i * 72 + rng:NextNumber(-10, 10)
		local leaf = at * CFrame.new(top + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
		Build.block(
			parent,
			Vector3.new(7, 0.8, 1.8),
			leaf * CFrame.new(3, -0.6, 0) * CFrame.Angles(0, 0, math.rad(-20)),
			LEAF,
			solid
		)
	end
	put(parent, at, Vector3.new(1, 1, 1), top + Vector3.new(0.9, 0.6, 0.9), rgb(110, 70, 35), false)
end

-- Cette méthode permet de construire un cactus en colonnes à deux bras lorsque l'on habille une zone.
builders.cactus = function(parent, at, rng, solid)
	local h = snap(rng, 6, 10, 1)
	local green = rgb(70, 175, 70)
	put(parent, at, Vector3.new(2, h, 2), Vector3.new(0, h / 2, 0), green, solid)
	for _, side in { -1, 1 } do
		local y = h * rng:NextNumber(0.35, 0.6)
		put(parent, at, Vector3.new(2.5, 1.6, 1.6), Vector3.new(side * 2.2, y, 0), green, solid)
		put(parent, at, Vector3.new(1.6, 3, 1.6), Vector3.new(side * 2.9, y + 2.2, 0), green, solid)
	end
end

-- Cette méthode permet de construire un buisson sec du désert lorsque l'on habille une zone.
builders.drybush = function(parent, at, rng)
	for i = 1, 3 do
		local size = snap(rng, 1.5, 2.5, 0.5)
		put(parent, at, Vector3.one * size, Vector3.new((i - 2) * 1.6, size / 2, 0), rgb(170, 150, 70), false)
	end
end

-- Cette méthode permet de construire un plot de chantier orange à bande blanche lorsque l'on habille une zone.
builders.cone = function(parent, at, rng)
	local s = snap(rng, 1, 1.6, 0.2)
	local orange = rgb(255, 120, 20)
	put(parent, at, Vector3.new(3, 0.4, 3) * s, Vector3.new(0, 0.2 * s, 0), rgb(40, 40, 45), false)
	put(parent, at, Vector3.new(2.2, 1.4, 2.2) * s, Vector3.new(0, 1.1 * s, 0), orange, false)
	put(parent, at, Vector3.new(1.7, 0.8, 1.7) * s, Vector3.new(0, 2.2 * s, 0), WHITE, false)
	put(parent, at, Vector3.new(1.2, 1.4, 1.2) * s, Vector3.new(0, 3.3 * s, 0), orange, false)
end

-- Cette méthode permet de construire une barrière de chantier à rayures rouges et blanches lorsque l'on habille une zone.
builders.barrier = function(parent, at, _rng, solid)
	for _, side in { -1, 1 } do
		put(parent, at, Vector3.new(0.8, 3.5, 0.8), Vector3.new(side * 4, 1.75, 0), rgb(60, 60, 70), solid)
	end
	for i = 0, 4 do
		put(
			parent,
			at,
			Vector3.new(2, 1.4, 0.6),
			Vector3.new(-4 + i * 2, 2.8, 0),
			if i % 2 == 0 then rgb(230, 40, 40) else WHITE,
			solid
		)
	end
end

-- Cette méthode permet de construire une pile de poutrelles orange lorsque l'on habille une zone.
builders.girders = function(parent, at, rng, solid)
	for i = 0, rng:NextInteger(2, 3) do
		put(
			parent,
			at,
			Vector3.new(1.2, 1.2, 12),
			Vector3.new((i % 2) * 1.4 - 0.7, 0.6 + i * 1.2, 0),
			rgb(240, 95, 35),
			solid,
			Vector3.new(0, i * 8, 0)
		)
	end
end

-- Cette méthode permet de construire un bonhomme de neige lorsque l'on habille une zone.
builders.snowman = function(parent, at, _rng, solid)
	put(parent, at, Vector3.new(4, 4, 4), Vector3.new(0, 2, 0), WHITE, solid)
	put(parent, at, Vector3.new(3, 3, 3), Vector3.new(0, 5.5, 0), WHITE, solid)
	put(parent, at, Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 8.1, 0), WHITE, solid)
	put(parent, at, Vector3.new(0.5, 0.5, 1.4), Vector3.new(0, 8.1, -1.6), rgb(255, 130, 30), false)
	put(parent, at, Vector3.new(2.6, 0.4, 2.6), Vector3.new(0, 9.4, 0), rgb(40, 40, 50), false)
	put(parent, at, Vector3.new(1.8, 1.2, 1.8), Vector3.new(0, 10.2, 0), rgb(40, 40, 50), false)
end

-- Cette méthode permet de construire un arbre mort du volcan lorsque l'on habille une zone.
builders.deadtree = function(parent, at, rng, solid)
	local dark = rgb(70, 45, 35)
	put(parent, at, Vector3.new(1.6, 9, 1.6), Vector3.new(0, 4.5, 0), dark, solid)
	put(
		parent,
		at,
		Vector3.new(1, 4, 1),
		Vector3.new(1.5, 7, 0),
		dark,
		solid,
		Vector3.new(0, 0, -40 + rng:NextNumber(-10, 10))
	)
	put(parent, at, Vector3.new(1, 3.5, 1), Vector3.new(-1.3, 5.5, 0), dark, solid, Vector3.new(0, 0, 45))
end

-- Cette méthode permet de construire une sucette géante à spirale en carrés lorsque l'on habille une zone.
builders.lollipop = function(parent, at, rng, solid)
	local colors = { rgb(255, 80, 160), rgb(80, 200, 255), rgb(255, 210, 50), rgb(140, 100, 255) }
	local color = colors[rng:NextInteger(1, #colors)]
	put(parent, at, Vector3.new(0.8, 9, 0.8), Vector3.new(0, 4.5, 0), WHITE, solid)
	-- Spirale en carrés concentriques, de plus en plus épais pour ressortir sur les deux faces
	for i, width in { 6, 4.6, 3.2, 1.8 } do
		put(
			parent,
			at,
			Vector3.new(width, width, 1 + i * 0.2),
			Vector3.new(0, 11, 0),
			if i % 2 == 1 then color else WHITE,
			i == 1 and solid
		)
	end
end

-- Cette méthode permet de construire un sucre d'orge rayé à crosse lorsque l'on habille une zone.
builders.candycane = function(parent, at, _rng, solid)
	for i = 0, 6 do
		put(
			parent,
			at,
			Vector3.new(1.4, 1.4, 1.4),
			Vector3.new(0, 0.7 + i * 1.4, 0),
			if i % 2 == 0 then rgb(235, 40, 50) else WHITE,
			solid
		)
	end
	put(parent, at, Vector3.new(1.4, 1.4, 1.4), Vector3.new(1.4, 10.5, 0), WHITE, solid)
	put(parent, at, Vector3.new(1.4, 1.4, 1.4), Vector3.new(2.8, 9.8, 0), rgb(235, 40, 50), solid)
end

-- Cette méthode permet de construire une boule de gomme lorsque l'on habille une zone.
builders.gumdrop = function(parent, at, rng, solid)
	local colors = { rgb(255, 90, 90), rgb(90, 220, 120), rgb(255, 200, 60), rgb(110, 160, 255) }
	local color = colors[rng:NextInteger(1, #colors)]
	put(parent, at, Vector3.new(4, 2.5, 4), Vector3.new(0, 1.25, 0), color, solid)
	put(parent, at, Vector3.new(2.6, 1.5, 2.6), Vector3.new(0, 3.25, 0), Build.shade(color, 1.15), solid)
end

-- Cette méthode permet de construire des cristaux lumineux de la base lunaire lorsque l'on habille une zone.
builders.crystal = function(parent, at, rng)
	local colors = { rgb(120, 230, 255), rgb(200, 120, 255), rgb(255, 120, 220) }
	for i = 1, 3 do
		local h = snap(rng, 3, 8, 1)
		local tilt = Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25))
		local crystal = put(
			parent,
			at,
			Vector3.new(1.4, h, 1.4),
			Vector3.new((i - 2) * 1.6, h / 2, 0),
			colors[rng:NextInteger(1, #colors)],
			false,
			tilt
		)
		crystal.Material = Enum.Material.Neon
		crystal.Transparency = 0.15
	end
end

-- Cette méthode permet de construire un cratère (couronne de blocs) lorsque l'on habille une zone.
builders.crater = function(parent, at, rng)
	local rim = rgb(140, 125, 190)
	for i = 0, 5 do
		local angle = i * math.pi / 3 + rng:NextNumber(-0.2, 0.2)
		put(parent, at, Vector3.new(3, 1.2, 3), Vector3.new(math.cos(angle) * 4, 0.6, math.sin(angle) * 4), rim, false)
	end
end

-- Cette méthode permet de construire une petite fusée blanche à ailerons rouges lorsque l'on habille une zone.
builders.rocket = function(parent, at, _rng, solid)
	local red = rgb(235, 50, 50)
	put(parent, at, Vector3.new(3, 10, 3), Vector3.new(0, 6, 0), WHITE, solid)
	put(parent, at, Vector3.new(2, 2, 2), Vector3.new(0, 12, 0), red, solid)
	put(parent, at, Vector3.new(1, 1.5, 1), Vector3.new(0, 13.75, 0), red, solid)
	put(parent, at, Vector3.new(1.4, 1.4, 0.4), Vector3.new(0, 8, -1.6), rgb(90, 190, 255), false)
	for _, side in { -1, 1 } do
		put(parent, at, Vector3.new(1, 4, 3), Vector3.new(side * 2, 2, 0), red, solid)
	end
end

-- Cette méthode permet de construire une meule de foin (deux étages de blocs dorés) lorsque l'on habille la ferme.
builders.haystack = function(parent, at, rng, solid)
	local s = snap(rng, 0.8, 1.2, 0.2)
	put(parent, at, Vector3.new(6, 3, 5) * s, Vector3.new(0, 1.5 * s, 0), rgb(240, 200, 70), solid)
	put(parent, at, Vector3.new(4, 2.4, 3.6) * s, Vector3.new(0, 4.2 * s, 0), rgb(220, 175, 50), solid)
end

-- Cette méthode permet de construire un silo de ferme (cuve rouge à cerclages blancs, dôme gris) lorsque l'on habille
-- la ferme.
builders.silo = function(parent, at, _rng, solid)
	local red = rgb(210, 55, 45)
	for i = 0, 3 do
		put(parent, at, Vector3.new(6, 3.6, 6), Vector3.new(0, 1.8 + i * 3.6, 0), red, solid)
		put(parent, at, Vector3.new(6.2, 0.4, 6.2), Vector3.new(0, 3.6 + i * 3.6, 0), WHITE, false)
	end
	put(parent, at, Vector3.new(4.6, 1.6, 4.6), Vector3.new(0, 15.2, 0), STONE, solid)
	put(parent, at, Vector3.new(2.6, 1, 2.6), Vector3.new(0, 16.5, 0), STONE, solid)
end

-- Cette méthode permet de planter un parasol de plage (mât blanc, toile en pétales rayés) lorsque l'on habille la
-- plage.
builders.parasol = function(parent, at, rng, solid)
	local colors = { rgb(255, 80, 80), rgb(60, 180, 255), rgb(255, 200, 50) }
	local color = colors[rng:NextInteger(1, #colors)]
	put(parent, at, Vector3.new(0.6, 7, 0.6), Vector3.new(0, 3.5, 0), WHITE, solid)
	for i = 0, 5 do
		local yaw = i * 60
		local petal = at * CFrame.new(0, 7, 0) * CFrame.Angles(0, math.rad(yaw), 0)
		Build.block(
			parent,
			Vector3.new(3.4, 0.4, 2.2),
			petal * CFrame.new(1.6, -0.5, 0) * CFrame.Angles(0, 0, math.rad(-18)),
			if i % 2 == 0 then color else WHITE,
			false
		)
	end
end

-- Cette méthode permet de poser un ballon de plage en cubes (quartiers de couleurs) lorsque l'on habille la plage ou
-- le pays des jouets.
builders.beachball = function(parent, at, rng)
	local colors = { rgb(255, 80, 80), WHITE, rgb(60, 160, 255), rgb(255, 210, 50) }
	local s = snap(rng, 1.2, 2, 0.2)
	for i = 0, 3 do
		local x, z = (i % 2 - 0.5) * s, (math.floor(i / 2) - 0.5) * s
		put(parent, at, Vector3.new(s, s * 2, s), Vector3.new(x, s, z), colors[i + 1], false)
	end
end

-- Cette méthode permet d'empiler des pneus usés en colonne (dernier à jante jaune) lorsque l'on habille la casse.
builders.tirestack = function(parent, at, rng, solid)
	local count = rng:NextInteger(2, 4)
	for i = 0, count - 1 do
		local tire = put(parent, at, Vector3.new(1.2, 4, 4), Vector3.new(0, 0.6 + i * 1.2, 0), rgb(45, 45, 50), solid)
		tire.Shape = Enum.PartType.Cylinder
		tire.CFrame = at * CFrame.new(0, 0.6 + i * 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
	put(parent, at, Vector3.new(1.8, 0.2, 1.8), Vector3.new(0, count * 1.2 + 0.1, 0), rgb(255, 210, 40), false)
end

-- Cette méthode permet de poser une épave de voiture rouillée en blocs (caisse cabossée de travers, roue tombée)
-- lorsque l'on habille la casse.
builders.wreck = function(parent, at, rng, solid)
	local colors = { rgb(170, 90, 55), rgb(95, 120, 150), rgb(140, 140, 120) }
	local color = colors[rng:NextInteger(1, #colors)]
	put(parent, at, Vector3.new(10, 2.6, 5), Vector3.new(0, 1.3, 0), color, solid, Vector3.new(0, 0, 4))
	put(
		parent,
		at,
		Vector3.new(5, 2.2, 4.4),
		Vector3.new(-0.6, 3.6, 0),
		Build.shade(color, 0.8),
		solid,
		Vector3.new(0, 6, -6)
	)
	put(parent, at, Vector3.new(1.2, 2.6, 2.6), Vector3.new(5.8, 1.3, 2.8), rgb(45, 45, 50), false)
end

-- Cette méthode permet d'empiler des cubes de jouet géants aux couleurs primaires lorsque l'on habille le pays des
-- jouets.
builders.toyblocks = function(parent, at, rng, solid)
	local colors = { rgb(235, 50, 50), rgb(50, 120, 240), rgb(255, 210, 40), rgb(60, 190, 80) }
	local size = snap(rng, 3, 4.5, 0.5)
	for i = 0, 2 do
		local offset = Vector3.new((i - 1) * size * 1.05, size / 2, 0)
		put(parent, at, Vector3.one * size, offset, colors[rng:NextInteger(1, #colors)], solid)
	end
	put(
		parent,
		at,
		Vector3.one * size,
		Vector3.new(-size * 0.5, size * 1.5, 0),
		colors[rng:NextInteger(1, #colors)],
		solid
	)
end

-- Cette méthode permet d'asseoir un ours en peluche géant en blocs (corps, tête, oreilles, museau, nœud) lorsque l'on
-- habille le pays des jouets.
builders.teddy = function(parent, at, rng, solid)
	local s = snap(rng, 0.8, 1.2, 0.2)
	local fur, light = rgb(190, 120, 65), rgb(235, 185, 130)
	put(parent, at, Vector3.new(5, 5, 4) * s, Vector3.new(0, 2.5 * s, 0), fur, solid)
	put(parent, at, Vector3.new(3, 2.4, 3) * s, Vector3.new(0, 2.2 * s, -1.2 * s), light, false)
	put(parent, at, Vector3.new(4, 4, 3.6) * s, Vector3.new(0, 7 * s, 0), fur, solid)
	for _, side in { -1, 1 } do
		put(parent, at, Vector3.new(1.4, 1.4, 1) * s, Vector3.new(side * 1.8 * s, 9.4 * s, 0), fur, false)
		put(parent, at, Vector3.new(1.6, 1.6, 2.4) * s, Vector3.new(side * 3 * s, 3 * s, -0.6 * s), fur, false)
	end
	put(parent, at, Vector3.new(1.8, 1.2, 1) * s, Vector3.new(0, 6.4 * s, -2 * s), light, false)
	put(parent, at, Vector3.new(2.4, 1, 1) * s, Vector3.new(0, 4.9 * s, -1.9 * s), rgb(235, 50, 60), false)
end

-- Cette méthode permet de construire l'élément de décor `kind` au repère `at` lorsque l'on habille une zone ;
-- `solid` = faux pour un élément que le mannequin traverse (pied des parois).
function Props.build(kind: string, parent: Instance, at: CFrame, rng: Random, solid: boolean)
	local builder = builders[kind]
	if builder then
		builder(parent, at, rng, solid)
	else
		warn("[Props] élément inconnu : " .. kind)
	end
end

-- Cette méthode permet de poser une barrière en blocs de bois (poteaux carrés, deux lisses) de `from` à `to` au sol
-- lorsque l'on clôture une base ou le bord d'une zone.
function Props.fence(parent: Instance, from: Vector3, to: Vector3)
	local delta = to - from
	local length = delta.Magnitude
	local count = math.max(1, math.floor(length / 6 + 0.5))
	local frame = CFrame.lookAt(from, to)
	for i = 0, count do
		Build.block(parent, Vector3.new(1.4, 4.4, 1.4), frame * CFrame.new(0, 2.2, -length * i / count), WOOD_DARK)
	end
	for _, y in { 1.6, 3.2 } do
		Build.block(parent, Vector3.new(0.8, 0.9, length), frame * CFrame.new(0, y, -length / 2), WOOD)
	end
end

-- Stands du hub (#68), calés sur les stands de 01 et 09 : échoppe en bois à auvent rayé, comptoir garni, marchand
-- derrière, enseigne. SHOP (bleu, haut : enseigne néon coiffée d'une tête de mannequin, vitrine, caisses) et SELL
-- (rouge, large : caisse enregistreuse, balance, sacs et liasses, pancarte de prix, pièce géante) se reconnaissent de
-- loin. Les pièces animées (marchand, mannequins exposés, pièce géante, éclat de pièces) sont marquées pour le client
-- (étiquettes de Shared.CourseLayout, animées par Client.HubShops).

local STALL_W = 16 -- largeur de l'échoppe (axe X local)

-- Cette méthode permet de poser un bloc lisse (sans tenons : plastique, néon, verre, métal) lorsque l'on assemble un
-- détail qui ne doit pas porter la texture à briques.
local function smooth(
	parent: Instance,
	at: CFrame,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material,
	solid: boolean,
	rotation: Vector3?
): Part
	local p = put(parent, at, size, offset, color, solid, rotation)
	p.Material = material
	p.MaterialVariant = ""
	return p
end

-- Cette méthode permet de construire l'échoppe commune aux deux stands (plancher, comptoir, fond, poteaux, auvent
-- `stripe` / blanc incliné avec lambrequin) au repère `at` lorsque l'on bâtit un stand du hub.
local function stall(folder: Instance, at: CFrame, stripe: Color3)
	put(folder, at, Vector3.new(STALL_W, 0.6, 10), Vector3.new(0, 0.3, 0), WOOD_DARK, true)
	put(folder, at, Vector3.new(STALL_W - 2, 4, 3), Vector3.new(0, 2.6, -3), WOOD, true)
	put(folder, at, Vector3.new(STALL_W - 1.4, 0.6, 3.6), Vector3.new(0, 4.9, -3), WOOD_DARK, true)
	-- Bandeau du comptoir à la couleur du stand, liseré blanc
	put(folder, at, Vector3.new(STALL_W - 1.8, 1.2, 0.3), Vector3.new(0, 3.4, -4.6), stripe, false)
	put(folder, at, Vector3.new(STALL_W - 1.8, 0.3, 0.32), Vector3.new(0, 2.7, -4.6), WHITE, false)
	put(folder, at, Vector3.new(STALL_W, 11, 1), Vector3.new(0, 6.1, 4.5), WOOD_DARK, true)
	for _, x in { -(STALL_W / 2 - 0.5), STALL_W / 2 - 0.5 } do
		put(folder, at, Vector3.new(1, 11.4, 1), Vector3.new(x, 6.3, -4.5), WOOD_DARK, true)
		put(folder, at, Vector3.new(1.4, 0.6, 1.4), Vector3.new(x, 0.9, -4.5), WOOD, true)
	end
	-- Auvent : lattes alternées, inclinées vers l'avant, puis festons sous le bord avant
	local slats = STALL_W / 2
	for i = 0, slats do
		local x = -STALL_W / 2 + i * 2
		smooth(
			folder,
			at,
			Vector3.new(2, 0.6, 11),
			Vector3.new(x, 12.6, -0.6),
			if i % 2 == 0 then stripe else WHITE,
			Enum.Material.SmoothPlastic,
			true,
			Vector3.new(-14, 0, 0)
		)
		smooth(
			folder,
			at,
			Vector3.new(2, 1.4, 0.4),
			Vector3.new(x, 10.9, -6.2),
			if i % 2 == 0 then stripe else WHITE,
			Enum.Material.SmoothPlastic,
			false
		)
	end
end

-- Cette méthode permet de construire un marchand en blocs (jambes, corps `shirt`, bras, tête, casquette `cap`,
-- yeux) debout au repère `at`, face à -Z, lorsque l'on garnit un stand ; marqué MERCHANT_TAG pour être animé.
local function merchant(parent: Instance, at: CFrame, shirt: Color3, cap: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Merchant"
	-- Atomique : le client l'anime d'un bloc (corps et bras arrivent ensemble, comme les pièges de Server.TrapProps)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local skin = rgb(255, 205, 150)
	local pants = rgb(50, 60, 90)
	put(model, at, Vector3.new(0.9, 2.4, 1), Vector3.new(-0.5, 1.2, 0), pants, false)
	put(model, at, Vector3.new(0.9, 2.4, 1), Vector3.new(0.5, 1.2, 0), pants, false)
	local torso = put(model, at, Vector3.new(2, 2.4, 1.1), Vector3.new(0, 3.6, 0), shirt, false)
	put(model, at, Vector3.new(1.6, 1.8, 0.2), Vector3.new(0, 3.5, -0.6), WHITE, false) -- tablier
	put(model, at, Vector3.new(0.8, 2.3, 0.9), Vector3.new(-1.45, 3.7, 0), shirt, false)
	local arm = put(model, at, Vector3.new(0.8, 2.3, 0.9), Vector3.new(1.45, 3.7, 0), shirt, false)
	arm.Name = "WaveArm"
	put(model, at, Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 5.6, 0), skin, false)
	for _, x in { -0.35, 0.35 } do
		smooth(
			model,
			at,
			Vector3.new(0.25, 0.35, 0.1),
			Vector3.new(x, 5.75, -0.82),
			rgb(25, 25, 30),
			Enum.Material.SmoothPlastic,
			false
		)
	end
	smooth(
		model,
		at,
		Vector3.new(0.7, 0.15, 0.1),
		Vector3.new(0, 5.2, -0.82),
		rgb(120, 40, 40),
		Enum.Material.SmoothPlastic,
		false
	)
	put(model, at, Vector3.new(1.8, 0.5, 1.8), Vector3.new(0, 6.6, 0), cap, false)
	put(model, at, Vector3.new(1.6, 0.25, 0.9), Vector3.new(0, 6.45, -1.2), cap, false)
	model.PrimaryPart = torso
	CollectionService:AddTag(model, CourseLayout.MERCHANT_TAG)
	model.Parent = parent
	return model
end

-- Cette méthode permet d'afficher la bulle d'appel du marchand (texte noir sur bulle blanche, pointe en bas) au point
-- `position` lorsque l'on garnit un stand.
local function bubble(parent: Instance, position: Vector3, text: string)
	local anchor =
		Build.decor({ Name = "Bubble", Size = Vector3.one, Position = position, Transparency = 1, Parent = parent })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(9, 2.2)
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Parent = anchor
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 0.8)
	frame.BackgroundColor3 = WHITE
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.82)
	tip.Size = UDim2.fromScale(0.08, 0.3)
	tip.SizeConstraint = Enum.SizeConstraint.RelativeYY
	tip.Rotation = 45
	tip.BackgroundColor3 = WHITE
	tip.BorderSizePixel = 0
	tip.ZIndex = 0
	tip.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = rgb(20, 20, 26)
	label.Text = text
	label.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.14, 0)
	padding.PaddingBottom = UDim.new(0.14, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = label
end

-- Cette méthode permet de tracer au sol, devant le comptoir, l'anneau de la couleur du stand (là où l'invite
-- s'ouvre, comme le cercle rouge devant le stand de 01) lorsque l'on bâtit un stand du hub.
local function ring(parent: Instance, at: CFrame, color: Color3)
	for i = 0, 15 do
		local angle = i * math.pi / 8
		local piece = smooth(
			parent,
			at * CFrame.new(0, 0, -7.5) * CFrame.Angles(0, angle, 0),
			Vector3.new(1.5, 0.12, 0.5),
			Vector3.new(0, 0.07, 3.6),
			color,
			Enum.Material.Neon,
			false
		)
		piece.CastShadow = false
	end
end

-- Cette méthode permet de poser une caisse en bois (cadre foncé, planches claires) de côté `s` au repère `at`
-- lorsque l'on garnit un stand.
local function crate(parent: Instance, at: CFrame, s: number)
	put(parent, at, Vector3.new(s, s, s), Vector3.new(0, s / 2, 0), WOOD, true)
	for _, y in { 0.08, 0.92 } do
		put(parent, at, Vector3.new(s + 0.1, 0.3, s + 0.1), Vector3.new(0, s * y, 0), WOOD_DARK, false)
	end
	put(
		parent,
		at,
		Vector3.new(0.3, s * 0.84, s + 0.1),
		Vector3.new(0, s / 2, 0),
		WOOD_DARK,
		false,
		Vector3.new(0, 0, 40)
	)
end

-- Cette méthode permet de poser un socle de vitrine (plateau tournant à liseré néon) dont le client fait tourner le
-- mannequin à lancer `index` (attributs Index et Scale, tag Shared.ThrowDummies.DISPLAY_TAG) lorsque l'on garnit le
-- stand SHOP.
local function turntable(parent: Instance, at: CFrame, offset: Vector3, index: number, scale: number, tag: string)
	local base = smooth(
		parent,
		at,
		Vector3.new(0.4, 2.4, 2.4),
		offset + Vector3.new(0, 0.2, 0),
		rgb(60, 64, 76),
		Enum.Material.SmoothPlastic,
		false,
		Vector3.new(0, 0, 90)
	)
	base.Shape = Enum.PartType.Cylinder
	local glow = smooth(
		parent,
		at,
		Vector3.new(0.12, 2.6, 2.6),
		offset + Vector3.new(0, 0.06, 0),
		rgb(80, 200, 255),
		Enum.Material.Neon,
		false,
		Vector3.new(0, 0, 90)
	)
	glow.Shape = Enum.PartType.Cylinder
	-- Point d'appui du mannequin exposé (pieds sur le plateau)
	local socket = Build.decor({
		Name = "Display" .. index,
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = at * CFrame.new(offset + Vector3.new(0, 0.4, 0)),
		Transparency = 1,
		Parent = parent,
	})
	socket:SetAttribute("Index", index)
	socket:SetAttribute("Scale", scale)
	CollectionService:AddTag(socket, tag)
end

export type ShopStand = { prompt: Vector3 }

-- Cette méthode permet de construire le stand SHOP (boutique de mannequins à lancer, #14) au repère `at` (face avant
-- vers -Z) : échoppe bleue, six mannequins à lancer sur plateaux tournants (comptoir et étagère), vitrine du plus
-- cher, caisses empilées dont une ouverte, enseigne néon « DUMMY SHOP » coiffée d'une tête de mannequin, marchand
-- et sa bulle, anneau au sol ; `displayTag` marque les plateaux. Renvoie la position de l'invite.
function Props.shopStand(parent: Instance, at: CFrame, displayTag: string, count: number): ShopStand
	local blue = rgb(50, 140, 255)
	local folder = Instance.new("Model")
	folder.Name = "ShopStand"
	stall(folder, at, blue)
	-- Comptoir (les 3 premiers), étagère du fond (les suivants), vitrine (le dernier), chacun sur son plateau
	put(folder, at, Vector3.new(STALL_W - 2, 0.5, 2), Vector3.new(0, 7.2, 3.1), WOOD, true)
	local shelved = count - 4
	for i = 1, count - 1 do
		local offset = if i <= 3
			then Vector3.new((i - 2) * 4.4, 5.2, -3)
			else Vector3.new((i - 4 - (shelved - 1) / 2) * 5, 7.45, 3.1)
		turntable(folder, at, offset, i, if i <= 3 then 0.5 else 0.42, displayTag)
	end
	-- Vitrine du côté gauche : socle, montants, verre, mannequin le plus cher qui tourne
	local case = at * CFrame.new(STALL_W / 2 + 3.5, 0, -1)
	put(folder, case, Vector3.new(5, 1.6, 5), Vector3.new(0, 0.8, 0), rgb(40, 44, 56), true)
	smooth(folder, case, Vector3.new(5.2, 0.3, 5.2), Vector3.new(0, 1.75, 0), blue, Enum.Material.Neon, false)
	for _, corner in
		{ Vector3.new(-2.3, 0, -2.3), Vector3.new(2.3, 0, -2.3), Vector3.new(-2.3, 0, 2.3), Vector3.new(2.3, 0, 2.3) }
	do
		put(folder, case, Vector3.new(0.5, 7, 0.5), corner + Vector3.new(0, 5.3, 0), rgb(240, 240, 245), true)
	end
	for _, side in { Vector3.new(0, 0, -2.3), Vector3.new(0, 0, 2.3), Vector3.new(-2.3, 0, 0), Vector3.new(2.3, 0, 0) } do
		local size = if side.X == 0 then Vector3.new(4.2, 6.8, 0.15) else Vector3.new(0.15, 6.8, 4.2)
		local glass =
			smooth(folder, case, size, side + Vector3.new(0, 5.3, 0), rgb(200, 235, 255), Enum.Material.Glass, true)
		glass.Transparency = 0.6
	end
	put(folder, case, Vector3.new(5.2, 0.6, 5.2), Vector3.new(0, 9, 0), rgb(240, 240, 245), true)
	turntable(folder, case, Vector3.new(0, 1.9, 0), count, 0.75, displayTag)
	-- Caisses empilées du côté droit, une ouverte d'où dépasse un bras de mannequin
	local stack = at * CFrame.new(-(STALL_W / 2 + 3), 0, -2)
	crate(folder, stack, 3)
	crate(folder, stack * CFrame.new(3.2, 0, 0.4) * CFrame.Angles(0, math.rad(12), 0), 3)
	crate(folder, stack * CFrame.new(1.4, 3, 0.2) * CFrame.Angles(0, math.rad(-8), 0), 2.6)
	put(
		folder,
		stack,
		Vector3.new(0.8, 2, 0.8),
		Vector3.new(0.4, 3.6, -0.2),
		DUMMY_YELLOW,
		false,
		Vector3.new(0, 0, -25)
	)
	put(
		folder,
		stack,
		Vector3.new(0.8, 1, 0.8),
		Vector3.new(0.8, 4.9, -0.2),
		rgb(45, 47, 55),
		false,
		Vector3.new(0, 0, -25)
	)
	-- Enseigne néon au-dessus de l'auvent : panneau sombre, cadre lumineux, tête de mannequin à cibles qui tourne
	local sign = put(folder, at, Vector3.new(STALL_W, 4.2, 0.8), Vector3.new(0, 16.6, 4.2), rgb(30, 40, 80), true)
	Build.surfaceText(sign, Enum.NormalId.Front, "DUMMY SHOP", rgb(130, 220, 255))
	for _, edge in
		{
			{ Vector3.new(STALL_W + 0.4, 0.35, 0.3), Vector3.new(0, 18.8, 3.7) },
			{ Vector3.new(STALL_W + 0.4, 0.35, 0.3), Vector3.new(0, 14.4, 3.7) },
			{ Vector3.new(0.35, 4.75, 0.3), Vector3.new(STALL_W / 2 + 0.03, 16.6, 3.7) },
			{ Vector3.new(0.35, 4.75, 0.3), Vector3.new(-STALL_W / 2 - 0.03, 16.6, 3.7) },
		}
	do
		smooth(folder, at, edge[1], edge[2], rgb(255, 220, 60), Enum.Material.Neon, false).CastShadow = false
	end
	local head = Instance.new("Model")
	head.Name = "SignHead"
	head.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- tourne d'un bloc côté client
	local skull = put(head, at, Vector3.new(4, 4, 4), Vector3.new(0, 21.4, 4.2), DUMMY_YELLOW, true)
	for _, face in { -1, 1 } do
		-- Cible de crash-test (disques noir et jaune) de chaque côté
		local disc = smooth(
			head,
			at,
			Vector3.new(0.1, 1.8, 1.8),
			Vector3.new(face * 2.02, 21.6, 4.2),
			rgb(25, 25, 30),
			Enum.Material.SmoothPlastic,
			false
		)
		disc.Shape = Enum.PartType.Cylinder
		local dot = smooth(
			head,
			at,
			Vector3.new(0.12, 0.8, 0.8),
			Vector3.new(face * 2.04, 21.6, 4.2),
			DUMMY_YELLOW,
			Enum.Material.SmoothPlastic,
			false
		)
		dot.Shape = Enum.PartType.Cylinder
	end
	for _, x in { -0.8, 0.8 } do
		smooth(
			head,
			at,
			Vector3.new(0.6, 0.8, 0.1),
			Vector3.new(x, 22, 2.17),
			rgb(25, 25, 30),
			Enum.Material.SmoothPlastic,
			false
		)
	end
	head.PrimaryPart = skull
	CollectionService:AddTag(head, CourseLayout.SPIN_TAG)
	head.Parent = folder
	merchant(folder, at * CFrame.new(-4.5, 0.6, 0.5), blue, rgb(255, 210, 40))
	bubble(folder, (at * CFrame.new(-4.5, 9.6, 0.5)).Position, "Better dummies here!")
	ring(folder, at, blue)
	folder.Parent = parent
	return { prompt = (at * CFrame.new(0, 3, -6)).Position }
end

-- Cette méthode permet de poser une liasse de billets (bloc vert, bande blanche) au repère `at` lorsque l'on garnit
-- le stand SELL.
local function bills(parent: Instance, at: CFrame, layers: number)
	for i = 0, layers - 1 do
		put(parent, at, Vector3.new(1.8, 0.35, 0.9), Vector3.new(0, 0.18 + i * 0.36, 0), rgb(90, 190, 80), false)
	end
	smooth(
		parent,
		at,
		Vector3.new(0.35, layers * 0.36 + 0.04, 0.95),
		Vector3.new(0, layers * 0.18, 0),
		WHITE,
		Enum.Material.SmoothPlastic,
		false
	)
end

-- Cette méthode permet de poser un sac d'argent (bloc toile, col noué, « $ » sur la face) de taille `s` au repère
-- `at` lorsque l'on garnit le stand SELL.
local function moneyBag(parent: Instance, at: CFrame, s: number)
	local canvas = rgb(215, 180, 110)
	local body = put(parent, at, Vector3.new(2.4, 2.2, 2.2) * s, Vector3.new(0, 1.1 * s, 0), canvas, true)
	put(parent, at, Vector3.new(1.6, 0.6, 1.6) * s, Vector3.new(0, 2.5 * s, 0), Build.shade(canvas, 0.85), false)
	put(parent, at, Vector3.new(1, 0.3, 1) * s, Vector3.new(0, 2.85 * s, 0), rgb(120, 70, 40), false)
	put(parent, at, Vector3.new(1.2, 0.8, 1.2) * s, Vector3.new(0, 3.3 * s, 0), canvas, false)
	Build.surfaceText(body, Enum.NormalId.Front, "$", rgb(60, 170, 60))
end

-- Cette méthode permet de construire le stand SELL (vente des mannequins de collection) au repère `at` (face avant vers
-- -Z) : échoppe rouge, caisse enregistreuse, balance, liasses et sacs d'argent, pancarte du prix de vente, marchand et
-- sa bulle, pièce géante qui tourne au-dessus de l'enseigne, émetteur de pièces (éclat à chaque vente), anneau au sol.
function Props.sellStand(parent: Instance, at: CFrame)
	local red = rgb(235, 45, 45)
	local gold = rgb(255, 200, 40)
	local folder = Instance.new("Model")
	folder.Name = "SellStand"
	stall(folder, at, red)
	-- Caisse enregistreuse sur le comptoir (côté gauche) : corps, écran vert incliné, touches, tiroir
	local till = at * CFrame.new(3.6, 5.2, -3)
	put(folder, till, Vector3.new(3, 1.6, 2.2), Vector3.new(0, 0.8, 0), rgb(70, 75, 90), true)
	put(folder, till, Vector3.new(3.2, 0.5, 2.4), Vector3.new(0, 0.25, -0.1), gold, false)
	smooth(
		folder,
		till,
		Vector3.new(2.4, 0.9, 0.2),
		Vector3.new(0, 2, 0.6),
		rgb(90, 230, 120),
		Enum.Material.Neon,
		false,
		Vector3.new(-20, 0, 0)
	)
	for i = 0, 5 do
		local x, z = (i % 3 - 1) * 0.7, math.floor(i / 3) * 0.5 - 0.5
		put(
			folder,
			till,
			Vector3.new(0.5, 0.2, 0.35),
			Vector3.new(x, 1.7, z),
			if i == 5 then rgb(80, 200, 80) else WHITE,
			false
		)
	end
	-- Balance dorée (côté droit) : pied, fléau, deux plateaux, l'un chargé de pièces
	local scale = at * CFrame.new(-4, 5.2, -3)
	put(folder, scale, Vector3.new(2, 0.4, 1.4), Vector3.new(0, 0.2, 0), gold, true)
	put(folder, scale, Vector3.new(0.4, 2.6, 0.4), Vector3.new(0, 1.7, 0), gold, false)
	put(folder, scale, Vector3.new(4, 0.3, 0.3), Vector3.new(0, 3, 0), gold, false, Vector3.new(0, 0, -8))
	for _, side in { -1, 1 } do
		local pan = smooth(
			folder,
			scale,
			Vector3.new(0.2, 1.6, 1.6),
			Vector3.new(side * 1.9, 2.1 + side * 0.25, 0),
			gold,
			Enum.Material.Metal,
			false,
			Vector3.new(0, 0, 90)
		)
		pan.Shape = Enum.PartType.Cylinder
	end
	for i = 0, 2 do
		local coin = smooth(
			folder,
			scale,
			Vector3.new(0.2, 0.7, 0.7),
			Vector3.new(1.9 + (i - 1) * 0.35, 2.45 + i * 0.12, 0),
			rgb(255, 225, 70),
			Enum.Material.Metal,
			false,
			Vector3.new(0, 0, 90)
		)
		coin.Shape = Enum.PartType.Cylinder
	end
	-- Liasses sur le comptoir et piles au sol, sacs d'argent devant les poteaux
	bills(folder, at * CFrame.new(0, 5.2, -2.6), 3)
	bills(folder, at * CFrame.new(0.4, 5.2, -3.6) * CFrame.Angles(0, math.rad(20), 0), 2)
	bills(folder, at * CFrame.new(5, 0.6, 2.2), 6)
	bills(folder, at * CFrame.new(-5.5, 0.6, 2.4), 4)
	moneyBag(folder, at * CFrame.new(STALL_W / 2 + 2.2, 0, -3) * CFrame.Angles(0, math.rad(-15), 0), 1.2)
	moneyBag(folder, at * CFrame.new(STALL_W / 2 + 4.4, 0, -1.2) * CFrame.Angles(0, math.rad(20), 0), 0.9)
	moneyBag(folder, at * CFrame.new(-(STALL_W / 2 + 2.4), 0, -2.4) * CFrame.Angles(0, math.rad(10), 0), 1)
	-- Pancarte du prix de vente sur deux piquets, à droite du stand
	local board = at * CFrame.new(-(STALL_W / 2 + 4.5), 0, 1) * CFrame.Angles(0, math.rad(15), 0)
	for _, x in { -2.2, 2.2 } do
		put(folder, board, Vector3.new(0.6, 5, 0.6), Vector3.new(x, 2.5, 0.2), WOOD_DARK, false)
	end
	local plank = put(folder, board, Vector3.new(6, 3.4, 0.5), Vector3.new(0, 4.8, 0), WOOD, true)
	Build.surfaceText(plank, Enum.NormalId.Front, "SELL = 2 MIN\nOF INCOME", rgb(255, 235, 120))
	-- Enseigne et pièce géante au-dessus (silhouette ronde dorée, opposée à la tête carrée du SHOP)
	local sign = put(folder, at, Vector3.new(STALL_W, 4.2, 0.8), Vector3.new(0, 16.6, 4.2), red, true)
	Build.surfaceText(sign, Enum.NormalId.Front, "SELL")
	local coin = Instance.new("Model")
	coin.Name = "GiantCoin"
	coin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- tourne d'un bloc côté client
	local disc = smooth(
		coin,
		at,
		Vector3.new(1, 6, 6),
		Vector3.new(0, 22, 4.2),
		gold,
		Enum.Material.Metal,
		true,
		Vector3.new(0, 90, 0)
	)
	disc.Shape = Enum.PartType.Cylinder
	local rim = smooth(
		coin,
		at,
		Vector3.new(1.1, 4.6, 4.6),
		Vector3.new(0, 22, 4.2),
		rgb(255, 230, 110),
		Enum.Material.Metal,
		false,
		Vector3.new(0, 90, 0)
	)
	rim.Shape = Enum.PartType.Cylinder
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local front = smooth(
			coin,
			at,
			Vector3.new(4, 4, 0.05),
			Vector3.new(0, 22, 4.2 + (if face == Enum.NormalId.Front then -0.56 else 0.56)),
			gold,
			Enum.Material.Metal,
			false
		)
		front.Transparency = 1
		Build.surfaceText(front, face, "$", rgb(255, 250, 200))
	end
	coin.PrimaryPart = disc
	CollectionService:AddTag(coin, CourseLayout.SPIN_TAG)
	coin.Parent = folder
	merchant(folder, at * CFrame.new(0, 0.6, 0.5), rgb(80, 180, 80), rgb(40, 120, 50))
	bubble(folder, (at * CFrame.new(0, 9.6, 0.5)).Position, "Sell your dummies!")
	ring(folder, at, red)
	-- Éclat de pièces : émetteur au-dessus du comptoir, déclenché par le client à chaque vente (attribut Sales)
	local burst = Build.decor({
		Name = "SellBurst",
		Size = Vector3.new(4, 0.5, 2),
		CFrame = at * CFrame.new(0, 6, -3),
		Transparency = 1,
		Parent = folder,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Coins"
	emitter.Enabled = false
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(rgb(255, 230, 80), rgb(255, 170, 30))
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.3) })
	emitter.Lifetime = NumberRange.new(0.8, 1.3)
	emitter.Speed = NumberRange.new(14, 24)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, -50, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Parent = burst
	burst:SetAttribute("Sales", 0)
	CollectionService:AddTag(burst, CourseLayout.SELL_BURST_TAG)
	folder.Parent = parent
end

-- Cette méthode permet de planter un panneau en bois (poteau, planche à texte) au repère `at` lorsque l'on annonce
-- une zone au bord de la piste.
function Props.signpost(parent: Instance, at: CFrame, text: string, color: Color3)
	put(parent, at, Vector3.new(1.2, 9, 1.2), Vector3.new(0, 4.5, 0), WOOD_DARK, false)
	local board = put(parent, at, Vector3.new(14, 4.5, 1), Vector3.new(0, 9, 0), color, false)
	Build.surfaceText(board, Enum.NormalId.Front, text)
end

return Props
