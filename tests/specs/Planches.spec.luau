-- Planches de référence (#121) : plan des prises de vue (Shared.PlanchePlan) et garde-fou du manifeste
-- docs/planches/manifest.json (chaque planche liste tout le catalogue, avec l'apparence actuelle de chaque élément).
return function(T, Loader, Lib)
	local loader = Loader.new()
	local BaseLook = loader:require("src/shared/BaseLook")
	local Collection = loader:require("src/shared/Collection")
	local PlanchePlan = loader:require("src/shared/PlanchePlan")
	local Rarity = loader:require("src/shared/Rarity")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")
	local Training = loader:require("src/shared/Training")

	local REGENERATE = "planches à régénérer (docs/planches/README.md : lune run tools/planches-manifest.luau,"
		.. " prises de vue en Studio, python -I tools/planches.py)"

	-- Cette méthode permet de compter les cases d'une planche (toutes ses prises) lorsqu'un test la compare au
	-- catalogue.
	local function cells(sheet: string): { any }
		local list = {}
		for _, shot in PlanchePlan.shots(sheet) do
			for _, item in shot.items do
				table.insert(list, item)
			end
		end
		return list
	end

	T.describe("PlanchePlan", function()
		T.it("chaque planche montre tout son catalogue, une fois chacun", function()
			local expected = {
				collection = #Collection.DUMMIES,
				["a-lancer"] = #ThrowDummies.LIST,
				base = #BaseLook.BASE_TIERS,
				entrainement = #Training.GEARS,
			}
			for _, sheet in PlanchePlan.SHEETS do
				local list = cells(sheet)
				T.expect(
					#list == expected[sheet],
					string.format("%s : %d cases, %d attendues", sheet, #list, expected[sheet])
				)
				local seen = {}
				for _, item in list do
					T.expect(not seen[item.key], sheet .. " : " .. tostring(item.key) .. " en double")
					seen[item.key] = true
				end
			end
		end)

		T.it("une rangée de collection ne mélange pas les raretés et suit l'ordre du catalogue", function()
			local order = {}
			for _, shot in PlanchePlan.shots("collection") do
				T.expect(#shot.items <= PlanchePlan.ROW, shot.name .. " : trop de cases")
				for _, item in shot.items do
					T.expect(Collection.get(item.key).rarity == shot.group, shot.name .. " : " .. item.key)
					table.insert(order, item.key)
				end
			end
			for index, dummy in Collection.DUMMIES do
				T.expect(order[index] == dummy.id, "ordre : " .. tostring(order[index]) .. " au lieu de " .. dummy.id)
			end
			T.expect(PlanchePlan.shots("collection")[1].group == 1, "Common en premier")
			T.expect(
				PlanchePlan.shots("collection")[#PlanchePlan.shots("collection")].group == #Rarity.LIST,
				"Infinity en dernier"
			)
		end)

		T.it("chaque prise de palier de base montre un nombre de présentoirs possible (#156)", function()
			local GameConfig = loader:require("src/shared/GameConfig")
			local CourseLayout = loader:require("src/shared/CourseLayout")
			for tier, look in BaseLook.BASE_TIERS do
				T.expect(
					look.displays >= GameConfig.DISPLAY_START and look.displays <= CourseLayout.DISPLAY_MAX,
					string.format(
						"palier %d à %d présentoirs : PhotoStudio montrerait un pad impossible",
						tier,
						look.displays
					)
				)
				T.expectEqual(BaseLook.baseTier(look.displays), tier, "prise du palier " .. tier)
			end
		end)

		T.it("retrouve une prise par son nom, rien pour un nom inconnu", function()
			local lastBase, gears = #BaseLook.BASE_TIERS, #Training.GEARS
			T.expect(PlanchePlan.find("base-" .. lastBase).items[1].key == lastBase, "dernier palier de base")
			T.expect(PlanchePlan.find("entrainement-" .. gears).framing == "station", "dernier palier d'appareil")
			T.expect(PlanchePlan.find("a-lancer-1").items[1].key == 1, "a-lancer-1")
			T.expect(PlanchePlan.find("base-" .. lastBase + 1) == nil, "palier de base au-delà du dernier")
			T.expect(PlanchePlan.find("decor-1") == nil, "decor-1")
			T.expect(PlanchePlan.find("collection") == nil, "sans numéro")
		end)

		T.it("la largeur cadrée remplit l'image : distance de la caméra", function()
			-- Champ vertical 30° : demi-hauteur = d × tan 15° ; image 2:1 → demi-largeur = 2 × d × tan 15°
			local d = PlanchePlan.distance(42, 2)
			T.expectNear(2 * d * math.tan(math.rad(15)), 21, 1e-9)
		end)
	end)

	T.describe("docs/planches/manifest.json", function()
		T.it("suit le catalogue et les apparences : sinon " .. REGENERATE, function()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			local fresh = Lib.Planches.build(Loader.new())
			local saved = serde.decode("json", fs.readFile(Lib.Planches.PATH))
			-- Comparaison case par case : le message nomme ce qui a changé
			local savedSheets = {}
			for _, sheet in saved.sheets or {} do
				savedSheets[sheet.name] = sheet
			end
			for _, sheet in fresh.sheets do
				local old = savedSheets[sheet.name]
				if old == nil then
					error(sheet.name .. " absente du manifeste")
				end
				local before = {}
				for _, shot in old.shots do
					for _, item in shot.items do
						before[tostring(item.key)] = serde.encode("json", item)
					end
				end
				for _, shot in sheet.shots do
					for _, item in shot.items do
						local key = tostring(item.key)
						T.expect(before[key] ~= nil, sheet.name .. " : " .. key .. " ajouté")
						T.expect(before[key] == serde.encode("json", item), sheet.name .. " : " .. key .. " modifié")
						before[key] = nil
					end
				end
				T.expect(next(before) == nil, sheet.name .. " : " .. tostring(next(before)) .. " retiré")
			end
			T.expect(
				serde.encode("json", saved) == serde.encode("json", serde.decode("json", serde.encode("json", fresh))),
				"ordre des prises ou cadrage changé"
			)
		end)
	end)
end
