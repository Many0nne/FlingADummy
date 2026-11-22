-- Anneau propulseur de la Moon Base (#98) : depuis le vol plafonné de #113, les vols qui atteignent la Moon Base
-- filent à APEX_HEIGHT (100 studs) ; l'ancien cerceau, à 81-89 studs sur la chute, n'en prenait que 5 %. Le cerceau est
-- calé sur le plafond (sa boîte l'entoure) et un vol simulé (tools/BoosterRingSim : plan du serveur, puissances et jauges
-- équiréparties, vols en l'air au passage du site) le traverse souvent, sans que ce soit garanti, à chaque site et pour
-- chaque comportement (Crash, Glider, Rocket).
return function(T, Loader, Lib)
	local Sim = Lib.BoosterRingSim
	local m = Sim.modules(Loader.new())
	local def = m.Traps.KINDS.Booster
	local bottom, top = def.bottom :: number, def.height

	T.describe("Anneau propulseur (#98) : hauteur", function()
		T.it("entoure le plafond du vol, dans l'ouverture du cerceau (boîte de 8 studs)", function()
			T.expectNear((bottom + top) / 2, m.GameConfig.APEX_HEIGHT, 1e-9)
			T.expectNear(top - bottom, 2 * m.Traps.RING_HALF, 1e-9)
			T.expect(top - bottom <= 9.8, "pas plus grand que l'ouverture du cerceau (9,8 studs)")
		end)

		T.it("garde les deux sites de la Moon Base (1,8 km et 2,2 km)", function()
			local sites = Sim.sites(m)
			T.expectEqual(#sites, 2)
			T.expect(sites[1] > 1650 and sites[2] < 2400, "sites dans la Moon Base")
		end)
	end)

	T.describe("Anneau propulseur (#98) : taux de passage", function()
		-- Pas plus gros que l'outil (1,25 et 0,05 : 1 743 vols par mannequin) pour tenir en quelques secondes
		local STEP, GAUGE_STEP = 1.4, 0.1
		for _, index in { 1, 5, 6 } do
			local thrown = m.ThrowDummies.get(index)
			T.it(thrown.name .. " : 40 à 75 % des vols en l'air au-dessus de chaque site le traversent", function()
				local flights = Sim.flights(m, thrown, STEP, GAUGE_STEP)
				for _, z in Sim.sites(m) do
					local heights = Sim.heights(flights, z)
					T.expect(#heights >= 100, "assez de vols en l'air au site " .. z)
					local share = Sim.share(heights, bottom, top)
					T.expect(share >= 0.4 and share <= 0.75, string.format("site %.0f : %.0f %%", z, 100 * share))
				end
			end)
		end

		T.it("l'ancien cerceau (81-89 studs) n'en prenait que quelques-uns : le recalage change tout", function()
			local flights = Sim.flights(m, m.ThrowDummies.get(1), STEP, GAUGE_STEP)
			for _, z in Sim.sites(m) do
				local share = Sim.share(Sim.heights(flights, z), 81, 89)
				T.expect(share < 0.1, string.format("site %.0f : %.0f %%", z, 100 * share))
			end
		end)
	end)
end
