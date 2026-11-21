-- Obstacles partagés de la piste unique, posés aux sites de Shared.TrackPlan : dans chaque thème une rangée de vitres
-- (une par colonne, cadre à la couleur du thème), ses obstacles cassables (Server.ThemeObstacles) en pièces légères
-- simulées par le serveur, et son piège signature (Server.TrapProps, déclenché par Server.LaunchService). Les
-- mannequins de tous les joueurs cassent les obstacles ; une pièce déplacée réapparaît à sa place RESPAWN_DELAY après le dernier choc subi par son obstacle, une par une, de bas en
-- haut, avec un petit effet d'apparition (Shared.ObstacleRules).
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ObstacleRules = require(ReplicatedStorage.Shared.ObstacleRules)
local TrackPlan = require(ReplicatedStorage.Shared.TrackPlan)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Build = require(script.Parent.Build)
local CollisionGroups = require(script.Parent.CollisionGroups)
local ThemeObstacles = require(script.Parent.ThemeObstacles)
local TrapProps = require(script.Parent.TrapProps)

local SHARD_COUNT = 12
local SHARD_LIFETIME = 4
local SCAN_PERIOD = 0.2 -- surveillance des pièces (s)
local SETTLE_SPEED = 2 -- une pièce déplacée qui bouge encore repousse la réapparition
local POP_TIME = 0.25
local OCCUPIED_SCALE = 0.9 -- emplacement vérifié avant réapparition (pièces voisines qui se touchent tolérées)
local OCCUPIED_RETRY = 0.2 -- une pièce dont l'emplacement est occupé attend (s)…
local OCCUPIED_TRIES = 40 -- … au plus 8 s (un mannequin posé disparaît RESULT_CLEAR_TIME après la fin de son vol)

local GLASS_COLOR = Color3.fromRGB(170, 225, 255)

export type Glass = { part: BasePart?, z: number, top: number, minX: number, maxX: number, brokenAt: number? }

-- `kind` : ce qu'un choc dans la pièce raconte (cause du crash) ; `material` : son joué quand elle est projetée
export type Piece = {
	part: BasePart,
	template: BasePart,
	home: CFrame,
	kind: string, -- obstacle du thème (Server.ThemeObstacles : "Crates", "Wall", "Tractor"…)
	material: string, -- "Crate" | "Brick"
	group: Group,
	displaced: boolean,
	claimed: boolean,
}

export type Group = { pieces: { Piece }, lastHit: number?, respawning: boolean }

local Obstacles = {}

local folder: Folder
local glasses: { Glass } = {}
local trapBoxes: { TrackPlan.TrapBox } = {}
local pieces: { Piece } = {}
local groups: { Group } = {}
local pieceOf: { [BasePart]: Piece } = {}
local overlap = OverlapParams.new()
overlap.RespectCanCollide = true

-- Cette méthode permet de créer une pièce d'obstacle non ancrée et légère, et son gabarit de réapparition, lorsque
-- l'on monte un obstacle ; elle ignore les avatars (seuls les mannequins la bousculent).
local function addPiece(group: Group, props: { [string]: any }, density: number, kind: string, material: string)
	props.Anchored = false
	-- Briques à tenons, sauf matériau imposé (roche en fusion en Neon)
	if props.Material == nil then
		props.Variant = Build.BRICK
	end
	props.CollisionGroup = CollisionGroups.OBSTACLES
	props.CustomPhysicalProperties = PhysicalProperties.new(density, 0.5, 0.2)
	props.Parent = folder
	local p = Build.part(props)
	local template = p:Clone()
	template.Parent = nil
	local piece: Piece = {
		part = p,
		template = template,
		home = p.CFrame,
		kind = kind,
		material = material,
		group = group,
		displaced = false,
		claimed = false,
	}
	table.insert(group.pieces, piece)
	table.insert(pieces, piece)
	pieceOf[p] = piece
end

-- Cette méthode permet de créer un obstacle vide (groupe de pièces qui réapparaissent ensemble) lorsque l'on en monte
-- un.
local function newGroup(): Group
	local group: Group = { pieces = {}, lastHit = nil, respawning = false }
	table.insert(groups, group)
	return group
