-- Collection possédée par un joueur (logique pure, testée) : stock de mannequins gagnés non posés (doublons possibles),
-- présentoirs de la base (achetés au pad jusqu'à CourseLayout.DISPLAY_MAX), Index des mannequins déjà obtenus
-- (meilleure taille, gardé même après vente), dernier gagné encore à poser (panneau « Place your … »). Pose à la main,
-- AUTO, « Place best », retrait, vente (à l'unité ou par rareté), achat de présentoir, sauvegarde avec migration, et
-- encodage en texte pour les attributs répliqués au client. Le serveur seul modifie ces données (Server.BaseService).
-- Une entrée (mannequin + taille) n'a pas d'identité propre : deux doublons sont interchangeables, le client désigne
-- un mannequin du stock par sa clé « id:taille ».
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local CourseLayout = require(Shared:WaitForChild("CourseLayout"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

type Entry = Collection.Entry

local Inventory = {}

export type Data = {
	base: { [number]: Entry | false }, -- DISPLAY_MAX présentoirs (false = vide ; au-delà de `displays` : pas acheté)
	displays: number, -- présentoirs achetés (DISPLAY_START à DISPLAY_MAX)
	stock: { Entry }, -- mannequins possédés non posés, dans l'ordre d'arrivée
	index: { [string]: number }, -- Index : identifiant déjà obtenu → meilleure taille obtenue
	last: Entry?, -- dernier gagné, montré par le panneau « Place your … » tant qu'il est en stock et pas rangé
}

-- Ligne de la fenêtre d'inventaire : un présentoir occupé, ou les doublons d'une clé du stock
export type Row = { key: string, entry: Entry, display: number?, count: number }

-- Cette méthode permet de créer une collection vide (DISPLAY_START présentoirs libres, stock vide) lorsqu'un joueur
-- arrive sans sauvegarde.
function Inventory.new(): Data
	local base = {}
	for display = 1, CourseLayout.DISPLAY_MAX do
		base[display] = false
	end
	return { base = base, displays = GameConfig.DISPLAY_START, stock = {}, index = {}, last = nil }
end

-- Cette méthode permet de donner la clé « id:taille » d'une entrée lorsque le client désigne un mannequin du stock ou
-- que l'on encode une liste.
function Inventory.key(entry: Entry): string
	return entry.id .. ":" .. entry.size
end

-- Cette méthode permet de relire une clé « id:taille » (nil si illisible ou inconnue) lorsque le serveur reçoit une
-- demande du client ou que le client décode un attribut.
function Inventory.parseKey(text: any): Entry?
	if type(text) ~= "string" then
		return nil
	end
	local id, size = string.match(text, "^([%w_]+):(%d+)$")
	local entry = { id = id, size = tonumber(size) }
	return if Collection.isEntry(entry) then entry :: Entry else nil
end

-- Cette méthode permet de copier une entrée valide (nil sinon) lorsque l'on relit une sauvegarde : seules les clés
-- connues sont gardées.
local function copyEntry(value: any): Entry?
	if Collection.isEntry(value) then
		return { id = value.id, size = value.size }
	end
	return nil
end

-- Cette méthode permet de noter une entrée dans l'Index (meilleure taille gardée) et de dire si son mannequin n'avait
-- jamais été obtenu lorsque le joueur la gagne (ou qu'une sauvegarde est migrée).
function Inventory.discover(data: Data, entry: Entry): boolean
	local best = data.index[entry.id]
	if not best or entry.size > best then
		data.index[entry.id] = entry.size
	end
	return best == nil
end

-- Cette méthode permet de donner la position du mannequin le moins rentable du stock (le plus ancien à égalité)
-- lorsque le stock déborde.
local function worstInStock(stock: { Entry }): number?
	local worst, worstIncome = nil, math.huge
	for position, entry in stock do
		local income = Collection.income(entry)
		if income < worstIncome then
			worst, worstIncome = position, income
		end
	end
	return worst
end

-- Cette méthode permet de relire la collection sauvegardée (entrées inconnues ou abîmées ignorées) lorsque les données
-- d'un joueur sont chargées. Migration de #13 : l'ancien mannequin en main (`pending`) passe au stock, la liste
-- `discovered` devient l'Index (taille 1, relevée par ce qui est possédé). Renvoie aussi l'argent des mannequins vendus
-- d'office si le stock dépasse INVENTORY_MAX (à créditer).
function Inventory.read(saved: any): (Data, number)
	local data = Inventory.new()
	if type(saved) ~= "table" then
		return data, 0
	end
	if type(saved.displays) == "number" then
		data.displays = math.clamp(math.floor(saved.displays), GameConfig.DISPLAY_START, CourseLayout.DISPLAY_MAX)
	end
	if type(saved.stock) == "table" then
		for _, value in saved.stock do
			local entry = copyEntry(value)
			if entry then
				table.insert(data.stock, entry)
			end
		end
	end
	if type(saved.base) == "table" then
		for display = 1, CourseLayout.DISPLAY_MAX do
			local entry = copyEntry(saved.base[display])
			if entry and display <= data.displays then
				data.base[display] = entry
			elseif entry then
				table.insert(data.stock, entry) -- présentoir pas (plus) acheté : rien ne se perd
			end
		end
	end
	local pending = copyEntry(saved.pending)
	if pending then
		table.insert(data.stock, pending)
		data.last = { id = pending.id, size = pending.size } -- toujours à poser : le panneau le propose
	end
	-- Plafond du stock (migration comprise) : les moins rentables en trop sont vendus, comme à l'ajout
	local sold = 0
	while #data.stock > GameConfig.INVENTORY_MAX do
		sold += Inventory.sellValue(table.remove(data.stock, worstInStock(data.stock) :: number) :: Entry)
	end
	Inventory.checkLast(data)
	if type(saved.index) == "table" then
		for id, size in saved.index do
			if type(id) == "string" and Collection.get(id) and type(size) == "number" and Collection.SIZES[size] then
				data.index[id] = size
			end
		end
	end
	if type(saved.discovered) == "table" then
		for _, id in saved.discovered do
			if type(id) == "string" and Collection.get(id) and not data.index[id] then
				data.index[id] = 1
			end
		end
	end
	-- Tout ce qui est possédé figure dans l'Index (sauvegardes de #13, données réparées)
	for _, entry in data.stock do
		Inventory.discover(data, entry)
	end
	for display = 1, data.displays do
		local entry = data.base[display]
		if entry then
			Inventory.discover(data, entry)
		end
	end
	return data, sold
end

-- Cette méthode permet de mettre la collection au format sauvegardé (le dernier gagné n'est pas gardé : il est déjà
-- dans le stock) lorsque les données d'un joueur sont écrites.
function Inventory.write(data: Data): { [string]: any }
	return {
		base = table.clone(data.base),
		displays = data.displays,
		stock = table.clone(data.stock),
		index = table.clone(data.index),
	}
end

-- Cette méthode permet de trouver un mannequin du stock par sa clé « id:taille » lorsque le joueur le pose ou le vend ;
-- nil s'il n'en a pas.
function Inventory.findStock(data: Data, key: string): number?
	for position, entry in data.stock do
		if Inventory.key(entry) == key then
			return position
		end
	end
	return nil
end

-- Cette méthode permet d'oublier le dernier gagné lorsqu'il n'est plus dans le stock (posé, vendu) : le panneau « Place
-- your … » se ferme.
function Inventory.checkLast(data: Data)
	if data.last and not Inventory.findStock(data, Inventory.key(data.last)) then
		data.last = nil
	end
end

-- Cette méthode permet de donner le prix de vente d'une entrée (SELL_MINUTES de son revenu) lorsque le stand SELL ou
-- l'inventaire l'affichent ou la vendent.
function Inventory.sellValue(entry: Entry): number
	return Collection.income(entry) * GameConfig.SELL_MINUTES * 60
end

-- Cette méthode permet d'ajouter un mannequin au stock lorsque le joueur le gagne ou le retire d'un présentoir ;
-- au-delà de INVENTORY_MAX, le moins rentable du stock (peut-être celui-ci) est vendu d'office. Renvoie l'argent de
-- cette vente (0 sinon).
function Inventory.add(data: Data, entry: Entry): number
	table.insert(data.stock, { id = entry.id, size = entry.size })
	if #data.stock <= GameConfig.INVENTORY_MAX then
		return 0
	end
	local worst = worstInStock(data.stock) :: number
	local sold = table.remove(data.stock, worst) :: Entry
	Inventory.checkLast(data)
	return Inventory.sellValue(sold)
end

-- Cette méthode permet de savoir si le présentoir `display` est acheté et libre lorsque le joueur veut y poser.
function Inventory.isFree(data: Data, display: any): boolean
	return typeof(display) == "number"
		and display == math.floor(display)
		and display >= 1
		and display <= data.displays
		and not data.base[display]
end

-- Cette méthode permet de choisir où poser une entrée avec AUTO ou le bouton Place de l'inventaire lorsque le joueur
-- le demande : le premier présentoir acheté libre, sinon celui du moins rentable s'il rapporte moins que l'entrée ;
-- nil si rien ne lui va (elle reste au stock).
function Inventory.autoTarget(data: Data, entry: Entry): number?
	local worst, worstIncome = nil, math.huge
	for display = 1, data.displays do
		local placed = data.base[display]
		if not placed then
			return display
		end
		local income = Collection.income(placed)
		if income < worstIncome then
			worst, worstIncome = display, income
		end
	end
	if worst and Collection.income(entry) > worstIncome then
		return worst
	end
	return nil
end

-- Cette méthode permet de poser le mannequin du stock en position `position` sur le présentoir `display` (libre), ou
-- avec la règle AUTO si `display` est nil (le mannequin remplacé retourne au stock) lorsque le joueur le pose. Renvoie
-- le présentoir utilisé, nil si rien n'a bougé.
function Inventory.place(data: Data, position: number, display: number?): number?
	local entry = data.stock[position]
	if not entry then
		return nil
	end
	local target = display
	if target == nil then
		target = Inventory.autoTarget(data, entry)
	elseif not Inventory.isFree(data, target) then
		return nil
	end
	if target == nil then
		return nil
	end
	table.remove(data.stock, position)
	local replaced = data.base[target]
	if replaced then
		table.insert(data.stock, replaced) -- sans débordement : un mannequin vient de quitter le stock
	end
	data.base[target] = entry
	Inventory.checkLast(data)
	return target
end

-- Cette méthode permet de rendre au stock le mannequin du présentoir `display` lorsque le joueur clique Remove ;
-- refusé si le présentoir est vide ou si le stock est plein. Renvoie true s'il a bougé.
function Inventory.remove(data: Data, display: any): boolean
	if typeof(display) ~= "number" or display < 1 or display > data.displays or display ~= math.floor(display) then
		return false
	end
	local entry = data.base[display]
	if not entry or #data.stock >= GameConfig.INVENTORY_MAX then
		return false
	end
	data.base[display] = false
	table.insert(data.stock, entry)
	return true
end

-- Cette méthode permet de remplir les présentoirs achetés avec les mannequins les plus rentables (posés et stock
-- confondus) lorsque le joueur clique « Place best » : un posé reste en place s'il fait partie des meilleurs (à
-- égalité, le posé est gardé), les autres retournent au stock. Renvoie true si la base a changé.
function Inventory.placeBest(data: Data): boolean
	type Item = { entry: Entry, display: number?, position: number?, income: number }
	local pool: { Item } = {}
	for display = 1, data.displays do
		local entry = data.base[display]
		if entry then
			table.insert(pool, { entry = entry, display = display, income = Collection.income(entry) })
		end
	end
	for position, entry in data.stock do
		table.insert(pool, { entry = entry, position = position, income = Collection.income(entry) })
	end
	table.sort(pool, function(a, b)
		if a.income ~= b.income then
			return a.income > b.income
		end
		if (a.display ~= nil) ~= (b.display ~= nil) then
			return a.display ~= nil
		end
		return (a.display or a.position or 0) < (b.display or b.position or 0)
	end)
	local keep: { [number]: boolean } = {} -- présentoirs dont le mannequin reste
	local incoming: { Item } = {} -- mannequins du stock à poser
	for rank = 1, math.min(data.displays, #pool) do
		local item = pool[rank]
		if item.display then
			keep[item.display] = true
		else
			table.insert(incoming, item)
		end
	end
	if #incoming == 0 then
		return false
	end
	-- Les posés écartés retournent au stock ; les nouveaux quittent le stock (positions décroissantes)
	local leaving: { Entry } = {}
	for display = 1, data.displays do
		if data.base[display] and not keep[display] then
			table.insert(leaving, data.base[display] :: Entry)
			data.base[display] = false
		end
	end
	local positions = {}
	for _, item in incoming do
		table.insert(positions, item.position :: number)
	end
	table.sort(positions, function(a, b)
		return a > b
	end)
	for _, position in positions do
		table.remove(data.stock, position)
	end
	local nextItem = 1
	for display = 1, data.displays do
		if not data.base[display] and incoming[nextItem] then
			data.base[display] = incoming[nextItem].entry
			nextItem += 1
		end
	end
	for _, entry in leaving do
		table.insert(data.stock, entry)
	end
	Inventory.checkLast(data)
	return true
end

-- Cette méthode permet de vendre le mannequin du stock en position `position` lorsque le joueur clique Sell ; renvoie
-- l'argent gagné (0 si rien à vendre). Un mannequin posé ne se vend pas : le retirer d'abord.
function Inventory.sell(data: Data, position: number): number
	local entry = data.stock[position]
	if not entry then
		return 0
	end
	table.remove(data.stock, position)
	Inventory.checkLast(data)
	return Inventory.sellValue(entry)
end

-- Cette méthode permet de vendre tout le stock d'une rareté lorsque le joueur clique « Sell all » au stand ; renvoie le
-- nombre de mannequins vendus et l'argent gagné.
function Inventory.sellRarity(data: Data, rarity: number): (number, number)
	local kept, count, total = {}, 0, 0
	for _, entry in data.stock do
		local dummy = Collection.get(entry.id)
		if dummy and dummy.rarity == rarity then
			count += 1
			total += Inventory.sellValue(entry)
		else
			table.insert(kept, entry)
		end
	end
	data.stock = kept
	Inventory.checkLast(data)
	return count, total
end

-- Cette méthode permet de donner le prix du présentoir suivant lorsque `displays` présentoirs sont achetés ; nil au
-- maximum.
function Inventory.displayPrice(displays: number): number?
	return GameConfig.DISPLAY_PRICES[displays - GameConfig.DISPLAY_START + 1]
end

-- Cette méthode permet d'acheter le présentoir suivant lorsque le joueur utilise le pad « 6 > 7 » avec `money` ;
-- renvoie le prix payé, nil si refusé (maximum atteint ou argent insuffisant).
function Inventory.buyDisplay(data: Data, money: number): number?
	local price = Inventory.displayPrice(data.displays)
	if not price or money < price then
		return nil
	end
	data.displays += 1
	return price
end

-- Cette méthode permet de calculer le revenu ($/s) des présentoirs achetés lorsque la base change.
function Inventory.income(data: Data): number
	return Collection.baseIncome(data.base, data.displays)
end

-- Cette méthode permet de donner les lignes de la fenêtre d'inventaire lorsque le stock ou la base changent : les
-- posés d'abord (un par présentoir), puis le stock regroupé par clé (doublons comptés), chaque groupe trié par $/s
-- décroissant.
function Inventory.rows(base: { [number]: Entry | false }, displays: number, stock: { Entry }): { Row }
	local placed: { Row } = {}
	for display = 1, displays do
		local entry = base[display]
		if entry then
			table.insert(placed, { key = Inventory.key(entry), entry = entry, display = display, count = 1 })
		end
	end
	local grouped: { [string]: Row } = {}
	local stocked: { Row } = {}
	for _, entry in stock do
		local key = Inventory.key(entry)
		local row = grouped[key]
		if row then
			row.count += 1
		else
			row = { key = key, entry = entry, display = nil, count = 1 }
			grouped[key] = row
			table.insert(stocked, row)
		end
	end
	-- Cette méthode permet de classer deux lignes ($/s décroissant, puis clé puis présentoir) lorsque l'on trie un groupe.
	local function before(a: Row, b: Row): boolean
		local ia, ib = Collection.income(a.entry), Collection.income(b.entry)
		if ia ~= ib then
			return ia > ib
		end
		if a.key ~= b.key then
			return a.key < b.key
		end
		return (a.display or 0) < (b.display or 0)
	end
	table.sort(placed, before)
	table.sort(stocked, before)
	for _, row in stocked do
		table.insert(placed, row)
	end
	return placed
end

-- Cette méthode permet d'encoder une liste d'entrées (« id:taille,id:taille ») lorsque le serveur publie le stock
-- dans un attribut du joueur.
function Inventory.encodeList(entries: { Entry }): string
	local keys = table.create(#entries)
	for _, entry in entries do
		table.insert(keys, Inventory.key(entry))
	end
	return table.concat(keys, ",")
end

-- Cette méthode permet de relire une liste d'entrées encodée (clés illisibles ignorées) lorsque le client lit le stock.
function Inventory.decodeList(text: any): { Entry }
	local entries = {}
	if type(text) ~= "string" then
		return entries
	end
	for key in string.gmatch(text, "[^,]+") do
		local entry = Inventory.parseKey(key)
		if entry then
			table.insert(entries, entry)
		end
	end
	return entries
end

-- Cette méthode permet d'encoder les présentoirs (une clé ou rien par présentoir, dans l'ordre) lorsque le serveur
-- publie la base dans un attribut du joueur.
function Inventory.encodeBase(base: { [number]: Entry | false }): string
	local parts = table.create(CourseLayout.DISPLAY_MAX)
	for display = 1, CourseLayout.DISPLAY_MAX do
		local entry = base[display]
		table.insert(parts, if entry then Inventory.key(entry) else "")
	end
	return table.concat(parts, ",")
end

-- Cette méthode permet de relire les présentoirs encodés (false = vide) lorsque le client lit la base.
function Inventory.decodeBase(text: any): { [number]: Entry | false }
	local base: { [number]: Entry | false } = {}
	for display = 1, CourseLayout.DISPLAY_MAX do
		base[display] = false
	end
	if type(text) ~= "string" then
		return base
	end
	local display = 0
	for key in string.gmatch(text .. ",", "([^,]*),") do
		display += 1
		if display > CourseLayout.DISPLAY_MAX then
			break
		end
		base[display] = Inventory.parseKey(key) or false
	end
	return base
end

-- Cette méthode permet d'encoder l'Index (« id:meilleure taille », par identifiant) lorsque le serveur le publie dans
-- un attribut du joueur.
function Inventory.encodeIndex(index: { [string]: number }): string
	local entries = {}
	for _, dummy in Collection.DUMMIES do
		local size = index[dummy.id]
		if size then
			table.insert(entries, { id = dummy.id, size = size })
		end
	end
	return Inventory.encodeList(entries)
end

-- Cette méthode permet de relire l'Index encodé (identifiant → meilleure taille) lorsque le client remplit l'Index.
function Inventory.decodeIndex(text: any): { [string]: number }
	local index = {}
	for _, entry in Inventory.decodeList(text) do
		index[entry.id] = math.max(index[entry.id] or 0, entry.size)
	end
	return index
end

return Inventory
