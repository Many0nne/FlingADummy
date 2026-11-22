-- Mannequins de collection : catalogue (rareté, revenu, cote ; modèles dans Shared.DummyModels), tailles, tirage
-- « 1 en N » poussé par la CHANCE du lancer, probabilités affichables. Possession (stock, présentoirs, vente, Index) :
-- Shared.Inventory.
--
-- Tirage : on essaie les mannequins du plus rare au plus courant ; chacun sort avec la probabilité min(1, chance / n)
-- et le plus courant ramasse le reste. La chance multiplie donc les chances des raretés hautes, et les probabilités
-- exactes se calculent (Collection.probabilities) pour l'affichage. La taille se tire de même, à chance ^ 0,5.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DummyAura = require(Shared:WaitForChild("DummyAura"))
local DummyFamilies = require(Shared:WaitForChild("DummyFamilies"))
local DummyModels = require(Shared:WaitForChild("DummyModels"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Collection = {}

export type Dummy = {
	id: string,
	name: string,
	rarity: number, -- indice dans Shared.Rarity (1 Common … 7 Secret … 11 Infinity)
	income: number, -- $/s en taille Normal
	n: number, -- « 1 en n » de base : probabilité min(1, chance / n) quand vient son tour
}

export type Size = {
	name: string, -- préfixe affiché (vide en taille normale)
	income: number, -- multiplicateur du revenu
	scale: number, -- échelle du modèle
	n: number, -- « 1 en n » de base (la taille Normal ramasse le reste)
}

export type Entry = { id: string, size: number }


-- Mannequins dessinés (modèles de #66) ; le catalogue complet y ajoute les mannequins générés (Shared.DummyFamilies).
-- Revenus sur la règle des générés (#15, DummyFamilies.bandIncome) : plage de revenu de la rareté (Shared.Rarity),
-- × 2 dans une rareté et × 3 à son passage, en progression géométrique par cote croissante.
-- stylua: ignore
Collection.DRAWN = {
	-- Common
	{ id = "crash",    name = "Crash Dummy",    rarity = 1, income = 4,       n = 2 },
	{ id = "rookie",   name = "Rookie Dummy",   rarity = 1, income = 5,       n = 3 },
	{ id = "traffic",  name = "Traffic Dummy",  rarity = 1, income = 6,       n = 5 },
	-- Uncommon
	{ id = "mint",     name = "Mint Dummy",     rarity = 2, income = 25,      n = 10 },
	{ id = "biker",    name = "Biker Dummy",    rarity = 2, income = 29,      n = 15 },
	{ id = "nerd",     name = "Nerd Dummy",     rarity = 2, income = 33,      n = 25 },
	-- Rare
	{ id = "ocean",    name = "Ocean Dummy",    rarity = 3, income = 150,     n = 60 },
	{ id = "hero",     name = "Hero Dummy",     rarity = 3, income = 170,     n = 100 },
	{ id = "pilot",    name = "Pilot Dummy",    rarity = 3, income = 200,     n = 150 },
	-- Epic
	{ id = "ice",      name = "Ice Dummy",      rarity = 4, income = 900,     n = 500 },
	{ id = "toxic",    name = "Toxic Dummy",    rarity = 4, income = 1000,    n = 800 },
	{ id = "royal",    name = "Royal Dummy",    rarity = 4, income = 1200,    n = 1200 },
	-- Legendary
	{ id = "gold",     name = "Gold Dummy",     rarity = 5, income = 5500,    n = 4000 },
	{ id = "lava",     name = "Lava Dummy",     rarity = 5, income = 6300,    n = 7000 },
	{ id = "diamond",  name = "Diamond Dummy",  rarity = 5, income = 7300,    n = 10000 },
	-- Mythic
	{ id = "galaxy",   name = "Galaxy Dummy",   rarity = 6, income = 33000,   n = 40000 },
	{ id = "ghost",    name = "Ghost Dummy",    rarity = 6, income = 38000,   n = 70000 },
	{ id = "neon",     name = "Neon Dummy",     rarity = 6, income = 44000,   n = 100000 },
	-- Secret
	{ id = "king",     name = "Crash King",     rarity = 7, income = 200000,  n = 500000 },
	{ id = "void",     name = "Void Dummy",     rarity = 7, income = 230000,  n = 1000000 },
	{ id = "cosmic",   name = "Cosmic Dummy",   rarity = 7, income = 260000,  n = 2000000 },
} :: { Dummy }

-- Catalogue complet (#94) : dessinés puis générés (famille × palette), par rareté puis cote croissante. Les dessinés
-- restent en tête de leur rareté, dans leur ordre.
Collection.DUMMIES = table.clone(Collection.DRAWN)
for _, spec in DummyFamilies.specs(Collection.DRAWN) do
	table.insert(Collection.DUMMIES, spec)
end
table.sort(Collection.DUMMIES, function(a, b)
	if a.rarity ~= b.rarity then
		return a.rarity < b.rarity
	end
	return a.n < b.n
end)

-- Revenu × 2, × 5, × 12 selon la taille (#15 : une taille rare se sent sur le compteur, × 1,5 / × 3 / × 8 avant)
-- stylua: ignore
Collection.SIZES = {
	{ name = "",      income = 1,   scale = 1,    n = 1 },
	{ name = "Big",   income = 2,   scale = 1.3,  n = 8 },
	{ name = "Huge",  income = 5,   scale = 1.7,  n = 60 },
	{ name = "Giant", income = 12,  scale = 2.3,  n = 500 },
} :: { Size }

-- Échelle du modèle par rareté (indice de Shared.Rarity), multipliée par celle de la taille : plus rare, plus grand
-- (comme les arbres de plus en plus grands de la référence 09)
Collection.RARITY_SCALE = { 1, 1.1, 1.2, 1.32, 1.46, 1.62, 1.8, 1.86, 1.92, 1.98, 2.05 }
-- Échelle maximale sur un présentoir de la base (un Giant Secret, ×4,1, déborderait sur ses voisins) ; le tirage et
-- la main gardent l'échelle entière
Collection.DISPLAY_SCALE_MAX = 2.5

Collection.STARTER = "crash" -- premier mannequin, garanti au premier lancer
Collection.PROMPT_TAG = "DisplayPrompt" -- invites « Place » des présentoirs (attributs Slot, Display)
Collection.SELL_TAG = "SellStand" -- invite du stand SELL du hub (ouvre la fenêtre de vente)
Collection.PAD_TAG = "DisplayPad" -- invites des pads d'achat de présentoir (attributs Slot, Price, Maxed)

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

-- Cette méthode permet de donner le nom affiché d'une entrée (« Huge Gold Dummy ») lorsque l'interface la nomme.
function Collection.label(entry: Entry): string
	local dummy = byId[entry.id]
	local size = Collection.SIZES[entry.size]
	local name = if dummy then dummy.name else "???"
	return if size and size.name ~= "" then size.name .. " " .. name else name
end

-- Cette méthode permet de donner l'échelle du modèle d'une entrée (taille × rareté) lorsque l'on le construit
-- (présentoir, en main, tirage).
function Collection.scale(entry: Entry): number
	local dummy = byId[entry.id]
	local size = Collection.SIZES[entry.size]
	local rarity = if dummy then Collection.RARITY_SCALE[dummy.rarity] else nil
	return (if size then size.scale else 1) * (rarity or 1)
end

-- Cette méthode permet de donner l'échelle d'une entrée posée sur un présentoir de la base (celle de Collection.scale,
-- plafonnée à DISPLAY_SCALE_MAX : les présentoirs sont à 9 studs les uns des autres) lorsque la base est rendue.
function Collection.displayScale(entry: Entry): number
	return math.min(Collection.scale(entry), Collection.DISPLAY_SCALE_MAX)
end

-- Looks des mannequins générés, construits à la demande (famille × palette)
local generatedLooks: { [string]: any } = {}

-- Cette méthode permet de donner le look d'un mannequin (dessiné : Shared.DummyModels ; généré : famille × palette,
-- Shared.DummyFamilies) lorsque l'on construit son modèle.
function Collection.look(id: string): any
	local drawn = DummyModels.LOOKS[id]
	if drawn then
		return drawn
	end
	local cached = generatedLooks[id]
	if cached then
		return cached
	end
	local family, palette = DummyFamilies.parse(id)
	local look = if family and palette
		then DummyFamilies.look(family, palette)
		else DummyModels.LOOKS[Collection.STARTER]
	generatedLooks[id] = look
	return look
end

-- Cette méthode permet de donner la déclinaison du modèle d'une entrée (couleur du corps et par pièce, matériau,
-- pièces masquées, pièces ajoutées, effets du modèle : Shared.DummyModels, puis thème et aura de rareté :
-- Shared.DummyAura) lorsque l'on construit son modèle (Shared.DummyShape) ; `carried` (porté en main) écarte les
-- effets de l'aura posés au sol.
function Collection.variant(entry: Entry, carried: boolean?): { [string]: any }
	local dummy = byId[entry.id] or byId[Collection.STARTER]
	local look = Collection.look(dummy.id)
	local effects = {}
	for _, effect in look.effects or {} do
		if not (carried and DummyAura.isGrounded(effect)) then
			table.insert(effects, effect)
		end
	end
	for _, effect in DummyAura.effects(dummy.id, dummy.rarity, carried) do
		table.insert(effects, effect)
	end
	return {
		color = look.color,
		material = look.material,
		pieceColors = look.pieceColors,
		hidden = look.hidden,
		accessories = look.accessories,
		accessoryColors = look.accessoryColors,
		accessoryMaterial = look.accessoryMaterial,
		effects = if #effects > 0 then effects else nil,
	}
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

-- Cette méthode permet de donner la cote affichée pendant qu'elle grimpe de `from` à `to` (avancement `t` de 0 à 1),
-- comme un compteur qui défile vite puis ralentit à l'approche du palier, lorsque le suspense du tirage s'anime :
-- progression géométrique (1 → 10 → 100 au même rythme), entière, `to` exactement à la fin.
function Collection.climbOdds(from: number, to: number, t: number): number
	local k = math.clamp(t, 0, 1)
	if k >= 1 or to <= from then
		return to
	end
	local eased = 1 - (1 - k) ^ 3
	local low = math.max(from, 1)
	return math.clamp(math.floor(low * (to / low) ^ eased), from, to)
end

-- Cette méthode permet de donner la durée (s) de la montée de la cote de `from` à `to` lorsque le suspense passe au
-- palier suivant : plus l'écart est grand, plus le compteur défile longtemps (0,7 à 1,5 s).
function Collection.climbTime(from: number, to: number): number
	local decades = math.log10(math.max(to, 1) / math.max(from, 1))
	return math.clamp(0.7 + 0.25 * decades, 0.7, 1.5)
end

export type TeaseStep = { id: string, size: number, odds: number, rarity: number }

-- Cette méthode permet de donner les étapes du suspense avant la révélation, comme la silhouette de la référence 09
-- qui se change en candidats de plus en plus rares (pousse « 1 EN 3 » → buisson « 1 EN 40 » → arbre « 1 EN 1.37K ») :
-- 0 à 3 mannequins plus courants que le gagné, à cotes croissantes (chacun à sa propre cote), puis le gagné lui-même
-- (dernière étape, sa cote) lorsque le tirage se joue.
function Collection.teaseSequence(entry: Entry): { TeaseStep }
	local prize = byId[entry.id]
	local finalOdds = Collection.odds(entry)
	local sequence: { TeaseStep } = {}
	local lastOdds = 1
	for _, value in Collection.teaseSteps(finalOdds) do
		-- Candidat : le mannequin (autre que le gagné, pas plus rare) dont la cote approche le palier par en dessous
		local best: Dummy? = nil
		for _, dummy in Collection.DUMMIES do
			local odds = baseOdds[dummy.id]
			if dummy.id ~= entry.id and dummy.rarity <= prize.rarity and odds <= value and odds > lastOdds then
				if not best or odds > baseOdds[best.id] then
					best = dummy
				end
			end
		end
		if best and baseOdds[best.id] < finalOdds then
			lastOdds = baseOdds[best.id]
			table.insert(sequence, { id = best.id, size = 1, odds = lastOdds, rarity = best.rarity })
		end
	end
	table.insert(sequence, { id = entry.id, size = entry.size, odds = finalOdds, rarity = prize.rarity })
	return sequence
end

return Collection
