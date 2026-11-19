-- Couloirs : un couloir par joueur, personnage replacé à côté de sa zone de lancer à chaque apparition, état
-- « Holding » (mannequin dans les bras) quand l'avatar se tient sur la zone de lancer et que le couloir est prêt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CollisionGroups = require(script.Parent.CollisionGroups)
local CourseBuilder = require(script.Parent.CourseBuilder)

type Lane = CourseBuilder.Lane

local LaneService = {}

local lanes: { Lane } = {}
local owners: { [number]: Player } = {}
local laneOf: { [Player]: Lane } = {}

-- Cette méthode permet de mettre toutes les pièces du personnage dans le groupe Characters lorsqu'il apparaît
-- (accessoires chargés après coup compris) : il ne gêne ni le mannequin ni les éclats.
local function setupCharacter(player: Player, character: Model)
	CollisionGroups.assign(character, CollisionGroups.CHARACTERS)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionGroups.CHARACTERS
		end
	end)
	player:SetAttribute("Action", nil)
	local lane = laneOf[player]
	if lane and character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(lane.spawn)
	end
end

-- Cette méthode permet d'afficher le nom et le record du joueur au-dessus de sa zone de lancer lorsqu'il arrive ou
-- bat son record (statut visible des autres, comme dans les jeux de référence).
local function refreshSign(lane: Lane)
	local owner = owners[lane.index]
	if not owner then
		lane.sign.Text = "FREE LANE"
		return
	end
	local best = (owner:GetAttribute("BestDistance") :: number?) or 0
	lane.sign.Text = string.format('%s\n<font color="#FFD23C">BEST %s</font>', owner.DisplayName, Format.meters(best))
end

-- Cette méthode permet de donner au joueur le premier couloir libre lorsqu'il arrive.
local function assign(player: Player)
	for i, lane in lanes do
		if owners[i] == nil then
			owners[i] = player
			laneOf[player] = lane
			player:SetAttribute("Lane", i)
			player:SetAttribute("LaneState", "Ready")
			refreshSign(lane)
			player:GetAttributeChangedSignal("BestDistance"):Connect(function()
				if laneOf[player] == lane then
					refreshSign(lane)
				end
			end)
			break
		end
	end
	if not laneOf[player] then
		warn("[LaneService] aucun couloir libre pour " .. player.Name)
	end
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

-- Cette méthode permet de savoir si l'avatar se tient sur la zone de lancer de son couloir lorsque l'état « Holding »
-- est recalculé.
local function isOnPad(player: Player, lane: Lane): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local offset = root.Position - lane.pad
	return Vector2.new(offset.X, offset.Z).Magnitude <= GameConfig.PAD_RADIUS and offset.Y < 8
end

-- Cette méthode permet de donner le couloir d'un joueur lorsque le serveur traite son lancer ; nil s'il n'en a pas.
function LaneService.getLane(player: Player): Lane?
	return laneOf[player]
end

-- Cette méthode permet de brancher l'attribution, la libération des couloirs et l'état « Holding » lorsque le
-- serveur démarre.
function LaneService.init(builtLanes: { Lane })
	lanes = builtLanes
	Players.PlayerAdded:Connect(assign)
	for _, player in Players:GetPlayers() do
		assign(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local lane = laneOf[player]
		if lane then
			owners[lane.index] = nil
			laneOf[player] = nil
			refreshSign(lane)
		end
	end)
	RunService.Heartbeat:Connect(function()
		for player, lane in laneOf do
			local action = player:GetAttribute("Action")
			if action == "Training" then
				continue
			end
			local holding = player:GetAttribute("LaneState") == "Ready" and isOnPad(player, lane)
			if holding and action == nil then
				player:SetAttribute("Action", "Holding")
			elseif not holding and action == "Holding" then
				player:SetAttribute("Action", nil)
			end
		end
	end)
end

return LaneService
