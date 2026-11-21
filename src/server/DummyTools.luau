-- Mannequins du stock dans le Backpack Roblox (#54) : un Tool par mannequin non posé, doublons compris, dans l'ordre de
-- Shared.BackpackPlan (rareté décroissante, puis arrivée). Les outils ne portent que des données (nom, info-bulle,
-- icône de rareté, attribut DummyKey) : le mannequin tenu est construit par chaque client (Client.CharacterPoser) d'après
-- l'outil équipé. Le joueur ne tient un mannequin qu'au hub, libre : sur la bande, en vol, au résultat ou à
-- l'entraînement, il est déséquipé. Le Backpack, recréé à chaque réapparition, est resynchronisé depuis le stock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Assets = require(Shared.Assets)
local BackpackPlan = require(Shared.BackpackPlan)
local Collection = require(Shared.Collection)
local Format = require(Shared.Format)
local Rarity = require(Shared.Rarity)

local ATTRIBUTE = BackpackPlan.TOOL_ATTRIBUTE

local DummyTools = {}

-- Outils rangés par le serveur dans le Backpack courant, dans l'ordre où il les y a mis (= ordre de la barre)
type State = { backpack: Instance?, sequence: { Tool } }
local states: { [Player]: State } = {}

-- Cette méthode permet de savoir si le joueur peut tenir un mannequin (au hub, ni sur la bande ni à l'entraînement)
-- lorsqu'il en équipe un ou que son état change.
local function canHold(player: Player): boolean
	return player:GetAttribute("LaneState") == "Ready" and player:GetAttribute("Action") == nil
end

-- Cette méthode permet de créer l'outil d'un mannequin (nom, info-bulle avec rareté et $/s, icône de rareté, sans
-- poignée ni lâcher) lorsque le Backpack doit en contenir un de plus.
local function makeTool(entry: Collection.Entry): Tool
	local dummy = Collection.get(entry.id) :: Collection.Dummy
	local tool = Instance.new("Tool")
	tool.Name = Collection.label(entry)
	tool.ToolTip = string.format(
		"%s · %s · %s/s",
		Collection.label(entry),
		Rarity.get(dummy.rarity).name,
		Format.money(Collection.income(entry))
	)
	tool.TextureId = Assets.uri(Assets.RARITY_ICONS[dummy.rarity]) or ""
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool:SetAttribute(ATTRIBUTE, entry.id .. ":" .. entry.size)
	return tool
end

-- Cette méthode permet de donner l'outil de mannequin équipé par le joueur (et sa clé) lorsque le serveur pose le
-- mannequin tenu ; nil s'il n'en tient pas.
function DummyTools.equipped(player: Player): (Tool?, string?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	for _, child in character:GetChildren() do
		local key = child:GetAttribute(ATTRIBUTE)
		if child:IsA("Tool") and type(key) == "string" then
			return child, key
		end
	end
	return nil, nil
end

-- Cette méthode permet de déséquiper le mannequin tenu lorsque le joueur ne peut plus le tenir (lancer, entraînement).
function DummyTools.unequip(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and DummyTools.equipped(player) then
		humanoid:UnequipTools()
	end
end

-- Cette méthode permet d'aligner le Backpack du joueur sur son stock (outils manquants créés, en trop détruits, ordre
-- de la barre rétabli seulement s'il a changé) lorsque la collection change ou que le Backpack est recréé.
function DummyTools.sync(player: Player, stock: { Collection.Entry })
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local state = states[player]
	if not state or state.backpack ~= backpack then
		state = { backpack = backpack, sequence = {} }
		states[player] = state
	end
	-- Outils rangés, dans l'ordre où le serveur les a mis (un outil rendu au Backpack après un réordonnancement, tenu
	-- pendant celui-ci, vient en dernier), puis celui que le joueur tient
	local tools: { Tool } = {}
	local described: { BackpackPlan.Tool } = {}
	local seen: { [Tool]: boolean } = {}
	local stored: { Tool } = {}
	for _, tool in state.sequence do
		if tool.Parent == backpack then
			seen[tool] = true
			table.insert(stored, tool)
		end
	end
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") and type(child:GetAttribute(ATTRIBUTE)) == "string" and not seen[child] then
			table.insert(stored, child)
		end
	end
	for _, tool in stored do
		table.insert(tools, tool)
		table.insert(described, { key = tool:GetAttribute(ATTRIBUTE) :: string, equipped = false })
	end
	local held, heldKey = DummyTools.equipped(player)
	if held and heldKey then
		table.insert(tools, held)
		table.insert(described, { key = heldKey, equipped = true })
	end
	local plan = BackpackPlan.plan(stock, described)
	local removed: { [Tool]: boolean } = {}
	for _, index in plan.remove do
		removed[tools[index]] = true
		tools[index]:Destroy()
	end
	-- Outils rangés gardés, par clé (doublons interchangeables), puis les nouveaux
	local pool: { [string]: { Tool } } = {}
	local current: { string } = {}
	for _, tool in stored do
		if not removed[tool] then
			local key = tool:GetAttribute(ATTRIBUTE) :: string
			pool[key] = pool[key] or {}
			table.insert(pool[key], tool)
			table.insert(current, key)
		end
	end
	if #plan.add == 0 and BackpackPlan.sameSequence(current, plan.sequence) then
		return
	end
	for _, entry in plan.add do
		local key = entry.id .. ":" .. entry.size
		pool[key] = pool[key] or {}
		table.insert(pool[key], makeTool(entry))
	end
	-- La barre d'outils range les outils dans l'ordre où ils arrivent dans le Backpack : retirer puis remettre
	local ordered: { Tool } = {}
	for _, key in plan.sequence do
		local tool = table.remove(pool[key], 1)
		if tool then
			table.insert(ordered, tool)
		end
	end
	for _, tool in ordered do
		if tool.Parent == backpack then
			tool.Parent = nil
		end
	end
	for _, tool in ordered do
		tool.Parent = backpack
	end
	state.sequence = ordered
end

-- Cette méthode permet de déséquiper aussitôt un mannequin que le joueur équipe alors qu'il ne peut pas le tenir
-- (sur la bande, en vol, à l'entraînement) lorsqu'un outil arrive dans son personnage.
local function watchCharacter(player: Player, character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute(ATTRIBUTE) and not canHold(player) then
			task.defer(DummyTools.unequip, player)
		end
	end)
end

-- Cette méthode permet de suivre un joueur (réapparition : nouveau Backpack à remplir ; changement d'état : mannequin
-- déséquipé) lorsqu'il arrive ; `stock` donne son stock courant (nil tant que ses données ne sont pas prêtes).
function DummyTools.track(player: Player, stock: () -> { Collection.Entry }?)
	-- Cette méthode permet de remplir le Backpack depuis le stock lorsqu'il vient d'être (re)créé.
	local function refill()
		local entries = stock()
		if entries then
			DummyTools.sync(player, entries)
		end
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			task.defer(refill)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
		task.defer(refill)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
	for _, attribute in { "LaneState", "Action" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if not canHold(player) then
				DummyTools.unequip(player)
			end
		end)
	end
end

-- Cette méthode permet d'oublier un joueur lorsqu'il quitte la partie.
function DummyTools.forget(player: Player)
	states[player] = nil
end

return DummyTools
