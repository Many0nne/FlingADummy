-- Rythme de la progression (#15) : le joueur simulé (tools/ProgressionSim, vrais modules du jeu) achète tout le
-- catalogue (équipements, mannequins à lancer, présentoirs) puis renaît ; aucun « mur » entre deux achats, rythme de la
-- première heure, présentoirs étalés, première renaissance vers 6 h (#223). Modèle : mannequins hors
-- présentoirs vendus aussitôt (un joueur qui ne passe pas au stand SELL touche le même argent, mais plus tard).
return function(T, Loader, Lib)
	local Sim = Lib.ProgressionSim
	local m = Sim.modules(Loader.new())
	local PLAYERS = 15
	-- Rythme de la première heure (#133) : écarts de quelques secondes à quelques minutes, que la médiane de 15 joueurs
	-- déplace de ± 60 s selon les graines ; 200 joueurs simulés sur 75 min (+ 1,3 s) la stabilisent. Écarts entre
	-- instants médians, pour chaque achat dont l'instant médian tombe dans la première heure ; l'attente qui chevauche la
	-- fin de l'heure ne compte que pour sa part avant 60 min (ensuite les écarts s'allongent : docs/design.md, « Rythme
	-- et économie »)
	local HOUR_PLAYERS = 200
	local HOUR_SECONDS = 75 * 60

	local runs = {}
	local steps = {}
	local hourSteps = {}

	T.describe("Joueur simulé (#15) : partie", function()
		T.it("15 joueurs simulés sur 16 h (renaissances comprises), 200 sur la première heure", function()
			for seed = 1, PLAYERS do
				table.insert(runs, Sim.simulate(m, seed, 16 * 3600))
			end
			local hourRuns = {}
			for seed = 1, HOUR_PLAYERS do
				table.insert(hourRuns, Sim.simulate(m, seed, HOUR_SECONDS, true))
			end
			-- Le joueur simulé fixe la graine de math.random : les specs suivantes retrouvent un hasard non répété
			math.randomseed(os.time())
			steps = Sim.steps(runs)
			hourSteps = Sim.steps(hourRuns)
			T.expectEqual(#runs, PLAYERS)
		end)
	end)

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
		T.it(
			"achète avant la première renaissance tout ce qui coûte moins cher qu'elle, dans le même ordre",
			function()
				-- Depuis #223 la renaissance ($15B) tombe avant les derniers mannequins à lancer et présentoirs : ils
				-- deviennent les achats des cycles suivants
				local price = m.Rebirth.price(0)
				local catalog = 0
				for tier = 2, #m.Training.GEARS do
					catalog += if m.Training.GEARS[tier].cost < price then 1 else 0
				end
				for tier = 2, #m.ThrowDummies.LIST do
					catalog += if m.ThrowDummies.LIST[tier].cost < price then 1 else 0
				end
				for _, displayPrice in m.GameConfig.DISPLAY_PRICES do
					catalog += if displayPrice < price then 1 else 0
				end
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
			end
		)
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
				T.expect(hourSteps[1].t < 60, "premier achat à " .. hourSteps[1].t .. " s")
				local count = 0
				for k = 2, #hourSteps do
					if hourSteps[k].t <= 3600 then
						count += 1
						local gap = hourSteps[k].t - hourSteps[k - 1].t
						T.expect(gap <= 360, string.format("achat %d : %d s après le précédent", k, gap))
					elseif hourSteps[k - 1].t <= 3600 then
						-- Attente qui chevauche la fin de l'heure : sa part dans la première heure compte aussi
						local wait = 3600 - hourSteps[k - 1].t
						T.expect(
							wait <= 360,
							string.format("achat %d : %d s d'attente avant la fin de l'heure", k, wait)
						)
					end
				end
				T.expect(count >= 12, count .. " achats la première heure")
			end
		)
		T.it(
			"présentoirs étalés sur toute la courbe (#156) : pas plus d'une heure sans achat entre 1 h et la première renaissance",
			function()
				local start = m.GameConfig.DISPLAY_START
				local last = start + #m.GameConfig.DISPLAY_PRICES
				-- Présentoirs 6 à 8 bon marché (#211) : achetés dans les 10 premières minutes, dans l'ordre
				local previous = 0
				for display = start + 1, start + 3 do
					local at = median("display:" .. display)
					T.expect(
						at ~= nil and at < 600 and at > previous,
						string.format("présentoir %d acheté à %s s", display, tostring(at))
					)
					previous = at or previous
				end
				local ninth = median("display:" .. (start + 4))
				T.expect(
					ninth ~= nil and ninth > 300 and ninth < 900,
					"présentoir 9 acheté à " .. tostring(ninth) .. " s"
				)
				-- Un présentoir de la deuxième moitié de la liste n'arrive qu'après la première heure
				local half = median("display:" .. (start + math.ceil(#m.GameConfig.DISPLAY_PRICES / 2) + 1))
				T.expect(
					half ~= nil and half > 3600,
					"présentoir de la 2e moitié acheté à " .. tostring(half) .. " s"
				)
				-- Depuis #223 la première renaissance (≈ 5,5 h) passe avant les derniers présentoirs (26 à 30, de $16B à
				-- $81B) : ils deviennent les achats des cycles suivants, avec le revenu gardé (le dernier vers 11 h)
				local t = median("display:" .. last)
				local rebirth = median("rebirth:1")
				T.expect(t ~= nil and t > 8 * 3600, "dernier présentoir à " .. tostring(t) .. " s")
				T.expect(t ~= nil and rebirth ~= nil and t > rebirth, "dernier présentoir après la 1re renaissance")
				local count = 0
				for k = 2, #steps do
					local from, to = steps[k - 1].t, steps[k].t
					if to > 3600 then
						count += 1
						T.expect(
							to - from <= 3600,
							string.format("achat %d : %d s après le précédent", k, to - from)
						)
					end
				end
				T.expect(count >= 20, count .. " achats entre 1 h et la première renaissance (5,5 h)")
			end
		)
		T.it("raretés hautes rares (#156) : Secret vers 4 h, Divine vers 9 h de jeu", function()
			local secret, divine = median("rarity:7"), median("rarity:8")
			T.expect(
				secret ~= nil and secret > 3 * 3600 and secret < 5 * 3600,
				"Secret à " .. tostring(secret) .. " s"
			)
			T.expect(divine ~= nil and divine > 8 * 3600, "Divine à " .. tostring(divine) .. " s")
		end)
		T.it("bout de piste vers la fin des équipements (#157) : entre 3,5 h et 6 h", function()
			local t = median("trackEnd")
			T.expect(t ~= nil and t > 3.5 * 3600 and t < 6 * 3600, "bout de piste à " .. tostring(t) .. " s")
		end)
		T.it("première renaissance vers 6 h de jeu (#223), peu après le bout de piste", function()
			local t = median("rebirth:1")
			T.expect(t ~= nil and t > 5 * 3600 and t < 7 * 3600, "première renaissance à " .. tostring(t) .. " s")
			local trackEnd = median("trackEnd")
			T.expect(
				t ~= nil and trackEnd ~= nil and t > trackEnd and t - trackEnd < 3 * 3600,
				"renaissance " .. tostring(t) .. " s, bout de piste " .. tostring(trackEnd) .. " s"
			)
		end)
		T.it("renaissances suivantes pas trop rapprochées (#223) : 1,5 h au moins entre les 4 premières", function()
			for k = 2, 4 do
				local previous, current = median("rebirth:" .. (k - 1)), median("rebirth:" .. k)
				T.expect(
					previous ~= nil and current ~= nil and current - previous >= 1.5 * 3600,
					string.format(
						"renaissance %d à %s s, la précédente à %s s",
						k,
						tostring(current),
						tostring(previous)
					)
				)
			end
		end)
		T.it(
			"chaque cycle de renaissance garde des achats (#223) : pas 45 min sans achat, médiane des joueurs",
			function()
				-- Attente entre deux achats d'un même cycle (celle qui précède la renaissance elle-même n'en est pas une)
				for cycle = 0, 3 do
					local worst = {}
					for _, run in runs do
						local previous, count, longest = 0, 0, 0
						for _, purchase in run.purchases do
							if purchase.kind == "rebirth" then
								count += 1
							elseif count == cycle then
								longest = math.max(longest, purchase.t - previous)
							end
							previous = purchase.t
						end
						table.insert(worst, longest)
					end
					local value = Sim.median(worst)
					T.expect(
						value ~= nil and value <= 45 * 60,
						string.format("cycle %d : %s s sans achat", cycle, tostring(value))
					)
				end
			end
		)
	end)
end
