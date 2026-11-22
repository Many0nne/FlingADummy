-- Effets des comportements en vol (#138) : flamme du Rocket jusqu'à la fin de sa poussée affichée, traînées du Glider
-- pendant sa descente planée, « boing » du Rubber au rebond affiché apparié au compteur du serveur.
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local FlightArc = loader:require("src/shared/FlightArc")
	local FlightFx = loader:require("src/shared/FlightFx")
	local FlightGhost = loader:require("src/shared/FlightGhost")
	local GameConfig = loader:require("src/shared/GameConfig")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")

	local G = GameConfig.GRAVITY
	local PITCH = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local ORIGIN = Vector3.new(-2.1, 5.3, -5.7) -- main de l'avatar au lâcher (mesuré en Studio)
	local DT = 1 / 60

	-- Cette méthode permet de donner la vitesse de départ d'un lancer à `power` (jauge pleine, le long de +Z) lorsque
	-- l'on construit un vol de test.
	local function launchVelocity(power: number): Vector3
		local speed = Economy.launchSpeed(power)
		return Vector3.new(0, speed * math.sin(PITCH), speed * math.cos(PITCH))
	end

	-- Cette méthode permet de donner le premier mannequin dessiné du comportement `name` lorsque l'on vérifie ses
	-- effets.
	local function dummyOf(name: string): any
		for _, dummy in ThrowDummies.LIST do
			if dummy.behavior == name then
				return dummy
			end
		end
		error("mannequin introuvable : " .. name)
	end

	export type Run = {
		boostOff: number?, -- temps où la flamme s'éteint
		reignited: boolean, -- flamme rallumée après extinction
		glideOn: number?, -- temps où la glisse commence
		glideStarts: number, -- souffles joués
		glideFrames: number,
		bounces: { number }, -- temps de chaque « boing »
		ranks: { number }, -- rang de chaque « boing »
	}

	-- Cette méthode permet de rejouer les effets d'un vol affiché (positions `display(t)` à `fps`, rebonds comptés par
	-- le serveur `counted(t)`) pendant `duration` s lorsque l'on vérifie quand chaque effet tombe.
	local function replay(
		cues: any,
		velocity: Vector3,
		display: (number) -> Vector3,
		duration: number,
		counted: ((number) -> number)?,
		fps: number?
	): Run
		local tracker = FlightFx.tracker(cues, ORIGIN, velocity)
		local dt = 1 / (fps or 60)
		local run: Run = {
			boostOff = nil,
			reignited = false,
			glideOn = nil,
			glideStarts = 0,
			glideFrames = 0,
			bounces = {},
			ranks = {},
		}
		local t = 0
		local first = true
		while t < duration do
			-- Première image : temps 0, sans avance (le suivi démarre à l'apparition)
			local frame = FlightFx.step(tracker, display(t), if first then 0 else dt, if counted then counted(t) else 0)
			first = false
			if not frame.boosting and not run.boostOff then
				run.boostOff = t
			elseif frame.boosting and run.boostOff then
				run.reignited = true
			end
			if frame.glideStart then
				run.glideStarts += 1
				run.glideOn = run.glideOn or t
			end
			if frame.gliding then
				run.glideFrames += 1
			end
			if frame.bounce then
				table.insert(run.bounces, t)
				table.insert(run.ranks, frame.bounce)
			end
			t += dt
		end
		return run
	end

	T.describe("FlightFx.cues", function()
		T.it("donne poussée, glisse et rebonds au seul mannequin qui les a", function()
			local v = launchVelocity(22e6)
			local crash = FlightFx.cues(ORIGIN, v, G, dummyOf("Classic"))
			T.expectEqual(crash.boostAlong, 0, "Crash : pas de poussée")
			T.expect(not crash.glide, "Crash : pas de glisse")
			T.expectEqual(crash.bounces, 0, "Crash : pas de rebond réglé")
			local rocket = FlightFx.cues(ORIGIN, v, G, dummyOf("Jetpack"))
			T.expectNear(rocket.boostTime, dummyOf("Jetpack").thrustTime, 1e-9, "Rocket : durée de la poussée")
			T.expect(rocket.boostAlong > v.Z * rocket.boostTime, "Rocket : plus loin qu'à vitesse de départ")
			T.expect(FlightFx.cues(ORIGIN, v, G, dummyOf("Glides")).glide, "Glider : glisse")
			T.expectEqual(FlightFx.cues(ORIGIN, v, G, dummyOf("Bouncy")).bounces, 4, "Rubber : 4 rebonds à 22 M")
		end)

		T.it("place la fin de la poussée là où la trajectoire du plan l'atteint", function()
			local rocket = dummyOf("Jetpack")
			for _, power in { 1e4, 22e6, 4.4e9 } do
				local v = launchVelocity(power)
				local cues = FlightFx.cues(ORIGIN, v, G, rocket)
				local path = FlightGhost.path(ORIGIN, v, G, rocket)
				local at = FlightGhost.sample(path, cues.boostTime)
				local along = (at - ORIGIN):Dot(Vector3.zAxis)
				T.expectNear(cues.boostAlong, along, along * 0.01, "distance de fin de poussée à " .. power)
			end
		end)
	end)

	T.describe("FlightFx.step : Rocket", function()
		T.it("garde la flamme pendant la poussée affichée, puis l'éteint pour de bon", function()
			local rocket = dummyOf("Jetpack")
			local v = launchVelocity(22e6)
			local cues = FlightFx.cues(ORIGIN, v, G, rocket)
			local path = FlightGhost.path(ORIGIN, v, G, rocket)
			-- Copie locale du lanceur : la trajectoire du plan à temps réel
			local run = replay(cues, v, function(t)
				return (FlightGhost.sample(path, t))
			end, 3)
			T.expect(run.boostOff ~= nil, "flamme éteinte")
			T.expectNear(run.boostOff :: number, cues.boostTime, 2 * DT, "extinction à la fin de la poussée")
			T.expect(not run.reignited, "pas rallumée")
		end)

		T.it(
			"suit la copie répliquée en retard (tampon de 250 ms) : la flamme dure jusqu'à ce qu'elle passe la fin",
			function()
				local rocket = dummyOf("Jetpack")
				local v = launchVelocity(22e6)
				local cues = FlightFx.cues(ORIGIN, v, G, rocket)
				local path = FlightGhost.path(ORIGIN, v, G, rocket)
				local run = replay(cues, v, function(t)
					return (FlightGhost.sample(path, math.max(t - 0.25, 0)))
				end, 3, nil, 30)
				T.expectNear(run.boostOff :: number, cues.boostTime + 0.25, 2 / 30, "extinction décalée du tampon")
			end
		)

		T.it("s'éteint au plus tard BOOST_SLACK après la fin prévue (vol arrêté par un piège)", function()
			local rocket = dummyOf("Jetpack")
			local v = launchVelocity(22e6)
			local cues = FlightFx.cues(ORIGIN, v, G, rocket)
			local run = replay(cues, v, function()
				return ORIGIN + Vector3.new(0, 20, 30) -- bloqué loin avant la fin de la poussée
			end, 4)
			T.expectNear(run.boostOff :: number, cues.boostTime + FlightFx.BOOST_SLACK, 2 * DT, "extinction bornée")
		end)

		T.it("compte la poussée depuis le lâcher quand le suivi commence en retard", function()
			local rocket = dummyOf("Jetpack")
			local v = launchVelocity(22e6)
			local cues = FlightFx.cues(ORIGIN, v, G, rocket)
			-- Torse arrivé 1,5 s après le lâcher, mannequin retenu (piège) avant la fin de la poussée
			local tracker = FlightFx.tracker(cues, ORIGIN, v, 1.5)
			local off: number? = nil
			local t = 1.5
			while t < 5 do
				local frame = FlightFx.step(tracker, ORIGIN + Vector3.new(0, 20, 30), DT, 0)
				if not frame.boosting and not off then
					off = t
				end
				t += DT
			end
			T.expectNear(off :: number, cues.boostTime + FlightFx.BOOST_SLACK, 2 * DT, "extinction à l'heure du vol")
		end)

		T.it("n'allume rien pour un mannequin sans réacteur", function()
			local v = launchVelocity(22e6)
			local cues = FlightFx.cues(ORIGIN, v, G, dummyOf("Classic"))
			local path = FlightGhost.path(ORIGIN, v, G)
			local run = replay(cues, v, function(t)
				return (FlightGhost.sample(path, t))
			end, 2)
			T.expectEqual(run.boostOff, 0, "éteinte dès la première image")
		end)
	end)

	T.describe("FlightFx.step : Glider", function()
		T.it("allume les traînées pendant la descente planée seulement, souffle une fois", function()
			for _, power in { 1e4, 22e6, 4.4e9 } do
				local glider = dummyOf("Glides")
				local v = launchVelocity(power)
				local cues = FlightFx.cues(ORIGIN, v, G, glider)
				local path = FlightGhost.path(ORIGIN, v, G, glider, 20)
				local plan = FlightArc.plan(v.Z, v.Y, ORIGIN.Y, G, glider)
				local duration = FlightGhost.duration(path)
				-- Après le premier contact, le mannequin reste posé
				local run = replay(cues, v, function(t)
					return (FlightGhost.sample(path, t))
				end, duration + 1)
				local label = " à " .. power
				T.expectEqual(run.glideStarts, 1, "un souffle" .. label)
				-- La glisse commence dans la descente (après le sommet ou la croisière) et dure presque toute la descente
				local descentStart = if plan.drop then plan.drop / v.Z else v.Y / G
				T.expect((run.glideOn :: number) >= descentStart - 0.05, "pas avant la descente" .. label)
				T.expect(
					run.glideFrames * DT > 0.6 * (duration - (run.glideOn :: number)),
					"pendant la descente" .. label
				)
			end
		end)

		T.it("ne glisse jamais pour un mannequin sans aile", function()
			local v = launchVelocity(22e6)
			local cues = FlightFx.cues(ORIGIN, v, G, dummyOf("Classic"))
			local path = FlightGhost.path(ORIGIN, v, G, nil, 20)
			local run = replay(cues, v, function(t)
				return (FlightGhost.sample(path, t))
			end, FlightGhost.duration(path) + 1)
			T.expectEqual(run.glideFrames, 0)
		end)

		T.it("ne rallume pas les traînées sur les sauts contre les obstacles après la descente (Studio)", function()
			local glider = dummyOf("Glides")
			local v = launchVelocity(22e6)
			local cues = FlightFx.cues(ORIGIN, v, G, glider)
			local path = FlightGhost.path(ORIGIN, v, G, glider, 20)
			local duration = FlightGhost.duration(path)
			-- Descente jusqu'à 5 studs (posé sur une caisse, sans passer sous GROUND_HEIGHT), puis un saut de 15 studs
			local landing = duration
			for i, p in path.positions do
				if p.Y <= 5 then
					landing = (i - 1) * path.dt
					break
				end
			end
			local stop = FlightGhost.sample(path, landing)
			local run = replay(cues, v, function(t)
				if t <= landing then
					return (FlightGhost.sample(path, t))
				end
				local dt = t - landing
				local height = 5 + 30 * dt - G * dt * dt / 2
				return Vector3.new(stop.X, math.max(height, 5), stop.Z + 80 * dt)
			end, landing + 1)
			T.expectEqual(run.glideStarts, 1)
			-- Glisse seulement pendant la descente : pas au-delà de l'atterrissage
			T.expect(run.glideFrames * DT <= landing - (run.glideOn :: number) + DT, "pas de glisse après le plancher")
		end)
	end)

	T.describe("FlightFx.step : Rubber", function()
		-- Cette méthode permet de donner un vol de rebonds affiché (chute depuis 40 studs, puis rebonds partant aux
		-- vitesses `ups`, torse posé à 1 stud) et les instants des contacts lorsque l'on vérifie les « boing ».
		local function bouncing(ups: { number }): ((number) -> Vector3, { number })
			local contacts = {}
			local t = math.sqrt(2 * 39 / G)
			table.insert(contacts, t)
			for _, up in ups do
				t += 2 * up / G
				table.insert(contacts, t)
			end
			-- Cette méthode permet de donner la position affichée du torse à l'instant `time` lorsque le suivi rejoue le
			-- vol de rebonds.
			local function display(time: number): Vector3
				local start, up = 0, 0
				local height = 40 - G * time * time / 2
				for i, contact in contacts do
					if time >= contact then
						start, up = contact, ups[i] or 0
						local dt = time - start
						height = 1 + up * dt - G * dt * dt / 2
					end
				end
				return Vector3.new(0, math.max(height, 1), 30 * time)
			end
			return display, contacts
		end

		local UPS = { 60, 36, 21.6, 13 }
		local cues = { boostTime = 0, boostAlong = 0, glide = false, bounces = 4 }
		local v = Vector3.new(0, 0, 30)

		T.it("joue chaque rebond au moment où le torse affiché repart (serveur en avance de 0,2 s)", function()
			local display, contacts = bouncing(UPS)
			local run = replay(cues, v, display, contacts[#contacts] + 1, function(t)
				local count = 0
				for i = 1, 4 do
					if t >= contacts[i] - 0.2 then
						count = i
					end
				end
				return count
			end)
			T.expectEqual(#run.bounces, 4, "4 boing")
			for i = 1, 4 do
				T.expectEqual(run.ranks[i], i, "rang " .. i)
				T.expectNear(run.bounces[i], contacts[i], 2 * DT, "boing " .. i .. " au rebond affiché")
			end
		end)

		T.it("joue aussi un rebond compté par le serveur un peu après la remontée affichée", function()
			local display, contacts = bouncing(UPS)
			local run = replay(cues, v, display, contacts[#contacts] + 1, function(t)
				return if t >= contacts[1] + 0.15 then 1 else 0
			end)
			T.expectEqual(#run.bounces, 1)
			T.expectNear(run.bounces[1], contacts[1] + 0.15, 2 * DT, "dès que le compteur arrive")
		end)

		T.it("joue un rebond compté sans remontée affichée passé MATCH (repli)", function()
			local run = replay(
				cues,
				v,
				function(t)
					return Vector3.new(0, 1, 30 * t) -- posé, sans remontée
				end,
				2,
				function(t)
					return if t >= 0.5 then 1 else 0
				end
			)
			T.expectEqual(#run.bounces, 1)
			T.expectNear(run.bounces[1], 0.5 + FlightFx.MATCH, 2 * DT, "repli")
		end)

		T.it("garde chaque boing sur son rebond quand l'affichage a plus de MATCH de retard sur le serveur", function()
			local display, contacts = bouncing(UPS)
			-- Compteur du serveur 0,6 s avant chaque remontée affichée : chaque boing part par repli, 0,2 s tôt, sans que
			-- la remontée d'un rebond déjà joué ne déclenche le suivant
			local lead = 0.6
			local run = replay(cues, v, display, contacts[#contacts] + 1, function(t)
				local count = 0
				for i = 1, 4 do
					if t >= contacts[i] - lead then
						count = i
					end
				end
				return count
			end)
			T.expectEqual(#run.bounces, 4, "4 boing")
			local previous = 0
			for i = 1, 4 do
				-- Attente du repli à partir du compteur, ou du boing précédent si le compteur l'a devancé
				local expected = math.max(contacts[i] - lead, previous + DT) + FlightFx.MATCH
				T.expectNear(run.bounces[i], expected, 2 * DT, "boing " .. i .. " par repli")
				T.expect(run.bounces[i] <= contacts[i] + FlightFx.MATCH, "boing " .. i .. " pas après son rebond")
				previous = run.bounces[i]
			end
		end)

		T.it("ne prend pas la remontée suivante pour un compteur arrivé en retard (plus de MATCH)", function()
			local display, contacts = bouncing(UPS)
			-- Rebond 1 compté 0,5 s après sa remontée affichée, les suivants à l'heure
			local run = replay(cues, v, display, contacts[#contacts] + 1, function(t)
				local count = 0
				for i = 1, 4 do
					local at = if i == 1 then contacts[1] + 0.5 else contacts[i] - 0.1
					if t >= at then
						count = i
					end
				end
				return count
			end)
			T.expectEqual(#run.bounces, 4, "4 boing")
			T.expectNear(run.bounces[1], contacts[1] + 0.5 + FlightFx.MATCH, 2 * DT, "boing 1 par repli")
			for i = 2, 4 do
				T.expectNear(run.bounces[i], contacts[i], 2 * DT, "boing " .. i .. " à son rebond")
			end
		end)

		T.it("ne rejoue pas les rebonds déjà comptés quand le suivi commence en cours de vol", function()
			local tracker = FlightFx.tracker(cues, ORIGIN, v, 6, 3)
			local played = {}
			local t = 0
			while t < 2 do
				local frame = FlightFx.step(tracker, Vector3.new(0, 1, 100 + 30 * t), DT, 3)
				if frame.bounce then
					table.insert(played, frame.bounce)
				end
				t += DT
			end
			T.expectEqual(#played, 0, "rien à rejouer")
			local frame
			for _ = 1, 40 do
				frame = FlightFx.step(tracker, Vector3.new(0, 1, 200), DT, 4)
				if frame.bounce then
					break
				end
			end
			T.expectEqual(frame.bounce, 4, "le suivant garde son rang")
		end)

		T.it("ignore les rebonds physiques non comptés et borne aux rebonds du plan", function()
			local display, contacts = bouncing(UPS)
			local none = replay(cues, v, display, contacts[#contacts] + 1)
			T.expectEqual(#none.bounces, 0, "rien sans compteur")
			local capped = replay(
				{ boostTime = 0, boostAlong = 0, glide = false, bounces = 2 },
				v,
				display,
				5,
				function()
					return 4
				end
			)
			T.expectEqual(#capped.bounces, 2, "au plus les rebonds du plan")
		end)
	end)

	T.describe("FlightFx : réglages", function()
		T.it("monte la hauteur du boing et réduit l'éclat d'un rebond à l'autre", function()
			for k = 2, 6 do
				T.expect(FlightFx.boingPitch(k) > FlightFx.boingPitch(k - 1), "plus aigu")
				T.expect(FlightFx.bounceScale(k) <= FlightFx.bounceScale(k - 1), "plus petit")
				T.expect(FlightFx.bounceScale(k) >= 0.4, "pas invisible")
			end
			T.expectEqual(FlightFx.boingPitch(1), 1)
			T.expectEqual(FlightFx.bounceScale(1), 1)
		end)

		T.it("allège les effets en mouvement réduit", function()
			local full, reduced = FlightFx.profile(false), FlightFx.profile(true)
			T.expect(reduced.rate < full.rate and reduced.burst < full.burst, "moins de particules")
			T.expect(full.ring and not reduced.ring, "pas d'anneau qui s'étend")
		end)
	end)
end
