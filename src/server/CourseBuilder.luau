-- Construction du décor, thème « centre d'essais de crash-test » : hub du labo (zones de lancer, postes
-- d'entraînement), piste de chaque couloir découpée en zones (arches, barrières colorées), obstacles régénérables.
-- Axe de la piste : +Z ; le couloir i est centré sur x = (i - 1) × LANE_SPACING ; ligne de départ à z = 0.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Zones = require(ReplicatedStorage.Shared.Zones)
local CollisionGroups = require(script.Parent.CollisionGroups)

local SEGMENT_LENGTH = 400 -- la piste est découpée (taille de pièce maximale : 2 048 studs)
local ARCH_HEIGHT = 26
local SHARD_COUNT = 12
local SHARD_LIFETIME = 4
local STATION_OFFSET = Vector3.new(-14, 0, -26) -- poste d'entraînement, relatif au centre du couloir
-- Obstacles très légers : le mannequin les traverse et les projette au lieu de s'y arrêter
local CRATE_DENSITY = 0.05
local BRICK_DENSITY = 0.08

local GLASS_Z = { 45, 140, 240, 380, 560, 800, 1100, 1500, 2000 }
local CRATES_Z = { 90, 300, 650, 1250, 1800 }
local WALLS_Z = { 185, 480, 950, 1600, 2200 }

local COLORS = {
	grass = Color3.fromRGB(110, 190, 80),
	hub = Color3.fromRGB(225, 225, 230),
	labWall = Color3.fromRGB(245, 245, 248),
	asphalt = Color3.fromRGB(52, 54, 62),
	line = Color3.fromRGB(245, 245, 245),
	yellow = Color3.fromRGB(255, 205, 40),
	black = Color3.fromRGB(25, 25, 30),
	mat = Color3.fromRGB(40, 42, 50),
	glass = Color3.fromRGB(170, 225, 255),
	post = Color3.fromRGB(60, 64, 75),
	crate = Color3.fromRGB(205, 140, 70),
	brick = Color3.fromRGB(190, 80, 55),
}

export type Glass = { part: BasePart, z: number, top: number, broken: boolean }

export type Lane = {
	index: number,
	x: number,
	folder: Folder,
	obstacles: Folder?,
	pad: Vector3, -- centre de la zone de lancer, au sol
	station: CFrame, -- position de l'avatar qui s'entraîne
	prompt: ProximityPrompt, -- « Train » sur le poste d'entraînement
	sign: TextLabel, -- nom du joueur et record, au-dessus de la zone de lancer
	direction: Vector3,
	spawn: CFrame,
	glass: { Glass },
	breakables: { BasePart },
}

local CourseBuilder = {}

-- Cette méthode permet de créer une pièce ancrée avec ses propriétés lorsque le décor est construit.
local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	-- Parent en dernier : la pièce entre dans le monde déjà configurée
	p.Parent = props.Parent
	return p
end

