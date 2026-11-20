-- Inventory : stock, pose (main, AUTO, Place best), retrait, vente, présentoirs achetés, Index, sauvegarde et
-- migration, encodage pour les attributs.
return function(T, Loader)
	local loader = Loader.new()
	local Collection = loader:require("src/shared/Collection")
	local CourseLayout = loader:require("src/shared/CourseLayout")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Inventory = loader:require("src/shared/Inventory")

	local crash = { id = "crash", size = 1 } -- 4 $/s
	local rookie = { id = "rookie", size = 1 } -- 5 $/s
	local mint = { id = "mint", size = 1 } -- 15 $/s (Uncommon)
	local biker = { id = "biker", size = 1 } -- 22 $/s (Uncommon)
	local gold = { id = "gold", size = 1 } -- 2 500 $/s

	-- Cette méthode permet de donner une collection dont la base contient `placed` (dans l'ordre) et le stock `stock`
	-- lorsqu'un test part d'un état précis.
	local function make(placed: { any }, stock: { any }?): any
		local data = Inventory.new()
		for display, entry in placed do
			data.base[display] = if entry then table.clone(entry) else false
		end
		for _, entry in stock or {} do
			table.insert(data.stock, table.clone(entry))
		end
		return data
	end

	-- Cette méthode permet de lister les clés des présentoirs achetés (« - » si vide) lorsqu'un test compare une base.
	local function baseKeys(data: any): string
		local keys = {}
		for display = 1, data.displays do
			local entry = data.base[display]
			table.insert(keys, if entry then Inventory.key(entry) else "-")
		end
		return table.concat(keys, " ")
	end

	-- Cette méthode permet de lister les clés du stock triées lorsqu'un test compare un stock sans tenir à l'ordre.
	local function stockKeys(data: any): string
		local keys = {}
		for _, entry in data.stock do
			table.insert(keys, Inventory.key(entry))
		end
		table.sort(keys)
		return table.concat(keys, " ")
	end

	T.describe("Inventory.new / add", function()
		T.it("base neuve : DISPLAY_START présentoirs achetés, DISPLAY_MAX emplacements vides", function()
			local data = Inventory.new()
			T.expectEqual(data.displays, GameConfig.DISPLAY_START)
			T.expectEqual(#data.base, CourseLayout.DISPLAY_MAX)
			T.expectEqual(#data.stock, 0)
		end)
		T.it("deux gains sans poser : les deux sont au stock (#54)", function()
			local data = Inventory.new()
			T.expectEqual(Inventory.add(data, crash), 0)
			T.expectEqual(Inventory.add(data, mint), 0)
			T.expectEqual(stockKeys(data), "crash:1 mint:1")
		end)
		T.it("au-delà de INVENTORY_MAX, le moins rentable du stock est vendu d'office", function()
			local data = Inventory.new()
			for _ = 1, GameConfig.INVENTORY_MAX - 1 do
				Inventory.add(data, mint)
			end
			Inventory.add(data, rookie)
			T.expectEqual(#data.stock, GameConfig.INVENTORY_MAX)
			-- Le 201e (un Gold) fait sortir le Rookie, le moins rentable
			T.expectEqual(Inventory.add(data, gold), Inventory.sellValue(rookie))
			T.expectEqual(#data.stock, GameConfig.INVENTORY_MAX)
			T.expect(Inventory.findStock(data, "rookie:1") == nil, "Rookie vendu")
			T.expect(Inventory.findStock(data, "gold:1") ~= nil, "Gold gardé")
			-- Un nouveau moins rentable que tout le stock est vendu lui-même
			T.expectEqual(Inventory.add(data, crash), Inventory.sellValue(crash))
			T.expect(Inventory.findStock(data, "crash:1") == nil, "Crash vendu")
		end)
	end)

	T.describe("Inventory.discover", function()
		T.it("nouveau la première fois, meilleure taille gardée", function()
			local data = Inventory.new()
			T.expect(Inventory.discover(data, { id = "gold", size = 2 }), "nouveau")
			T.expect(not Inventory.discover(data, { id = "gold", size = 1 }), "déjà vu")
			T.expectEqual(data.index.gold, 2)
			Inventory.discover(data, { id = "gold", size = 4 })
			T.expectEqual(data.index.gold, 4)
		end)
		T.it("l'Index survit à la vente", function()
			local data = Inventory.new()
			Inventory.discover(data, mint)
			Inventory.add(data, mint)
			Inventory.sell(data, 1)
			T.expectEqual(data.index.mint, 1)
		end)
	end)

	T.describe("Inventory.place / autoTarget", function()
		T.it("pose à la main : seulement sur un présentoir acheté et libre", function()
			local data = make({ mint }, { crash, crash })
			T.expectEqual(Inventory.place(data, 1, 1), nil)
			T.expectEqual(Inventory.place(data, 1, GameConfig.DISPLAY_START + 1), nil)
			T.expectEqual(Inventory.place(data, 1, 3), 3)
			T.expectEqual(baseKeys(data), "mint:1 - crash:1 - - -")
			T.expectEqual(stockKeys(data), "crash:1")
		end)
		T.it("AUTO : premier présentoir libre", function()
			local data = make({ mint, false, mint }, { crash })
			T.expectEqual(Inventory.place(data, 1), 2)
		end)
		T.it("base pleine : AUTO remplace le moins rentable s'il rapporte plus, l'ancien retourne au stock", function()
			local data = make({ mint, mint, crash, mint, mint, mint }, { gold })
			T.expectEqual(Inventory.place(data, 1), 3)
			T.expectEqual(baseKeys(data), "mint:1 mint:1 gold:1 mint:1 mint:1 mint:1")
			T.expectEqual(stockKeys(data), "crash:1")
		end)
		T.it("base pleine et pas plus rentable : le nouveau reste au stock, rien n'est vendu", function()
			local data = make({ mint, mint, mint, mint, mint, mint }, { crash })
			T.expectEqual(Inventory.place(data, 1), nil)
			T.expectEqual(stockKeys(data), "crash:1")
			T.expectEqual(Inventory.autoTarget(data, mint), nil, "égalité : pas d'échange")
		end)
		T.it("les présentoirs achetés comptent", function()
			local data = make({ mint, mint, mint, mint, mint, mint }, { crash })
			data.displays += 1
			T.expectEqual(Inventory.place(data, 1), 7)
		end)
	end)

	T.describe("Inventory.remove", function()
		T.it("rend le posé au stock", function()
			local data = make({ mint, crash })
			T.expect(Inventory.remove(data, 2), "retiré")
			T.expectEqual(baseKeys(data), "mint:1 - - - - -")
			T.expectEqual(stockKeys(data), "crash:1")
		end)
		T.it("refuse un présentoir vide, invalide, ou un stock plein", function()
			local data = make({ mint })
			T.expect(not Inventory.remove(data, 2), "vide")
			T.expect(not Inventory.remove(data, "1"), "pas un nombre")
			T.expect(not Inventory.remove(data, 1.5), "pas entier")
			for _ = 1, GameConfig.INVENTORY_MAX do
				table.insert(data.stock, crash)
			end
			T.expect(not Inventory.remove(data, 1), "stock plein")
		end)
	end)

	T.describe("Inventory.placeBest", function()
		T.it("base pleine → les plus rentables (posés et stock) sur les présentoirs", function()
			local data = make({ crash, mint, rookie, mint, crash, mint }, { gold, biker, crash })
			T.expect(Inventory.placeBest(data), "changé")
			T.expectEqual(Collection.baseIncome(data.base, data.displays), 2500 + 22 + 15 * 3 + 5)
			T.expectEqual(stockKeys(data), "crash:1 crash:1 crash:1")
			-- Les posés gardés n'ont pas bougé
			T.expectEqual(Inventory.key(data.base[2]), "mint:1")
			T.expectEqual(Inventory.key(data.base[4]), "mint:1")
			T.expectEqual(Inventory.key(data.base[6]), "mint:1")
		end)
		T.it("remplit les présentoirs libres, ne change rien si c'est déjà le mieux", function()
			local data = make({ mint }, { crash })
			T.expect(Inventory.placeBest(data), "posé")
			T.expectEqual(baseKeys(data), "mint:1 crash:1 - - - -")
			T.expect(not Inventory.placeBest(data), "rien à faire")
		end)
		T.it("à égalité, le posé reste", function()
			local data = make({ mint, mint, mint, mint, mint, mint }, { mint })
			T.expect(not Inventory.placeBest(data), "rien ne bouge")
		end)
	end)

	T.describe("Inventory.sell / sellRarity / sellValue", function()
		T.it("prix = SELL_MINUTES minutes de revenu", function()
			T.expectEqual(GameConfig.SELL_MINUTES, 2)
			T.expectEqual(Inventory.sellValue(crash), 4 * 120)
			local huge = { id = "gold", size = 3 }
			T.expectEqual(Inventory.sellValue(huge), Collection.income(huge) * 120)
		end)
		T.it("vend un mannequin du stock, pas un posé", function()
			local data = make({ gold }, { crash, mint })
			T.expectEqual(Inventory.sell(data, Inventory.findStock(data, "mint:1") :: number), 15 * 120)
			T.expectEqual(stockKeys(data), "crash:1")
			T.expectEqual(Inventory.findStock(data, "gold:1"), nil)
			T.expectEqual(Inventory.sell(data, 5), 0)
		end)
		T.it("vend tout le stock d'une rareté", function()
			local data = make({ crash }, { crash, mint, rookie, biker, gold })
			local count, total = Inventory.sellRarity(data, 1)
			T.expectEqual(count, 2)
			T.expectEqual(total, (4 + 5) * 120)
			T.expectEqual(stockKeys(data), "biker:1 gold:1 mint:1")
			T.expectEqual(Inventory.key(data.base[1]), "crash:1", "le posé reste")
		end)
		T.it("le dernier gagné est oublié une fois vendu ou posé", function()
			local data = make({}, { mint, mint })
			data.last = mint
			Inventory.sell(data, 1)
			T.expect(data.last ~= nil, "un doublon reste")
			Inventory.place(data, 1, 1)
			T.expectEqual(data.last, nil)
		end)
	end)

	T.describe("Inventory.displayPrice / buyDisplay", function()
		T.it("prix croissants jusqu'à DISPLAY_MAX", function()
			local last = 0
			for displays = GameConfig.DISPLAY_START, CourseLayout.DISPLAY_MAX - 1 do
				local price = Inventory.displayPrice(displays) :: number
				T.expect(price > last, "prix croissant")
				last = price
			end
			T.expectEqual(Inventory.displayPrice(CourseLayout.DISPLAY_MAX), nil)
		end)
		T.it("achat : prix déduit, refus si argent insuffisant ou au maximum", function()
			local data = Inventory.new()
			local price = Inventory.displayPrice(data.displays) :: number
			T.expectEqual(Inventory.buyDisplay(data, price - 1), nil)
			T.expectEqual(data.displays, GameConfig.DISPLAY_START)
			T.expectEqual(Inventory.buyDisplay(data, price), price)
			T.expectEqual(data.displays, GameConfig.DISPLAY_START + 1)
			data.displays = CourseLayout.DISPLAY_MAX
			T.expectEqual(Inventory.buyDisplay(data, math.huge), nil)
		end)
	end)

	T.describe("Inventory.read / write", function()
		T.it("aller-retour", function()
			local data = make({ gold, false, mint }, { crash, crash })
			data.displays = 8
			data.base[8] = biker
			Inventory.discover(data, gold)
			Inventory.discover(data, { id = "mint", size = 3 })
			local copy = Inventory.read(Inventory.write(data))
			T.expectEqual(baseKeys(copy), baseKeys(data))
			T.expectEqual(stockKeys(copy), "crash:1 crash:1")
			T.expectEqual(copy.displays, 8)
			T.expectEqual(copy.index.mint, 3)
			T.expectEqual(copy.index.gold, 1)
			T.expectEqual(copy.index.crash, 1, "possédé = dans l'Index")
		end)
		T.it("migration de #13 : mannequin en main → stock, discovered → Index", function()
			local saved = {
				base = { mint, false, { id = "gold", size = 2 } },
				pending = crash,
				discovered = { "mint", "gold", "crash", "rookie", "nope" },
			}
			local data = Inventory.read(saved)
			T.expectEqual(data.displays, GameConfig.DISPLAY_START)
			T.expectEqual(baseKeys(data), "mint:1 - gold:2 - - -")
			T.expectEqual(stockKeys(data), "crash:1")
			T.expectEqual(Inventory.key(data.last), "crash:1", "toujours proposé à la pose")
			T.expectEqual(data.index.rookie, 1)
			T.expectEqual(data.index.gold, 2, "taille relevée par ce qui est posé")
			T.expectEqual(data.index.nope, nil)
		end)
		T.it("entrées abîmées ignorées, présentoirs bornés", function()
			local data = Inventory.read({
				displays = 99,
				stock = { crash, { id = "nope", size = 1 }, "x" },
				index = { crash = 9, mint = 2 },
			})
			T.expectEqual(data.displays, CourseLayout.DISPLAY_MAX)
			T.expectEqual(stockKeys(data), "crash:1")
			T.expectEqual(data.index.crash, 1)
			T.expectEqual(data.index.mint, 2)
			T.expectEqual(Inventory.read(nil).displays, GameConfig.DISPLAY_START)
		end)
		T.it("stock plafonné à INVENTORY_MAX, migration comprise (les moins rentables écartés)", function()
			local stock = {}
			for _ = 1, GameConfig.INVENTORY_MAX do
				table.insert(stock, mint)
			end
			local data = Inventory.read({ stock = stock, pending = gold, base = { [1] = crash } })
			T.expectEqual(#data.stock, GameConfig.INVENTORY_MAX)
			T.expect(Inventory.findStock(data, "gold:1") ~= nil, "Gold gardé")
		end)
		T.it("un posé sur un présentoir non acheté retourne au stock", function()
			local data = Inventory.read({ base = { false, false, false, false, false, false, false, mint } })
			T.expectEqual(stockKeys(data), "mint:1")
		end)
	end)

	T.describe("Inventory.rows", function()
		T.it("posés d'abord, puis stock regroupé, $/s décroissant", function()
			local data = make({ crash, gold }, { mint, crash, mint, biker })
			local rows = Inventory.rows(data.base, data.displays, data.stock)
			local summary = {}
			for _, row in rows do
				table.insert(summary, string.format("%s%s×%d", row.key, if row.display then "@" else "", row.count))
			end
			T.expectEqual(table.concat(summary, " "), "gold:1@×1 crash:1@×1 biker:1×1 mint:1×2 crash:1×1")
		end)
	end)

	T.describe("Inventory.encode / decode", function()
		T.it("liste, base et Index font l'aller-retour", function()
			local list = { crash, { id = "gold", size = 3 } }
			T.expectEqual(Inventory.encodeList(list), "crash:1,gold:3")
			local back = Inventory.decodeList("crash:1,gold:3,nope:1,")
			T.expectEqual(#back, 2)
			T.expectEqual(Inventory.key(back[2]), "gold:3")
			local data = make({ false, mint })
			local base = Inventory.decodeBase(Inventory.encodeBase(data.base))
			T.expectEqual(#base, CourseLayout.DISPLAY_MAX)
			T.expectEqual(base[1], false)
			T.expectEqual(Inventory.key(base[2]), "mint:1")
			local index = Inventory.decodeIndex(Inventory.encodeIndex({ gold = 2, crash = 1 }))
			T.expectEqual(index.gold, 2)
			T.expectEqual(index.crash, 1)
			T.expectEqual(#Inventory.decodeList(nil), 0)
		end)
		T.it("parseKey refuse les clés illisibles ou inconnues", function()
			T.expectEqual(Inventory.key(Inventory.parseKey("mint:2") :: any), "mint:2")
			T.expectEqual(Inventory.parseKey("mint"), nil)
			T.expectEqual(Inventory.parseKey("mint:9"), nil)
			T.expectEqual(Inventory.parseKey(42), nil)
		end)
	end)
end
