-- Mannequins de collection : catalogue (rareté, revenu, cote, déclinaison du mannequin), tailles, tirage « 1 en N »
-- poussé par la CHANCE du lancer, probabilités affichables, et rangement dans la base (présentoirs).
--
-- Tirage : on essaie les mannequins du plus rare au plus courant ; chacun sort avec la probabilité min(1, chance / n)
-- et le plus courant ramasse le reste. La chance multiplie donc les chances des raretés hautes, et les probabilités
-- exactes se calculent (Collection.probabilities) pour l'affichage. La taille se tire de même, à chance ^ 0,5.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Collection = {}

export type Dummy = {
	id: string,
	name: string,
	rarity: number, -- indice dans Shared.Rarity (1 Common … 7 Secret)
	income: number, -- $/s en taille Normal
	n: number, -- « 1 en n » de base : probabilité min(1, chance / n) quand vient son tour
	color: Color3,
	material: Enum.Material?,
	accessories: { string }?,
	accessoryColor: Color3?,
}

export type Size = {
	name: string, -- préfixe affiché (vide en taille normale)
	income: number, -- multiplicateur du revenu
	scale: number, -- échelle du modèle
	n: number, -- « 1 en n » de base (la taille Normal ramasse le reste)
}

export type Entry = { id: string, size: number }

local rgb = Color3.fromRGB
local M = Enum.Material

-- stylua: ignore
Collection.DUMMIES = {
	-- Common
	{ id = "crash",    name = "Crash Dummy",    rarity = 1, income = 4,       n = 2,       color = rgb(255, 205, 40) },
	{ id = "rookie",   name = "Rookie Dummy",   rarity = 1, income = 5,       n = 3,       color = rgb(240, 240, 240) },
	{ id = "traffic",  name = "Traffic Dummy",  rarity = 1, income = 6,       n = 5,       color = rgb(255, 130, 30),
	  accessories = { "Helmet" }, accessoryColor = rgb(255, 255, 255) },
	-- Uncommon
	{ id = "mint",     name = "Mint Dummy",     rarity = 2, income = 15,      n = 10,      color = rgb(110, 235, 170) },
	{ id = "biker",    name = "Biker Dummy",    rarity = 2, income = 22,      n = 15,      color = rgb(225, 50, 50),
	  accessories = { "Helmet" }, accessoryColor = rgb(40, 40, 45) },
	{ id = "nerd",     name = "Nerd Dummy",     rarity = 2, income = 30,      n = 25,      color = rgb(140, 200, 255),
	  accessories = { "Glasses" }, accessoryColor = rgb(30, 30, 35) },
	-- Rare
	{ id = "ocean",    name = "Ocean Dummy",    rarity = 3, income = 70,      n = 60,      color = rgb(40, 120, 255) },
	{ id = "hero",     name = "Hero Dummy",     rarity = 3, income = 100,     n = 100,     color = rgb(230, 40, 40),
	  accessories = { "Cape" }, accessoryColor = rgb(40, 90, 255) },
	{ id = "pilot",    name = "Pilot Dummy",    rarity = 3, income = 150,     n = 150,     color = rgb(70, 165, 60),
	  accessories = { "Helmet", "Glasses" }, accessoryColor = rgb(120, 80, 40) },
	-- Epic
	{ id = "ice",      name = "Ice Dummy",      rarity = 4, income = 400,     n = 500,     color = rgb(160, 225, 255),
	  material = M.Ice },
	{ id = "toxic",    name = "Toxic Dummy",    rarity = 4, income = 550,     n = 800,     color = rgb(110, 255, 60),
	  material = M.Neon },
	{ id = "royal",    name = "Royal Dummy",    rarity = 4, income = 700,     n = 1200,    color = rgb(150, 70, 230),
	  accessories = { "Cape" }, accessoryColor = rgb(255, 200, 40) },
	-- Legendary
	{ id = "gold",     name = "Gold Dummy",     rarity = 5, income = 2500,    n = 4000,    color = rgb(255, 195, 40),
	  material = M.Foil },
	{ id = "lava",     name = "Lava Dummy",     rarity = 5, income = 3500,    n = 7000,    color = rgb(255, 90, 30),
	  material = M.CrackedLava },
	{ id = "diamond",  name = "Diamond Dummy",  rarity = 5, income = 5000,    n = 10000,   color = rgb(120, 230, 255),
	  material = M.Glass, accessories = { "Glasses" }, accessoryColor = rgb(255, 255, 255) },
	-- Mythic
	{ id = "galaxy",   name = "Galaxy Dummy",   rarity = 6, income = 20000,   n = 40000,   color = rgb(120, 60, 255),
	  material = M.Neon, accessories = { "Cape" }, accessoryColor = rgb(30, 20, 60) },
	{ id = "ghost",    name = "Ghost Dummy",    rarity = 6, income = 30000,   n = 70000,   color = rgb(235, 245, 255),
	  material = M.ForceField },
	{ id = "neon",     name = "Neon Dummy",     rarity = 6, income = 40000,   n = 100000,  color = rgb(255, 60, 200),
	  material = M.Neon, accessories = { "Glasses" }, accessoryColor = rgb(60, 255, 255) },
	-- Secret
	{ id = "king",     name = "Crash King",     rarity = 7, income = 150000,  n = 500000,  color = rgb(255, 200, 40),
	  material = M.Foil, accessories = { "Helmet", "Cape" }, accessoryColor = rgb(230, 30, 50) },
	{ id = "void",     name = "Void Dummy",     rarity = 7, income = 200000,  n = 1000000, color = rgb(20, 18, 30),
	  accessories = { "Glasses", "Cape" }, accessoryColor = rgb(170, 60, 255) },
	{ id = "cosmic",   name = "Cosmic Dummy",   rarity = 7, income = 300000,  n = 2000000, color = rgb(190, 120, 255),
	  material = M.ForceField, accessories = { "Helmet" }, accessoryColor = rgb(110, 255, 225) },
} :: { Dummy }

