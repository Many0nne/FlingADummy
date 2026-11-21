-- Plan des obstacles : obstacles du thème à tour de rôle (plus de vitres, #90), piège signature, boîtes des pièges.
return function(T, Loader)
	local loader = Loader.new()
	local TrackPlan = loader:require("src/shared/TrackPlan")
	local Traps = loader:require("src/shared/Traps")
	local Zones = loader:require("src/shared/Zones")
	local CourseLayout = loader:require("src/shared/CourseLayout")
	local GameConfig = loader:require("src/shared/GameConfig")

	local LENGTH = GameConfig.COURSE_LENGTH
	local sites = TrackPlan.sites(LENGTH)

	T.describe("TrackPlan.zoneSites", function()
		T.it("pose dans chaque zone chaque obstacle du thème et son piège, sans vitres", function()
			for index, zone in Zones.LIST do
				local traps, obstacles = 0, {}
				for _, site in TrackPlan.zoneSites(index, LENGTH) do
					T.expectEqual(site.zone, index)
					if site.kind == "Trap" then
						traps += 1
						T.expectEqual(site.name, zone.trap)
					else
						T.expectEqual(site.kind, "Obstacle")
						obstacles[site.name] = true
					end
				end
				T.expect(traps >= 1, zone.name .. " : piège")
				for _, name in zone.obstacles do
					T.expect(obstacles[name], zone.name .. " : obstacle absent " .. name)
				end
			end
		end)

		T.it("garde chaque site dans sa zone, dégagé de son entrée et du départ", function()
			for _, site in sites do
				local zone = Zones.LIST[site.zone]
				local finish = Zones.finish(site.zone, LENGTH)
				T.expect(site.z >= zone.start + TrackPlan.START_GAP, zone.name .. " : site trop près de l'entrée")
				T.expect(site.z <= finish - TrackPlan.END_GAP + 0.25, zone.name .. " : site trop près de la sortie")
				T.expect(site.z >= TrackPlan.FIRST_SITE, "site trop près de la main")
			end
		end)

		T.it("espace les sites d'au moins 8 m, dans l'ordre de la piste", function()
			for i = 2, #sites do
				T.expect(
					sites[i].z - sites[i - 1].z >= 8,
					string.format("sites à %g et %g m", sites[i - 1].z, sites[i].z)
				)
			end
		end)

		T.it("met un piège avant la fin des 50 premiers mètres (lancer raté, bande vers la Prairie)", function()
			local first = math.huge
			for _, site in sites do
				if site.kind == "Trap" then
					first = math.min(first, site.z)
				end
			end
			T.expect(first <= 50, "premier piège à " .. first .. " m")
		end)

		T.it("ajoute des pièges dans les zones longues, sans dépasser MAX_SITES (plus l'obstacle en plus)", function()
			for index in Zones.LIST do
				local zoneSites = TrackPlan.zoneSites(index, LENGTH)
				T.expect(
					#zoneSites - TrackPlan.EXTRA_OBSTACLES
						<= math.max(TrackPlan.MAX_SITES, #Zones.LIST[index].obstacles + 1),
					"sites"
				)
			end
			local moon = TrackPlan.zoneSites(#Zones.LIST, LENGTH)
			local traps = 0
			for _, site in moon do
				traps += if site.kind == "Trap" then 1 else 0
			end
			T.expect(traps >= 2, "dernière zone (750 m) : " .. traps .. " pièges")
		end)
	end)

	T.describe("TrackPlan.zoneSites (pièges)", function()
		T.it("pose tous les pièges prévus sans en perdre", function()
			for index, zone in Zones.LIST do
				local length = Zones.finish(index, LENGTH) - zone.start
				local zoneSites = TrackPlan.zoneSites(index, LENGTH)
				local traps = 0
				for _, site in zoneSites do
					traps += if site.kind == "Trap" then 1 else 0
				end
				local base =
					math.clamp(math.floor(length / TrackPlan.SPACING + 0.5), TrackPlan.MIN_SITES, TrackPlan.MAX_SITES)
				local expected = math.max(1, math.min(math.floor(length / TrackPlan.TRAP_EVERY), math.floor(base / 3)))
				T.expectEqual(traps, expected)
			end
		end)
	end)

	T.describe("TrackPlan.trapBoxes", function()
		local boxes = TrackPlan.trapBoxes(sites)
		T.it("pose une boîte par colonne d'obstacles et par piège, numérotées", function()
			local trapSites = 0
			for _, site in sites do
				trapSites += if site.kind == "Trap" then 1 else 0
			end
			T.expectEqual(#boxes, trapSites * GameConfig.SLOT_COUNT)
			for i, box in boxes do
				T.expectEqual(box.id, i)
				T.expectEqual(box.x, CourseLayout.slotX(box.column))
			end
		end)

		T.it("donne le même site aux boîtes d'un piège (une fois par vol, toutes colonnes confondues)", function()
			local columnsBySite = {}
			for _, box in boxes do
				columnsBySite[box.site] = (columnsBySite[box.site] or 0) + 1
			end
			for site, columns in columnsBySite do
				T.expectEqual(columns, GameConfig.SLOT_COUNT)
				T.expect(site >= 1, "site numéroté")
			end
			T.expectEqual(#boxes, #columnsBySite * GameConfig.SLOT_COUNT)
		end)

		T.it(
			"part sous le sol (mannequin couché), ou du bas du piège suspendu, et monte à la hauteur du piège",
			function()
				for _, box in boxes do
					local def = Traps.KINDS[box.kind]
					local bottom = box.center.Y - box.size.Y / 2
					T.expectNear(bottom, def.bottom or Traps.FLOOR, 1e-9)
					local top = box.center.Y + box.size.Y / 2
					T.expectNear(top, def.height, 1e-9)
					T.expectEqual(box.size.X, def.width or Traps.WIDTH)
					T.expect(box.size.X <= Traps.WIDTH, box.kind .. " : dans sa colonne")
					T.expect(Traps.WIDTH < GameConfig.SLOT_SPACING, "un passage entre deux colonnes")
				end
			end
		)
	end)

	T.describe("TrackPlan.trapBox (anneau propulseur, #85)", function()
		local center, size = TrackPlan.trapBox("Booster", 7, 1900)
		local def = Traps.KINDS.Booster

		T.it("ne couvre que l'ouverture du cerceau, suspendue au-dessus de la piste", function()
			T.expect(def.bottom ~= nil and def.bottom > 40, "anneau suspendu")
			T.expectNear(center.Y, (def.bottom + def.height) / 2, 1e-9)
			T.expect(size.X <= 9.8 and size.Y <= 9.8, "pas plus grand que l'ouverture du cerceau (9,8 studs)")
			T.expectNear(center.X, 7, 1e-9)
			T.expectNear(center.Z, 1900, 1e-9)
		end)

		T.it("déclenche en passant dans l'anneau, pas sur la colonne en dessous ni à côté", function()
			local through = Traps.crosses(center, size, center - Vector3.new(0, 0, 8), center + Vector3.new(0, 0, 8))
			T.expect(through, "passage par le centre")
			local y = center.Y
			-- Ancienne colonne : à mi-hauteur (y 60, vérifié en Studio sur #85) et au ras du sol (pad)
			for _, height in { 60, 30, 1 } do
				local a, b = Vector3.new(7, height, 1890), Vector3.new(7, height, 1910)
				T.expect(not Traps.crosses(center, size, a, b), "sous l'anneau à " .. height .. " studs")
			end
			T.expect(
				not Traps.crosses(center, size, Vector3.new(14, y, 1890), Vector3.new(14, y, 1910)),
				"à côté de l'anneau (colonne voisine)"
			)
			T.expect(
				not Traps.crosses(center, size, Vector3.new(7, y + 8, 1890), Vector3.new(7, y + 8, 1910)),
				"au-dessus de l'anneau"
			)
		end)
	end)
end
