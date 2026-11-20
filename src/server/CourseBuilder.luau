-- Construction du décor au style des jeux de référence (01 / 09) : hub en pelouse à damier (bases des joueurs avec
-- leur appareil d'entraînement devant l'entrée, stands à auvents), zone de lancer commune à SLOT_COUNT places, piste unique au fond d'un canyon
-- en gradins (parois à briques, herbe voxel qui déborde, arbres et rochers voxel) qui change de couleurs à chaque zone,
-- obstacles partagés (Server.Obstacles). Repère : Shared.CourseLayout.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local Drips = require(ReplicatedStorage.Shared.Drips)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local DummyShape = require(ReplicatedStorage.Shared.DummyShape)
local Objectives = require(ReplicatedStorage.Shared.Objectives)
local Training = require(ReplicatedStorage.Shared.Training)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Build = require(script.Parent.Build)
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
local RACK_MESH_WAIT = 20 -- attente maximale des gabarits maillés pour les mannequins du râtelier (s)

local rgb = Color3.fromRGB
local COLORS = {
	launch = rgb(255, 175, 35),
	line = rgb(250, 250, 250),
	pad = rgb(255, 225, 60),
	plot = rgb(175, 115, 65),
	wood = rgb(200, 140, 80),
	woodDark = rgb(150, 95, 50),
	stone = rgb(200, 200, 210),
}

export type Base = { model: Model, sign: TextLabel, displays: { BasePart } }

export type Slot = {
	index: number,
	color: Color3,
	pad: Vector3, -- centre de la place sur la zone de lancer, au sol
	station: CFrame, -- position de l'avatar qui s'entraîne (sur le podium, face au centre du hub)
	prompt: ProximityPrompt, -- « Lift » sur l'appareil d'entraînement, devant la base
	sign: TextLabel, -- nom du joueur et record, au-dessus de sa place
	base: Base, -- présentoirs vides, remplis par la tâche collection
	direction: Vector3,
	spawn: CFrame,
}

export type Course = { slots: { Slot }, dummies: Folder }

local CourseBuilder = {}

local rng = Random.new(SEED)

-- Cette méthode permet de désigner une pièce comme cible d'objectif du HUD (réservée au joueur de la place `slot`)
-- lorsque l'on construit sa pastille ou son appareil d'entraînement.
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

-- Cette méthode permet de construire la zone de lancer commune (bande orange à damier, ligne de départ blanche, une
-- pastille colorée par place avec son enseigne) lorsque le serveur démarre.
local function buildLaunchZone(parent: Instance, slots: { Slot })
	local half = GameConfig.TRACK_WIDTH / 2
	ground(parent, -half, half, -GameConfig.LAUNCH_DEPTH, 0, COLORS.launch, "LaunchZone")
	Build.decor({
		Name = "StartLine",
		Size = Vector3.new(GameConfig.TRACK_WIDTH, 0.1, 1.2),
		Position = Vector3.new(0, 0.05, 0.6),
		Color = COLORS.line,
		Parent = parent,
	})
	for _, slot in slots do
		local disc = CFrame.new(slot.pad) * CFrame.Angles(0, 0, math.rad(90))
		Build.decor({
			Name = "PadRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, GameConfig.PAD_RADIUS * 2 + 2.4, GameConfig.PAD_RADIUS * 2 + 2.4),
			CFrame = disc + Vector3.new(0, 0.05, 0),
			Color = slot.color,
			Parent = parent,
		})
		Build.decor({
			Name = "PadEdge",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, GameConfig.PAD_RADIUS * 2 + 0.8, GameConfig.PAD_RADIUS * 2 + 0.8),
			CFrame = disc + Vector3.new(0, 0.07, 0),
			Color = COLORS.line,
			Parent = parent,
		})
		-- Pastille jaune comme dans les références (et l'aide à l'écran « yellow pad ») ; la couronne dit à qui elle est
		local pad = Build.decor({
			Name = "Pad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.16, GameConfig.PAD_RADIUS * 2, GameConfig.PAD_RADIUS * 2),
			CFrame = disc + Vector3.new(0, 0.09, 0),
			Color = COLORS.pad,
			Parent = parent,
		})
		markObjective(pad, "Throw", slot.index)
		slot.sign = Build.billboard(parent, slot.pad + Vector3.new(0, 13, 0), "FREE", Vector2.new(8, 2.4))
	end
end

-- Cette méthode permet de poser un mannequin d'entraînement décoratif debout (pièces ancrées, sans collision) sur le
-- râtelier lorsque l'appareil est construit ; `feet` = repère sous ses pieds (face vers -Z).
local function rackDummy(parent: Instance, gear: Training.Gear, feet: CFrame)
	local model = Instance.new("Model")
	model.Name = "RackDummy"
	local parts = DummyShape.buildPieces(model, gear.scale, { color = gear.color, material = gear.material })
	local lowest = math.huge
	for _, part in parts do
		lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = feet * CFrame.new(0, -lowest, 0) * part.CFrame
	end
	model.Parent = parent
