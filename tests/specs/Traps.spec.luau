-- Pièges signatures : réaction propre à chaque piège, traversée de boîte, membres qui cassent.
return function(T, Loader)
	local loader = Loader.new()
	local Traps = loader:require("src/shared/Traps")
	local Damage = loader:require("src/shared/Damage")
	local Sounds = loader:require("src/shared/Sounds")

	local falling = Vector3.new(2, -40, 30) -- mannequin qui retombe en avançant
	local sliding = Vector3.new(0, 0, 25) -- mannequin qui glisse au sol

	T.describe("Traps.KINDS", function()
		T.it("donne à chaque piège un popup, un son connu, des os cassés et une cause de crash", function()
			for kind, def in Traps.KINDS do
				T.expect(#def.label > 0, kind .. " : popup")
				T.expect(Sounds[def.sound] ~= nil, kind .. " : son inconnu " .. def.sound)
				T.expect(def.bones >= 1 and def.bones <= 3, kind .. " : os")
				T.expect(def.depth > 0, kind .. " : profondeur")
				T.expect(def.height > (def.bottom or Traps.FLOOR), kind .. " : hauteur")
				local cause = Damage.cause(kind, 20)
				T.expect(not string.find(cause, "Hit the ground", 1, true), kind .. " : cause de crash")
			end
		end)

		T.it("fait réagir le mannequin de façon différente d'un piège à l'autre", function()
			local seen = {}
			for kind in Traps.KINDS do
				local v = Traps.react(kind, falling, Vector3.zAxis)
				local key = string.format("%.0f/%.0f/%.0f", v.X, v.Y, v.Z)
				T.expect(not seen[key], kind .. " réagit comme " .. tostring(seen[key]))
				seen[key] = kind
			end
		end)
	end)

	T.describe("Traps.react", function()
		T.it("trampoline et lave renvoient vers le haut un mannequin qui tombe", function()
			T.expect(Traps.react("Trampoline", falling, Vector3.zero).Y >= 60, "trampoline")
			local lava = Traps.react("Lava", Vector3.new(0, -120, 20), Vector3.zero)
			T.expectNear(lava.Y, 120, 1e-6) -- rebond complet au-delà du minimum
			T.expect(Traps.react("Lava", sliding, Vector3.zero).Y >= 80, "lave : rebond même sans chute")
		end)

		T.it("la presse écrase vers le sol et coupe l'élan", function()
			local v = Traps.react("Press", falling, Vector3.zero)
			T.expect(v.Y < 0, "vers le bas")
			T.expect(v.Z < falling.Z, "élan coupé")
		end)

		T.it("l'aimant coupe l'essentiel de la course et soulève", function()
			local v = Traps.react("Magnet", Vector3.new(0, 10, 200), Vector3.zero)
			T.expect(math.abs(v.Z) <= 0.3 * 200, "élan coupé : " .. v.Z)
			T.expect(v.Y > 0, "soulevé")
		end)

		T.it("ventilateur, vague, tremplin, canon et propulseur poussent vers l'avant", function()
			for _, kind in { "Fan", "Wave", "SkiJump", "Cannon", "Booster", "Rainbow", "Wormhole" } do
				T.expect(Traps.react(kind, sliding, Vector3.zero).Z >= sliding.Z + 25, kind)
			end
		end)

		T.it("geyser, cristal et fantôme renvoient vers le haut ; le laser coupe l'élan (#97)", function()
			T.expect(Traps.react("Geyser", sliding, Vector3.zero).Y >= 90, "geyser")
			T.expect(Traps.react("Bumper", falling, Vector3.zero).Y >= 50, "cristal")
			T.expect(Traps.react("Ghost", sliding, Vector3.zero).Y >= 60, "fantôme")
			local laser = Traps.react("Laser", Vector3.new(0, 0, 200), Vector3.zero)
			T.expect(laser.Z <= 0.6 * 200, "laser : élan coupé (" .. laser.Z .. ")")
		end)

		T.it("le rondin pousse dans l'axe de la piste, dans le sens de sa poussée", function()
			local ahead = Traps.react("SwingLog", sliding, Vector3.zAxis)
			local back = Traps.react("SwingLog", sliding, -Vector3.zAxis)
			T.expectNear(ahead.X, 0, 1e-9)
			T.expectNear(ahead.Z - back.Z, 2 * Traps.KINDS.SwingLog.side, 1e-9)
			T.expect(back.Z < sliding.Z, "rondin qui revient : élan coupé")
		end)
	end)

	T.describe("Traps.crosses", function()
		local center, size = Vector3.new(0, 4, 100), Vector3.new(12, 10, 8)
		T.it("voit un passage à grande vitesse d'un bout à l'autre de la boîte", function()
			T.expect(Traps.crosses(center, size, Vector3.new(0, 4, 80), Vector3.new(0, 4, 120)), "traversée")
		end)
		T.it("voit un mannequin immobile dedans", function()
			local inside = Vector3.new(1, 1, 101)
			T.expect(Traps.crosses(center, size, inside, inside), "immobile dedans")
		end)
		T.it("ignore un passage au-dessus, à côté ou qui s'arrête avant", function()
			T.expect(not Traps.crosses(center, size, Vector3.new(0, 20, 80), Vector3.new(0, 20, 120)), "au-dessus")
			T.expect(not Traps.crosses(center, size, Vector3.new(8, 4, 80), Vector3.new(8, 4, 120)), "à côté")
			T.expect(not Traps.crosses(center, size, Vector3.new(0, 4, 80), Vector3.new(0, 4, 95)), "avant")
		end)
		T.it("voit une chute en diagonale qui ne fait qu'effleurer un coin", function()
			T.expect(Traps.crosses(center, size, Vector3.new(-10, 12, 94), Vector3.new(-4, 6, 98)), "coin")
		end)
	end)

	T.describe("Traps.motion", function()
		T.it("tourne d'un tour par période, balance et monte puis revient au repos", function()
			local spin = Traps.motion("Spin", 0.25, Vector3.zAxis, 0, 1)
			T.expect((spin.UpVector - Vector3.new(-1, 0, 0)).Magnitude < 1e-3, "quart de tour")
			T.expect(Traps.motion("Swing", 0, Vector3.xAxis, 50, 2).UpVector:Dot(Vector3.yAxis) > 0.999, "au milieu")
			local bob = Traps.motion("Bob", 0.5, Vector3.yAxis, 2, 1)
			T.expectNear(bob.Position.Y, 2, 1e-6)
			T.expectNear(Traps.motion("Bob", 1, Vector3.yAxis, 2, 1).Position.Y, 0, 1e-6)
		end)
		T.it("la presse s'abat vite puis remonte lentement", function()
			local amplitude = -10
			T.expectNear(Traps.motion("Press", 0, Vector3.yAxis, amplitude, 2).Position.Y, 0, 1e-6)
			T.expectNear(Traps.motion("Press", 0.3, Vector3.yAxis, amplitude, 2).Position.Y, amplitude, 1e-6)
			local rising = Traps.motion("Press", 1.3, Vector3.yAxis, amplitude, 2).Position.Y
			T.expect(rising > amplitude and rising < 0, "en remontée : " .. rising)
		end)
	end)

	-- Cette méthode permet de donner la position Y de la pièce animée du piège `kind` (Traps.motion, comme Client.TrapMotion)
	-- à la phase de cycle `phase` lorsque l'on compare l'animation à la fenêtre active.
	local function animated(kind, motion, phase, amplitude)
		local period = Traps.CYCLES[kind].period
		return Traps.motion(motion, phase * period, Vector3.yAxis, amplitude, period).Position.Y
	end

	T.describe("Traps.active", function()
		T.it("donne la même phase que l'animation du client, décalage compris", function()
			T.expectEqual(Traps.phaseOffset(0, 0), 0)
			local offset = Traps.phaseOffset(14, 535)
			local period = Traps.CYCLES.Magnet.period
			local now = 1000.3
			-- Client.TrapMotion : t = now + offset * period, phase = (t / period) % 1
			T.expectNear(Traps.phase("Magnet", now, offset), ((now + offset * period) / period) % 1, 1e-9)
			T.expectEqual(Traps.phase("Trampoline", now, offset), 0)
		end)

		T.it("la presse écrase pendant la descente seulement, au rythme de l'animation", function()
			local period = Traps.CYCLES.Press.period
			T.expect(Traps.active("Press", 0.2 * period, 0), "plateau en bas")
			T.expect(not Traps.active("Press", 0.8 * period, 0), "plateau en remontée haute")
			T.expect(not Traps.active("Press", 0.01 * period, 0), "plateau encore en haut")
			-- Plateau à plus de 70 % de sa descente pendant toute la fenêtre active
			for phase = Traps.CYCLES.Press.from, Traps.CYCLES.Press.to, 0.01 do
				local down = -animated("Press", "Press", phase, -1)
				T.expect(down >= 0.7, string.format("phase %.2f : plateau à %.0f %%", phase, down * 100))
			end
		end)

		T.it("le diable n'éjecte que sorti à plus de la moitié de sa course", function()
			local cycle = Traps.CYCLES.JackBox
			for phase = 0, 0.995, 0.005 do
				local out = animated("JackBox", "Press", phase, 1)
				local active = Traps.active("JackBox", phase * cycle.period, 0)
				if active then
					T.expect(out >= 0.5, string.format("phase %.3f : sorti à %.0f %%", phase, out * 100))
				elseif out >= 0.6 then
					T.expect(false, string.format("phase %.3f : sorti à %.0f %% mais inactif", phase, out * 100))
				end
			end
			T.expect(not Traps.active("JackBox", 0.9 * cycle.period, 0), "rentré")
		end)

		T.it("l'aimant n'agit que pendant sa phase allumée", function()
			local cycle = Traps.CYCLES.Magnet
			T.expect(Traps.active("Magnet", 0.2 * cycle.period, 0), "allumé")
			T.expect(not Traps.active("Magnet", 0.7 * cycle.period, 0), "éteint")
			T.expect(cycle.to - cycle.from < 0.6, "éteint une bonne partie du cycle")
		end)

		T.it("les pièges sans cycle agissent toujours", function()
			for _, kind in { "Trampoline", "Fan", "Booster", "Lava", "Bumper", "Rainbow", "Wormhole" } do
				T.expect(Traps.active(kind, 12.34, 0.5), kind)
			end
		end)

		T.it("le fantôme n'emporte que sorti de sa tombe à plus de la moitié de sa course (#97)", function()
			local cycle = Traps.CYCLES.Ghost
			for phase = 0, 0.995, 0.005 do
				local out = animated("Ghost", "Press", phase, 1)
				if Traps.active("Ghost", phase * cycle.period, 0) then
					T.expect(out >= 0.5, string.format("phase %.3f : sorti à %.0f %%", phase, out * 100))
				elseif out >= 0.6 then
					T.expect(false, string.format("phase %.3f : sorti à %.0f %% mais inactif", phase, out * 100))
				end
			end
		end)

		T.it(
			"geyser et laser n'agissent que pendant leur phase allumée, éteints une bonne partie du cycle",
			function()
				for _, kind in { "Geyser", "Laser" } do
					local cycle = Traps.CYCLES[kind]
					T.expect(Traps.active(kind, (cycle.from + 0.01) * cycle.period, 0), kind .. " allumé")
					T.expect(not Traps.active(kind, (cycle.to + 0.05) * cycle.period, 0), kind .. " éteint")
					T.expect(cycle.to - cycle.from <= 0.5, kind .. " : éteint au moins la moitié du cycle")
				end
			end
		)

		T.it("le rondin ne frappe que lorsqu'il passe dans la boîte, en bas de son balancement", function()
			local period = Traps.CYCLES.SwingLog.period
			local depth = Traps.KINDS.SwingLog.depth
			local hits = 0
			for phase = 0, 0.995, 0.005 do
				-- Centre du rondin d'après l'animation (rotation autour de X du pivot, bras de SWING_ARM)
				local swing = Traps.motion("Swing", phase * period, Vector3.xAxis, Traps.SWING_AMPLITUDE, period)
				local log = swing * Vector3.new(0, -Traps.SWING_ARM, 0)
				local active = Traps.active("SwingLog", phase * period, 0)
				if active then
					hits += 1
					T.expect(
						math.abs(log.Z) <= Traps.SWING_REACH + 1e-6,
						string.format("phase %.3f : z %.1f", phase, log.Z)
					)
				else
					T.expect(math.abs(log.Z) > depth / 2, string.format("phase %.3f : inactif dans la boîte", phase))
				end
			end
			T.expect(hits > 20 and hits < 100, "partie active : " .. hits .. " / 200")
		end)

		T.it("le rondin ne frappe que le torse qu'il touche, à la position que montre l'animation", function()
			local period = Traps.CYCLES.SwingLog.period
			-- Centre d'après l'animation : rotation autour de X du pivot (SWING_PIVOT du sol), bras de SWING_ARM
			for phase = 0, 0.995, 0.005 do
				local swing = Traps.motion("Swing", phase * period, Vector3.xAxis, Traps.SWING_AMPLITUDE, period)
				local center = Vector3.new(0, Traps.SWING_PIVOT, 0) + swing * Vector3.new(0, -Traps.SWING_ARM, 0)
				T.expect(
					(Traps.swingCenter(phase) - center).Magnitude < 1e-3, -- Vector3 en float32
					string.format("phase %.3f : centre", phase)
				)
				local hit = Traps.active("SwingLog", phase * period, 0, center)
				T.expectEqual(hit, Traps.swingReach(phase))
			end
			local low = Traps.swingCenter(0.5)
			T.expectNear(low.Y, Traps.SWING_PIVOT - Traps.SWING_ARM, 1e-4)
			T.expect(Traps.active("SwingLog", 0.5 * period, 0, low + Vector3.new(5, 2, 1)), "torse contre le rondin")
			T.expect(not Traps.active("SwingLog", 0.5 * period, 0, low + Vector3.new(0, 9, 0)), "torse au-dessus")
			T.expect(not Traps.active("SwingLog", 0.5 * period, 0, low + Vector3.new(0, 0, 5)), "torse devant")
			T.expect(Traps.active("SwingLog", 0.5 * period, 0, Vector3.new(0, 0.5, 0)), "mannequin couché qui glisse")
		end)

		T.it("le rondin pousse dans le sens où il balance, à pleine force au plus bas", function()
			local period = Traps.CYCLES.SwingLog.period
			T.expectNear(Traps.swingPush(0.5), 1, 1e-9)
			T.expectNear(Traps.swingPush(0), -1, 1e-9)
			for _, phase in { 0.02, 0.48, 0.5, 0.53, 0.97, 0 } do
				local before = Traps.motion("Swing", phase * period, Vector3.xAxis, Traps.SWING_AMPLITUDE, period)
				local after =
					Traps.motion("Swing", phase * period + 0.001, Vector3.xAxis, Traps.SWING_AMPLITUDE, period)
				local dz = (after * Vector3.new(0, -Traps.SWING_ARM, 0)).Z
					- (before * Vector3.new(0, -Traps.SWING_ARM, 0)).Z
				local push = Traps.push("SwingLog", phase * period, 0)
				T.expect(push.Z * dz > 0, string.format("phase %.2f : même sens", phase))
				T.expectNear(push.X, 0, 1e-9)
				if Traps.swingReach(phase) then
					T.expect(math.abs(push.Z) > 0.8, string.format("phase %.2f : force %.2f", phase, push.Z))
				end
			end
			T.expectEqual(Traps.push("Fan", 1, 0), Vector3.zero)
		end)
	end)

	T.describe("Traps.contact", function()
		T.it("ramène un point sur la boîte", function()
			local c = Traps.contact(Vector3.new(0, 4, 100), Vector3.new(12, 10, 8), Vector3.new(20, 4, 90))
			T.expectEqual(c, Vector3.new(6, 4, 96))
		end)
	end)

	T.describe("Traps.nearestLimbs", function()
		T.it("casse les membres les plus proches du contact, un os chacun", function()
			local limbs = {
				Head = Vector3.new(0, 6, 0),
				Torso = Vector3.new(0, 4, 0),
				LeftLowerLeg = Vector3.new(-1, 0.5, 0),
				RightLowerLeg = Vector3.new(1, 0.5, 0),
			}
			local chosen = Traps.nearestLimbs(limbs, Vector3.new(0, 0, 0), 2)
			T.expectEqual(#chosen, 2)
			T.expectEqual(chosen[1], "LeftLowerLeg") -- à égalité : ordre alphabétique
			T.expectEqual(chosen[2], "RightLowerLeg")
			T.expectEqual(#Traps.nearestLimbs(limbs, Vector3.zero, 9), 4)
		end)
	end)
end
