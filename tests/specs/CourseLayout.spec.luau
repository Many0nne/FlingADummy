-- Plan de la carte : places de la zone de lancer, appareils d'entraînement, bases, colonnes d'obstacles, gradins ;
-- zones et leur décor.
local fs = require("@lune/fs")

return function(T, Loader)
	local loader = Loader.new()
	local CourseLayout = loader:require("src/shared/CourseLayout")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Zones = loader:require("src/shared/Zones")
	local count = GameConfig.SLOT_COUNT

	T.describe("CourseLayout places", function()
		T.it("aligne SLOT_COUNT points de lancer de test côte à côte, centrés, sur la ligne de la bande", function()
			T.expectEqual(count, 4)
			local sum = 0
			for index = 1, count do
				local point = CourseLayout.launchPoint(index)
				sum += point.X
				T.expectEqual(point.Z, CourseLayout.BAND_Z)
				T.expect(CourseLayout.isOnBand(point), "point de lancer sur la bande")
			end
			T.expect(math.abs(sum) < 1e-6, "places centrées")
		end)

		T.it("met la bande sur toute la largeur de la piste, au bord du départ, dans la zone de lancer", function()
			local half = GameConfig.TRACK_WIDTH / 2
			local top = CourseLayout.BAND_TOP
			T.expect(GameConfig.BAND_DEPTH <= GameConfig.LAUNCH_DEPTH, "bande dans la zone de lancer")
			T.expect(CourseLayout.isOnBand(Vector3.new(half, top + 3, -0.1)), "coin gauche côté piste")
			T.expect(
				CourseLayout.isOnBand(Vector3.new(-half, top + 3, -GameConfig.BAND_DEPTH)),
				"coin droit côté hub"
			)
			T.expect(not CourseLayout.isOnBand(Vector3.new(0, top + 3, -GameConfig.BAND_DEPTH - 0.5)), "hub")
			T.expect(CourseLayout.isOnBand(Vector3.new(0, top + 3, 0.6)), "liseré blanc compté comme bande")
			T.expect(not CourseLayout.isOnBand(Vector3.new(0, top + 3, CourseLayout.BAND_EDGE + 0.5)), "piste")
			T.expect(not CourseLayout.isOnBand(Vector3.new(half + 1, top + 3, -2)), "hors de la largeur")
			T.expect(not CourseLayout.isOnBand(Vector3.new(0, top + 20, -2)), "loin au-dessus")
		end)
	end)

	T.describe("CourseLayout.bandDepth", function()
		T.it("fige le joueur à la profondeur où il est entré, à BAND_MARGIN des bords", function()
			local margin = GameConfig.BAND_MARGIN
			T.expectNear(CourseLayout.bandDepth(-7), -7)
			T.expectNear(CourseLayout.bandDepth(-GameConfig.BAND_DEPTH), -GameConfig.BAND_DEPTH + margin)
			T.expectNear(CourseLayout.bandDepth(0.5), -margin)
		end)
	end)

	T.describe("CourseLayout.bandSpot", function()
		local spacing = GameConfig.BAND_SPACING
		local limit = GameConfig.TRACK_WIDTH / 2 - GameConfig.BAND_MARGIN

		T.it("fige le joueur là où il est entré quand la place est libre", function()
			T.expectNear(CourseLayout.bandSpot(7.3, {}) :: number, 7.3)
			T.expectNear(CourseLayout.bandSpot(-12, { 10 }) :: number, -12)
		end)

		T.it("garde les bords à BAND_MARGIN", function()
			T.expectNear(CourseLayout.bandSpot(100, {}) :: number, limit)
			T.expectNear(CourseLayout.bandSpot(-GameConfig.TRACK_WIDTH / 2, {}) :: number, -limit)
		end)

		T.it("décale latéralement un joueur qui tomberait sur un autre, du côté le plus proche", function()
			T.expectNear(CourseLayout.bandSpot(1, { 0 }) :: number, spacing)
			T.expectNear(CourseLayout.bandSpot(-1, { 0 }) :: number, -spacing)
			-- Coincé contre le bord : décalé vers l'intérieur
			T.expectNear(CourseLayout.bandSpot(limit, { limit }) :: number, limit - spacing)
		end)

		T.it("glisse au-delà d'un groupe de joueurs serrés", function()
			local spot = CourseLayout.bandSpot(0.5, { 0, spacing }) :: number
			T.expectNear(spot, -spacing)
			local right = CourseLayout.bandSpot(spacing - 0.5, { 0, spacing }) :: number
			T.expectNear(right, 2 * spacing)
		end)

		T.it("fait tenir 4 joueurs côte à côte entrés au même endroit, tous à BAND_SPACING", function()
			local taken = {}
			for _ = 1, 4 do
				local spot = CourseLayout.bandSpot(0, taken)
				T.expect(spot ~= nil, "place trouvée")
				for _, other in taken do
					T.expect(math.abs((spot :: number) - other) >= spacing - 1e-6, "écart minimal")
				end
				table.insert(taken, spot :: number)
			end
			T.expectEqual(#taken, 4)
		end)

		T.it("renvoie nil quand la bande est pleine", function()
			local taken = {}
			local x = -limit
			while x <= limit + 1e-6 do
				table.insert(taken, x)
				x += spacing
			end
			T.expectEqual(CourseLayout.bandSpot(0, taken), nil)
		end)
	end)

	T.describe("CourseLayout hub", function()
		T.it("place l'appareil d'entraînement devant la base, à côté de l'entrée qu'il laisse libre", function()
			local half = CourseLayout.BASE_SIZE / 2
			local podium = CourseLayout.STATION_SIZE / 2
			for index = 1, count do
				local station, facing = CourseLayout.stationPosition(index)
				local base = CourseLayout.basePosition(index)
				local side = CourseLayout.entranceSide(index)
				-- Entrée de 10 studs au milieu du côté de la base : l'appareil ne la couvre pas, sans quitter la base
				local beside = math.abs(station.Z - base.Z) - podium
				T.expect(beside >= 5, "entrée libre, obtenu " .. beside)
				T.expect(math.abs(station.Z - base.Z) + podium <= half.Z, "le long de la base")
				T.expectEqual(math.sign(station.X - base.X), side, "du côté de l'entrée (centre du hub)")
				T.expect(-side * base.X > 0, "entrée tournée vers le centre du hub")
				T.expectEqual(facing, Vector3.new(side, 0, 0), "avatar face au centre du hub")
				local gap = math.abs(station.X - base.X) - half.X - podium
				T.expect(gap >= 4, "passage libre entre l'appareil et la clôture, obtenu " .. gap)
				T.expect(gap <= 8, "près de la base, obtenu " .. gap)
				T.expect(math.abs(station.X) + podium <= GameConfig.HUB_WIDTH / 2, "dans la largeur du hub")
				T.expect(station.Z + podium < -GameConfig.LAUNCH_DEPTH, "derrière la zone de lancer")
				for other = 1, count do
					local o = CourseLayout.basePosition(other)
					local apart = math.abs(o.X - station.X) >= half.X + podium
						or math.abs(o.Z - station.Z) >= half.Z + podium
					T.expect(apart, string.format("appareil %d hors de la base %d", index, other))
					if other ~= index then
						local s2 = CourseLayout.stationPosition(other)
						T.expect((s2 - station).Magnitude > 2 * podium, "appareils séparés")
					end
				end
			end
		end)

		T.it("donne à chaque joueur sa base, du côté de sa place, dans le hub, sans chevauchement", function()
			local half = CourseLayout.BASE_SIZE / 2
			for index = 1, count do
				local base = CourseLayout.basePosition(index)
				T.expect(base.X * CourseLayout.slotX(index) > 0, "base du côté de la place " .. index)
				T.expect(math.abs(base.X) + half.X <= GameConfig.HUB_WIDTH / 2, "base dans la largeur du hub")
				T.expect(base.Z + half.Z <= -GameConfig.LAUNCH_DEPTH, "base derrière la zone de lancer")
				T.expect(
					base.Z - half.Z >= -GameConfig.LAUNCH_DEPTH - GameConfig.HUB_DEPTH,
					"base dans la profondeur du hub"
				)
				for other = 1, index - 1 do
					local o = CourseLayout.basePosition(other)
					local apart = math.abs(o.X - base.X) >= 2 * half.X or math.abs(o.Z - base.Z) >= 2 * half.Z
					T.expect(apart, string.format("bases %d et %d séparées", other, index))
				end
				local displays = CourseLayout.displayPositions(index)
				T.expectEqual(#displays, CourseLayout.DISPLAY_COUNT)
				for _, position in displays do
					T.expect(math.abs(position.X - base.X) < half.X - 3, "présentoir dans la base (x)")
					T.expect(math.abs(position.Z - base.Z) < half.Z - 3, "présentoir dans la base (z)")
				end
			end
		end)
	end)

	T.describe("CourseLayout.isNearBase", function()
		T.it(
			"vrai dans la base et jusqu'à BASE_REACH de sa clôture, faux au-delà et dans les autres bases",
			function()
				local center = CourseLayout.basePosition(1)
				local half = CourseLayout.BASE_SIZE.X / 2
				T.expect(CourseLayout.isNearBase(1, center), "centre")
				T.expect(
					CourseLayout.isNearBase(1, center + Vector3.new(half + CourseLayout.BASE_REACH - 1, 5, 0)),
					"bord"
				)
				T.expect(
					not CourseLayout.isNearBase(1, center + Vector3.new(half + CourseLayout.BASE_REACH + 1, 0, 0)),
					"loin"
				)
				for index = 2, GameConfig.SLOT_COUNT do
					T.expect(not CourseLayout.isNearBase(1, CourseLayout.basePosition(index)), "base " .. index)
				end
				T.expect(not CourseLayout.isNearBase(1, Vector3.new(0, 0, -8)), "bande de lancer")
			end
		)
	end)

	T.describe("CourseLayout.columnAt", function()
		T.it("rend la colonne de chaque place et rien sur les bords du canyon", function()
			for index = 1, count do
				T.expectEqual(CourseLayout.columnAt(CourseLayout.slotX(index)), index)
			end
			T.expectEqual(CourseLayout.columnAt(GameConfig.TRACK_WIDTH / 2 - 1), nil)
			T.expectEqual(CourseLayout.columnAt(-GameConfig.TRACK_WIDTH / 2 + 1), nil)
		end)
	end)

	T.describe("CourseLayout.tier", function()
		T.it("recule et monte chaque marche, la première au bord de la piste", function()
			local inner, top = CourseLayout.tier(0)
			T.expectEqual(inner, GameConfig.TRACK_WIDTH / 2)
			T.expectEqual(top, CourseLayout.TIER_HEIGHT)
			for tier = 1, CourseLayout.TIER_COUNT - 1 do
				local i1, t1 = CourseLayout.tier(tier)
				local i0, t0 = CourseLayout.tier(tier - 1)
				T.expectEqual(i1 - i0, CourseLayout.TIER_STEP)
				T.expectEqual(t1 - t0, CourseLayout.TIER_HEIGHT)
			end
			local last = CourseLayout.tier(CourseLayout.TIER_COUNT - 1)
			T.expect(last < CourseLayout.OUTER, "plateau au-delà de la dernière marche")
		end)
	end)

	T.describe("Zones (identité visuelle)", function()
		-- Éléments de décor connus : `builders.<nom> =` dans Server.Props
		local known = {}
		for name in string.gmatch(fs.readFile("src/server/Props.luau"), "builders%.(%w+) =") do
			known[name] = true
		end

		T.it("donne à chaque zone ses couleurs (sol, parois, dessus) et un décor connu", function()
			for _, zone in Zones.LIST do
				for _, field in { "color", "ground", "wall", "top" } do
					T.expect(typeof(zone[field]) == "Color3", zone.name .. " : " .. field)
				end
				T.expect(#zone.props > 0, zone.name .. " : décor")
				for _, kind in zone.props do
					T.expect(known[kind], zone.name .. " : élément inconnu " .. kind)
				end
			end
		end)

		T.it("change de sol d'une zone à la suivante (identité forte)", function()
			for i = 2, #Zones.LIST do
				local a, b = Zones.LIST[i - 1].ground, Zones.LIST[i].ground
				local distance = math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
				T.expect(distance > 0.25, Zones.LIST[i].name .. " : sol trop proche de la zone précédente")
			end
		end)

		T.it("borne chaque zone par le début de la suivante, la dernière par la longueur de la piste", function()
			for i = 1, #Zones.LIST - 1 do
				T.expectEqual(Zones.finish(i, GameConfig.COURSE_LENGTH), Zones.LIST[i + 1].start)
			end
			T.expectEqual(Zones.finish(#Zones.LIST, GameConfig.COURSE_LENGTH), GameConfig.COURSE_LENGTH)
		end)
	end)
end