end

-- Cette méthode permet de construire l'appareil d'entraînement d'une place devant l'entrée de sa base (podium en
-- briques à tenons, pastille jaune où l'avatar soulève son mannequin, râtelier de mannequins derrière lui, invite
-- « Lift ») lorsque le hub est construit, à la place de la barre de traction de 01 / 09.
local function buildStation(parent: Instance, slot: Slot)
	local size = CourseLayout.STATION_SIZE
	local center, facing = CourseLayout.stationPosition(slot.index)
	local floor = CFrame.lookAt(center, center + facing) -- centre du podium au sol, -Z = face de l'avatar
	local model = Instance.new("Model")
	model.Name = "Station" .. slot.index
	-- Podium : socle en briques, bordure à la couleur de la place, dessus en bois
	Build.block(
		model,
		Vector3.new(size, STATION_HEIGHT - 0.4, size),
		floor * CFrame.new(0, (STATION_HEIGHT - 0.4) / 2, 0),
		COLORS.stone
	)
	Build.block(model, Vector3.new(size + 0.6, 0.6, size + 0.6), floor * CFrame.new(0, 0.3, 0), slot.color)
	Build.block(
		model,
		Vector3.new(size - 0.4, 0.4, size - 0.4),
		floor * CFrame.new(0, STATION_HEIGHT - 0.2, 0),
		COLORS.wood
	)
	-- Marche devant le podium
	Build.block(
		model,
		Vector3.new(4, STATION_HEIGHT / 2, 1.6),
		floor * CFrame.new(0, STATION_HEIGHT / 4, -size / 2 - 0.8),
		COLORS.woodDark
	)
	local top = floor * CFrame.new(0, STATION_HEIGHT, 0)
	Build.decor({
		Name = "TrainPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, 4.6, 4.6),
		CFrame = top * CFrame.new(0, 0.08, -STATION_SPOT) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.pad,
		Parent = model,
	})
	-- Râtelier derrière l'avatar : deux montants, une traverse, les mannequins des premiers paliers debout devant
	local rackZ = size / 2 - 1.2
	for _, side in { -1, 1 } do
		Build.block(model, Vector3.new(1, 6.4, 1), top * CFrame.new(side * 3.9, 3.2, rackZ), COLORS.wood)
		Build.block(model, Vector3.new(1.3, 0.6, 1.3), top * CFrame.new(side * 3.9, 6.5, rackZ), slot.color)
	end
	Build.block(model, Vector3.new(8.8, 0.8, 0.8), top * CFrame.new(0, 5.4, rackZ), COLORS.woodDark)
	Build.block(model, Vector3.new(8.2, 0.5, 1.6), top * CFrame.new(0, 0.25, rackZ - 0.2), COLORS.woodDark)
	model.Parent = parent
	-- Mannequins maillés quand les gabarits sont prêts (blocs du gabarit s'ils ne se chargent pas)
	task.spawn(function()
		local waited = 0
		while not DummyShape.isMeshed() and waited < RACK_MESH_WAIT do
			waited += task.wait(0.5)
		end
		for i, x in { -2.1, 0, 2.1 } do
			local feet = top * CFrame.new(x, 0.5, rackZ - 0.3) -- tournés vers le hub, comme l'avatar
			rackDummy(model, Training.GEARS[i], feet)
		end
	end)
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
	Build.billboard(model, (top * CFrame.new(0, 9, rackZ)).Position, "💪 TRAIN", Vector2.new(6, 1.8))
end

-- Cette méthode permet de construire la base d'une place (terrain clôturé, présentoirs vides, panneau au nom du
-- joueur) lorsque le hub est construit ; les présentoirs attendent les mannequins de collection.
local function buildBase(parent: Instance, slot: Slot)
	local center = CourseLayout.basePosition(slot.index)
	local size = CourseLayout.BASE_SIZE
	local model = Instance.new("Model")
	model.Name = "Base" .. slot.index
	Build.decor({
		Name = "Plot",
		Size = Vector3.new(size.X, 0.3, size.Z),
		Position = center + Vector3.new(0, 0.15, 0),
		Color = COLORS.plot,
		Variant = Build.BRICK,
		Parent = model,
	})
	-- Clôture en blocs, ouverte du côté du centre du hub
	local hx, hz = size.X / 2, size.Z / 2
	local inward = if center.X > 0 then -1 else 1
	local corners = {
		Vector3.new(-hx, 0, -hz),
		Vector3.new(hx, 0, -hz),
		Vector3.new(hx, 0, hz),
		Vector3.new(-hx, 0, hz),
	}
	for i, corner in corners do
		local nextCorner = corners[i % 4 + 1]
		local from, to = center + corner, center + nextCorner
		if math.abs(corner.X - nextCorner.X) < 0.01 and math.sign(corner.X) == inward then
			-- Côté du hub : deux tronçons de part et d'autre d'une entrée de 10 studs
			local mid = (from + to) / 2
			local dir = (to - from).Unit
			Props.fence(model, from, mid - dir * 5)
			Props.fence(model, mid + dir * 5, to)
		else
			Props.fence(model, from, to)
		end
	end
	local displays: { BasePart } = {}
	for _, position in CourseLayout.displayPositions(slot.index) do
		Build.block(model, Vector3.new(5, 1.6, 5), CFrame.new(position + Vector3.new(0, 0.8, 0)), COLORS.stone)
		table.insert(
			displays,
			Build.block(model, Vector3.new(4, 0.4, 4), CFrame.new(position + Vector3.new(0, 1.8, 0)), slot.color)
		)
	end
	-- Panneau à l'entrée, tourné vers le centre du hub
	local front = center + Vector3.new(inward * (hx + 3), 0, 0)
	local facing = CFrame.lookAt(front, front + Vector3.new(inward, 0, 0))
	for _, side in { -1, 1 } do
		Build.block(model, Vector3.new(1, 7, 1), facing * CFrame.new(side * 6, 3.5, 0), COLORS.woodDark)
	end
	local board = Build.block(model, Vector3.new(14, 3.6, 0.8), facing * CFrame.new(0, 6.5, 0), slot.color)
	local sign = Build.surfaceText(board, Enum.NormalId.Front, "EMPTY BASE")
	model.Parent = parent
	slot.base = { model = model, sign = sign, displays = displays }
