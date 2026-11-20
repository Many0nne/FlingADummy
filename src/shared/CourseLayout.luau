-- Plan de la carte (logique pure, testée) : places des joueurs (bases, appareil d'entraînement devant chaque base),
-- bande de lancer commune (où se fige chaque joueur), colonnes des obstacles partagés, gradins du canyon. Repère :
-- piste vers +Z, départ à z = 0, hub derrière (z < 0) ; +X est à gauche quand on regarde la piste.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local CourseLayout = {}

local BASE_X = 64 -- centre des bases, de part et d'autre du hub
local BASE_Z = { -48, -100 } -- rangée avant, rangée arrière
CourseLayout.BASE_SIZE = Vector3.new(34, 0, 40)
CourseLayout.DISPLAY_COUNT = 6 -- présentoirs par base (2 rangées de 3)
CourseLayout.STATION_GAP = 10 -- de la clôture d'entrée de la base au centre de son appareil d'entraînement (studs)
CourseLayout.STATION_SHIFT = 12 -- décalage de l'appareil sur le côté de l'entrée, vers la zone de lancer (+Z)
CourseLayout.STATION_SIZE = 9 -- côté du podium de l'appareil

-- Bande de lancer : toute la largeur de la piste, de z = -BAND_DEPTH au départ (z = 0), au ras du sol
CourseLayout.BAND_TOP = 0
CourseLayout.EDGE_RISE = 0.25 -- le liseré blanc dépasse un peu du sol
CourseLayout.BAND_Z = -GameConfig.BAND_DEPTH / 2 -- milieu de la bande (points de lancer de test, flèche)
CourseLayout.BAND_EDGE = 1.2 -- liseré blanc, côté piste (z de 0 à BAND_EDGE), compté comme bande
CourseLayout.BAND_REACH = 8 -- hauteur au-dessus de la bande où l'avatar compte comme posé dessus (studs)
CourseLayout.BAND_SHINE_TAG = "LaunchBandShine" -- dégradé du reflet de la bande, que chaque client fait glisser

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

-- Cette méthode permet de donner le centre, au sol, de la base du joueur de la place `index` : les places de gauche
-- (x > 0) ont leur base à gauche du hub, celles de droite à droite, la plus proche du centre devant.
function CourseLayout.basePosition(index: number): Vector3
	local x = CourseLayout.slotX(index)
	local side = if x >= 0 then 1 else -1
	local half = GameConfig.SLOT_COUNT / 2
	-- Rang depuis le centre : 1 pour la place la plus proche de l'axe, puis 2…
	local rank = if side > 0 then index - math.floor(half) else math.ceil(half) - index + 1
	return Vector3.new(side * BASE_X, 0, BASE_Z[math.clamp(rank, 1, #BASE_Z)])
end

-- Cette méthode permet de donner le côté de l'entrée de la base `index` (+1 ou -1 sur X : vers le centre du hub)
-- lorsque l'on clôture la base ou que l'on pose son appareil d'entraînement.
function CourseLayout.entranceSide(index: number): number
	return if CourseLayout.basePosition(index).X > 0 then -1 else 1
end

-- Cette méthode permet de donner le centre au sol de l'appareil d'entraînement de la place `index` (devant la base, à
-- côté de son entrée qu'il laisse libre) et la direction où regarde l'avatar (centre du hub).
function CourseLayout.stationPosition(index: number): (Vector3, Vector3)
	local side = CourseLayout.entranceSide(index)
	local base = CourseLayout.basePosition(index)
	local x = base.X + side * (CourseLayout.BASE_SIZE.X / 2 + CourseLayout.STATION_GAP)
	return Vector3.new(x, 0, base.Z + CourseLayout.STATION_SHIFT), Vector3.new(side, 0, 0)
end

-- Cette méthode permet de donner les emplacements des présentoirs d'une base (2 rangées de 3, centrés sur la base)
-- lorsque l'on construit la base ; la tâche collection y pose les mannequins gagnés.
function CourseLayout.displayPositions(index: number): { Vector3 }
	local center = CourseLayout.basePosition(index)
	local positions = {}
	for row = 0, 1 do
		for col = -1, 1 do
			table.insert(positions, center + Vector3.new(col * 9, 0, (row - 0.5) * 14))
		end
	end
	return positions
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