end

-- Cette méthode permet de créer la vitre de la colonne `column` à `z` lorsque la piste est construite ou que la
-- vitre réapparaît ; plus elle est loin, plus elle est haute, pour rester sur la trajectoire des lancers puissants.
local function makeGlass(glass: Glass)
	local width = glass.maxX - glass.minX
	local center = (glass.minX + glass.maxX) / 2
	glass.part = Build.part({
		Name = "Glass",
		Size = Vector3.new(width - 0.4, glass.top, 0.4),
		Position = Vector3.new(center, glass.top / 2, glass.z),
		Color = GLASS_COLOR,
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Reflectance = 0.15,
		-- Traversée détectée par LaunchService (franchissement de z), pas par collision
		CanCollide = false,
		CanTouch = false,
		Parent = folder,
	})
end

-- Cette méthode permet de poser une rangée de vitres (une par colonne, cadre à la couleur du thème `color`) à `z`
-- lorsque la piste est construite.
local function buildGlassRow(z: number, color: Color3)
	local height = TrackPlan.glassHeight(z)
	local half = GameConfig.SLOT_SPACING / 2
	for index = 1, GameConfig.SLOT_COUNT do
		local x = CourseLayout.slotX(index)
		local glass: Glass = { part = nil, z = z, top = height, minX = x - half, maxX = x + half, brokenAt = nil }
		makeGlass(glass)
		table.insert(glasses, glass)
	end
	-- Cadre : montants entre les colonnes et traverse en haut (décor)
	local span = GameConfig.SLOT_COUNT * GameConfig.SLOT_SPACING
	for index = 0, GameConfig.SLOT_COUNT do
		Build.decor({
			Name = "GlassPost",
			Size = Vector3.new(0.8, height, 0.8),
			Position = Vector3.new(-span / 2 + index * GameConfig.SLOT_SPACING, height / 2, z),
			Color = color,
			Variant = Build.BRICK,
			Parent = folder,
		})
	end
	Build.decor({
		Name = "GlassFrame",
		Size = Vector3.new(span + 0.8, 1.2, 1),
		Position = Vector3.new(0, height, z),
		Color = color,
		Variant = Build.BRICK,
		Parent = folder,
	})
end

-- Cette méthode permet de donner à Server.ThemeObstacles de quoi monter l'obstacle `kind` (un groupe de pièces par
-- appel à `group`) lorsque l'on construit un site.
local function kitFor(kind: string): ThemeObstacles.Kit
	return {
		group = function()
			local group = newGroup()
			return function(props, density, material)
				addPiece(group, props, density, kind, material)
			end
		end,
	}
end

-- Cette méthode permet de construire tous les obstacles de la piste (vitres, obstacles des thèmes, pièges) sous
-- `parent` lorsque le serveur démarre.
function Obstacles.build(parent: Instance)
	folder = Instance.new("Folder")
	folder.Name = "Obstacles"
	folder.Parent = parent
	local sites = TrackPlan.sites(GameConfig.COURSE_LENGTH)
	for _, site in sites do
		local zone = Zones.LIST[site.zone]
		if site.kind == "Glass" then
			buildGlassRow(site.z, zone.color)
		elseif site.kind == "Obstacle" then
			ThemeObstacles.build(site.name, kitFor(site.name), site.z, zone)
		end
	end
	trapBoxes = TrackPlan.trapBoxes(sites)
	for _, box in trapBoxes do
		TrapProps.build(box, folder)
	end
	-- Simulées par le serveur : sinon le joueur le plus proche prend la main sur la physique des débris
	for _, piece in pieces do
		piece.part:SetNetworkOwner(nil)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= SCAN_PERIOD then
			elapsed = 0
			Obstacles.scan(os.clock())
		end
	end)
end

-- Cette méthode permet de donner toutes les pièces des obstacles lorsque LaunchService compte les objets projetés.
function Obstacles.pieces(): { Piece }
	return pieces
end

-- Cette méthode permet de donner les boîtes de déclenchement des pièges lorsque LaunchService suit un vol.
function Obstacles.traps(): { TrackPlan.TrapBox }
	return trapBoxes
end