end

-- Cette méthode permet de construire le hub (pelouse à damier, parois en gradins, bases et leurs appareils, stands à auvents,
-- chevrons vers la zone de lancer, point d'apparition) lorsque le serveur démarre.
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
	-- Stands du fond (vente et boutique : branchés par les tâches collection et boutique)
	local standZ = back + 14
	Props.stand(
		parent,
		CFrame.new(-24, 0, standZ) * CFrame.Angles(0, math.pi, 0),
		"SELL",
		rgb(235, 45, 45),
		rgb(235, 45, 45)
	)
	Props.stand(
		parent,
		CFrame.new(24, 0, standZ) * CFrame.Angles(0, math.pi, 0),
		"SHOP",
		rgb(50, 140, 255),
		rgb(50, 140, 255)
	)
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

-- Cette méthode permet de construire la piste (sol de chaque zone, parois en gradins à ses couleurs, décor au pied des
-- parois, ligne et panneaux d'entrée de zone, paroi de bout de piste) lorsque le serveur démarre.
local function buildTrack(parent: Instance)
	local half = GameConfig.TRACK_WIDTH / 2
	local length = GameConfig.COURSE_LENGTH
	for index, zone in Zones.LIST do
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
			local label = string.format("%s  x%s", string.upper(zone.name), zone.multiplier)
			for _, side in { -1, 1 } do
				Props.signpost(folder, CFrame.new(side * (half - 9), 0, zoneStart + 4), label, zone.color)
			end
		end
		folder.Parent = parent
	end
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
end

-- Cette méthode permet de créer les places des joueurs (position, couleur, repères) avant que le décor ne les habille
-- lorsque le serveur démarre.
local function newSlots(): { Slot }
	local pitch = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local direction = Vector3.new(0, math.sin(pitch), math.cos(pitch))
	local slots = {}
	for index = 1, GameConfig.SLOT_COUNT do
		local pad = CourseLayout.padPosition(index)
		local stationGround, stationFacing = CourseLayout.stationPosition(index)
		-- Avatar debout sur la pastille du podium (HumanoidRootPart à 3 studs au-dessus des pieds), dos au râtelier
		local stationPos = stationGround + Vector3.new(0, STATION_HEIGHT + 3, 0) + stationFacing * STATION_SPOT
		local spawnPos = pad + Vector3.new(0, 3, -GameConfig.PAD_RADIUS - 3)
		slots[index] = {
			index = index,
			color = CourseLayout.SLOT_COLORS[(index - 1) % #CourseLayout.SLOT_COLORS + 1],
			pad = pad,
			station = CFrame.lookAt(stationPos, stationPos + stationFacing),
			prompt = nil :: any,
			sign = nil :: any,
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
	local course = Instance.new("Folder")
	course.Name = "Course"
	local slots = newSlots()
	buildHub(course, slots)
	buildLaunchZone(course, slots)
	buildTrack(course)
	local dummies = Instance.new("Folder")
	dummies.Name = "Dummies"
	dummies.Parent = course
	course.Parent = Workspace
	Obstacles.build(course)
	return { slots = slots, dummies = dummies }
end

return CourseBuilder
