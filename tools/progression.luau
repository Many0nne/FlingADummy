-- Joueur simulé de la progression longue (#94, #15) : estime le temps de jeu pour atteindre chaque palier (équipement
-- d'entraînement, mannequin à lancer, présentoir, première sortie de chaque rareté, renaissance) et mesure le « mur »
-- (ratio « prix du prochain achat / revenu », achat par achat et minute par minute). Simulation : tools/ProgressionSim.
-- Usage : lune run tools/progression [joueurs] [heures] [facteur de prix des renaissances] [fichier CSV minute par minute]
-- [part des boutons « 2x TRAINING! » cliqués, #119]
-- (défaut : 40 joueurs, 14 h, Rebirth.PRICE_GROWTH ; renaissances : 100 h et plus)
local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("../tests/lib/Loader")
local ProgressionSim = require("./ProgressionSim")

local m = ProgressionSim.modules(Loader.new())
local Collection, Format, GameConfig = m.Collection, m.Format, m.GameConfig
local Rarity, Rebirth, ThrowDummies, Training = m.Rarity, m.Rebirth, m.ThrowDummies, m.Training

local PLAYERS = tonumber(process.args[1]) or 40
local HOURS = tonumber(process.args[2]) or 14
-- 3e argument (essai) : facteur de prix entre deux renaissances à la place de Rebirth.PRICE_GROWTH
Rebirth.PRICE_GROWTH = tonumber(process.args[3]) or Rebirth.PRICE_GROWTH
local CSV = if process.args[4] ~= "" then process.args[4] else nil -- "" : pas de CSV (pour passer le 5e argument)
-- 5e argument : part des boutons « 2x TRAINING! » cliqués à temps (#119 ; 0 = sans le bonus, pour comparer)
ProgressionSim.BOOST_SUCCESS = tonumber(process.args[5]) or ProgressionSim.BOOST_SUCCESS

local runs = {}
for seed = 1, PLAYERS do
	table.insert(runs, ProgressionSim.simulate(m, seed, HOURS * 3600))
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

-- Cette méthode permet de donner la médiane d'un palier sur tous les joueurs (nil si la moitié ne l'atteint pas)
-- lorsque l'on imprime le tableau.
local function median(key: string): number?
	local values = {}
	for _, run in runs do
		table.insert(values, run.marks[key] or math.huge)
	end
	return ProgressionSim.median(values)
end

-- Cette méthode permet de donner la médiane d'un champ du résultat final sur tous les joueurs lorsque l'on imprime le
-- bilan.
local function finalMedian(field: string): number
	local values = {}
	for _, run in runs do
		table.insert(values, (run.final :: any)[field])
	end
	return ProgressionSim.median(values) or 0
end

-- Cette méthode permet de nommer un achat (« Iron Dummy », « Display 8 », « Rebirth 1 ») lorsque l'on imprime la
-- courbe du ratio.
local function purchaseName(kind: string, index: number): string
	if kind == "gear" then
		return "Gear: " .. Training.GEARS[index].name
	elseif kind == "throw" then
		return "Throw: " .. ThrowDummies.LIST[index].name
	elseif kind == "display" then
		return "Display " .. index
	end
	return "Rebirth " .. index
end

print(string.format("Joueur simulé : %d joueurs, %d h, médianes\n", PLAYERS, HOURS))

print("| Relevé | Achats | Revenu | Puissance | Rareté max | Renaissances |")
print("|---|---|---|---|---|---|")
for index, at in ProgressionSim.SNAPSHOTS do
	if at <= HOURS * 3600 then
		local columns = { purchases = {}, income = {}, power = {}, rarity = {}, rebirths = {} }
		for _, run in runs do
			local snapshot = run.snapshots[index]
			for field, list in columns do
				table.insert(list, if snapshot then (snapshot :: any)[field] else math.huge)
			end
		end
		local rarity = ProgressionSim.median(columns.rarity)
		print(
			string.format(
				"| %s | %d | %s | %s | %s | %d |",
				duration(at),
				ProgressionSim.median(columns.purchases) or 0,
				Format.perSecond(ProgressionSim.median(columns.income) or 0),
				Format.short(ProgressionSim.median(columns.power) or 0),
				if rarity then Rarity.get(rarity).name else "-",
				ProgressionSim.median(columns.rebirths) or 0
			)
		)
	end
end

print("\n| # | Achat | Prix | Atteint | Prix suivant / revenu | Saut |")
print("|---|---|---|---|---|---|")
local steps = ProgressionSim.steps(runs)
local worst = 0
for k, step in steps do
	worst = math.max(worst, step.jump)
	print(
		string.format(
			"| %d | %s | %s | %s | %s | ×%.1f%s |",
			k,
			purchaseName(step.kind, step.index),
			Format.money(step.cost),
			duration(step.t),
			duration(step.ratio),
			step.jump,
			if step.jump > 2 then " ⚠" else ""
		)
	)
end
print(
	string.format(
		"Saut le plus fort du ratio d'un achat au suivant : ×%.2f (plancher %d s)",
		worst,
		ProgressionSim.RATIO_FLOOR
	)
)

-- Ratio minute par minute (médiane des joueurs), en minutes d'attente au revenu du moment
local minuteCount = HOURS * 60
local perMinute: { number } = {}
for minute = 1, minuteCount do
	local values = {}
	for _, run in runs do
		table.insert(values, run.minutes[minute] or math.huge)
	end
	perMinute[minute] = ProgressionSim.median(values) or math.huge
end
local marks = {}
for _, minute in { 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 90, 120, 180, 240, 360, 480, 600, 720, 840 } do
	if minute <= minuteCount then
		table.insert(marks, string.format("%d min : %s", minute, duration(perMinute[minute])))
	end
end
print("\nPrix suivant / revenu, minute par minute (médiane) : " .. table.concat(marks, " · "))
if CSV then
	local lines = { "minute,ratio_s" }
	for minute, value in perMinute do
		table.insert(lines, string.format("%d,%s", minute, if value == math.huge then "" else tostring(value)))
	end
	fs.writeFile(CSV, table.concat(lines, "\n") .. "\n")
	print("Courbe écrite dans " .. CSV)
end

print("\n| Équipement | Gain (EXP/rép.) | Prix | Atteint |")
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
print("\n| Renaissance | Prix | CHANCE | Atteinte |")
print("|---|---|---|---|")
for k = 1, 30 do
	local reached = median("rebirth:" .. k)
	print(
		string.format(
			"| %d | %s | %s | %s |",
			k,
			Format.money(Rebirth.price(k - 1)),
			Rebirth.luckText(k),
			duration(reached)
		)
	)
	if not reached then
		break
	end
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
		"track:2.4km",
		"track:3.6km",
		"track:4.8km",
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
		"\nFin (%d h, médiane) : %d renaissance(s), CHANCE %s, revenu %s, puissance %s",
		HOURS,
		finalMedian("rebirths"),
		Format.multiplier(finalMedian("chance")),
		Format.perSecond(finalMedian("income")),
		Format.short(finalMedian("power"))
	)
)
