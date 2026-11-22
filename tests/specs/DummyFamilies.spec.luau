-- Catalogue généré (#94) : familles × palettes, règles de cote et de revenu, looks reconstruits à partir des modèles
-- dessinés.
return function(T, Loader, Lib)
	local loader = Loader.new()
	local Collection = loader:require("src/shared/Collection")
	local DummyFamilies = loader:require("src/shared/DummyFamilies")
	local DummyModels = loader:require("src/shared/DummyModels")
	local DummyAura = loader:require("src/shared/DummyAura")
	local Rarity = loader:require("src/shared/Rarity")
	local Enum = require("@lune/roblox").Enum

	-- Cette méthode permet de donner les mannequins générés du catalogue (ceux qui ne sont pas dessinés) lorsqu'un test
	-- les parcourt.
	local function generated(): { any }
		local drawn = {}
		for _, dummy in Collection.DRAWN do
			drawn[dummy.id] = true
		end
		local list = {}
		for _, dummy in Collection.DUMMIES do
			if not drawn[dummy.id] then
				table.insert(list, dummy)
			end
		end
		return list
	end

	T.describe("assets/dummy/export/generated.json (aperçus et icônes des générés)", function()
		T.it("suit les palettes et les modèles : sinon réexporter, rendre et republier les icônes", function()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			local built = Lib.GeneratedLooks.build(Loader.new())
			local saved = serde.decode("json", fs.readFile(Lib.GeneratedLooks.PATH))
			local fresh = serde.decode("json", serde.encode("json", built, true))
			for id, look in fresh do
				T.expect(
					serde.encode("json", saved[id] or {}) == serde.encode("json", look),
					id
						.. " : lune run tools/export-generated-looks.luau, build_collection.py --generated, dummy_icons.py,"
						.. " puis publier l'icône (Assets.DUMMY_ICONS)"
				)
			end
			for id in saved do
				T.expect(fresh[id] ~= nil, id .. " n'est plus généré")
			end
		end)
	end)

	T.describe("DummyFamilies.PAIRS / PALETTES", function()
		T.it("une liste par rareté, familles et palettes connues, aucun couple en double", function()
			T.expectEqual(#DummyFamilies.PAIRS, #Rarity.LIST)
			local seen = {}
			for rarity, pairs in DummyFamilies.PAIRS do
				T.expect(#pairs >= 1, "rareté " .. rarity)
				for _, pair in pairs do
					T.expect(DummyModels.LOOKS[pair[1]] ~= nil, "famille " .. pair[1])
					T.expect(DummyFamilies.PALETTES[pair[2]] ~= nil, "palette " .. pair[2])
					local key = pair[2] .. "_" .. pair[1]
					T.expect(not seen[key], "couple en double " .. key)
					seen[key] = true
				end
			end
		end)
		T.it("aucune palette en verre ni en champ de force (invisibles dans les fenêtres)", function()
			for id, palette in DummyFamilies.PALETTES do
				for _, material in { palette.material, palette.accessoryMaterial } do
					T.expect(material ~= Enum.Material.Glass and material ~= Enum.Material.ForceField, id)
				end
				T.expect(palette.tint >= 0 and palette.tint <= 1, id .. " teinte")
			end
		end)
	end)

	T.describe("DummyFamilies.specs", function()
		T.it("un mannequin par couple, identifiant « palette_famille », nom « Palette Famille »", function()
			local list = generated()
			local expected = 0
			for _, pairs in DummyFamilies.PAIRS do
				expected += #pairs
			end
			T.expectEqual(#list, expected)
			for _, dummy in list do
				local family, paletteId = DummyFamilies.parse(dummy.id)
				T.expect(family ~= nil and paletteId ~= nil, dummy.id)
				local base = Collection.get(family :: string)
				T.expectEqual(dummy.name, DummyFamilies.PALETTES[paletteId :: string].name .. " " .. base.name)
			end
		end)
		T.it("au-delà de Secret : cotes dans la plage de la rareté", function()
			for _, dummy in generated() do
				local range = DummyFamilies.RANGES[dummy.rarity]
				if range then
					T.expect(dummy.n >= range[1] * 0.95 and dummy.n <= range[2] * 1.05, dummy.id .. " cote")
				end
			end
		end)
		T.it("bandIncome : du bas au haut de la plage de revenu de la rareté, géométrique, arrondi", function()
			local band = Rarity.get(5).income
			T.expectEqual(DummyFamilies.bandIncome(5, 1, 6), band[1])
			T.expectEqual(DummyFamilies.bandIncome(5, 6, 6), band[2])
			T.expectEqual(DummyFamilies.bandIncome(5, 1, 1), band[1], "seul de sa rareté")
			local middle = DummyFamilies.bandIncome(5, 3, 5)
			T.expect(math.abs(middle / math.sqrt(band[1] * band[2]) - 1) < 0.05, "milieu " .. middle)
		end)
		T.it("raretés dessinées : les générés au-dessus des dessinés, sous la rareté suivante", function()
			local topDrawn = {}
			for _, dummy in Collection.DRAWN do
				topDrawn[dummy.rarity] = math.max(topDrawn[dummy.rarity] or 0, dummy.n)
			end
			for _, dummy in generated() do
				if topDrawn[dummy.rarity] then
					T.expect(dummy.n > topDrawn[dummy.rarity], dummy.id .. " au-dessus des dessinés")
				end
			end
		end)
		T.it("arrondit à 2 chiffres significatifs (entier sous 100)", function()
			T.expectEqual(DummyFamilies.nice(4.6), 4.6)
			T.expectEqual(DummyFamilies.nice(4.6, true), 5)
			T.expectEqual(DummyFamilies.nice(6.2996), 6.3)
			T.expectEqual(DummyFamilies.nice(0.2), 1)
			T.expectEqual(DummyFamilies.nice(155), 160)
			T.expectEqual(DummyFamilies.nice(12345), 12000)
			T.expectEqual(DummyFamilies.nice(2.46e9), 2.5e9)
		end)
	end)

	T.describe("DummyFamilies.look", function()
		T.it("reprend les pièces ajoutées et masquées de la famille, teintées vers la palette", function()
			for _, dummy in generated() do
				local family, paletteId = DummyFamilies.parse(dummy.id)
				local base = DummyModels.LOOKS[family :: string]
				local palette = DummyFamilies.PALETTES[paletteId :: string]
				local look = Collection.look(dummy.id)
				T.expectEqual(look.accessories, base.accessories, dummy.id)
				T.expectEqual(look.hidden, base.hidden, dummy.id)
				T.expectEqual(look.color, palette.body, dummy.id)
				T.expectEqual(look.accessoryMaterial, palette.accessoryMaterial, dummy.id)
				for _, name in base.accessories do
					local expected = DummyModels.ADDONS[name].color:Lerp(palette.accent, palette.tint)
					T.expectEqual(look.accessoryColors[name], expected, dummy.id .. " " .. name)
				end
			end
		end)
		T.it("reprend les effets de la famille (modèle et thème) à la couleur de la palette", function()
			local look = DummyFamilies.look("lava", "frost")
			local base = DummyModels.LOOKS.lava
			local count = #(base.effects or {}) + #(DummyAura.THEMES.lava or {})
			T.expectEqual(#look.effects, count)
			local glow = DummyFamilies.PALETTES.frost.glow
			T.expectEqual(look.effects[1].color, base.effects[1].color:Lerp(glow, 0.8))
			T.expectEqual(look.effects[1].preset, base.effects[1].preset)
			T.expect(base.effects[1].color ~= look.effects[1].color, "effet d'origine intact")
		end)
		T.it(
			"la déclinaison d'une entrée générée porte les couleurs et le matériau des pièces ajoutées",
			function()
				local variant = Collection.variant({ id = "golden_void", size = 1 })
				T.expectEqual(variant.accessoryMaterial, Enum.Material.Foil)
				T.expect(variant.accessoryColors ~= nil, "couleurs des pièces ajoutées")
				T.expectEqual(variant.material, Enum.Material.Foil)
			end
		)
		T.it("un identifiant inconnu n'est pas un mannequin généré", function()
			T.expectEqual(DummyFamilies.parse("crash"), nil)
			T.expectEqual(DummyFamilies.parse("pink_nope"), nil)
			T.expectEqual(DummyFamilies.parse("nope_crash"), nil)
			T.expectEqual(DummyFamilies.parse("pink_rookie"), "rookie")
		end)
	end)
end
