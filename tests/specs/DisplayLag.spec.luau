-- Retard d'affichage des mannequins (#84) : heure serveur de la position affichée, retard lissé et borné, horloge
-- des pièges décalée sans saut.
return function(T, Loader)
	local loader = Loader.new()
	local DisplayLag = loader:require("src/shared/DisplayLag")

	local DT = 1 / DisplayLag.SAMPLE_RATE

	-- Cette méthode permet de donner la position d'un vol type parti à l'heure serveur 10 (avance, monte puis retombe)
	-- à l'heure serveur `t` lorsque l'on fabrique des échantillons.
	local function flight(t: number): Vector3
		local age = t - 10
		return Vector3.new(0.3 * age, 20 + 60 * age - 0.5 * 98 * age * age, 120 * age)
	end

	-- Cette méthode permet de donner la trajectoire échantillonnée d'un vol de `from` à `to` (heures serveur) lorsque
	-- l'on mesure un retard.
	local function sampled(from: number, to: number, path: ((number) -> Vector3)?): any
		local track = DisplayLag.track()
		local t = from
		while t <= to + 1e-9 do
			DisplayLag.push(track, t, (path or flight)(t))
			t += DT
		end
		return track
	end

	T.describe("DisplayLag.shownAt", function()
		T.it("retrouve l'heure serveur d'une position affichée, entre deux échantillons", function()
			local track = sampled(10, 11)
			for _, t in { 10.2, 10.37, 10.61, 10.98 } do
				local shown = DisplayLag.shownAt(track, flight(t))
				T.expect(shown ~= nil, "position sur la trajectoire")
				-- Pas linéaire entre deux échantillons d'un arc : quelques millisecondes d'écart au plus
				T.expectNear(shown :: number, t, 0.005, string.format("à %.2f s", t))
			end
		end)

		T.it("ne mesure rien loin de la trajectoire ni sur un mannequin arrêté", function()
			local track = sampled(10, 11)
			T.expectEqual(DisplayLag.shownAt(track, flight(10.5) + Vector3.new(0, 20, 0)), nil)
			local still = sampled(10, 11, function()
				return Vector3.new(5, 2, 300)
			end)
			T.expectEqual(DisplayLag.shownAt(still, Vector3.new(5, 2, 300)), nil)
			T.expectEqual(DisplayLag.shownAt(DisplayLag.track(), Vector3.zero), nil)
		end)

		T.it("ne fait pas grandir le retard d'un mannequin arrêté après une glissade (Studio : 0,6 s)", function()
			-- Glissade freinée jusqu'à l'arrêt en z = 200 à l'heure 10,6, puis immobile
			local function slide(t: number): Vector3
				local left = math.max(10.6 - t, 0)
				return Vector3.new(0, 2, 200 - 40 * left * left)
			end
			local track = sampled(10, 11.2, slide)
			T.expectEqual(DisplayLag.shownAt(track, slide(11.2)), nil, "arrêté : heure ambiguë")
			T.expectEqual(DisplayLag.shownAt(track, slide(10.6) - Vector3.new(0, 0, 0.5)), nil, "presque arrêté")
			-- Encore en glissade à l'affichage : mesurable
			T.expectNear(DisplayLag.shownAt(track, slide(10.3)) :: number, 10.3, 0.01)
		end)

		T.it("ne prend pas le bout d'un pas rapide pour un mannequin qui ralentit à 3-6 studs/s (revue)", function()
			-- Rapide jusqu'à l'heure 10,5 (z = 100), puis 4 studs/s : pas de 0,2 stud, trop courts pour être mesurés
			local function slowing(t: number): Vector3
				if t <= 10.5 then
					return Vector3.new(0, 2, 100 - 60 * (10.5 - t))
				end
				return Vector3.new(0, 2, 100 + 4 * (t - 10.5))
			end
			local track = sampled(10, 11.5, slowing)
			-- Affiché 0,3 s en retard sur la queue lente : 1,2 stud derrière le dernier échantillon, à 2,8 studs du bout
			-- du dernier pas rapide (dans MATCH) ; avant la revue, l'heure de ce bout (10,5) donnait 0,9 s de retard
			T.expectEqual(DisplayLag.shownAt(track, slowing(11.2), 11.5), nil)
		end)

		T.it("ne cherche l'heure affichée que de now - MAX à now", function()
			-- Trajet qui repasse au même endroit 0,8 s plus tard : seul le passage récent est dans la fenêtre
			local function loop(t: number): Vector3
				local angle = (t - 10) * 2 * math.pi / 0.8
				return Vector3.new(30 * math.cos(angle), 2, 30 * math.sin(angle))
			end
			local track = sampled(10, 11, loop)
			T.expectNear(DisplayLag.shownAt(track, loop(10.9), 11) :: number, 10.9, 0.01)
			-- 0,7 s plus tôt : hors fenêtre (sans `now`, le vieux passage serait pris)
			T.expectEqual(DisplayLag.shownAt(track, loop(10.3), 11), nil)
			T.expectNear(DisplayLag.shownAt(track, loop(10.3)) :: number, 10.3, 0.01)
		end)

		T.it("prolonge le dernier pas quand l'échantillon suivant n'est pas encore arrivé", function()
			local track = sampled(10, 10.5)
			local t = 10.5 + DT / 2
			T.expectNear(DisplayLag.shownAt(track, flight(t)) :: number, t, 0.005)
		end)
	end)

	T.describe("DisplayLag.push", function()
		T.it("ignore un échantillon arrivé dans le désordre et oublie les plus vieux", function()
			local track = sampled(10, 12)
			T.expect(track.times[1] >= 12 - DisplayLag.KEEP - 1e-9, "vieux échantillons oubliés")
			T.expectEqual(#track.times, #track.positions)
			local count = #track.times
			DisplayLag.push(track, 11.9, Vector3.zero)
			T.expectEqual(#track.times, count, "échantillon en retard ignoré")
			for i = 2, #track.times do
				T.expect(track.times[i] > track.times[i - 1], "heures croissantes")
			end
		end)
	end)

	T.describe("DisplayLag.measure", function()
		T.it("mesure l'écart entre l'heure serveur et celle du mannequin affiché, de 0 à MAX", function()
			local track = sampled(10, 11)
			T.expectNear(DisplayLag.measure(track, 11, flight(10.7)) :: number, 0.3, 0.005)
			T.expectEqual(DisplayLag.measure(track, 11, flight(10.1)), nil, "plus vieux que MAX : hors fenêtre")
			T.expectEqual(
				DisplayLag.measure(track, 10.9, flight(10.95)),
				nil,
				"heure affichée dans le futur : hors fenêtre"
			)
		end)
	end)

	T.describe("DisplayLag.wait", function()
		T.it("montre un choc quand le mannequin affiché y arrive, sans attendre plus que MAX", function()
			local clock = DisplayLag.clock()
			DisplayLag.step(clock, 0.3, 1 / 60)
			-- Choc à 100, arrivé 0,1 s plus tard : le mannequin affiché y sera dans 0,2 s
			T.expectNear(DisplayLag.wait(clock, 100, 100.1), 0.2, 1e-9)
			T.expectEqual(DisplayLag.wait(clock, 100, 100.5), 0, "déjà passé : tout de suite")
			T.expectEqual(DisplayLag.wait(clock, 105, 100), DisplayLag.MAX, "heure aberrante : bornée")
		end)
	end)

	T.describe("DisplayLag.step", function()
		T.it("prend telle quelle la première mesure de la session", function()
			local clock = DisplayLag.clock()
			DisplayLag.step(clock, nil, 1 / 60)
			T.expectEqual(clock.lag, 0, "retard nul avant toute mesure")
			T.expectEqual(DisplayLag.step(clock, 0.27, 1 / 60), 0.27)
		end)

		T.it("rejoint le retard mesuré sans changer l'heure des pièges de plus de MAX_RATE par seconde", function()
			local clock = DisplayLag.clock()
			local dt = 1 / 60
			DisplayLag.step(clock, 0, dt) -- première mesure : retard nul
			local previous = DisplayLag.now(clock, 100)
			for frame = 1, 120 do
				DisplayLag.step(clock, 0.3, dt)
				local now = DisplayLag.now(clock, 100 + frame * dt)
				local rate = (now - previous) / dt
				T.expect(
					rate >= 1 - DisplayLag.MAX_RATE - 1e-6 and rate <= 1 + DisplayLag.MAX_RATE + 1e-6,
					string.format("vitesse des pièges %.2f", rate)
				)
				previous = now
			end
			T.expectNear(clock.lag, 0.3, 0.02, "retard rejoint en 2 s")
		end)

		T.it("garde le dernier retard sans mesure et lisse le bruit d'une image", function()
			local clock = DisplayLag.clock()
			for _ = 1, 300 do
				DisplayLag.step(clock, 0.25, 1 / 60)
			end
			for _ = 1, 60 do
				DisplayLag.step(clock, nil, 1 / 60)
			end
			T.expectNear(clock.lag, 0.25, 0.005, "retard gardé hors vol")
			DisplayLag.step(clock, 0.45, 1 / 60)
			T.expect(clock.lag - 0.25 <= DisplayLag.MAX_RATE / 60 + 1e-9, "une mesure isolée ne fait pas sauter")
		end)

		T.it("borne le retard de 0 à MAX", function()
			local clock = DisplayLag.clock()
			for _ = 1, 600 do
				DisplayLag.step(clock, 5, 1 / 60)
			end
			T.expectNear(clock.lag, DisplayLag.MAX, 1e-6)
			for _ = 1, 600 do
				DisplayLag.step(clock, -1, 1 / 60)
			end
			T.expectNear(clock.lag, 0, 1e-6)
		end)
	end)
end
