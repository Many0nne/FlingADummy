-- Construction du décor au style des jeux de référence (01 / 09) : hub en pelouse à damier (bases des joueurs avec leur
-- appareil d'entraînement devant l'entrée, stands à auvents), bande de lancer commune, piste unique
-- au fond d'un canyon en gradins (parois à briques, herbe voxel qui déborde, arbres et rochers voxel) qui change de
-- couleurs à chaque zone, obstacles partagés (Server.Obstacles). Repère : Shared.CourseLayout.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseLook = require(ReplicatedStorage.Shared.BaseLook)
local Collection = require(ReplicatedStorage.Shared.Collection)
local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local Drips = require(ReplicatedStorage.Shared.Drips)
local DummyShape = require(ReplicatedStorage.Shared.DummyShape)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Objectives = require(ReplicatedStorage.Shared.Objectives)
local ThrowDummies = require(ReplicatedStorage.Shared.ThrowDummies)
local Training = require(ReplicatedStorage.Shared.Training)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Build = require(script.Parent.Build)
local CollisionGroups = require(script.Parent.CollisionGroups)
local Obstacles = require(script.Parent.Obstacles)
local Props = require(script.Parent.Props)

type Zone = Zones.Zone

local SEED = 20261120 -- décor identique d'un serveur à l'autre
local SEGMENT_LENGTH = 400 -- longueur maximale d'une pièce de sol ou de paroi (limite : 2 048 studs)
local CAP_THICKNESS = Drips.CAP_THICKNESS
local CAP_OVERHANG = 1 -- l'herbe déborde du bord de chaque marche
local END_Z = GameConfig.COURSE_LENGTH + 40 -- fond du canyon, derrière la paroi de bout de piste
local STATION_HEIGHT = 1.4 -- hauteur du podium de l'appareil d'entraînement
local STATION_SPOT = 0.6 -- avance de la place de l'avatar devant le centre du podium (le râtelier est derrière)
local RACK_SCALE = 0.5 -- taille des mannequins suspendus au râtelier (sans se toucher)
local RACK_HEIGHT = 7.2 -- hauteur des montants du râtelier au-dessus du podium
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
	plot = rgb(175, 115, 65),
	wood = rgb(200, 140, 80),
	woodDark = rgb(150, 95, 50),
	stone = rgb(200, 200, 210),
	woodLight = rgb(225, 170, 105),
	rope = rgb(235, 215, 165),
	metal = rgb(70, 72, 80),
}

local PLOT_TOP = 0.3 -- épaisseur du terrain d'une base (dessus au-dessus de la pelouse)
local GATE_WIDTH = 10 -- entrée de la base, côté hub
local BED_INSET = 2.2 -- du bord de la base à l'axe d'un massif de fleurs
local BED_END = 5 -- massifs arrêtés à cette distance des clôtures avant et arrière
local FLAG_INSET = 2.5 -- drapeaux plantés à l'intérieur des coins
local LABEL_HEIGHT = 24 -- texte flottant de la base, au-dessus de son centre (au-dessus des plus grands mannequins posés)
local LABEL_SIZE = Vector2.new(14, 8) -- taille du texte flottant en studs (plus une marge en pixels : lisible de loin)
local LABEL_DISTANCE = 600 -- distance d'affichage du texte flottant (tout le hub et la zone de lancer)
local LABEL_GREEN = Color3.fromRGB(80, 215, 70) -- revenu (vert du HUD)
local LABEL_CYAN = Color3.fromRGB(90, 205, 255) -- Throw Power (cyan du HUD)

-- Pad d'achat de présentoir devant la base (panneau « 6 > 7 » et prix, mis à jour par Server.BaseService)
export type Pad = { title: TextLabel, price: TextLabel, prompt: ProximityPrompt }

