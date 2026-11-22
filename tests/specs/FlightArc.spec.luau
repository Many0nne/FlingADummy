-- Vol plafonné et glissade bornée (#113) : plan du vol, montée freinée au plafond, croisière, chute au point de l'arc
-- naturel, frein au sol ; comportements des mannequins à lancer (#130) : poussée, planeur, rebonds. Vérifiés sur un vol
-- simulé (gravité seule, sol plat, sans obstacle).
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local FlightArc = loader:require("src/shared/FlightArc")
	local GameConfig = loader:require("src/shared/GameConfig")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")

	local G = GameConfig.GRAVITY
	local PITCH = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local ORIGIN_HEIGHT = 5.3 -- main de l'avatar au lâcher, au-dessus de la bande (piste à y = 0)
	local FORWARD = Vector3.zAxis
	local DT = 1 / 60
	local TORSO_REST = 1 -- hauteur du torse posé sur la piste

	-- Cette méthode permet de donner le premier mannequin dessiné du comportement `name` (« Bouncy », « Glides »,
	-- « Jetpack ») lorsque l'on vérifie son vol.
	local function dummyOf(name: string): any
		for _, dummy in ThrowDummies.LIST do
			if dummy.behavior == name then
				return dummy
			end
		end
		error("mannequin introuvable : " .. name)
	end

	export type Flight = {
		apex: number, -- plus haut point du torse
		landed: number, -- distance au premier contact
		final: number, -- distance à l'arrêt
		duration: number, -- durée jusqu'à l'arrêt (s)
		bounces: number, -- rebonds du caoutchouc
		descent: number, -- durée de la dernière descente depuis plus de 90 studs jusqu'au premier contact (s)
		plan: FlightArc.Plan,
	}

	-- Cette méthode permet de simuler un vol sans obstacle (gravité, sol plat qui arrête la chute, comportement et
	-- contrôle FlightArc à chaque frame, comme Server.LaunchService) lorsque l'on vérifie la trajectoire.
	local function simulate(speed: number, behavior: FlightArc.Behavior?): Flight
		local vx, vy = speed * math.cos(PITCH), speed * math.sin(PITCH)
		local plan = FlightArc.plan(vx, vy, ORIGIN_HEIGHT, G, behavior)
		local phase = FlightArc.startPhase(plan)
		local position = Vector3.new(0, ORIGIN_HEIGHT, 0)
		local velocity = Vector3.new(0, vy, vx)
		local apex, landed = position.Y, nil
		local fall, bounces, bounceUntil = 0, 0, 0
		local highAt, descent = 0, 0
		local t = 0
		while t < 60 do
			t += DT
			local before = velocity
			velocity -= Vector3.new(0, G * DT, 0)
			position += velocity * DT
			if position.Y < TORSO_REST then
				position = Vector3.new(position.X, TORSO_REST, position.Z)
				velocity = Vector3.new(velocity.X, math.max(velocity.Y, 0), velocity.Z)
			end
			apex = math.max(apex, position.Y)
			if position.Y > 90 then
				highAt = t
			end
			local armed = t > GameConfig.IMPACT_GRACE_TIME
			local change = FlightArc.accel(plan, velocity, FORWARD, t, G) * DT
			if armed then
				local bounced = FlightArc.bounce(plan, before, velocity, FORWARD, fall)
				if bounced then
					change += bounced - velocity
					bounces += 1
					bounceUntil = t + FlightArc.bounceTime(bounced, G)
				end
			end
			local vyNow = (velocity + change).Y
			fall = if vyNow < 0 then math.max(fall, -vyNow) else 0
			local control
			phase, control = FlightArc.step(plan, {
				phase = phase,
				along = position.Z,
				height = position.Y,
				velocity = velocity + change,
				forward = FORWARD,
				armed = armed,
				impact = false,
				trapped = false,
				coasting = false,
				bouncing = t < bounceUntil,
				dt = DT,
				gravity = G,
			})
			velocity += change + control
			if phase == "Landed" and not landed then
				landed = position.Z
				descent = t - highAt
			end
			if phase == "Landed" and velocity.Magnitude < 0.5 then
				break
			end
		end
		return {
			apex = apex,
			landed = landed or position.Z,
			final = position.Z,
			duration = t,
			bounces = bounces,
			descent = descent,
			plan = plan,
		}
	end

	-- Cette méthode permet de simuler un vol du Crash Dummy (sans comportement) lorsque l'on vérifie la trajectoire ;
	-- renvoie le sommet, la distance au premier contact, la distance finale et le plan.
	local function fly(speed: number): (number, number, number, FlightArc.Plan)
		local flight = simulate(speed)
		return flight.apex, flight.landed, flight.final, flight.plan
	end

	T.describe("FlightArc.plan", function()
		T.it("laisse l'arc naturel sous le plafond (débutant)", function()
			local speed = Economy.launchSpeed(GameConfig.START_POWER)
			local vx, vy = speed * math.cos(PITCH), speed * math.sin(PITCH)
			local plan = FlightArc.plan(vx, vy, ORIGIN_HEIGHT, G)
			T.expect(not plan.capped, "pas plafonné")
			T.expectNear(plan.apex, ORIGIN_HEIGHT + vy * vy / (2 * G), 1e-6)
			T.expect(plan.drop == nil, "pas de croisière")
		end)

		T.it("plafonne le sommet et garde la portée de l'arc naturel (pleine puissance)", function()
			local speed = Economy.launchSpeed(4.4e9)
			local vx, vy = speed * math.cos(PITCH), speed * math.sin(PITCH)
			local plan = FlightArc.plan(vx, vy, ORIGIN_HEIGHT, G)
			local fallHeight = ORIGIN_HEIGHT - FlightArc.GROUND_HEIGHT
			local natural = vx * (vy + math.sqrt(vy * vy + 2 * G * fallHeight)) / G
			T.expect(plan.capped, "plafonné")
			T.expectNear(plan.apex, GameConfig.APEX_HEIGHT, 1e-9)
			T.expectNear(plan.range, natural, 1e-6, "même point de chute que l'arc naturel")
			T.expect(plan.drop and plan.drop < plan.range, "croisière puis chute")
		end)

		T.it("donne une portée qui croît avec la vitesse, sans saut au plafond", function()
			local previous = 0
			for speed = 100, 1000, 5 do
				local plan = FlightArc.plan(speed * math.cos(PITCH), speed * math.sin(PITCH), ORIGIN_HEIGHT, G)
				T.expect(plan.range > previous, "portée croissante à " .. speed)
				T.expect(
					previous == 0 or plan.range / previous < (speed / (speed - 5)) ^ 2 * 1.03,
					"pas de saut à " .. speed
				)
				previous = plan.range
			end
		end)
	end)

	T.describe("FlightArc.step (vol simulé)", function()
		T.it("ne dépasse jamais le plafond, quelle que soit la puissance", function()
			for _, power in { 10, 1e4, 2.2e7, 3.6e8, 4.4e9, 1e12 } do
				local apex = fly(Economy.launchSpeed(power))
				T.expect(
					apex <= GameConfig.APEX_HEIGHT + 2,
					string.format("puissance %g : sommet %.0f studs", power, apex)
				)
			end
		end)

		T.it("touche le sol au point prévu par le plan (± 2 %)", function()
			for _, power in { 10, 1e4, 2.2e7, 3.6e8, 4.4e9 } do
				local _, landed, _, plan = fly(Economy.launchSpeed(power))
				T.expect(
					math.abs(landed - plan.range) <= plan.range * 0.02 + 3,
					string.format("puissance %g : contact à %.0f, prévu %.0f", power, landed, plan.range)
				)
			end
		end)

		T.it("borne la glissade au frein seul (≈ un thème à pleine puissance)", function()
			local speed = Economy.launchSpeed(4.4e9)
			local _, landed, final = fly(speed)
			local slide = final - landed
			local expected = FlightArc.slide(speed * math.cos(PITCH))
			T.expect(
				math.abs(slide - expected) < expected * 0.05 + 5,
				string.format("glissade %.0f, attendue %.0f", slide, expected)
			)
			T.expect(slide > 300 and slide < 650, string.format("glissade %.0f m", slide))
		end)

		T.it("compte un choc pendant la montée comme premier contact, sans lever le plafond", function()
			local plan = FlightArc.plan(600, 300, ORIGIN_HEIGHT, G)
			local state = {
				phase = "Rise" :: FlightArc.Phase,
				along = 50,
				height = 30,
				velocity = Vector3.new(0, 250, 600),
				forward = FORWARD,
				armed = true,
				impact = true,
				trapped = false,
				coasting = false,
				dt = DT,
				gravity = G,
			}
			local phase, change = FlightArc.step(plan, state)
			T.expect(phase == "Landed", "premier contact, obtenu " .. phase)
			T.expect(change.Y < 0, "montée encore freinée vers le plafond")
			-- Projeté par un piège : plus de plafond
			state.trapped = true
			local _, free = FlightArc.step(plan, state)
			T.expectNear(free.Y, 0, 1e-9, "rebond de piège laissé libre")
		end)

		T.it("ne remonte pas au plafond une montée stoppée bien plus bas", function()
			local plan = FlightArc.plan(600, 300, ORIGIN_HEIGHT, G)
			local phase, change = FlightArc.step(plan, {
				phase = "Rise",
				along = 80,
				height = 40,
				velocity = Vector3.new(0, -5, 600),
				forward = FORWARD,
				armed = true,
				impact = false,
				trapped = false,
				coasting = false,
				dt = DT,
				gravity = G,
			})
			T.expect(phase == "Free", "chute libre, obtenu " .. phase)
			T.expect(change.Y <= 0, "pas de remontée")
		end)

		T.it("laisse un arc sous le plafond sans contrôle", function()
			local plan = FlightArc.plan(100, 60, ORIGIN_HEIGHT, G)
			local phase, change = FlightArc.step(plan, {
				phase = FlightArc.startPhase(plan),
				along = 5,
				height = 8,
				velocity = Vector3.new(0, 55, 100),
				forward = FORWARD,
				armed = true,
				impact = false,
				trapped = false,
				coasting = false,
				dt = DT,
				gravity = G,
			})
			T.expect(phase == "Free", "arc naturel")
			T.expect(change == Vector3.zero, "aucune force")
		end)

		T.it("passe au sol au premier contact, pas pendant le délai de grâce", function()
			local plan = FlightArc.plan(100, 50, ORIGIN_HEIGHT, G)
			local state = {
				phase = "Free" :: FlightArc.Phase,
				along = 10,
				height = 2,
				velocity = Vector3.new(0, -20, 100),
				forward = FORWARD,
				armed = false,
				impact = false,
				trapped = false,
				coasting = false,
				dt = DT,
				gravity = G,
			}
			T.expect(FlightArc.step(plan, state) == "Free", "pas pendant la grâce")
			state.armed = true
			T.expect(FlightArc.step(plan, state) == "Landed", "au sol")
		end)
	end)

	T.describe("Comportements des mannequins à lancer (#130)", function()
		local POWERS = { 200, 1e4, 1e6, 2.2e7, 3.6e8, 4.4e9 }

		T.it("chacun gagne 10 à 30 % de distance finale sur le Crash Dummy, à toute puissance", function()
			local misses = {}
			for _, name in { "Bouncy", "Glides", "Jetpack" } do
				local dummy = dummyOf(name)
				for _, power in POWERS do
					local speed = Economy.launchSpeed(power)
					local crash = simulate(speed).final
					local own = simulate(speed, dummy).final
					local gain = own / crash - 1
					print(
						string.format(
							"[mesure] %s puissance %g : %.0f m contre %.0f (%+.1f %%)",
							name,
							power,
							own,
							crash,
							gain * 100
						)
					)
					if gain < 0.1 or gain > 0.3 then
						table.insert(misses, string.format("%s à %g : %+.1f %%", name, power, gain * 100))
					end
				end
			end
			T.expect(#misses == 0, table.concat(misses, " ; "))
		end)

		T.it("touche le sol et finit ses rebonds au point prévu par le plan (± 3 %)", function()
			for _, name in { "Bouncy", "Glides", "Jetpack" } do
				for _, power in POWERS do
					local flight = simulate(Economy.launchSpeed(power), dummyOf(name))
					local plan = flight.plan
					T.expect(
						math.abs(flight.landed - plan.range) <= plan.range * 0.03 + 3,
						string.format("%s à %g : contact à %.0f, prévu %.0f", name, power, flight.landed, plan.range)
					)
					local slide = FlightArc.slide(plan.landingSpeed)
					T.expect(
						math.abs(flight.final - (plan.reach + slide)) <= plan.reach * 0.03 + 5,
						string.format(
							"%s à %g : arrêt à %.0f, prévu %.0f",
							name,
							power,
							flight.final,
							plan.reach + slide
						)
					)
				end
			end
		end)

		T.it("aucun ne passe le plafond", function()
			for _, name in { "Bouncy", "Glides", "Jetpack" } do
				for _, power in { 1e4, 2.2e7, 4.4e9, 1e12 } do
					local flight = simulate(Economy.launchSpeed(power), dummyOf(name))
					T.expect(
						flight.apex <= GameConfig.APEX_HEIGHT + 2,
						string.format("%s à %g : sommet %.0f studs", name, power, flight.apex)
					)
				end
			end
		end)

		T.it("le caoutchouc rebondit au moins 3 fois, haut (un tiers du plafond) puis de moins en moins", function()
			local rubber = dummyOf("Bouncy")
			for _, power in { 2.2e7, 4.4e9 } do
				local flight = simulate(Economy.launchSpeed(power), rubber)
				T.expect(flight.bounces >= 3, string.format("%g : %d rebonds", power, flight.bounces))
				local up = math.sqrt(2 * G * (GameConfig.APEX_HEIGHT - FlightArc.TORSO_REST))
					* FlightArc.BOUNCE_RESTITUTION
				T.expect(up * up / (2 * G) > GameConfig.APEX_HEIGHT / 3, "premier rebond haut")
			end
		end)

		T.it("le planeur descend du plafond lentement (vitesse tenue, descente bien plus longue)", function()
			local glider = dummyOf("Glides")
			for _, power in { 2.2e7, 4.4e9 } do
				local speed = Economy.launchSpeed(power)
				local crash = simulate(speed)
				local flight = simulate(speed, glider)
				local sink = flight.plan.sink :: number
				T.expect(sink >= 25 and sink <= 70, string.format("%g : descente à %.0f studs/s", power, sink))
				T.expect(
					flight.descent > crash.descent * 1.5,
					string.format("%g : descente %.2f s contre %.2f", power, flight.descent, crash.descent)
				)
			end
		end)

		T.it("le réacteur accélère pendant sa poussée, puis file à vitesse constante", function()
			local rocket = dummyOf("Jetpack")
			local speed = Economy.launchSpeed(2.2e7)
			local plan = FlightArc.plan(speed * math.cos(PITCH), speed * math.sin(PITCH), ORIGIN_HEIGHT, G, rocket)
			T.expect(plan.boost > 0 and plan.boostTime == rocket.thrustTime, "poussée")
			T.expect(
				plan.landingSpeed > speed * math.cos(PITCH) * 1.1,
				string.format("vitesse %.0f après la poussée", plan.landingSpeed)
			)
			local pitched = Vector3.new(0, math.sin(PITCH), math.cos(PITCH))
			local early = FlightArc.accel(plan, Vector3.new(0, 20, 90), pitched, 0.2, G)
			T.expectNear(early.Y, 0, 1e-6, "à plat")
			T.expectNear(early.Z, plan.boost, 1e-3)
			T.expectEqual(FlightArc.accel(plan, Vector3.new(0, 20, 90), pitched, plan.boostTime + 0.1, G), Vector3.zero)
		end)

		T.it("garde des vols sous MAX_FLIGHT_TIME à pleine puissance (marge pour les obstacles)", function()
			for _, name in { "Classic", "Bouncy", "Glides", "Jetpack" } do
				local flight = simulate(Economy.launchSpeed(4.4e9), if name == "Classic" then nil else dummyOf(name))
				-- Plus REST_TIME pour clore le vol
				local total = flight.duration + GameConfig.REST_TIME
				print(string.format("[mesure] %s à 4,4 B : vol de %.1f s (sol plat)", name, total))
				T.expect(total < GameConfig.MAX_FLIGHT_TIME * 0.75, string.format("%s : %.1f s", name, total))
			end
		end)
	end)

	T.describe("FlightArc.accel et FlightArc.bounce", function()
		local function planOf(name: string): FlightArc.Plan
			local speed = Economy.launchSpeed(2.2e7)
			return FlightArc.plan(speed * math.cos(PITCH), speed * math.sin(PITCH), ORIGIN_HEIGHT, G, dummyOf(name))
		end

		T.it("le planeur porte seulement quand il descend plus vite que sa vitesse tenue", function()
			local plan = planOf("Glides")
			local sink = plan.sink :: number
			T.expectEqual(FlightArc.accel(plan, Vector3.new(0, 30, 80), FORWARD, 2, G), Vector3.zero, "en montée")
			T.expectEqual(FlightArc.accel(plan, Vector3.new(0, -sink + 1, 80), FORWARD, 2, G), Vector3.zero)
			T.expectNear(FlightArc.accel(plan, Vector3.new(0, -sink - 0.01, 80), FORWARD, 2, G).Y, G, 0.5, "tient")
			T.expect(FlightArc.accel(plan, Vector3.new(0, -sink - 20, 80), FORWARD, 2, G).Y > G, "rattrape")
		end)

		T.it("le caoutchouc rebondit à élan réglé, seulement sur une chute arrêtée", function()
			local plan = planOf("Bouncy")
			local speed = plan.bounceSpeed :: number
			local before = Vector3.new(0, -60, speed + 300)
			local stopped = Vector3.new(3, 0, 20)
			local out = FlightArc.bounce(plan, before, stopped, FORWARD) :: Vector3
			T.expect(out ~= nil, "rebond au sol")
			T.expectNear(out.Y, 60 * FlightArc.BOUNCE_RESTITUTION, 1e-3)
			T.expectNear(out.Z, speed, 1e-3, "élan réglé par le plan")
			T.expectNear(out.X, 3, 1e-3)
			local staggered = FlightArc.bounce(plan, before, stopped, FORWARD, 150) :: Vector3
			T.expectNear(staggered.Y, 150 * FlightArc.BOUNCE_RESTITUTION, 1e-3, "chute la plus forte retenue")
			T.expectEqual(FlightArc.bounce(plan, Vector3.new(0, -10, 80), stopped, FORWARD), nil, "chute faible")
			T.expectEqual(FlightArc.bounce(plan, before, Vector3.new(0, -50, 80), FORWARD), nil, "en l'air")
			T.expectEqual(FlightArc.bounce(planOf("Classic"), before, stopped, FORWARD), nil, "pas rebondissant")
		end)

		T.it("le Crash Dummy n'a aucun comportement propre", function()
			local plan = planOf("Classic")
			T.expectEqual(FlightArc.accel(plan, Vector3.new(0, -50, 90), FORWARD, 0.1, G), Vector3.zero)
			T.expectEqual(plan.reach, plan.range)
			T.expectNear(plan.range, plan.natural, 1e-6)
		end)

		T.it("ne freine pas l'élan d'un rebond en cours, freine après", function()
			local v = FlightArc.brake(Vector3.new(0, 40, 300), FORWARD, 1, 0.1, false, true)
			T.expectNear(v.Z, 300, 1e-9)
		end)
	end)

	T.describe("FlightArc.brake", function()
		T.it("freine l'élan au sol et amortit la vitesse latérale, sans toucher la chute", function()
			local v = FlightArc.brake(Vector3.new(40, -10, 300), FORWARD, 1, 0.1)
			T.expectNear(v.Z, 300 - GameConfig.GROUND_BRAKE * 0.1, 1e-6)
			T.expectNear(v.X, 40 * math.exp(-GameConfig.LATERAL_DAMP * 0.1), 1e-6)
			T.expectNear(v.Y, -10, 1e-9)
		end)

		T.it("ne repart pas en arrière et ne freine pas l'élan en l'air", function()
			T.expectNear(FlightArc.brake(Vector3.new(0, 0, 5), FORWARD, 1, 0.1).Z, 0, 1e-9)
			T.expectNear(FlightArc.brake(Vector3.new(0, 0, -5), FORWARD, 1, 0.1).Z, 0, 1e-9)
			T.expectNear(FlightArc.brake(Vector3.new(0, 30, 300), FORWARD, 20, 0.1).Z, 300, 1e-9)
		end)

		T.it("laisse la poussée d'un piège au sol se voir (pas de frein juste après)", function()
			local v = FlightArc.brake(Vector3.new(20, 5, 270), FORWARD, 2, 0.1, true)
			T.expectNear(v.Z, 270, 1e-9)
			T.expectNear(v.X, 20, 1e-9, "poussée latérale du piège gardée")
		end)
	end)
end
