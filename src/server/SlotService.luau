-- Places du lobby (SLOT_COUNT joueurs sur une piste partagée) : chaque joueur reçoit une place (sa pastille sur la
-- zone de lancer commune, sa base et son appareil d'entraînement), réapparaît à côté de sa pastille, et passe à l'état
-- « Holding » (mannequin dans les bras) quand il s'y tient et que son lancer précédent est fini.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CollisionGroups = require(script.Parent.CollisionGroups)
local CourseBuilder = require(script.Parent.CourseBuilder)

type Slot = CourseBuilder.Slot

local SlotService = {}

local slots: { Slot } = {}
local owners: { [number]: Player } = {}
local slotOf: { [Player]: Slot } = {}

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
	local slot = slotOf[player]
	if slot and character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(slot.spawn)
	end
end

-- Cette méthode permet d'afficher le nom et le record du joueur au-dessus de sa place et sur sa base lorsqu'il arrive,
-- part ou bat son record (statut visible des autres, comme dans les jeux de référence).
local function refreshSigns(slot: Slot)
	local owner = owners[slot.index]
	if not owner then
		slot.sign.Text = "FREE"
		slot.base.sign.Text = "EMPTY BASE"
		return
	end
	local best = (owner:GetAttribute("BestDistance") :: number?) or 0
	slot.sign.Text = string.format('%s\n<font color="#FFD23C">BEST %s</font>', owner.DisplayName, Format.meters(best))
	slot.base.sign.Text = string.upper(owner.DisplayName) .. "'S BASE"
end

-- Cette méthode permet de donner au joueur la première place libre lorsqu'il arrive.
local function assign(player: Player)
	for index, slot in slots do
		if owners[index] == nil then
			owners[index] = player
			slotOf[player] = slot
			player:SetAttribute("Slot", index)
			player:SetAttribute("LaneState", "Ready")
			refreshSigns(slot)
			player:GetAttributeChangedSignal("BestDistance"):Connect(function()
				if slotOf[player] == slot then
					refreshSigns(slot)
				end
			end)
			break
		end
	end
	if not slotOf[player] then
		warn("[SlotService] aucune place libre pour " .. player.Name)
	end
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

-- Cette méthode permet de savoir si l'avatar se tient sur sa pastille de la zone de lancer lorsque l'état « Holding »
-- est recalculé.
local function isOnPad(player: Player, slot: Slot): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local offset = root.Position - slot.pad
	return Vector2.new(offset.X, offset.Z).Magnitude <= GameConfig.PAD_RADIUS and offset.Y < 8
end

-- Cette méthode permet de donner la place d'un joueur lorsque le serveur traite son lancer ou son entraînement ; nil
-- s'il n'en a pas.
function SlotService.getSlot(player: Player): Slot?
	return slotOf[player]
end

-- Cette méthode permet de donner les places sans joueur lorsque l'on lance des mannequins de test (Studio).
function SlotService.freeSlots(): { Slot }
	local free = {}
	for index, slot in slots do
		if owners[index] == nil then
			table.insert(free, slot)
		end
	end
	return free
end

-- Cette méthode permet de brancher l'attribution, la libération des places et l'état « Holding » lorsque le serveur
-- démarre.
function SlotService.init(builtSlots: { Slot })
	slots = builtSlots
	Players.PlayerAdded:Connect(assign)
	for _, player in Players:GetPlayers() do
		assign(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local slot = slotOf[player]
		if slot then
			owners[slot.index] = nil
			slotOf[player] = nil
			refreshSigns(slot)
		end
	end)
	RunService.Heartbeat:Connect(function()
		for player, slot in slotOf do
			local action = player:GetAttribute("Action")
			if action == "Training" then
				continue
			end
			local holding = player:GetAttribute("LaneState") == "Ready" and isOnPad(player, slot)
			if holding and action == nil then
				player:SetAttribute("Action", "Holding")
			elseif not holding and action == "Holding" then
				player:SetAttribute("Action", nil)
			end
		end
	end)
end

return SlotService
