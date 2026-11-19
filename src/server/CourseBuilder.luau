-- Construction du décor : plateforme de départ, couloirs (sol, murs, canon, repères) et obstacles régénérables.
-- Axe du parcours : +Z ; le couloir i est centré sur x = (i - 1) × LANE_SPACING ; bouche du canon à z = 0.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CollisionGroups = require(script.Parent.CollisionGroups)

local HUB_DEPTH = 50 -- profondeur de la plateforme de départ, derrière z = 0
local SIDE_WALL_BACK = 15 -- les murs latéraux commencent à z = -15
local BARREL_LENGTH = 10
local GLASS_HEIGHT = 30
local SHARD_COUNT = 10
local SHARD_LIFETIME = 4
-- Obstacles très légers : le mannequin les traverse et les projette au lieu de s'y arrêter
local CRATE_DENSITY = 0.05
local BRICK_DENSITY = 0.08

local OBSTACLES = {
	{ z = 45, kind = "Glass" },
	{ z = 90, kind = "Crates" },
	{ z = 140, kind = "Glass" },
	{ z = 185, kind = "Wall" },
	{ z = 240, kind = "Glass" },
	{ z = 300, kind = "Crates" },
	{ z = 360, kind = "Wall" },
	{ z = 420, kind = "Glass" },
	{ z = 480, kind = "Crates" },
	{ z = 550, kind = "Wall" },
	{ z = 620, kind = "Glass" },
}

local COLORS = {
	grass = Color3.fromRGB(96, 158, 72),
	hub = Color3.fromRGB(205, 205, 210),
	floor = Color3.fromRGB(62, 64, 72),
	stripe = Color3.fromRGB(95, 98, 108),
	marker = Color3.fromRGB(245, 245, 245),
	sideWall = Color3.fromRGB(150, 200, 255),
	cannon = Color3.fromRGB(40, 42, 50),
	cannonTrim = Color3.fromRGB(230, 60, 50),
	glass = Color3.fromRGB(170, 220, 255),
	crate = Color3.fromRGB(165, 112, 58),
	brick = Color3.fromRGB(170, 75, 55),
}

export type Glass = { part: BasePart, z: number, top: number, broken: boolean }

