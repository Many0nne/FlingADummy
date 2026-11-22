-- Entraînement : niveaux de répétitions, paliers d'équipement, zones de la piste.
return function(T, Loader)
	local loader = Loader.new()
	local Training = loader:require("src/shared/Training")
	local Zones = loader:require("src/shared/Zones")
	local GameConfig = loader:require("src/shared/GameConfig")

	T.describe("Training.expForLevel", function()
		T.it("démarre à LEVEL_BASE_EXP et ne décroît jamais", function()
			T.expectEqual(Training.expForLevel(1), GameConfig.LEVEL_BASE_EXP)
			for level = 1, 40 do
				T.expect(Training.expForLevel(level + 1) >= Training.expForLevel(level), "niveau " .. level)
			end
		end)
		T.it(
			"plafonnée à LEVEL_MAX_REPS répétitions de l'équipement (#15 : un niveau ne dure jamais longtemps)",
			function()
				for tier = 1, #Training.GEARS do
					local gain = Training.GEARS[tier].gain
					for _, level in { 1, 10, 30, 100, 1000 } do
						local needed = Training.expForLevel(level, tier)
						T.expect(
							needed <= GameConfig.LEVEL_MAX_REPS * gain,
							string.format("palier %d niveau %d", tier, level)
						)
					end
					T.expectEqual(Training.expForLevel(1000, tier), GameConfig.LEVEL_MAX_REPS * gain)
				end
				-- Niveau 30 au bois : 594 répétitions (≈ 8 min) avant #15, LEVEL_MAX_REPS (≈ 10 s) maintenant
				local progress = { level = 30, exp = 0 }
				local reps = 0
				repeat
					local power
					progress, power = Training.completeRep(progress, 1)
					reps += 1
				until power > 0
				T.expectEqual(reps, GameConfig.LEVEL_MAX_REPS)
			end
		)
	end)

	T.describe("Training.completeRep (EXP de l'équipement, puissance au niveau)", function()
		-- Cette méthode permet de faire `count` répétitions avec le palier `tier` lorsqu'un test simule une séance ;
		-- renvoie la progression et la Throw Power versée au total.
		local function train(progress, tier, count)
			local total = 0
			for _ = 1, count do
				local power
				progress, power = Training.completeRep(progress, tier)
				total += power
			end
			return progress, total
		end

		T.it("chaque répétition donne l'EXP de l'équipement, sans puissance avant le niveau", function()
			local progress, power = Training.completeRep({ level = 1, exp = 0 }, 1)
			T.expectEqual(progress.exp, Training.GEARS[1].gain, "EXP du bois")
			T.expectEqual(power, 0)
			progress, power = Training.completeRep({ level = 10, exp = 0 }, 2)
			T.expectEqual(progress.exp, Training.GEARS[2].gain, "EXP de la pierre")
			T.expectEqual(progress.level, 10)
			T.expectEqual(power, 0)
		end)
		T.it("le niveau franchi verse l'EXP qu'il demandait en Throw Power, barre vidée", function()
			local needed = Training.expForLevel(1)
			local progress, total = train({ level = 1, exp = 0 }, 1, needed)
			T.expectEqual(progress.level, 2)
			T.expectEqual(progress.exp, 0, "barre vidée")
			T.expectEqual(total, needed)
		end)
		T.it("un meilleur équipement remplit les niveaux plus vite et reporte l'EXP en trop", function()
			-- Fer : une répétition franchit plusieurs niveaux d'un coup, l'EXP en trop est reportée sur le suivant
			local progress, power = Training.completeRep({ level = 1, exp = 0 }, 3)
			local gain, level, spent = Training.GEARS[3].gain, 1, 0
			while spent + Training.expForLevel(level, 3) <= gain do
				spent += Training.expForLevel(level, 3)
				level += 1
			end
			T.expect(level >= 3, "plusieurs niveaux d'un coup")
			T.expectEqual(progress.level, level, "niveaux franchis")
			T.expectEqual(progress.exp, gain - spent, "EXP reportée")
			T.expectEqual(power, spent)
			local _, woodPower = train({ level = 1, exp = 0 }, 1, 20)
			local _, ironPower = train({ level = 1, exp = 0 }, 3, 20)
			T.expect(ironPower > 5 * woodPower, "le fer rapporte bien plus que le bois")
		end)
		T.it("garde le rythme : puissance + EXP en cours = gain de l'équipement × répétitions", function()
			for _, tier in { 1, 2, 4, #Training.GEARS } do
				local progress, total = train({ level = 1, exp = 0 }, tier, 50)
				T.expectEqual(total + progress.exp, Training.GEARS[tier].gain * 50, "palier " .. tier)
			end
		end)
	end)

	T.describe("Training.GEARS", function()
		T.it("premier palier offert, prix et EXP par répétition strictement croissants", function()
			T.expectEqual(Training.GEARS[1].cost, 0)
			for tier = 2, #Training.GEARS do
				T.expect(Training.GEARS[tier].cost > Training.GEARS[tier - 1].cost, "prix du palier " .. tier)
				T.expect(Training.GEARS[tier].gain > Training.GEARS[tier - 1].gain, "gain du palier " .. tier)
			end
		end)
		T.it("nextGearCost donne le prix du palier suivant, nil au dernier", function()
			T.expectEqual(Training.nextGearCost(1), Training.GEARS[2].cost)
			T.expectEqual(Training.nextGearCost(#Training.GEARS), nil)
		end)
		T.it("gear borne le palier", function()
			T.expectEqual(Training.gear(0), Training.GEARS[1])
			T.expectEqual(Training.gear(99), Training.GEARS[#Training.GEARS])
		end)
		T.it(
			"prolongé (#94) : les 7 paliers d'origine, puis gain × GAIN_STEP et le prix de sa ligne de EXTENDED",
			function()
				T.expectEqual(#Training.GEARS, 7 + #Training.EXTENDED)
				T.expectEqual(Training.GEARS[7].name, "Cosmic Dummy")
				T.expectEqual(Training.GEARS[7].gain, 35000)
				for tier = 8, #Training.GEARS do
					local gear, before = Training.GEARS[tier], Training.GEARS[tier - 1]
					T.expect(math.abs(gear.gain / before.gain / Training.GAIN_STEP - 1) < 0.05, gear.name .. " gain")
					T.expectEqual(gear.cost, Training.EXTENDED[tier - 7].cost, gear.name .. " prix")
					T.expect(gear.scale <= 0.9, gear.name .. " : soulevé sans traverser la tête")
				end
			end
		)
	end)

	T.describe("Zones", function()
		T.it("première zone à 0 m, chances croissantes", function()
			T.expectEqual(Zones.LIST[1].start, 0)
			for i = 2, #Zones.LIST do
				T.expect(Zones.LIST[i].start > Zones.LIST[i - 1].start, "début croissant")
				T.expect(Zones.LIST[i].chance > Zones.LIST[i - 1].chance, "chance croissante")
			end
		end)
		T.it("indexAt trouve la zone atteinte, bornes incluses", function()
			T.expectEqual(Zones.indexAt(0), 1)
			T.expectEqual(Zones.indexAt(Zones.LIST[2].start - 1), 1)
			T.expectEqual(Zones.indexAt(Zones.LIST[2].start), 2)
			T.expectEqual(Zones.indexAt(1e9), #Zones.LIST)
			T.expectEqual(Zones.at(Zones.LIST[3].start + 1), Zones.LIST[3])
		end)
	end)
end
