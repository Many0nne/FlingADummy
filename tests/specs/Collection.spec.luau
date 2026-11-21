-- Collection : catalogue, tirage « 1 en N » poussé par la CHANCE, tailles, revenus, rangement dans la base.
return function(T, Loader)
	local loader = Loader.new()
	local Collection = loader:require("src/shared/Collection")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Rarity = loader:require("src/shared/Rarity")

	-- Cette méthode permet de donner une suite de tirages fixe (puis 0,999…) lorsqu'un test impose le hasard.
	local function rolls(list: { number }): () -> number
		local i = 0
		return function()
			i += 1
			return list[i] or 0.999999
		end
	end

	-- Cette méthode permet de faire la somme des valeurs d'une table lorsqu'un test vérifie des probabilités.
	local function sum(values: { [any]: number }): number
		local total = 0
		for _, v in values do
			total += v
		end
		return total
	end

	T.describe("Collection.DUMMIES", function()
		T.it("une vingtaine de mannequins, toutes les raretés de Common à Secret", function()
			T.expect(#Collection.DUMMIES >= 20, "au moins 20 mannequins")
			local seen = {}
			for _, dummy in Collection.DUMMIES do
				seen[dummy.rarity] = true
				T.expectEqual(Collection.get(dummy.id), dummy)
			end
			for index = 1, #Rarity.LIST do
				T.expect(seen[index] == true, "rareté " .. Rarity.LIST[index].name)
			end
		end)
		T.it("plus rare = cote et revenu plus hauts (revenu ×3 à ×10 d'une rareté à l'autre)", function()
			local byRarity = {}
			for _, dummy in Collection.DUMMIES do
				local r = byRarity[dummy.rarity] or { minN = math.huge, maxN = 0, total = 0, count = 0 }
				r.minN = math.min(r.minN, dummy.n)
				r.maxN = math.max(r.maxN, dummy.n)
				r.total += dummy.income
				r.count += 1
				byRarity[dummy.rarity] = r
			end
			for index = 2, #Rarity.LIST do
				local low, high = byRarity[index - 1], byRarity[index]
				T.expect(high.minN > low.maxN, "cotes séparées entre raretés " .. index)
				local ratio = (high.total / high.count) / (low.total / low.count)
				T.expect(ratio >= 3 and ratio <= 10, string.format("revenu ×%.1f à la rareté %d", ratio, index))
			end
		end)
		T.it("le premier mannequin est un Common à ≈ 4 $/s", function()
			local starter = Collection.get(Collection.STARTER)
			T.expectEqual(starter.rarity, 1)
			T.expectEqual(Collection.income({ id = Collection.STARTER, size = 1 }), 4)
		end)
	end)

	T.describe("Collection.probabilities", function()
		T.it("somme à 1 quelle que soit la chance", function()
			for _, luck in { 1, 1.22, 5, 25, 1000 } do
				T.expectNear(sum(Collection.probabilities(luck)), 1, 1e-9)
				T.expectNear(sum(Collection.sizeProbabilities(luck)), 1, 1e-9)
			end
		end)
		T.it("la chance rend les raretés hautes plus probables et les communs moins", function()
			local low, high = Collection.probabilities(1), Collection.probabilities(10)
			T.expect(high.galaxy > low.galaxy * 9, "Mythic ≈ ×10")
			T.expect(high.cosmic > low.cosmic * 9, "Secret ≈ ×10")
			T.expect(high.crash < low.crash, "Common moins probable")
			local big = Collection.sizeProbabilities(16)
			T.expect(big[2] > Collection.sizeProbabilities(1)[2] * 3, "Big ≈ ×4 à chance 16")
		end)
		T.it("cote affichée cohérente avec la probabilité (« 1 IN N »)", function()
			local p = Collection.probabilities(1)
			T.expectEqual(Collection.odds({ id = "cosmic", size = 1 }), math.floor(1 / p.cosmic + 0.5))
			T.expect(Collection.odds({ id = "cosmic", size = 1 }) >= 1000000, "Secret ≥ 1 M")
			T.expect(Collection.odds({ id = "crash", size = 1 }) <= 3, "Common courant")
			T.expect(Collection.odds({ id = "crash", size = 3 }) > Collection.odds({ id = "crash", size = 1 }), "Huge")
		end)
	end)

	T.describe("Collection.draw", function()
		T.it("essaie du plus rare au plus courant : un tirage de 0 donne le plus rare", function()
			local entry = Collection.draw(1, rolls({ 0, 0.999 }))
			T.expectEqual(entry.id, "cosmic")
		end)
		T.it("tous les essais ratés : le plus courant, taille normale", function()
			local entry = Collection.draw(1, rolls({}))
			T.expectEqual(entry.id, "crash")
			T.expectEqual(entry.size, 1)
		end)
		T.it("fréquences d'un grand nombre de tirages proches des probabilités affichées", function()
			-- Graine fixe (Random n'existe pas sous Lune) : résultat reproductible
			math.randomseed(42)
			local function nextNumber(): number
				return math.random()
			end
			local counts = {}
			local n = 20000
			for _ = 1, n do
				local entry = Collection.draw(3, nextNumber)
				counts[entry.id] = (counts[entry.id] or 0) + 1
			end
			local p = Collection.probabilities(3)
			for _, id in { "crash", "rookie", "traffic", "mint" } do
				local observed = (counts[id] or 0) / n
				T.expect(math.abs(observed - p[id]) < 0.02, string.format("%s %.3f vs %.3f", id, observed, p[id]))
			end
		end)
	end)

	T.describe("Collection.income / label", function()
		T.it("la taille multiplie le revenu et préfixe le nom", function()
			local huge = { id = "gold", size = 3 }
			T.expectEqual(Collection.income(huge), 2500 * Collection.SIZES[3].income)
			T.expectEqual(Collection.label(huge), "Huge Gold Dummy")
			T.expectEqual(Collection.label({ id = "gold", size = 1 }), "Gold Dummy")
		end)
		T.it("isEntry refuse les entrées inconnues ou abîmées", function()
			T.expect(Collection.isEntry({ id = "crash", size = 1 }), "valide")
			T.expect(not Collection.isEntry({ id = "nope", size = 1 }), "id inconnu")
			T.expect(not Collection.isEntry({ id = "crash", size = 9 }), "taille inconnue")
			T.expect(not Collection.isEntry("crash"), "pas une table")
			T.expect(not Collection.isEntry(nil), "nil")
		end)
	end)

	T.describe("Collection.scale", function()
		T.it("taille × rareté : un Secret normal plus grand qu'un Common, un Giant encore plus", function()
			T.expectNear(Collection.scale({ id = "crash", size = 1 }), 1, 1e-6)
			local secret = Collection.scale({ id = "king", size = 1 })
			T.expectNear(secret, Collection.RARITY_SCALE[7], 1e-6)
			T.expect(secret > Collection.scale({ id = "gold", size = 1 }), "Secret > Legendary")
			local giant = Collection.scale({ id = "king", size = #Collection.SIZES })
			T.expectNear(giant, Collection.SIZES[#Collection.SIZES].scale * Collection.RARITY_SCALE[7], 1e-6)
			T.expectEqual(#Collection.RARITY_SCALE, #Rarity.LIST)
		end)
	end)

	T.describe("Collection.baseIncome", function()
		local crash = { id = "crash", size = 1 } -- 4 $/s
		local mint = { id = "mint", size = 1 } -- 15 $/s
		T.it("revenu de la base = somme des présentoirs occupés", function()
			T.expectEqual(Collection.baseIncome({ mint, false, crash }, 3), 19)
			T.expectEqual(Collection.baseIncome({ false, false }, 2), 0)
			T.expectEqual(
				Collection.baseIncome({ mint, crash }, 1),
				15,
				"présentoirs au-delà de la capacité ignorés"
			)
		end)
	end)

	T.describe("Collection.teaseSteps", function()
		T.it("1 à 3 paliers croissants, tous sous la cote finale", function()
			for _, odds in { 3, 7, 54, 220, 1370, 100000 } do
				local steps = Collection.teaseSteps(odds)
				T.expect(#steps >= 1 and #steps <= 3, "paliers pour " .. odds)
				local last = 1
				for _, value in steps do
					T.expect(value > last and value < odds, "palier " .. value .. " pour " .. odds)
					last = value
				end
			end
			T.expectEqual(#Collection.teaseSteps(1370), 3)
		end)
		T.it("cote minuscule : aucun palier (la silhouette montre « 1 IN ? »)", function()
			T.expectEqual(#Collection.teaseSteps(2), 0)
		end)
	end)

	T.describe("Collection.climbOdds / climbTime", function()
		T.it(
			"part de `from`, finit exactement sur `to`, ne redescend jamais et passe par les petites valeurs",
			function()
				T.expectEqual(Collection.climbOdds(1, 16, 0), 1)
				T.expectEqual(Collection.climbOdds(1, 16, 1), 16)
				T.expectEqual(Collection.climbOdds(1, 16, 2), 16)
				local previous, seen = 0, {}
				for i = 0, 200 do
					local value = Collection.climbOdds(4, 16, i / 200)
					T.expect(value >= previous and value >= 4 and value <= 16, "valeur " .. value)
					previous = value
					seen[value] = true
				end
				-- Le compteur défile : on voit passer chaque chiffre entre 4 et 16
				for n = 4, 16 do
					T.expect(seen[n] == true, "chiffre " .. n .. " affiché")
				end
			end
		)
		T.it("ralentit à l'approche du palier (plus de chemin parcouru au début qu'à la fin)", function()
			local early = Collection.climbOdds(1, 1000, 0.2)
			local late = Collection.climbOdds(1, 1000, 0.8)
			T.expect(math.log10(early) > math.log10(1000) - math.log10(late), "début rapide, fin lente")
		end)
		T.it("défile plus longtemps sur un grand écart, dans [0,7 ; 1,5] s", function()
			T.expectNear(Collection.climbTime(1, 1), 0.7)
			T.expect(Collection.climbTime(10, 1000) > Collection.climbTime(10, 20), "plus long")
			T.expectNear(Collection.climbTime(1, 1e9), 1.5)
		end)
	end)

	T.describe("Collection.teaseSequence", function()
		T.it(
			"finit par le mannequin gagné, à sa cote ; candidats d'avant plus courants, cotes croissantes",
			function()
				for _, entry in { { id = "hero", size = 1 }, { id = "gold", size = 3 }, { id = "cosmic", size = 1 } } do
					local sequence = Collection.teaseSequence(entry)
					local last = sequence[#sequence]
					T.expectEqual(last.id, entry.id)
					T.expectEqual(last.size, entry.size)
					T.expectEqual(last.odds, Collection.odds(entry))
					local prize = Collection.get(entry.id)
					local previous = 0
					for index, step in sequence do
						T.expect(step.odds > previous, "cote croissante pour " .. entry.id)
						previous = step.odds
						if index < #sequence then
							T.expect(step.id ~= entry.id, "candidat différent du gagné")
							T.expect(step.rarity <= prize.rarity, "candidat pas plus rare que le gagné")
						end
					end
				end
			end
		)
		T.it("un gagné rare passe par des candidats (suspense), un commun courant va droit au but", function()
			T.expect(#Collection.teaseSequence({ id = "cosmic", size = 1 }) >= 3, "Secret : au moins 2 candidats")
			T.expect(#Collection.teaseSequence({ id = "hero", size = 1 }) >= 2, "Rare : au moins 1 candidat")
			T.expectEqual(#Collection.teaseSequence({ id = "crash", size = 1 }), 1)
		end)
	end)
end
