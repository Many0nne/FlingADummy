-- Entraînement : niveaux de répétitions, paliers d'équipement, zones de la piste.
return function(T, Loader)
	local loader = Loader.new()
	local Training = loader:require("src/shared/Training")
	local Zones = loader:require("src/shared/Zones")
	local GameConfig = loader:require("src/shared/GameConfig")

	T.describe("Training.repsForLevel", function()
		T.it("démarre à LEVEL_BASE_REPS et ne décroît jamais", function()
			T.expectEqual(Training.repsForLevel(1), GameConfig.LEVEL_BASE_REPS)
			for level = 1, 40 do
				T.expect(Training.repsForLevel(level + 1) >= Training.repsForLevel(level), "niveau " .. level)
			end
		end)
	end)

	T.describe("Training.addRep", function()
		T.it("remplit le niveau puis passe au suivant en remettant les répétitions à zéro", function()
			local progress = { level = 1, reps = 0 }
			local leveled
			for _ = 1, Training.repsForLevel(1) - 1 do
				progress, leveled = Training.addRep(progress)
				T.expect(not leveled, "pas encore de niveau")
			end
			progress, leveled = Training.addRep(progress)
			T.expect(leveled, "niveau franchi")
			T.expectEqual(progress.level, 2)
			T.expectEqual(progress.reps, 0)
		end)
	end)

	T.describe("Training.completeRep (EXP et puissance au niveau)", function()
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

		T.it("chaque répétition donne 1 EXP et aucune puissance tant que le niveau n'est pas franchi", function()
			local progress = { level = 1, reps = 0 }
			for rep = 1, Training.repsForLevel(1) - 1 do
				local power
				progress, power = Training.completeRep(progress, 1)
				T.expectEqual(progress.reps, rep, "EXP après la répétition " .. rep)
				T.expectEqual(progress.level, 1)
				T.expectEqual(power, 0, "pas de puissance avant le niveau")
			end
		end)
		T.it(
			"le niveau franchi verse gain de l'équipement × répétitions du niveau, barre et réserve vidées",
			function()
				for _, tier in { 1, 3, #Training.GEARS } do
					for _, level in { 1, 7 } do
						local needed = Training.repsForLevel(level)
						local progress, total = train({ level = level, reps = 0, bank = 0 }, tier, needed)
						T.expectEqual(progress.level, level + 1, "niveau suivant")
						T.expectEqual(progress.reps, 0, "barre vidée")
						T.expectEqual(progress.bank, 0, "réserve vidée")
						T.expectEqual(
							total,
							Training.GEARS[tier].gain * needed,
							"palier " .. tier .. ", niveau " .. level
						)
					end
				end
			end
		)
		T.it("un équipement acheté en cours de niveau ne compte que pour les répétitions suivantes", function()
			local needed = Training.repsForLevel(4)
			local progress, before = train({ level = 4, reps = 0, bank = 0 }, 2, needed - 1)
			T.expectEqual(before, 0)
			local _, power = Training.completeRep(progress, 5)
			T.expectEqual(power, Training.GEARS[2].gain * (needed - 1) + Training.GEARS[5].gain)
		end)
		T.it("garde le rythme : même puissance par répétition qu'avant (gain × répétitions)", function()
			local progress, total, reps = { level = 1, reps = 0 }, 0, 0
			while progress.level <= 5 do
				local power
				progress, power = Training.completeRep(progress, 2)
				total += power
				reps += 1
			end
			T.expectEqual(total, Training.GEARS[2].gain * reps)
		end)
	end)

	T.describe("Training.GEARS", function()
		T.it("premier palier offert, prix et gains strictement croissants", function()
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
	end)

	T.describe("Zones", function()
		T.it("première zone à 0 m, multiplicateurs croissants", function()
			T.expectEqual(Zones.LIST[1].start, 0)
			for i = 2, #Zones.LIST do
				T.expect(Zones.LIST[i].start > Zones.LIST[i - 1].start, "début croissant")
				T.expect(Zones.LIST[i].multiplier > Zones.LIST[i - 1].multiplier, "multiplicateur croissant")
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
