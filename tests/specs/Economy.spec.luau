-- Économie du lancer : vitesse selon la Throw Power, CHANCE gagnée en vol (zones, os, casse) ; le lancer ne paie rien.
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Laps = loader:require("src/shared/Laps")
	local Zones = loader:require("src/shared/Zones")

	T.describe("Economy.launchSpeed", function()
		T.it("vaut la vitesse de base à la puissance de départ (et en dessous)", function()
			T.expectNear(Economy.launchSpeed(GameConfig.START_POWER), GameConfig.SPEED_BASE)
			T.expectNear(Economy.launchSpeed(0), GameConfig.SPEED_BASE)
		end)
		T.it("gagne SPEED_PER_LOG à chaque facteur e de puissance", function()
			local power = GameConfig.START_POWER * math.exp(2)
			T.expectNear(Economy.launchSpeed(power), GameConfig.SPEED_BASE + 2 * GameConfig.SPEED_PER_LOG, 1e-6)
		end)
		T.it("croît de moins en moins vite : ×10 de puissance donne le même gain jusqu'au coude", function()
			local knee = GameConfig.SPEED_KNEE_POWER
			local a = Economy.launchSpeed(100) - Economy.launchSpeed(10)
			local b = Economy.launchSpeed(knee) - Economy.launchSpeed(knee / 10)
			T.expectNear(a, b, 1e-6)
		end)
		T.it("au-delà du coude, SPEED_PER_LOG_FAR par facteur e, sans saut (#157)", function()
			local knee = GameConfig.SPEED_KNEE_POWER
			local atKnee = GameConfig.SPEED_BASE + GameConfig.SPEED_PER_LOG * math.log(knee / GameConfig.START_POWER)
			T.expectNear(Economy.launchSpeed(knee), atKnee, 1e-6)
			T.expectNear(Economy.launchSpeed(knee * math.exp(3)), atKnee + 3 * GameConfig.SPEED_PER_LOG_FAR, 1e-6)
			T.expect(GameConfig.SPEED_PER_LOG_FAR < GameConfig.SPEED_PER_LOG, "moins pentue après le coude")
		end)
	end)

	T.describe("Economy.zoneChance", function()
		T.it("vaut la chance de la zone à son entrée", function()
			T.expectNear(Economy.zoneChance(0), 1)
			for _, zone in Zones.LIST do
				T.expectNear(Economy.zoneChance(zone.start), zone.chance, 1e-9)
			end
		end)
		T.it("monte en continu vers la zone suivante (bannière qui grimpe en vol)", function()
			local a, b = Zones.LIST[1], Zones.LIST[2]
			T.expectNear(Economy.zoneChance((a.start + b.start) / 2), (a.chance + b.chance) / 2, 1e-9)
			local previous = 0
			for d = 0, GameConfig.COURSE_LENGTH, 25 do
				local value = Economy.zoneChance(d)
				T.expect(value >= previous, "croissante à " .. d .. " m")
				previous = value
			end
		end)
		T.it("atteint FINAL_CHANCE au bout de la piste et n'est jamais sous 1", function()
			T.expectNear(Economy.zoneChance(GameConfig.COURSE_LENGTH), Zones.FINAL_CHANCE, 1e-9)
			T.expectNear(Economy.zoneChance(-50), 1)
		end)
		T.it(
			"continue de monter au-delà du bout, tours du portail compris (#224) : × CHANCE_PER_LAP par tour",
			function()
				local length = GameConfig.COURSE_LENGTH
				T.expectNear(Economy.zoneChance(length + 1e-6), Zones.FINAL_CHANCE, 1e-6)
				T.expectNear(Economy.zoneChance(2 * length), Zones.FINAL_CHANCE * Laps.CHANCE_PER_LAP, 1e-9)
				T.expectNear(Economy.zoneChance(2.5 * length), Zones.FINAL_CHANCE * Laps.CHANCE_PER_LAP ^ 1.5, 1e-9)
				local previous = 0
				for d = length - 600, 4 * length, 50 do
					local value = Economy.zoneChance(d)
					T.expect(value >= previous, "croissante à " .. d .. " m")
					previous = value
				end
			end
		)
		T.it("garde la courbe d'avant #97 jusqu'à 2,4 km (Moon Base de × 10 à × 18), puis × 60 à 6 km", function()
			-- Ancienne courbe : Moon Base de 1 650 m (× 10) au bout de la piste de 2,4 km (× 18)
			for d = 1650, 2400, 50 do
				T.expectNear(Economy.zoneChance(d), 10 + 8 * (d - 1650) / 750, 1e-9)
			end
			T.expectNear(Economy.zoneChance(3600), 27, 1e-9)
			T.expectNear(Economy.zoneChance(4800), 40, 1e-9)
			T.expectNear(Economy.zoneChance(6000), 60, 1e-9)
		end)
	end)

	T.describe("Economy.chance", function()
		T.it(
			"premier lancer (≈ 145 m, rien de cassé) : ≈ 1.3X comme la référence 09 (1.22X à 1.36X)",
			function()
				local c = Economy.chance({ distance = 145, bones = 0, smashed = 0 })
				T.expect(c.total > 1.15 and c.total < 1.45, "chance " .. c.total)
				T.expectEqual(c.distance, 145)
				T.expectEqual(c.zone, 3) -- Forest : un premier lancer traverse 3 thèmes (#33)
			end
		)
		T.it("os et casse ajoutent un bonus proportionnel", function()
			local base = Economy.chance({ distance = 0, bones = 0, smashed = 0 })
			local crash = Economy.chance({ distance = 0, bones = 5, smashed = 10 })
			T.expectNear(base.total, 1)
			T.expectNear(crash.bonesBonus, 5 * GameConfig.CHANCE_PER_BONE)
			T.expectNear(crash.smashBonus, 10 * GameConfig.CHANCE_PER_SMASH)
			local expected = 1 + 5 * GameConfig.CHANCE_PER_BONE + 10 * GameConfig.CHANCE_PER_SMASH
			T.expectNear(crash.total, math.floor(expected * 100 + 0.5) / 100)
		end)
		T.it("le bonus multiplie la chance des zones", function()
			local far = Economy.chance({ distance = Zones.LIST[3].start, bones = 10, smashed = 0 })
			local expected = Zones.LIST[3].chance * (1 + 10 * GameConfig.CHANCE_PER_BONE)
			T.expectNear(far.total, math.floor(expected * 100 + 0.5) / 100)
		end)
		T.it("le lancer ne rapporte aucun argent (pas de montant dans le résultat)", function()
			local c: any = Economy.chance({ distance = 900, bones = 12, smashed = 30 })
			T.expectEqual(c.money, nil)
			T.expectEqual(c.payout, nil)
			T.expectEqual(Economy.payout, nil)
		end)
		T.it("le service des lancers ne touche jamais à Money (seule la base verse de l'argent)", function()
			local fs = require("@lune/fs")
			local source = fs.readFile("src/server/LaunchService.luau")
			T.expect(not string.find(source, "addMoney", 1, true), "LaunchService appelle addMoney")
			T.expect(not string.find(source, '"Money"', 1, true), "LaunchService écrit l'attribut Money")
		end)
	end)
end
