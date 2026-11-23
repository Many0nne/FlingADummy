-- Construction du décor au style des jeux de référence (01 / 09) : hub en pelouse à damier (bases des joueurs avec leur
-- appareil d'entraînement devant l'entrée, stands à auvents), bande de lancer commune, piste unique
-- au fond d'un canyon en gradins (parois à briques, herbe voxel qui déborde, arbres et rochers voxel) qui change de
-- couleurs à chaque zone, obstacles partagés (Server.Obstacles). Repère : Shared.CourseLayout.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseLook = require(ReplicatedStorage.Shared.BaseLook)
local BaseUpgrade = require(ReplicatedStorage.Shared.BaseUpgrade)
local Collection = require(ReplicatedStorage.Shared.Collection)
local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local Drips = require(ReplicatedStorage.Shared.Drips)
local DummyShape = require(ReplicatedStorage.Shared.DummyShape)
local GearPad = require(ReplicatedStorage.Shared.GearPad)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Leaderboard = require(ReplicatedStorage.Shared.Leaderboard)
local Objectives = require(ReplicatedStorage.Shared.Objectives)
local ThrowDummies = require(ReplicatedStorage.Shared.ThrowDummies)
local SurfaceGap = require(ReplicatedStorage.Shared.SurfaceGap)
local ThrowStart = require(ReplicatedStorage.Shared.ThrowStart)
local TrackPlan = require(ReplicatedStorage.Shared.TrackPlan)
local TrainingLook = require(ReplicatedStorage.Shared.TrainingLook)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Build = require(script.Parent.Build)
local CollisionGroups = require(script.Parent.CollisionGroups)
local Obstacles = require(script.Parent.Obstacles)
local Props = require(script.Parent.Props)
local StationPieces = require(script.Parent.StationPieces)

type Zone = Zones.Zone

