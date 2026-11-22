-- Plan de la carte (logique pure, testée) : places des joueurs (bases, appareil d'entraînement devant chaque base),
-- stands, tableaux de scores et zone d'événement du hub, bande de lancer commune (où se fige chaque joueur), colonnes
-- des obstacles partagés, gradins du canyon. Repère :
-- piste vers +Z, départ à z = 0, hub derrière (z < 0) ; +X est à gauche quand on regarde la piste.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local CourseLayout = {}

-- Hub (#120) : rangée de SLOT_COUNT bases côte à côte, entrée tournée vers la bande (+Z), comme les jardins de 09 ;
-- devant chaque base, son appareil d'entraînement et son pad d'achat ; au bord de la bande, dos à la paroi du départ,
-- les stands à gauche (+X), les tableaux de scores puis la zone d'événement à droite (-X).
CourseLayout.HUB_FRONT = -GameConfig.LAUNCH_DEPTH -- bord du hub côté bande (z)
CourseLayout.HUB_BACK = CourseLayout.HUB_FRONT - GameConfig.HUB_DEPTH -- fond du hub (z)
CourseLayout.ENTRANCE = Vector3.zAxis -- les entrées des bases regardent la bande
CourseLayout.BASE_SIZE = Vector3.new(40, 0, 34) -- largeur le long de l'entrée (X), profondeur (Z)
CourseLayout.BASE_PITCH = 48 -- d'un centre de base au suivant : 8 studs de passage entre deux clôtures
CourseLayout.BASE_FRONT = -62 -- clôture d'entrée des bases (z) : place pour les appareils, une allée, puis les stands
-- Présentoirs par base : GameConfig.DISPLAY_START au départ (2 rangées de 3), puis achetés au pad jusqu'à DISPLAY_MAX
CourseLayout.DISPLAY_MAX = GameConfig.DISPLAY_START + #GameConfig.DISPLAY_PRICES
CourseLayout.PAD_SHIFT = 12 -- pad d'achat de présentoir : de l'autre côté de l'entrée que l'appareil (vers -X)
CourseLayout.PAD_GAP = 6 -- de la clôture d'entrée au pad d'achat de présentoir (studs)
CourseLayout.BASE_REACH = 12 -- bouton AUTO de pose : dans la base ou à moins de 12 studs de sa clôture
CourseLayout.STATION_GAP = 10 -- de la clôture d'entrée de la base au centre de son appareil d'entraînement (studs)
CourseLayout.STATION_SHIFT = 12 -- décalage de l'appareil sur le côté de l'entrée (vers +X : à gauche en sortant)
CourseLayout.STATION_SIZE = 9 -- côté du podium de l'appareil

-- Bord de la bande : stands et tableaux adossés à la paroi du départ (z = HUB_FRONT), tournés vers les bases (-Z)
local STAND_BACK = 6 -- de la paroi au repère d'un stand (le fond de l'échoppe est 5 studs derrière le repère)
-- Emprise au sol d'un stand autour de son repère (échoppe, vitrine ou pancarte sur les côtés, anneau devant)
CourseLayout.STAND_SIZE = Vector3.new(32, 0, 17)
local STAND_DEPTH_SHIFT = -3 -- centre de l'emprise devant le repère (l'anneau dépasse plus que le fond)
local STAND_X = { shop = 58, sell = 92 } -- SHOP au plus près de la bande, SELL ensuite
CourseLayout.BOARD_SIZE = Vector3.new(16, 0, 3) -- emprise d'un tableau de scores (panneau sur deux poteaux)
local BOARD_X = { -51, -69, -87 } -- LONGEST THROW au plus près de la bande, puis INCOME et REBIRTHS
local BOARD_BACK = 2 -- de la paroi au centre de l'emprise d'un tableau
CourseLayout.EVENT_SIZE = Vector3.new(28, 0, 28) -- zone d'événement réservée (dallage vide et pancarte)
local EVENT_X = -112
CourseLayout.SPAWN = Vector3.new(0, 0, -40) -- point d'apparition de secours (avant qu'une place soit donnée), au sol

