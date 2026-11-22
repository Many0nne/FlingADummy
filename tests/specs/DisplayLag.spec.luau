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
		T.it("mesure l'écart entre l'heure serveur et celle du mannequin affiché, borné de 0 à MAX", function()
			local track = sampled(10, 11)
			T.expectNear(DisplayLag.measure(track, 11, flight(10.7)) :: number, 0.3, 0.005)
			T.expectEqual(DisplayLag.measure(track, 11, flight(10.1)), DisplayLag.MAX)
			T.expectEqual(DisplayLag.measure(track, 10.9, flight(11)), 0)
		end)
	end)

	T.describe("DisplayLag.step", function()
		T.it("rejoint le retard mesuré sans changer l'heure des pièges de plus de MAX_RATE par seconde", function()
			local clock = DisplayLag.clock()
			local dt = 1 / 60
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
