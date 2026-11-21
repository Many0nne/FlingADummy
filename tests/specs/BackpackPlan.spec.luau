-- BackpackPlan : un Tool par mannequin du stock, ordre de la barre d'outils, outils à ajouter, retirer, réordonner.
return function(T, Loader)
	local loader = Loader.new()
	local BackpackPlan = loader:require("src/shared/BackpackPlan")

	local crash = { id = "crash", size = 1 } -- Common
	local rookie = { id = "rookie", size = 1 } -- Common
	local mint = { id = "mint", size = 1 } -- Uncommon
	local gold = { id = "gold", size = 1 } -- Legendary
	local bigGold = { id = "gold", size = 2 }

	-- Cette méthode permet de lister les clés d'entrées lorsqu'un test compare un ordre.
	local function keys(entries: { any }): string
		local list = {}
		for _, entry in entries do
			table.insert(list, entry.id .. ":" .. entry.size)
		end
		return table.concat(list, " ")
	end

	-- Cette méthode permet de décrire des outils existants (« k » rangé, « k* » équipé) lorsqu'un test part d'un
	-- Backpack précis.
	local function tools(spec: { string }): { any }
		local list = {}
		for _, text in spec do
			local key, star = string.match(text, "^([^*]+)(%*?)$")
			table.insert(list, { key = key, equipped = star == "*" })
		end
		return list
	end

	T.describe("BackpackPlan.order", function()
		T.it("rareté décroissante, puis ordre d'arrivée dans le stock", function()
			local ordered = BackpackPlan.order({ crash, mint, rookie, gold, crash, bigGold })
			T.expect(keys(ordered) == "gold:1 gold:2 mint:1 crash:1 rookie:1 crash:1", "obtenu : " .. keys(ordered))
		end)

		T.it("stock vide : barre vide", function()
			T.expect(#BackpackPlan.order({}) == 0)
		end)
	end)

	T.describe("BackpackPlan.plan", function()
		T.it("Backpack vide : un outil par mannequin, doublons compris, dans l'ordre de la barre", function()
			local plan = BackpackPlan.plan({ crash, gold, crash }, {})
			T.expect(#plan.remove == 0)
			T.expect(keys(plan.add) == "gold:1 crash:1 crash:1", "obtenu : " .. keys(plan.add))
			T.expect(table.concat(plan.sequence, " ") == "gold:1 crash:1 crash:1")
		end)

		T.it("rien n'a changé : rien à créer ni à retirer", function()
			local plan = BackpackPlan.plan({ crash, gold }, tools({ "gold:1", "crash:1" }))
			T.expect(#plan.remove == 0 and #plan.add == 0)
			T.expect(table.concat(plan.sequence, " ") == "gold:1 crash:1")
		end)

		T.it("nouveau mannequin gagné : seul lui est créé, le premier reste (rien ne se perd, #54)", function()
			local plan = BackpackPlan.plan({ crash, mint }, tools({ "crash:1" }))
			T.expect(#plan.remove == 0)
			T.expect(keys(plan.add) == "mint:1")
			T.expect(table.concat(plan.sequence, " ") == "mint:1 crash:1", "le plus rare passe devant")
		end)

		T.it("mannequin posé ou vendu : son outil est retiré", function()
			local plan = BackpackPlan.plan({ gold }, tools({ "gold:1", "crash:1" }))
			T.expect(#plan.remove == 1 and plan.remove[1] == 2)
			T.expect(#plan.add == 0)
		end)

		T.it("doublon retiré : l'outil équipé reste en main, un rangé part", function()
			local plan = BackpackPlan.plan({ crash }, tools({ "crash:1*", "crash:1" }))
			T.expect(#plan.remove == 1 and plan.remove[1] == 2, "l'outil rangé est retiré")
			T.expect(#plan.sequence == 0, "l'outil équipé n'est pas dans la séquence du Backpack")
		end)

		T.it("outil équipé dont le mannequin n'est plus au stock : retiré", function()
			local plan = BackpackPlan.plan({ crash }, tools({ "gold:1*", "crash:1" }))
			T.expect(#plan.remove == 1 and plan.remove[1] == 1)
			T.expect(table.concat(plan.sequence, " ") == "crash:1")
		end)

		T.it("séquence sans l'outil équipé, doublons de même clé comptés une fois en moins", function()
			local plan = BackpackPlan.plan({ crash, gold, crash }, tools({ "crash:1*", "gold:1", "crash:1" }))
			T.expect(#plan.remove == 0 and #plan.add == 0)
			T.expect(table.concat(plan.sequence, " ") == "gold:1 crash:1", table.concat(plan.sequence, " "))
		end)

		T.it("indices à retirer triés, même mêlés aux outils gardés", function()
			local plan = BackpackPlan.plan({ mint }, tools({ "crash:1", "mint:1", "gold:1", "mint:1" }))
			T.expect(table.concat(plan.remove, ",") == "1,3,4", table.concat(plan.remove, ","))
		end)
	end)

	T.describe("BackpackPlan.sameSequence", function()
		T.it("compare l'ordre, pas seulement le contenu", function()
			T.expect(BackpackPlan.sameSequence({ "a", "b" }, { "a", "b" }))
			T.expect(not BackpackPlan.sameSequence({ "a", "b" }, { "b", "a" }))
			T.expect(not BackpackPlan.sameSequence({ "a" }, { "a", "a" }))
		end)
	end)
end
