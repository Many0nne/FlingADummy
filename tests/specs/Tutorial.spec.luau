-- Tutoriel : étapes (lancer, poser, entraînement, équipement), reprise d'une ancienne sauvegarde, popup « NEW GEAR! ».
return function(T, Loader)
	local Tutorial = Loader.new():require("src/shared/Tutorial")

	T.describe("Tutorial.current / complete", function()
		T.it("un nouveau joueur lance, pose son mannequin, s'entraîne puis achète un équipement", function()
			local flags = 0
			for _, step in { "Throw", "Place", "Train", "BuyGear" } do
				T.expectEqual(Tutorial.current(flags), step)
				flags = Tutorial.complete(flags, step)
			end
			T.expectEqual(Tutorial.current(flags), nil)
			T.expectEqual(flags, Tutorial.DONE)
		end)
		T.it("une étape faite dans le désordre compte quand même", function()
			local flags = Tutorial.complete(0, "Train")
			T.expectEqual(Tutorial.current(flags), "Throw")
			T.expectEqual(Tutorial.current(Tutorial.complete(flags, "Throw")), "Place")
		end)
		T.it("poser vaut lancer ; acheter un équipement vaut toutes les étapes d'avant", function()
			T.expectEqual(Tutorial.current(Tutorial.complete(0, "Place")), "Train")
			T.expectEqual(Tutorial.complete(0, "BuyGear"), Tutorial.DONE)
		end)
		T.it("rien ne revient une fois le tutoriel fini", function()
			for _, event in { "Throw", "Place", "Train", "BuyGear", "Autre" } do
				T.expectEqual(Tutorial.complete(Tutorial.DONE, event), Tutorial.DONE)
			end
			T.expectEqual(Tutorial.complete(0, "Autre"), 0)
		end)
	end)

	T.describe("Tutorial.canThrowAgain", function()
		T.it("masqué jusqu'à la première pose, permis ensuite", function()
			T.expectEqual(Tutorial.canThrowAgain(0), false)
			T.expectEqual(Tutorial.canThrowAgain(Tutorial.complete(0, "Throw")), false)
			T.expectEqual(Tutorial.canThrowAgain(Tutorial.complete(Tutorial.complete(0, "Throw"), "Train")), false)
			T.expectEqual(Tutorial.canThrowAgain(Tutorial.complete(0, "Place")), true)
			T.expectEqual(Tutorial.canThrowAgain(Tutorial.DONE), true)
		end)
		T.it("ancien joueur sans base : pas avant sa première pose", function()
			T.expectEqual(Tutorial.canThrowAgain(Tutorial.infer({ GearTier = 2, BestDistance = 50 })), false)
		end)
	end)

	T.describe("Tutorial.infer", function()
		T.it("nouvelle sauvegarde : tutoriel complet à faire", function()
			T.expectEqual(Tutorial.infer({}), 0)
			T.expectEqual(Tutorial.infer({ GearTier = 1, TrainLevel = 1, BestDistance = 0 }), 0)
		end)
		T.it("ancien joueur : les étapes déjà faites sont sautées, « poser » reste à faire", function()
			T.expectEqual(Tutorial.current(Tutorial.infer({ BestDistance = 120 })), "Place")
			T.expectEqual(Tutorial.current(Tutorial.infer({ TrainLevel = 3 })), "Throw")
			T.expectEqual(Tutorial.current(Tutorial.infer({ GearTier = 2 })), "Place")
			T.expectEqual(
				Tutorial.current(Tutorial.infer({ GearTier = 2, BestDistance = 50, TrainLevel = 4 })),
				"Place"
			)
		end)
	end)

	T.describe("Tutorial.gearOffer", function()
		T.it("propose le palier suivant dès qu'il est abordable", function()
			T.expectEqual(Tutorial.gearOffer(1, 100, 99, {}), nil)
			T.expectEqual(Tutorial.gearOffer(1, 100, 100, {}), 2)
		end)
		T.it("une fois fermé, plus proposé pour ce palier, mais de nouveau pour le suivant", function()
			local dismissed = { [2] = true }
			T.expectEqual(Tutorial.gearOffer(1, 100, 5000, dismissed), nil)
			T.expectEqual(Tutorial.gearOffer(2, 1500, 5000, dismissed), 3)
		end)
		T.it("rien au dernier palier", function()
			T.expectEqual(Tutorial.gearOffer(7, nil, 1e12, {}), nil)
		end)
	end)
end
