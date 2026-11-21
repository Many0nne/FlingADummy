-- Rythme de la progression (#15) : le joueur simulé (tools/ProgressionSim, vrais modules du jeu) achète tout le
-- catalogue (équipements, mannequins à lancer, présentoirs) puis renaît ; aucun « mur » entre deux achats, rythme de la
-- première heure, présentoirs étalés, première renaissance vers une douzaine d'heures.
return function(T, Loader, Lib)
	local Sim = Lib.ProgressionSim
	local m = Sim.modules(Loader.new())
	local PLAYERS = 15

	local runs = {}
	for seed = 1, PLAYERS do
		table.insert(runs, Sim.simulate(m, seed, 16 * 3600, true))
	end
	local steps = Sim.steps(runs)

	-- Cette méthode permet de donner l'instant médian (s) d'un palier sur les joueurs simulés (nil si la moitié ne
	-- l'atteint pas) lorsqu'un test vérifie un repère.
	local function median(key: string): number?
		local values = {}
		for _, run in runs do
			table.insert(values, run.marks[key] or math.huge)
		end
		return Sim.median(values)
	end

	T.describe("Joueur simulé (#15)", function()
		T.it("achète tout le catalogue avant la première renaissance, dans le même ordre pour tous", function()
			local catalog = (#m.Training.GEARS - 1) + (#m.ThrowDummies.LIST - 1) + #m.GameConfig.DISPLAY_PRICES
			T.expectEqual(#steps, catalog)
			for _, run in runs do
				for k, step in steps do
					local purchase = run.purchases[k]
					T.expect(
						purchase ~= nil and purchase.kind == step.kind and purchase.index == step.index,
						string.format("achat %d : %s %d attendu", k, step.kind, step.index)
					)
				end
			end
		end)
		T.it("pas de mur : le ratio « prix suivant / revenu » ne fait jamais de saut de plus de × 2", function()
			for k, step in steps do
				T.expect(
					step.jump <= 2,
					string.format(
						"achat %d (%s %d) : saut × %.2f, ratio %d s",
						k,
						step.kind,
						step.index,
						step.jump,
						step.ratio
					)
				)
			end
		end)
		T.it(
			"premier achat en moins d'une minute, puis un achat toutes les 6 min au plus la première heure",
			function()
				T.expect(steps[1].t < 60, "premier achat à " .. steps[1].t .. " s")
				local count = 0
				for k = 2, #steps do
					if steps[k].t <= 3600 then
						count += 1
						local gap = steps[k].t - steps[k - 1].t
						T.expect(gap <= 360, string.format("achat %d : %d s après le précédent", k, gap))
					end
				end
				T.expect(count >= 12, count .. " achats la première heure")
			end
		)
		T.it("présentoirs étalés : le 10e (palier Golden) après la première heure, avant 3 h", function()
			local last = m.GameConfig.DISPLAY_START + #m.GameConfig.DISPLAY_PRICES
			local t = median("display:" .. last)
			T.expect(t ~= nil and t > 3600 and t < 3 * 3600, "10e présentoir à " .. tostring(t) .. " s")
		end)
		T.it("première renaissance vers une douzaine d'heures de jeu", function()
			local t = median("rebirth:1")
			T.expect(t ~= nil and t > 9 * 3600 and t < 15 * 3600, "première renaissance à " .. tostring(t) .. " s")
		end)
	end)
end
