-- Joueur simulé de la progression (#94, #15) : estime le temps de jeu pour atteindre chaque palier (équipement
-- d'entraînement, mannequin à lancer, présentoir, rareté, renaissance) avec les vrais modules du jeu (tirage
-- Shared.Collection, entraînement Shared.Training, CHANCE Shared.Economy, prix Shared.ThrowDummies, Shared.Inventory,
-- Shared.Rebirth). Modèle simple : distance d'un vol plafonné (Shared.FlightArc, recalée sur les vols de #113), une
-- boucle = un lancer (THROW_TIME s) puis TRAIN_TIME s d'entraînement, achats dès que possible (le moins cher
-- d'abord), mannequins hors présentoirs vendus aussitôt, renaissance dès que possible après les achats moins chers.
-- Partagé par tools/progression.luau (tableaux) et tests/specs/Progression.spec.luau (règle du « pas de mur »).
local ProgressionSim = {}

ProgressionSim.THROW_TIME = 15 -- lancer, vol, tirage et retour (s ; 15 s mesurés sur Throw a Seed)
ProgressionSim.TRAIN_TIME = 15 -- entraînement entre deux lancers (s)
-- Distance (m) : premier contact au sol prévu par Shared.FlightArc (main à ORIGIN_HEIGHT au-dessus de la piste) avec
-- le comportement du mannequin lancé (poussée, descente lente, rebonds : #130), plus SLIDE_SHARE de la glissade freinée
-- théorique (0,3 à 0,75 mesuré par #113 : obstacles et rebonds au point de chute)
ProgressionSim.ORIGIN_HEIGHT = 5.3
ProgressionSim.SLIDE_SHARE = 0.4
-- Bonus des os et objets (part ajoutée à la CHANCE) : ≈ +30 % au départ, ≈ +55 % à 10,5 K de puissance (mesures #14)
ProgressionSim.BONUS_BASE = 0.3
ProgressionSim.BONUS_PER_LOG = 0.035
-- Relevés de l'état du joueur (s) : 2, 5, 10, 30, 60 min, 3, 8, 14 h
ProgressionSim.SNAPSHOTS = { 120, 300, 600, 1800, 3600, 3 * 3600, 8 * 3600, 14 * 3600 }
-- Attente en dessous de laquelle un « prix suivant / revenu » ne compte pas comme un mur (s) : deux achats coup sur
-- coup donnent un ratio minuscule, puis normal, sans que le joueur sente une marche
ProgressionSim.RATIO_FLOOR = 60
-- Bouton « 2x TRAINING! » (#119, Shared.TrainingBoost) : part des apparitions cliquées à temps (clic compté dès
-- l'apparition ; le bonus s'arrête avec la séance de TRAIN_TIME s). 0 : joueur sans le bonus (comparaison)
ProgressionSim.BOOST_SUCCESS = 0.7

export type Purchase = {
	t: number, -- instant de l'achat (s)
	kind: string, -- "gear", "throw", "display", "rebirth"
	index: number, -- palier atteint (équipement, mannequin à lancer, présentoirs, renaissances)
	cost: number,
	income: number, -- revenu ($/s) au moment de l'achat
	nextCost: number?, -- prix du prochain achat (le moins cher restant, sinon la renaissance)
}

export type Snapshot = { purchases: number, income: number, power: number, rarity: number, rebirths: number }

export type Run = {
	marks: { [string]: number }, -- instant (s) de chaque palier, par clé (« gear:3 », « rarity:5 », « power:1M »…)
	purchases: { Purchase },
	snapshots: { Snapshot }, -- un par instant de SNAPSHOTS atteint
	minutes: { number }, -- « prix suivant / revenu » (s) à chaque minute de jeu (math.huge sans revenu)
	final: { chance: number, rebirths: number, income: number, power: number },
}

-- Cette méthode permet de charger les modules du jeu utilisés par la simulation lorsque l'outil ou le test démarre
-- (`loader` : tests/lib/Loader).
function ProgressionSim.modules(loader: any): { [string]: any }
	local modules = {}
	for _, name in
		{
			"Collection",
			"Economy",
			"FlightArc",
			"Format",
			"GameConfig",
			"Inventory",
			"Rarity",
			"Rebirth",
			"ThrowDummies",
			"Training",
			"TrainingBoost",
		}
	do
		modules[name] = loader:require("src/shared/" .. name)
	end
	return modules
end

-- Cette méthode permet d'estimer la distance d'un lancer jauge pleine lorsque le joueur a `power` de Throw Power et
-- lance le mannequin `thrown` (Shared.ThrowDummies ; le Crash Dummy, sans comportement, par défaut).
function ProgressionSim.distanceFor(m: { [string]: any }, power: number, thrown: any?): number
	local speed = m.Economy.launchSpeed(power)
	local pitch = math.rad(m.GameConfig.LAUNCH_PITCH_DEG)
	local forward = speed * math.cos(pitch)
	local plan = m.FlightArc.plan(
		forward,
		speed * math.sin(pitch),
		ProgressionSim.ORIGIN_HEIGHT,
		m.GameConfig.GRAVITY,
		thrown or m.ThrowDummies.get(1)
	)
	local slide = ProgressionSim.SLIDE_SHARE * m.FlightArc.slide(plan.landingSpeed)
	return math.min(plan.reach + slide, m.GameConfig.COURSE_LENGTH)
end

-- Cette méthode permet d'estimer la CHANCE d'un lancer lorsque le joueur a `power` et lance le mannequin `thrown`
-- (chance et comportement ; renaissances non comprises).
function ProgressionSim.chanceFor(m: { [string]: any }, power: number, thrown: any): number
	local bonus = ProgressionSim.BONUS_BASE + ProgressionSim.BONUS_PER_LOG * math.log(math.max(power, 10) / 10)
	return m.Economy.zoneChance(ProgressionSim.distanceFor(m, power, thrown)) * (1 + bonus) * thrown.luck
end

-- Cette méthode permet de simuler un joueur (graine `seed`) pendant `seconds` s lorsque l'on estime la courbe de
-- progression ; `stopAtRebirth` arrête la partie à la première renaissance (règle du « pas de mur » des tests).
function ProgressionSim.simulate(m: { [string]: any }, seed: number, seconds: number, stopAtRebirth: boolean?): Run
	local Collection, GameConfig, Training = m.Collection, m.GameConfig, m.Training
	local ThrowDummies, Inventory, Rebirth = m.ThrowDummies, m.Inventory, m.Rebirth
	math.randomseed(seed)
	-- Cette méthode permet de tirer un nombre dans [0, 1) lorsque le tirage du mannequin en demande un.
	local roll = function()
		return math.random()
	end
	-- Hasard du bonus à part (Park-Miller, exact en double) : les tirages de mannequins restent ceux d'avant #119
	local boostSeed = (seed * 7919) % 2147483646 + 1
	-- Cette méthode permet de tirer un nombre dans [0, 1) lorsque le calendrier du bonus ou le clic du joueur en
	-- demandent un.
	local function boostRoll(): number
		boostSeed = (boostSeed * 16807) % 2147483647
		return (boostSeed - 1) / 2147483646
	end
	local boost = m.TrainingBoost.new(boostRoll)
	local t = 0
	local money = 0
	local power = GameConfig.START_POWER
	local progress = { level = 1, exp = 0 }
	local gear, thrown = 1, 1
	local displays = GameConfig.DISPLAY_START
	local base: { number } = {} -- revenus des mannequins posés
	local draws = 0
	local rebirths = 0
	local bestRarity = 0
	local marks: { [string]: number } = {}
	local purchases: { Purchase } = {}
	local snapshots: { Snapshot } = {}
	local minutes: { number } = {}
	local stopped = false

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
		table.insert(base, Collection.income(entry))
		table.sort(base, function(a, b)
			return a > b
		end)
		while #base > displays do
			money += (table.remove(base) :: number) * GameConfig.SELL_MINUTES * 60
		end
	end
	-- Cette méthode permet de lister les achats possibles ensuite (équipement, mannequin à lancer, présentoir), le
	-- moins cher d'abord, lorsque le joueur fait ses courses ou que l'on mesure le prochain mur.
	local function options(): { { kind: string, cost: number } }
		local list = {}
		local nextGear = Training.nextGearCost(gear)
		if nextGear then
			table.insert(list, { kind = "gear", cost = nextGear })
		end
		local nextThrow = ThrowDummies.nextCost(thrown)
		if nextThrow then
			table.insert(list, { kind = "throw", cost = nextThrow })
		end
		local nextDisplay = Inventory.displayPrice(displays)
		if nextDisplay then
			table.insert(list, { kind = "display", cost = nextDisplay })
		end
		table.sort(list, function(a, b)
			return a.cost < b.cost
		end)
		return list
	end
	-- Cette méthode permet de donner le prix du prochain achat (le moins cher restant, sinon la renaissance) lorsque
	-- l'on mesure le ratio « prix suivant / revenu ».
	local function nextCost(): number
		local list = options()
		return if list[1] then list[1].cost else Rebirth.price(rebirths)
	end
	-- Cette méthode permet de noter un achat (instant, prix, revenu, prix du suivant) lorsque le joueur vient de payer.
	local function record(kind: string, index: number, cost: number)
		table.insert(purchases, {
			t = t,
			kind = kind,
			index = index,
			cost = cost,
			income = income(),
			nextCost = nextCost(),
		})
	end
	-- Cette méthode permet d'acheter tout ce qui est abordable, le moins cher d'abord, lorsque l'argent change.
	local function shop()
		while true do
			local pick = options()[1]
			if not pick or pick.cost > money then
				return
			end
			money -= pick.cost
			if pick.kind == "gear" then
				gear += 1
				mark("gear:" .. gear)
				record("gear", gear, pick.cost)
			elseif pick.kind == "throw" then
				thrown += 1
				mark("throw:" .. thrown)
				record("throw", thrown, pick.cost)
			else
				displays += 1
				mark("display:" .. displays)
				record("display", displays, pick.cost)
			end
		end
	end
	-- Cette méthode permet de renaître dès que la condition est remplie (Shared.Rebirth), après les achats moins chers,
	-- lorsque l'argent change : argent, puissance, entraînement, équipement et mannequins à lancer à zéro.
	local function rebirth()
		if Rebirth.missing({ gearTier = gear, money = money, rebirths = rebirths }) then
			return
		end
		local price = Rebirth.price(rebirths)
		rebirths += 1
		mark("rebirth:" .. rebirths)
		money, power = 0, GameConfig.START_POWER
		progress = { level = 1, exp = 0 }
		gear, thrown = 1, 1
		record("rebirth", rebirths, price)
		if stopAtRebirth then
			stopped = true
		end
	end
	-- Cette méthode permet de relever l'état du joueur (relevés fixes, ratio minute par minute) lorsque le temps de jeu
	-- passe un instant de relevé.
	local function sample(from: number)
		for minute = math.floor(from / 60) + 1, math.floor(t / 60) do
			local value = income()
			minutes[minute] = if value > 0 then nextCost() / value else math.huge
		end
		for index, at in ProgressionSim.SNAPSHOTS do
			if from < at and t >= at then
				snapshots[index] = {
					purchases = #purchases,
					income = income(),
					power = power,
					rarity = bestRarity,
					rebirths = rebirths,
				}
			end
		end
	end
	-- Cette méthode permet de faire avancer le temps de jeu de `dt` s (revenu versé) lorsque le joueur lance ou s'entraîne.
	local function advance(dt: number)
		local from = t
		t += dt
		money += income() * dt
		sample(from)
	end

	while t < seconds and not stopped do
		-- Lancer
		local entry
		if draws == 0 then
			entry = { id = Collection.STARTER, size = 1 }
		else
			local chance = ProgressionSim.chanceFor(m, power, ThrowDummies.get(thrown))
			entry = Collection.draw(chance * Rebirth.luck(rebirths), roll)
		end
		draws += 1
		advance(ProgressionSim.THROW_TIME)
		receive(entry)
		local dummy = Collection.get(entry.id)
		bestRarity = math.max(bestRarity, dummy.rarity)
		mark("rarity:" .. dummy.rarity)
		mark("first")
		shop()
		-- Entraînement
		local reps = math.floor(ProgressionSim.TRAIN_TIME / GameConfig.REP_TIME)
		for _ = 1, reps do
			-- Bouton « 2x TRAINING! » : cliqué à temps par BOOST_SUCCESS des joueurs, bonus coupé en fin de séance
			if
				m.TrainingBoost.advance(boost, GameConfig.REP_TIME, boostRoll) == "Offer"
				and boostRoll() < ProgressionSim.BOOST_SUCCESS
			then
				m.TrainingBoost.claim(boost, boost.lastId)
			end
			local gained
			progress, gained = Training.completeRep(progress, gear, m.TrainingBoost.multiplier(boost))
			power += gained
		end
		m.TrainingBoost.stop(boost, boostRoll)
		advance(ProgressionSim.TRAIN_TIME)
		for _, threshold in { 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10 } do
			if power >= threshold then
				mark("power:" .. m.Format.short(threshold))
			end
		end
		-- Repères de la piste prolongée (#97) : fin de la Moon Base, Neon City, Haunted Castle, bout de piste
		local distance = ProgressionSim.distanceFor(m, power, ThrowDummies.get(thrown))
		for _, meters in { 2400, 3600, 4800 } do
			if distance >= meters then
				mark(string.format("track:%.1fkm", meters / 1000))
			end
		end
		if distance >= GameConfig.COURSE_LENGTH then
			mark("trackEnd")
		end
		for _, threshold in { 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9 } do
			if income() >= threshold then
				mark("income:" .. m.Format.short(threshold))
			end
		end
		shop()
		rebirth()
	end
	return {
		marks = marks,
		purchases = purchases,
		snapshots = snapshots,
		minutes = minutes,
		final = {
			chance = ProgressionSim.chanceFor(m, power, ThrowDummies.get(thrown)) * Rebirth.luck(rebirths),
			rebirths = rebirths,
			income = income(),
			power = power,
		},
	}
end

-- Cette méthode permet de donner la médiane d'une liste de valeurs (math.huge pour une valeur manquante, nil si la
-- moitié manque) lorsque l'on résume plusieurs joueurs.
function ProgressionSim.median(values: { number }): number?
	local sorted = table.clone(values)
	table.sort(sorted)
	local value = sorted[math.floor((#sorted + 1) / 2)]
	return if value == nil or value == math.huge then nil else value
end

export type Step = {
	kind: string,
	index: number,
	cost: number,
	t: number, -- instant médian de l'achat (s)
	ratio: number, -- « prix suivant / revenu » médian juste après l'achat (s d'attente au revenu du moment)
	jump: number, -- ratio de cet achat / ratio de l'achat précédent (planchers à RATIO_FLOOR)
}

-- Cette méthode permet de résumer les joueurs simulés achat par achat jusqu'à la première renaissance (instant et
-- ratio médians, saut du ratio) lorsque l'on cherche un mur ; l'ordre « le moins cher d'abord » est le même pour tous.
function ProgressionSim.steps(runs: { Run }): { Step }
	local result: { Step } = {}
	local count = 0
	for _, run in runs do
		local firstRebirth = #run.purchases
		for i, purchase in run.purchases do
			if purchase.kind == "rebirth" then
				firstRebirth = i
				break
			end
		end
		count = math.max(count, firstRebirth)
	end
	local previous = ProgressionSim.RATIO_FLOOR
	for k = 1, count do
		local times, ratios = {}, {}
		local sample: Purchase? = nil
		for _, run in runs do
			local purchase = run.purchases[k]
			if purchase and (k == 1 or run.purchases[k - 1].kind ~= "rebirth") then
				sample = sample or purchase
				table.insert(times, purchase.t)
				table.insert(ratios, (purchase.nextCost or 0) / math.max(purchase.income, 1e-9))
			else
				table.insert(times, math.huge)
				table.insert(ratios, math.huge)
			end
		end
		local t, ratio = ProgressionSim.median(times), ProgressionSim.median(ratios)
		-- La renaissance clôt la courbe : son « prix suivant » est le premier achat d'une partie remise à zéro
		if not (sample and t and ratio) or sample.kind == "rebirth" then
			break
		end
		local floored = math.max(ratio, ProgressionSim.RATIO_FLOOR)
		table.insert(result, {
			kind = sample.kind,
			index = sample.index,
			cost = sample.cost,
			t = t,
			ratio = ratio,
			jump = floored / previous,
		})
		previous = floored
	end
	return result
end

return ProgressionSim