export type Lane = {
	index: number,
	x: number,
	folder: Folder,
	obstacles: Folder?,
	muzzle: Vector3,
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
local function decal(props: { [string]: any }): Part
	local p = part(props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Cette méthode permet d'afficher un texte flottant au-dessus d'un point lorsque l'on pose un repère de distance.
local function label(parent: Instance, position: Vector3, text: string)
	local anchor = decal({ Name = "Label", Size = Vector3.new(1, 1, 1), Position = position, Transparency = 1 })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(12, 5)
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Parent = anchor
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.2
	textLabel.Text = text
	textLabel.Parent = gui
	anchor.Parent = parent
end

-- Cette méthode permet de construire le canon d'un couloir (socle, roues, fût orienté) lorsque le couloir est créé.
local function buildCannon(lane: Lane): Model
	local model = Instance.new("Model")
	model.Name = "Cannon"
	local x, dir = lane.x, lane.direction
	local barrelCenter = lane.muzzle - dir * (BARREL_LENGTH / 2)
	-- Le cylindre a son axe sur X local : on aligne X sur la direction de tir
	local barrelFrame = CFrame.lookAt(barrelCenter, barrelCenter + dir) * CFrame.Angles(0, math.rad(90), 0)
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(BARREL_LENGTH, 3.2, 3.2),
		CFrame = barrelFrame,
		Color = COLORS.cannon,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	part({
		Name = "Muzzle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 3.8, 3.8),
		CFrame = barrelFrame * CFrame.new(BARREL_LENGTH / 2 - 0.5, 0, 0),
		Color = COLORS.cannonTrim,
		Parent = model,
	})
	local baseZ = barrelCenter.Z - 1.5
	part({
		Name = "Base",
		Size = Vector3.new(3.4, 3, 6),
		Position = Vector3.new(x, 1.5, baseZ),
		Color = COLORS.cannonTrim,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 4.4, 4.4),
			Position = Vector3.new(x + side * 2.1, 2.2, baseZ),
			Color = COLORS.cannon,
			Parent = model,
		})
	end
	CollisionGroups.assign(model, CollisionGroups.CANNON)
	model.Parent = lane.folder
	return model
end

-- Cette méthode permet de construire sol, murs latéraux, marquages et canon d'un couloir lorsque le serveur démarre.
local function buildLane(lane: Lane)
	local x, length, width = lane.x, GameConfig.COURSE_LENGTH, GameConfig.LANE_WIDTH
	part({
		Name = "Floor",
		Size = Vector3.new(width, 2, length),
		Position = Vector3.new(x, -1, length / 2),
		Color = COLORS.floor,
		Material = Enum.Material.Concrete,
		-- Faible frottement : le mannequin glisse après l'atterrissage
		CustomPhysicalProperties = PhysicalProperties.new(2.4, 0.35, 0.25, 5, 1),
		Parent = lane.folder,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "SideWall",
			-- Commence un peu derrière le canon : le fond de la plateforme reste ouvert entre les couloirs
			Size = Vector3.new(1, GameConfig.SIDE_WALL_HEIGHT, length + SIDE_WALL_BACK),
			Position = Vector3.new(
				x + side * (width / 2 + 0.5),
				GameConfig.SIDE_WALL_HEIGHT / 2,
				(length - SIDE_WALL_BACK) / 2
			),
			Color = COLORS.sideWall,
			Transparency = 0.85,
			Parent = lane.folder,
		})
	end
	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	for d = 10, length, 10 do
		local major = d % 50 == 0
		decal({
			Name = if major then "Marker" else "Stripe",
			Size = Vector3.new(width, 0.06, if major then 1 else 0.4),
			Position = Vector3.new(x, 0.03, d),
			Color = if major then COLORS.marker else COLORS.stripe,
			Parent = markers,
		})
		if major then
			label(markers, Vector3.new(x - width / 2 + 3, 6, d), d .. " m")
		end
	end
	markers.Parent = lane.folder
	buildCannon(lane)
end

-- Cette méthode permet de créer une pièce d'obstacle non ancrée et légère lorsque l'on monte une pile ou un mur.
local function breakable(folder: Folder, props: { [string]: any }, density: number): Part
	local p = part(props)
	p.Anchored = false
	p.CustomPhysicalProperties = PhysicalProperties.new(density, 0.5, 0.2)
	p.Parent = folder
	return p
end

-- Cette méthode permet d'ajouter un obstacle au couloir lorsque les obstacles sont (re)construits.
local function buildObstacle(lane: Lane, folder: Folder, z: number, kind: string)
	local x = lane.x
	if kind == "Glass" then
		local glass = part({
			Name = "Glass",
			Size = Vector3.new(GameConfig.LANE_WIDTH, GLASS_HEIGHT, 0.4),
			Position = Vector3.new(x, GLASS_HEIGHT / 2, z),
			Color = COLORS.glass,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			Reflectance = 0.1,
			-- Traversée détectée par LaunchService (franchissement de z), pas par collision
			CanCollide = false,
			CanTouch = false,
			Parent = folder,
		})
		table.insert(lane.glass, { part = glass, z = z, top = GLASS_HEIGHT, broken = false })
	elseif kind == "Crates" then
		for row = 0, 2 do
			for col = -1, 1 do
				table.insert(
					lane.breakables,
					breakable(folder, {
						Name = "Crate",
						Size = Vector3.new(4, 4, 4),
						Position = Vector3.new(x + col * 4.05, 2 + row * 4, z),
						Color = COLORS.crate,
						Material = Enum.Material.WoodPlanks,
					}, CRATE_DENSITY)
				)
			end
		end
	elseif kind == "Wall" then
		for row = 0, 4 do
			local offset = if row % 2 == 0 then -1 else 1
			for col = 0, 5 do
				table.insert(
					lane.breakables,
					breakable(folder, {
						Name = "Brick",
						Size = Vector3.new(3.96, 2, 2),
						Position = Vector3.new(x + (col - 2.5) * 4 + offset, 1 + row * 2, z),
						Color = COLORS.brick,
						Material = Enum.Material.Brick,
					}, BRICK_DENSITY)
				)
			end
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
	for _, obstacle in OBSTACLES do
		buildObstacle(lane, folder, obstacle.z, obstacle.kind)
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
		local offset = Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, 0)
		local position = Vector3.new(impact.X, math.clamp(impact.Y, 1, glass.top - 1), glass.z) + offset
		local shard = part({
			Name = "Shard",
			Size = Vector3.new(0.6 + math.random() * 1.6, 0.6 + math.random() * 1.6, 0.15),
			CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = COLORS.glass,
			Material = Enum.Material.Glass,
			Transparency = 0.4,
			Anchored = false,
			CanQuery = false,
			CanTouch = false,
			CollisionGroup = CollisionGroups.DEBRIS,
			Parent = parent,
		})
		local spread = Vector3.new(math.random() * 30 - 15, math.random() * 20, math.random() * 10)
		shard.AssemblyLinearVelocity = velocity * 0.5 + spread
		shard:SetNetworkOwner(nil)
		Debris:AddItem(shard, SHARD_LIFETIME)
	end
