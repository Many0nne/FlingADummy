-- Bouton « 2x TRAINING! » (#119) : calendrier des apparitions, fenêtre de clic, refus d'un clic tardif ou en double,
-- multiplicateur d'EXP et effet sur la Throw Power d'une séance.
return function(T, Loader)
	local loader = Loader.new()
	local TrainingBoost = loader:require("src/shared/TrainingBoost")
	local Training = loader:require("src/shared/Training")
	local GameConfig = loader:require("src/shared/GameConfig")

	local OFFER = GameConfig.BOOST_OFFER_TIME
	local SLACK = GameConfig.BOOST_CLICK_SLACK
	local DT = 1 / 60

	-- Cette méthode permet de donner un hasard fixe (toujours `value`) lorsqu'un test veut un calendrier prévisible.
	local function fixed(value: number): () -> number
		return function()
			return value
		end
	end

	-- Cette méthode permet de faire avancer l'horloge jusqu'au prochain événement (au plus `limit` s) lorsqu'un test
	-- attend une apparition, un raté ou la fin du bonus ; renvoie l'événement (nil si rien).
	local function runUntilEvent(state, rng, limit: number): string?
		local start = state.clock
		while state.clock - start < limit do
			local event = TrainingBoost.advance(state, DT, rng)
			if event then
				return event
			end
		end
		return nil
	end

	T.describe("TrainingBoost : calendrier des apparitions", function()
		T.it("intervalle tiré entre BOOST_INTERVAL_MIN et BOOST_INTERVAL_MAX", function()
			T.expectEqual(TrainingBoost.nextDelay(fixed(0)), GameConfig.BOOST_INTERVAL_MIN)
			T.expectNear(TrainingBoost.nextDelay(fixed(0.999999)), GameConfig.BOOST_INTERVAL_MAX, 1e-3)
			for _ = 1, 200 do
				local delay = TrainingBoost.nextDelay(math.random)
				T.expect(
					delay >= GameConfig.BOOST_INTERVAL_MIN and delay <= GameConfig.BOOST_INTERVAL_MAX,
					tostring(delay)
				)
			end
		end)

		T.it("première apparition après un intervalle d'entraînement, numérotée", function()
			local state = TrainingBoost.new(fixed(0))
			T.expectEqual(TrainingBoost.advance(state, GameConfig.BOOST_INTERVAL_MIN - 0.1, fixed(0)), nil)
			T.expectEqual(TrainingBoost.advance(state, 0.1, fixed(0)), "Offer")
			T.expectEqual(state.lastId, 1)
			T.expect(state.offer ~= nil and state.offer.id == 1, "apparition 1 en cours")
		end)

		T.it("raté : l'apparition expire après l'affichage et la marge, puis le calendrier repart", function()
			local state = TrainingBoost.new(fixed(0))
			T.expectEqual(runUntilEvent(state, fixed(0), 60), "Offer")
			local shownAt = state.clock
			T.expectEqual(runUntilEvent(state, fixed(0), 60), "Missed")
			T.expectNear(state.clock - shownAt, OFFER + SLACK, 2 * DT)
			T.expectEqual(state.offer, nil)
			local missedAt = state.clock
			T.expectEqual(runUntilEvent(state, fixed(0), 60), "Offer")
			T.expectNear(state.clock - missedAt, GameConfig.BOOST_INTERVAL_MIN, 2 * DT)
			T.expectEqual(state.lastId, 2)
		end)

		T.it("pas d'apparition pendant un bonus actif ; la suivante vient un intervalle après sa fin", function()
			local state = TrainingBoost.new(fixed(0))
			runUntilEvent(state, fixed(0), 60)
			T.expect((TrainingBoost.claim(state, 1)), "clic accepté")
			local startedAt = state.clock
			T.expectEqual(runUntilEvent(state, fixed(0), 120), "Ended")
			T.expectNear(state.clock - startedAt, GameConfig.BOOST_TIME, 2 * DT)
			local endedAt = state.clock
			T.expectEqual(runUntilEvent(state, fixed(0), 120), "Offer")
			T.expectNear(state.clock - endedAt, GameConfig.BOOST_INTERVAL_MIN, 2 * DT)
		end)

		T.it("arrêter la séance annule l'apparition ou le bonus, sans report", function()
			local state = TrainingBoost.new(fixed(0))
			T.expect(not TrainingBoost.stop(state, fixed(0)), "rien en cours")
			runUntilEvent(state, fixed(0), 60)
			T.expect(TrainingBoost.stop(state, fixed(0)), "apparition annulée")
			local accepted, why = TrainingBoost.claim(state, 1)
			T.expect(not accepted and why == "Cancelled", "clic après l'arrêt de la séance : " .. tostring(why))
			runUntilEvent(state, fixed(0), 60)
			T.expect((TrainingBoost.claim(state, 2)), "bonus démarré")
			T.expect(TrainingBoost.stop(state, fixed(0)), "bonus annulé")
			T.expectEqual(TrainingBoost.multiplier(state), 1)
			T.expectEqual(state.boostEndsAt, nil)
		end)
	end)

	T.describe("TrainingBoost : clic", function()
		T.it("accepté jusqu'à BOOST_OFFER_TIME + BOOST_CLICK_SLACK après l'apparition", function()
			local state = TrainingBoost.new(fixed(0))
			runUntilEvent(state, fixed(0), 60)
			TrainingBoost.advance(state, OFFER + SLACK - 0.05, fixed(0))
			local ok, why = TrainingBoost.claim(state, 1)
			T.expect(ok, "clic dans la marge accepté : " .. tostring(why))
			T.expectEqual(state.claimedId, 1)
		end)

		T.it("tardif refusé (fenêtre close, que l'horloge ait expiré l'apparition ou non)", function()
			-- Horloge passée sans pas d'expiration (clic reçu entre deux images)
			local state = TrainingBoost.new(fixed(0))
			runUntilEvent(state, fixed(0), 60)
			state.clock += OFFER + SLACK + 0.05
			local ok, why = TrainingBoost.claim(state, 1)
			T.expect(not ok and why == "Late", "clic tardif : " .. tostring(why))
			T.expectEqual(TrainingBoost.multiplier(state), 1)
			-- Apparition déjà expirée par l'horloge
			local later = TrainingBoost.new(fixed(0))
			runUntilEvent(later, fixed(0), 60)
			T.expectEqual(runUntilEvent(later, fixed(0), 60), "Missed")
			ok, why = TrainingBoost.claim(later, 1)
			T.expect(not ok and why == "Late", "clic après le raté : " .. tostring(why))
			T.expectEqual(later.boostEndsAt, nil)
		end)

		T.it("en double refusé, numéro inconnu ou invalide refusé, pas de bonus sans apparition", function()
			local state = TrainingBoost.new(fixed(0))
			local ok, why = TrainingBoost.claim(state, 1)
			T.expect(not ok and why == "Unknown", "aucune apparition : " .. tostring(why))
			ok, why = TrainingBoost.claim(state, 0)
			T.expect(not ok and why == "Unknown", "numéro 0 : " .. tostring(why))
			runUntilEvent(state, fixed(0), 60)
			for _, bad in { "1", 1.5, 2, -1, {} } do
				ok = TrainingBoost.claim(state, bad)
				T.expect(not ok, "numéro invalide " .. tostring(bad))
			end
			T.expect((TrainingBoost.claim(state, 1)), "premier clic")
			local endsAt = state.boostEndsAt
			TrainingBoost.advance(state, 5, fixed(0))
			ok, why = TrainingBoost.claim(state, 1)
			T.expect(not ok and why == "Duplicate", "second clic : " .. tostring(why))
			T.expectEqual(state.boostEndsAt, endsAt, "pas de prolongation")
		end)
	end)

	T.describe("TrainingBoost : affichage du bouton par le client", function()
		T.it("caché à la fin de l'affichage en temps serveur, même si l'annonce arrive en retard", function()
			T.expectEqual(TrainingBoost.offerTimeLeft(103, 100), OFFER, "annonce à l'heure")
			T.expectNear(TrainingBoost.offerTimeLeft(103, 100.6), OFFER - 0.6, 1e-9, "annonce en retard de 0,6 s")
			T.expectEqual(TrainingBoost.offerTimeLeft(103, 104), 0, "annonce arrivée après la fin")
			T.expectEqual(TrainingBoost.offerTimeLeft(110, 100), OFFER, "horloge du client en retard : borné")
			T.expectEqual(TrainingBoost.offerTimeLeft(nil, 100), OFFER, "sans échéance : durée complète")
		end)

		T.it(
			"un clic envoyé avant la fin de l'affichage arrive dans la fenêtre du serveur (latence ≤ marge)",
			function()
				-- Le serveur annonce à shownAt, le client cache le bouton à shownAt + OFFER (temps serveur) : un clic au
				-- dernier moment arrive au plus une demi-latence plus tard
				local state = TrainingBoost.new(fixed(0))
				runUntilEvent(state, fixed(0), 60)
				TrainingBoost.advance(state, OFFER + SLACK * 0.9, fixed(0))
				T.expect((TrainingBoost.claim(state, 1)), "clic à la dernière image + 0,45 s de trajet")
			end
		)
	end)

	T.describe("TrainingBoost : multiplicateur", function()
		T.it("× BOOST_MULTIPLIER pendant BOOST_TIME s, 1 avant et après", function()
			local state = TrainingBoost.new(fixed(0))
			T.expectEqual(TrainingBoost.multiplier(state), 1)
			runUntilEvent(state, fixed(0), 60)
			T.expectEqual(TrainingBoost.multiplier(state), 1, "bouton affiché, pas encore cliqué")
			TrainingBoost.claim(state, 1)
			T.expectEqual(TrainingBoost.multiplier(state), GameConfig.BOOST_MULTIPLIER)
			TrainingBoost.advance(state, GameConfig.BOOST_TIME - 0.1, fixed(0))
			T.expectEqual(TrainingBoost.multiplier(state), GameConfig.BOOST_MULTIPLIER)
			TrainingBoost.advance(state, 0.2, fixed(0))
			T.expectEqual(TrainingBoost.multiplier(state), 1)
		end)

		T.it("multiplicateur affiché par le client et temps restant", function()
			-- « +N EXP » et barre : attribut présent = répétition doublée, même juste après la fin vue par l'horloge du
			-- client (le serveur le retire dans l'image où le bonus finit)
			T.expectEqual(TrainingBoost.grantedMultiplier(99), GameConfig.BOOST_MULTIPLIER)
			T.expectEqual(TrainingBoost.grantedMultiplier(nil), 1)
			T.expectEqual(TrainingBoost.grantedMultiplier("x"), 1)
			T.expectEqual(TrainingBoost.remainingText(24), "0:24")
			T.expectEqual(TrainingBoost.remainingText(23.2), "0:24")
			T.expectEqual(TrainingBoost.remainingText(30), "0:30")
			T.expectEqual(TrainingBoost.remainingText(65), "1:05")
			T.expectEqual(TrainingBoost.remainingText(-3), "0:00")
		end)

		T.it("une séance de 30 s sous bonus gagne 2 fois la Throw Power d'une séance sans bonus", function()
			-- Cette méthode permet de jouer `seconds` s d'entraînement au palier `tier` (répétitions de REP_TIME s,
			-- EXP × `multiplier`) lorsque l'on compare les gains ; renvoie la Throw Power versée et l'EXP gagnée.
			local function session(tier: number, seconds: number, multiplier: number): (number, number)
				local progress = { level = 20, exp = 0 }
				local power = 0
				local exp = 0
				for _ = 1, math.floor(seconds / GameConfig.REP_TIME) do
					local before = progress
					local gained
					progress, gained = Training.completeRep(progress, tier, multiplier)
					power += gained
					exp += Training.gear(tier).gain * multiplier
					T.expect(progress.level >= before.level, "niveau jamais en baisse")
				end
				return power, exp
			end
			for _, tier in { 1, 3, 7, #Training.GEARS } do
				local plainPower, plainExp = session(tier, GameConfig.BOOST_TIME, 1)
				local boostedPower, boostedExp = session(tier, GameConfig.BOOST_TIME, GameConfig.BOOST_MULTIPLIER)
				T.expectEqual(boostedExp, plainExp * GameConfig.BOOST_MULTIPLIER, "EXP du palier " .. tier)
				-- Niveaux plafonnés à LEVEL_MAX_REPS répétitions : la puissance suit l'EXP à un niveau près
				local cap = GameConfig.LEVEL_MAX_REPS * Training.gear(tier).gain
				T.expect(
					math.abs(boostedPower - plainPower * GameConfig.BOOST_MULTIPLIER) <= 2 * cap,
					string.format("palier %d : %d contre 2 × %d", tier, boostedPower, plainPower)
				)
			end
		end)
	end)
end