-- stylua: ignore
Collection.SIZES = {
	{ name = "",      income = 1,   scale = 1,    n = 1 },
	{ name = "Big",   income = 1.5, scale = 1.3,  n = 8 },
	{ name = "Huge",  income = 3,   scale = 1.7,  n = 60 },
	{ name = "Giant", income = 8,   scale = 2.3,  n = 500 },
} :: { Size }

Collection.STARTER = "crash" -- premier mannequin, garanti au premier lancer
Collection.PROMPT_TAG = "DisplayPrompt" -- invites « Place » des présentoirs (attributs Slot, Display)

local byId: { [string]: Dummy } = {}
for _, dummy in Collection.DUMMIES do
	byId[dummy.id] = dummy
end

-- Ordre d'essai du tirage : du plus rare au plus courant (le dernier ramasse le reste)
local drawOrder = table.clone(Collection.DUMMIES)
table.sort(drawOrder, function(a, b)
	return a.n > b.n
end)

-- Cette méthode permet de donner un mannequin du catalogue lorsque l'on connaît son identifiant ; nil s'il n'existe
-- pas (sauvegarde d'une version plus récente, donnée corrompue).
function Collection.get(id: string): Dummy?
	return byId[id]
end

-- Cette méthode permet de savoir si une entrée (mannequin + taille) est valide lorsque l'on lit une sauvegarde ou
-- une demande.
function Collection.isEntry(entry: any): boolean
	return type(entry) == "table"
		and type(entry.id) == "string"
		and byId[entry.id] ~= nil
		and type(entry.size) == "number"
		and Collection.SIZES[entry.size] ~= nil
end

-- Cette méthode permet de calculer la probabilité de sortie de chaque élément d'une liste essayée dans l'ordre
-- (`p(i)` : probabilité de l'élément quand vient son tour, le dernier ramasse le reste) lorsque l'on tire ou affiche.
local function sequential(count: number, p: (number) -> number): { number }
	local result = {}
	local remaining = 1
	for i = 1, count do
		local chance = if i == count then 1 else math.clamp(p(i), 0, 1)
		result[i] = remaining * chance
		remaining *= 1 - chance
	end
	return result
end

-- Cette méthode permet de donner la probabilité de sortie de chaque mannequin (par identifiant) lorsque la CHANCE
-- vaut `luck` (Index, tableau des probabilités, tests).
function Collection.probabilities(luck: number): { [string]: number }
	local list = sequential(#drawOrder, function(i)
		return luck / drawOrder[i].n
	end)
	local result = {}
	for i, dummy in drawOrder do
		result[dummy.id] = list[i]
	end
	return result
end

-- Cette méthode permet de donner la probabilité de chaque taille (indice dans SIZES) lorsque la CHANCE vaut `luck`.
function Collection.sizeProbabilities(luck: number): { number }
	local sizeLuck = math.max(1, luck) ^ GameConfig.SIZE_LUCK_POWER
	local count = #Collection.SIZES
	-- Essai de la plus rare à la plus courante : indice count, count - 1, …, 1
	local list = sequential(count, function(i)
		return sizeLuck / Collection.SIZES[count + 1 - i].n
	end)
	local result = {}
	for i = 1, count do
		result[count + 1 - i] = list[i]
	end
	return result
end

-- Cette méthode permet de tirer un mannequin et sa taille lorsque le mannequin lancé s'arrête ; `roll` rend un
-- nombre dans [0, 1) (Random:NextNumber, ou suite fixe dans les tests).
function Collection.draw(luck: number, roll: () -> number): Entry
	local id = drawOrder[#drawOrder].id
	for i, dummy in drawOrder do
		if i == #drawOrder or roll() < luck / dummy.n then
			id = dummy.id
			break
		end
	end
	local sizeLuck = math.max(1, luck) ^ GameConfig.SIZE_LUCK_POWER
	local size = 1
	for index = #Collection.SIZES, 2, -1 do
		if roll() < sizeLuck / Collection.SIZES[index].n then
			size = index
			break
		end
	end
	return { id = id, size = size }
end

-- Cotes affichées (« 1 IN N ») : l'inverse des probabilités à la chance de base, arrondi
local baseOdds: { [string]: number } = {}
for id, p in Collection.probabilities(1) do
	baseOdds[id] = math.max(1, math.floor(1 / p + 0.5))
end
local sizeOdds: { number } = {}
for index, p in Collection.sizeProbabilities(1) do
	sizeOdds[index] = if index == 1 then 1 else math.floor(1 / p + 0.5)
end

-- Cette méthode permet de donner la cote affichée d'une entrée (« 1 IN N » : mannequin × taille, à la chance de
-- base) lorsque le tirage est révélé.
function Collection.odds(entry: Entry): number
	return (baseOdds[entry.id] or 1) * (sizeOdds[entry.size] or 1)
end

-- Cette méthode permet de calculer le revenu ($/s) d'une entrée lorsqu'elle est posée dans la base.
function Collection.income(entry: Entry): number
	local dummy = byId[entry.id]
	local size = Collection.SIZES[entry.size]
	if not dummy or not size then
		return 0
	end
	return math.floor(dummy.income * size.income + 0.5)
end

-- Cette méthode permet de donner le prix de revente d'une entrée (SELL_SECONDS de son revenu) lorsque la base est
-- pleine et qu'elle n'y entre pas, ou qu'elle cède sa place.
function Collection.sellValue(entry: Entry): number
	return Collection.income(entry) * GameConfig.SELL_SECONDS
end

-- Cette méthode permet de donner le nom affiché d'une entrée (« Huge Gold Dummy ») lorsque l'interface la nomme.
function Collection.label(entry: Entry): string
	local dummy = byId[entry.id]
	local size = Collection.SIZES[entry.size]
	local name = if dummy then dummy.name else "???"
	return if size and size.name ~= "" then size.name .. " " .. name else name
end

-- Cette méthode permet de donner la déclinaison du mannequin (couleur, matériau, accessoires) d'une entrée lorsque
-- l'on construit son modèle (Shared.DummyShape).
function Collection.variant(entry: Entry): { [string]: any }
	local dummy = byId[entry.id] or byId[Collection.STARTER]
	return {
		color = dummy.color,
		material = dummy.material,
		accessories = dummy.accessories,
		accessoryColor = dummy.accessoryColor,
	}
end

-- Cette méthode permet de choisir où ranger une entrée gagnée (bouton AUTO) lorsque la base a `capacity`
-- présentoirs : le premier libre, sinon celui du mannequin le moins rentable s'il rapporte moins que l'entrée ; nil si
-- l'entrée doit être revendue.
function Collection.autoSlot(slots: { [number]: Entry | false }, capacity: number, entry: Entry): number?
	local worst, worstIncome = nil, math.huge
	for index = 1, capacity do
		local placed = slots[index]
		if not placed then
			return index
		end
		local income = Collection.income(placed)
		if income < worstIncome then
			worst, worstIncome = index, income
		end
	end
	if worst and Collection.income(entry) > worstIncome then
		return worst
	end
	return nil
end

-- Cette méthode permet de calculer le revenu total de la base lorsque ses présentoirs changent.
function Collection.baseIncome(slots: { [number]: Entry | false }, capacity: number): number
	local total = 0
	for index = 1, capacity do
		local placed = slots[index]
		if placed then
			total += Collection.income(placed)
		end
	end
	return total
end

-- Cette méthode permet de donner les cotes montrées sur la silhouette avant la révélation (1 à 3 paliers qui
-- grimpent, tous sous la cote finale, comme « 1 IN 3 » → « 1 IN 40 » → « 1 IN 1.37K ») lorsque le tirage se joue.
function Collection.teaseSteps(odds: number): { number }
	local count = if odds < 20 then 1 elseif odds < 1000 then 2 else 3
	local steps = {}
	local last = 1
	for i = 1, count do
		local value = math.floor(odds ^ (i / (count + 1)) + 0.5)
		value = math.max(value, last + 1, 2)
		if value >= odds then
			break
		end
		table.insert(steps, value)
		last = value
	end
	return steps
end

return Collection