-- Cette méthode permet de trouver la pièce d'obstacle touchée (déplacée ou en mouvement) la plus proche de `position`,
-- à moins de `radius`, lorsque l'on cherche ce qui a cassé un os.
function Obstacles.nearest(position: Vector3, radius: number): Piece?
	local best, bestDistance = nil, radius
	for _, piece in pieces do
		local distance = (piece.part.Position - position).Magnitude
		local touched = piece.displaced or piece.part.AssemblyLinearVelocity.Magnitude > SETTLE_SPEED
		if piece.part.Parent and touched and distance < bestDistance then
			best, bestDistance = piece, distance
		end
	end
	return best
end

-- Cette méthode permet de donner les vitres intactes franchies entre `previous` et `position` (franchissement de z,
-- dans les bornes en x et en hauteur de la vitre), avec le point de passage, lorsque le mannequin avance.
function Obstacles.crossedGlass(previous: Vector3, position: Vector3): { { glass: Glass, crossing: Vector3 } }
	local crossed = {}
	if position.Z <= previous.Z then
		return crossed
	end
	for _, glass in glasses do
		if glass.part and previous.Z < glass.z and position.Z >= glass.z then
			local crossing = previous:Lerp(position, (glass.z - previous.Z) / (position.Z - previous.Z))
			-- Borne droite exclue : un passage pile entre deux colonnes ne brise qu'une vitre
			if crossing.Y <= glass.top and crossing.X >= glass.minX and crossing.X < glass.maxX then
				table.insert(crossed, { glass = glass, crossing = crossing })
			end
		end
	end
	return crossed
end

-- Cette méthode permet de faire apparaître une pièce avec un petit effet (elle grossit depuis son centre) lorsqu'elle
-- réapparaît.
local function pop(p: BasePart)
	local size = p.Size
	p.Size = size * 0.2
	-- Sans dépassement : la pièce ancrée ne doit pas bousculer ses voisines
	TweenService:Create(p, TweenInfo.new(POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = size })
		:Play()
end

-- Cette méthode permet de briser une vitre en éclats lorsqu'un mannequin la traverse au point `impact`.
function Obstacles.shatter(glass: Glass, impact: Vector3, velocity: Vector3)
	local part = glass.part
	if not part then
		return
	end
	glass.part = nil
	glass.brokenAt = os.clock()
	part:Destroy()
	for _ = 1, SHARD_COUNT do
		local offset = Vector3.new(math.random() * 8 - 4, math.random() * 10 - 5, 0)
		local position = Vector3.new(impact.X, math.clamp(impact.Y, 1, glass.top - 1), glass.z) + offset
		local shard = Build.part({
			Name = "Shard",
			Size = Vector3.new(0.6 + math.random() * 1.8, 0.6 + math.random() * 1.8, 0.15),
			CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = GLASS_COLOR,
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			Reflectance = 0.3,
			Anchored = false,
			CanQuery = false,
			CanTouch = false,
			CollisionGroup = CollisionGroups.DEBRIS,
			Parent = folder,
		})
		local spread = Vector3.new(math.random() * 40 - 20, math.random() * 30, math.random() * 10)
		shard.AssemblyLinearVelocity = velocity * 0.5 + spread
		shard:SetNetworkOwner(nil)
		Debris:AddItem(shard, SHARD_LIFETIME)
	end
end

-- Cette méthode permet d'inspecter l'emplacement d'une pièce lorsqu'elle va réapparaître : renvoie s'il est occupé par
-- un mannequin (les avatars, eux, sont repoussés), et ajoute à `debris` les pièces déplacées qui l'encombrent.
local function inspect(piece: Piece, debris: { Piece }): boolean
	for _, hit in Workspace:GetPartBoundsInBox(piece.home, piece.template.Size * OCCUPIED_SCALE, overlap) do
		local other = pieceOf[hit]
		if other then
			if other ~= piece and (other.displaced or ObstacleRules.isDisplaced(other.home, hit.CFrame)) then
				table.insert(debris, other)
			end
		elseif not hit.Anchored and not Players:GetPlayerFromCharacter(hit:FindFirstAncestorOfClass("Model")) then
			return true
		end
	end
	return false
end

