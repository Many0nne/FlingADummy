-- Attribution des couloirs : un couloir par joueur, personnage replacé sur sa plateforme à chaque apparition.
local Players = game:GetService("Players")

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
	local lane = laneOf[player]
	if lane and character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(lane.spawn)
	end
end

-- Cette méthode permet de donner au joueur le premier couloir libre lorsqu'il arrive.
local function assign(player: Player)
	for i, lane in lanes do
		if owners[i] == nil then
			owners[i] = player
			laneOf[player] = lane
			player:SetAttribute("Lane", i)
			player:SetAttribute("LaneState", "Ready")
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

-- Cette méthode permet de donner le couloir d'un joueur lorsque le serveur traite son lancer ; nil s'il n'en a pas.
function LaneService.getLane(player: Player): Lane?
	return laneOf[player]
end

-- Cette méthode permet de brancher l'attribution et la libération des couloirs lorsque le serveur démarre.
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
		end
	end)
end

return LaneService
