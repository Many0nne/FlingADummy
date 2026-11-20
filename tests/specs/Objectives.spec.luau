-- Objectifs : choix du texte et de la cible, cible suivie par le joueur, chevrons au sol.
return function(T, Loader)
	local Objectives = Loader.new():require("src/shared/Objectives")

	-- Cette méthode permet de construire un état de joueur (prêt, rien à acheter) modifié par `patch` lorsqu'un test
	-- choisit un objectif.
	local function state(patch: { [string]: any }?)
		local s = {
			action = nil,
			laneState = "Ready",
			step = "Throw",
			canBuyGear = false,
			hasPrize = false,
		}
		for key, value in patch or {} do
			s[key] = value
		end
		return s
	end

	T.describe("Objectives.pick", function()
		T.it("suit l'étape du tutoriel : lancer, puis entraînement", function()
			T.expectEqual(Objectives.pick(state()).id, "Throw")
			T.expectEqual(Objectives.pick(state()).target, "Throw")
			T.expectEqual(Objectives.pick(state({ step = "Train" })).id, "Train")
			T.expectEqual(Objectives.pick(state({ step = "Train" })).target, "Train")
		end)
		T.it("étape équipement : rien tant qu'il n'est pas abordable, puis Shop et sa carte", function()
			T.expectEqual(Objectives.pick(state({ step = "BuyGear", hasPrize = true })), nil)
			local buy = Objectives.pick(state({ step = "BuyGear", canBuyGear = true }))
			T.expectEqual(buy.id, "BuyGear")
			T.expectEqual(buy.button, "Shop")
			T.expectEqual(buy.buy, "Gear")
		end)
		T.it(
			"étape pose : un présentoir libre de sa base quand un mannequin gagné est en main, sinon relancer",
			function()
				local place = Objectives.pick(state({ step = "Place", hasPrize = true }))
				T.expectEqual(place.id, "Place")
				T.expectEqual(place.target, "Place")
				T.expectEqual(place.button, nil)
				T.expectEqual(place.buy, nil)
				T.expectEqual(Objectives.pick(state({ step = "Place" })).id, "Throw")
			end
		)
		T.it("plus aucun objectif une fois le tutoriel fini, même avec un achat possible", function()
			local finished = state({ canBuyGear = true, hasPrize = true })
			finished.step = nil -- (un nil dans `patch` ne remplacerait rien)
			T.expectEqual(Objectives.pick(finished), nil)
		end)
		T.it("se tait pendant la jauge, le vol et le résultat", function()
			T.expectEqual(Objectives.pick(state({ action = "Holding", step = "Throw" })), nil)
			T.expectEqual(Objectives.pick(state({ laneState = "Flying" })), nil)
			T.expectEqual(Objectives.pick(state({ laneState = "Result", step = "BuyGear", canBuyGear = true })), nil)
		end)
		T.it("n'affiche rien pendant la séance d'entraînement (seul le bouton STOP en bas)", function()
			T.expectEqual(Objectives.pick(state({ action = "Training" })), nil)
			T.expectEqual(Objectives.pick(state({ action = "Training", step = "Train" })), nil)
		end)
		T.it("textes en anglais du brief", function()
			T.expectEqual(Objectives.pick(state()).text, "Throw your dummy!")
			T.expectEqual(Objectives.pick(state({ step = "Train" })).text, "Train!")
			T.expectEqual(Objectives.pick(state({ step = "BuyGear", canBuyGear = true })).text, "Buy better gear!")
			T.expectEqual(Objectives.pick(state({ step = "Place", hasPrize = true })).text, "Place your dummy!")
		end)
	end)

	T.describe("Objectives.chooseTarget", function()
		local mine = { position = Vector3.new(100, 0, 0), slot = 2 }
		local other = { position = Vector3.new(1, 0, 0), slot = 3 }
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

	T.describe("Objectives.aimPoint", function()
		T.it("vise le centre d'une cible ordinaire", function()
			local center = Vector3.new(3, 1, -4)
			T.expectEqual(Objectives.aimPoint(center, nil, Vector3.new(30, 0, -20)), center)
			T.expectEqual(Objectives.aimPoint(center, 0, Vector3.new(30, 0, -20)), center)
		end)
		T.it("vise le point de la bande le plus proche du joueur, sans dépasser `span`", function()
			local center = Vector3.new(0, 0.3, -4)
			T.expectEqual(Objectives.aimPoint(center, 37, Vector3.new(12, 3, -20)), Vector3.new(12, 0.3, -4))
			T.expectEqual(Objectives.aimPoint(center, 37, Vector3.new(-80, 3, -20)), Vector3.new(-37, 0.3, -4))
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
