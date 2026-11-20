-- Objectifs : choix du texte et de la cible, cible suivie par le joueur, chevrons au sol.
return function(T, Loader)
	local Objectives = Loader.new():require("src/shared/Objectives")

	-- Cette méthode permet de construire un état de joueur (prêt, rien à acheter) modifié par `patch` lorsqu'un test
	-- choisit un objectif.
	local function state(patch: { [string]: any }?)
		local s = {
			action = nil,
			laneState = "Ready",
			thrown = false,
			levelsThisSession = 0,
			canBuyGear = false,
			canBuyDummy = false,
		}
		for key, value in patch or {} do
			s[key] = value
		end
		return s
	end

	T.describe("Objectives.pick", function()
		T.it("commence par lancer, puis alterne entraînement et lancer", function()
			T.expectEqual(Objectives.pick(state()).id, "Throw")
			T.expectEqual(Objectives.pick(state()).target, "Throw")
			T.expectEqual(Objectives.pick(state({ thrown = true })).id, "Train")
			T.expectEqual(Objectives.pick(state({ thrown = true })).target, "Train")
		end)
		T.it("se tait pendant la jauge, le vol et le résultat", function()
			T.expectEqual(Objectives.pick(state({ action = "Holding" })), nil)
			T.expectEqual(Objectives.pick(state({ laneState = "Flying" })), nil)
			T.expectEqual(Objectives.pick(state({ laneState = "Result", canBuyGear = true })), nil)
		end)
		T.it("propose STOP après un niveau gagné à l'entraînement, rien avant", function()
			T.expectEqual(Objectives.pick(state({ action = "Training" })), nil)
			local stop = Objectives.pick(state({ action = "Training", levelsThisSession = 1 }))
			T.expectEqual(stop.id, "Stop")
			T.expectEqual(stop.button, "Stop")
			T.expectEqual(stop.target, nil)
		end)
		T.it("fait acheter l'équipement, puis le mannequin, avant de relancer", function()
			local both = Objectives.pick(state({ thrown = true, canBuyGear = true, canBuyDummy = true }))
			T.expectEqual(both.id, "BuyGear")
			T.expectEqual(both.button, "Shop")
			T.expectEqual(Objectives.pick(state({ canBuyDummy = true })).button, "Dummies")
		end)
		T.it("textes en anglais du brief", function()
			T.expectEqual(Objectives.pick(state()).text, "Throw your dummy!")
			T.expectEqual(Objectives.pick(state({ thrown = true })).text, "Train!")
			T.expectEqual(Objectives.pick(state({ canBuyDummy = true })).text, "Buy a better dummy!")
		end)
	end)

	T.describe("Objectives.chooseTarget", function()
		local mine = { position = Vector3.new(100, 0, 0), lane = 2 }
		local other = { position = Vector3.new(1, 0, 0), lane = 3 }
		local private = { position = Vector3.new(2, 0, 0), owner = 99 }
		local sharedNear = { position = Vector3.new(10, 0, 0) }
		local sharedFar = { position = Vector3.new(50, 0, 0) }
		T.it("ignore les cibles des autres couloirs et des autres joueurs", function()
			T.expectEqual(Objectives.chooseTarget({ other, private, mine }, 2, 1, Vector3.zero), mine)
		end)
		T.it("prend la plus proche des cibles ouvertes", function()
			T.expectEqual(Objectives.chooseTarget({ sharedFar, sharedNear, mine }, 2, 1, Vector3.zero), sharedNear)
			T.expectEqual(Objectives.chooseTarget({ private, sharedNear }, nil, 99, Vector3.zero), private)
		end)
		T.it("rien si aucune cible n'est ouverte", function()
			T.expectEqual(Objectives.chooseTarget({ other, private }, 2, 1, Vector3.zero), nil)
			T.expectEqual(Objectives.chooseTarget({}, 2, 1, Vector3.zero), nil)
		end)
	end)

	T.describe("Objectives.chevrons", function()
		T.it("espace les chevrons entre les deux marges, au sol, vers la cible", function()
			local points = Objectives.chevrons(Vector3.new(0, 0, 0), Vector3.new(0, 4, 20), 4, 2, 0, 10)
			T.expectEqual(#points, 5) -- 2, 6, 10, 14, 18
			T.expectNear(points[1].Z, 2)
			T.expectNear(points[5].Z, 18)
			T.expectNear(points[5].Y, 3.6)
			T.expectNear(points[3].X, 0)
		end)
		T.it("défile avec la phase et respecte le maximum", function()
			local points = Objectives.chevrons(Vector3.zero, Vector3.new(20, 0, 0), 4, 2, 0.5, 3)
			T.expectEqual(#points, 3)
			T.expectNear(points[1].X, 4)
		end)
		T.it("aucun chevron quand la cible est toute proche", function()
			T.expectEqual(#Objectives.chevrons(Vector3.zero, Vector3.new(3, 0, 0), 4, 2, 0, 10), 0)
		end)
	end)
end
