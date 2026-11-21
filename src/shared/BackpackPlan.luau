-- Contenu du Backpack Roblox d'un joueur (logique pure, testée) : un Tool par mannequin du stock (Shared.Inventory),
-- doublons compris, dans un ordre stable (rareté décroissante, puis ordre d'arrivée). Le serveur (Server.DummyTools)
-- compare les outils existants au stock et n'ajoute, ne retire ou ne réordonne que ce qui a changé. Deux doublons
-- sont interchangeables : un outil se reconnaît à sa clé « id:taille » (attribut TOOL_ATTRIBUTE).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local Inventory = require(Shared:WaitForChild("Inventory"))

type Entry = Collection.Entry

local BackpackPlan = {}

BackpackPlan.TOOL_ATTRIBUTE = "DummyKey" -- clé « id:taille » portée par chaque Tool de mannequin

-- Outil existant, tel que le serveur le décrit : clé, et s'il est équipé (dans le personnage)
export type ToolInfo = { key: string, equipped: boolean }

-- Ce que le serveur doit faire : outils à détruire (indices dans la liste reçue), entrées à créer, et ordre voulu
-- des clés dans le Backpack (outils non équipés seulement)
export type Plan = { remove: { number }, add: { Entry }, sequence: { string } }

-- Cette méthode permet de donner la clé « id:taille » d'une entrée lorsque l'on compare outils et stock.
local function keyOf(entry: Entry): string
	return entry.id .. ":" .. entry.size
end

-- Cette méthode permet de ranger le stock dans l'ordre de la barre d'outils (rareté décroissante, puis ordre
-- d'arrivée dans le stock) lorsque le Backpack est synchronisé.
function BackpackPlan.order(stock: { Entry }): { Entry }
	local items = table.create(#stock)
	for position, entry in stock do
		local dummy = Collection.get(entry.id)
		table.insert(items, { entry = entry, position = position, rarity = if dummy then dummy.rarity else 0 })
	end
	table.sort(items, function(a, b)
		if a.rarity ~= b.rarity then
			return a.rarity > b.rarity
		end
		return a.position < b.position
	end)
	local ordered = table.create(#items)
	for _, item in items do
		table.insert(ordered, item.entry)
	end
	return ordered
end

-- Cette méthode permet de comparer les outils existants au stock lorsque la collection change : les outils en trop
-- sont retirés (un outil équipé n'est retiré que s'il n'en reste aucun de sa clé), les manquants créés, et l'ordre
-- voulu des outils rangés dans le Backpack (l'outil équipé y garde sa place hors de la liste).
function BackpackPlan.plan(stock: { Entry }, tools: { ToolInfo }): Plan
	local wanted: { [string]: number } = {}
	local ordered = BackpackPlan.order(stock)
	for _, entry in ordered do
		local key = keyOf(entry)
		wanted[key] = (wanted[key] or 0) + 1
	end
	-- Les outils équipés réclament leur clé d'abord : celui que le joueur tient reste en main
	local kept: { [string]: number } = {}
	local remove: { number } = {}
	local equippedKept: { [string]: number } = {}
	for _, pass in { true, false } do
		for index, tool in tools do
			if tool.equipped == pass then
				local count = kept[tool.key] or 0
				if count < (wanted[tool.key] or 0) then
					kept[tool.key] = count + 1
					if pass then
						equippedKept[tool.key] = (equippedKept[tool.key] or 0) + 1
					end
				else
					table.insert(remove, index)
				end
			end
		end
	end
	table.sort(remove)
	local add: { Entry } = {}
	local missing: { [string]: number } = {}
	for key, count in wanted do
		missing[key] = count - (kept[key] or 0)
	end
	local sequence: { string } = {}
	local skipped: { [string]: number } = {}
	for _, entry in ordered do
		local key = keyOf(entry)
		if (missing[key] or 0) > 0 then
			missing[key] -= 1
			table.insert(add, { id = entry.id, size = entry.size })
		end
		-- Les outils équipés sont hors du Backpack : la séquence ne compte que les autres
		if (skipped[key] or 0) < (equippedKept[key] or 0) then
			skipped[key] = (skipped[key] or 0) + 1
		else
			table.insert(sequence, key)
		end
	end
	return { remove = remove, add = add, sequence = sequence }
end

-- Cette méthode permet de donner l'outil de mannequin équipé par un personnage et sa clé (valide) lorsque le serveur
-- pose le mannequin tenu ou qu'un client le dessine ; nil s'il n'en tient pas.
function BackpackPlan.held(character: Instance?): (Tool?, string?)
	if not character then
		return nil, nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			local key = child:GetAttribute(BackpackPlan.TOOL_ATTRIBUTE)
			if Inventory.parseKey(key) then
				return child, key :: string
			end
		end
	end
	return nil, nil
end

-- Cette méthode permet de savoir si deux listes de clés sont identiques (même ordre) lorsque le serveur décide s'il
-- doit réordonner le Backpack.
function BackpackPlan.sameSequence(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for index, key in a do
		if b[index] ~= key then
			return false
		end
	end
	return true
end

return BackpackPlan