-- Cette méthode permet de créer une pièce décorative sans collision ni requête lorsque l'on pose un marquage.
local function decor(props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return part(props)
end

-- Cette méthode permet de poser un gros texte au style du jeu sur une face de pièce lorsque l'on habille un panneau.
local function surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = target
	return label
end

-- Cette méthode permet d'afficher un texte flottant au-dessus d'un point lorsque l'on pose un repère ou une enseigne.
local function billboard(parent: Instance, position: Vector3, text: string, size: Vector2): TextLabel
	local anchor = decor({ Name = "Label", Size = Vector3.one, Position = position, Transparency = 1, Parent = parent })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.LightInfluence = 0
	gui.MaxDistance = 500
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.RichText = true
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	return label
end

-- Cette méthode permet de poser une bande de danger jaune et noire de `length` studs le long de X lorsque l'on marque
-- une limite au sol.
local function hazardStripe(parent: Instance, center: Vector3, length: number, depth: number)
	local count = math.floor(length / 4)
	local width = length / count
	for i = 0, count - 1 do
		decor({
			Name = "Hazard",
			Size = Vector3.new(width, 0.08, depth),
			Position = center + Vector3.new(-length / 2 + width * (i + 0.5), 0.04, 0),
			Color = if i % 2 == 0 then COLORS.yellow else COLORS.black,
			Parent = parent,
		})
	end
end

-- Cette méthode permet de régler la lumière (plein jour saturé, comme les jeux du genre) lorsque le serveur démarre.
local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 3
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Haze = 0.6
	atmosphere.Color = Color3.fromRGB(200, 225, 255)
	atmosphere.Decay = Color3.fromRGB(120, 160, 220)
	atmosphere.Parent = Lighting
	local grading = Lighting:FindFirstChild("Grading") or Instance.new("ColorCorrectionEffect")
	grading.Name = "Grading"
	grading.Saturation = 0.2
	grading.Contrast = 0.08
	grading.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 20
	bloom.Threshold = 1.5
	bloom.Parent = Lighting
end

-- Cette méthode permet de construire la zone de lancer d'un couloir (pastille, chevrons, enseigne) lorsque le couloir
-- est créé.
local function buildPad(lane: Lane)
	local pad = lane.pad
	local disc = CFrame.new(pad) * CFrame.Angles(0, 0, math.rad(90))
	decor({
		Name = "PadRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, GameConfig.PAD_RADIUS * 2 + 1, GameConfig.PAD_RADIUS * 2 + 1),
		CFrame = disc + Vector3.new(0, 0.06, 0),
		Color = COLORS.black,
		Parent = lane.folder,
	})
	decor({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, GameConfig.PAD_RADIUS * 2, GameConfig.PAD_RADIUS * 2),
		CFrame = disc + Vector3.new(0, 0.08, 0),
		Color = COLORS.yellow,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = lane.folder,
	})
	for i = 1, 3 do
		decor({
			Name = "Chevron",
			Size = Vector3.new(4, 0.1, 1),
			CFrame = CFrame.new(pad + Vector3.new(0, 0.1, GameConfig.PAD_RADIUS + 1.5 * i))
				* CFrame.Angles(0, math.rad(45), 0),
			Color = COLORS.yellow,
			Parent = lane.folder,
		})
	end
	lane.sign = billboard(lane.folder, pad + Vector3.new(0, 15, 0), "FREE LANE", Vector2.new(9, 2.6))
	billboard(lane.folder, pad + Vector3.new(0, 11.5, 0), "THROW!", Vector2.new(6, 1.8))
end

