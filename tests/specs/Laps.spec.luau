-- Tours de piste (#224) : distance au-delà du bout de la piste (échelle propre, continue), tour en cours, relance au
-- portail (point de chute posé à la distance restante, comportements compris), durée du vol bornée.
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local FlightArc = loader:require("src/shared/FlightArc")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Laps = loader:require("src/shared/Laps")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")

	local G = GameConfig.GRAVITY
	local L = Laps.LENGTH
	local PITCH = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local ORIGIN_HEIGHT = 5.3 -- main de l'avatar au lâcher (tools/ProgressionSim)
	local BEHAVIORS = { "Classic", "Bouncy", "Glides", "Jetpack" }

	-- Cette méthode permet de donner le premier mannequin dessiné du comportement `name` lorsque l'on vérifie ses tours.
	local function dummyOf(name: string): any
		for _, dummy in ThrowDummies.LIST do
			if dummy.behavior == name then
				return dummy
			end
		end
		error("mannequin introuvable : " .. name)
	end

	-- Cette méthode permet de donner le plan du lâcher (jauge pleine) à `power` lorsque l'on vérifie un lancer.
	local function launchPlan(power: number, dummy: any): any
		local speed = Economy.launchSpeed(power)
		return FlightArc.plan(speed * math.cos(PITCH), speed * math.sin(PITCH), ORIGIN_HEIGHT, G, dummy)
	end

	-- Cette méthode permet de donner la distance totale prévue (tours compris) d'un lancer à `power` lorsque l'on
	-- vérifie l'échelle d'après le portail.
	local function totalAt(power: number, dummy: any): number
		return Laps.total(Laps.virtual(launchPlan(power, dummy)))
	end

	-- Cette méthode permet de donner la puissance qui pose la distance totale `target` lorsque l'on compare des tours.
	local function powerFor(target: number, dummy: any): number
		local low, high = 1, 1e30
		for _ = 1, 200 do
			local mid = math.sqrt(low * high)
			if totalAt(mid, dummy) < target then
				low = mid
			else
				high = mid
			end
		end
		return low
	end

	T.describe("Laps.total", function()
		T.it("ne change rien en deçà du bout de la piste", function()
			for _, reach in { 0, 145, 2400, 5999 } do
				T.expectNear(Laps.total(reach), reach, 1e-9)
			end
			T.expectNear(Laps.total(-5), 0)
		end)
		T.it(
			"continue au bout, puis un tour de plus chaque fois que la portée virtuelle est multipliée par RATIO",
			function()
				T.expectNear(Laps.total(L), L, 1e-9)
				T.expectNear(Laps.total(L * 1.00001), L, 1)
				T.expectNear(Laps.total(L * Laps.RATIO), 2 * L, 1e-6)
				T.expectNear(Laps.total(L * Laps.RATIO ^ 1.5), 2.5 * L, 1e-6)
				T.expectNear(Laps.total(L * 1e9), Laps.MAX * L, 1e-6)
			end
		)
		T.it("un tour de plus vaut ≈ POWER_PER_LAP de puissance, pour chaque comportement", function()
			for _, name in BEHAVIORS do
				local dummy = if name == "Classic" then nil else dummyOf(name)
				local factor = powerFor(2 * L, dummy) / powerFor(L, dummy)
				print(string.format("[mesure] %s : un tour de plus pour × %.2f de puissance", name, factor))
				T.expect(
					factor > Laps.POWER_PER_LAP * 0.7 and factor < Laps.POWER_PER_LAP * 1.4,
					string.format("%s : × %.2f", name, factor)
				)
			end
		end)
	end)

	T.describe("Laps.finishNeeded (#231 : portail ouvert seulement pour un passage)", function()
		T.it("s'ouvre juste avant la ligne, reste ouvert le temps du passage, puis se referme", function()
			local speed = 1000 -- studs/s : ouvert à 600 studs de la ligne
			T.expect(not Laps.finishNeeded(0, speed, 1), "au repos, au départ")
			T.expect(not Laps.finishNeeded(L - 700, speed, 1), "encore loin")
			T.expect(Laps.finishNeeded(L - 500, speed, 1), "arrive")
			T.expect(Laps.finishNeeded(L + 20, speed, 1), "en train de passer")
			T.expect(not Laps.finishNeeded(L + Laps.PAST_LINE + 1, speed, 1), "passé")
		end)
		T.it("reste fermé au dernier tour (paroi du bout) et pour un mannequin arrêté", function()
			T.expect(not Laps.finishNeeded(L - 10, 1000, Laps.MAX), "dernier tour")
			T.expect(not Laps.finishNeeded(L - 0.1, 0, 1), "arrêté")
			T.expect(not Laps.finishNeeded(L - 10, -50, 1), "rebondit en arrière")
		end)
	end)

	T.describe("Laps.lapOf et Laps.within", function()
		T.it("donnent le tour en cours et la distance dans ce tour", function()
			T.expectEqual(Laps.lapOf(0), 1)
			T.expectEqual(Laps.lapOf(L - 1), 1)
			T.expectEqual(Laps.lapOf(L), 2)
			T.expectEqual(Laps.lapOf(2.5 * L), 3)
			T.expectEqual(Laps.lapOf(1e12), Laps.MAX)
			T.expectNear(Laps.within(L + 120), 120, 1e-9)
			T.expectNear(Laps.within(300), 300, 1e-9)
		end)
		T.it("donnent la CHANCE des zones au-delà du bout (× CHANCE_PER_LAP par tour)", function()
			T.expectNear(Laps.chanceFactor(L), 1, 1e-9)
			T.expectNear(Laps.chanceFactor(2 * L), Laps.CHANCE_PER_LAP, 1e-9)
			T.expectNear(Laps.chanceFactor(100), 1, 1e-9)
		end)
	end)

	T.describe("Laps.relaunch", function()
		T.it("pose la portée virtuelle du tour à la distance restante, comportement compris", function()
			for _, name in BEHAVIORS do
				local dummy = if name == "Classic" then nil else dummyOf(name)
				for _, run in { 300, 2500, 5800, 9000 } do
					local forward, up, plan = Laps.relaunch(run, dummy, G)
					T.expectNear(Laps.virtual(plan), run, 1, string.format("%s, %d studs", name, run))
					T.expectNear(math.deg(math.atan2(up, forward)), Laps.PITCH_DEG, 1e-6)
				end
			end
		end)
		T.it("relance au moins de MIN_RUN un mannequin passé sans réserve", function()
			local _, _, plan = Laps.relaunch(-200, nil, G)
			T.expectNear(Laps.virtual(plan), Laps.MIN_RUN, 1)
		end)
		T.it(
			"tient le vol sous 25 s jusqu'à 2 tours de plus (#224 : bout de piste, puis tours plus courts)",
			function()
				for _, name in BEHAVIORS do
					local dummy = if name == "Classic" then nil else dummyOf(name)
					local power = powerFor(3 * L, dummy)
					local first = launchPlan(power, dummy)
					local total = Laps.total(Laps.virtual(first))
					-- Premier tour jusqu'au portail, puis un plan par tour jusqu'à l'arrêt
					local time = Laps.duration(first, false)
					local offset = L
					while true do
						local run = total - offset - Laps.EXIT_Z
						local _, _, plan = Laps.relaunch(run, dummy, G)
						local last = Laps.EXIT_Z + Laps.virtual(plan) < L
						time += Laps.duration(plan, last)
						if last then
							break
						end
						offset += L
					end
					print(
						string.format(
							"[mesure] %s à 3 tours (puissance %.3g) : vol de %.1f s (sol plat)",
							name,
							power,
							time
						)
					)
					T.expect(time <= 25, string.format("%s : %.1f s", name, time))
				end
			end
		)
	end)
end
