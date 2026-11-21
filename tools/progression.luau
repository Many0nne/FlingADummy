-- Joueur simulé de la progression longue (#94) : estime le temps de jeu pour atteindre chaque palier (équipement
-- d'entraînement, mannequin à lancer, présentoir, première sortie de chaque rareté) avec les vrais modules du jeu
-- (tirage Shared.Collection, entraînement Shared.Training, CHANCE Shared.Economy, prix Shared.ThrowDummies). Modèle
-- simple, à recaler sur les mesures de Studio (#15) : distance ∝ vitesse² (calée sur les vols mesurés de #14), une
-- boucle = un lancer (THROW_TIME s) puis TRAIN_TIME s d'entraînement, achats dès que possible (le moins cher d'abord),
-- mannequins hors présentoirs vendus aussitôt.
-- Usage : lune run tools/progression [joueurs] [heures]   (défaut : 40 joueurs, 12 h)
local process = require("@lune/process")

local Loader = require("../tests/lib/Loader")

local loader = Loader.new()
local Collection = loader:require("src/shared/Collection")
local Economy = loader:require("src/shared/Economy")
local Format = loader:require("src/shared/Format")
local GameConfig = loader:require("src/shared/GameConfig")
local Inventory = loader:require("src/shared/Inventory")
local Rarity = loader:require("src/shared/Rarity")
local ThrowDummies = loader:require("src/shared/ThrowDummies")
local Training = loader:require("src/shared/Training")

local PLAYERS = tonumber(process.args[1]) or 40
local HOURS = tonumber(process.args[2]) or 12

local THROW_TIME = 15 -- lancer, vol, tirage et retour (s ; 15 s mesurés sur Throw a Seed)
local TRAIN_TIME = 15 -- entraînement entre deux lancers (s)
-- Distance (m) ≈ DIST_K × vitesse² : 145-168 m à la puissance 10, ≈ 1 150 m à 10,5 K (vols mesurés de #14)
local DIST_K = 0.012
-- Bonus des os et objets (part ajoutée à la CHANCE) : ≈ +30 % au départ, ≈ +55 % à 10,5 K de puissance (mesures #14)
local BONUS_BASE, BONUS_PER_LOG = 0.3, 0.035

-- Cette méthode permet d'estimer la distance d'un lancer jauge pleine lorsque le joueur a `power` de Throw Power.
local function distanceFor(power: number): number
	local v = Economy.launchSpeed(power)
	return math.min(DIST_K * v * v, GameConfig.COURSE_LENGTH)
end

-- Cette méthode permet d'estimer la CHANCE d'un lancer lorsque le joueur a `power` et lance un mannequin de chance `luck`.
local function chanceFor(power: number, luck: number): number
	local bonus = BONUS_BASE + BONUS_PER_LOG * math.log(math.max(power, 10) / 10)
	return Economy.zoneChance(distanceFor(power)) * (1 + bonus) * luck
end

-- Cette méthode permet de simuler un joueur pendant `seconds` s lorsque l'on estime la courbe ; renvoie les instants
-- (s) de chaque palier, par clé (« gear:3 », « throw:7 », « display:8 », « rarity:5 », « power:1M »…).
local function simulate(seed: number, seconds: number): { [string]: number }
	math.randomseed(seed)
	local roll = function()
		return math.random()
	end
	local t = 0
	local money = 0
	local power = GameConfig.START_POWER
	local progress = { level = 1, exp = 0 }
	local gear, thrown = 1, 1
	local displays = GameConfig.DISPLAY_START
	local base: { number } = {} -- revenus des mannequins posés
	local draws = 0
	local marks: { [string]: number } = {}

	-- Cette méthode permet de noter l'instant où un palier est atteint pour la première fois lorsque la simulation avance.
	local function mark(key: string)
		if marks[key] == nil then
			marks[key] = t
		end
	end
	-- Cette méthode permet de donner le revenu de la base ($/s) lorsque le temps de jeu avance.
	local function income(): number
		local total = 0
		for _, value in base do
			total += value
		end
		return total
	end
	-- Cette méthode permet de poser un mannequin gagné s'il est parmi les plus rentables, et de vendre le moins rentable
	-- (2 min de revenu) lorsque la base déborde après un tirage.
	local function receive(entry)
		local value = Collection.income(entry)
		table.insert(base, value)
		table.sort(base, function(a, b)
			return a > b
		end)
		while #base > displays do
			money += (table.remove(base) :: number) * GameConfig.SELL_MINUTES * 60
		end
	end
	-- Cette méthode permet d'acheter tout ce qui est abordable, le moins cher d'abord (équipement, mannequin à lancer,
	-- présentoir), lorsque l'argent change.
	local function shop()
		while true do
			local options = {}
			local nextGear = Training.nextGearCost(gear)
			if nextGear then
				table.insert(options, { kind = "gear", cost = nextGear })
			end
			local nextThrow = ThrowDummies.nextCost(thrown)
			if nextThrow then
				table.insert(options, { kind = "throw", cost = nextThrow })
			end
			local nextDisplay = Inventory.displayPrice(displays)
			if nextDisplay then
				table.insert(options, { kind = "display", cost = nextDisplay })
			end
			table.sort(options, function(a, b)
				return a.cost < b.cost
			end)
			local pick = options[1]
			if not pick or pick.cost > money then
				return
			end
			money -= pick.cost
			if pick.kind == "gear" then
				gear += 1
				mark("gear:" .. gear)
			elseif pick.kind == "throw" then
				thrown += 1
				mark("throw:" .. thrown)
			else
				displays += 1
				mark("display:" .. displays)
			end
		end
	end

	while t < seconds do
		-- Lancer
		local entry
		if draws == 0 then
			entry = { id = Collection.STARTER, size = 1 }
		else
			entry = Collection.draw(chanceFor(power, ThrowDummies.get(thrown).luck), roll)
		end
		draws += 1
		t += THROW_TIME
		money += income() * THROW_TIME
		receive(entry)
		local dummy = Collection.get(entry.id)
		mark("rarity:" .. dummy.rarity)
		mark("first")
		shop()
		-- Entraînement
		local reps = math.floor(TRAIN_TIME / GameConfig.REP_TIME)
		for _ = 1, reps do
			local gained
			progress, gained = Training.completeRep(progress, gear)
			power += gained
		end
		t += TRAIN_TIME
		money += income() * TRAIN_TIME
		for _, threshold in { 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10 } do
			if power >= threshold then
				mark("power:" .. Format.short(threshold))
			end
		end
		if distanceFor(power) >= GameConfig.COURSE_LENGTH then
			mark("trackEnd")
		end
		for _, threshold in { 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9 } do
			if income() >= threshold then
				mark("income:" .. Format.short(threshold))
			end
		end
		shop()
	end
	marks.finalChance = chanceFor(power, ThrowDummies.get(thrown).luck)
	marks.finalIncome = income()
	marks.finalPower = power
	return marks
end

-- Cette méthode permet d'écrire une durée lisible (« 45 s », « 12 min », « 3.4 h ») lorsque l'on imprime le tableau.
local function duration(s: number?): string
	if s == nil then
		return string.format("> %d h", HOURS)
	elseif s < 120 then
		return string.format("%d s", s)
	elseif s < 7200 then
		return string.format("%d min", math.floor(s / 60 + 0.5))
	end
	return string.format("%.1f h", s / 3600)
end

local runs = {}
for seed = 1, PLAYERS do
	table.insert(runs, simulate(seed, HOURS * 3600))
end

-- Cette méthode permet de donner la médiane d'un palier sur tous les joueurs (nil si la moitié ne l'atteint pas)
-- lorsque l'on imprime le tableau.
local function median(key: string): number?
	local values = {}
	for _, marks in runs do
		table.insert(values, marks[key] or math.huge)
	end
	table.sort(values)
	local value = values[math.floor((#values + 1) / 2)]
	return if value == math.huge then nil else value
end

print(string.format("Joueur simulé : %d joueurs, %d h, médianes\n", PLAYERS, HOURS))
print("| Équipement | Gain (EXP/rép.) | Prix | Atteint |")
print("|---|---|---|---|")
for tier, g in Training.GEARS do
	print(
		string.format(
			"| %s | +%s | %s | %s |",
			g.name,
			Format.short(g.gain),
			Format.money(g.cost),
			if tier == 1 then "départ" else duration(median("gear:" .. tier))
		)
	)
end
print("\n| Mannequin à lancer | Chance | Prix | Atteint |")
print("|---|---|---|---|")
for index, d in ThrowDummies.LIST do
	print(
		string.format(
			"| %s | %s | %s | %s |",
			d.name,
			Format.luck(d.luck),
			Format.money(d.cost),
			if index == 1 then "départ" else duration(median("throw:" .. index))
		)
	)
end
print("\n| Rareté | Cotes (taille normale) | Revenu ($/s) | Mannequins | Premier obtenu |")
print("|---|---|---|---|---|")
for rarity, tier in Rarity.LIST do
	local minN, maxN, minI, maxI, count = math.huge, 0, math.huge, 0, 0
	for _, dummy in Collection.DUMMIES do
		if dummy.rarity == rarity then
			local odds = Collection.odds({ id = dummy.id, size = 1 })
			minN, maxN = math.min(minN, odds), math.max(maxN, odds)
			minI, maxI = math.min(minI, dummy.income), math.max(maxI, dummy.income)
			count += 1
		end
	end
	print(
		string.format(
			"| %s | %s à %s | %s à %s | %d | %s |",
			tier.name,
			Format.odds(minN),
			Format.short(maxN),
			Format.short(minI),
			Format.short(maxI),
			count,
			duration(median("rarity:" .. rarity))
		)
	)
end
print("\n| Présentoir | Prix | Atteint |")
print("|---|---|---|")
for count = GameConfig.DISPLAY_START + 1, GameConfig.DISPLAY_START + #GameConfig.DISPLAY_PRICES do
	print(
		string.format(
			"| %d | %s | %s |",
			count,
			Format.money(GameConfig.DISPLAY_PRICES[count - GameConfig.DISPLAY_START]),
			duration(median("display:" .. count))
		)
	)
end
print("\n| Repère | Atteint |")
print("|---|---|")
for _, key in
	{
		"first",
		"power:100",
		"power:1K",
		"power:10K",
		"power:100K",
		"power:1M",
		"power:10M",
		"power:100M",
		"power:1B",
		"power:10B",
		"trackEnd",
		"income:100",
		"income:1K",
		"income:10K",
		"income:100K",
		"income:1M",
		"income:10M",
	}
do
	print(string.format("| %s | %s |", key, duration(median(key))))
end
print(
	string.format(
		"\nFin (%d h, médiane) : CHANCE %s, revenu %s, puissance %s",
		HOURS,
		Format.multiplier(median("finalChance") or 0),
		Format.perSecond(median("finalIncome") or 0),
		Format.short(median("finalPower") or 0)
	)
)