-- Cette méthode permet de construire le poste d'entraînement d'un couloir (tapis, portique, invite « Train »)
-- lorsque le couloir est créé.
local function buildStation(lane: Lane)
	local center = lane.station.Position - Vector3.new(0, 3, 0)
	decor({
		Name = "TrainingMat",
		Size = Vector3.new(10, 0.3, 10),
		Position = center + Vector3.new(0, 0.15, 0),
		Color = COLORS.mat,
		Material = Enum.Material.Rubber,
		Parent = lane.folder,
	})
	hazardStripe(lane.folder, center + Vector3.new(0, 0.3, 5.2), 10, 0.6)
	hazardStripe(lane.folder, center + Vector3.new(0, 0.3, -5.2), 10, 0.6)
	-- Portique décoratif derrière l'avatar
	for _, side in { -1, 1 } do
		part({
			Name = "RackPost",
			Size = Vector3.new(0.8, 9, 0.8),
			Position = center + Vector3.new(side * 4.2, 4.5, -4),
			Color = COLORS.black,
			Material = Enum.Material.Metal,
			Parent = lane.folder,
		})
	end
	part({
		Name = "RackBar",
		Size = Vector3.new(9.2, 0.8, 0.8),
		Position = center + Vector3.new(0, 9, -4),
		Color = COLORS.yellow,
		Material = Enum.Material.Metal,
		Parent = lane.folder,
	})
	local anchor = decor({
		Name = "TrainSpot",
		Size = Vector3.new(2, 2, 2),
		Position = center + Vector3.new(0, 2, 0),
		Transparency = 1,
		Parent = lane.folder,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Train"
	prompt.ObjectText = "Lift dummies"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	lane.prompt = prompt
	billboard(lane.folder, center + Vector3.new(0, 12, -4), "💪 TRAIN", Vector2.new(7, 2.2))
end

-- Cette méthode permet de construire la piste d'un couloir (bitume, lignes, repères, barrières et arches de zones)
-- lorsque le serveur démarre.
local function buildTrack(lane: Lane)
	local x, length, width = lane.x, GameConfig.COURSE_LENGTH, GameConfig.LANE_WIDTH
	for start = 0, length - 1, SEGMENT_LENGTH do
		local segment = math.min(SEGMENT_LENGTH, length - start)
		part({
			Name = "Track",
			Size = Vector3.new(width, 2, segment),
			Position = Vector3.new(x, -1, start + segment / 2),
			Color = COLORS.asphalt,
			Material = Enum.Material.Asphalt,
			-- Frottement moyen : le mannequin glisse un peu après l'atterrissage
			CustomPhysicalProperties = PhysicalProperties.new(2.4, 0.35, 0.25, 5, 1),
			Parent = lane.folder,
		})
		for _, side in { -1, 1 } do
			decor({
				Name = "EdgeLine",
				Size = Vector3.new(0.6, 0.06, segment),
				Position = Vector3.new(x + side * (width / 2 - 1.5), 0.03, start + segment / 2),
				Color = COLORS.line,
				Parent = lane.folder,
			})
		end
	end
	hazardStripe(lane.folder, Vector3.new(x, 0, 1), width, 2)

	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	for d = 50, length, 50 do
		local major = d % 100 == 0
		decor({
			Name = "Marker",
			Size = Vector3.new(if major then width - 4 else 6, 0.06, if major then 0.8 else 0.5),
			Position = Vector3.new(x, 0.03, d),
			Color = COLORS.line,
			Parent = markers,
		})
		if major then
			billboard(markers, Vector3.new(x - width / 2 + 4, 5, d), d .. " m", Vector2.new(10, 4))
		end
	end
	markers.Parent = lane.folder

	for index, zone in Zones.LIST do
		local zoneEnd = if Zones.LIST[index + 1] then Zones.LIST[index + 1].start else length
		local zoneLength = math.min(zoneEnd, length) - zone.start
		for _, side in { -1, 1 } do
			-- Barrière basse colorée de la zone, et paroi invisible qui garde le mannequin dans son couloir
			part({
				Name = "Barrier",
				Size = Vector3.new(1.5, 3, zoneLength),
				Position = Vector3.new(x + side * (width / 2 + 0.75), 1.5, zone.start + zoneLength / 2),
				Color = zone.color,
				Parent = lane.folder,
			})
			part({
				Name = "SideWall",
				Size = Vector3.new(1, GameConfig.SIDE_WALL_HEIGHT, zoneLength),
				Position = Vector3.new(
					x + side * (width / 2 + 0.75),
					GameConfig.SIDE_WALL_HEIGHT / 2 + 3,
					zone.start + zoneLength / 2
				),
				Transparency = 1,
				Parent = lane.folder,
			})
		end
		-- Arche d'entrée de zone (traversable) avec nom et multiplicateur
		local z = math.max(zone.start, 6)
		for _, side in { -1, 1 } do
			decor({
				Name = "ArchPillar",
				Size = Vector3.new(2, ARCH_HEIGHT, 2),
				Position = Vector3.new(x + side * (width / 2 + 2), ARCH_HEIGHT / 2, z),
				Color = zone.color,
				Parent = lane.folder,
			})
		end
		local beam = decor({
			Name = "ArchBeam",
			Size = Vector3.new(width + 6, 5, 2),
			Position = Vector3.new(x, ARCH_HEIGHT + 2.5, z),
			Color = zone.color,
			Parent = lane.folder,
		})
		surfaceText(beam, Enum.NormalId.Front, string.format("%s  x%s", string.upper(zone.name), zone.multiplier))
	end
end

-- Cette méthode permet de créer une pièce d'obstacle non ancrée et légère lorsque l'on monte une pile ou un mur.
local function breakable(folder: Folder, props: { [string]: any }, density: number): Part
	props.Anchored = false
	props.CustomPhysicalProperties = PhysicalProperties.new(density, 0.5, 0.2)
	props.Parent = folder
	return part(props)
end

-- Cette méthode permet d'ajouter une vitre (avec son cadre haut) au couloir lorsque les obstacles sont reconstruits ;
-- plus elle est loin, plus elle est haute, pour rester sur la trajectoire des lancers puissants.
local function buildGlass(lane: Lane, folder: Folder, z: number)
	local height = math.clamp(30 + z * 0.15, 30, 320)
	local glass = part({
		Name = "Glass",
		Size = Vector3.new(GameConfig.LANE_WIDTH, height, 0.4),
		Position = Vector3.new(lane.x, height / 2, z),
		Color = COLORS.glass,
		Material = Enum.Material.Glass,
		Transparency = 0.5,
		Reflectance = 0.15,
		-- Traversée détectée par LaunchService (franchissement de z), pas par collision
		CanCollide = false,
		CanTouch = false,
		Parent = folder,
	})
	decor({
		Name = "GlassFrame",
		Size = Vector3.new(GameConfig.LANE_WIDTH, 1.2, 1),
		Position = Vector3.new(lane.x, height, z),
		Color = COLORS.post,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	table.insert(lane.glass, { part = glass, z = z, top = height, broken = false })
end

-- Cette méthode permet d'ajouter une pile de caisses (3 × 3) au couloir lorsque les obstacles sont reconstruits.
local function buildCrates(lane: Lane, folder: Folder, z: number)
	for row = 0, 2 do
		for col = -1, 1 do
			table.insert(
				lane.breakables,
				breakable(folder, {
					Name = "Crate",
					Size = Vector3.new(4, 4, 4),
					Position = Vector3.new(lane.x + col * 4.05, 2 + row * 4, z),
					Color = COLORS.crate,
					Material = Enum.Material.WoodPlanks,
				}, CRATE_DENSITY)
			)
		end
	end
end

-- Cette méthode permet d'ajouter un mur de briques en quinconce (6 × 5) au couloir lorsque les obstacles sont
-- reconstruits.
local function buildWall(lane: Lane, folder: Folder, z: number)
	for row = 0, 4 do
		local offset = if row % 2 == 0 then -1 else 1
		for col = 0, 5 do
			table.insert(
				lane.breakables,
				breakable(folder, {
					Name = "Brick",
					Size = Vector3.new(3.96, 2, 2),
					Position = Vector3.new(lane.x + (col - 2.5) * 4 + offset, 1 + row * 2, z),
					Color = COLORS.brick,
					Material = Enum.Material.Brick,
				}, BRICK_DENSITY)
			)
		end
	end
end

-- Cette méthode permet de reconstruire tous les obstacles d'un couloir à neuf lorsque le lancer précédent est fini.
function CourseBuilder.resetObstacles(lane: Lane)
	if lane.obstacles then
		lane.obstacles:Destroy()
	end
	table.clear(lane.glass)
	table.clear(lane.breakables)
	local folder = Instance.new("Folder")
	folder.Name = "Obstacles"
	for _, z in GLASS_Z do
		buildGlass(lane, folder, z)
	end
	for _, z in CRATES_Z do
		buildCrates(lane, folder, z)
	end
	for _, z in WALLS_Z do
		buildWall(lane, folder, z)
	end
	folder.Parent = lane.folder
	lane.obstacles = folder
	-- Simulées par le serveur : sinon le joueur le plus proche prend la main sur la physique des débris
	for _, p in lane.breakables do
		p:SetNetworkOwner(nil)
	end
end

-- Cette méthode permet de briser une vitre en éclats lorsque le mannequin la traverse au point `impact`.
function CourseBuilder.shatter(lane: Lane, glass: Glass, impact: Vector3, velocity: Vector3)
	glass.broken = true
	glass.part:Destroy()
	local parent = lane.obstacles or lane.folder
	for _ = 1, SHARD_COUNT do
		local offset = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, 0)
		local position = Vector3.new(impact.X, math.clamp(impact.Y, 1, glass.top - 1), glass.z) + offset
		local shard = part({
			Name = "Shard",
			Size = Vector3.new(0.6 + math.random() * 1.8, 0.6 + math.random() * 1.8, 0.15),
			CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = COLORS.glass,
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			Reflectance = 0.3,
			Anchored = false,
			CanQuery = false,
			CanTouch = false,
			CollisionGroup = CollisionGroups.DEBRIS,
			Parent = parent,
		})
		local spread = Vector3.new(math.random() * 40 - 20, math.random() * 30, math.random() * 10)
		shard.AssemblyLinearVelocity = velocity * 0.5 + spread
		shard:SetNetworkOwner(nil)
		Debris:AddItem(shard, SHARD_LIFETIME)
	end
end

-- Cette méthode permet de construire le hub du labo (pelouse, sol, mur du fond et son enseigne, point
-- d'apparition) lorsque le serveur démarre.
local function buildHub(course: Folder, minX: number, maxX: number)
	local centerX = (minX + maxX) / 2
	local depth = GameConfig.HUB_DEPTH
	local grassMinZ, grassMaxZ = -depth - 80, GameConfig.COURSE_LENGTH + 300
	part({
		Name = "Grass",
		Size = Vector3.new(maxX - minX + 300, 2, grassMaxZ - grassMinZ),
		Position = Vector3.new(centerX, -1.6, (grassMinZ + grassMaxZ) / 2),
		Color = COLORS.grass,
		Material = Enum.Material.Grass,
		Parent = course,
	})
	part({
		Name = "Hub",
		Size = Vector3.new(maxX - minX, 2, depth),
		Position = Vector3.new(centerX, -1, -depth / 2),
		Color = COLORS.hub,
		Material = Enum.Material.Concrete,
		Parent = course,
	})
	part({
		Name = "LabWall",
		Size = Vector3.new(maxX - minX, 30, 2),
		Position = Vector3.new(centerX, 15, -depth - 1),
		Color = COLORS.labWall,
		Parent = course,
	})
	part({
		Name = "LabStripe",
		Size = Vector3.new(maxX - minX, 3, 0.2),
		Position = Vector3.new(centerX, 4, -depth + 0.1),
		Color = COLORS.yellow,
		Parent = course,
	})
	local sign = decor({
		Name = "LabSign",
		Size = Vector3.new(120, 14, 0.2),
		Position = Vector3.new(centerX, 18, -depth + 0.1),
		Transparency = 1,
		Parent = course,
	})
	surfaceText(sign, Enum.NormalId.Back, "CRASH TEST LAB", COLORS.yellow)
	for _, side in { -1, 1 } do
		part({
			Name = "HubWall",
			Size = Vector3.new(2, 12, depth),
			Position = Vector3.new(if side < 0 then minX - 1 else maxX + 1, 6, -depth / 2),
			Color = COLORS.labWall,
			Parent = course,
		})
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(centerX, 0.5, -depth + 10)
	spawn.Parent = course
end

-- Cette méthode permet de construire tout le décor (hub, couloirs, obstacles, lumière) lorsque le serveur démarre ;
-- renvoie la liste des couloirs.
function CourseBuilder.build(): { Lane }
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	setupLighting()

	local course = Instance.new("Folder")
	course.Name = "Course"
	local count, spacing = GameConfig.LANE_COUNT, GameConfig.LANE_SPACING
	buildHub(course, -spacing / 2, (count - 0.5) * spacing)

	local pitch = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local direction = Vector3.new(0, math.sin(pitch), math.cos(pitch))
	local lanes = {}
	for i = 1, count do
		local x = (i - 1) * spacing
		local folder = Instance.new("Folder")
		folder.Name = "Lane" .. i
		folder.Parent = course
		local stationPos = Vector3.new(x, 3, 0) + STATION_OFFSET
		local spawnPos = Vector3.new(x + 10, 3, GameConfig.PAD_Z - 8)
		local lane: Lane = {
			index = i,
			x = x,
			folder = folder,
			obstacles = nil,
			pad = Vector3.new(x, 0, GameConfig.PAD_Z),
			station = CFrame.lookAt(stationPos, stationPos + Vector3.zAxis),
			prompt = nil :: any,
			sign = nil :: any,
			direction = direction,
			spawn = CFrame.lookAt(spawnPos, spawnPos + Vector3.zAxis),
			glass = {},
			breakables = {},
		}
		buildPad(lane)
		buildStation(lane)
		buildTrack(lane)
		lanes[i] = lane
	end
	course.Parent = Workspace
	for _, lane in lanes do
		CourseBuilder.resetObstacles(lane)
	end
	return lanes
end

return CourseBuilder
