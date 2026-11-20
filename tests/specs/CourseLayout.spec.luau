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
		T.it("aligne SLOT_COUNT places côte à côte, centrées sur la piste et dans la zone de lancer", function()
			T.expectEqual(count, 4)
			local sum = 0
			for index = 1, count do
				local pad = CourseLayout.padPosition(index)
				sum += pad.X
				T.expectEqual(pad.Z, GameConfig.PAD_Z)
				T.expect(
					pad.Z - GameConfig.PAD_RADIUS >= -GameConfig.LAUNCH_DEPTH and pad.Z + GameConfig.PAD_RADIUS <= 0,
					"pastille dans la zone de lancer"
				)
				T.expect(math.abs(pad.X) + GameConfig.PAD_RADIUS <= GameConfig.TRACK_WIDTH / 2, "pastille sur la piste")
				if index > 1 then
					local gap = pad.X - CourseLayout.padPosition(index - 1).X
					T.expect(gap >= 2 * GameConfig.PAD_RADIUS + 2, "pastilles séparées")
				end
			end
			T.expect(math.abs(sum) < 1e-6, "places centrées")
		end)

		T.it("place l'appareil d'entraînement devant l'entrée de la base, au milieu, passage libre", function()
			local half = CourseLayout.BASE_SIZE / 2
			local podium = CourseLayout.STATION_SIZE / 2
			for index = 1, count do
				local station, facing = CourseLayout.stationPosition(index)
				local base = CourseLayout.basePosition(index)
				local side = CourseLayout.entranceSide(index)
				T.expectEqual(station.Z, base.Z, "au milieu de l'entrée")
				T.expectEqual(math.sign(station.X - base.X), side, "du côté de l'entrée (centre du hub)")
				T.expect(-side * base.X > 0, "entrée tournée vers le centre du hub")
				T.expectEqual(facing, Vector3.new(side, 0, 0), "avatar face au centre du hub")
				local gap = math.abs(station.X - base.X) - half.X - podium
				T.expect(gap >= 4, "passage libre entre l'appareil et la clôture, obtenu " .. gap)
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