-- Texte flottant au-dessus de la base (#91), rempli par Server.BaseService (Shared.BaseLook.label)
export type BaseLabel = { avatar: ImageLabel, title: TextLabel, income: TextLabel, power: TextLabel }

export type Base = {
	model: Model,
	plot: BasePart, -- terrain, teinté au palier
	look: Folder, -- clôture et décor du palier visuel (Shared.BaseLook), refaits à chaque palier
	tier: number, -- palier visuel affiché
	label: BaseLabel,
	burst: BasePart, -- confettis d'achat de présentoir (CourseBuilder.celebrate)
	displays: { BasePart }, -- dessus des DISPLAY_MAX présentoirs (invite « Place » dedans), grisés tant que pas achetés
	pedestals: { BasePart }, -- socles des présentoirs
	facing: number, -- côté de l'entrée (±1 sur X) : les mannequins posés regardent par là
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
	station: CFrame, -- position de l'avatar qui s'entraîne (sur le podium, face au centre du hub)
	prompt: ProximityPrompt, -- « Lift » sur l'appareil d'entraînement, devant la base
	trainer: Trainer, -- appareil d'entraînement, habillé par Server.TrainingService
	base: Base, -- présentoirs, remplis par Server.BaseService
	direction: Vector3,
	spawn: CFrame, -- réapparition et retour après un lancer : dans le hub, juste derrière la bande, face à la piste
}

export type Course = { slots: { Slot }, dummies: Folder }

local CourseBuilder = {}

local rng = Random.new(SEED)
-- Par place : repose les mannequins de son râtelier quand les gabarits maillés arrivent
local rackPlacers: { [number]: () -> () } = {}

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
-- `spacing`, écart latéral `jitter` le long de `side`) lorsque l'on habille une marche ou le pied d'une paroi.
local function scatter(
	parent: Instance,
	zone: Zone,
	from: Vector3,
	to: Vector3,
	spacing: number,
	side: Vector3,
	jitter: number,
	solid: boolean
)
	local delta = to - from
	local length = delta.Magnitude
	local direction = delta.Unit
	local t = rng:NextNumber(0, spacing)
	while t < length do
		local kind = zone.props[rng:NextInteger(1, #zone.props)]
		local position = from + direction * t + side * rng:NextNumber(-jitter, jitter)
		Props.build(
			kind,
			parent,
			CFrame.new(position) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0),
			rng,
			solid
		)
		t += spacing * rng:NextNumber(0.6, 1.4)
	end
end

-- Cette méthode permet de monter une paroi en gradins coiffés d'herbe et décorés (bord de `start` à `finish`, tournée vers
-- `facing`) lorsque l'on borde le hub ou la piste ; `grow` ±1 allonge ou raccourcit les marches hautes à chaque bout.
local function terraces(
	parent: Instance,
	start: Vector3,
	finish: Vector3,
	facing: Vector3,
	zone: Zone,
	growStart: number,
	growEnd: number
)
	local along = (finish - start).Unit
	for tier = 0, CourseLayout.TIER_COUNT - 1 do
		local _, top = CourseLayout.tier(tier)
		local back = tier * CourseLayout.TIER_STEP -- recul de la marche
		local a = start - along * (growStart * back) - facing * back
		local b = finish + along * (growEnd * back) - facing * back
		-- Bloc de la marche : du bord jusqu'au bord extérieur du plateau
		local depth = CourseLayout.OUTER - GameConfig.TRACK_WIDTH / 2 - back
		local outer = -facing * depth
		local low = Vector3.new(
			math.min(a.X, b.X + outer.X, a.X + outer.X, b.X),
			top - CourseLayout.TIER_HEIGHT,
			math.min(a.Z, b.Z + outer.Z, a.Z + outer.Z, b.Z)
		)
		local high = Vector3.new(
			math.max(a.X, b.X + outer.X, a.X + outer.X, b.X),
			top,
			math.max(a.Z, b.Z + outer.Z, a.Z + outer.Z, b.Z)
		)
		box(parent, low, high, zone.wall, Build.WALL, "Terrace")
		-- Couverture de tout le dessus du bloc (cachée sous la marche suivante), qui déborde côté zone ouverte ; pas aux
		-- bouts, où elle chevaucherait la couverture de la paroi voisine
		local c0 = a + facing * CAP_OVERHANG
		local c1 = b + outer
		box(
			parent,
			Vector3.new(math.min(c0.X, c1.X), top - 0.4, math.min(c0.Z, c1.Z)),
			Vector3.new(math.max(c0.X, c1.X), top + CAP_THICKNESS - 0.4, math.max(c0.Z, c1.Z)),
			zone.top,
			Build.WALL,
			"TerraceTop"
		)
		drips(parent, a + Vector3.new(0, top - 0.4, 0), facing, (b - a).Magnitude, zone.top, low, high)
		-- Décor du terre-plein (marches) ou du plateau (dernière marche, deux rangées)
		local ground0 = a + Vector3.new(0, top + CAP_THICKNESS - 0.4, 0) - facing * (CourseLayout.TIER_STEP / 2)
		local ground1 = b + Vector3.new(0, top + CAP_THICKNESS - 0.4, 0) - facing * (CourseLayout.TIER_STEP / 2)
		if tier < CourseLayout.TIER_COUNT - 1 then
			scatter(parent, zone, ground0, ground1, 26, facing, 1.5, true)
		else
			scatter(parent, zone, ground0, ground1, 16, facing, 2, true)
			scatter(parent, zone, ground0 - facing * 22, ground1 - facing * 22, 18, facing, 8, true)
		end
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
		Size = Vector3.new(GameConfig.TRACK_WIDTH, 1.2, CourseLayout.BAND_EDGE),
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
-- lorsque l'appareil est construit ; `hook` = repère au sommet de sa tête (face vers -Z).
local function rackDummy(parent: Instance, gear: Training.Gear, hook: CFrame)
	local model = Instance.new("Model")
	model.Name = "RackDummy"
	local parts = DummyShape.buildPieces(model, RACK_SCALE, { color = gear.color, material = gear.material })
	local highest = -math.huge
	for _, part in parts do
		highest = math.max(highest, part.Position.Y + part.Size.Y / 2)
	end
	-- Pas de cibles de crash-test (mannequin en blocs) : ce mannequin-là ne se lance pas
	for _, gui in parts.Torso:GetChildren() do
		if gui:IsA("SurfaceGui") then
			gui:Destroy()
		end
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = hook * CFrame.new(0, -highest, 0) * part.CFrame
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
local function sparkles(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, rate: number)
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
	fine(model, Vector3.new(size, h - 0.9, size), floor * CFrame.new(0, 0.5 + (h - 0.9) / 2, 0), COLORS.stone)
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
	local postX = 3.9
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
			rackDummy(model, Training.GEARS[rack[i]], top * CFrame.new(x, hookY, z))
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
	buildPodium(fresh, trainer.floor, slot.color, look)
	buildRack(fresh, trainer.floor * CFrame.new(0, STATION_HEIGHT, 0), slot.color, look, tier, slot.index)
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

