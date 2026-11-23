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
			local expected = { 1, 1, 2, 2, 3, 3, 4, 4, 4, 4, 4 }
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

	T.describe("RevealPlan.shownRarity et teaseCues (#201)", function()
		T.it("Common avant le premier palier, puis la rareté du dernier palier atteint", function()
			local sequence = Collection.teaseSequence(entryOf("king"))
			T.expect(#sequence >= 2, "king : plusieurs paliers")
			T.expectEqual(RevealPlan.shownRarity(sequence, 0), 1, "« 1 IN 1 » : Common")
			for index, step in sequence do
				T.expectEqual(RevealPlan.shownRarity(sequence, index), step.rarity)
			end
		end)
		T.it("aucun effet de suspense ne trahit la rareté gagnée avant que la cote l'atteigne", function()
			for _, dummy in Collection.DUMMIES do
				for size = 1, #Collection.SIZES do
					local sequence = Collection.teaseSequence({ id = dummy.id, size = size })
					for reached = 0, #sequence do
						local shown = if reached == 0 then 1 else sequence[reached].rarity
						local cues = RevealPlan.teaseCues(RevealPlan.shownRarity(sequence, reached))
						local label = string.format("%s taille %d, palier %d", dummy.id, size, reached)
						-- Les effets sont ceux de la rareté affichée, quelle que soit la rareté gagnée
						T.expectEqual(cues.rarity, shown, label)
						T.expect(cues.outline == Rarity.LIST[shown].color, label .. " : contour du palier affiché")
						T.expectEqual(cues.darkSky, RevealPlan.get(shown).darkSky, label)
						T.expectEqual(cues.rays, RevealPlan.get(shown).rays, label)
						if reached < #sequence then
							-- Même suite, gagné remplacé par un Infinity : rien ne change avant que la cote l'atteigne
							local rigged = table.clone(sequence)
							rigged[#rigged] = table.clone(sequence[#sequence])
							rigged[#rigged].rarity = #Rarity.LIST
							local other = RevealPlan.teaseCues(RevealPlan.shownRarity(rigged, reached))
							T.expectEqual(other.rarity, cues.rarity, label .. " : indépendant du gagné")
							T.expectEqual(other.rays, cues.rays, label .. " : rayons indépendants du gagné")
							T.expectEqual(other.darkSky, cues.darkSky, label .. " : ciel indépendant du gagné")
							if shown < 5 then
								T.expect(
									not cues.rays and not cues.darkSky,
									label .. " : ni rayons ni ciel avant Legendary"
								)
								T.expectEqual(#RevealPlan.teaseEffects(cues.rarity, cues.outline), 0, label)
							end
						end
					end
				end
			end
		end)
		T.it("un Legendary ou mieux tiré en plusieurs paliers ne s'annonce pas dès la silhouette", function()
			local checked = 0
			for _, dummy in Collection.DUMMIES do
				local sequence = Collection.teaseSequence(entryOf(dummy.id))
				if dummy.rarity >= 5 and #sequence >= 2 then
					checked += 1
					local first = RevealPlan.teaseCues(RevealPlan.shownRarity(sequence, 0))
					T.expect(not first.rays and not first.darkSky, dummy.id .. " : silhouette nue au départ")
				end
			end
			T.expect(checked > 0, "au moins un Legendary ou mieux vérifié")
		end)
		T.it("Client.Prize règle les effets du suspense sur le palier affiché, pas sur le gagné", function()
			local fs = require("@lune/fs")
			local source = fs.readFile("src/client/Prize.luau")
			for line in string.gmatch(source, "[^\n]+") do
				if string.find(line, "teaseCues(", 1, true) or string.find(line, "teaseEffects(", 1, true) then
					T.expect(not string.find(line, "prize", 1, true), "effet de suspense lu sur le gagné : " .. line)
				end
			end
			for _, pattern in { "plan.darkSky", "plan.rays", "teaseEffects(a.prize" } do
				T.expect(not string.find(source, pattern, 1, true), pattern .. " : effet de suspense lu sur le gagné")
			end
		end)
	end)

	T.describe("Tirage impossible à passer (#197)", function()
		T.it("aucun passage au clic, au toucher ni à Espace dans Client.Prize", function()
			local fs = require("@lune/fs")
			local source = fs.readFile("src/client/Prize.luau")
			for _, pattern in { "InputBegan", "ContextActionService", "BindAction", "SKIP_", "to skip" } do
				T.expect(not string.find(source, pattern, 1, true), pattern .. " : le tirage ne se passe pas")
			end
			T.expectEqual((RevealPlan :: any).SKIP_AFTER, nil)
		end)
		T.it("durée du tirage par rareté, jusqu'à GO BACK", function()
			for rarity = 1, #Rarity.LIST do
				local low, high = math.huge, 0
				for _, dummy in Collection.DUMMIES do
					if dummy.rarity == rarity then
						for size = 1, #Collection.SIZES do
							local time =
								RevealPlan.revealTime(rarity, Collection.teaseSequence({ id = dummy.id, size = size }))
							low, high = math.min(low, time), math.max(high, time)
						end
					end
				end
				if high > 0 then
					print(
						string.format(
							"[mesure] %s : GO BACK après %.1f à %.1f s (fermeture auto %d s plus tard)",
							Rarity.LIST[rarity].name,
							low,
							high,
							RevealPlan.get(rarity).autoClose
						)
					)
				end
			end
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
		T.it("une phrase propre à chaque secret, à sa rareté au-delà de Secret ou à sa famille (#94)", function()
			T.expectEqual(RevealPlan.secretLine("king"), "THE CRASH KINGDOM HAS FOUND ITS KING...")
			for _, dummy in Collection.DUMMIES do
				if dummy.rarity == 7 and table.find(Collection.DRAWN, dummy) then
					T.expect(RevealPlan.SECRET_LINES[dummy.id] ~= nil, dummy.id .. " a sa phrase")
				end
				if dummy.rarity >= 7 then
					T.expect(
						RevealPlan.secretLine(dummy.id) ~= RevealPlan.SECRET_LINE_DEFAULT,
						dummy.id .. " a une phrase"
					)
				end
			end
			T.expectEqual(RevealPlan.secretLine("golden_void"), RevealPlan.SECRET_LINES.void)
			T.expectEqual(RevealPlan.secretLine("radiant_king"), RevealPlan.RARITY_LINES[8])
			T.expectEqual(RevealPlan.secretLine("inconnu"), RevealPlan.SECRET_LINE_DEFAULT)
			for _, line in RevealPlan.RARITY_LINES do
				T.expect(
					#line / RevealPlan.TYPE_RATE < RevealPlan.CINEMATIC[1].duration - 0.8,
					line .. " : lue au moins 0,8 s"
				)
			end
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
			T.expectEqual(
				RevealPlan.announceText("You", "Neon Dummy", 6, "100K", "ff466e"),
				'You pulled a <font color="#ff466e">MYTHIC Neon Dummy</font>! 1 IN 100K'
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
			for _, value in { nil, 0, #Rarity.LIST + 1, "nope", "king:99", true } do
				T.expectEqual(RevealPlan.debugEntry(value, fixed(0)), nil, tostring(value))
			end
		end)
	end)
end