-- Cette méthode permet de vérifier les emplacements des pièces déplacées d'un obstacle lorsque sa réapparition est due :
-- renvoie les débris d'obstacles qui les encombrent, ou nil si un mannequin y est encore.
local function clearance(group: Group): { Piece }?
	local debris = {}
	for _, piece in group.pieces do
		if piece.displaced and inspect(piece, debris) then
			return nil
		end
	end
	return debris
end

-- Cette méthode permet de retirer une pièce déplacée du monde (son obstacle la fera réapparaître) lorsque l'on libère
-- un emplacement ou que son tour de réapparaître vient.
local function remove(piece: Piece)
	if piece.part.Parent then
		pieceOf[piece.part] = nil
		piece.part:Destroy()
	end
end

-- Cette méthode permet de remettre les pièces déplacées d'un obstacle à leur place, une par une de bas en haut, lorsque
-- sa réapparition est due ; chaque pièce, ancrée sans collision le temps de son apparition, ne bloque aucun mannequin.
local function respawn(group: Group, debris: { Piece })
	group.respawning = true
	local homes, displaced = {}, {}
	for index, piece in group.pieces do
		homes[index] = piece.home
		displaced[index] = piece.displaced
		if piece.displaced then
			remove(piece)
		end
	end
	for _, piece in debris do
		remove(piece)
	end
	local order = ObstacleRules.respawnOrder(homes, displaced)
	task.spawn(function()
		local aborted = false
		for _, index in order do
			local piece = group.pieces[index]
			-- L'emplacement a pu se remplir depuis le début de la réapparition (mannequin, débris)
			local late = {}
			local tries = 0
			local occupied = inspect(piece, late)
			while occupied and tries < OCCUPIED_TRIES do
				tries += 1
				task.wait(OCCUPIED_RETRY)
				table.clear(late)
				occupied = inspect(piece, late)
			end
			if occupied then
				-- Toujours occupé : les pièces restantes attendent une prochaine surveillance
				group.lastHit = os.clock()
				aborted = true
				break
			end
			for _, other in late do
				remove(other)
			end
			local p = piece.template:Clone()
			p.Anchored = true
			p.CanCollide = false
			p.CFrame = piece.home
			p.Parent = folder
			pop(p)
			piece.part = p
			piece.displaced = false
			piece.claimed = false
			pieceOf[p] = piece
			task.delay(POP_TIME, function()
				if p.Parent then
					p.CanCollide = true
					p.Anchored = false
					p:SetNetworkOwner(nil)
				end
			end)
			task.wait(GameConfig.RESPAWN_STAGGER)
		end
		task.wait(POP_TIME)
		if not aborted then
			group.lastHit = nil
		end
		group.respawning = false
	end)
end

-- Cette méthode permet de relever les pièces déplacées, de noter le dernier choc de chaque obstacle, et de lancer
-- les réapparitions dues (obstacles et vitres) lorsque la surveillance périodique tourne.
function Obstacles.scan(now: number)
	for _, group in groups do
		if group.respawning then
			continue
		end
		for _, piece in group.pieces do
			local p = piece.part
			if not piece.displaced and (not p.Parent or ObstacleRules.isDisplaced(piece.home, p.CFrame)) then
				piece.displaced = true
				group.lastHit = now
			elseif piece.displaced and p.Parent and p.AssemblyLinearVelocity.Magnitude > SETTLE_SPEED then
				group.lastHit = now
			elseif not piece.displaced and piece.claimed and p.AssemblyLinearVelocity.Magnitude < SETTLE_SPEED then
				-- Bousculée puis revenue au repos à sa place : elle pourra de nouveau compter
				piece.claimed = false
			end
		end
	end
	for _, group in groups do
		if not group.respawning and ObstacleRules.isDue(group.lastHit, now) then
			local debris = clearance(group)
			if debris then
				respawn(group, debris)
			else
				group.lastHit = now
			end
		end
	end
	for _, glass in glasses do
		if not glass.part and ObstacleRules.isDue(glass.brokenAt, now) then
			glass.brokenAt = nil
			makeGlass(glass)
			pop(glass.part :: BasePart)
		end
	end
end

return Obstacles
