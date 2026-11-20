-- Décor voxel au style des jeux de référence (01 / 09) : arbres et rochers en blocs à tenons, végétation et objets de
-- chaque zone, barrières en blocs, stands à auvents rayés, panneaux. Chaque élément est posé au repère `at` (au sol,
-- face avant vers -Z de `at`) et ne contient que des blocs ancrés.
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

-- Cette méthode permet de construire un stand à auvent rayé (comptoir en bois, auvent `stripe` / blanc, enseigne)
-- au repère `at` (face avant vers -Z) lorsque l'on habille le hub ; renvoie l'enseigne.
function Props.stand(parent: Instance, at: CFrame, title: string, stripe: Color3, signColor: Color3): BasePart
	local folder = Instance.new("Model")
	folder.Name = "Stand"
	put(folder, at, Vector3.new(12, 4, 4), Vector3.new(0, 2, -2), WOOD, true)
	put(folder, at, Vector3.new(12.4, 0.6, 4.4), Vector3.new(0, 4.3, -2), WOOD_DARK, true)
	put(folder, at, Vector3.new(12, 8, 1), Vector3.new(0, 4, 3), WOOD_DARK, true)
	for _, x in { -5.5, 5.5 } do
		put(folder, at, Vector3.new(1, 10, 1), Vector3.new(x, 5, -3.5), WOOD_DARK, true)
	end
	-- Auvent : lattes alternées, inclinées vers l'avant
	for i = 0, 6 do
		local slat = put(
			folder,
			at,
			Vector3.new(2, 0.6, 9),
			Vector3.new(-6 + i * 2, 11, -0.5),
			if i % 2 == 0 then stripe else WHITE,
			true,
			Vector3.new(-14, 0, 0)
		)
		slat.Material = Enum.Material.SmoothPlastic
		slat.MaterialVariant = ""
	end
	-- Lambrequin : festons sous le bord avant
	for i = 0, 6 do
		put(
			folder,
			at,
			Vector3.new(2, 1.2, 0.4),
			Vector3.new(-6 + i * 2, 9.4, -5),
			if i % 2 == 0 then stripe else WHITE,
			false
		)
	end
	local sign = put(folder, at, Vector3.new(14, 3.6, 0.8), Vector3.new(0, 14.5, 2.5), signColor, true)
	Build.surfaceText(sign, Enum.NormalId.Front, title)
	folder.Parent = parent
	return sign
end

-- Cette méthode permet de planter un panneau en bois (poteau, planche à texte) au repère `at` lorsque l'on annonce
-- une zone au bord de la piste.
function Props.signpost(parent: Instance, at: CFrame, text: string, color: Color3)
	put(parent, at, Vector3.new(1.2, 9, 1.2), Vector3.new(0, 4.5, 0), WOOD_DARK, false)
	local board = put(parent, at, Vector3.new(14, 4.5, 1), Vector3.new(0, 9, 0), color, false)
	Build.surfaceText(board, Enum.NormalId.Front, text)
end

return Props
