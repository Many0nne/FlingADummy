-- Boutique Robux (#160) : catalogue de 09 (prix, sections), reçus attribués une seule fois, sauvegarde relue, boosts
-- cumulés et décomptés, multiplicateurs (CHANCE, revenu, EXP), Big Base, argent rapide, pack de démarrage, Rainbow
-- Dummy, CHANCE du lancer multipliée.
return function(T, Loader)
	local loader = Loader.new()
	local CourseLayout = loader:require("src/shared/CourseLayout")
	local Economy = loader:require("src/shared/Economy")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Inventory = loader:require("src/shared/Inventory")
	local Store = loader:require("src/shared/Store")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")

	-- Cette méthode permet de construire ce que voit le calcul des multiplicateurs lorsqu'un test combine des sources.
	local function active(passes: { string }?, boosts: { string }?, serverLuck: boolean?, lucky: boolean?): any
		local p, b = {}, {}
		for _, id in passes or {} do
			p[id] = true
		end
		for _, kind in boosts or {} do
			b[kind] = 60
		end
		return { passes = p, boosts = b, serverLuck = serverLuck, lucky = lucky }
	end

	T.describe("Store.ITEMS (catalogue de 09)", function()
		T.it("reprend les prix de 09 tels quels", function()
			local prices = {
				StarterPack = 99,
				Luck2x = 249,
				Money2x = 199,
				VIP = 99,
				StrongArms = 149,
				BigBase = 79,
				Rainbow = 799,
				LuckPotion = 39,
				MegaLuck = 99,
				ServerLuck = 99,
				LuckyThrow1 = 19,
				LuckyThrow5 = 79,
				LuckyThrow20 = 249,
				MoneyBoost = 49,
				TrainBoost = 49,
				CashSmall = 29,
				CashMedium = 99,
				CashLarge = 299,
				CashHuge = 799,
			}
			local count = 0
			for id, price in prices do
				local item = Store.get(id)
				T.expect(item ~= nil, id .. " au catalogue")
				T.expectEqual(item.price, price)
				count += 1
			end
			T.expectEqual(#Store.ITEMS, count)
		end)
		T.it("six passes, le reste en produits ; chaque article dans une section de la fenêtre", function()
			T.expectEqual(#Store.section("Passes"), 6)
			local sections = {}
			for _, section in Store.SECTIONS do
				sections[section.id] = true
			end
			for _, item in Store.ITEMS do
				T.expect(sections[item.section], item.id .. " : section connue")
				T.expectEqual(item.kind == "Pass", item.section == "Passes")
				if item.boost then
					T.expect(Store.BOOSTS[item.boost] ~= nil, item.id .. " : boost connu")
				end
			end
		end)
		T.it("articles créés (#172) : identifiant Roblox unique par type, retrouvé par Store.byAsset", function()
			local seen = {}
			for _, item in Store.ITEMS do
				T.expect(item.assetId > 0, item.id .. " : identifiant Roblox renseigné")
				local key = item.kind .. ":" .. item.assetId
				T.expect(not seen[key], item.id .. " : identifiant déjà pris par " .. tostring(seen[key]))
				seen[key] = item.id
				T.expectEqual(Store.byAsset(item.kind, item.assetId), item)
			end
			T.expectEqual(Store.byAsset("Product", 0), nil)
			T.expectEqual(Store.get("Nope"), nil)
			T.expectEqual(Store.get(nil), nil)
		end)
	end)

	T.describe("Store.applyReceipt (reçus)", function()
		T.it("un reçu rejoué deux fois n'est attribué qu'une fois", function()
			local state = Store.new()
			local grants = 0
			local function grant()
				grants += 1
				return true
			end
			T.expect(Store.applyReceipt(state, "abc", grant), "premier passage attribué")
			T.expect(Store.applyReceipt(state, "abc", grant), "rejeu : déjà attribué")
			T.expectEqual(grants, 1)
			T.expect(Store.applyReceipt(state, "def", grant), "autre reçu")
			T.expectEqual(grants, 2)
		end)
		T.it("un reçu dont l'attribution échoue n'est pas noté (Roblox le représentera)", function()
			local state = Store.new()
			T.expect(not Store.applyReceipt(state, "x", function()
				return false
			end), "refusé")
			T.expect(not Store.hasReceipt(state, "x"), "pas noté")
		end)
		T.it("garde les RECEIPT_KEEP derniers reçus, sauvegarde comprise", function()
			local state = Store.new()
			for i = 1, Store.RECEIPT_KEEP + 5 do
				Store.noteReceipt(state, "r" .. i)
			end
			T.expectEqual(#state.receipts, Store.RECEIPT_KEEP)
			T.expect(not Store.hasReceipt(state, "r1"), "le plus ancien est oublié")
			local back = Store.read(Store.write(state))
			T.expect(Store.hasReceipt(back, "r" .. (Store.RECEIPT_KEEP + 5)), "le plus récent est relu")
		end)
	end)

	T.describe("Store.read / write", function()
		T.it("relit passes, boosts, lancers chanceux, temps de jeu et pack", function()
			local state = Store.new()
			state.passes.VIP = true
			Store.addBoost(state, "Money", 1800)
			state.lucky = 7
			state.played = 125.6
			state.starter = true
			local back = Store.read(Store.write(state))
			T.expect(back.passes.VIP, "VIP")
			T.expectEqual(back.boosts.Money, 1800)
			T.expectEqual(back.lucky, 7)
			T.expectEqual(back.played, 125)
			T.expect(back.starter, "pack acheté")
		end)
		T.it("ignore ce qui est inconnu ou abîmé", function()
			local back = Store.read({
				passes = { Nope = true, LuckPotion = true, VIP = "oui" },
				boosts = { Nope = 10, Luck2 = -5, Train = 0 / 0, Money = 1e12 },
				lucky = -3,
				receipts = { 1, "ok" },
			})
			T.expectEqual(next(back.passes), nil)
			T.expectEqual(back.boosts.Luck2, nil)
			T.expectEqual(back.boosts.Train, nil)
			T.expectEqual(back.boosts.Money, Store.BOOST_MAX)
			T.expectEqual(back.lucky, 0)
			T.expectEqual(#back.receipts, 1)
			T.expectEqual(Store.read(nil).lucky, 0)
		end)
		T.it("passes publiés : aller-retour dans l'ordre du catalogue", function()
			local text = Store.encodePasses({ VIP = true, Luck2x = true })
			T.expectEqual(text, "Luck2x,VIP")
			local back = Store.decodePasses(text .. ",Nope,CashSmall")
			T.expect(back.VIP and back.Luck2x, "relus")
			T.expectEqual(back.CashSmall, nil)
			T.expectEqual(next(Store.decodePasses(nil)), nil)
		end)
	end)

	T.describe("Store.addBoost / tick (minuteurs)", function()
		T.it("un deuxième achat prolonge la durée restante", function()
			local state = Store.new()
			Store.addBoost(state, "Luck2", 900)
			Store.tick(state, 100)
			Store.addBoost(state, "Luck2", 900)
			T.expectEqual(state.boosts.Luck2, 1700)
		end)
		T.it("décompte le temps passé en jeu et annonce les boosts finis", function()
			local state = Store.new()
			Store.addBoost(state, "Money", 10)
			Store.addBoost(state, "Train", 30)
			local ended = Store.tick(state, 10)
			T.expectEqual(#ended, 1)
			T.expectEqual(ended[1], "Money")
			T.expectEqual(state.boosts.Money, nil)
			T.expectEqual(state.boosts.Train, 20)
			T.expectEqual(state.played, 10)
		end)
	end)

	T.describe("Multiplicateurs", function()
		T.it("CHANCE : passe × potion la plus forte × serveur × lancer chanceux", function()
			T.expectEqual(Store.luck(active()), 1)
			T.expectEqual(Store.luck(active({ "Luck2x" })), 2)
			T.expectEqual(Store.luck(active(nil, { "Luck2" })), 2)
			T.expectEqual(Store.luck(active(nil, { "Luck2", "Luck5" })), 5)
			T.expectEqual(Store.luck(active({ "Luck2x" }, { "Luck5" }, true)), 20)
			T.expectEqual(Store.luck(active(nil, nil, nil, true)), 50)
		end)
		T.it("revenu : 2x Money × VIP (+25 %) × boost d'argent", function()
			T.expectEqual(Store.income(active()), 1)
			T.expectEqual(Store.income(active({ "VIP" })), 1.25)
			T.expectEqual(Store.income(active({ "Money2x", "VIP" }, { "Money" })), 5)
		end)
		T.it("EXP : Strong Arms × boost d'entraînement", function()
			T.expectEqual(Store.training(active({ "StrongArms" })), 2)
			T.expectEqual(Store.training(active({ "StrongArms" }, { "Train" })), 4)
		end)
		T.it("la CHANCE du lancer compte le multiplicateur de la boutique", function()
			local base = Economy.chance({ distance = 0, bones = 0, smashed = 0, luck = 2, rebirth = 2 })
			local boosted = Economy.chance({ distance = 0, bones = 0, smashed = 0, luck = 2, rebirth = 2, boost = 50 })
			T.expectEqual(boosted.boost, 50)
			T.expectNear(boosted.total, base.total * 50, 0.01)
		end)
	end)

	T.describe("Big Base", function()
		T.it("+10 présentoirs au-delà des achetés, jusqu'à DISPLAY_ROOM", function()
			T.expectEqual(Store.displayBonus({ BigBase = true }), 10)
			T.expectEqual(Store.displayBonus({}), 0)
			T.expectEqual(CourseLayout.DISPLAY_ROOM, CourseLayout.DISPLAY_MAX + Store.BIG_BASE)
			local data = Inventory.new(Store.BIG_BASE)
			T.expectEqual(Inventory.capacity(data), GameConfig.DISPLAY_START + 10)
			data.displays = CourseLayout.DISPLAY_MAX
			T.expectEqual(Inventory.capacity(data), CourseLayout.DISPLAY_ROOM)
		end)
		T.it("les présentoirs 31 à 40 se posent, comptent dans le revenu et survivent à la sauvegarde", function()
			local data = Inventory.new(Store.BIG_BASE)
			data.displays = CourseLayout.DISPLAY_MAX
			table.insert(data.stock, { id = "crash", size = 1 })
			T.expectEqual(Inventory.place(data, 1, CourseLayout.DISPLAY_ROOM), CourseLayout.DISPLAY_ROOM)
			T.expect(Inventory.income(data) > 0, "revenu du présentoir 40")
			local saved = Inventory.write(data)
			local back = Inventory.read(saved, Store.BIG_BASE)
			T.expect(back.base[CourseLayout.DISPLAY_ROOM] ~= false, "relu sur le présentoir 40")
			local without = Inventory.read(saved, 0)
			T.expectEqual(without.base[CourseLayout.DISPLAY_ROOM], false)
			T.expectEqual(#without.stock, 1) -- sans le passe : rendu au stock, rien ne se perd
		end)
		T.it("la base agrandie garde son entrée et s'allonge vers le fond", function()
			local center, size = CourseLayout.baseBox(1, false)
			local bigCenter, bigSize = CourseLayout.baseBox(1, true)
			T.expectEqual(size, CourseLayout.BASE_SIZE)
			T.expect(bigSize.Z > size.Z, "plus profonde")
			T.expectNear(center.Z + size.Z / 2, bigCenter.Z + bigSize.Z / 2, 1e-6)
			for _, position in CourseLayout.displayPositions(1, CourseLayout.DISPLAY_ROOM) do
				T.expect(math.abs(position.Z - bigCenter.Z) < bigSize.Z / 2, "présentoir dans la base agrandie")
			end
			local back = bigCenter - Vector3.new(0, 0, bigSize.Z / 2 - 1)
			T.expect(CourseLayout.isNearBase(1, back, true), "fond de la base agrandie : près")
		end)
	end)

	T.describe("Store.cash (argent rapide)", function()
		T.it("donne les minutes de revenu au revenu affiché", function()
			T.expectEqual(Store.cash(30, 1000), 1000 * 30 * 60)
			T.expectEqual(Store.cash(2880, 1e6), 1e6 * 2880 * 60)
		end)
		T.it("garde un revenu minimal pour un joueur sans revenu", function()
			T.expectEqual(Store.cash(30, 0), Store.CASH_MIN_INCOME * 30 * 60)
			T.expectEqual(Store.cash(30, 0 / 0), Store.CASH_MIN_INCOME * 30 * 60)
		end)
	end)

	T.describe("Pack de démarrage", function()
		T.it("offert pendant STARTER_WINDOW s de jeu, plus après, ni une fois acheté", function()
			local state = Store.new()
			T.expectEqual(Store.starterLeft(state), Store.STARTER_WINDOW)
			Store.tick(state, 600)
			T.expectEqual(Store.starterLeft(state), Store.STARTER_WINDOW - 600)
			state.starter = true
			T.expectEqual(Store.starterLeft(state), nil)
			state.starter = false
			Store.tick(state, Store.STARTER_WINDOW)
			T.expectEqual(Store.starterLeft(state), nil)
		end)
		T.it("contient lancers chanceux, deux boosts de 15 min et de l'argent", function()
			T.expectEqual(Store.STARTER.throws, 2)
			T.expectEqual(Store.STARTER.boosts.Luck2, 900)
			T.expectEqual(Store.STARTER.boosts.Money, 900)
			T.expect(Store.STARTER.minutes > 0, "argent")
		end)
		T.it(
			"deux reçus d'identifiants différents : pack attribué une fois, le second donne l'article de même prix",
			function()
				local state = Store.new()
				local pack = Store.get("StarterPack") :: any
				local given = {}
				-- Cette méthode permet de rejouer l'attribution du serveur (état, puis argent) lorsque un reçu arrive.
				local function grant()
					local granted, minutes = Store.applyProduct(state, pack)
					table.insert(given, { id = granted and granted.id, minutes = minutes })
					return granted ~= nil
				end
				T.expect(Store.applyReceipt(state, "r1", grant), "premier reçu attribué")
				T.expect(Store.applyReceipt(state, "r2", grant), "second reçu traité (pas de NotProcessedYet)")
				T.expect(Store.applyReceipt(state, "r2", grant), "rejeu du second : déjà attribué")
				T.expectEqual(#given, 2)
				T.expectEqual(given[1].id, "StarterPack")
				T.expectEqual(given[1].minutes, Store.STARTER.minutes)
				local replacement = Store.get(Store.STARTER_REPLACEMENT) :: any
				T.expectEqual(given[2].id, replacement.id)
				T.expectEqual(given[2].minutes, replacement.minutes)
				T.expectEqual(replacement.price, pack.price)
				-- Contenu du pack (lancers, boosts) donné une seule fois
				T.expectEqual(state.lucky, Store.STARTER.throws)
				T.expectEqual(state.boosts.Luck2, Store.STARTER.boosts.Luck2)
				T.expectEqual(state.boosts.Money, Store.STARTER.boosts.Money)
				T.expect(state.starter, "pack noté acheté")
			end
		)
		T.it("applyProduct : effets des autres produits inchangés, passes refusés", function()
			local state = Store.new()
			local potion, minutes = Store.applyProduct(state, Store.get("LuckPotion") :: any)
			T.expectEqual((potion :: any).id, "LuckPotion")
			T.expectEqual(minutes, nil)
			T.expectEqual(state.boosts.Luck2, 900)
			Store.applyProduct(state, Store.get("LuckyThrow5") :: any)
			T.expectEqual(state.lucky, 5)
			local cash, cashMinutes = Store.applyProduct(state, Store.get("CashLarge") :: any)
			T.expectEqual((cash :: any).id, "CashLarge")
			T.expectEqual(cashMinutes, 720)
			local luck = Store.applyProduct(state, Store.get("ServerLuck") :: any)
			T.expectEqual((luck :: any).id, "ServerLuck")
			T.expectEqual(Store.applyProduct(state, Store.get("VIP") :: any), nil)
		end)
		T.it(
			"canPrompt : invite du pack seulement pendant l'offre, une à la fois, plus après un achat confirmé",
			function()
				local state = Store.new()
				local pack = Store.get("StarterPack") :: any
				T.expect(Store.promptedByServer(pack), "invite ouverte par le serveur")
				T.expect(
					not Store.promptedByServer(Store.get("CashSmall") :: any),
					"autres produits : invite du client"
				)
				T.expect(Store.canPrompt(state, pack, nil), "offre en cours")
				T.expect(not Store.canPrompt(state, pack, 2), "invite déjà ouverte (double clic)")
				T.expect(Store.canPrompt(state, pack, Store.PROMPT_TIMEOUT), "invite perdue : rouverte")
				T.expect(not Store.canPrompt(state, pack, Store.PROMPT_TIMEOUT, true), "achat confirmé, reçu attendu")
				state.starter = true
				T.expect(not Store.canPrompt(state, pack, nil), "déjà acheté")
				state.starter = false
				Store.tick(state, Store.STARTER_WINDOW)
				T.expect(not Store.canPrompt(state, pack, nil), "offre passée")
				T.expect(not Store.canPrompt(state, Store.get("VIP") :: any, nil), "passe : pas un produit")
			end
		)
	end)

	T.describe("Rainbow Dummy", function()
		T.it("1,5 × la chance du meilleur possédé, 15x au moins", function()
			T.expectEqual(ThrowDummies.luckOf(ThrowDummies.RAINBOW, 1), 15)
			local last = #ThrowDummies.LIST
			T.expectEqual(ThrowDummies.luckOf(ThrowDummies.RAINBOW, last), ThrowDummies.LIST[last].luck * 1.5)
			T.expectEqual(ThrowDummies.luckOf(2, last), ThrowDummies.LIST[2].luck)
		end)
		T.it("hors du catalogue séquentiel : ni acheté ni compté, équipé seulement avec le passe", function()
			T.expect(not ThrowDummies.isIndex(ThrowDummies.RAINBOW), "pas un indice du catalogue")
			T.expectEqual(ThrowDummies.get(ThrowDummies.RAINBOW).name, "Rainbow Dummy")
			T.expectEqual(ThrowDummies.act(3, 1, 0, "Equip", ThrowDummies.RAINBOW, false), nil)
			local result = ThrowDummies.act(3, 1, 0, "Equip", ThrowDummies.RAINBOW, true)
			T.expectEqual(result.equipped, ThrowDummies.RAINBOW)
			T.expectEqual(result.owned, 3)
			local owned, equipped = ThrowDummies.sanitize(3, ThrowDummies.RAINBOW)
			T.expectEqual(owned, 3)
			T.expectEqual(equipped, ThrowDummies.RAINBOW)
			-- Acheter le suivant ne déséquipe pas le Rainbow Dummy
			local bought = ThrowDummies.act(3, ThrowDummies.RAINBOW, 1e15, "Buy", 4, true)
			T.expectEqual(bought.owned, 4)
			T.expectEqual(bought.equipped, ThrowDummies.RAINBOW)
		end)
	end)

	T.describe("icônes dessinées (#173)", function()
		T.it(
			"donne à chaque article et chaque section une icône connue de Assets.ICONS, avec un emoji de repli",
			function()
				local Assets = loader:require("src/shared/Assets")
				for _, entry in Store.ITEMS do
					T.expect(Assets.ICONS[entry.art] ~= nil, entry.id .. " : icône " .. tostring(entry.art))
					T.expect(entry.icon ~= "", entry.id .. " : emoji de repli")
				end
				for _, section in Store.SECTIONS do
					T.expect(Assets.ICONS[section.art] ~= nil, section.id .. " : icône " .. tostring(section.art))
					T.expect(section.icon ~= "", section.id .. " : emoji de repli")
				end
				T.expect(Assets.ICONS.rebirth ~= nil, "icône Rebirth déclarée")
			end
		)
		T.it("publie les icônes de la boutique et celle du bouton Rebirth (identifiant > 0)", function()
			local Assets = loader:require("src/shared/Assets")
			local names = { rebirth = true }
			for _, entry in Store.ITEMS do
				names[entry.art] = true
			end
			for _, section in Store.SECTIONS do
				names[section.art] = true
			end
			for name in names do
				T.expect(Assets.ICONS[name] > 0, name .. " publiée")
			end
		end)
	end)
	end)

	T.describe("Store.clock", function()
		T.it("écrit les minuteurs en m:ss ou h:mm:ss", function()
			T.expectEqual(Store.clock(899.2), "15:00")
			T.expectEqual(Store.clock(59), "0:59")
			T.expectEqual(Store.clock(3723), "1:02:03")
			T.expectEqual(Store.clock(-4), "0:00")
		end)
	end)
end