-- Bande de lancer : toute la largeur de la piste, de z = -BAND_DEPTH au départ (z = 0), au ras du sol
CourseLayout.BAND_TOP = 0
CourseLayout.EDGE_RISE = 0.25 -- le liseré blanc dépasse un peu du sol
CourseLayout.BAND_Z = -GameConfig.BAND_DEPTH / 2 -- milieu de la bande (points de lancer de test, flèche)
CourseLayout.BAND_EDGE = 1.2 -- liseré blanc, côté piste (z de 0 à BAND_EDGE), compté comme bande
CourseLayout.BAND_REACH = 8 -- hauteur au-dessus de la bande où l'avatar compte comme posé dessus (studs)
CourseLayout.BAND_SHINE_TAG = "LaunchBandShine" -- dégradé du reflet de la bande, que chaque client fait glisser

-- Décor animé des stands du hub (#68), construit par Server.Props et animé par chaque client (Client.HubShops)
CourseLayout.MERCHANT_TAG = "HubMerchant" -- marchand en blocs (il se balance et salue)
CourseLayout.SPIN_TAG = "HubSpin" -- modèle qui tourne sur lui-même (pièce géante, tête de l'enseigne)
CourseLayout.SELL_BURST_TAG = "SellBurst" -- émetteur de pièces du stand SELL (attribut Sales : une vente de plus)
-- Confettis d'une base ou d'un appareil d'entraînement (attribut Upgrades : un présentoir ou un Training Gear acheté)
CourseLayout.UPGRADE_BURST_TAG = "UpgradeBurst"

-- Couleur de chaque place (base, appareil) : on retrouve ses affaires d'un coup d'œil
CourseLayout.SLOT_COLORS = {
	Color3.fromRGB(255, 75, 75),
	Color3.fromRGB(60, 150, 255),
	Color3.fromRGB(70, 210, 90),
	Color3.fromRGB(190, 100, 255),
}

CourseLayout.TIER_COUNT = 3 -- marches des parois du canyon
CourseLayout.TIER_HEIGHT = 12
CourseLayout.TIER_STEP = 10 -- recul de chaque marche (studs)
CourseLayout.OUTER = 220 -- bord extérieur (|x|) du plateau au-dessus des gradins

-- Cette méthode permet de donner l'abscisse de la place `index` (1 à SLOT_COUNT, centrées sur x = 0) lorsque l'on
-- pose une colonne d'obstacles ou le point de lancer d'un mannequin de test.
function CourseLayout.slotX(index: number): number
	return (index - (GameConfig.SLOT_COUNT + 1) / 2) * GameConfig.SLOT_SPACING
end

-- Cette méthode permet de donner le point, au sol sur la ligne de la bande, d'où partent les mannequins de test de la
-- place `index` (Studio) et les lancers dont l'avatar manque.
function CourseLayout.launchPoint(index: number): Vector3
	return Vector3.new(CourseLayout.slotX(index), 0, CourseLayout.BAND_Z)
end

-- Cette méthode permet de savoir si un avatar (position de son HumanoidRootPart) est au-dessus de la bande de lancer
-- lorsque le serveur cherche les joueurs à figer.
function CourseLayout.isOnBand(position: Vector3): boolean
	return math.abs(position.X) <= GameConfig.TRACK_WIDTH / 2
		and position.Z >= -GameConfig.BAND_DEPTH
		and position.Z <= CourseLayout.BAND_EDGE
		and position.Y <= CourseLayout.BAND_TOP + CourseLayout.BAND_REACH
end

-- Cette méthode permet de donner la profondeur où figer un joueur entré sur la bande en `z` : la sienne, ramenée à
-- BAND_MARGIN des bords (hub et piste).
function CourseLayout.bandDepth(z: number): number
	return math.clamp(z, -GameConfig.BAND_DEPTH + GameConfig.BAND_MARGIN, -GameConfig.BAND_MARGIN)
end

-- Cette méthode permet de donner l'abscisse où figer un joueur entré sur la bande en `x` (voisins figés en `taken`) :
-- la plus proche de `x` à BAND_SPACING de chacun, dans les bords (BAND_MARGIN) ; nil si la bande est pleine.
function CourseLayout.bandSpot(x: number, taken: { number }): number?
	local limit = GameConfig.TRACK_WIDTH / 2 - GameConfig.BAND_MARGIN
	local spacing = GameConfig.BAND_SPACING
	-- Candidats : l'entrée elle-même, et juste à côté de chaque joueur déjà figé
	local candidates = { math.clamp(x, -limit, limit) }
	for _, other in taken do
		table.insert(candidates, other - spacing)
		table.insert(candidates, other + spacing)
	end
	local best, bestDistance = nil, math.huge
	for _, candidate in candidates do
		if math.abs(candidate) > limit + 1e-6 then
			continue
		end
		local free = true
		for _, other in taken do
			if math.abs(candidate - other) < spacing - 1e-6 then
				free = false
				break
			end
		end
		local distance = math.abs(candidate - x)
		if free and distance < bestDistance then
			best, bestDistance = candidate, distance
		end
	end
	return best
end

-- Cette méthode permet de donner le centre, au sol, de la base du joueur de la place `index` : bases côte à côte, dans
-- l'ordre des places (la place 1 à droite, comme sa colonne d'obstacles), entrée tournée vers la bande.
function CourseLayout.basePosition(index: number): Vector3
	local x = (index - (GameConfig.SLOT_COUNT + 1) / 2) * CourseLayout.BASE_PITCH
	return Vector3.new(x, 0, CourseLayout.BASE_FRONT - CourseLayout.BASE_SIZE.Z / 2)
end

-- Cette méthode permet de savoir si un point est dans la base `index` ou à moins de BASE_REACH studs de sa clôture
-- avant ou arrière (au sol, hauteur ignorée ; sur les côtés, pas au-delà du milieu du passage vers la base voisine)
-- lorsque le bouton AUTO de pose s'affiche ou que le serveur le valide.
function CourseLayout.isNearBase(index: number, position: Vector3): boolean
	local center = CourseLayout.basePosition(index)
	local reach = CourseLayout.BASE_REACH
	-- Un peu moins que le demi-passage : le milieu du passage n'est près d'aucune des deux bases
	local side = math.min(reach, (CourseLayout.BASE_PITCH - CourseLayout.BASE_SIZE.X) / 2 - 0.5)
	return math.abs(position.X - center.X) <= CourseLayout.BASE_SIZE.X / 2 + side
		and math.abs(position.Z - center.Z) <= CourseLayout.BASE_SIZE.Z / 2 + reach
end

-- Cette méthode permet de donner le centre au sol de l'appareil d'entraînement de la place `index` (devant la base, à
-- côté de son entrée qu'il laisse libre) et la direction où regarde l'avatar (la bande).
function CourseLayout.stationPosition(index: number): (Vector3, Vector3)
	local base = CourseLayout.basePosition(index)
	local z = CourseLayout.BASE_FRONT + CourseLayout.STATION_GAP
	return Vector3.new(base.X + CourseLayout.STATION_SHIFT, 0, z), CourseLayout.ENTRANCE
end

-- Présentoirs achetables (7 à 10) : deux le long de chaque clôture de côté, entre les rangées des 6 premiers
local EXTRA_DISPLAYS =
	{ Vector3.new(-15.5, 0, -4.5), Vector3.new(-15.5, 0, 4.5), Vector3.new(15.5, 0, -4.5), Vector3.new(15.5, 0, 4.5) }

-- Cette méthode permet de donner les emplacements des DISPLAY_MAX présentoirs d'une base (2 rangées de 3 dans la
-- profondeur, puis les 4 achetables le long des clôtures de côté) lorsque l'on construit la base ; les achetables
-- existent dès la construction (grisés tant qu'ils ne sont pas achetés), pour ne déplacer aucun autre présentoir.
-- Disposition de #61 (entrée vers +X) symétrique par la diagonale x = z : entrée vers +Z, même ordre des présentoirs.
function CourseLayout.displayPositions(index: number): { Vector3 }
	local center = CourseLayout.basePosition(index)
	local positions = {}
	for row = 0, 1 do
		for col = -1, 1 do
			table.insert(positions, center + Vector3.new((row - 0.5) * 14, 0, col * 9))
		end
	end
	for _, offset in EXTRA_DISPLAYS do
		table.insert(positions, center + offset)
	end
	return positions
end

-- Cette méthode permet de donner le centre au sol du pad d'achat de présentoir de la place `index` (devant la base, de
-- l'autre côté de l'entrée que l'appareil d'entraînement) et la direction où regarde son panneau (la bande).
function CourseLayout.padPosition(index: number): (Vector3, Vector3)
	local base = CourseLayout.basePosition(index)
	local z = CourseLayout.BASE_FRONT + CourseLayout.PAD_GAP
	return Vector3.new(base.X - CourseLayout.PAD_SHIFT, 0, z), CourseLayout.ENTRANCE
end

-- Cette méthode permet de donner le repère au sol du stand `kind` (« shop » ou « sell ») à gauche de la bande, dos à
-- la paroi du départ, face avant (-Z local) tournée vers les bases, lorsque le hub est construit.
function CourseLayout.standFrame(kind: string): CFrame
	local x = STAND_X[kind]
	assert(x, "CourseLayout.standFrame : stand inconnu " .. tostring(kind))
	return CFrame.new(x, 0, CourseLayout.HUB_FRONT - STAND_BACK)
end

-- Cette méthode permet de donner le repère au sol (centre de l'emprise, face avant -Z vers les bases) du tableau de
-- scores `index` (1 : LONGEST THROW, 2 : INCOME, 3 : REBIRTHS) à droite de la bande, lorsque le hub est construit.
function CourseLayout.boardFrame(index: number): CFrame
	local x = BOARD_X[index]
	assert(x, "CourseLayout.boardFrame : tableau inconnu " .. tostring(index))
	return CFrame.new(x, 0, CourseLayout.HUB_FRONT - BOARD_BACK)
end

-- Cette méthode permet de donner le centre au sol de la zone d'événement réservée (au bout de la rangée des tableaux,
-- contre la paroi du départ) lorsque le hub est construit.
function CourseLayout.eventPosition(): Vector3
	return Vector3.new(EVENT_X, 0, CourseLayout.HUB_FRONT - CourseLayout.EVENT_SIZE.Z / 2 - 1)
end

-- Emprise au sol d'un élément du hub (rectangle aligné sur les axes, hauteur ignorée)
export type Footprint = { name: string, center: Vector3, size: Vector3 }

-- Cette méthode permet de lister les emprises au sol de ce qui est posé dans le hub (bases, appareils, pads, stands,
-- tableaux, zone d'événement) lorsque les tests vérifient qu'ils ne se chevauchent pas et restent dans le hub.
function CourseLayout.hubFootprints(): { Footprint }
	local list: { Footprint } = {}
	local podium = Vector3.new(CourseLayout.STATION_SIZE, 0, CourseLayout.STATION_SIZE)
	for index = 1, GameConfig.SLOT_COUNT do
		local base = CourseLayout.basePosition(index)
		table.insert(list, { name = "base" .. index, center = base, size = CourseLayout.BASE_SIZE })
		table.insert(list, { name = "station" .. index, center = CourseLayout.stationPosition(index), size = podium })
		-- Pad : dalle de 6 studs devant son repère, panneau de 11 studs de large 2 studs derrière
		local pad = CourseLayout.padPosition(index)
		local padSize = Vector3.new(11, 0, 8.5)
		table.insert(list, { name = "pad" .. index, center = pad + Vector3.new(0, 0, 1.75), size = padSize })
	end
	for _, kind in { "shop", "sell" } do
		local center = CourseLayout.standFrame(kind).Position + Vector3.new(0, 0, STAND_DEPTH_SHIFT)
		table.insert(list, { name = kind, center = center, size = CourseLayout.STAND_SIZE })
	end
	for index in BOARD_X do
		local center = CourseLayout.boardFrame(index).Position
		table.insert(list, { name = "board" .. index, center = center, size = CourseLayout.BOARD_SIZE })
	end
	table.insert(list, { name = "event", center = CourseLayout.eventPosition(), size = CourseLayout.EVENT_SIZE })
	return list
end

-- Cette méthode permet de donner la colonne d'obstacles (une par place) qui couvre l'abscisse `x` ; nil hors des
-- colonnes (bords du canyon).
function CourseLayout.columnAt(x: number): number?
	local half = GameConfig.SLOT_SPACING / 2
	for index = 1, GameConfig.SLOT_COUNT do
		if math.abs(x - CourseLayout.slotX(index)) <= half then
			return index
		end
	end
	return nil
end

-- Cette méthode permet de donner le bord intérieur (|x|) et la hauteur du sommet de la marche `tier` (0 = la plus
-- basse) des parois du canyon, de part et d'autre de la piste.
function CourseLayout.tier(tier: number): (number, number)
	local inner = GameConfig.TRACK_WIDTH / 2 + tier * CourseLayout.TIER_STEP
	return inner, (tier + 1) * CourseLayout.TIER_HEIGHT
end

return CourseLayout
