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

	T.describe("Zones.LIST", function()
		T.it("compte une douzaine de thèmes, dans l'ordre, sur la piste", function()
			T.expect(#Zones.LIST >= 11 and #Zones.LIST <= 13, "thèmes : " .. #Zones.LIST)
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
