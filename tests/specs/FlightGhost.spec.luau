-- Départ du vol vu par le lanceur (#117) : trajectoire du plan, temps retrouvé depuis la position, affichage anticipé
-- qui ne recule jamais et rejoint la copie répliquée (figée au départ le temps du tampon d'interpolation, puis en retard).
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local FlightArc = loader:require("src/shared/FlightArc")
	local FlightGhost = loader:require("src/shared/FlightGhost")
	local GameConfig = loader:require("src/shared/GameConfig")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")

	local G = GameConfig.GRAVITY
	local PITCH = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local ORIGIN = Vector3.new(-2.1, 5.3, -5.7) -- main de l'avatar au lâcher (mesuré en Studio)

	-- Cette méthode permet de donner la vitesse de départ d'un lancer à `power` (jauge pleine, le long de +Z) lorsque
	-- l'on construit une trajectoire de test.
	local function launchVelocity(power: number): Vector3
		local speed = Economy.launchSpeed(power)
		return Vector3.new(0, speed * math.sin(PITCH), speed * math.cos(PITCH))
	end

	export type Run = {
		backward: number, -- plus grand recul d'une image à l'autre de la position affichée (studs, le long de la piste)
		frozen: number, -- images où la position affichée n'avance pas (après la première)
		doneAt: number?, -- temps (s) où l'affichage rend la main
		maxOffset: number, -- plus grand décalage ajouté (studs)
	}

	-- Cette méthode permet de rejouer un départ vu par le client lorsque la copie répliquée reste figée `buffer` s à
	-- sa première position (temps `first` sur la trajectoire) puis suit le plan avec ce retard, à `fps` images/s, la
	-- copie s'arrêtant net au bout de la trajectoire (premier contact) ; `error` décale la copie du plan (studs),
	-- `catchUp` la fait défiler plus vite que le temps réel une fois partie (le moteur réduit son retard).
	local function replay(
		path: FlightGhost.Path,
		buffer: number,
		fps: number,
		first: number?,
		error: Vector3?,
		catchUp: number?
	): Run
		local state = FlightGhost.new()
		local dt = 1 / fps
		local run: Run = { backward = 0, frozen = 0, doneAt = nil, maxOffset = 0 }
		local previous: number? = nil
		local t = 0
		while t < 4 do
			local played = math.max(t - buffer, 0) * (catchUp or 1)
			local replicatedTime = math.min(math.max(first or 0, played), FlightGhost.duration(path))
			local replicated = FlightGhost.sample(path, replicatedTime) + (error or Vector3.zero)
			local offset = FlightGhost.advance(path, state, replicated, dt)
			run.maxOffset = math.max(run.maxOffset, offset.Magnitude)
			local along = (replicated + offset - path.origin):Dot(path.flat)
			if previous then
				run.backward = math.max(run.backward, previous - along)
				if along - previous < 1e-3 and replicatedTime < FlightGhost.duration(path) then
					run.frozen += 1
				end
			end
			previous = along
			if state.done and not run.doneAt then
				run.doneAt = t
			end
			t += dt
		end
		return run
	end

	T.describe("FlightGhost.path", function()
		T.it("monte au plafond, y file à plat et s'arrête au premier contact (puissance forte)", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G, nil, 30)
			local apex = 0
			for _, p in path.positions do
				apex = math.max(apex, p.Y)
			end
			T.expectNear(apex, GameConfig.APEX_HEIGHT, 2, "sommet au plafond")
			local last = path.positions[#path.positions]
			T.expect(last.Y < FlightArc.GROUND_HEIGHT + 5, "trajectoire arrêtée près du sol")
			local v = launchVelocity(22e6)
			local plan = FlightArc.plan(v.Z, v.Y, ORIGIN.Y, G)
			T.expectNear(path.along[#path.along], plan.range, plan.range * 0.01, "premier contact au point du plan")
		end)

		T.it("garde des distances croissantes le long de la piste", function()
			for _, power in { GameConfig.START_POWER, 1e4, 22e6, 4.4e9 } do
				local path = FlightGhost.path(ORIGIN, launchVelocity(power), G)
				for i = 2, #path.along do
					T.expect(path.along[i] >= path.along[i - 1], "distance croissante à " .. power)
				end
			end
		end)

		T.it("suit la poussée du réacteur (mannequin à lancer)", function()
			local rocket
			for _, dummy in ThrowDummies.LIST do
				if dummy.thrust > 0 then
					rocket = dummy
					break
				end
			end
			T.expect(rocket ~= nil, "un réacteur au catalogue")
			local plain = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			local pushed = FlightGhost.path(ORIGIN, launchVelocity(22e6), G, rocket)
			local a = FlightGhost.sample(plain, 1)
			local b = FlightGhost.sample(pushed, 1)
			T.expect(b.Z > a.Z + 5, "plus loin après 1 s de poussée")
		end)
	end)

	T.describe("FlightGhost.timeAt", function()
		T.it("retrouve le temps d'une position de la trajectoire", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			for _, time in { 0, 0.01, 0.2, 0.55, 1.3, 2.4 } do
				local found, beyond = FlightGhost.timeAt(path, (FlightGhost.sample(path, time)))
				T.expectNear(found, time, 1e-3, "temps " .. time)
				T.expect(not beyond, "dans la trajectoire")
			end
		end)

		T.it("borne au départ et signale une position au-delà de la trajectoire", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(GameConfig.START_POWER), G)
			T.expectEqual(FlightGhost.timeAt(path, ORIGIN - Vector3.new(0, 0, 3)), 0)
			local far = path.positions[#path.positions] + Vector3.new(0, 0, 50)
			local found, beyond = FlightGhost.timeAt(path, far)
			T.expectNear(found, FlightGhost.duration(path), 1e-9)
			T.expect(beyond, "au-delà")
		end)
	end)

	T.describe("FlightGhost.advance", function()
		T.it(
			"ne recule jamais et ne se fige pas au départ d'un lancer fort (tampon de 50 à 350 ms, 15 et 60 i/s)",
			function()
				local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
				for _, buffer in { 0.05, 0.2, 0.35 } do
					for _, fps in { 15, 60 } do
						local run = replay(path, buffer, fps)
						local label = string.format(" (tampon %.2f s, %d i/s)", buffer, fps)
						T.expect(run.backward < 0.05, "recul " .. run.backward .. label)
						T.expectEqual(run.frozen, 0, "images figées" .. label)
						T.expect(run.doneAt ~= nil and run.doneAt < buffer + 2, "main rendue" .. label)
						-- Avance (s) bornée par 1 / GAIN, quel que soit le tampon
						local bound = launchVelocity(22e6).Magnitude / FlightGhost.GAIN
						T.expect(run.maxOffset < bound, "avance bornée " .. run.maxOffset .. label)
					end
				end
			end
		)

		T.it(
			"rattrape une copie répliquée qui part un pas devant (premier instantané après un pas du serveur)",
			function()
				local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
				local run = replay(path, 0.2, 60, FlightGhost.DT)
				T.expect(run.backward < 0.05, "recul " .. run.backward)
				T.expect(run.doneAt ~= nil, "main rendue")
			end
		)

		T.it(
			"rend la main quand la copie répliquée défile plus vite que le temps réel (retard réduit, mesuré à 4 %)",
			function()
				local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
				for _, catchUp in { 1.02, 1.04, 1.08 } do
					for _, fps in { 15, 60 } do
						local run = replay(path, 0.35, fps, nil, nil, catchUp)
						local label = string.format(" (× %.2f, %d i/s)", catchUp, fps)
						T.expect(run.backward < 0.05, "recul " .. run.backward .. label)
						T.expect(run.doneAt ~= nil and run.doneAt < 2.2, "main rendue" .. label)
					end
				end
			end
		)

		T.it("tolère l'écart du plan avec la physique du serveur (quelques studs)", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			local run = replay(path, 0.2, 60, nil, Vector3.new(0.5, -2, 1))
			T.expect(run.backward < 0.05, "recul " .. run.backward)
			T.expect(run.doneAt ~= nil and run.doneAt < 2.2, "main rendue")
		end)

		T.it("rend la main en douceur quand un vol court touche le sol avant d'avoir résorbé l'avance", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(GameConfig.START_POWER), G)
			local run = replay(path, 0.2, 60)
			T.expect(run.doneAt ~= nil, "main rendue")
			T.expect(run.backward < 1, "recul " .. run.backward .. " studs")
		end)

		T.it("donne la vitesse affichée (ralentie tant que la copie est figée) pour la caméra", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			local state = FlightGhost.new()
			local dt = 1 / 60
			for _ = 1, 12 do
				FlightGhost.advance(path, state, ORIGIN, dt) -- copie répliquée figée 0,2 s
			end
			local _, planned = FlightGhost.sample(path, state.shown)
			local replicated = launchVelocity(22e6)
			local shown = FlightGhost.velocity(path, state, replicated)
			T.expect(state.rate > 0.4 and state.rate < 0.8, "ralentie : " .. state.rate)
			T.expectNear(shown.Magnitude, planned.Magnitude * state.rate, 1e-3)
			-- Résorption forcée : la copie répliquée moins l'écart qui se résorbe
			state.fading = FlightGhost.BLEND_TIME
			state.fadeFrom = Vector3.new(0, 0, 30)
			local fading = FlightGhost.velocity(path, state, replicated)
			T.expectNear(fading.Z, replicated.Z - 30 / FlightGhost.BLEND_TIME, 1e-3)
			state.done = true
			T.expectEqual(
				FlightGhost.velocity(path, state, replicated),
				replicated,
				"copie répliquée après le retour"
			)
		end)

		T.it("rend la main quand la copie quitte le plan (choc)", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			local state = FlightGhost.new()
			local dt = 1 / 60
			for _ = 1, 6 do
				FlightGhost.advance(path, state, ORIGIN, dt)
			end
			-- Déviée de 20 studs vers le haut : choc
			local hit = FlightGhost.sample(path, 0.05) + Vector3.new(0, 20, 0)
			local offset = FlightGhost.advance(path, state, hit, dt)
			T.expect(state.fading ~= nil, "résorption forcée")
			local after = offset
			for _ = 1, 20 do
				after = FlightGhost.advance(path, state, hit, dt)
			end
			T.expect(state.done, "main rendue après BLEND_TIME")
			T.expectEqual(after, Vector3.zero)
		end)
	end)
end
