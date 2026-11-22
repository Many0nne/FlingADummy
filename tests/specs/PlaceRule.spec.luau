-- Règle de pose AUTO et retour au joueur (#70).
return function(T, Loader)
	local PlaceRule = Loader.new():require("src/shared/PlaceRule")
	local Tutorial = Loader.new():require("src/shared/Tutorial")

	local THROWN = Tutorial.complete(0, "Throw") -- lancer fait : l'étape courante est « Place »

	-- Cette méthode permet de construire une entrée de la règle hors tutoriel, avec les écarts voulus par le test.
	local function input(overrides: { [string]: any }?)
		local base = { tutorialStep = Tutorial.DONE, hasEntry = true, near = true, hasTarget = true }
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	T.describe("PlaceRule.firstPending", function()
		T.it("vrai seulement quand l'étape courante est « Place »", function()
			T.expectEqual(PlaceRule.firstPending(THROWN), true)
			T.expectEqual(PlaceRule.firstPending(0), false)
			T.expectEqual(PlaceRule.firstPending(nil), false)
			T.expectEqual(PlaceRule.firstPending(Tutorial.DONE), false)
		end)
	end)

	T.describe("PlaceRule.status", function()
		T.it("première pose du tutoriel en attente : tutorial", function()
			T.expectEqual(PlaceRule.status(input({ tutorialStep = THROWN })), "tutorial")
		end)
		T.it("hors tutoriel, mannequin, près de la base, présentoir : ok", function()
			T.expectEqual(PlaceRule.status(input()), "ok")
			T.expectEqual(PlaceRule.message("ok"), nil)
		end)
		T.it("rien à poser : none, sans message", function()
			T.expectEqual(PlaceRule.status(input({ hasEntry = false })), "none")
			T.expectEqual(PlaceRule.message("none"), nil)
		end)
		T.it("loin de la base : far, avec son message", function()
			T.expectEqual(PlaceRule.status(input({ near = false })), "far")
			T.expectEqual(PlaceRule.message("far") ~= nil, true)
		end)
		T.it("base pleine : full, message qui pointe vers le stand SELL", function()
			T.expectEqual(PlaceRule.status(input({ hasTarget = false })), "full")
			T.expectEqual(string.find(PlaceRule.message("full") :: string, "SELL") ~= nil, true)
		end)
		T.it("loin et pleine : far d'abord (la cause la plus simple à corriger)", function()
			T.expectEqual(PlaceRule.status(input({ near = false, hasTarget = false })), "far")
		end)
	end)
end