end

-- Cette méthode permet de construire tout le décor (sol, plateforme, couloirs, obstacles) lorsque le serveur démarre ;
-- renvoie la liste des couloirs.
function CourseBuilder.build(): { Lane }
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local course = Instance.new("Folder")
	course.Name = "Course"
	local count, spacing = GameConfig.LANE_COUNT, GameConfig.LANE_SPACING
	local minX, maxX = -spacing / 2, (count - 0.5) * spacing
	local centerX = (minX + maxX) / 2
	local grassMinZ, grassMaxZ = -HUB_DEPTH - 60, GameConfig.COURSE_LENGTH + 300
	part({
		Name = "Grass",
		Size = Vector3.new(maxX - minX + 200, 2, grassMaxZ - grassMinZ),
		Position = Vector3.new(centerX, -1.5, (grassMinZ + grassMaxZ) / 2),
		Color = COLORS.grass,
		Material = Enum.Material.Grass,
		Parent = course,
	})
	part({
		Name = "Hub",
		Size = Vector3.new(maxX - minX, 2, HUB_DEPTH),
		Position = Vector3.new(centerX, -1, -HUB_DEPTH / 2),
		Color = COLORS.hub,
		Material = Enum.Material.Concrete,
		Parent = course,
	})
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(centerX, 0.5, -HUB_DEPTH + 10)
	spawn.Parent = course

	local pitch = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local direction = Vector3.new(0, math.sin(pitch), math.cos(pitch))
	local lanes = {}
	for i = 1, count do
		local x = (i - 1) * spacing
		local folder = Instance.new("Folder")
		folder.Name = "Lane" .. i
		folder.Parent = course
		local spawnPos = Vector3.new(x + 9, 3, -10)
		local lane: Lane = {
			index = i,
			x = x,
			folder = folder,
			obstacles = nil,
			muzzle = Vector3.new(x, GameConfig.MUZZLE_HEIGHT, 0),
			direction = direction,
			spawn = CFrame.lookAt(spawnPos, spawnPos + Vector3.zAxis),
			glass = {},
			breakables = {},
		}
		buildLane(lane)
		lanes[i] = lane
	end
	course.Parent = Workspace
	for _, lane in lanes do
		CourseBuilder.resetObstacles(lane)
	end
	return lanes
end

return CourseBuilder
