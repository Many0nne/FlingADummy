-- Jauge : onde triangle, facteur de vitesse (pas de zone PERFECT).
return function(T, Loader)
	local loader = Loader.new()
	local Gauge = loader:require("src/shared/Gauge")
	local GameConfig = loader:require("src/shared/GameConfig")
	local P = GameConfig.GAUGE_PERIOD

	T.describe("Gauge.value", function()
		T.it("part de 0, atteint 1 à mi-période et revient à 0", function()
			T.expectNear(Gauge.value(0), 0)
			T.expectNear(Gauge.value(P / 4), 0.5)
			T.expectNear(Gauge.value(P / 2), 1)
			T.expectNear(Gauge.value(3 * P / 4), 0.5)
			T.expectNear(Gauge.value(P), 0)
		end)
		T.it("est périodique", function()
			T.expectNear(Gauge.value(2 * P + P / 4), 0.5, 1e-6)
		end)
	end)

	T.describe("Gauge.launchFactor", function()
		T.it("va de GAUGE_MIN_FACTOR à 1, borné", function()
			T.expectNear(Gauge.launchFactor(0), GameConfig.GAUGE_MIN_FACTOR)
			T.expectNear(Gauge.launchFactor(1), 1)
			T.expectNear(Gauge.launchFactor(2), 1)
			T.expectNear(Gauge.launchFactor(-1), GameConfig.GAUGE_MIN_FACTOR)
		end)
	end)

	T.describe("Gauge.range", function()
		T.it("donne les extrêmes de l'aiguille sur un intervalle, sommets compris", function()
			local low, high = Gauge.range(0.1 * P, 0.2 * P)
			T.expectNear(low, 0.2)
			T.expectNear(high, 0.4)
			low, high = Gauge.range(0.4 * P, 0.6 * P)
			T.expectNear(low, 0.8)
			T.expectNear(high, 1)
			low, high = Gauge.range(0.9 * P, 1.1 * P)
			T.expectNear(low, 0)
			T.expectNear(high, 0.2)
			low, high = Gauge.range(0, 2 * P)
			T.expectEqual(low, 0)
			T.expectEqual(high, 1)
		end)
	end)

	T.describe("Gauge.verify", function()
		local release = GameConfig.THROW_RELEASE_TIME

		-- Cette méthode permet de simuler un client honnête qui clique `click` s après avoir vu la jauge, avec une
		-- latence aller-retour `rtt` et un lâcher en retard de `late`, lorsqu'un test vérifie la réception du lancer.
		local function honest(click: number, rtt: number, late: number): (number, number)
			return Gauge.value(click), click + release + late + rtt
		end

		T.it("accepte la valeur juste d'un client sans latence", function()
			for _, click in { 0.1, 0.35, P / 2, 0.9, 1.7, 2.45 } do
				local claimed, elapsed = honest(click, 0, 0)
				local value, accepted = Gauge.verify(claimed, elapsed, 0)
				T.expect(accepted, "clic à " .. click .. " s accepté")
				T.expectNear(value, claimed)
			end
		end)

		T.it("accepte la valeur juste malgré la latence, sa gigue et un lâcher en retard", function()
			for _, case in { { 0.3, 0.1, 0.03, 0.12 }, { 0.8, 0.25, 0.2, 0.3 }, { 1.4, 0.15, 0.05, 0.05 } } do
				local click, rtt, late, measured = case[1], case[2], case[3], case[4]
				local claimed, elapsed = honest(click, rtt, late)
				local value, accepted = Gauge.verify(claimed, elapsed, measured)
				T.expect(accepted, string.format("clic %.2f s, latence %.2f (mesurée %.2f)", click, rtt, measured))
				T.expectNear(value, claimed)
			end
		end)

		T.it("remplace une valeur trichée (max envoyé loin du sommet) par celle du serveur", function()
			-- Clic réel au creux de l'aiguille, le client prétend avoir atteint le haut
			local click = P
			local _, elapsed = honest(click, 0.1, 0)
			local value, accepted = Gauge.verify(1, elapsed, 0.1)
			T.expect(not accepted, "max refusé")
			T.expectNear(value, Gauge.value(click), 1e-6)
			T.expect(value < 0.2, "valeur du serveur basse, obtenu " .. value)
		end)

		T.it("borne la latence prise en compte à GAUGE_MAX_LAG", function()
			-- Latence mesurée de 5 s : le serveur estime le clic avec GAUGE_MAX_LAG, pas avec 5 s (clic estimé au creux
			-- de l'aiguille, loin du sommet quelle que soit la période)
			local elapsed = release + P + GameConfig.GAUGE_MAX_LAG
			local value, accepted = Gauge.verify(1, elapsed, 5)
			T.expect(not accepted, "max refusé hors fenêtre")
			T.expectNear(value, Gauge.value(P), 1e-6)
		end)

		T.it("borne la valeur reçue entre 0 et 1", function()
			local value = Gauge.verify(7, release + P / 2, 0)
			T.expect(value >= 0 and value <= 1, "valeur dans [0, 1]")
		end)
	end)

	T.describe("Gauge.verify avec GaugeStop", function()
		local release = GameConfig.THROW_RELEASE_TIME
		local tolerance = GameConfig.GAUGE_LAG_TOLERANCE

		-- Cette méthode permet de donner l'arrivée du GaugeStop et du Launch d'un client honnête qui clique `click` s après
		-- l'ouverture, avec une latence aller-retour `rtt` et un lâcher en retard de `late`, lorsqu'un test les simule.
		local function arrivals(click: number, rtt: number, late: number): (number, number)
			-- La jauge du client apparaît rtt/2 après l'ouverture serveur : les deux arrivées sont décalées de rtt entiers
			return click + rtt, click + release + late + rtt
		end

		T.it("accepte la valeur juste, avec latence et gigue de la mesure", function()
			for _, case in { { 0.3, 0.1, 0.03, 0.12 }, { 0.8, 0.25, 0.2, 0.3 }, { 1.4, 0.15, 0.05, 0.05 } } do
				local click, rtt, late, measured = case[1], case[2], case[3], case[4]
				local stopAt, elapsed = arrivals(click, rtt, late)
				local value, accepted = Gauge.verify(Gauge.value(click), elapsed, measured, stopAt)
				T.expect(accepted, string.format("clic %.2f s, latence %.2f (mesurée %.2f)", click, rtt, measured))
				T.expectNear(value, Gauge.value(click))
			end
		end)

		T.it("refuse un 1 envoyé hors de la fenêtre de latence, même avec un lâcher en retard", function()
			-- Clic à 0,35 s (aiguille à 0,58), lâcher en retard : sans GaugeStop le sommet (0,6 s) est atteignable
			local stopAt, elapsed = arrivals(0.35, 0.1, 0.25)
			local value, accepted = Gauge.verify(1, elapsed, 0.1, stopAt)
			T.expect(not accepted, "max refusé")
			T.expectNear(value, Gauge.value(0.35), 1e-6)
			local _, acceptedOld = Gauge.verify(1, elapsed, 0.1)
			T.expect(acceptedOld, "le repli #29 l'acceptait")
		end)

		T.it("se replie sur #29 sans GaugeStop", function()
			local _, elapsed = arrivals(0.3, 0.1, 0.2)
			local value, accepted = Gauge.verify(Gauge.value(0.3), elapsed, 0.1, nil)
			T.expect(accepted, "valeur juste acceptée sans GaugeStop")
			T.expectNear(value, Gauge.value(0.3))
		end)

		T.it("se replie sur #29 si le GaugeStop est arrivé avant l'ouverture de la jauge", function()
			local _, elapsed = arrivals(0.35, 0.1, 0.25)
			local value, accepted = Gauge.verify(Gauge.value(0.35), elapsed, 0.1, -0.5)
			T.expect(accepted, "valeur juste acceptée")
			T.expectNear(value, Gauge.value(0.35))
			local _, cheat = Gauge.verify(1, elapsed, 0.1, -0.5)
			T.expect(cheat, "même fenêtre qu'avant (#29), pas de fenêtre plus large")
		end)

		T.it("le premier GaugeStop fait foi : un doublon tardif ne rend pas atteignable le sommet", function()
			-- Le serveur ne note que la première arrivée (LaunchService.gaugeStop) ; la fenêtre reste autour d'elle
			local stopAt, elapsed = arrivals(0.3, 0.1, 0)
			local _, accepted = Gauge.verify(1, elapsed, 0.1, stopAt)
			T.expect(not accepted, "1 refusé : le sommet est hors de " .. tolerance .. " s du clic")
		end)

		T.describe("triche « toujours 1 »", function()
			-- Cette méthode permet de donner la proportion de lancers où un client envoyant toujours 1 obtient le max,
			-- pour des clics répartis sur la période, une latence `rtt` et un lâcher en retard de 0 à 0,25 s.
			local function cheatRate(useStop: boolean): number
				local rtt, wins, total = 0.1, 0, 0
				for i = 0, 239 do
					local click = (i + 0.5) / 240 * P
					for _, late in { 0, 0.0625, 0.125, 0.1875, 0.25 } do
						local stopAt, elapsed = arrivals(click, rtt, late)
						local value = Gauge.verify(1, elapsed, rtt, if useStop then stopAt else nil)
						total += 1
						if value > 0.999 then
							wins += 1
						end
					end
				end
				return wins / total
			end

			T.it("est nettement réduite par le GaugeStop", function()
				local before, after = cheatRate(false), cheatRate(true)
				print(
					string.format(
						"[mesure] « toujours 1 » obtient le max : avant %.1f %%, après %.1f %%",
						before * 100,
						after * 100
					)
				)
				T.expect(after < before / 1.5, string.format("avant %.3f, après %.3f", before, after))
			end)
		end)
	end)

	T.describe("pas de PERFECT", function()
		T.it("ni fonction ni constante : le haut de la jauge est le max, sans bonus", function()
			T.expectEqual((Gauge :: any).isPerfect, nil)
			T.expectEqual((GameConfig :: any).PERFECT_THRESHOLD, nil)
			T.expectEqual((GameConfig :: any).PERFECT_BONUS, nil)
		end)
	end)
end