-- Cette méthode permet de construire le pad d'achat de présentoir d'une place (dalle en briques vertes au sol,
-- panneau en bois « 6 > 7 » avec le prix sur une plaque verte, comme le pad « 8 > 9 » de la référence 09) devant la
-- base, lorsque le hub est construit ; l'invite « Buy display » est activée par le client du propriétaire, qui envoie
-- l'achat au serveur (remote Inventory).
local function buildPad(parent: Instance, slot: Slot): Pad
	local spot, facing = CourseLayout.padPosition(slot.index)
	local model = Instance.new("Model")
	model.Name = "DisplayPad" .. slot.index
	-- Repère : regard vers le centre du hub ; le panneau est derrière la dalle
	local frame = CFrame.lookAt(spot, spot + facing)
	local slab = Build.block(model, Vector3.new(6, 0.3, 6), frame * CFrame.new(0, 0.15, -3), COLORS.padGreen)
	slab.Name = "Slab"
	for _, side in { -1, 1 } do
		Build.block(model, Vector3.new(1, 7.6, 1), frame * CFrame.new(side * 5, 3.8, 2), COLORS.woodDark)
	end
	Build.block(model, Vector3.new(11, 5.6, 0.8), frame * CFrame.new(0, 5, 2), COLORS.wood)
	local titlePlate = Build.block(model, Vector3.new(9, 2.6, 0.2), frame * CFrame.new(0, 6.2, 1.5), COLORS.woodDark)
	local title = Build.surfaceText(titlePlate, Enum.NormalId.Front, "6 > 7")
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

-- Cette méthode permet de construire le texte flottant d'une base (portrait, nom, revenu, Throw Power ; taille en
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
	gui.Size = UDim2.new(LABEL_SIZE.X, 110, LABEL_SIZE.Y, 70)
	gui.LightInfluence = 0
	gui.MaxDistance = LABEL_DISTANCE
	gui.Parent = anchor
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.fromScale(0.5, 0)
	avatar.Size = UDim2.fromScale(1, 0.3)
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
	return {
		avatar = avatar,
		title = line("Title", 0.31, 0.25, Color3.new(1, 1, 1)),
		income = line("Income", 0.56, 0.24, LABEL_GREEN),
		power = line("Power", 0.8, 0.2, LABEL_CYAN),
	}
end

