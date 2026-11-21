-- Thèmes de la piste (#33) : une douzaine de zones courtes au début, CHANCE croissante, obstacles et piège propres à
-- chaque thème.
return function(T, Loader)
	local fs = require("@lune/fs")
	local loader = Loader.new()
	local Zones = loader:require("src/shared/Zones")
	local Traps = loader:require("src/shared/Traps")
	local GameConfig = loader:require("src/shared/GameConfig")

	-- Obstacles connus : `builders.<Nom> =` dans Server.ThemeObstacles
	local known = {}
	for name in string.gmatch(fs.readFile("src/server/ThemeObstacles.luau"), "builders%.(%w+) =") do
		known[name] = true
	end

	-- Pièges habillés : `builders.<Nom> =` dans Server.TrapProps
	local dressed = {}
	for name in string.gmatch(fs.readFile("src/server/TrapProps.luau"), "builders%.(%w+) =") do
		dressed[name] = true
	end
	local Damage = loader:require("src/shared/Damage")

	T.describe("Zones.LIST (habillage)", function()
		T.it("habille le piège de chaque thème et nomme la cause de chaque crash (obstacles, piège)", function()
			for _, zone in Zones.LIST do
				T.expect(dressed[zone.trap], zone.name .. " : piège sans habillage " .. zone.trap)
				T.expect(Damage.CAUSE_LABELS[zone.trap] ~= nil, zone.name .. " : cause du piège " .. zone.trap)
				for _, name in zone.obstacles do
					T.expect(Damage.CAUSE_LABELS[name] ~= nil, zone.name .. " : cause de l'obstacle " .. name)
				end
			end
		end)
	end)

	T.describe("Zones.LIST", function()
		T.it("compte douze thèmes jusqu'à 2,4 km et six de plus jusqu'à 6 km, dans l'ordre, sur la piste", function()
			T.expectEqual(#Zones.LIST, 18)
			T.expectEqual(GameConfig.COURSE_LENGTH, 6000)
			T.expectEqual(Zones.LIST[1].start, 0)
			for i = 2, #Zones.LIST do
				T.expect(Zones.LIST[i].start > Zones.LIST[i - 1].start, Zones.LIST[i].name .. " après la précédente")
			end
			T.expect(Zones.LIST[#Zones.LIST].start < GameConfig.COURSE_LENGTH, "dernière zone sur la piste")
		end)

		T.it("change de thème tous les 60 à 150 m sur les 1 000 premiers mètres", function()
			local inFirstKm = 0
			for i = 1, #Zones.LIST - 1 do
				local zone = Zones.LIST[i]
				if zone.start < 1000 then
					inFirstKm += 1
					-- Longueur entière au moins 60 m ; part dans le premier kilomètre au plus 150 m
					local length = Zones.LIST[i + 1].start - zone.start
					local firstKm = math.min(Zones.LIST[i + 1].start, 1000) - zone.start
					T.expect(length >= 60 and firstKm <= 150, zone.name .. " : " .. length .. " m")
				end
			end
			T.expect(inFirstKm >= 8, "thèmes avant 1 km : " .. inFirstKm)
		end)

		T.it("garde la Moon Base de 1 650 à 2 400 m, puis un thème tous les 600 m jusqu'au bout (#97)", function()
			local moon = Zones.LIST[12]
			T.expectEqual(moon.name, "Moon Base")
			T.expectEqual(moon.start, 1650)
			T.expectEqual(moon.chance, 10)
			local names = { "Mars", "Crystal Cave", "Neon City", "Sky Kingdom", "Haunted Castle", "Galaxy" }
			for k, name in names do
				local zone = Zones.LIST[12 + k]
				T.expectEqual(zone.name, name)
				T.expectEqual(zone.start, 2400 + (k - 1) * 600)
			end
			T.expectEqual(Zones.finish(#Zones.LIST, GameConfig.COURSE_LENGTH) - Zones.LIST[#Zones.LIST].start, 600)
		end)

		T.it("monte la CHANCE de × 18 à × 60 sur la piste prolongée (× 27 à 3,6 km, × 40 à 4,8 km)", function()
			T.expectEqual(Zones.at(2400).chance, 18)
			T.expectEqual(Zones.at(3600).chance, 27)
			T.expectEqual(Zones.at(4800).chance, 40)
			T.expectEqual(Zones.FINAL_CHANCE, 60)
			-- Progression régulière : même rapport (± 5 %) d'un thème au suivant, bout de piste compris
			local ratios = {}
			for i = 13, #Zones.LIST do
				local nextChance = if i < #Zones.LIST then Zones.LIST[i + 1].chance else Zones.FINAL_CHANCE
				table.insert(ratios, nextChance / Zones.LIST[i].chance)
			end
			for _, ratio in ratios do
				T.expect(math.abs(ratio - ratios[1]) / ratios[1] <= 0.05, string.format("rapport %.3f", ratio))
			end
		end)

		T.it("fait monter la CHANCE d'une zone à la suivante, jusqu'à FINAL_CHANCE", function()
			for i = 2, #Zones.LIST do
				T.expect(Zones.LIST[i].chance > Zones.LIST[i - 1].chance, Zones.LIST[i].name .. " : chance croissante")
			end
			T.expect(Zones.FINAL_CHANCE > Zones.LIST[#Zones.LIST].chance, "chance au bout de la piste")
		end)

		T.it("donne à chaque thème 2 ou 3 obstacles connus et un piège signature qui lui est propre", function()
			local traps = {}
			for _, zone in Zones.LIST do
				T.expect(
					#zone.obstacles >= 2 and #zone.obstacles <= 3,
					zone.name .. " : " .. #zone.obstacles .. " obstacles"
				)
				for _, name in zone.obstacles do
					T.expect(known[name], zone.name .. " : obstacle inconnu " .. name)
				end
				T.expect(Traps.KINDS[zone.trap] ~= nil, zone.name .. " : piège inconnu " .. tostring(zone.trap))
				T.expect(not traps[zone.trap], zone.name .. " : piège déjà pris par " .. tostring(traps[zone.trap]))
				traps[zone.trap] = zone.name
			end
		end)

		T.it("garde des noms distincts (bannière et panneaux)", function()
			local seen = {}
			for _, zone in Zones.LIST do
				T.expect(not seen[zone.name], "nom en double : " .. zone.name)
				seen[zone.name] = true
			end
		end)
	end)

	T.describe("Zones.isNight", function()
		T.it("fait tomber la nuit sur la Galaxy seulement, un peu avant son entrée (#97)", function()
			local galaxy = Zones.LIST[#Zones.LIST]
			T.expectEqual(galaxy.name, "Galaxy")
			T.expect(not Zones.isNight(-100), "hub")
			T.expect(not Zones.isNight(galaxy.start - Zones.NIGHT_LEAD - 1), "avant la Galaxy")
			T.expect(Zones.isNight(galaxy.start - Zones.NIGHT_LEAD + 1), "à l'approche")
			T.expect(Zones.isNight(galaxy.start + 300), "dans la Galaxy")
			T.expect(Zones.isNight(GameConfig.COURSE_LENGTH + 40), "au bout")
			for i = 1, #Zones.LIST - 1 do
				T.expect(not Zones.LIST[i].night, Zones.LIST[i].name .. " de jour")
			end
		end)
	end)

	T.describe("Zones.indexAt", function()
		T.it("donne la zone d'une distance, la première avant le départ", function()
			T.expectEqual(Zones.indexAt(-5), 1)
			for i, zone in Zones.LIST do
				T.expectEqual(Zones.indexAt(zone.start), i)
				if i > 1 then
					T.expectEqual(Zones.indexAt(zone.start - 0.01), i - 1)
				end
			end
			T.expectEqual(Zones.indexAt(1e9), #Zones.LIST)
		end)
	end)
end
