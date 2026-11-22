-- Look des mannequins d'entraînement (#118) : une famille de la collection par palier, teintes et aura de plus en plus
-- fournies, trois usages (soulevé, râtelier, fenêtre).
return function(T, Loader)
	local loader = Loader.new()
	local DummyAura = loader:require("src/shared/DummyAura")
	local DummyFamilies = loader:require("src/shared/DummyFamilies")
	local DummyModels = loader:require("src/shared/DummyModels")
	local Training = loader:require("src/shared/Training")
	local TrainingLook = loader:require("src/shared/TrainingLook")
	local Enum = require("@lune/roblox").Enum

	T.describe("TrainingLook.LOOKS", function()
		T.it("a un look par équipement, chacun d'une famille différente de la collection", function()
			T.expectEqual(#TrainingLook.LOOKS, #Training.GEARS)
			local seen = {}
			for tier, look in TrainingLook.LOOKS do
				local base = DummyModels.LOOKS[look.family]
				T.expect(base ~= nil, "famille inconnue au palier " .. tier)
				T.expect(not seen[look.family], "famille déjà prise au palier " .. tier)
				seen[look.family] = true
				for _, name in look.keep or {} do
					T.expect(
						table.find(base.accessories, name) ~= nil,
						name .. " n'est pas de la famille " .. look.family
					)
				end
				for name in look.colors or {} do
					T.expect(DummyModels.ADDONS[name] ~= nil, "couleur pour une pièce inconnue : " .. name)
				end
			end
		end)
		T.it("n'imite aucun mannequin généré de la collection (même famille, même couleur de corps)", function()
			for _, rarity in DummyFamilies.PAIRS do
				for _, pair in rarity do
					local palette = DummyFamilies.PALETTES[pair[2]]
					for tier, look in TrainingLook.LOOKS do
						local same = look.family == pair[1] and Training.GEARS[tier].color == palette.body
						T.expect(not same, "palier " .. tier .. " identique à " .. pair[2] .. "_" .. pair[1])
					end
				end
			end
		end)
		T.it("donne une aura de plus en plus fournie, présente dès l'or", function()
			for tier = 2, #TrainingLook.LOOKS do
				T.expect(
					TrainingLook.LOOKS[tier].aura >= TrainingLook.LOOKS[tier - 1].aura,
					"aura en baisse au palier " .. tier
				)
			end
			T.expect(TrainingLook.LOOKS[4].aura >= 3, "aura en or")
			T.expect(
				TrainingLook.LOOKS[#TrainingLook.LOOKS].aura > TrainingLook.LOOKS[4].aura,
				"aura plus riche au bout"
			)
		end)
	end)

	T.describe("TrainingLook.variant", function()
		T.it("habille chaque palier de sa couleur, de pièces ajoutées et de son matériau", function()
			for tier, gear in Training.GEARS do
				local variant = TrainingLook.variant(tier, "lifted")
				T.expectEqual(variant.color, gear.color)
				T.expect(#variant.accessories >= 3, "moins de 3 pièces ajoutées au palier " .. tier)
				for _, name in variant.accessories do
					T.expect(variant.accessoryColors[name] ~= nil, "pièce sans couleur : " .. name)
				end
			end
		end)
		T.it("n'a ni verre ni champ de force invisibles au râtelier pour Cosmic et au-delà (#118)", function()
			for tier = 7, #Training.GEARS do
				local material = Training.GEARS[tier].material
				T.expect(material ~= Enum.Material.ForceField, "champ de force au palier " .. tier)
				T.expect(material ~= Enum.Material.Glass, "verre au palier " .. tier)
			end
		end)
		T.it("soulevé : effets thème et aura, rien au sol ; sans particules en mouvement réduit", function()
			local last = #Training.GEARS
			local lifted = TrainingLook.variant(last, "lifted")
			T.expect(lifted.effects ~= nil and #lifted.effects >= 3, "aura du dernier palier")
			local particles = 0
			for _, effect in lifted.effects do
				T.expect(not DummyAura.isGrounded(effect), "effet posé au sol sur un mannequin soulevé")
				particles += if effect.kind == "particles" then 1 else 0
			end
			T.expect(particles >= 2, "particules au dernier palier")
			for _, effect in TrainingLook.variant(last, "lifted", true).effects or {} do
				T.expectEqual(effect.kind, "light", "seulement des lumières en mouvement réduit")
			end
			for tier, look in TrainingLook.LOOKS do
				local has = TrainingLook.variant(tier, "lifted").effects ~= nil
				T.expectEqual(has, look.aura >= TrainingLook.FX_AURA, "effets du palier " .. tier)
			end
		end)
		T.it("râtelier : lumières seulement, pas de pièce plus large que l'écart des crochets", function()
			for tier in Training.GEARS do
				local variant = TrainingLook.variant(tier, "rack")
				for _, effect in variant.effects or {} do
					T.expectEqual(effect.kind, "light", "palier " .. tier)
				end
				for _, name in variant.accessories do
					T.expect(DummyModels.ADDONS[name].size.X <= TrainingLook.RACK_WIDTH, name .. " trop large")
				end
				T.expect(#variant.accessories >= 2, "râtelier sans pièces au palier " .. tier)
			end
		end)
		T.it("fenêtre : sans effets (particules et lumières ne s'y rendent pas)", function()
			for tier in Training.GEARS do
				T.expect(TrainingLook.variant(tier, "viewport").effects == nil, "palier " .. tier)
			end
		end)
		T.it("borne le palier demandé", function()
			T.expectEqual(TrainingLook.variant(0, "rack").color, Training.GEARS[1].color)
			T.expectEqual(TrainingLook.variant(99, "rack").color, Training.GEARS[#Training.GEARS].color)
		end)
	end)
end
