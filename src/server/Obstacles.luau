-- Obstacles partagés de la piste unique, posés aux sites de Shared.TrackPlan : dans chaque thème ses obstacles
-- cassables (Server.ThemeObstacles) en pièces légères simulées par le serveur, et son piège signature (Server.TrapProps, déclenché par Server.LaunchService). Les
-- mannequins de tous les joueurs cassent les obstacles ; une pièce déplacée réapparaît à sa place RESPAWN_DELAY après le dernier choc subi par son obstacle, une par une, de bas en
-- haut, avec un petit effet d'apparition (Shared.ObstacleRules).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ObstacleRules = require(ReplicatedStorage.Shared.ObstacleRules)
local SurfaceGap = require(ReplicatedStorage.Shared.SurfaceGap)
local TrackPlan = require(ReplicatedStorage.Shared.TrackPlan)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Build = require(script.Parent.Build)
local CollisionGroups = require(script.Parent.CollisionGroups)
local ThemeObstacles = require(script.Parent.ThemeObstacles)
local TrapProps = require(script.Parent.TrapProps)

local SCAN_PERIOD = 0.2 -- surveillance des pièces (s)
local SETTLE_SPEED = 2 -- une pièce déplacée qui bouge encore repousse la réapparition
local POP_TIME = 0.25
local OCCUPIED_SCALE = 0.9 -- emplacement vérifié avant réapparition (pièces voisines qui se touchent tolérées)
local OCCUPIED_RETRY = 0.2 -- une pièce dont l'emplacement est occupé attend (s)…
local OCCUPIED_TRIES = 40 -- … au plus 8 s (un mannequin posé disparaît RESULT_CLEAR_TIME après la fin de son vol)

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

-- Cette méthode permet de construire tous les obstacles de la piste (obstacles des thèmes, pièges) sous
-- `parent` lorsque le serveur démarre.
function Obstacles.build(parent: Instance)
	folder = Instance.new("Folder")
	folder.Name = "Obstacles"
	folder.Parent = parent
	local sites = TrackPlan.sites(GameConfig.COURSE_LENGTH)
	for _, site in sites do
		local zone = Zones.LIST[site.zone]
		if site.kind == "Obstacle" then
			ThemeObstacles.build(site.name, kitFor(site.name), site.z, zone)
		end
	end
	trapBoxes = TrackPlan.trapBoxes(sites)
	-- Colonnes d'un même piège posées dans une même zone : leurs pièces qui se touchent ne scintillent pas (#93)
	local areas: { [number]: SurfaceGap.Area } = {}
	for _, box in trapBoxes do
		areas[box.site] = areas[box.site] or SurfaceGap.area()
		TrapProps.build(box, folder, areas[box.site])
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

-- Cette méthode permet de faire apparaître une pièce avec un petit effet (elle grossit depuis son centre) lorsqu'elle
-- réapparaît.
local function pop(p: BasePart)
	local size = p.Size
	p.Size = size * 0.2
	-- Sans dépassement : la pièce ancrée ne doit pas bousculer ses voisines
	TweenService:Create(p, TweenInfo.new(POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = size })
		:Play()
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
-- les réapparitions dues lorsque la surveillance périodique tourne.
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
end

return Obstacles
