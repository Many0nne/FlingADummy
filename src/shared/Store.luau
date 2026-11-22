-- Boutique Robux (#160), calée sur celle de Throw a Seed (09) : catalogue (passes de jeu, boosts, lancers chanceux,
-- argent rapide, pack de démarrage), effets cumulés (CHANCE, revenu, EXP d'entraînement, présentoirs), minuteurs des
-- boosts (décomptés seulement en jeu), montant de l'argent rapide, offre du pack de démarrage et reçus déjà attribués.
-- Logique pure, partagée par le serveur (Server.StoreService : attribution, sauvegarde) et le client (Client.StoreWindow).
-- Les identifiants Roblox (`assetId`) sont ceux des passes et produits créés sur l'expérience (#172). Un nouvel article
-- garde 0 tant qu'il n'est pas créé : en Studio, l'achat est alors simulé ; ailleurs, le bouton montre le prix mais
-- n'achète rien.
local Store = {}

local rgb = Color3.fromRGB

export type Section = "Packs" | "Passes" | "Boosts" | "Cash"

export type Item = {
	id: string,
	kind: "Pass" | "Product", -- passe de jeu (possédé pour toujours) ou produit développeur (racheté à volonté)
	section: Section,
	name: string,
	text: string, -- effet affiché sur la carte
	price: number, -- prix en Robux (ceux de 09)
	assetId: number, -- identifiant du passe ou du produit sur l'expérience ; 0 = pas encore créé
	icon: string, -- emoji de la vignette
	colors: { Color3 }, -- dégradé de la vignette (haut, bas)
	boost: string?, -- boost minuté accordé (Store.BOOSTS)
	seconds: number?, -- durée du boost (s)
	throws: number?, -- lancers chanceux accordés
	minutes: number?, -- argent rapide : minutes de revenu
	best: boolean?, -- bandeau « BEST VALUE »
}

-- Boosts minutés : multiplicateur et cible. Les deux potions de chance ne se cumulent pas entre elles (la plus forte
-- compte, les deux minuteurs tournent) ; les autres sources se multiplient.
Store.BOOSTS = {
	Luck2 = { label = "LUCK", multiplier = 2, color = rgb(80, 220, 90) },
	Luck5 = { label = "MEGA LUCK", multiplier = 5, color = rgb(60, 230, 200) },
	Money = { label = "MONEY", multiplier = 2, color = rgb(255, 200, 40) },
	Train = { label = "TRAINING", multiplier = 2, color = rgb(255, 80, 110) },
}
Store.BOOST_ORDER = { "Luck5", "Luck2", "Money", "Train" }
Store.SERVER_LUCK = 2 -- chance du serveur : × 2 pour tous les joueurs du serveur
Store.LUCKY_THROW = 50 -- lancer chanceux : × 50 sur la CHANCE de ce lancer
Store.BOOST_MAX = 30 * 24 * 3600 -- minuteur borné à la relecture (sauvegarde abîmée)
Store.LUCKY_MAX = 10000

-- Passes de jeu (effets)
Store.VIP_INCOME = 1.25 -- VIP : + 25 % de revenu
Store.BIG_BASE = 10 -- Big Base : + 10 présentoirs (CourseLayout.DISPLAY_ROOM)
Store.RAINBOW_FACTOR = 1.5 -- Rainbow Dummy : 1,5 × la chance du meilleur mannequin possédé…
Store.RAINBOW_MIN = 15 -- … 15x au moins

-- Argent rapide : revenu de référence minimal ($/s), pour qu'un joueur sans présentoir garni reçoive quelque chose
Store.CASH_MIN_INCOME = 50

-- Pack de démarrage : offert pendant la première heure de jeu (temps passé en jeu, sauvegardé), une fois par compte
Store.STARTER_WINDOW = 3600
Store.STARTER_WAS = 396 -- prix barré (valeur des contenus, comme 09)
Store.STARTER = {
	throws = 2,
	boosts = { Luck2 = 15 * 60, Money = 15 * 60 },
	minutes = 120, -- deux heures de revenu
}

Store.RECEIPT_KEEP = 50 -- derniers reçus attribués gardés dans la sauvegarde (rejeu d'un reçu par Roblox)

local GREEN = { rgb(150, 255, 90), rgb(40, 190, 50) }
local GOLD = { rgb(255, 225, 90), rgb(255, 150, 30) }
local PURPLE = { rgb(220, 110, 255), rgb(140, 40, 220) }
local RED = { rgb(255, 120, 130), rgb(220, 40, 80) }
local SKY = { rgb(120, 230, 255), rgb(40, 140, 255) }
local RAINBOW = { rgb(255, 90, 90), rgb(120, 90, 255) }
local TEAL = { rgb(120, 255, 230), rgb(30, 170, 190) }
local DICE = { rgb(200, 150, 255), rgb(150, 90, 240) }
local CASH = { rgb(140, 240, 120), rgb(40, 160, 70) }

-- stylua: ignore
Store.ITEMS = {
	-- Packs
	{ id = "StarterPack",  kind = "Product", section = "Packs",  name = "Starter Pack",   price = 99,  assetId = 3734877786, icon = "🎁", colors = RED,
	  text = "2 Lucky Throws, 15 min 2x Luck, 15 min 2x Money, 2 h of cash" },
	-- Passes de jeu
	{ id = "Luck2x",       kind = "Pass",    section = "Passes", name = "2x Luck",        price = 249, assetId = 2097060407, icon = "🍀", colors = GREEN,
	  text = "2x luck on every throw" },
	{ id = "Money2x",      kind = "Pass",    section = "Passes", name = "2x Money",       price = 199, assetId = 2096750455, icon = "💰", colors = GOLD,
	  text = "2x income from your dummies" },
	{ id = "VIP",          kind = "Pass",    section = "Passes", name = "VIP",            price = 99,  assetId = 2094204472, icon = "👑", colors = PURPLE,
	  text = "+25% income, gold VIP badge" },
	{ id = "StrongArms",   kind = "Pass",    section = "Passes", name = "Strong Arms",    price = 149, assetId = 2092998634, icon = "💪", colors = RED,
	  text = "2x EXP for every rep" },
	{ id = "BigBase",      kind = "Pass",    section = "Passes", name = "Big Base",       price = 79,  assetId = 2096444601, icon = "🏠", colors = SKY,
	  text = "+10 displays in your base" },
	{ id = "Rainbow",      kind = "Pass",    section = "Passes", name = "Rainbow Dummy",  price = 799, assetId = 2097228437, icon = "🌈", colors = RAINBOW,
	  text = "1.5x the luck of your best dummy (15x at least)" },
	-- Boosts
	{ id = "LuckPotion",   kind = "Product", section = "Boosts", name = "Luck Potion",    price = 39,  assetId = 3734877812, icon = "🧪", colors = GREEN,
	  text = "2x luck for 15 min", boost = "Luck2", seconds = 15 * 60 },
	{ id = "MegaLuck",     kind = "Product", section = "Boosts", name = "Mega Luck Potion", price = 99, assetId = 3734877835, icon = "🧪", colors = TEAL,
	  text = "5x luck for 15 min", boost = "Luck5", seconds = 15 * 60 },
	{ id = "ServerLuck",   kind = "Product", section = "Boosts", name = "Server Luck",    price = 99,  assetId = 3734877852, icon = "🌍", colors = SKY,
	  text = "2x luck for everyone in the server for 30 min", seconds = 30 * 60 },
	{ id = "LuckyThrow1",  kind = "Product", section = "Boosts", name = "Lucky Throw",    price = 19,  assetId = 3734877874, icon = "🎲", colors = DICE,
	  text = "Your next throw gets 50x luck", throws = 1 },
	{ id = "LuckyThrow5",  kind = "Product", section = "Boosts", name = "5 Lucky Throws", price = 79,  assetId = 3734877898, icon = "🎲", colors = DICE,
	  text = "50x luck on 5 throws", throws = 5 },
	{ id = "LuckyThrow20", kind = "Product", section = "Boosts", name = "20 Lucky Throws", price = 249, assetId = 3734877914, icon = "🎲", colors = DICE,
	  text = "50x luck on 20 throws", throws = 20 },
	{ id = "MoneyBoost",   kind = "Product", section = "Boosts", name = "Money Boost",    price = 49,  assetId = 3734877934, icon = "🧪", colors = GOLD,
	  text = "2x income for 30 min", boost = "Money", seconds = 30 * 60 },
	{ id = "TrainBoost",   kind = "Product", section = "Boosts", name = "Training Boost", price = 49,  assetId = 3734877957, icon = "🧪", colors = RED,
	  text = "2x training EXP for 30 min", boost = "Train", seconds = 30 * 60 },
	-- Argent rapide
	{ id = "CashSmall",    kind = "Product", section = "Cash",   name = "Small Cash",     price = 29,  assetId = 3734877984, icon = "💵", colors = CASH,
	  text = "30 min of income", minutes = 30 },
	{ id = "CashMedium",   kind = "Product", section = "Cash",   name = "Medium Cash",    price = 99,  assetId = 3734878020, icon = "💵", colors = CASH,
	  text = "3 h of income", minutes = 180 },
	{ id = "CashLarge",    kind = "Product", section = "Cash",   name = "Large Cash",     price = 299, assetId = 3734878043, icon = "💵", colors = CASH,
	  text = "12 h of income", minutes = 720 },
	{ id = "CashHuge",     kind = "Product", section = "Cash",   name = "Huge Cash",      price = 799, assetId = 3734878062, icon = "💵", colors = CASH,
	  text = "48 h of income", minutes = 2880, best = true },
} :: { Item }

-- Sections de la fenêtre, dans l'ordre de la liste (ancres de la colonne de droite) : titre, pastille, onglet
Store.SECTIONS = {
	{ id = "Packs", title = "Packs", note = "One-time offer", icon = "🎁", colors = RED },
	{ id = "Passes", title = "Gamepasses", note = "Yours forever", icon = "🎫", colors = GOLD },
	{ id = "Boosts", title = "Boosts", note = "Use wisely", icon = "🧪", colors = SKY },
	{ id = "Cash", title = "Cash", note = "Quick cash", icon = "💵", colors = CASH },
}

local byId: { [string]: Item } = {}
for _, item in Store.ITEMS do
	assert(not byId[item.id], "Store : identifiant en double " .. item.id)
	byId[item.id] = item
end

-- Cette méthode permet de donner un article du catalogue par son identifiant lorsque le serveur l'attribue ou que la
-- fenêtre l'affiche ; nil s'il n'existe pas.
function Store.get(id: any): Item?
	return if type(id) == "string" then byId[id] else nil
end

-- Cette méthode permet de retrouver l'article d'un identifiant Roblox (passe ou produit, jamais 0) lorsque un reçu ou
-- la fin d'un achat de passe arrive ; nil s'il n'est pas au catalogue.
function Store.byAsset(kind: string, assetId: any): Item?
	if type(assetId) ~= "number" or assetId == 0 then
		return nil
	end
	for _, item in Store.ITEMS do
		if item.kind == kind and item.assetId == assetId then
			return item
		end
	end
	return nil
end

-- Cette méthode permet de donner les articles d'une section, dans l'ordre du catalogue, lorsque la fenêtre se construit.
function Store.section(section: string): { Item }
	local list = {}
	for _, item in Store.ITEMS do
		if item.section == section then
			table.insert(list, item)
		end
	end
	return list
end

-- État d'achat d'un joueur, sauvegardé avec ses données
export type State = {
	passes: { [string]: boolean }, -- passes possédés (identifiant du catalogue)
	boosts: { [string]: number }, -- boost → secondes restantes (décomptées en jeu seulement)
	lucky: number, -- lancers chanceux restants
	played: number, -- secondes passées en jeu (fenêtre du pack de démarrage)
	starter: boolean, -- pack de démarrage acheté
	receipts: { string }, -- derniers reçus attribués (PurchaseId), du plus ancien au plus récent
}

-- Cette méthode permet de créer l'état d'achat d'un nouveau joueur lorsqu'il arrive sans sauvegarde.
function Store.new(): State
	return { passes = {}, boosts = {}, lucky = 0, played = 0, starter = false, receipts = {} }
end

-- Cette méthode permet de borner un nombre relu (entier de 0 à `max`, 0 si illisible) lorsque l'on relit une sauvegarde.
local function count(value: any, max: number): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, max)
end

-- Cette méthode permet de relire l'état d'achat sauvegardé (passes et boosts inconnus ignorés, nombres bornés)
-- lorsque les données d'un joueur sont chargées.
function Store.read(saved: any): State
	local state = Store.new()
	if type(saved) ~= "table" then
		return state
	end
	if type(saved.passes) == "table" then
		for id, owned in saved.passes do
			local item = Store.get(id)
			if owned == true and item and item.kind == "Pass" then
				state.passes[id] = true
			end
		end
	end
	if type(saved.boosts) == "table" then
		for kind, left in saved.boosts do
			if Store.BOOSTS[kind] then
				local seconds = count(left, Store.BOOST_MAX)
				if seconds > 0 then
					state.boosts[kind] = seconds
				end
			end
		end
	end
	state.lucky = count(saved.lucky, Store.LUCKY_MAX)
	state.played = count(saved.played, math.huge)
	state.starter = saved.starter == true
	if type(saved.receipts) == "table" then
		for _, id in saved.receipts do
			if type(id) == "string" then
				table.insert(state.receipts, id)
			end
		end
		while #state.receipts > Store.RECEIPT_KEEP do
			table.remove(state.receipts, 1)
		end
	end
	return state
end

-- Cette méthode permet de mettre l'état d'achat au format sauvegardé lorsque les données d'un joueur sont écrites.
function Store.write(state: State): { [string]: any }
	return {
		passes = table.clone(state.passes),
		boosts = table.clone(state.boosts),
		lucky = state.lucky,
		played = math.floor(state.played),
		starter = state.starter,
		receipts = table.clone(state.receipts),
	}
end

-- Cette méthode permet de savoir si un reçu (PurchaseId) a déjà été attribué lorsque Roblox (re)présente un achat.
function Store.hasReceipt(state: State, purchaseId: string): boolean
	return table.find(state.receipts, purchaseId) ~= nil
end

-- Cette méthode permet de noter un reçu attribué (les RECEIPT_KEEP derniers sont gardés) lorsque un achat est accordé.
function Store.noteReceipt(state: State, purchaseId: string)
	if not Store.hasReceipt(state, purchaseId) then
		table.insert(state.receipts, purchaseId)
		while #state.receipts > Store.RECEIPT_KEEP do
			table.remove(state.receipts, 1)
		end
	end
end

-- Cette méthode permet d'attribuer un reçu une seule fois (`grant` n'est pas rappelé pour un reçu déjà noté ; le reçu
-- n'est noté que si `grant` réussit) lorsque Roblox présente ou représente un achat ; renvoie true si le reçu est
-- (maintenant ou déjà) attribué.
function Store.applyReceipt(state: State, purchaseId: string, grant: () -> boolean): boolean
	if Store.hasReceipt(state, purchaseId) then
		return true
	end
	if not grant() then
		return false
	end
	Store.noteReceipt(state, purchaseId)
	return true
end

-- Cette méthode permet d'encoder les passes possédés (« BigBase,VIP », ordre du catalogue) lorsque le serveur les
-- publie dans un attribut du joueur.
function Store.encodePasses(passes: { [string]: boolean }): string
	local ids = {}
	for _, item in Store.ITEMS do
		if passes[item.id] then
			table.insert(ids, item.id)
		end
	end
	return table.concat(ids, ",")
end

-- Cette méthode permet de relire les passes publiés (identifiants inconnus ignorés) lorsque le client ou un service
-- du serveur lit l'attribut Passes.
function Store.decodePasses(text: any): { [string]: boolean }
	local passes = {}
	if type(text) == "string" then
		for id in string.gmatch(text, "[^,]+") do
			local item = Store.get(id)
			if item and item.kind == "Pass" then
				passes[id] = true
			end
		end
	end
	return passes
end

-- Cette méthode permet de prolonger un boost de `seconds` (cumul : la durée s'ajoute à ce qui reste) lorsque le joueur
-- en achète un.
function Store.addBoost(state: State, kind: string, seconds: number)
	assert(Store.BOOSTS[kind], "Store : boost inconnu " .. tostring(kind))
	state.boosts[kind] = math.min((state.boosts[kind] or 0) + seconds, Store.BOOST_MAX)
end

-- Cette méthode permet de faire avancer les minuteurs de `dt` secondes passées en jeu (temps de jeu compris) lorsque
-- l'horloge du serveur tourne ; renvoie les boosts qui viennent de finir.
function Store.tick(state: State, dt: number): { string }
	state.played += dt
	local ended = {}
	for kind, left in state.boosts do
		local rest = left - dt
		if rest <= 0 then
			state.boosts[kind] = nil
			table.insert(ended, kind)
		else
			state.boosts[kind] = rest
		end
	end
	table.sort(ended)
	return ended
end

-- Ce que voit le calcul des multiplicateurs : passes possédés, boosts actifs, chance du serveur, lancer chanceux
export type Active = {
	passes: { [string]: boolean },
	boosts: { [string]: boolean | number }, -- boost actif (secondes restantes ou fin, peu importe)
	serverLuck: boolean?,
	lucky: boolean?,
}

-- Cette méthode permet de calculer le multiplicateur de CHANCE de la boutique (2x Luck, potion la plus forte, chance du
-- serveur, lancer chanceux) lorsque un lancer part.
function Store.luck(active: Active): number
	local multiplier = 1
	if active.passes.Luck2x then
		multiplier *= 2
	end
	if active.boosts.Luck5 then
		multiplier *= Store.BOOSTS.Luck5.multiplier
	elseif active.boosts.Luck2 then
		multiplier *= Store.BOOSTS.Luck2.multiplier
	end
	if active.serverLuck then
		multiplier *= Store.SERVER_LUCK
	end
	if active.lucky then
		multiplier *= Store.LUCKY_THROW
	end
	return multiplier
end

-- Cette méthode permet de calculer le multiplicateur de revenu de la boutique (2x Money, VIP, boost d'argent) lorsque
-- le revenu de la base est recalculé.
function Store.income(active: Active): number
	local multiplier = 1
	if active.passes.Money2x then
		multiplier *= 2
	end
	if active.passes.VIP then
		multiplier *= Store.VIP_INCOME
	end
	if active.boosts.Money then
		multiplier *= Store.BOOSTS.Money.multiplier
	end
	return multiplier
end

-- Cette méthode permet de calculer le multiplicateur d'EXP d'entraînement de la boutique (Strong Arms, boost
-- d'entraînement) lorsque une répétition est comptée.
function Store.training(active: Active): number
	local multiplier = 1
	if active.passes.StrongArms then
		multiplier *= 2
	end
	if active.boosts.Train then
		multiplier *= Store.BOOSTS.Train.multiplier
	end
	return multiplier
end

-- Cette méthode permet de donner les présentoirs ajoutés par la boutique (Big Base) lorsque la capacité de la base est
-- calculée.
function Store.displayBonus(passes: { [string]: boolean }): number
	return if passes.BigBase then Store.BIG_BASE else 0
end

-- Cette méthode permet de calculer l'argent rapide (`minutes` de revenu au revenu affiché `income` $/s, au moins
-- CASH_MIN_INCOME) lorsque le joueur en achète.
function Store.cash(minutes: number, income: number): number
	local perSecond = math.max(if income == income then income else 0, Store.CASH_MIN_INCOME)
	return math.floor(perSecond * minutes * 60)
end

-- Cette méthode permet de donner le temps restant (s) de l'offre du pack de démarrage lorsque la fenêtre ou le serveur
-- la consultent ; nil si elle est passée ou déjà achetée.
function Store.starterLeft(state: State): number?
	if state.starter then
		return nil
	end
	local left = Store.STARTER_WINDOW - state.played
	return if left > 0 then left else nil
end

-- Cette méthode permet de donner la chance du Rainbow Dummy (1,5 × la chance `best` du meilleur mannequin possédé,
-- RAINBOW_MIN au moins) lorsque le Rainbow Dummy est lancé ou affiché.
function Store.rainbowLuck(best: number): number
	return math.max(Store.RAINBOW_MIN, best * Store.RAINBOW_FACTOR)
end

-- Cette méthode permet d'écrire une durée restante en « 14:59 » ou « 1:02:03 » lorsque un minuteur s'affiche.
function Store.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h, m, r = s // 3600, (s // 60) % 60, s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

return Store