-- Cette méthode permet de poser la clôture d'une base au style `fence` (ouverte côté hub, entrée de 10 studs) dans
-- `folder` lorsque la base est habillée ; renvoie les deux bouts de l'entrée et les quatre coins, au sol.
local function baseFence(folder: Instance, slot: Slot, fence: BaseLook.Fence): ({ Vector3 }, { Vector3 })
	local center = CourseLayout.basePosition(slot.index)
	local size = CourseLayout.BASE_SIZE
	local hx, hz = size.X / 2, size.Z / 2
	local inward = CourseLayout.entranceSide(slot.index)
	local corners = {
		center + Vector3.new(-hx, 0, -hz),
		center + Vector3.new(hx, 0, -hz),
		center + Vector3.new(hx, 0, hz),
		center + Vector3.new(-hx, 0, hz),
	}
	local gate = {}
	for i, from in corners do
		local to = corners[i % 4 + 1]
		-- Chaque coin n'a qu'un poteau : posé par le tronçon qui y finit
		if math.abs(from.X - to.X) < 0.01 and math.sign(from.X - center.X) == inward then
			local mid = (from + to) / 2
			local dir = (to - from).Unit
			gate = { mid - dir * GATE_WIDTH / 2, mid + dir * GATE_WIDTH / 2 }
			Props.fence(folder, from, gate[1], fence, true)
			Props.fence(folder, gate[2], to, fence)
		else
			Props.fence(folder, from, to, fence, true)
		end
	end
	return gate, corners
end

-- Cette méthode permet d'habiller une base au palier visuel `tier` (Shared.BaseLook : sol, clôture, décor) lorsque son
-- propriétaire change ou achète un présentoir ; sans effet si la base a déjà ce palier.
function CourseBuilder.styleBase(slot: Slot, tier: number)
	local base = slot.base
	if base.tier == tier then
		return
	end
	local look, fence = BaseLook.base(tier)
	-- Nouvel habillage posé avant de retirer l'ancien : la clôture ne disparaît jamais
	local folder = Instance.new("Folder")
	folder.Name = "Look"
	local old = base.look
	base.plot.Color = look.plot or Build.shade(slot.color, 0.6)
	local center = CourseLayout.basePosition(slot.index)
	local hx, hz = CourseLayout.BASE_SIZE.X / 2, CourseLayout.BASE_SIZE.Z / 2
	local inward = CourseLayout.entranceSide(slot.index)
	local gate, corners = baseFence(folder, slot, fence)
	local lift = Vector3.new(0, BaseLook.postTop(fence), 0)
	-- Arche d'entrée : les lanternes de l'entrée montent sur son linteau
	local gateTops = { gate[1] + lift, gate[2] + lift }
	if look.arch then
		local a, b = Props.arch(folder, gate[1], gate[2], slot.color)
		gateTops = { a, b }
	end
	if look.lanterns >= 2 then
		for _, top in gateTops do
			Props.lantern(folder, top)
		end
	end
	if look.lanterns >= 6 then
		for _, corner in corners do
			Props.lantern(folder, corner + lift)
		end
	end
	local plotTop = center.Y + PLOT_TOP
	if look.flowers then
		-- Le long du fond (côté opposé à l'entrée) et de part et d'autre de l'entrée, entre clôture et présentoirs
		local back = center.X - inward * (hx - BED_INSET)
		local front = center.X + inward * (hx - BED_INSET)
		local reach = hz - BED_END
		Props.flowerBed(
			folder,
			Vector3.new(back, plotTop, center.Z - reach),
			Vector3.new(back, plotTop, center.Z + reach)
		)
		for _, side in { -1, 1 } do
			Props.flowerBed(
				folder,
				Vector3.new(front, plotTop, center.Z + side * (GATE_WIDTH / 2 + 1.5)),
				Vector3.new(front, plotTop, center.Z + side * reach)
			)
		end
	end
	if look.flags then
		for _, corner in corners do
			local inside = Vector3.new(math.sign(center.X - corner.X), 0, math.sign(center.Z - corner.Z))
			-- Fanion tourné vers l'extérieur de la base, côté entrée ou fond
			local outward = Vector3.new(-inside.X, 0, 0)
			Props.flag(folder, Vector3.new(corner.X, plotTop, corner.Z) + inside * FLAG_INSET, outward, slot.color)
		end
	end
	if fence.shine then
		sparkles(
			folder,
			Vector3.new(hx * 2, 8, hz * 2),
			CFrame.new(center + Vector3.new(0, 6, 0)),
			rgb(255, 215, 80),
			14
		)
	end
	folder.Parent = base.model
	old:Destroy()
	base.look = folder
	base.tier = tier
end

-- Cette méthode permet de construire la base d'une place (terrain, présentoirs vides, texte flottant, confettis
-- d'achat, habillage du premier palier) lorsque le hub est construit.
local function buildBase(parent: Instance, slot: Slot)
	local center = CourseLayout.basePosition(slot.index)
	local size = CourseLayout.BASE_SIZE
	local model = Instance.new("Model")
	model.Name = "Base" .. slot.index
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
	for index, position in CourseLayout.displayPositions(slot.index) do
		local pedestal =
			Build.block(model, Vector3.new(5, 1.6, 5), CFrame.new(position + Vector3.new(0, 0.8, 0)), COLORS.stone)
		table.insert(pedestals, pedestal)
		local top =
			Build.block(model, Vector3.new(4, 0.4, 4), CFrame.new(position + Vector3.new(0, 1.8, 0)), slot.color)
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
		-- Au-dessus du centre de la base, plus haut que les plus grands mannequins posés (comme les jardins de 09)
		label = baseLabel(model, center + Vector3.new(0, LABEL_HEIGHT, 0)),
		burst = upgradeBurst(model, center + Vector3.new(0, 3, 0), slot.color),
		displays = displays,
		pedestals = pedestals,
		facing = CourseLayout.entranceSide(slot.index),
		pad = buildPad(parent, slot),
	}
	CourseBuilder.styleBase(slot, 1)
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

