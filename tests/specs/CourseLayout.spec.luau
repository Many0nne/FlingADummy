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
				-- Entrée de 10 studs au milieu du côté de la base : l'appareil ne la couvre pas, sans quitter la base
				local beside = math.abs(station.X - base.X) - podium
				T.expect(beside >= 5, "entrée libre, obtenu " .. beside)
				T.expect(math.abs(station.X - base.X) + podium <= half.X, "le long de la base")
				T.expect(station.Z > base.Z, "du côté de l'entrée (la bande)")
				T.expectEqual(facing, CourseLayout.ENTRANCE, "avatar face à la bande")
				local gap = station.Z - podium - CourseLayout.BASE_FRONT
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

		T.it("donne à chaque joueur sa base, en rangée face à la bande, dans le hub, sans chevauchement", function()
			local half = CourseLayout.BASE_SIZE / 2
			for index = 1, count do
				local base = CourseLayout.basePosition(index)
				T.expectEqual(base.Z, CourseLayout.basePosition(1).Z, "bases sur une rangée")
				T.expect(base.X * CourseLayout.slotX(index) > 0, "base du côté de la place " .. index)
				if index > 1 then
					local gap = base.X - CourseLayout.basePosition(index - 1).X - 2 * half.X
					T.expect(gap >= 6 and gap <= 12, "côte à côte avec un passage, obtenu " .. gap)
				end
				T.expectEqual(base.Z + half.Z, CourseLayout.BASE_FRONT, "entrée sur la clôture avant")
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
				T.expectEqual(#displays, CourseLayout.DISPLAY_MAX)
				for _, position in displays do
					T.expect(math.abs(position.X - base.X) < half.X - 3, "présentoir dans la base (x)")
					T.expect(math.abs(position.Z - base.Z) < half.Z - 3, "présentoir dans la base (z)")
				end
			end
		end)

		-- Cette méthode permet de savoir si deux emprises au sol se touchent à moins de `margin` studs lorsque l'on
		-- vérifie le plan du hub.
		local function overlap(a, b, margin: number): boolean
			return math.abs(a.center.X - b.center.X) < (a.size.X + b.size.X) / 2 + margin
				and math.abs(a.center.Z - b.center.Z) < (a.size.Z + b.size.Z) / 2 + margin
		end

		T.it(
			"ne fait se chevaucher ni bases, ni appareils, ni pads, ni stands, ni tableaux, ni zone d'événement",
			function()
				local list = CourseLayout.hubFootprints()
				T.expectEqual(#list, 4 * count + 2 + 3 + 1, "tout est listé")
				for i = 1, #list do
					for j = i + 1, #list do
						-- 2 studs de passage au moins entre deux éléments
						T.expect(not overlap(list[i], list[j], 2), list[i].name .. " / " .. list[j].name)
					end
				end
			end
		)

		T.it("garde tout dans le hub, hors de la bande", function()
			local halfW = GameConfig.HUB_WIDTH / 2
			for _, item in CourseLayout.hubFootprints() do
				local half = item.size / 2
				T.expect(math.abs(item.center.X) + half.X <= halfW, item.name .. " dans la largeur du hub")
				T.expect(item.center.Z + half.Z <= CourseLayout.HUB_FRONT, item.name .. " derrière la bande")
				T.expect(item.center.Z - half.Z >= CourseLayout.HUB_BACK, item.name .. " dans la profondeur du hub")
			end
		end)

		T.it(
			"met les stands à gauche de la bande, les tableaux puis la zone d'événement à droite, contre la paroi",
			function()
				local edge = GameConfig.TRACK_WIDTH / 2
				local byName = {}
				for _, item in CourseLayout.hubFootprints() do
					byName[item.name] = item
				end
				for _, name in { "shop", "sell", "board1", "board2", "board3", "event" } do
					local item = byName[name]
					T.expect(
						CourseLayout.HUB_FRONT - (item.center.Z + item.size.Z / 2) <= 1.5,
						name .. " contre la paroi"
					)
				end
				T.expect(byName.shop.center.X - byName.shop.size.X / 2 > edge, "SHOP à gauche de la bande")
				T.expect(byName.sell.center.X > byName.shop.center.X, "SELL après le SHOP")
				T.expect(byName.board1.center.X + byName.board1.size.X / 2 < -edge, "tableaux à droite de la bande")
				T.expect(byName.board2.center.X < byName.board1.center.X, "INCOME après LONGEST THROW")
				T.expect(byName.board3.center.X < byName.board2.center.X, "REBIRTHS après INCOME")
				T.expect(byName.event.center.X < byName.board3.center.X, "zone d'événement au bout")
				-- Premier stand et premier tableau au ras de la bande (à moins de 4 studs de son bord)
				T.expect(byName.shop.center.X - byName.shop.size.X / 2 - edge < 4, "SHOP au bord de la bande")
				T.expect(-edge - (byName.board1.center.X + byName.board1.size.X / 2) < 4, "tableau au bord de la bande")
			end
		)

		T.it("garde le point d'apparition de secours dégagé, entre les bases et la bande", function()
			local spawn = { name = "spawn", center = CourseLayout.SPAWN, size = Vector3.new(6, 0, 6) }
			for _, item in CourseLayout.hubFootprints() do
				T.expect(not overlap(spawn, item, 2), "apparition hors de " .. item.name)
			end
			T.expect(CourseLayout.SPAWN.Z > CourseLayout.BASE_FRONT, "devant les bases")
		end)
	end)

	T.describe("CourseLayout.isNearBase", function()
		T.it(
			"vrai dans la base et jusqu'à BASE_REACH de sa clôture, faux au-delà et dans les autres bases",
			function()
				local center = CourseLayout.basePosition(1)
				local half = CourseLayout.BASE_SIZE.Z / 2
				T.expect(CourseLayout.isNearBase(1, center), "centre")
				T.expect(
					CourseLayout.isNearBase(1, center + Vector3.new(0, 5, half + CourseLayout.BASE_REACH - 1)),
					"devant l'entrée"
				)
				T.expect(
					not CourseLayout.isNearBase(1, center + Vector3.new(0, 0, half + CourseLayout.BASE_REACH + 1)),
					"loin"
				)
				for index = 2, GameConfig.SLOT_COUNT do
					T.expect(not CourseLayout.isNearBase(1, CourseLayout.basePosition(index)), "base " .. index)
				end
				-- Bases côte à côte : jamais près de la sienne depuis l'intérieur de la voisine
				local neighbour = CourseLayout.basePosition(2)
				local inside = neighbour - Vector3.new(CourseLayout.BASE_SIZE.X / 2 - 0.5, 0, 0)
				T.expect(not CourseLayout.isNearBase(1, inside), "dans la base voisine")
				T.expect(CourseLayout.isNearBase(1, (CourseLayout.stationPosition(1))), "appareil d'entraînement")
				T.expect(CourseLayout.isNearBase(1, (CourseLayout.padPosition(1))), "pad d'achat")
				T.expect(not CourseLayout.isNearBase(1, Vector3.new(0, 0, -8)), "bande de lancer")
			end
		)
	end)

	T.describe("CourseLayout.displayPositions / padPosition", function()
		T.it(
			"présentoirs écartés les uns des autres, en rangées depuis l'entrée, remplies du milieu (#156)",
			function()
				local center = CourseLayout.basePosition(1)
				local displays = CourseLayout.displayPositions(1, CourseLayout.DISPLAY_ROOM)
				T.expectEqual(#displays, CourseLayout.DISPLAY_ROOM)
				T.expectEqual(displays[1].X, center.X, "le premier face à l'entrée")
				T.expectEqual(displays[1].Z, CourseLayout.BASE_FRONT - CourseLayout.DISPLAY_FIRST_ROW)
				local gap = CourseLayout.DISPLAY_PITCH.X - CourseLayout.PEDESTAL_SIZE
				T.expect(gap >= 3, "passage entre deux socles, obtenu " .. gap)
				for i = 1, #displays do
					for j = i + 1, #displays do
						T.expect(
							(displays[i] - displays[j]).Magnitude >= 7,
							string.format("présentoirs %d et %d", i, j)
						)
					end
				end
				-- Base neuve : une rangée pleine et le milieu de la suivante, symétrique autour de l'entrée
				local sum = 0
				for i = 1, GameConfig.DISPLAY_START do
					sum += displays[i].X - center.X
				end
				T.expect(math.abs(sum) < 1e-6, "présentoirs de départ centrés, décalage " .. sum)
				-- Mêmes emplacements quel que soit le nombre demandé : un présentoir acheté ne déplace aucun autre
				local built = CourseLayout.displayPositions(1)
				for i, position in built do
					T.expectEqual(position, displays[i])
				end
			end
		)
		T.it(
			"la base tient DISPLAY_MAX présentoirs, le hub la place prévue pour DISPLAY_ROOM (#156, #160)",
			function()
				T.expectEqual(CourseLayout.BASE_SIZE.Z, CourseLayout.baseDepthFor(CourseLayout.DISPLAY_MAX))
				local depth = CourseLayout.baseDepthFor(CourseLayout.DISPLAY_ROOM)
				T.expect(CourseLayout.BASE_FRONT - depth >= CourseLayout.HUB_BACK + 2, "base agrandie dans le hub")
				local half = CourseLayout.BASE_SIZE.X / 2
				for index = 1, count do
					local center = CourseLayout.basePosition(index)
					for _, position in CourseLayout.displayPositions(index, CourseLayout.DISPLAY_ROOM) do
						local edge = math.abs(position.X - center.X) + CourseLayout.PEDESTAL_SIZE / 2
						T.expect(edge <= half - 2, "socle loin de la clôture de côté, obtenu " .. edge)
						T.expect(position.Z >= CourseLayout.BASE_FRONT - depth + 3, "dans la base agrandie")
					end
				end
			end
		)
		T.it(
			"la base a la profondeur de ses rangées ouvertes, entrée fixe, dans la place prévue du hub (#212)",
			function()
				local columns = CourseLayout.DISPLAY_COLUMNS
				T.expectEqual(CourseLayout.baseRows(1), 1)
				T.expectEqual(CourseLayout.baseRows(columns), 1)
				T.expectEqual(CourseLayout.baseRows(columns + 1), 2, "une rangée de plus au présentoir suivant")
				T.expectEqual(
					CourseLayout.baseRows(CourseLayout.DISPLAY_ROOM + 50),
					math.ceil(CourseLayout.DISPLAY_ROOM / columns)
				)
				-- Base neuve : DISPLAY_START par défaut
				local _, start = CourseLayout.baseBox(1)
				T.expectEqual(start.Z, CourseLayout.baseDepthFor(GameConfig.DISPLAY_START))
				local footprints = CourseLayout.hubFootprints()
				local previous = 0
				for _, displays in { 5, 6, 8, 30, 40 } do
					for index = 1, count do
						local center, size = CourseLayout.baseBox(index, displays)
						local label = string.format("base %d à %d présentoirs", index, displays)
						T.expectNear(center.Z + size.Z / 2, CourseLayout.BASE_FRONT, 1e-6, label .. " : entrée fixe")
						T.expectEqual(size.X, CourseLayout.BASE_SIZE.X, label)
						T.expectEqual(
							size.Z,
							CourseLayout.baseDepthFor(CourseLayout.baseRows(displays) * columns),
							label
						)
						T.expect(center.Z - size.Z / 2 >= CourseLayout.HUB_BACK + 2, label .. " : dans le hub")
						T.expect(
							math.abs(center.X) + size.X / 2 <= GameConfig.HUB_WIDTH / 2,
							label .. " : largeur du hub"
						)
						-- Ses présentoirs dedans, loin de la clôture du fond
						local positions =
							CourseLayout.displayPositions(index, math.min(displays, CourseLayout.DISPLAY_ROOM))
						for _, position in positions do
							local back = position.Z - CourseLayout.PEDESTAL_SIZE / 2 - (center.Z - size.Z / 2)
							T.expect(back >= 3, label .. " : socle loin du fond, obtenu " .. back)
						end
						-- Ni appareil, ni pad, ni stands, ni autre base (à sa profondeur maximale)
						for _, item in footprints do
							if item.name == "base" .. index then
								continue
							end
							local apart = math.abs(item.center.X - center.X) >= (item.size.X + size.X) / 2
								or math.abs(item.center.Z - center.Z) >= (item.size.Z + size.Z) / 2
							T.expect(apart, label .. " : hors de " .. item.name)
						end
					end
					local _, size = CourseLayout.baseBox(1, displays)
					T.expect(size.Z >= previous, "la base ne rétrécit pas quand on achète")
					previous = size.Z
				end
				-- 5 : une rangée ; 6 : deux ; 30 : six ; 40 (Big Base) : huit
				T.expectEqual(select(2, CourseLayout.baseBox(1, 5)).Z, CourseLayout.baseDepthFor(5))
				T.expect(
					select(2, CourseLayout.baseBox(1, 6)).Z > select(2, CourseLayout.baseBox(1, 5)).Z,
					"6 : rangée 2"
				)
				T.expectEqual(select(2, CourseLayout.baseBox(1, 30)).Z, CourseLayout.BASE_SIZE.Z)
				T.expectEqual(
					select(2, CourseLayout.baseBox(1, 40)).Z,
					CourseLayout.baseDepthFor(CourseLayout.DISPLAY_ROOM)
				)
			end
		)
		T.it("près de la base : suit sa profondeur du moment (#212)", function()
			local center, size = CourseLayout.baseBox(1, 5)
			local behind = Vector3.new(center.X, 0, center.Z - size.Z / 2 - CourseLayout.BASE_REACH - 2)
			T.expect(not CourseLayout.isNearBase(1, behind, 5), "derrière une base d'une rangée : loin")
			T.expect(CourseLayout.isNearBase(1, behind, CourseLayout.DISPLAY_ROOM), "dans la base agrandie : près")
		end)
		T.it("pad devant la base, hors de la clôture, à côté de l'entrée, loin de l'appareil", function()
			for index = 1, count do
				local pad, facing = CourseLayout.padPosition(index)
				local base = CourseLayout.basePosition(index)
				local station = CourseLayout.stationPosition(index)
				T.expect(pad.Z - base.Z > CourseLayout.BASE_SIZE.Z / 2, "hors de la base, côté entrée")
				T.expect(CourseLayout.isNearBase(index, pad), "près de la base")
				T.expect(math.abs(pad.X - base.X) > 5, "pas devant l'entrée")
				T.expect((pad - station).Magnitude > 15, "loin de l'appareil")
				T.expectEqual(facing, CourseLayout.ENTRANCE)
			end
		end)
	end)

	T.describe("CourseLayout.gearPadPosition", function()
		T.it("pad d'amélioration à côté de l'appareil, côté extérieur, hors de l'avant des marches", function()
			for index = 1, count do
				local pad, facing = CourseLayout.gearPadPosition(index)
				local station = CourseLayout.stationPosition(index)
				local base = CourseLayout.basePosition(index)
				T.expect(pad.X - base.X > station.X - base.X, "au-delà de l'appareil, côté extérieur")
				T.expect(pad.X - station.X > CourseLayout.STATION_SIZE / 2, "pas devant les marches")
				T.expect((pad - station).Magnitude < 14, "près de l'appareil")
				T.expect(pad.Z - base.Z > CourseLayout.BASE_SIZE.Z / 2, "hors de la base, côté entrée")
				T.expectEqual(facing, CourseLayout.ENTRANCE)
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