local SEED = 20261120 -- décor identique d'un serveur à l'autre
local SEGMENT_LENGTH = 400 -- longueur maximale d'une pièce de sol ou de paroi (limite : 2 048 studs)
local CAP_THICKNESS = Drips.CAP_THICKNESS
local CAP_OVERHANG = 1 -- l'herbe déborde du bord de chaque marche
local END_Z = GameConfig.COURSE_LENGTH + 40 -- fond du canyon, derrière la paroi de bout de piste
local END_EXTRA = 200 -- les parois de la dernière zone dépassent d'autant la paroi de bout de piste (pas de trou aux coins)
-- Décor lointain allégé (#115) : au-delà de 2,4 km (zones de 600 m, vues seulement en vol, vite), accessoires semés
-- FAR_SPACING fois plus espacés ; la piste, les parois et les obstacles ne changent pas
local FAR_START = 2400
local FAR_SPACING = 1.6
local TRAP_MARGIN = 10 -- pas d'accessoire au pied des parois à moins de 10 studs d'un piège (rayon de l'arc-en-ciel)
local FINISH_CLEARANCE = 12 -- pas de décor au pied des parois à moins de 12 studs avant l'arche d'arrivée (piliers)
local STATION_HEIGHT = 1.4 -- hauteur du podium de l'appareil d'entraînement
local STATION_SPOT = 0.6 -- avance de la place de l'avatar devant le centre du podium (le râtelier est derrière)
local RACK_SCALE = 0.5 -- taille des mannequins suspendus au râtelier (sans se toucher)
local RACK_HEIGHT = 7.2 -- hauteur des montants du râtelier au-dessus du podium
local RACK_POST_X = 3.9 -- écart des montants du râtelier à l'axe du podium
local RACK_ROPE = 0.7 -- longueur de la corde qui suspend chaque mannequin du râtelier
local BAND_TILE = 4 -- côté des carreaux de la bande de lancer (studs)
local BARRIER_HEIGHT = 120 -- barrière des avatars : plus haute que les gradins et qu'un saut depuis leur sommet
local SPAWN_BACK = 6 -- réapparition à cette distance derrière la bande (studs)

local rgb = Color3.fromRGB
local COLORS = {
	band = rgb(255, 170, 30),
	bandLight = rgb(255, 205, 50),
	line = rgb(250, 250, 250),
	pad = rgb(255, 225, 60),
	padGreen = rgb(80, 200, 70),
	padRed = rgb(225, 60, 60),
	padGold = rgb(255, 190, 40),
	padGrey = rgb(125, 125, 135),
	gearPad = rgb(160, 70, 235), -- violet de la fenêtre Training Gear
	plot = rgb(175, 115, 65),
	wood = rgb(200, 140, 80),
	woodDark = rgb(150, 95, 50),
	stone = rgb(200, 200, 210),
	woodLight = rgb(225, 170, 105),
	rope = rgb(235, 215, 165),
	metal = rgb(70, 72, 80),
	ink = rgb(40, 38, 48),
}

local PLOT_TOP = 0.3 -- épaisseur du terrain d'une base (dessus au-dessus de la pelouse)
local GATE_WIDTH = 10 -- entrée de la base, côté hub
local BED_INSET = 2.2 -- du bord de la base à l'axe d'un massif de fleurs
local BED_END = 5 -- massifs arrêtés à cette distance des clôtures de côté
local FLAG_INSET = 2.5 -- drapeaux plantés à l'intérieur des coins
local SHRUB_GAP = 1 -- buissons au-delà du bout des massifs de fleurs (#198)
local TREE_INSET = 2 -- arbres des coins du fond plantés à l'intérieur de la clôture (#198)
-- Bas du texte flottant de la base, au-dessus de son centre : au-dessus des plus grands mannequins posés vus de la bande
-- (#150 ; le texte grandit vers le haut, sa marge en pixels ne le fait plus descendre derrière eux)
local LABEL_HEIGHT = 26
local LABEL_DISTANCE = 600 -- distance d'affichage du texte flottant (tout le hub et la zone de lancer)
local LABEL_GREEN = Color3.fromRGB(80, 215, 70) -- revenu (vert du HUD)
local LABEL_CYAN = Color3.fromRGB(90, 205, 255) -- Throw Power (cyan du HUD)
local LABEL_GOLD = Color3.fromRGB(255, 205, 60) -- record (#44)

-- Pad d'achat de présentoir devant la base (panneau « 8 > 9 » et prix, mis à jour par Server.BaseService)
export type Pad = { title: TextLabel, price: TextLabel, prompt: ProximityPrompt }

-- Pad d'amélioration de l'équipement à côté de l'appareil (#159) : panneau « NEXT: … », EXP par répétition et prix sur
-- une plaque teintée (Shared.GearPad), mis à jour par Server.TrainingService ; invites « Upgrade » et « View all »
export type GearPadParts = {
	title: TextLabel,
	gain: TextLabel,
	price: TextLabel,
	plate: BasePart,
	buy: ProximityPrompt,
	view: ProximityPrompt,
	shown: string?, -- dernier contenu affiché (pas de mise à jour à chaque gain d'argent)
}

-- Texte flottant au-dessus de la base (#91), rempli par Server.BaseService (Shared.BaseLook.label)
export type BaseLabel = { avatar: ImageLabel, title: TextLabel, income: TextLabel, best: TextLabel, power: TextLabel }

export type Base = {
	model: Model,
	plot: BasePart, -- terrain, teinté au palier
	look: Folder, -- clôture et décor du palier visuel (Shared.BaseLook), refaits à chaque palier
	tier: number, -- palier visuel affiché
	big: boolean, -- agrandie vers le fond (passe Big Base, #160) : terrain et clôture pour DISPLAY_ROOM présentoirs
	label: BaseLabel,
	burst: BasePart, -- confettis d'achat de présentoir (CourseBuilder.celebrate)
	-- dessus des DISPLAY_ROOM présentoirs (invite « Place » dedans), grisés tant que pas achetés ; ceux au-delà de
	-- DISPLAY_MAX (Big Base) cachés quand la base n'est pas agrandie
	displays: { BasePart },
	pedestals: { BasePart }, -- socles des présentoirs
	collars: { [number]: BasePart }, -- bandeaux des socles aux hauts paliers (#198), par présentoir, dans l'habillage
	facing: Vector3, -- direction de l'entrée (vers la bande) : les mannequins posés regardent par là
	pad: Pad,
}

-- Appareil d'entraînement d'une place (#92) : habillé au palier de Training Gear de son propriétaire
export type Trainer = {
	model: Model,
	look: Model, -- podium et râtelier, refaits à chaque palier
	floor: CFrame, -- centre du podium au sol, -Z = face de l'avatar
	tier: number, -- palier de Training Gear affiché
	burst: BasePart, -- confettis d'achat de Training Gear (CourseBuilder.celebrate)
}

export type Slot = {
	index: number,
	color: Color3,
	launchPoint: Vector3, -- point de la bande, au sol, d'où partent les mannequins de test de la place (Studio)
	station: CFrame, -- position de l'avatar qui s'entraîne (sur le podium, face à la bande)
	prompt: ProximityPrompt, -- « Lift » sur l'appareil d'entraînement, devant la base
	trainer: Trainer, -- appareil d'entraînement, habillé par Server.TrainingService
	gearPad: GearPadParts, -- pad d'amélioration de l'équipement, à côté de l'appareil
	base: Base, -- présentoirs, remplis par Server.BaseService
	direction: Vector3,
	spawn: CFrame, -- réapparition et retour après un lancer : dans le hub, juste derrière la bande, face à la piste
}

export type Course = { slots: { Slot }, dummies: Folder, boards: { Props.Scoreboard } }

local CourseBuilder = {}

CourseBuilder.FAR_START = FAR_START -- début du décor lointain allégé (tools/decor-count.luau)

local rng = Random.new(SEED)
-- Par place : repose les mannequins de son râtelier quand les gabarits maillés arrivent
local rackPlacers: { [number]: () -> () } = {}

-- Cette méthode permet de reposer les mannequins des râteliers à chaque étape de chargement des gabarits (corps maillé,
-- puis pièces ajoutées des looks d'entraînement, #118) lorsque le hub est construit avant eux.
local function watchRackTemplates()
	-- Cette méthode permet de resuspendre les mannequins de tous les râteliers lorsque une étape de chargement arrive.
	local function replace()
		for _, place in rackPlacers do
			place()
		end
	end
	-- Cette méthode permet de suivre les étapes du dossier des gabarits lorsqu'il est (ou vient d'être) répliqué.
	local function watch(folder: Instance)
		folder:GetAttributeChangedSignal("Ready"):Connect(replace)
		folder:GetAttributeChangedSignal(DummyShape.COMPLETE):Connect(replace)
		if folder:GetAttribute("Ready") then
			replace()
		end
	end
	local folder = ReplicatedStorage:FindFirstChild(DummyShape.TEMPLATES)
	if folder then
		watch(folder)
		return
	end
	local connection
	connection = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == DummyShape.TEMPLATES then
			connection:Disconnect()
			watch(child)
		end
	end)
end

-- Cette méthode permet de désigner une pièce comme cible d'objectif du HUD (réservée au joueur de la place `slot`)
-- lorsque l'on construit son appareil d'entraînement.
local function markObjective(part: BasePart, objective: string, slot: number)
	part:SetAttribute("Objective", objective)
	part:SetAttribute("Slot", slot)
	CollectionService:AddTag(part, Objectives.TAG)
end

-- Cette méthode permet de régler la lumière (plein jour clair et saturé, ombres douces et peu marquées, nuages, comme
-- les jeux de référence) lorsque le serveur démarre.
local function setupLighting()
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 3
	Lighting.Ambient = rgb(110, 110, 120)
	Lighting.OutdoorAmbient = rgb(190, 195, 210)
	Lighting.ShadowSoftness = 0.6
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.2
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.18
	atmosphere.Haze = 0.4
	atmosphere.Glare = 0
	atmosphere.Color = rgb(205, 230, 255)
	atmosphere.Decay = rgb(140, 185, 240)
	atmosphere.Parent = Lighting
	local grading = Lighting:FindFirstChild("Grading") or Instance.new("ColorCorrectionEffect")
	grading.Name = "Grading"
	grading.Saturation = 0.2
	grading.Contrast = 0
	grading.Brightness = 0.04
	grading.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.3
	bloom.Size = 20
	bloom.Threshold = 1.5
	bloom.Parent = Lighting
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.7
	clouds.Color = rgb(255, 255, 255)
	clouds.Parent = Workspace.Terrain
end

-- Cette méthode permet de poser une dalle de sol à damier (axe-aligné, dessus à y = 0) sur le rectangle donné, découpée
-- en pièces de SEGMENT_LENGTH au plus, lorsque l'on construit le hub, la zone de lancer ou la piste.
local function ground(
	parent: Instance,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	color: Color3,
	name: string
)
	local z = minZ
	while z < maxZ - 0.01 do
		local length = math.min(SEGMENT_LENGTH, maxZ - z)
		Build.part({
			Name = name,
			Size = Vector3.new(maxX - minX, 2, length),
			Position = Vector3.new((minX + maxX) / 2, -1, z + length / 2),
			Color = color,
			Variant = Build.CHECKER,
			-- Frottement moyen : le mannequin glisse un peu après l'atterrissage
			CustomPhysicalProperties = PhysicalProperties.new(2.4, 0.35, 0.25, 5, 1),
			Parent = parent,
		})
		z += length
	end
end

-- Cette méthode permet de poser un bloc axe-aligné entre deux coins (minimum, maximum) lorsque l'on monte une marche de
-- paroi ou sa couverture.
local function box(parent: Instance, low: Vector3, high: Vector3, color: Color3, variant: string, name: string): Part
	return Build.part({
		Name = name,
		Size = high - low,
		Position = (low + high) / 2,
		Color = color,
		Variant = variant,
		Parent = parent,
	})
end

-- Cette méthode permet de faire déborder l'herbe (neige, sable…) d'une marche en blocs qui descendent en escalier
-- (tracé : Shared.Drips) le long d'un bord tourné vers `facing`, lorsque l'on habille une paroi ; `low`, `high` : coins de
-- la marche, dont Roblox fait partir le damier de la face.
local function drips(
	parent: Instance,
	edge: Vector3,
	facing: Vector3,
	length: number,
	color: Color3,
	low: Vector3,
	high: Vector3
)
	-- `edge` : début du bord, au niveau du dessous de la couverture ; le bord court le long de `along`
	local along = Vector3.new(0, 1, 0):Cross(facing)
	-- Le damier de la face part du bout de la marche où commence `along` (vérifié en jeu sur les quatre orientations)
	local start = math.min(low:Dot(along), high:Dot(along))
	local blocks = Drips.layout(edge:Dot(along) - start, length, function(a, b)
		return rng:NextInteger(a, b)
	end, function()
		return rng:NextNumber()
	end)
	for _, block in blocks do
		local center = edge
			+ along * (block.t + block.width / 2)
			+ facing * (CAP_OVERHANG / 2)
			- Vector3.new(0, block.top + block.height / 2, 0)
		local extent = along * block.width + facing * CAP_OVERHANG
		Build.decor({
			Name = "Drip",
			Size = Vector3.new(math.abs(extent.X), block.height, math.abs(extent.Z)),
			Position = center,
			Color = color,
			-- Tenons seuls (pas de damier) : chaque bloc ancre sa texture à son propre coin, un damier y serait décalé
			Variant = Build.BRICK,
			Parent = parent,
		})
	end
end

-- Cette méthode permet de semer le décor de la zone sur une bande (de `from` à `to` au sol, espacement moyen
-- `spacing`, plus large au-delà de FAR_START, écart latéral `jitter` le long de `side`, rien dans l'emprise des
-- pièges `keepOut`) lorsque l'on habille une marche ou le pied d'une paroi.
local function scatter(
	parent: Instance,
	zone: Zone,
	from: Vector3,
	to: Vector3,
	spacing: number,
	side: Vector3,
	jitter: number,
	solid: boolean,
	keepOut: { TrackPlan.TrapBox }?
)
	local delta = to - from
	local length = delta.Magnitude
	local direction = delta.Unit
	if zone.start >= FAR_START then
		spacing *= FAR_SPACING
	end
	local t = rng:NextNumber(0, spacing)
	while t < length do
		local kind = zone.props[rng:NextInteger(1, #zone.props)]
		local position = from + direction * t + side * rng:NextNumber(-jitter, jitter)
		local turn = rng:NextInteger(0, 3)
		if not keepOut or TrackPlan.clearOfTraps(keepOut, position.X, position.Z, TRAP_MARGIN) then
			Props.build(kind, parent, CFrame.new(position) * CFrame.Angles(0, math.rad(turn * 90), 0), rng, solid)
		end
		t += spacing * rng:NextNumber(0.6, 1.4)
	end
end

-- Bout d'une paroi en gradins (#93, #38) : avancée de la couverture du dessus (`cover`) et du débord côté zone ouverte
-- (`strip`) au-delà du bout de la marche, coulées arrêtées à `drip` studs du bout ; `fill` : la marche (et sa
-- couverture) se prolonge jusqu'au bord extérieur de la paroi voisine, qui la coupe à angle droit (coin du hub sans
-- encoche). Une couverture qui affleure le bout de sa marche scintille : elle le dépasse ou s'arrête avant.
type WallEnd = { cover: number, strip: number, drip: number, fill: boolean?, recede: boolean? }
local CAP_LIP = SurfaceGap.STEP -- avancée de la couverture sur un bout visible
-- Bout visible : la couverture dépasse un peu la marche
local FREE: WallEnd = { cover = CAP_LIP, strip = CAP_LIP, drip = 0 }
-- Prolongée dans l'alignement (paroi de la zone suivante, ou fond du hub qui la recouvre) : couverture au ras, bout caché
local JOINT: WallEnd = { cover = 0, strip = 0, drip = 0 }
-- Épaulement du hub : la couverture de la piste avance par-dessus, celle du hub s'arrête avant
local UNDER: WallEnd = { cover = -CAP_LIP, strip = -CAP_LIP, drip = 0 }
-- Entre deux parois qui la bordent (bout de piste) : leur débord couvre le coin, couverture et coulées s'arrêtent avant
local INNER: WallEnd = { cover = -CAP_OVERHANG, strip = -CAP_OVERHANG, drip = CAP_OVERHANG }
-- Fond du hub : la marche couvre le coin jusqu'au bord extérieur des côtés ; son débord et ses coulées s'arrêtent avant
-- celui des côtés
local FILL: WallEnd = { cover = CAP_LIP, strip = -CAP_OVERHANG, drip = CAP_OVERHANG, fill = true }
-- Au-delà de la paroi de bout de piste (côtés de la dernière zone) : coulées arrêtées à son pied, qui recule d'une marche
-- à l'autre (`recede`)
local BEYOND_END: WallEnd = { cover = CAP_LIP, strip = CAP_LIP, drip = END_EXTRA, recede = true }

-- Cette méthode permet de poser un bloc axe-aligné entre deux coins opposés quelconques (hauteurs `y0` à `y1`) lorsque
-- l'on monte la couverture d'une marche.
local function capBox(parent: Instance, p: Vector3, q: Vector3, y0: number, y1: number, color: Color3, name: string)
	box(
		parent,
		Vector3.new(math.min(p.X, q.X), y0, math.min(p.Z, q.Z)),
		Vector3.new(math.max(p.X, q.X), y1, math.max(p.Z, q.Z)),
		color,
		Build.WALL,
		name
	)
end

-- Cette méthode permet de monter la marche `tier` d'une paroi (bloc, couverture du dessus, débord, coulées) lorsque l'on
-- monte la paroi ; renvoie les deux bouts de la ligne du décor de son terre-plein.
local function terrace(
	parent: Instance,
	start: Vector3,
	finish: Vector3,
	facing: Vector3,
	zone: Zone,
	tier: number,
	grows: { number },
	ends: { WallEnd }
): (Vector3, Vector3)
	local startEnd, finishEnd = ends[1], ends[2]
	local along = (finish - start).Unit
	local _, top = CourseLayout.tier(tier)
	local back = tier * CourseLayout.TIER_STEP -- recul de la marche
	local a = start - along * (grows[1] * back) - facing * back
	local b = finish + along * (grows[2] * back) - facing * back
	-- Bloc de la marche : du bord jusqu'au bord extérieur du plateau (et jusqu'à celui de la paroi voisine, `fill`)
	local depth = CourseLayout.OUTER - GameConfig.TRACK_WIDTH / 2 - back
	local outer = -facing * depth
	local a0 = a - along * (if startEnd.fill then depth else 0)
	local b0 = b + along * (if finishEnd.fill then depth else 0)
	local low = Vector3.new(
		math.min(a0.X, b0.X + outer.X, a0.X + outer.X, b0.X),
		top - CourseLayout.TIER_HEIGHT,
		math.min(a0.Z, b0.Z + outer.Z, a0.Z + outer.Z, b0.Z)
	)
	local high = Vector3.new(
		math.max(a0.X, b0.X + outer.X, a0.X + outer.X, b0.X),
		top,
		math.max(a0.Z, b0.Z + outer.Z, a0.Z + outer.Z, b0.Z)
	)
	box(parent, low, high, zone.wall, Build.WALL, "Terrace")
	-- Couverture du dessus du bloc (cachée sous la marche suivante), qui dépasse un peu son bord extérieur, puis son
	-- débord côté zone ouverte ; chacune dépasse le bout du bloc ou s'arrête avant (jamais au ras d'un bout visible)
	local y0, y1 = top - 0.4, top + CAP_THICKNESS - 0.4
	capBox(
		parent,
		a0 - along * startEnd.cover,
		b0 + along * finishEnd.cover - facing * (depth + CAP_LIP),
		y0,
		y1,
		zone.top,
		"TerraceTop"
	)
	capBox(
		parent,
		a - along * startEnd.strip,
		b + along * finishEnd.strip + facing * CAP_OVERHANG,
		y0,
		y1,
		zone.top,
		"TerraceTop"
	)
	-- Coulées arrêtées à `drip` studs de chaque bout (moins le recul de la marche si la paroi qui les arrête recule aussi)
	local trim0 = startEnd.drip - (if startEnd.recede then back else 0)
	local trim1 = finishEnd.drip - (if finishEnd.recede then back else 0)
	local length = (b - a).Magnitude - trim0 - trim1
	if length > 0 then
		drips(parent, a + along * trim0 + Vector3.new(0, y0, 0), facing, length, zone.top, low, high)
	end
	-- Ligne du décor du terre-plein : au milieu de la marche, sur la couverture
	local rise = Vector3.new(0, y1, 0) - facing * (CourseLayout.TIER_STEP / 2)
	return a + rise, b + rise
end

-- Cette méthode permet de monter les marches d'une paroi en gradins (bords, `grow` et bouts WallEnd) dans `area` lorsque
-- l'on borde le hub ou la piste ; renvoie de quoi poser son décor, une fois les parois voisines montées.
local function terraces(
	area: SurfaceGap.Area,
	parent: Instance,
	start: Vector3,
	finish: Vector3,
	facing: Vector3,
	zone: Zone,
	growStart: number,
	growEnd: number,
	startEnd: WallEnd,
	finishEnd: WallEnd
): () -> ()
	-- Marches réglées à la main (bouts, débords : WallEnd), ajoutées à la zone telles quelles
	local lines = {}
	Build.keep(area, function()
		for tier = 0, CourseLayout.TIER_COUNT - 1 do
			local ground0, ground1 = terrace(
				parent,
				start,
				finish,
				facing,
				zone,
				tier,
				{ growStart, growEnd },
				{ startEnd, finishEnd }
			)
			lines[tier] = { ground0, ground1 }
		end
	end)
	-- Cette méthode permet de semer le décor des terre-pleins et du plateau (dernière marche, deux rangées) lorsque les
	-- parois voisines sont montées : un accessoire qui affleure une marche, une coulée ou un voisin en ressort un peu.
	return function()
		Build.within(area, function()
			for tier = 0, CourseLayout.TIER_COUNT - 1 do
				local ground0, ground1 = lines[tier][1], lines[tier][2]
				if tier < CourseLayout.TIER_COUNT - 1 then
					scatter(parent, zone, ground0, ground1, 26, facing, 1.5, true)
				else
					scatter(parent, zone, ground0, ground1, 16, facing, 2, true)
					scatter(parent, zone, ground0 - facing * 22, ground1 - facing * 22, 18, facing, 8, true)
				end
			end
		end)
	end
end

-- Cette méthode permet de poser le reflet de la bande de lancer (bandeau blanc en dégradé sur son dessus, que chaque
-- client fait glisser lui-même : rien ne se réplique à chaque image) lorsque la zone de lancer est construite.
local function bandShine(parent: Instance, size: Vector3, position: Vector3): Part
	local overlay = Build.decor({
		Name = "LaunchBandShine",
		Size = size,
		Position = position,
		Transparency = 1,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.LightInfluence = 0
	local sheen = Instance.new("Frame")
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BorderSizePixel = 0
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	-- Bandeau étroit et doux, transparent ailleurs ; décalé hors de la bande au repos
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-1.5, 0)
	gradient.Parent = sheen
	CollectionService:AddTag(gradient, CourseLayout.BAND_SHINE_TAG)
	gui.Parent = overlay
	return overlay
end

-- Cette méthode permet de construire la zone de lancer (pelouse, bande à tenons orange-jaune sur toute la largeur et son
-- reflet, liseré blanc côté piste, barrière invisible des avatars juste derrière) lorsque le serveur démarre.
local function buildLaunchZone(parent: Instance)
	local half = GameConfig.TRACK_WIDTH / 2
	local depth = GameConfig.BAND_DEPTH
	local top = CourseLayout.BAND_TOP
	-- Pelouse entre le hub et la bande, si la bande ne couvre pas toute la zone de lancer
	if depth < GameConfig.LAUNCH_DEPTH then
		ground(parent, -half, half, -GameConfig.LAUNCH_DEPTH, -depth, Zones.LIST[1].ground, "LaunchZone")
	end
	-- Carreaux de BAND_TILE studs aux deux teintes alternées (01 / 09), au ras de la pelouse
	local model = Instance.new("Model")
	model.Name = "LaunchBand"
	local columns = math.floor(GameConfig.TRACK_WIDTH / BAND_TILE + 0.5)
	local rows = math.max(1, math.floor(depth / BAND_TILE + 0.5))
	local tileX, tileZ = GameConfig.TRACK_WIDTH / columns, depth / rows
	for col = 1, columns do
		for row = 1, rows do
			Build.part({
				Name = "BandTile",
				Size = Vector3.new(tileX, 1, tileZ),
				Position = Vector3.new(-half + (col - 0.5) * tileX, top - 0.5, -depth + (row - 0.5) * tileZ),
				Color = if (col + row) % 2 == 0 then COLORS.band else COLORS.bandLight,
				Variant = Build.BRICK,
				Parent = model,
			})
		end
	end
	-- Liseré blanc en bordure, côté piste, à peine surélevé
	Build.part({
		Name = "BandEdge",
		-- Entre un peu dans les parois : ses bouts ne sont pas au ras de ceux du sol de la piste (#93)
		Size = Vector3.new(GameConfig.TRACK_WIDTH + 2 * SurfaceGap.STEP, 1.2, CourseLayout.BAND_EDGE),
		Position = Vector3.new(0, top + CourseLayout.EDGE_RISE - 0.6, CourseLayout.BAND_EDGE / 2),
		Color = COLORS.line,
		Variant = Build.BRICK,
		Parent = model,
	})
	local shine =
		bandShine(model, Vector3.new(GameConfig.TRACK_WIDTH, 0.05, depth), Vector3.new(0, top + 0.03, -depth / 2))
	-- Cible partagée de l'objectif « Lancer » : la flèche vise le point de la bande le plus proche du joueur
	shine:SetAttribute("Objective", "Throw")
	shine:SetAttribute("Span", half - GameConfig.BAND_MARGIN)
	CollectionService:AddTag(shine, Objectives.TAG)
	model.Parent = parent
	-- Barrière invisible juste derrière le liseré (#26) : arrête les avatars (même en sautant, même sur les gradins),
	-- laisse passer mannequins et obstacles
	Build.part({
		Name = "AvatarBarrier",
		Size = Vector3.new(2 * CourseLayout.OUTER, BARRIER_HEIGHT, 1),
		Position = Vector3.new(0, BARRIER_HEIGHT / 2 - 2, CourseLayout.BAND_EDGE + 0.5),
		Transparency = 1,
		CanQuery = false,
		CanTouch = false,
		CollisionGroup = CollisionGroups.AVATAR_BARRIER,
		Parent = parent,
	})
end

-- Cette méthode permet de poser une pièce de l'appareil d'entraînement en briques fines (un tenon par stud, à l'échelle
-- de l'avatar comme les montants de la référence 09) lorsque l'appareil est construit.
local function fine(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): Part
	return Build.part({
		Name = "Block",
		Size = size,
		CFrame = cframe,
		Color = color,
		Variant = Build.FINE,
		CastShadow = true,
		Parent = parent,
	})
end

-- Cette méthode permet de poser une pièce de métal sombre (sangle, boulon, disque de fonte) sans tenons lorsque
-- l'appareil d'entraînement est construit.
local function metal(parent: Instance, props: { [string]: any }): Part
	props.Material = Enum.Material.Metal
	props.Color = COLORS.metal
	props.Parent = parent
	return Build.part(props)
end

-- Cette méthode permet de suspendre un mannequin d'entraînement décoratif (pièces ancrées, sans collision) au râtelier
-- lorsque l'appareil est construit ; `hook` = repère au sommet de sa tête (face vers -Z). Look du palier `tier`
-- (Shared.TrainingLook, #118) : pièces ajoutées fixes (soudures retirées, pas d'animation), lumières sans particules.
local function rackDummy(parent: Instance, tier: number, hook: CFrame)
	local model = Instance.new("Model")
	model.Name = "RackDummy"
	local variant = TrainingLook.variant(tier, "rack") :: DummyShape.Variant
	local parts = DummyShape.buildPieces(model, RACK_SCALE, variant)
	DummyShape.addAccessories(model, parts, RACK_SCALE, variant)
	-- Sommet du mannequin, pièces ajoutées comprises (couronne, cornes) : la corde s'y accroche sans qu'elles touchent
	-- la traverse
	local highest = -math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			highest = math.max(highest, part.Position.Y + part.Size.Y / 2)
		end
	end
	-- Pas de cibles de crash-test peintes sur les blocs de repli : ce mannequin-là ne se lance pas. Maillé, il garde
	-- visage et cibles de l'atlas (ou de sa coque sous un matériau, #126), comme tous les mannequins
	for _, gui in parts.Torso:GetChildren() do
		if gui:IsA("SurfaceGui") then
			gui:Destroy()
		end
	end
	-- Toutes les pièces du modèle, coques des marques et pièces ajoutées comprises (#126 : visage sur un matériau
	-- d'équipement) : soudures retirées avant de déplacer chaque pièce, sinon elle entraînerait les autres
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			for _, child in part:GetChildren() do
				if child:IsA("WeldConstraint") or child:IsA("Weld") then
					child:Destroy()
				end
			end
			part:RemoveTag(DummyShape.FX_TAG)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CFrame = hook * CFrame.new(0, -highest, 0) * part.CFrame
		end
	end
	model.Parent = parent
end

-- Cette méthode permet de poser une pièce lumineuse (néon, sans tenons ni collision) lorsque l'on habille l'appareil
-- d'entraînement des derniers paliers ou la base (lanternes).
local function glow(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): Part
	return Build.decor({
		Name = "Glow",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Parent = parent,
	})
end

-- Cette méthode permet de poser un émetteur d'étincelles dorées ou colorées dans le volume d'une pièce invisible
-- lorsque l'on habille un palier brillant (base dorée, appareil Diamond et plus).
local function sparkles(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, rate: number): Part
	local zone = Build.decor({ Name = "Sparkles", Size = size, CFrame = cframe, Transparency = 1, Parent = parent })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.Rate = rate
	emitter.Parent = zone
	return zone
end

-- Cette méthode permet de poser l'émetteur de confettis joué par chaque client (Client.HubShops) quand le serveur
-- incrémente l'attribut `Upgrades` (CourseBuilder.celebrate) lorsque l'on construit une base ou un appareil.
local function upgradeBurst(parent: Instance, position: Vector3, color: Color3): Part
	local burst = Build.decor({
		Name = "UpgradeBurst",
		Size = Vector3.new(4, 1, 4),
		Position = position,
		Transparency = 1,
		Parent = parent,
	})
	local confetti = Instance.new("ParticleEmitter")
	confetti.Name = "Confetti"
	confetti.Enabled = false
	confetti.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, rgb(255, 220, 60)),
		ColorSequenceKeypoint.new(1, rgb(255, 255, 255)),
	})
	confetti.Size = NumberSequence.new(1.2, 0.5)
	confetti.Lifetime = NumberRange.new(1, 1.8)
	confetti.Speed = NumberRange.new(25, 45)
	confetti.SpreadAngle = Vector2.new(60, 60)
	confetti.EmissionDirection = Enum.NormalId.Top
	confetti.Acceleration = Vector3.new(0, -40, 0)
	confetti.Drag = 1.5
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.RotSpeed = NumberRange.new(-300, 300)
	confetti:SetAttribute("Count", 80)
	confetti.Parent = burst
	local stars = Instance.new("ParticleEmitter")
	stars.Name = "Stars"
	stars.Enabled = false
	stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	stars.Color = ColorSequence.new(rgb(255, 240, 120))
	stars.LightEmission = 1
	stars.Size = NumberSequence.new(2.4, 0)
	stars.Lifetime = NumberRange.new(0.5, 0.9)
	stars.Speed = NumberRange.new(18, 30)
	stars.SpreadAngle = Vector2.new(180, 180)
	stars.Drag = 3
	stars:SetAttribute("Count", 30)
	stars.Parent = burst
	burst:SetAttribute("Upgrades", 0)
	CollectionService:AddTag(burst, CourseLayout.UPGRADE_BURST_TAG)
	return burst
end

-- Cette méthode permet de faire jaillir les confettis d'une base ou d'un appareil chez tous les clients lorsque son
-- propriétaire achète un présentoir ou un Training Gear.
function CourseBuilder.celebrate(burst: BasePart)
	burst:SetAttribute("Upgrades", ((burst:GetAttribute("Upgrades") :: number?) or 0) + 1)
end

-- Cette méthode permet de monter le podium de l'appareil (socle, bordure de la place, planches et marches aux couleurs
-- du Training Gear, liseré néon des derniers paliers) lorsque l'appareil est habillé.
local function buildPodium(model: Model, floor: CFrame, color: Color3, look: BaseLook.StationLook)
	local size = CourseLayout.STATION_SIZE
	local h = STATION_HEIGHT
	fine(model, Vector3.new(size + 0.8, 0.5, size + 0.8), floor * CFrame.new(0, 0.25, 0), color)
	local socle = look.base or COLORS.stone
	fine(model, Vector3.new(size, h - 0.9, size), floor * CFrame.new(0, 0.5 + (h - 0.9) / 2, 0), socle)
	if look.glow then
		-- Liseré néon sur la bordure, autour du socle (à 0,05 stud de ses faces : pas de faces coplanaires)
		local ring = size / 2 + 0.2
		glow(model, Vector3.new(size + 0.7, 0.2, 0.3), floor * CFrame.new(0, 0.6, ring), look.glow)
		-- Devant : interrompu par les marches (4 studs de large)
		local piece = size / 2 + 0.35 - 2.05
		for _, side in { -1, 1 } do
			local x = side * (2.05 + piece / 2)
			glow(model, Vector3.new(piece, 0.2, 0.3), floor * CFrame.new(x, 0.6, -ring), look.glow)
			glow(model, Vector3.new(0.3, 0.2, size + 0.1), floor * CFrame.new(side * ring, 0.6, 0), look.glow)
		end
	end
	-- Planches du dessus, teintes alternées, dans le sens de la face
	local planks = 4
	local width = (size - 0.4) / planks
	for i = 1, planks do
		local x = -(size - 0.4) / 2 + (i - 0.5) * width
		local tint = if i % 2 == 0 then look.plank else look.plankAlt
		fine(model, Vector3.new(width - 0.12, 0.4, size - 0.4), floor * CFrame.new(x, h - 0.2, 0), tint)
	end
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		local at = corner * (size / 2 - 0.5)
		metal(model, { Size = Vector3.new(0.7, 0.25, 0.7), CFrame = floor * CFrame.new(at.X, h + 0.05, at.Z) })
	end
	-- Deux marches devant, côté hub
	fine(model, Vector3.new(4, h * 2 / 3, 1.2), floor * CFrame.new(0, h / 3, -size / 2 - 0.6), look.postDark)
	fine(model, Vector3.new(4, h / 3, 1.2), floor * CFrame.new(0, h / 6, -size / 2 - 1.8), look.postDark)
	local top = floor * CFrame.new(0, h, 0)
	Build.decor({
		Name = "TrainPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, 4.6, 4.6),
		CFrame = top * CFrame.new(0, 0.08, -STATION_SPOT) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.pad,
		Parent = model,
	})
	-- Cerne sombre sous le rond jaune : il se détache aussi des planches dorées (#118)
	Build.decor({
		Name = "TrainPadRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 5.2, 5.2),
		CFrame = top * CFrame.new(0, 0.06, -STATION_SPOT) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.ink,
		Parent = model,
	})
	-- Pile de disques de fonte dans un coin, côté hub
	for i, diameter in { 2.4, 2.1, 1.8 } do
		metal(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, diameter, diameter),
			CFrame = top * CFrame.new(3.1, 0.2 + (i - 1) * 0.37, -3.1) * CFrame.Angles(0, 0, math.rad(90)),
		})
	end
	metal(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 0.35, 0.35),
		CFrame = top * CFrame.new(3.1, 1.1, -3.1) * CFrame.Angles(0, 0, math.rad(90)),
	})
end

-- Cette méthode permet de monter le râtelier (montants, traverse, mannequins des trois derniers paliers, 1 à 3 au départ) aux
-- couleurs du Training Gear `tier` lorsque l'appareil de la place `index` est habillé.
local function buildRack(
	model: Model,
	top: CFrame,
	color: Color3,
	look: BaseLook.StationLook,
	tier: number,
	index: number
)
	local z = CourseLayout.STATION_SIZE / 2 - 1.2
	local postX = RACK_POST_X
	for _, side in { -1, 1 } do
		local x = side * postX
		fine(model, Vector3.new(1.6, RACK_HEIGHT, 1.6), top * CFrame.new(x, RACK_HEIGHT / 2, z), look.post)
		for _, y in { 1.2, RACK_HEIGHT - 1.6 } do
			metal(model, { Size = Vector3.new(1.8, 0.35, 1.8), CFrame = top * CFrame.new(x, y, z) })
		end
		-- Chapeau en gradins, à la couleur de la place
		for step, cap in { { 2, 0.5 }, { 1.4, 0.45 }, { 0.8, 0.4 } } do
			local y = RACK_HEIGHT + 0.25 + (step - 1) * 0.45
			fine(model, Vector3.new(cap[1], cap[2], cap[1]), top * CFrame.new(x, y, z), color)
		end
		-- Jambe de force vers l'arrière
		fine(
			model,
			Vector3.new(0.7, 2.6, 0.7),
			top * CFrame.new(x, 1.1, z + 0.5) * CFrame.Angles(math.rad(-30), 0, 0),
			look.postDark
		)
	end
	local barY = RACK_HEIGHT - 0.9
	fine(model, Vector3.new(postX * 2, 0.9, 0.9), top * CFrame.new(0, barY, z), look.postDark)
	for _, x in { -2.9, 2.9 } do
		fine(model, Vector3.new(0.45, 1.05, 1.05), top * CFrame.new(x, barY, z), COLORS.rope)
	end
	if look.glow then
		-- Néon sous la traverse, plus étroit qu'elle
		glow(model, Vector3.new(postX * 2 - 1.7, 0.2, 0.5), top * CFrame.new(0, barY - 0.55, z), look.glow)
	end
	if look.sparkle then
		sparkles(
			model,
			Vector3.new(postX * 2 + 2, RACK_HEIGHT, 3),
			top * CFrame.new(0, RACK_HEIGHT / 2, z),
			look.glow or look.plankAlt,
			8
		)
	end
	local rack = BaseLook.rackTiers(tier)
	-- Cette méthode permet de suspendre (ou resuspendre) les mannequins des trois derniers paliers lorsque
	-- l'appareil est habillé puis quand les gabarits maillés arrivent (blocs du gabarit en attendant).
	local function placeRack()
		for _, child in model:GetChildren() do
			if child.Name == "RackDummy" then
				child:Destroy()
			end
		end
		for i, x in { -2.1, 0, 2.1 } do
			local hookY = barY - 0.45 - RACK_ROPE
			rackDummy(model, rack[i], top * CFrame.new(x, hookY, z))
		end
	end
	for _, x in { -2.1, 0, 2.1 } do
		Build.decor({
			Name = "Rope",
			Size = Vector3.new(0.2, RACK_ROPE, 0.2),
			CFrame = top * CFrame.new(x, barY - 0.45 - RACK_ROPE / 2, z),
			Color = COLORS.rope,
			Parent = model,
		})
	end
	placeRack()
	rackPlacers[index] = placeRack
end

-- Cette méthode permet d'habiller l'appareil d'une place au Training Gear `tier` de son propriétaire (podium et
-- râtelier refaits) lorsqu'il arrive, part ou achète un équipement ; sans effet si l'appareil a déjà ce palier.
function CourseBuilder.styleStation(slot: Slot, tier: number)
	local trainer = slot.trainer
	if trainer.tier == tier then
		return
	end
	local look = BaseLook.station(tier)
	-- Nouvel habillage posé avant de retirer l'ancien : le podium ne manque jamais sous l'avatar
	local fresh = Instance.new("Model")
	fresh.Name = "Look"
	-- D'un tenant : une pièce qui en affleure une autre ressort un peu (#93)
	Build.settled(function()
		buildPodium(fresh, trainer.floor, slot.color, look)
		local top = trainer.floor * CFrame.new(0, STATION_HEIGHT, 0)
		buildRack(fresh, top, slot.color, look, tier, slot.index)
		-- Pièces de palier (#118), sur le repère du podium et du râtelier (buildRack)
		StationPieces.build(fresh, {
			floor = trainer.floor,
			top = top,
			size = CourseLayout.STATION_SIZE,
			height = STATION_HEIGHT,
			rackZ = CourseLayout.STATION_SIZE / 2 - 1.2,
			postX = RACK_POST_X,
			rackHeight = RACK_HEIGHT,
			barY = RACK_HEIGHT - 0.9,
		}, look)
	end)
	fresh.Parent = trainer.model
	trainer.look:Destroy()
	trainer.look = fresh
	trainer.tier = tier
end

-- Cette méthode permet de construire l'appareil d'entraînement d'une place à côté de l'entrée de sa base (podium,
-- râtelier, invite « Lift », confettis d'achat) lorsque le hub est construit ; habillé au premier palier.
local function buildStation(parent: Instance, slot: Slot)
	local center, facing = CourseLayout.stationPosition(slot.index)
	local floor = CFrame.lookAt(center, center + facing) -- centre du podium au sol, -Z = face de l'avatar
	local model = Instance.new("Model")
	model.Name = "Station" .. slot.index
	local look = Instance.new("Model")
	look.Name = "Look"
	look.Parent = model
	local top = floor * CFrame.new(0, STATION_HEIGHT, 0)
	-- Confettis au-dessus du râtelier
	local burstAt = top * CFrame.new(0, RACK_HEIGHT + 1, CourseLayout.STATION_SIZE / 2 - 1.2)
	slot.trainer = {
		model = model,
		look = look,
		floor = floor,
		tier = 0,
		burst = upgradeBurst(model, burstAt.Position, slot.color),
	}
	CourseBuilder.styleStation(slot, 1)
	model.Parent = parent
	local anchor = Build.decor({
		Name = "TrainSpot",
		Size = Vector3.new(2, 2, 2),
		Position = slot.station.Position - Vector3.new(0, 1, 0),
		Transparency = 1,
		Parent = model,
	})
	markObjective(anchor, "Train", slot.index)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Lift"
	prompt.ObjectText = "Training dummy"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	slot.prompt = prompt
	local label = top * CFrame.new(0, RACK_HEIGHT + 2.6, CourseLayout.STATION_SIZE / 2 - 1.2)
	Build.billboard(model, label.Position, "💪 TRAIN", Vector2.new(6, 1.8))
end

-- Couleur de la plaque de prix du pad d'amélioration selon son état (Shared.GearPad)
local GEAR_PAD_TONES: { [GearPad.Tone]: Color3 } = {
	Afford = COLORS.padGreen,
	Short = COLORS.padRed,
	Idle = COLORS.padGrey,
	Max = COLORS.padGold,
}

-- Cette méthode permet d'afficher sur le pad d'amélioration d'une place l'équipement suivant du palier `tier`, son EXP
-- par répétition et son prix (plaque verte si `money` suffit, rouge sinon, grise sans propriétaire), ou MAX, lorsque
-- l'équipement ou l'argent du propriétaire changent ; sans effet si le panneau n'a pas changé.
function CourseBuilder.styleGearPad(slot: Slot, tier: number, money: number?)
	local pad = slot.gearPad
	local panel = GearPad.panel(tier, money)
	local key = panel.title .. "|" .. panel.price .. "|" .. panel.tone
	if pad.shown == key then
		return
	end
	pad.shown = key
	pad.title.Text = panel.title
	pad.gain.Text = panel.gain
	pad.price.Text = panel.price
	pad.plate.Color = GEAR_PAD_TONES[panel.tone]
	pad.buy.ObjectText = panel.price
	pad.buy:SetAttribute("Price", panel.cost)
	pad.buy:SetAttribute("Maxed", if panel.tone == "Max" then true else nil)
end

-- Cette méthode permet de construire le pad d'amélioration de l'équipement d'une place (dalle violette au sol,
-- panneau en bois « NEXT: … » avec l'EXP et le prix, comme le pad de la barre de traction de la référence 09) à côté
-- de son appareil d'entraînement lorsque le hub est construit ; ses invites sont activées par le client du propriétaire.
local function buildGearPad(parent: Instance, slot: Slot): GearPadParts
	local spot, facing = CourseLayout.gearPadPosition(slot.index)
	local model = Instance.new("Model")
	model.Name = "GearPad" .. slot.index
	-- Repère : regard vers la bande ; le panneau est derrière la dalle (même gabarit que le pad de présentoir)
	local frame = CFrame.lookAt(spot, spot + facing)
	local slab = Build.block(model, Vector3.new(6, 0.3, 6), frame * CFrame.new(0, 0.15, -3), COLORS.gearPad)
	markObjective(slab, "BuyGear", slot.index) -- objectif « Buy better gear! » du tutoriel (#160 : plus le bouton Shop)
	slab.Name = "Slab"
	for _, side in { -1, 1 } do
		Build.block(model, Vector3.new(1, 8.4, 1), frame * CFrame.new(side * 3.5, 4.2, 2), COLORS.woodDark)
	end
	Build.block(model, Vector3.new(6, 6.6, 0.8), frame * CFrame.new(0, 5, 2), COLORS.wood)
	local titlePlate = Build.block(model, Vector3.new(5.6, 1.6, 0.2), frame * CFrame.new(0, 7.3, 1.5), COLORS.woodDark)
	local title = Build.surfaceText(titlePlate, Enum.NormalId.Front, "")
	local gainPlate = Build.block(model, Vector3.new(5.6, 1.2, 0.2), frame * CFrame.new(0, 5.7, 1.5), COLORS.woodDark)
	local gain = Build.surfaceText(gainPlate, Enum.NormalId.Front, "", Color3.fromRGB(90, 205, 255))
	local plate = Build.block(model, Vector3.new(4.6, 1.6, 0.3), frame * CFrame.new(0, 3.6, 1.45), COLORS.padGrey)
	local price = Build.surfaceText(plate, Enum.NormalId.Front, "")
	-- Cette méthode permet de poser une invite du pad (touche `key`, sur la dalle) lorsque le pad est construit.
	local function padPrompt(name: string, action: string, key: Enum.KeyCode, button: Enum.KeyCode, tag: string)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = action
		prompt.ObjectText = ""
		prompt.KeyboardKeyCode = key
		prompt.GamepadKeyCode = button
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt:SetAttribute("Slot", slot.index)
		CollectionService:AddTag(prompt, tag)
		prompt.Parent = slab
		return prompt
	end
	-- Achat à l'invite, pas au simple contact : pas d'achat involontaire en passant sur la dalle
	local buy = padPrompt("BuyGear", "Upgrade", Enum.KeyCode.E, Enum.KeyCode.ButtonX, GearPad.BUY_TAG)
	local view = padPrompt("ViewGear", "View all", Enum.KeyCode.F, Enum.KeyCode.ButtonY, GearPad.VIEW_TAG)
	view.ObjectText = "Training Gear"
	model.Parent = parent
	return { title = title, gain = gain, price = price, plate = plate, buy = buy, view = view }
end

-- Cette méthode permet de construire le pad d'achat de présentoir d'une place (dalle en briques vertes au sol,
-- panneau en bois « 8 > 9 » avec le prix sur une plaque verte, comme le pad « 8 > 9 » de la référence 09) devant la
-- base, lorsque le hub est construit ; l'invite « Buy display » est activée par le client du propriétaire, qui envoie
-- l'achat au serveur (remote Inventory).
local function buildPad(parent: Instance, slot: Slot): Pad
	local spot, facing = CourseLayout.padPosition(slot.index)
	local model = Instance.new("Model")
	model.Name = "DisplayPad" .. slot.index
	-- Repère : regard vers la bande ; le panneau est derrière la dalle
	local frame = CFrame.lookAt(spot, spot + facing)
	local slab = Build.block(model, Vector3.new(6, 0.3, 6), frame * CFrame.new(0, 0.15, -3), COLORS.padGreen)
	slab.Name = "Slab"
	for _, side in { -1, 1 } do
		Build.block(model, Vector3.new(1, 7.6, 1), frame * CFrame.new(side * 5, 3.8, 2), COLORS.woodDark)
	end
	Build.block(model, Vector3.new(11, 5.6, 0.8), frame * CFrame.new(0, 5, 2), COLORS.wood)
	local titlePlate = Build.block(model, Vector3.new(9, 2.6, 0.2), frame * CFrame.new(0, 6.2, 1.5), COLORS.woodDark)
	local title = Build.surfaceText(titlePlate, Enum.NormalId.Front, "8 > 9")
	local pricePlate = Build.block(model, Vector3.new(6, 1.6, 0.3), frame * CFrame.new(0, 3.6, 1.45), COLORS.padGreen)
	local price = Build.surfaceText(pricePlate, Enum.NormalId.Front, "")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyDisplay"
	prompt.ActionText = "Buy display"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("Slot", slot.index)
	CollectionService:AddTag(prompt, Collection.PAD_TAG)
	prompt.Parent = slab
	model.Parent = parent
	return { title = title, price = price, prompt = prompt }
end

-- Cette méthode permet de construire le texte flottant d'une base (portrait, nom, revenu, Throw Power et renaissances ; taille en
-- studs plus une marge en pixels, lisible de loin) lorsque la base est construite ; rempli par Server.BaseService.
local function baseLabel(parent: Instance, position: Vector3): BaseLabel
	local anchor = Build.decor({
		Name = "BaseLabel",
		Size = Vector3.one,
		Position = position,
		Transparency = 1,
		Parent = parent,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "BaseLabel"
	-- Taille de départ ; chaque client la borne ensuite à chaque image (Client.BaseFx, BaseLook.labelPixels, #150)
	local studs, pixels = BaseLook.LABEL_STUDS, BaseLook.LABEL_PIXELS
	gui.Size = UDim2.new(studs.X, pixels.X, studs.Y, pixels.Y)
	gui.SizeOffset = Vector2.new(0, 0.5) -- ancré par le bas
	gui.LightInfluence = 0
	gui.MaxDistance = LABEL_DISTANCE
	gui.Parent = anchor
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.fromScale(0.5, 0)
	avatar.Size = UDim2.fromScale(1, 0.26)
	avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
	avatar.BackgroundColor3 = Color3.new(1, 1, 1)
	avatar.Image = ""
	avatar.Visible = false
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = avatar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = avatar
	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = avatar
	avatar.Parent = gui
	-- Cette méthode permet de poser une ligne du texte (hauteur `height` à partir de `y`, couleur) lorsque le texte
	-- flottant est construit.
	local function line(name: string, y: number, height: number, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, height)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = ""
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Parent = label
		label.Parent = gui
		return label
	end
	-- Record (#44) sous le revenu, un peu plus petit : le revenu reste la ligne la plus lisible
	local power = line("Power", 0.84, 0.16, LABEL_CYAN)
	power.RichText = true -- compteur de renaissances en violet à côté de la Throw Power (Shared.BaseLook.label)
	local title = line("Title", 0.27, 0.22, Color3.new(1, 1, 1))
	title.RichText = true -- badge VIP doré devant le nom (passe de la boutique Robux, #160)
	return {
		avatar = avatar,
		title = title,
		income = line("Income", 0.49, 0.2, LABEL_GREEN),
		best = line("Best", 0.69, 0.15, LABEL_GOLD),
		power = power,
	}
end

-- Cette méthode permet de poser la clôture d'une base au style `fence` (ouverte côté bande, entrée de 10 studs) dans
-- `folder` lorsque la base est habillée ; renvoie les deux bouts de l'entrée, les quatre coins (fond puis entrée) et
-- les pieds des poteaux de chaque tronçon, au sol.
local function baseFence(
	folder: Instance,
	slot: Slot,
	fence: BaseLook.Fence
): ({ Vector3 }, { Vector3 }, { { Vector3 } })
	local center, size = CourseLayout.baseBox(slot.index, slot.base.big)
	local hx, hz = size.X / 2, size.Z / 2
	local corners = {
		center + Vector3.new(-hx, 0, -hz),
		center + Vector3.new(hx, 0, -hz),
		center + Vector3.new(hx, 0, hz),
		center + Vector3.new(-hx, 0, hz),
	}
	local gate = {}
	local runs = {}
	for i, from in corners do
		local to = corners[i % 4 + 1]
		-- Chaque coin n'a qu'un poteau : posé par le tronçon qui y finit ; l'entrée est au milieu du côté qui regarde la
		-- bande (CourseLayout.ENTRANCE)
		local side = ((from + to) / 2 - center).Unit
		if side:Dot(CourseLayout.ENTRANCE) > 0.99 then
			local mid = (from + to) / 2
			local dir = (to - from).Unit
			gate = { mid - dir * GATE_WIDTH / 2, mid + dir * GATE_WIDTH / 2 }
			table.insert(runs, Props.fence(folder, from, gate[1], fence, true))
			table.insert(runs, Props.fence(folder, gate[2], to, fence))
		else
			table.insert(runs, Props.fence(folder, from, to, fence, true))
		end
	end
	return gate, corners, runs
end

-- Cette méthode permet de garder l'ancien habillage d'une base 5 s dans ReplicatedStorage pour l'animation des clients
-- lorsque la base monte de palier ; false si celui d'une montée de la même image est gardé à sa place.
local function keepPrevious(base: Base, old: Folder): boolean
	local store = ReplicatedStorage:FindFirstChild(BaseUpgrade.STORE)
	if not store then
		store = Instance.new("Folder")
		store.Name = BaseUpgrade.STORE
		store.Parent = ReplicatedStorage
	end
	local earlier = store:FindFirstChild(base.model.Name)
	if earlier and earlier:GetAttribute("KeptAt") == time() then
		-- Deux montées dans la même image : les clients n'ont vu que le premier habillage, gardé
		old:Destroy()
		return false
	end
	if earlier then
		earlier:Destroy()
	end
	old:SetAttribute("KeptAt", time())
	old.Name = base.model.Name
	old.Parent = store
	task.delay(BaseUpgrade.KEEP, function()
		if old.Parent == store then
			old:Destroy()
		end
	end)
	return true
end

-- Cette méthode permet d'habiller une base au palier `tier` (`upgrade` : animée par les clients, Shared.BaseUpgrade)
-- lorsque son propriétaire change ou achète un présentoir ; renvoie false si la base avait déjà ce palier.
function CourseBuilder.styleBase(slot: Slot, tier: number, upgrade: boolean?): boolean
	local base = slot.base
	if base.tier == tier then
		return false
	end
	local look, fence, gateLook = BaseLook.base(tier)
	-- Nouvel habillage posé avant de retirer l'ancien : la clôture ne disparaît jamais
	local folder = Instance.new("Folder")
	folder.Name = "Look"
	local old = base.look
	local oldPlot = base.plot.Color
	base.plot.Color = look.plot or Build.shade(slot.color, 0.6)
	local center, size = CourseLayout.baseBox(slot.index, base.big)
	local hx, hz = size.X / 2, size.Z / 2
	-- Socles des présentoirs au palier (#198) : teinte, bandeau doré des hauts paliers (sa transparence suit le socle,
	-- Server.BaseService) ; pas de bandeau sur les présentoirs de Big Base tant que la base n'est pas agrandie
	local collars = {}
	for index, pedestal in base.pedestals do
		pedestal.Color = look.pedestal or COLORS.stone
		if look.collar and (index <= CourseLayout.DISPLAY_MAX or base.big) then
			collars[index] = Props.collar(folder, pedestal, look.collar)
		end
	end
	-- Clôture et décor du palier d'un tenant : une pièce qui en affleure une autre ressort un peu (#93)
	Build.settled(function()
		local gate, corners, runs = baseFence(folder, slot, fence)
		local lift = Vector3.new(0, BaseLook.postTop(fence), 0)
		local towers = look.corners == "tower"
		-- Entrée (#198) : piliers et linteau au style du palier, étoiles du rang ; les lanternes montent sur le linteau
		local a, b = Props.gate(folder, gate[1], gate[2], gateLook, look.stars, slot.color, CourseLayout.ENTRANCE)
		if look.lanterns >= 2 then
			Props.lantern(folder, a)
			Props.lantern(folder, b)
		end
		if look.lanterns >= 6 then
			for index, corner in corners do
				-- Coins du fond (1 et 2) : la tour remplace la lanterne de son poteau
				if not (towers and index <= 2) then
					Props.lantern(folder, corner + lift)
				end
			end
		end
		-- Lanternes sur les poteaux, symétriques sur chaque tronçon (09 : lanternes sur la clôture des jardins)
		for _, feet in runs do
			for _, rank in BaseLook.lanternPosts(#feet - 1, look.postLanterns) do
				Props.lantern(folder, feet[rank + 1] + lift)
			end
		end
		local plotTop = center.Y + PLOT_TOP
		local back = center.Z - (hz - BED_INSET)
		local front = center.Z + (hz - BED_INSET)
		local reach = hx - BED_END
		if look.flowers then
			-- Le long du fond (côté opposé à l'entrée) et de part et d'autre de l'entrée, entre clôture et présentoirs
			Props.flowerBed(
				folder,
				Vector3.new(center.X - reach, plotTop, back),
				Vector3.new(center.X + reach, plotTop, back)
			)
			for _, side in { -1, 1 } do
				Props.flowerBed(
					folder,
					Vector3.new(center.X + side * (GATE_WIDTH / 2 + 1.5), plotTop, front),
					Vector3.new(center.X + side * reach, plotTop, front)
				)
			end
		end
		if look.bushes then
			-- Buissons voxel au bout des massifs, côté clôtures de côté
			for _, side in { -1, 1 } do
				for _, z in { back, front } do
					Props.shrub(folder, Vector3.new(center.X + side * (reach + SHRUB_GAP), plotTop, z))
				end
			end
		end
		-- Élément en hauteur aux deux coins du fond, vu de loin (#198)
		for index = 1, 2 do
			local corner = corners[index]
			local outward = Vector3.new(math.sign(corner.X - center.X), 0, -1)
			if look.corners == "tree" then
				local foot = Vector3.new(corner.X - outward.X * TREE_INSET, plotTop, corner.Z + TREE_INSET)
				Props.cornerTree(folder, foot, outward)
			elseif towers then
				Props.tower(folder, corner, fence, CourseLayout.ENTRANCE, slot.color)
			end
		end
		if look.flags then
			for index, corner in corners do
				-- Coins du fond : le drapeau est au sommet de la tour
				if towers and index <= 2 then
					continue
				end
				local inside = Vector3.new(math.sign(center.X - corner.X), 0, math.sign(center.Z - corner.Z))
				-- Fanion tourné vers l'extérieur de la base, côté entrée ou fond
				local outward = Vector3.new(0, 0, -inside.Z)
				Props.flag(folder, Vector3.new(corner.X, plotTop, corner.Z) + inside * FLAG_INSET, outward, slot.color)
			end
		end
	end)
	if fence.shine then
		local zone = sparkles(
			folder,
			Vector3.new(hx * 2, 8, hz * 2),
			CFrame.new(center + Vector3.new(0, 6, 0)),
			rgb(255, 215, 80),
			14
		)
		zone:SetAttribute(BaseUpgrade.STAGE_ATTRIBUTE, 2)
	end
	folder.Parent = base.model
	if upgrade then
		-- Posés après l'habillage : un client qui les reçoit a déjà le nouveau et l'ancien (sol de départ : celui que les
		-- clients ont vu, gardé si une autre montée a eu lieu dans la même image)
		if keepPrevious(base, old) then
			base.model:SetAttribute(BaseUpgrade.FROM_PLOT_ATTRIBUTE, oldPlot)
		end
		base.model:SetAttribute(BaseUpgrade.AT_ATTRIBUTE, Workspace:GetServerTimeNow())
	else
		old:Destroy()
	end
	base.look = folder
	base.collars = collars
	base.tier = tier
	return true
end

-- Cette méthode permet d'agrandir la base d'une place vers le fond (ou de la rendre à sa taille) lorsque son
-- propriétaire a le passe Big Base (#160) ou qu'il part : terrain étiré, clôture et décor refaits au même palier.
function CourseBuilder.setBaseBig(slot: Slot, big: boolean)
	local base = slot.base
	if base.big == big then
		return
	end
	base.big = big
	local center, size = CourseLayout.baseBox(slot.index, big)
	base.plot.Size = Vector3.new(size.X, PLOT_TOP, size.Z)
	base.plot.Position = center + Vector3.new(0, PLOT_TOP / 2, 0)
	local tier = base.tier
	base.tier = 0 -- habillage refait au même palier, sans animation de construction
	CourseBuilder.styleBase(slot, tier)
end

-- Cette méthode permet de construire la base d'une place (terrain, présentoirs vides, texte flottant, confettis
-- d'achat, habillage du premier palier, pad d'amélioration de l'équipement) lorsque le hub est construit.
local function buildBase(parent: Instance, slot: Slot)
	local center = CourseLayout.basePosition(slot.index)
	local size = CourseLayout.BASE_SIZE
	local model = Instance.new("Model")
	model.Name = "Base" .. slot.index
	CollectionService:AddTag(model, BaseUpgrade.BASE_TAG) -- animation de construction, taille du texte (Client.BaseFx)
	local plot = Build.decor({
		Name = "Plot",
		Size = Vector3.new(size.X, PLOT_TOP, size.Z),
		Position = center + Vector3.new(0, PLOT_TOP / 2, 0),
		Color = COLORS.plot,
		Variant = Build.BRICK,
		Parent = model,
	})
	local look = Instance.new("Folder")
	look.Name = "Look"
	look.Parent = model
	local displays: { BasePart } = {}
	local pedestals: { BasePart } = {}
	for index, position in CourseLayout.displayPositions(slot.index, CourseLayout.DISPLAY_ROOM) do
		local side = CourseLayout.PEDESTAL_SIZE
		local pedestal = Build.block(
			model,
			Vector3.new(side, 1.6, side),
			CFrame.new(position + Vector3.new(0, 0.8, 0)),
			COLORS.stone
		)
		table.insert(pedestals, pedestal)
		local top = Build.block(
			model,
			Vector3.new(side - 0.6, 0.4, side - 0.6),
			CFrame.new(position + Vector3.new(0, 1.8, 0)),
			slot.color
		)
		top.Name = "Display" .. index
		-- Cible d'objectif de cette place ; l'attribut Objective (« Place » si libre) est posé par Server.BaseService
		top:SetAttribute("Slot", slot.index)
		CollectionService:AddTag(top, Objectives.TAG)
		-- Invite « Place » : désactivée ici, chaque client l'active sur les présentoirs libres de sa base quand il tient
		-- un mannequin gagné (le serveur valide la pose)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Place"
		prompt.ActionText = "Place"
		prompt.ObjectText = "Display"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt:SetAttribute("Slot", slot.index)
		prompt:SetAttribute("Display", index)
		CollectionService:AddTag(prompt, Collection.PROMPT_TAG)
		prompt.Parent = top
		table.insert(displays, top)
	end
	model.Parent = parent
	slot.base = {
		model = model,
		plot = plot,
		look = look,
		tier = 0,
		big = false,
		-- Au-dessus du centre de la base, plus haut que les plus grands mannequins posés (comme les jardins de 09)
		label = baseLabel(model, center + Vector3.new(0, LABEL_HEIGHT, 0)),
		burst = upgradeBurst(model, center + Vector3.new(0, 3, 0), slot.color),
		displays = displays,
		pedestals = pedestals,
		collars = {},
		facing = CourseLayout.ENTRANCE,
		pad = Build.settled(buildPad, parent, slot),
	}
	CourseBuilder.styleBase(slot, 1)
	slot.gearPad = Build.settled(buildGearPad, parent, slot)
	CourseBuilder.styleGearPad(slot, 1, nil)
end

-- Cette méthode permet de poser l'invite d'un stand du hub (E, sans maintien, 10 studs, marquée `tag` : chaque client
-- y ouvre sa fenêtre) au point `position` lorsque l'on bâtit les stands.
local function standPrompt(parent: Instance, position: Vector3, action: string, object: string, tag: string)
	local anchor = Build.decor({
		Name = object .. "Prompt",
		Size = Vector3.one,
		CFrame = CFrame.new(position),
		Transparency = 1,
		Parent = parent,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	CollectionService:AddTag(prompt, tag)
	prompt.Parent = anchor
end

-- Cette méthode permet de tracer au sol `count` chevrons jaunes pointés vers la bande (+Z), le premier en (`x`, `z`),
-- tous les 6 studs, lorsque l'on balise un chemin du hub vers la zone de lancer (01 / 09).
local function chevrons(parent: Instance, x: number, z: number, count: number)
	for i = 0, count - 1 do
		for _, side in { -1, 1 } do
			Build.decor({
				Name = "Chevron",
				Size = Vector3.new(3.2, 0.1, 1),
				CFrame = CFrame.new(x + side * 1.1, 0.06, z + i * 6) * CFrame.Angles(0, math.rad(side * 45), 0),
				Color = COLORS.pad,
				Parent = parent,
			})
		end
	end
end

-- Cette méthode permet de poser la zone d'événement réservée (#120 : dallage clair bordé de blanc, vide, et pancarte
-- « EVENTS · SOON » au style des stands) au bout de la rangée des tableaux lorsque le hub est construit ; rien de jouable.
local function buildEventArea(parent: Instance)
	local center = CourseLayout.eventPosition()
	local size = CourseLayout.EVENT_SIZE
	local model = Instance.new("Model")
	model.Name = "EventArea"
	Build.part({
		Name = "Paving",
		Size = Vector3.new(size.X, 0.3, size.Z),
		Position = center + Vector3.new(0, 0.15, 0),
		Color = COLORS.stone,
		Variant = Build.CHECKER,
		Parent = model,
	})
	-- Bordure blanche à peine surélevée, comme le liseré de la bande
	for _, edge in
		{
			{ Vector3.new(size.X, 0.5, 1), Vector3.new(0, 0, size.Z / 2 - 0.5) },
			{ Vector3.new(size.X, 0.5, 1), Vector3.new(0, 0, -size.Z / 2 + 0.5) },
			{ Vector3.new(1, 0.5, size.Z - 2), Vector3.new(size.X / 2 - 0.5, 0, 0) },
			{ Vector3.new(1, 0.5, size.Z - 2), Vector3.new(-size.X / 2 + 0.5, 0, 0) },
		}
	do
		Build.part({
			Name = "Border",
			Size = edge[1],
			Position = center + edge[2] + Vector3.new(0, 0.25, 0),
			Color = COLORS.line,
			Variant = Build.BRICK,
			Parent = model,
		})
	end
	-- Pancarte au fond de la zone, tournée vers les bases
	Props.comingSoon(model, CFrame.new(center + Vector3.new(0, 0.3, size.Z / 2 - 4)), "EVENTS", "SOON")
	model.Parent = parent
end

-- Cette méthode permet de construire le hub (pelouse à damier, parois en gradins, rangée des bases avec leurs appareils
-- et pads, stands, tableaux de scores et zone d'événement au bord de la bande, chevrons vers la bande, arbres, point
-- d'apparition) lorsque le serveur démarre ; renvoie les tableaux de scores (remplis par Server.LeaderboardService) et
-- le décor des parois, à poser quand celles de la piste (`walls`, zone commune) sont montées.
local function buildHub(parent: Instance, slots: { Slot }, walls: SurfaceGap.Area): ({ Props.Scoreboard }, { () -> () })
	local zone = Zones.LIST[1]
	local halfW = GameConfig.HUB_WIDTH / 2
	local front = CourseLayout.HUB_FRONT
	local back = CourseLayout.HUB_BACK
	ground(parent, -halfW, halfW, back, front, zone.ground, "Hub")
	-- Parois : côtés (jusqu'aux épaulements de la piste) et fond
	-- Coins du fond : la paroi du fond les couvre (FILL), les côtés s'y arrêtent ; devant, la piste passe par-dessus
	local right, left = Vector3.new(halfW, 0, 0), Vector3.new(-halfW, 0, 0)
	local backZ, frontZ = Vector3.new(0, 0, back), Vector3.new(0, 0, front)
	local decor = {
		terraces(walls, parent, left + backZ, right + backZ, Vector3.zAxis, zone, 1, 1, FILL, FILL),
		terraces(walls, parent, right + backZ, right + frontZ, -Vector3.xAxis, zone, 1, 1, JOINT, UNDER),
		terraces(walls, parent, left + frontZ, left + backZ, Vector3.xAxis, zone, 1, 1, UNDER, JOINT),
	}
	-- Les épaulements entre le hub (large) et la piste (étroite) sont les bouts des parois de la piste : stands et
	-- tableaux s'y adossent, de part et d'autre de la bande

	for _, slot in slots do
		buildStation(parent, slot)
		buildBase(parent, slot)
		-- Chevrons de l'entrée de la base vers la bande
		Build.settled(chevrons, parent, CourseLayout.basePosition(slot.index).X, CourseLayout.BASE_FRONT + 4, 3)
	end
	-- Stands (#68) à gauche de la bande : boutique des mannequins à lancer (#14), vente des mannequins de collection
	local shopAt = CourseLayout.standFrame("shop")
	local shop = Props.shopStand(parent, shopAt, ThrowDummies.DISPLAY_TAG, ThrowDummies.SHOWCASE)
	-- Invite du stand SHOP : chaque client y ouvre la boutique des mannequins à lancer
	standPrompt(parent, shop.prompt, "Buy dummies", "SHOP", ThrowDummies.SHOP_TAG)
	local sellAt = CourseLayout.standFrame("sell")
	Props.sellStand(parent, sellAt)
	-- Invite du stand SELL, devant le comptoir : chaque client y ouvre sa fenêtre de vente
	standPrompt(parent, (sellAt * CFrame.new(0, 3, -6)).Position, "Sell dummies", "SELL", Collection.SELL_TAG)
	-- Tableaux de scores à droite de la bande (#120), puis la zone d'événement réservée
	local boards = {}
	for index, board in Leaderboard.BOARDS do
		table.insert(boards, Props.scoreboard(parent, CourseLayout.boardFrame(index), board))
	end
	Build.settled(buildEventArea, parent)
	-- Chevrons du point d'apparition vers la bande
	Build.settled(chevrons, parent, 0, CourseLayout.SPAWN.Z + 4, 3)
	-- Arbres et buissons aux coins du fond et le long des côtés, à côté des bases du bout de la rangée (un arbre qui
	-- affleure une paroi ou un voisin en ressort un peu)
	Build.within(walls, function()
		for _, side in { -1, 1 } do
			for _ = 1, 5 do
				local position =
					Vector3.new(side * rng:NextNumber(halfW - 12, halfW - 4), 0, rng:NextNumber(back + 4, back + 20))
				Props.build(if rng:NextNumber() < 0.6 then "tree" else "bush", parent, CFrame.new(position), rng, true)
			end
			for _ = 1, 4 do
				local position =
					Vector3.new(side * rng:NextNumber(halfW - 14, halfW - 5), 0, rng:NextNumber(back + 24, -52))
				Props.build(if rng:NextNumber() < 0.6 then "tree" else "bush", parent, CFrame.new(position), rng, true)
			end
		end
	end)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	-- Face à la bande (+Z)
	spawn.CFrame =
		CFrame.lookAt(CourseLayout.SPAWN + Vector3.new(0, 0.5, 0), CourseLayout.SPAWN + Vector3.new(0, 0.5, 1))
	spawn.Parent = parent
	return boards, decor
end

-- Cette méthode permet de dresser l'arche d'arrivée traversable (ligne et bandeau à damier, piliers, panneau « FINISH »)
-- au bout de la piste lorsqu'elle est construite : le mannequin passe dessous et finit contre la paroi du bout (#97).
local function buildFinish(parent: Instance)
	local half = GameConfig.TRACK_WIDTH / 2
	local z = GameConfig.COURSE_LENGTH
	local model = Instance.new("Model")
	model.Name = "FinishArch"
	local tiles = 20
	local tile = GameConfig.TRACK_WIDTH / tiles
	for row = 0, 1 do
		for col = 0, tiles - 1 do
			Build.decor({
				Name = "FinishLine",
				Size = Vector3.new(tile, 0.1, 1.6),
				Position = Vector3.new(-half + (col + 0.5) * tile, 0.05, z + (row - 0.5) * 1.6),
				Color = if (row + col) % 2 == 0 then COLORS.line else rgb(30, 30, 35),
				Parent = model,
			})
		end
	end
	local height = 24
	local pillarX = half - 3
	for _, side in { -1, 1 } do
		Build.block(model, Vector3.new(3, height, 3), CFrame.new(side * pillarX, height / 2, z), COLORS.line, false)
		Build.block(model, Vector3.new(4, 1.2, 4), CFrame.new(side * pillarX, height + 0.6, z), COLORS.pad, false)
	end
	-- Bandeau à damier entre les piliers, deux rangées
	local span = 2 * pillarX - 3
	local count = 16
	local width = span / count
	for row = 0, 1 do
		for col = 0, count - 1 do
			Build.block(
				model,
				Vector3.new(width, 1.6, 1.2),
				CFrame.new(-span / 2 + (col + 0.5) * width, height - 0.8 - row * 1.6, z),
				if (row + col) % 2 == 0 then COLORS.line else rgb(30, 30, 35),
				false
			)
		end
	end
	local last = Zones.LIST[#Zones.LIST]
	local board = Build.block(model, Vector3.new(30, 6, 1), CFrame.new(0, height - 6.4, z), last.color, false)
	Build.surfaceText(board, Enum.NormalId.Front, string.format("FINISH  %g KM", GameConfig.COURSE_LENGTH / 1000))
	model.Parent = parent
end

-- Cette méthode permet de construire la piste (sol, parois de chaque zone dans `walls`, arche d'arrivée, paroi du bout)
-- lorsque le serveur démarre ; renvoie de quoi poser son décor, qui rend le temps de chaque zone (ms) pour le journal.
local function buildTrack(parent: Instance, walls: SurfaceGap.Area): () -> { string }
	local half = GameConfig.TRACK_WIDTH / 2
	local length = GameConfig.COURSE_LENGTH
	local spent: { number } = {} -- temps de chaque zone (s), marches puis décor
	local traps = TrackPlan.trapBoxes(TrackPlan.sites(length)) -- emprise des pièges, laissée libre au pied des parois
	local dressers: { () -> () } = {}
	for index, zone in Zones.LIST do
		local started = os.clock()
		local folder = Instance.new("Folder")
		folder.Name = "Zone" .. index
		local zoneStart = zone.start
		local zoneEnd = if index == #Zones.LIST then END_Z else Zones.finish(index, length)
		ground(folder, -half, half, zoneStart, zoneEnd, zone.ground, "Track")
		-- Les parois de la dernière zone dépassent la paroi de bout de piste (pas de trou aux coins)
		local wallEnd = if index == #Zones.LIST then END_Z + END_EXTRA else zoneEnd
		-- Parois : la première zone part des épaulements (z = -LAUNCH_DEPTH), les marches hautes reculent avec eux
		local wallStart = if index == 1 then -GameConfig.LAUNCH_DEPTH else zoneStart
		local grow = if index == 1 then -1 else 0
		-- Bouts : épaulement du hub (la couverture avance sur celle du hub), raccord avec la zone voisine, ou au-delà de la
		-- paroi de bout de piste
		local first = if index == 1 then FREE else JOINT
		local last = if index == #Zones.LIST then BEYOND_END else JOINT
		local right, left = Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0)
		local z0, z1 = Vector3.new(0, 0, wallStart), Vector3.new(0, 0, wallEnd)
		local decor = {
			terraces(walls, folder, right + z0, right + z1, -Vector3.xAxis, zone, grow, 0, first, last),
			terraces(walls, folder, left + z1, left + z0, Vector3.xAxis, zone, 0, grow, last, first),
		}
		-- Ligne d'entrée de zone, que les accessoires qui la touchent devront éviter
		if index > 1 then
			Build.keep(walls, Build.decor, {
				Name = "ZoneLine",
				Size = Vector3.new(GameConfig.TRACK_WIDTH, 0.1, 1.2),
				Position = Vector3.new(0, 0.05, zoneStart),
				Color = COLORS.line,
				Parent = folder,
			})
		end
		folder.Parent = parent
		spent[index] = os.clock() - started
		-- Cette méthode permet de poser le décor de la zone (gradins, pied des parois, panneaux d'entrée) lorsque toutes
		-- les parois et lignes qu'il peut toucher sont posées.
		dressers[index] = function()
			local begun = os.clock()
			for _, decorate in decor do
				decorate()
			end
			-- Décor au pied des parois (traversable : le mannequin ne s'y accroche pas), arrêté avant les piliers de
			-- l'arche d'arrivée qui sont dans sa rangée
			local footEnd = if index == #Zones.LIST then length - FINISH_CLEARANCE else zoneEnd
			for _, side in { -1, 1 } do
				local x = side * (half - 4)
				local from, to = Vector3.new(x, 0, math.max(zoneStart, 8)), Vector3.new(x, 0, footEnd)
				Build.within(walls, scatter, folder, zone, from, to, 22, Vector3.xAxis, 1.5, false, traps)
			end
			-- Panneaux d'entrée de zone (pas au départ : la zone de lancer reste dégagée, comme dans les références), au
			-- pied des parois : ils ressortent un peu des accessoires qu'ils touchent
			if index > 1 then
				local label = string.format("%s  x%s CHANCE", string.upper(zone.name), zone.chance)
				for _, side in { -1, 1 } do
					local at = CFrame.new(side * (half - 9), 0, zoneStart + 4)
					Build.within(walls, Props.signpost, folder, at, label, zone.color)
				end
			end
			spent[index] += os.clock() - begun
		end
	end
	Build.settled(buildFinish, parent)
	-- Paroi de bout de piste, en gradins tournés vers le départ
	local from, to = Vector3.new(half, 0, END_Z), Vector3.new(-half, 0, END_Z)
	local endDecor = terraces(walls, parent, from, to, -Vector3.zAxis, Zones.LIST[#Zones.LIST], 1, 1, INNER, INNER)
	-- Parois invisibles au-dessus des gradins (côtés et bout de piste) : les mannequins restent dans le canyon
	local _, topHeight = CourseLayout.tier(CourseLayout.TIER_COUNT - 1)
	local innerTop = CourseLayout.tier(CourseLayout.TIER_COUNT - 1)
	local wallY = topHeight + GameConfig.SIDE_WALL_HEIGHT / 2
	local z = -GameConfig.LAUNCH_DEPTH
	local endZ = END_Z + innerTop - half -- recul de la dernière marche de la paroi du bout
	while z < endZ - 0.01 do
		local span = math.min(SEGMENT_LENGTH, endZ - z)
		for _, side in { -1, 1 } do
			Build.part({
				Name = "SideWall",
				Size = Vector3.new(1, GameConfig.SIDE_WALL_HEIGHT, span),
				Position = Vector3.new(side * (innerTop + 0.5), wallY, z + span / 2),
				Transparency = 1,
				CanQuery = false,
				Parent = parent,
			})
		end
		z += span
	end
	-- Près du départ, les marches hautes reculent (épaulements) : la paroi invisible y descend jusqu'à la première marche
	local _, firstTop = CourseLayout.tier(0)
	local shoulder = (CourseLayout.TIER_COUNT - 1) * CourseLayout.TIER_STEP
	for _, side in { -1, 1 } do
		Build.part({
			Name = "SideWall",
			Size = Vector3.new(1, topHeight - firstTop, shoulder),
			Position = Vector3.new(
				side * (innerTop + 0.5),
				(firstTop + topHeight) / 2,
				-GameConfig.LAUNCH_DEPTH + shoulder / 2
			),
			Transparency = 1,
			CanQuery = false,
			Parent = parent,
		})
	end
	Build.part({
		Name = "EndWall",
		Size = Vector3.new(2 * innerTop + 2, GameConfig.SIDE_WALL_HEIGHT, 1),
		Position = Vector3.new(0, wallY, endZ + 0.5),
		Transparency = 1,
		CanQuery = false,
		Parent = parent,
	})
	-- Cette méthode permet de poser le décor de toutes les zones puis celui de la paroi du bout lorsque toutes les parois
	-- sont montées ; renvoie le temps de chaque zone.
	return function()
		for _, dress in dressers do
			dress()
		end
		endDecor()
		local timings = {}
		for index, zone in Zones.LIST do
			table.insert(timings, string.format("%s %.0f", zone.name, spent[index] * 1000))
		end
		return timings
	end
end

-- Cette méthode permet de créer les places des joueurs (position, couleur, repères) avant que le décor ne les habille
-- lorsque le serveur démarre.
local function newSlots(): { Slot }
	-- Direction commune, recalculée par le lanceur au lâcher (Shared.ThrowStart, #144)
	local direction = ThrowStart.DIRECTION
	local slots = {}
	for index = 1, GameConfig.SLOT_COUNT do
		local launchPoint = CourseLayout.launchPoint(index)
		local stationGround, stationFacing = CourseLayout.stationPosition(index)
		-- Avatar debout sur la pastille du podium (HumanoidRootPart à 3 studs au-dessus des pieds), dos au râtelier
		local stationPos = stationGround + Vector3.new(0, STATION_HEIGHT + 3, 0) + stationFacing * STATION_SPOT
		local spawnPos = Vector3.new(launchPoint.X, 3, -GameConfig.BAND_DEPTH - SPAWN_BACK)
		slots[index] = {
			index = index,
			color = CourseLayout.SLOT_COLORS[(index - 1) % #CourseLayout.SLOT_COLORS + 1],
			launchPoint = launchPoint,
			station = CFrame.lookAt(stationPos, stationPos + stationFacing),
			prompt = nil :: any,
			trainer = nil :: any,
			base = nil :: any,
			direction = direction,
			spawn = CFrame.lookAt(spawnPos, spawnPos + Vector3.zAxis),
		}
	end
	return slots
end

-- Cette méthode permet de construire tout le décor (hub, zone de lancer, piste, obstacles, lumière) lorsque le serveur
-- démarre ; renvoie les places des joueurs et le dossier des mannequins lancés.
function CourseBuilder.build(): Course
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	setupLighting()
	local started = os.clock()
	local course = Instance.new("Folder")
	course.Name = "Course"
	local slots = newSlots()
	-- Parois du hub et de la piste dans une même zone : leur décor (posé une fois toutes montées) et celui du pied des
	-- parois ressortent un peu de tout ce qu'ils touchent, d'une zone à l'autre comprise (#93)
	local walls = SurfaceGap.area()
	local boards, hubDecor = buildHub(course, slots, walls)
	buildLaunchZone(course)
	local hubTime = os.clock() - started
	local dressTrack = buildTrack(course, walls)
	local hubDecorStarted = os.clock()
	for _, decorate in hubDecor do
		decorate()
	end
	hubTime += os.clock() - hubDecorStarted
	local zoneTimes = dressTrack()
	local trackTime = os.clock() - started - hubTime
	local dummies = Instance.new("Folder")
	dummies.Name = "Dummies"
	dummies.Parent = course
	course.Parent = Workspace
	local obstaclesStarted = os.clock()
	Obstacles.build(course)
	-- Coût du décor généré (#97) : temps par étape et par zone, nombre d'instances
	print(
		string.format(
			"[Course] construit en %.0f ms (hub et zone de lancer %.0f, piste %.0f, obstacles %.0f), %d instances ; zones (ms) : %s",
			(os.clock() - started) * 1000,
			hubTime * 1000,
			trackTime * 1000,
			(os.clock() - obstaclesStarted) * 1000,
			#course:GetDescendants(),
			table.concat(zoneTimes, ", ")
		)
	)
	if DummyShape.meshStage() < 2 then
		watchRackTemplates()
	end
	return { slots = slots, dummies = dummies, boards = boards }
end

return CourseBuilder
