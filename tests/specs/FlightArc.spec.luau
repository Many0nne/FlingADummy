-- Vol plafonné et glissade bornée (#113) : plan du vol, montée freinée au plafond, croisière, chute au point de l'arc
-- naturel, frein au sol ; vérifiés sur un vol simulé (gravité seule, sol plat, sans obstacle).
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local FlightArc = loader:require("src/shared/FlightArc")
	local GameConfig = loader:require("src/shared/GameConfig")

	local G = GameConfig.GRAVITY
	local PITCH = math.rad(GameConfig.LAUNCH_PITCH_DEG)
	local ORIGIN_HEIGHT = 5.3 -- main de l'avatar au lâcher, au-dessus de la bande (piste à y = 0)
	local FORWARD = Vector3.zAxis
	local DT = 1 / 60
	local TORSO_REST = 1 -- hauteur du torse posé sur la piste

	-- Cette méthode permet de simuler un vol sans obstacle (gravité, sol plat, contrôle FlightArc à chaque frame)
	-- lorsque l'on vérifie la trajectoire ; renvoie le sommet, la distance au premier contact et la distance finale.
	local function fly(speed: number): (number, number, number, FlightArc.Plan)
		local vx, vy = speed * math.cos(PITCH), speed * math.sin(PITCH)
		local plan = FlightArc.plan(vx, vy, ORIGIN_HEIGHT, G)
		local phase = FlightArc.startPhase(plan)
		local position = Vector3.new(0, ORIGIN_HEIGHT, 0)
		local velocity = Vector3.new(0, vy, vx)
		local apex, landed = position.Y, nil
		local t = 0
		while t < 60 do
			t += DT
			velocity -= Vector3.new(0, G * DT, 0)
			position += velocity * DT
			if position.Y < TORSO_REST then
				position = Vector3.new(position.X, TORSO_REST, position.Z)
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end
			apex = math.max(apex, position.Y)
			local change
			phase, change = FlightArc.step(plan, {
				phase = phase,
				along = position.Z,
				height = position.Y,
				velocity = velocity,
				forward = FORWARD,
				armed = t > GameConfig.IMPACT_GRACE_TIME,
				impact = false,
				trapped = false,
				coasting = false,
				dt = DT,
				gravity = G,
			})
			velocity += change
			if phase == "Landed" and not landed then
				landed = position.Z
			end
			if phase == "Landed" and velocity.Magnitude < 0.5 then
				break
			end
		end
		return apex, landed or position.Z, position.Z, plan
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
			T.expect(math.abs(v.X) < 20, "latéral toujours amorti")
		end)
	end)
end
