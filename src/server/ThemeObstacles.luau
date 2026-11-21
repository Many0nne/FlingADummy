-- Obstacles cassables des thèmes (#33), en blocs à tenons comme le reste du décor : chaque thème (Shared.Zones) en a 2
-- ou 3, posés à tour de rôle par Server.Obstacles aux sites de Shared.TrackPlan. Un obstacle de colonne est monté dans
-- chacune des SLOT_COUNT colonnes (un groupe de pièces par colonne), un obstacle de piste d'un seul tenant sur toute la
-- largeur des colonnes. Toutes les pièces sont légères : le mannequin les traverse et les projette.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Build = require(script.Parent.Build)

type Zone = Zones.Zone

-- Ajoute une pièce à l'obstacle en cours : propriétés de la pièce (Size, CFrame ou Position, Color…), densité, son
-- joué quand elle est projetée (« Crate » ou « Brick »)
export type Add = (props: { [string]: any }, density: number, material: string) -> ()
-- Commence un obstacle (pièces qui réapparaissent ensemble) et renvoie de quoi lui ajouter des pièces
export type Kit = { group: () -> Add }

local ThemeObstacles = {}

local LIGHT = 0.05 -- caisses, bottes, cartons : volent au moindre choc
local BRICK = 0.08 -- briques, blocs de glace, pierres
local HEAVY = 0.1 -- véhicules
local SPAN = GameConfig.SLOT_COUNT * GameConfig.SLOT_SPACING -- largeur des colonnes d'obstacles
local GAP = 0.04 -- jeu entre deux pièces posées l'une sur l'autre (jamais d'interpénétration au démarrage)

local rgb = Color3.fromRGB
local WHITE, BLACK = rgb(250, 250, 250), rgb(35, 35, 40)
local YELLOW = rgb(255, 210, 40)

-- Cette méthode permet d'ajouter un bloc (taille, centre, couleur, rotation locale en degrés) lorsque l'on assemble un
-- obstacle.
local function block(
	add: Add,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	density: number,
	material: string,
	rotation: Vector3?,
	extra: { [string]: any }?
)
	local cframe = CFrame.new(position)
	if rotation then
		cframe *= CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	end
	local props: { [string]: any } = { Name = name, Size = size, CFrame = cframe, Color = color }
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	add(props, density, material)
end

-- Cette méthode permet d'ajouter un cylindre couché (axe X, comme un rondin) ou debout (`upright`) lorsque l'on
-- assemble un obstacle ; `length` le long de l'axe, `diameter` en travers.
local function cylinder(
	add: Add,
	name: string,
	length: number,
	diameter: number,
	position: Vector3,
	color: Color3,
	density: number,
	material: string,
	upright: boolean?
)
	local rotation = if upright then Vector3.new(0, 0, 90) else nil
	block(
		add,
		name,
		Vector3.new(length, diameter, diameter),
		position,
		color,
		density,
		material,
		rotation,
		{ Shape = Enum.PartType.Cylinder }
	)
end

-- Cette méthode permet de monter un obstacle de colonne dans chaque colonne (un groupe par colonne) lorsque le site
-- est construit ; `fn` reçoit l'ajout de pièces, le centre de la colonne et son numéro.
local function eachColumn(kit: Kit, fn: (add: Add, x: number, column: number) -> ())
	for column = 1, GameConfig.SLOT_COUNT do
		fn(kit.group(), CourseLayout.slotX(column), column)
	end
end

-- Cette méthode permet de monter un mur en quinconce sur toute la largeur des colonnes (`rows` rangées de blocs
-- `brick`, deux teintes alternées) lorsque l'on construit un mur de thème ; rien en porte-à-faux.
local function staggeredWall(
	kit: Kit,
	z: number,
	brick: Vector3,
	rows: number,
	colors: { Color3 },
	density: number,
	material: string,
	extra: { [string]: any }?
)
	local add = kit.group()
	local step = brick.X + GAP
	local count = math.floor(SPAN / step)
	for row = 0, rows - 1 do
		local offset = if row % 2 == 0 then 0 else step / 2
		for col = 0, count - 1 - row % 2 do
			local x = -SPAN / 2 + step / 2 + col * step + offset
			local y = brick.Y / 2 + row * (brick.Y + GAP)
			block(
				add,
				"Block",
				brick,
				Vector3.new(x, y, z),
				colors[(row + col) % #colors + 1],
				density,
				material,
				nil,
				extra
			)
		end
	end
end

local builders: { [string]: (kit: Kit, z: number, zone: Zone) -> () } = {}

-- Prairie -----------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'empiler une tour de caisses (2 × 2, 4 étages) dans chaque colonne lorsque le site est construit.
builders.Crates = function(kit, z)
	local size = 3.6
	local colors = { rgb(235, 150, 55), rgb(210, 120, 45) }
	eachColumn(kit, function(add, x)
		for level = 0, 3 do
			for i = 0, 1 do
				for j = 0, 1 do
					local position = Vector3.new(x + (i - 0.5) * size, size / 2 + level * size, z + (j - 0.5) * size)
					block(add, "Crate", Vector3.one * size, position, colors[(i + j + level) % 2 + 1], LIGHT, "Crate")
				end
			end
		end
	end)
end

-- Cette méthode permet de dresser un panneau-cible de crash-test (damier jaune et noir de 3 × 3 plaques) dans chaque
-- colonne lorsque le site est construit.
builders.Sign = function(kit, z)
	eachColumn(kit, function(add, x)
		for row = 0, 2 do
			for col = -1, 1 do
				local position = Vector3.new(x + col * 4.62, 2.3 + row * 4.62, z)
				local color = if (row + col) % 2 == 0 then YELLOW else BLACK
				block(add, "SignPlate", Vector3.new(4.6, 4.6, 1.2), position, color, LIGHT, "Crate")
			end
		end
	end)
end

-- Cette méthode permet d'empiler des bottes de foin en pyramide (3, 2, 1) dans chaque colonne lorsque le site est
-- construit.
builders.HayBales = function(kit, z)
	local size = Vector3.new(3.9, 3, 4.6)
	local colors = { rgb(240, 200, 70), rgb(215, 170, 50) }
	eachColumn(kit, function(add, x)
		for row = 0, 2 do
			for i = 0, 2 - row do
				local position =
					Vector3.new(x + (i - (2 - row) / 2) * (size.X + GAP), size.Y / 2 + row * (size.Y + GAP), z)
				block(add, "HayBale", size, position, colors[(i + row) % 2 + 1], LIGHT, "Crate")
			end
		end
	end)
end

-- Ferme -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de garer un tracteur rouge en blocs (grandes roues arrière, petites roues et moteur à l'avant,
-- châssis, capot, cabine jaune, pot d'échappement) en travers de chaque colonne lorsque le site est construit ; chaque
-- étage repose sur le précédent.
builders.Tractor = function(kit, z)
	local red, dark = rgb(225, 50, 40), rgb(60, 60, 65)
	eachColumn(kit, function(add, x)
		block(add, "Wheel", Vector3.new(3.6, 4.4, 5.6), Vector3.new(x + 2.4, 2.2, z), BLACK, HEAVY, "Brick")
		block(add, "Wheel", Vector3.new(2.4, 2.4, 4.6), Vector3.new(x - 3.2, 1.2, z), BLACK, HEAVY, "Brick")
		block(add, "Engine", Vector3.new(3.4, 2, 3), Vector3.new(x - 3.2, 2.4 + GAP + 1, z), dark, HEAVY, "Brick")
		local deck = 4.4 + GAP -- dessus des roues arrière et du moteur
		block(add, "Chassis", Vector3.new(10, 0.8, 3.6), Vector3.new(x - 0.4, deck + 0.4, z), red, HEAVY, "Brick")
		local floor = deck + 0.8 + GAP
		block(add, "Hood", Vector3.new(4.4, 1.6, 3), Vector3.new(x - 2.8, floor + 0.8, z), red, HEAVY, "Brick")
		block(add, "Cabin", Vector3.new(3.6, 3.4, 3.4), Vector3.new(x + 2.4, floor + 1.7, z), YELLOW, HEAVY, "Brick")
		block(
			add,
			"Roof",
			Vector3.new(4.2, 0.6, 4),
			Vector3.new(x + 2.4, floor + 3.4 + GAP + 0.3, z),
			red,
			HEAVY,
			"Brick"
		)
		local exhaust = Vector3.new(x - 3.6, floor + 1.6 + GAP + 1.2, z + 0.9)
		block(add, "Exhaust", Vector3.new(0.6, 2.4, 0.6), exhaust, dark, HEAVY, "Brick")
	end)
end

-- Cette méthode permet de planter une clôture de ferme en planches (panneaux blancs et rouges entre des poteaux) sur
-- toute la largeur des colonnes lorsque le site est construit.
builders.Fence = function(kit, z)
	local add = kit.group()
	local panels = 14
	local width = SPAN / panels
	for i = 0, panels do
		local x = -SPAN / 2 + i * width
		block(add, "Post", Vector3.new(0.9, 5.4, 0.9), Vector3.new(x, 2.7, z), rgb(185, 130, 75), LIGHT, "Crate")
	end
	for i = 0, panels - 1 do
		local x = -SPAN / 2 + (i + 0.5) * width
		local color = if i % 2 == 0 then WHITE else rgb(210, 55, 45)
		block(add, "Panel", Vector3.new(width - 0.9 - GAP, 4, 0.5), Vector3.new(x, 2, z), color, LIGHT, "Crate")
	end
end

-- Forêt -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'empiler des rondins équarris en pyramide (3, 2, 1, chacun sur deux du dessous, bouts clairs)
-- dans chaque colonne lorsque le site est construit ; des blocs plutôt que des cylindres, qui rouleraient.
builders.Logs = function(kit, z)
	local side = 2.8
	local colors = { rgb(150, 95, 50), rgb(125, 80, 45) }
	eachColumn(kit, function(add, x)
		for row = 0, 2 do
			for i = 0, 2 - row do
				local offset = (i - (2 - row) / 2) * (side + GAP)
				local position = Vector3.new(x, side / 2 + row * (side + GAP), z + offset)
				block(add, "Log", Vector3.new(11, side, side), position, colors[(i + row) % 2 + 1], BRICK, "Crate")
			end
		end
	end)
end

-- Cette méthode permet de poser deux ruches en caisses empilées (corps jaunes et blancs, toit brun) dans chaque
-- colonne lorsque le site est construit.
builders.Beehives = function(kit, z)
	local colors = { YELLOW, WHITE, rgb(255, 180, 40) }
	eachColumn(kit, function(add, x)
		for _, side in { -1, 1 } do
			local cx = x + side * 3
			local y = 0
			for level = 1, 3 do
				local height = 2.2
				block(
					add,
					"Hive",
					Vector3.new(4.6, height, 4.6),
					Vector3.new(cx, y + height / 2, z),
					colors[level],
					LIGHT,
					"Crate"
				)
				y += height + GAP
			end
			block(
				add,
				"Roof",
				Vector3.new(5.4, 0.8, 5.4),
				Vector3.new(cx, y + 0.4, z),
				rgb(140, 90, 50),
				LIGHT,
				"Crate"
			)
		end
	end)
end

-- Plage -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de bâtir un château de sable (socle, quatre tours, donjon) dans chaque colonne lorsque le site
-- est construit.
builders.Sandcastle = function(kit, z)
	local sand, dark = rgb(245, 210, 130), rgb(220, 180, 100)
	eachColumn(kit, function(add, x)
		for _, side in { -1, 1 } do
			block(add, "Base", Vector3.new(5.4, 2.4, 7), Vector3.new(x + side * 2.72, 1.2, z), sand, LIGHT, "Crate")
		end
		for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
			local position = Vector3.new(x + corner.X * 4.1, 2.4 + GAP + 2, z + corner.Z * 2.4)
			block(add, "Tower", Vector3.new(2.2, 4, 2.2), position, dark, LIGHT, "Crate")
		end
		block(add, "Keep", Vector3.new(3.6, 5.6, 3.6), Vector3.new(x, 2.4 + GAP + 2.8, z), sand, LIGHT, "Crate")
		block(add, "Flag", Vector3.new(1.6, 1.2, 0.3), Vector3.new(x, 8.24 + 0.6, z), rgb(235, 60, 60), LIGHT, "Crate")
	end)
end

-- Cette méthode permet de dresser une rangée de planches de surf debout (couleurs vives, liseré blanc) dans chaque
-- colonne lorsque le site est construit.
builders.Surfboards = function(kit, z)
	local colors = { rgb(255, 90, 90), rgb(60, 190, 240), rgb(255, 200, 50), rgb(120, 220, 110) }
	eachColumn(kit, function(add, x, column)
		for i = 0, 3 do
			local position = Vector3.new(x + (i - 1.5) * 3, 4.5, z)
			block(add, "Surfboard", Vector3.new(2.4, 9, 0.9), position, colors[(i + column) % 4 + 1], LIGHT, "Crate")
		end
	end)
end

-- Désert ------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'empiler des tonneaux debout (2 × 2, deux étages, bois et rouge) dans chaque colonne lorsque
-- le site est construit.
builders.Barrels = function(kit, z)
	local colors = { rgb(165, 105, 55), rgb(210, 70, 50) }
	local height, diameter = 3.6, 3.4
	eachColumn(kit, function(add, x)
		for level = 0, 1 do
			for i = 0, 1 do
				for j = 0, 1 do
					local position =
						Vector3.new(x + (i - 0.5) * 3.6, height / 2 + level * (height + GAP), z + (j - 0.5) * 3.6)
					cylinder(
						add,
						"Barrel",
						height,
						diameter,
						position,
						colors[(i + j + level) % 2 + 1],
						LIGHT,
						"Crate",
						true
					)
				end
			end
		end
	end)
end

-- Cette méthode permet de planter un grand cactus en tronçons (deux bras, fleur rose) dans chaque colonne lorsque le
-- site est construit.
builders.Cactus = function(kit, z)
	local green, light = rgb(70, 175, 70), rgb(95, 200, 85)
	eachColumn(kit, function(add, x)
		for level = 0, 3 do
			local color = if level % 2 == 0 then green else light
			block(
				add,
				"Cactus",
				Vector3.new(2.6, 2.6, 2.6),
				Vector3.new(x, 1.3 + level * (2.6 + GAP), z),
				color,
				LIGHT,
				"Crate"
			)
		end
		for _, side in { -1, 1 } do
			-- Bras posé sur le tronçon du bas qui dépasse : coude puis avant-bras
			block(add, "Arm", Vector3.new(4.6, 1.8, 1.8), Vector3.new(x + side * 3.6, 0.9, z), green, LIGHT, "Crate")
			block(
				add,
				"Arm",
				Vector3.new(1.8, 3.4, 1.8),
				Vector3.new(x + side * 5, 1.8 + GAP + 1.7, z),
				light,
				LIGHT,
				"Crate"
			)
		end
		block(
			add,
			"Flower",
			Vector3.new(1.4, 0.8, 1.4),
			Vector3.new(x, 4 * 2.64 + 0.4, z),
			rgb(255, 110, 190),
			LIGHT,
			"Crate"
		)
	end)
end

-- Chantier ----------------------------------------------------------------------------------------------------------

-- Cette méthode permet de monter un échafaudage (montants gris, deux planchers orange, plinthe) dans chaque colonne
-- lorsque le site est construit.
builders.Scaffolding = function(kit, z)
	local pole, deck = rgb(150, 155, 165), rgb(255, 140, 30)
	eachColumn(kit, function(add, x)
		local y = 0
		for _ = 1, 2 do
			for _, corner in
				{ Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) }
			do
				local position = Vector3.new(x + corner.X * 4.4, y + 2.5, z + corner.Z * 1.8)
				block(add, "Pole", Vector3.new(0.7, 5, 0.7), position, pole, LIGHT, "Brick")
			end
			y += 5 + GAP
			block(add, "Deck", Vector3.new(10.4, 0.6, 4.6), Vector3.new(x, y + 0.3, z), deck, LIGHT, "Crate")
			y += 0.6 + GAP
		end
		block(add, "Board", Vector3.new(10.4, 1.2, 0.4), Vector3.new(x, y + 0.6, z - 2.1), YELLOW, LIGHT, "Crate")
	end)
end

-- Cette méthode permet de monter un mur de briques en quinconce (7 rangées) sur toute la largeur des colonnes lorsque
-- le site est construit.
builders.Wall = function(kit, z)
	staggeredWall(kit, z, Vector3.new(3.96, 3, 2.5), 7, { rgb(230, 60, 50), rgb(250, 120, 40) }, BRICK, "Brick")
end

-- Cette méthode permet d'aligner des plots de chantier (socle noir, cône orange à bande blanche) dans chaque colonne
-- lorsque le site est construit.
builders.Cones = function(kit, z)
	local orange = rgb(255, 120, 20)
	eachColumn(kit, function(add, x)
		for i = 0, 2 do
			for j = 0, 1 do
				local cx, cz = x + (i - 1) * 3.6, z + (j - 0.5) * 3.6
				block(add, "ConeBase", Vector3.new(3, 0.5, 3), Vector3.new(cx, 0.25, cz), BLACK, LIGHT, "Crate")
				local color = if (i + j) % 2 == 0 then orange else WHITE
				block(
					add,
					"Cone",
					Vector3.new(1.8, 3.2, 1.8),
					Vector3.new(cx, 0.5 + GAP + 1.6, cz),
					color,
					LIGHT,
					"Crate"
				)
			end
		end
	end)
end

-- Casse -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de garer une voiture-cible cabossée (roues, caisse aux couleurs passées, cabine, cible de
-- crash-test sur le toit) en travers de chaque colonne lorsque le site est construit.
builders.Car = function(kit, z)
	local colors = { rgb(70, 130, 220), rgb(215, 170, 50), rgb(200, 70, 70), rgb(90, 175, 110) }
	eachColumn(kit, function(add, x, column)
		local color = colors[(column - 1) % #colors + 1]
		for _, wx in { -3.4, 3.4 } do
			block(add, "Wheel", Vector3.new(2.4, 2.4, 5.2), Vector3.new(x + wx, 1.2, z), BLACK, HEAVY, "Brick")
		end
		block(add, "Chassis", Vector3.new(11, 2.4, 5), Vector3.new(x, 3.6, z), color, HEAVY, "Brick")
		block(
			add,
			"Cabin",
			Vector3.new(6, 2.6, 4.6),
			Vector3.new(x - 0.5, 6.1, z),
			Build.shade(color, 0.85),
			HEAVY,
			"Brick"
		)
		block(add, "Target", Vector3.new(3.6, 0.6, 3.6), Vector3.new(x - 0.5, 7.7, z), WHITE, HEAVY, "Brick")
		block(
			add,
			"Bullseye",
			Vector3.new(1.6, 0.6, 1.6),
			Vector3.new(x - 0.5, 8.3, z),
			rgb(235, 40, 40),
			HEAVY,
			"Brick"
		)
	end)
end

-- Cette méthode permet d'empiler deux piles de pneus (le dernier à jante jaune) dans chaque colonne lorsque le site
-- est construit.
builders.Tires = function(kit, z)
	eachColumn(kit, function(add, x)
		for _, side in { -1, 1 } do
			for level = 0, 3 do
				local position = Vector3.new(x + side * 2.8, 0.7 + level * (1.4 + GAP), z)
				local color = if level == 3 then YELLOW else rgb(45, 45, 50)
				cylinder(add, "Tire", 1.4, 4.6, position, color, LIGHT, "Brick", true)
			end
		end
	end)
end

-- Neige -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de dresser deux bonshommes de neige (trois boules, chapeau) dans chaque colonne lorsque le site
-- est construit.
builders.Snowmen = function(kit, z)
	eachColumn(kit, function(add, x)
		for _, side in { -1, 1 } do
			local cx = x + side * 3
			block(add, "Snow", Vector3.new(4, 4, 4), Vector3.new(cx, 2, z), WHITE, LIGHT, "Crate")
			block(add, "Snow", Vector3.new(3, 3, 3), Vector3.new(cx, 4 + GAP + 1.5, z), WHITE, LIGHT, "Crate")
			block(add, "Snow", Vector3.new(2.2, 2.2, 2.2), Vector3.new(cx, 7 + 2 * GAP + 1.1, z), WHITE, LIGHT, "Crate")
			block(
				add,
				"Hat",
				Vector3.new(1.8, 1.4, 1.8),
				Vector3.new(cx, 9.2 + 3 * GAP + 0.7, z),
				BLACK,
				LIGHT,
				"Crate"
			)
		end
	end)
end

-- Cette méthode permet de monter un mur de blocs de glace translucides (4 rangées) sur toute la largeur des colonnes
-- lorsque le site est construit.
builders.IceWall = function(kit, z)
	local colors = { rgb(175, 225, 255), rgb(140, 205, 250) }
	staggeredWall(kit, z, Vector3.new(4, 4, 3), 4, colors, BRICK, "Brick", { Transparency = 0.2, Reflectance = 0.1 })
end

-- Volcan ------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'entasser des rochers de basalte (2 × 2, deux étages) dont deux brûlants (lave) dans chaque
-- colonne lorsque le site est construit.
builders.LavaRocks = function(kit, z)
	local basalt = rgb(70, 50, 55)
	eachColumn(kit, function(add, x)
		for level = 0, 1 do
			for i = 0, 1 do
				for j = 0, 1 do
					local size = 4 - level * 0.6
					local position =
						Vector3.new(x + (i - 0.5) * 4.2, 2 + level * (4 + GAP) - level * 0.3, z + (j - 0.5) * 4.2)
					local hot = (i + j + level) % 3 == 0
					local extra = if hot then { Material = Enum.Material.Neon } else nil
					local color = if hot then rgb(255, 110, 20) else Build.shade(basalt, 1 + 0.1 * ((i + j) % 2))
					block(add, "Rock", Vector3.one * size, position, color, BRICK, "Brick", nil, extra)
				end
			end
		end
	end)
end

-- Cette méthode permet de monter un mur de basalte veiné de lave (5 rangées de gros blocs) sur toute la largeur des
-- colonnes lorsque le site est construit.
builders.BasaltWall = function(kit, z)
	local colors = { rgb(75, 55, 60), rgb(95, 65, 65), rgb(75, 55, 60), rgb(255, 100, 25) }
	staggeredWall(kit, z, Vector3.new(5.5, 3.2, 3), 5, colors, BRICK, "Brick")
end

-- Bonbons -----------------------------------------------------------------------------------------------------------

-- Cette méthode permet de planter deux sucres d'orge géants rayés (tronçons rouges et blancs, crosse) dans chaque
-- colonne lorsque le site est construit.
builders.CandyCanes = function(kit, z)
	local red = rgb(235, 40, 50)
	eachColumn(kit, function(add, x)
		for _, side in { -1, 1 } do
			local cx = x + side * 3
			for level = 0, 3 do
				local color = if level % 2 == 0 then red else WHITE
				block(
					add,
					"Cane",
					Vector3.new(1.8, 2.4, 1.8),
					Vector3.new(cx, 1.2 + level * (2.4 + GAP), z),
					color,
					LIGHT,
					"Crate"
				)
			end
			-- Crosse : un bloc qui déborde vers l'extérieur, centre de gravité au-dessus du sucre d'orge
			local top = 4 * (2.4 + GAP)
			block(
				add,
				"Hook",
				Vector3.new(3, 1.8, 1.8),
				Vector3.new(cx + side * 0.6, top + 0.9, z),
				WHITE,
				LIGHT,
				"Crate"
			)
		end
	end)
end

-- Cette méthode permet de monter un mur de guimauves (gros cubes rose, blanc et menthe, 3 rangées) sur toute la
-- largeur des colonnes lorsque le site est construit.
builders.MarshmallowWall = function(kit, z)
	local colors = { rgb(255, 190, 220), WHITE, rgb(170, 245, 215) }
	staggeredWall(kit, z, Vector3.new(4.6, 4.6, 4.6), 3, colors, LIGHT, "Crate")
end

-- Jouets ------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'empiler des cubes de jouet aux couleurs primaires (2 × 2, puis 2, puis 1) dans chaque colonne
-- lorsque le site est construit.
builders.ToyBlocks = function(kit, z)
	local colors = { rgb(235, 50, 50), rgb(50, 120, 240), YELLOW, rgb(60, 190, 80) }
	local size = 3.8
	eachColumn(kit, function(add, x, column)
		local n = 0
		-- Cette méthode permet de poser un cube de jouet à la position donnée lorsque l'on monte la pile.
		local function cube(position: Vector3)
			n += 1
			block(add, "ToyBlock", Vector3.one * size, position, colors[(n + column) % #colors + 1], LIGHT, "Crate")
		end
		for i = 0, 1 do
			for j = 0, 1 do
				cube(Vector3.new(x + (i - 0.5) * (size + GAP), size / 2, z + (j - 0.5) * (size + GAP)))
			end
		end
		for i = 0, 1 do
			cube(Vector3.new(x + (i - 0.5) * (size + GAP), size * 1.5 + GAP, z))
		end
		cube(Vector3.new(x, size * 2.5 + 2 * GAP, z))
	end)
end

-- Cette méthode permet d'aligner trois soldats de plomb (bottes, veste rouge, tête, shako noir) dans chaque colonne
-- lorsque le site est construit.
builders.ToySoldiers = function(kit, z)
	eachColumn(kit, function(add, x)
		for i = -1, 1 do
			local cx = x + i * 3.6
			block(add, "Legs", Vector3.new(2, 2.6, 1.6), Vector3.new(cx, 1.3, z), rgb(40, 70, 170), LIGHT, "Crate")
			block(
				add,
				"Coat",
				Vector3.new(2.4, 2.6, 1.8),
				Vector3.new(cx, 2.6 + GAP + 1.3, z),
				rgb(220, 40, 45),
				LIGHT,
				"Crate"
			)
			local head = Vector3.new(cx, 5.2 + 2 * GAP + 0.8, z)
			block(add, "Head", Vector3.new(1.6, 1.6, 1.6), head, rgb(255, 205, 160), LIGHT, "Crate")
			local hat = Vector3.new(cx, 6.8 + 3 * GAP + 1, z)
			block(add, "Shako", Vector3.new(1.8, 2, 1.8), hat, BLACK, LIGHT, "Crate")
		end
	end)
end

-- Base lunaire ------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser un satellite en blocs (corps, panneaux solaires en travers, parabole, antenne) dans
-- chaque colonne lorsque le site est construit.
builders.Satellites = function(kit, z)
	local silver, panel = rgb(205, 210, 220), rgb(60, 110, 230)
	eachColumn(kit, function(add, x)
		block(add, "Leg", Vector3.new(4.4, 1.2, 4.4), Vector3.new(x, 0.6, z), rgb(120, 120, 135), BRICK, "Brick")
		block(add, "Body", Vector3.new(3.6, 3.6, 3.6), Vector3.new(x, 1.2 + GAP + 1.8, z), silver, BRICK, "Brick")
		block(add, "Panels", Vector3.new(11, 0.4, 3), Vector3.new(x, 4.8 + 2 * GAP + 0.2, z), panel, LIGHT, "Brick")
		block(add, "Dish", Vector3.new(3.4, 0.8, 3.4), Vector3.new(x, 5.2 + 3 * GAP + 0.4, z), WHITE, LIGHT, "Brick")
		block(
			add,
			"Antenna",
			Vector3.new(0.5, 2.4, 0.5),
			Vector3.new(x, 6 + 4 * GAP + 1.2, z),
			rgb(235, 60, 60),
			LIGHT,
			"Brick"
		)
	end)
end

-- Cette méthode permet de garer un rover lunaire (six roues, caisse blanche, cabine bleue, antenne) en travers de
-- chaque colonne lorsque le site est construit.
builders.Rover = function(kit, z)
	eachColumn(kit, function(add, x)
		for _, wx in { -3.6, 0, 3.6 } do
			block(
				add,
				"Wheel",
				Vector3.new(2.2, 2.2, 5.4),
				Vector3.new(x + wx, 1.1, z),
				rgb(90, 90, 100),
				HEAVY,
				"Brick"
			)
		end
		block(add, "Body", Vector3.new(10.4, 1.8, 4.6), Vector3.new(x, 2.2 + GAP + 0.9, z), WHITE, HEAVY, "Brick")
		block(
			add,
			"Cabin",
			Vector3.new(4, 2.4, 4),
			Vector3.new(x + 1.6, 4 + 2 * GAP + 1.2, z),
			rgb(90, 190, 255),
			HEAVY,
			"Brick"
		)
		block(
			add,
			"Antenna",
			Vector3.new(0.4, 3, 0.4),
			Vector3.new(x - 3.4, 4 + 2 * GAP + 1.5, z),
			YELLOW,
			HEAVY,
			"Brick"
		)
	end)
end

-- Cette méthode permet de construire l'obstacle `name` du thème `zone` au site `z` lorsque la piste est construite ;
-- `kit` fournit les groupes de pièces (Server.Obstacles).
function ThemeObstacles.build(name: string, kit: Kit, z: number, zone: Zone)
	local builder = builders[name]
	if builder then
		builder(kit, z, zone)
	else
		warn("[ThemeObstacles] obstacle inconnu : " .. name)
	end
end

return ThemeObstacles
