-- Départ du vol vu par le lanceur (#117) : trajectoire du plan, temps retrouvé depuis la position, affichage anticipé
-- qui ne recule jamais et rejoint la copie répliquée (figée au départ le temps du tampon d'interpolation, puis en retard).
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local FlightArc = loader:require("src/shared/FlightArc")
	local FlightGhost = loader:require("src/shared/FlightGhost")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Gauge = loader:require("src/shared/Gauge")
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

	export type Release = {
		backward: number, -- plus grand recul d'une image à l'autre (studs, le long de la piste)
		frozen: number, -- images où la position affichée n'avance pas (maintien à la main exclu)
		firstMove: number?, -- temps (s) de la première image où le mannequin a quitté la main
		firstStep: number, -- écart (studs) entre le décoratif lâché et la première image affichée
		maxStep: number, -- plus grand déplacement d'une image (studs)
		minRate: number, -- vitesse d'affichage la plus basse avant le retour (hors résorption forcée)
		doneAt: number?, -- temps (s) du retour à la copie répliquée
	}

	-- Cette méthode permet de rejouer un lâcher anticipé vu par le lanceur (#144) : départ sur le plan prévu par le client
	-- (`client`), départ du serveur reçu `rtt` s après le lâcher (recalage sur `server`), copie répliquée figée `buffer` s
	-- de plus puis en retard (`catchUp` : défilement du moteur), relais du décoratif après TRANSITION ; `start` : écart
	-- du décoratif lâché au point de départ prévu.
	local function release(
		client: FlightGhost.Path,
		server: FlightGhost.Path,
		rtt: number,
		buffer: number,
		fps: number,
		start: Vector3?,
		catchUp: number?
	): Release
		local hold = FlightGhost.hold(rtt)
		local state = FlightGhost.new(hold, start)
		local dt = 1 / fps
		local run: Release = {
			backward = 0,
			frozen = 0,
			firstMove = nil,
			firstStep = 0,
			maxStep = 0,
			minRate = 1,
			doneAt = nil,
		}
		local released = client.origin + (start or Vector3.zero)
		local previous: Vector3? = nil
		local path = client
		local rebased, swapped = false, false
		local t = 0
		while t < 4 do
			t += dt
			if not rebased and t >= rtt then
				FlightGhost.rebase(state, client, server)
				path = server
				rebased = true
			end
			if rebased and not swapped and FlightGhost.flying(state) >= FlightGhost.TRANSITION then
				swapped = true
			end
			local position
			local replicatedTime =
				math.min(math.max(t - rtt - buffer, 0) * (catchUp or 1), FlightGhost.duration(server))
			if swapped then
				local replicated = FlightGhost.sample(server, replicatedTime)
				position = replicated + FlightGhost.advance(server, state, replicated, dt)
			else
				position = FlightGhost.ahead(path, state, dt)
			end
			if not state.done and not state.fading and t > hold + dt then
				run.minRate = math.min(run.minRate, state.rate)
			end
			if state.done and not run.doneAt then
				run.doneAt = t
			end
			if previous then
				local along = (position - server.origin):Dot(server.flat)
				local before = (previous - server.origin):Dot(server.flat)
				run.backward = math.max(run.backward, before - along)
				if along - before < 1e-3 and t > hold + dt and replicatedTime < FlightGhost.duration(server) then
					run.frozen += 1
				end
				run.maxStep = math.max(run.maxStep, (position - previous).Magnitude)
			else
				run.firstStep = (position - released).Magnitude
			end
			if not run.firstMove and (position - released).Magnitude > 0.05 then
				run.firstMove = t
			end
			previous = position
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

	T.describe("Lâcher anticipé (#144)", function()
		T.it("ralentit l'affichage sans descendre sous MIN_RATE, et le borne quand la copie n'arrive pas", function()
			T.expectNear(FlightGhost.rate(0), 1, 1e-9)
			T.expectNear(FlightGhost.rate(0.1), 1 - FlightGhost.GAIN * 0.1, 1e-9)
			T.expectNear(FlightGhost.rate(0.3), FlightGhost.MIN_RATE, 1e-9)
			T.expectNear(FlightGhost.rate(FlightGhost.MAX_LEAD - FlightGhost.FLOOR_FADE), FlightGhost.MIN_RATE, 1e-9)
			T.expectNear(FlightGhost.rate(FlightGhost.MAX_LEAD), 0, 1e-9)
			T.expectNear(FlightGhost.rate(-1), FlightGhost.MAX_RATE, 1e-9)
		end)

		T.it("ne maintient à la main qu'au-delà de RELEASE_LEAD_MAX de latence", function()
			T.expectEqual(FlightGhost.hold(0), 0)
			T.expectEqual(FlightGhost.hold(0.35), 0)
			T.expectNear(FlightGhost.hold(GameConfig.RELEASE_LEAD_MAX + 0.2), 0.2, 1e-9)
		end)

		T.it(
			"quitte la main dès le lâcher, sans recul ni gel, à 0 et 150 ms de latence (15 et 60 i/s, tampon de 200 à 290 ms)",
			function()
				local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
				local speed = launchVelocity(22e6).Magnitude
				-- Aller-retour mesuré en Studio : ≈ 50 ms sans latence simulée, ≈ 350 ms à 150 ms
				for _, rtt in { 0.05, 0.35 } do
					for _, buffer in { 0.2, 0.29 } do
						for _, fps in { 15, 60 } do
							local run = release(path, path, rtt, buffer, fps, Vector3.new(0.4, -0.3, -0.6), 1.04)
							local label =
								string.format(" (aller-retour %.2f s, tampon %.2f s, %d i/s)", rtt, buffer, fps)
							T.expect(
								run.firstMove ~= nil and run.firstMove <= 1.5 / fps,
								"départ à la 1re image" .. label
							)
							T.expect(run.firstStep <= speed / fps * 1.05 + 0.1, "1re image " .. run.firstStep .. label)
							T.expect(run.backward < 0.05, "recul " .. run.backward .. label)
							T.expectEqual(run.frozen, 0, "images figées" .. label)
							T.expect(run.minRate >= FlightGhost.MIN_RATE - 1e-6, "vitesse " .. run.minRate .. label)
							T.expect(
								run.maxStep <= speed / fps * FlightGhost.MAX_RATE + 1,
								"saut " .. run.maxStep .. label
							)
							T.expect(run.doneAt ~= nil and run.doneAt < 2.5, "main rendue" .. label)
							if fps == 60 then
								print(
									string.format(
										"[mesure] lâcher anticipé%s : vitesse affichée ≥ %.0f %%, main rendue à %.2f s",
										label,
										run.minRate * 100,
										run.doneAt or -1
									)
								)
							end
						end
					end
				end
			end
		)

		T.it("se recale sans recul sur un départ du serveur plus lent (jauge recalée)", function()
			local client = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			-- Jauge à 0,8 au lieu de 1 chez le serveur, départ 0,4 stud plus haut (main répliquée)
			local server =
				FlightGhost.path(ORIGIN + Vector3.new(0, 0.4, 0), launchVelocity(22e6) * Gauge.launchFactor(0.8), G)
			local speed = launchVelocity(22e6).Magnitude
			for _, rtt in { 0.05, 0.35 } do
				for _, fps in { 15, 60 } do
					local run = release(client, server, rtt, 0.25, fps, nil, 1.04)
					local label = string.format(" (aller-retour %.2f s, %d i/s)", rtt, fps)
					T.expect(run.backward < 0.05, "recul " .. run.backward .. label)
					T.expectEqual(run.frozen, 0, "images figées" .. label)
					T.expect(run.maxStep <= speed / fps * FlightGhost.MAX_RATE + 1, "saut " .. run.maxStep .. label)
					T.expect(run.doneAt ~= nil and run.doneAt < 3, "main rendue" .. label)
				end
			end
		end)

		T.it("garde le mannequin en main le temps de la latence au-delà de RELEASE_LEAD_MAX, puis part", function()
			local path = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			local rtt = GameConfig.RELEASE_LEAD_MAX + 0.2
			local run = release(path, path, rtt, 0.25, 60, nil, 1.04)
			T.expect(run.firstMove ~= nil and math.abs(run.firstMove - 0.2) <= 2 / 60, "départ après 0,2 s")
			T.expect(run.backward < 0.05, "recul " .. run.backward)
			T.expectEqual(run.frozen, 0, "images figées après le maintien")
			T.expect(run.doneAt ~= nil and run.doneAt < 3, "main rendue")
		end)

		T.it("recale le temps affiché sur la distance le long de la piste du plan du serveur", function()
			local client = FlightGhost.path(ORIGIN, launchVelocity(22e6), G)
			local server = FlightGhost.path(ORIGIN, launchVelocity(22e6) * 0.9, G)
			local state = FlightGhost.new()
			for _ = 1, 18 do
				FlightGhost.ahead(client, state, 1 / 60)
			end
			local before = FlightGhost.sample(client, state.shown)
			FlightGhost.rebase(state, client, server)
			local after = FlightGhost.sample(server, state.shown) + FlightGhost.correction(state)
			T.expectNear((after - before).Magnitude, 0, 1e-3, "pas de saut au recalage")
			T.expectNear((after - ORIGIN):Dot(server.flat), (before - ORIGIN):Dot(client.flat), 1e-3, "même distance")
			-- L'écart restant se résorbe en RECALE_TIME
			for _ = 1, math.ceil(FlightGhost.RECALE_TIME * 60) + 1 do
				FlightGhost.ahead(server, state, 1 / 60)
			end
			T.expectEqual(FlightGhost.correction(state), Vector3.zero)
		end)
	end)
end