-- Cette méthode permet de construire le hub (pelouse à damier, parois en gradins, bases et leurs appareils, stands à
-- auvents, chevrons vers la zone de lancer, point d'apparition) lorsque le serveur démarre.
local function buildHub(parent: Instance, slots: { Slot })
	local zone = Zones.LIST[1]
	local halfW = GameConfig.HUB_WIDTH / 2
	local front = -GameConfig.LAUNCH_DEPTH
	local back = front - GameConfig.HUB_DEPTH
	ground(parent, -halfW, halfW, back, front, zone.ground, "Hub")
	-- Parois : côtés (jusqu'aux épaulements de la piste) et fond
	terraces(parent, Vector3.new(halfW, 0, back), Vector3.new(halfW, 0, front), -Vector3.xAxis, zone, 1, 1)
	terraces(parent, Vector3.new(-halfW, 0, front), Vector3.new(-halfW, 0, back), Vector3.xAxis, zone, 1, 1)
	terraces(parent, Vector3.new(-halfW, 0, back), Vector3.new(halfW, 0, back), Vector3.zAxis, zone, 1, 1)
	-- Les épaulements entre le hub (large) et la piste (étroite) sont les bouts des parois de la piste

	for _, slot in slots do
		buildStation(parent, slot)
		buildBase(parent, slot)
	end
	-- Stands du fond (#68) : vente des mannequins de collection, boutique des mannequins à lancer (#14)
	local standZ = back + 14
	local sellAt = CFrame.new(-24, 0, standZ) * CFrame.Angles(0, math.pi, 0)
	Props.sellStand(parent, sellAt)
	-- Invite du stand SELL, devant le comptoir : chaque client y ouvre sa fenêtre de vente
	standPrompt(parent, (sellAt * CFrame.new(0, 3, -6)).Position, "Sell dummies", "SELL", Collection.SELL_TAG)
	local shopAt = CFrame.new(24, 0, standZ) * CFrame.Angles(0, math.pi, 0)
	local shop = Props.shopStand(parent, shopAt, ThrowDummies.DISPLAY_TAG, ThrowDummies.SHOWCASE)
	-- Invite du stand SHOP : chaque client y ouvre la boutique des mannequins à lancer
	standPrompt(parent, shop.prompt, "Buy dummies", "SHOP", ThrowDummies.SHOP_TAG)
	-- Chevrons jaunes au sol vers la zone de lancer (01 / 09)
	for i = 0, 3 do
		for _, side in { -1, 1 } do
			Build.decor({
				Name = "Chevron",
				Size = Vector3.new(3.2, 0.1, 1),
				CFrame = CFrame.new(side * 1.1, 0.06, front - 30 + i * 6) * CFrame.Angles(0, math.rad(side * 45), 0),
				Color = COLORS.pad,
				Parent = parent,
			})
		end
	end
	-- Arbres et buissons aux coins du hub
	for _, corner in { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) } do
		for _ = 1, 5 do
			local position =
				Vector3.new(corner.X * rng:NextNumber(halfW - 12, halfW - 4), 0, rng:NextNumber(back + 4, back + 20))
			Props.build(if rng:NextNumber() < 0.6 then "tree" else "bush", parent, CFrame.new(position), rng, true)
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, 0.5, front - 36)
	spawn.Parent = parent
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

-- Cette méthode permet de construire la piste (sol, parois et décor de chaque zone, panneaux, arche d'arrivée, paroi du
-- bout) lorsque le serveur démarre ; renvoie le temps de construction de chaque zone (ms), pour le journal.
local function buildTrack(parent: Instance): { string }
	local half = GameConfig.TRACK_WIDTH / 2
	local length = GameConfig.COURSE_LENGTH
	local timings = {}
	for index, zone in Zones.LIST do
		local started = os.clock()
		local folder = Instance.new("Folder")
		folder.Name = "Zone" .. index
		local zoneStart = zone.start
		local zoneEnd = if index == #Zones.LIST then END_Z else Zones.finish(index, length)
		ground(folder, -half, half, zoneStart, zoneEnd, zone.ground, "Track")
		-- Les parois de la dernière zone dépassent la paroi de bout de piste (pas de trou aux coins)
		local wallEnd = if index == #Zones.LIST then END_Z + 200 else zoneEnd
		-- Parois : la première zone part des épaulements (z = -LAUNCH_DEPTH), les marches hautes reculent avec eux
		local wallStart = if index == 1 then -GameConfig.LAUNCH_DEPTH else zoneStart
		local grow = if index == 1 then -1 else 0
		terraces(folder, Vector3.new(half, 0, wallStart), Vector3.new(half, 0, wallEnd), -Vector3.xAxis, zone, grow, 0)
		terraces(folder, Vector3.new(-half, 0, wallEnd), Vector3.new(-half, 0, wallStart), Vector3.xAxis, zone, 0, grow)
		-- Décor au pied des parois (traversable : le mannequin ne s'y accroche pas)
		for _, side in { -1, 1 } do
			local x = side * (half - 4)
			scatter(
				folder,
				zone,
				Vector3.new(x, 0, math.max(zoneStart, 8)),
				Vector3.new(x, 0, zoneEnd),
				22,
				Vector3.xAxis,
				1.5,
				false
			)
		end
		if index > 1 then
			Build.decor({
				Name = "ZoneLine",
				Size = Vector3.new(GameConfig.TRACK_WIDTH, 0.1, 1.2),
				Position = Vector3.new(0, 0.05, zoneStart),
				Color = COLORS.line,
				Parent = folder,
			})
			-- Panneaux d'entrée de zone (pas au départ : la zone de lancer reste dégagée, comme dans les références)
			local label = string.format("%s  x%s CHANCE", string.upper(zone.name), zone.chance)
			for _, side in { -1, 1 } do
				Props.signpost(folder, CFrame.new(side * (half - 9), 0, zoneStart + 4), label, zone.color)
			end
		end
		folder.Parent = parent
		table.insert(timings, string.format("%s %.0f", zone.name, (os.clock() - started) * 1000))
	end
	buildFinish(parent)
	-- Paroi de bout de piste, en gradins tournés vers le départ
	local last = Zones.LIST[#Zones.LIST]
	terraces(parent, Vector3.new(half, 0, END_Z), Vector3.new(-half, 0, END_Z), -Vector3.zAxis, last, 1, 1)
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
	return timings
end

-- Cette méthode permet de créer les places des joueurs (position, couleur, repères) avant que le décor ne les habille
-- lorsque le serveur démarre.
local function newSlots(): { Slot }
	local pitch = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local direction = Vector3.new(0, math.sin(pitch), math.cos(pitch))
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
	buildHub(course, slots)
	buildLaunchZone(course)
	local hubTime = os.clock() - started
	local zoneTimes = buildTrack(course)
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
			"[Course] construit en %.0f ms (hub %.0f, piste %.0f, obstacles %.0f), %d instances ; zones (ms) : %s",
			(os.clock() - started) * 1000,
			hubTime * 1000,
			trackTime * 1000,
			(os.clock() - obstaclesStarted) * 1000,
			#course:GetDescendants(),
			table.concat(zoneTimes, ", ")
		)
	)
	if not DummyShape.isMeshed() then
		local connection
		connection = ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == DummyShape.TEMPLATES and DummyShape.isMeshed() then
				connection:Disconnect()
				for _, place in rackPlacers do
					place()
				end
			end
		end)
	end
	return { slots = slots, dummies = dummies }
end

return CourseBuilder
