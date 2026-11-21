-- RevealPlan : paliers de mise en scène du tirage par rareté (#67), durées, hésitation de la silhouette, phrase du
-- secret, annonce serveur, fin forcée du résultat, rareté forcée en Studio.
return function(T, Loader)
	local loader = Loader.new()
	local RevealPlan = loader:require("src/shared/RevealPlan")
	local Collection = loader:require("src/shared/Collection")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Rarity = loader:require("src/shared/Rarity")

	-- Cette méthode permet de donner une suite de tirages fixe lorsqu'un test impose le hasard.
	local function fixed(value: number): () -> number
		return function()
			return value
		end
	end

	-- Cette méthode permet de donner l'entrée (taille normale) d'un mannequin du catalogue lorsqu'un test joue son tirage.
	local function entryOf(id: string): any
		return { id = id, size = 1 }
	end

	T.describe("RevealPlan.tierOf", function()
		T.it("regroupe les raretés par deux, le secret seul", function()
			local expected = { 1, 1, 2, 2, 3, 3, 4 }
			for rarity, tier in expected do
				T.expectEqual(RevealPlan.tierOf(rarity), tier, Rarity.LIST[rarity].name)
			end
		end)
		T.it("borne une rareté hors catalogue", function()
			T.expectEqual(RevealPlan.tierOf(0), 1)
			T.expectEqual(RevealPlan.tierOf(99), 4)
		end)
	end)

	T.describe("RevealPlan.TIERS", function()
		T.it("chaque palier dure plus longtemps et en montre plus que le précédent", function()
			for index = 2, #RevealPlan.TIERS do
				local low, high = RevealPlan.TIERS[index - 1], RevealPlan.TIERS[index]
				T.expect(high.climbFactor >= low.climbFactor, high.name .. " : montée au moins aussi longue")
				T.expect(high.drumroll >= low.drumroll, high.name .. " : roulement au moins aussi long")
				T.expect(high.confetti >= low.confetti, high.name .. " : au moins autant de confettis")
				T.expect(high.shake > low.shake, high.name .. " : secousse plus forte")
			end
		end)
		T.it("effets ajoutés au bon palier (#67)", function()
			local bright, hesitate, storm, secret = table.unpack(RevealPlan.TIERS)
			T.expect(bright.forms == 0 and bright.confetti == 0 and not bright.darkSky, "Common : révélation simple")
			T.expect(hesitate.forms >= 2 and hesitate.forms <= 3, "Rare : hésite entre 2 ou 3 formes")
			T.expect(hesitate.confetti > 0 and not hesitate.darkSky, "Rare : confettis, ciel normal")
			T.expect(storm.darkSky and storm.rays and storm.explosion, "Legendary : ciel sombre, rayons, explosion")
			T.expect(not storm.cinematic and secret.cinematic, "séquence complète au secret seulement")
		end)
	end)

	T.describe("RevealPlan.climbTime et teaseTime", function()
		T.it("la cote grimpe plus longtemps pour un mannequin plus rare", function()
			T.expectNear(RevealPlan.climbTime(1, 1, 100), Collection.climbTime(1, 100))
			T.expect(RevealPlan.climbTime(5, 1, 100) > RevealPlan.climbTime(3, 1, 100), "Legendary > Rare")
		end)
		T.it("le suspense s'allonge avec la rareté", function()
			local common = RevealPlan.teaseTime(1, Collection.teaseSequence(entryOf("traffic")))
			local rare = RevealPlan.teaseTime(3, Collection.teaseSequence(entryOf("pilot")))
			local legendary = RevealPlan.teaseTime(5, Collection.teaseSequence(entryOf("diamond")))
			T.expect(common < rare and rare < legendary, string.format("%.2f < %.2f < %.2f", common, rare, legendary))
			print(
				string.format("[mesure] suspense Common %.2f s, Rare %.2f s, Legendary %.2f s", common, rare, legendary)
			)
			T.expect(common < 5, string.format("Common : moins de 5 s (%.2f)", common))
		end)
	end)

	T.describe("RevealPlan.maxDuration et resultTime", function()
		T.it("couvre le plus long suspense réel de chaque rareté", function()
			for _, dummy in Collection.DUMMIES do
				for size = 1, #Collection.SIZES do
					local sequence = Collection.teaseSequence({ id = dummy.id, size = size })
					local tier = RevealPlan.get(dummy.rarity)
					local real = RevealPlan.teaseTime(dummy.rarity, sequence) + tier.autoClose
					if tier.cinematic then
						real += RevealPlan.cinematicTime()
					end
					T.expect(real <= RevealPlan.maxDuration(dummy.rarity), dummy.id .. " taille " .. size)
				end
			end
		end)
		T.it("le serveur ne coupe jamais un tirage avant sa fin, ni plus tôt qu'avant", function()
			for rarity = 1, #Rarity.LIST do
				local time = RevealPlan.resultTime(rarity)
				T.expect(time >= GameConfig.RESULT_MAX_TIME, "jamais sous RESULT_MAX_TIME")
				T.expect(time >= RevealPlan.maxDuration(rarity) + RevealPlan.RESULT_MARGIN, "marge gardée")
			end
			T.expectEqual(RevealPlan.resultTime(nil), RevealPlan.resultTime(1))
			T.expect(RevealPlan.resultTime(7) <= 60, "secret : une minute au plus")
		end)
	end)

	T.describe("RevealPlan.forms", function()
		T.it("aucune hésitation en Common", function()
			T.expectEqual(#RevealPlan.forms(1, Collection.teaseSequence(entryOf("traffic"))), 0)
		end)
		T.it("Rare et plus : les derniers candidats puis le gagné", function()
			local sequence = Collection.teaseSequence(entryOf("royal"))
			local forms = RevealPlan.forms(4, sequence)
			T.expect(#forms >= 2 and #forms <= 3, "2 ou 3 formes")
			T.expectEqual(forms[#forms], #sequence, "le gagné en dernier")
		end)
		T.it("pas d'hésitation sans autre candidat", function()
			T.expectEqual(#RevealPlan.forms(4, { { id = "ice", size = 1, odds = 500, rarity = 4 } }), 0)
		end)
	end)

	T.describe("RevealPlan.hesitation", function()
		T.it("changements de plus en plus lents, le dernier sur le gagné avant la fin", function()
			local duration = 1.8
			local swaps = RevealPlan.hesitation(3, duration)
			T.expect(#swaps >= 4, "plusieurs changements")
			T.expectEqual(swaps[#swaps].form, 3, "le gagné en dernier")
			T.expect(swaps[#swaps].at < duration, "fini avant la révélation")
			for k = 2, #swaps do
				T.expect(swaps[k].form ~= swaps[k - 1].form, "chaque changement montre une autre forme")
				if k > 2 then
					local gap = swaps[k].at - swaps[k - 1].at
					local previous = swaps[k - 1].at - swaps[k - 2].at
					T.expect(gap > previous, "ralentit")
				end
			end
		end)
		T.it("rien à planifier sous 2 formes", function()
			T.expectEqual(#RevealPlan.hesitation(1, 2), 0)
			T.expectEqual(#RevealPlan.hesitation(3, 0), 0)
		end)
	end)

	T.describe("RevealPlan.teaseEffects", function()
		T.it("rayons et colonne de lumière à partir de Legendary seulement", function()
			local color = Color3.new(1, 0, 0)
			T.expectEqual(#RevealPlan.teaseEffects(4, color), 0)
			local effects = RevealPlan.teaseEffects(5, color)
			local kinds = {}
			for _, effect in effects do
				kinds[effect.preset or effect.kind] = true
			end
			T.expect(kinds.rays and kinds.beam, "gloire de rayons et colonne de lumière")
		end)
	end)

	T.describe("RevealPlan.secretLine et typed", function()
		T.it("une phrase propre à chaque secret", function()
			T.expectEqual(RevealPlan.secretLine("king"), "THE CRASH KINGDOM HAS FOUND ITS KING...")
			for _, dummy in Collection.DUMMIES do
				if dummy.rarity == 7 then
					T.expect(RevealPlan.SECRET_LINES[dummy.id] ~= nil, dummy.id .. " a sa phrase")
				end
			end
			T.expectEqual(RevealPlan.secretLine("inconnu"), RevealPlan.SECRET_LINE_DEFAULT)
		end)
		T.it("écrit la phrase lettre à lettre, en entier à la fin", function()
			local text = "THE KING"
			T.expectEqual(RevealPlan.typed(text, 0), "")
			T.expectEqual(RevealPlan.typed(text, 3 / RevealPlan.TYPE_RATE), "THE")
			T.expectEqual(RevealPlan.typed(text, 100), text)
		end)
		T.it("ne coupe pas un caractère UTF-8", function()
			T.expectEqual(RevealPlan.typed("é…a", 2 / RevealPlan.TYPE_RATE), "é…")
		end)
		T.it("la phrase tient dans l'écran noir", function()
			local blackout = RevealPlan.CINEMATIC[1]
			T.expectEqual(blackout.name, "Blackout")
			for _, line in RevealPlan.SECRET_LINES do
				T.expect(#line / RevealPlan.TYPE_RATE < blackout.duration - 0.8, line .. " : lue au moins 0,8 s")
			end
		end)
	end)

	T.describe("RevealPlan annonce", function()
		T.it("annonce à partir de Legendary", function()
			T.expect(not RevealPlan.announces(4), "Epic : pas d'annonce")
			T.expect(RevealPlan.announces(5) and RevealPlan.announces(7), "Legendary et plus")
		end)
		T.it("texte du bandeau", function()
			T.expectEqual(
				RevealPlan.announceText("Ana", "Gold Dummy", 5, "4K"),
				"Ana pulled a LEGENDARY Gold Dummy! 1 IN 4K"
			)
		end)
		T.it("refuse une annonce mal formée", function()
			T.expectEqual(RevealPlan.parseAnnouncement(nil), nil)
			T.expectEqual(RevealPlan.parseAnnouncement({ player = "Ana", name = "Gold", rarity = "5", odds = 1 }), nil)
			local ok =
				RevealPlan.parseAnnouncement({ player = "Ana", name = "Gold", rarity = 5, odds = 4000, extra = 1 })
			T.expect(ok ~= nil and ok.odds == 4000 and (ok :: any).extra == nil, "champs connus seulement")
			T.expectEqual(ok.userId, nil, "identifiant facultatif")
			local own =
				RevealPlan.parseAnnouncement({ userId = 42, player = "Ana", name = "Gold", rarity = 5, odds = 1 })
			T.expectEqual(own and own.userId, 42)
		end)
	end)

	T.describe("RevealPlan.debugEntry", function()
		T.it("rareté par numéro ou par nom : un mannequin de cette rareté, taille normale", function()
			for rarity = 1, #Rarity.LIST do
				local name = Rarity.LIST[rarity].name
				for _, value in { rarity, tostring(rarity), name, string.lower(name) } do
					for _, roll in { 0, 0.5, 0.999 } do
						local entry = RevealPlan.debugEntry(value, fixed(roll))
						T.expect(entry ~= nil, tostring(value))
						local dummy = Collection.get(entry.id)
						T.expectEqual(dummy.rarity, rarity, tostring(value))
						T.expectEqual(entry.size, 1)
					end
				end
			end
		end)
		T.it("clé « id:taille » exacte", function()
			local entry = RevealPlan.debugEntry("king:3", fixed(0))
			T.expect(entry ~= nil and entry.id == "king" and entry.size == 3, "king:3")
		end)
		T.it("valeur absente ou illisible : tirage normal", function()
			for _, value in { nil, 0, 8, "nope", "king:9", true } do
				T.expectEqual(RevealPlan.debugEntry(value, fixed(0)), nil, tostring(value))
			end
		end)
	end)
end
