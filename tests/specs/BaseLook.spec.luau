-- Progression visible depuis le hub : paliers visuels de la base (présentoirs achetés), habillage de l'appareil
-- d'entraînement (Training Gear), texte flottant au-dessus de la base.
return function(T, Loader)
	local loader = Loader.new()
	local BaseLook = loader:require("src/shared/BaseLook")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Training = loader:require("src/shared/Training")

	local start = GameConfig.DISPLAY_START
	local max = start + #GameConfig.DISPLAY_PRICES

	T.describe("BaseLook.baseTier (un palier par présentoir acheté)", function()
		T.it("a un palier par nombre de présentoirs, du départ au maximum", function()
			T.expectEqual(#BaseLook.BASE_TIERS, max - start + 1)
			for displays = start, max do
				T.expectEqual(BaseLook.baseTier(displays), displays - start + 1, displays .. " présentoirs")
			end
		end)
		T.it("borne les valeurs hors plage et sans données", function()
			T.expectEqual(BaseLook.baseTier(nil), 1)
			T.expectEqual(BaseLook.baseTier(0), 1)
			T.expectEqual(BaseLook.baseTier(max + 5), #BaseLook.BASE_TIERS)
		end)
	end)

	T.describe("BaseLook.base (chaque palier se voit)", function()
		-- Cette méthode permet de résumer ce qui se voit d'un palier (clôture, sol, décor) lorsqu'un test compare deux
		-- paliers voisins.
		local function signature(tier)
			local look, fence = BaseLook.base(tier)
			return table.concat({
				look.fence,
				tostring(look.plot),
				tostring(look.lanterns),
				tostring(look.flowers),
				tostring(look.flags),
				tostring(look.arch),
				tostring(fence.shine),
				tostring(fence.post),
				tostring(fence.rail),
				tostring(fence.cap),
				tostring(fence.height),
			}, "|")
		end

		T.it("change d'aspect à chaque palier", function()
			for tier = 2, #BaseLook.BASE_TIERS do
				T.expect(signature(tier) ~= signature(tier - 1), "palier " .. tier .. " identique au précédent")
			end
		end)
		T.it("ne retire jamais de décor en montant", function()
			for tier = 2, #BaseLook.BASE_TIERS do
				local now, before = BaseLook.base(tier), BaseLook.base(tier - 1)
				T.expect(now.lanterns >= before.lanterns, "lanternes au palier " .. tier)
				for _, key in { "flowers", "flags", "arch" } do
					T.expect(now[key] or not before[key], key .. " retiré au palier " .. tier)
				end
			end
		end)
		T.it("passe la clôture du bois à la pierre puis au métal doré", function()
			T.expectEqual(BaseLook.base(1).fence, "wood")
			T.expectEqual(BaseLook.base(3).fence, "stone")
			T.expectEqual(BaseLook.base(#BaseLook.BASE_TIERS).fence, "gold")
			for tier = 1, #BaseLook.BASE_TIERS do
				local _, fence = BaseLook.base(tier)
				T.expect(fence ~= nil, "clôture connue au palier " .. tier)
				T.expectEqual(BaseLook.postTop(fence), fence.height + (if fence.cap then BaseLook.CAP_HEIGHT else 0))
			end
		end)
		T.it(
			"garde lisses et chapeaux décalés des poteaux (pas de faces coplanaires, écart de 0,05 stud au moins)",
			function()
				for name, fence in BaseLook.FENCES do
					local railGap = fence.width * (1 - BaseLook.RAIL_RATIO) / 2
					T.expect(railGap >= 0.05, "lisses en retrait des poteaux : " .. name)
					T.expect(BaseLook.CAP_OVERHANG >= 0.05, "chapeaux débordants : " .. name)
				end
			end
		)
		T.it("borne le palier demandé", function()
			T.expectEqual(BaseLook.base(0).name, BaseLook.BASE_TIERS[1].name)
			T.expectEqual(BaseLook.base(99).name, BaseLook.BASE_TIERS[#BaseLook.BASE_TIERS].name)
		end)
	end)

	T.describe("BaseLook.station (habillage au Training Gear)", function()
		T.it("prend la couleur du mannequin acheté, un habillage différent par palier", function()
			local seen = {}
			for tier, gear in Training.GEARS do
				local look = BaseLook.station(tier)
				T.expectEqual(look.gear, gear.name)
				local tones = BaseLook.STATION_TONES[tier]
				T.expectEqual(look.plank, tones.plank or gear.color)
				local key = tostring(look.plank) .. tostring(look.plankAlt)
				T.expect(not seen[key], "habillage du palier " .. tier .. " déjà vu")
				seen[key] = true
			end
		end)
		T.it("a un ton et une pièce de palier par équipement après le bois", function()
			T.expectEqual(#BaseLook.STATION_TONES, #Training.GEARS)
			T.expectEqual(#BaseLook.STATION_PIECES, #Training.GEARS - 1)
		end)
		T.it("ajoute à chaque palier au moins une pièce à celles du précédent (#118)", function()
			-- Cette méthode permet de compter les pièces de palier d'un habillage lorsque l'on compare deux paliers.
			local function count(look)
				local n = 0
				for _, on in look.pieces do
					n += if on then 1 else 0
				end
				return n
			end
			T.expectEqual(count(BaseLook.station(1)), 0, "le bois n'a pas de pièce ajoutée")
			for tier = 2, #Training.GEARS do
				local before, after = BaseLook.station(tier - 1), BaseLook.station(tier)
				for name, on in before.pieces do
					T.expect(not on or after.pieces[name], name .. " perdue au palier " .. tier)
				end
				T.expect(count(after) > count(before), "rien d'ajouté au palier " .. tier)
			end
			local last = BaseLook.station(#Training.GEARS)
			for _, name in BaseLook.STATION_PIECES do
				T.expect(last.pieces[name], name .. " absente du dernier palier")
			end
		end)
		-- Cette méthode permet de donner la teinte (0 à 360°) d'une couleur lorsque l'on compare deux paliers.
		local function hue(color: Color3): number
			local h = color:ToHSV()
			return h * 360
		end
		-- Cette méthode permet de donner l'écart de teinte entre deux couleurs (0 à 180°) lorsque l'on compare deux paliers.
		local function hueGap(a: Color3, b: Color3): number
			local d = math.abs(hue(a) - hue(b)) % 360
			return math.min(d, 360 - d)
		end
		T.it("distingue Neon et Plasma au premier coup d'œil (#118)", function()
			local neon, plasma = BaseLook.station(6), BaseLook.station(10)
			T.expect(hueGap(neon.plank, plasma.plank) >= 60, "planches de teintes trop proches")
			T.expect(hueGap(neon.accent, plasma.accent) >= 60, "néons de teintes trop proches")
			T.expect(hueGap(Training.GEARS[6].color, Training.GEARS[10].color) >= 60, "mannequins trop proches")
		end)
		T.it("distingue Diamond et Infinite de la pierre : planches saturées, socle coloré (#118)", function()
			local stone = BaseLook.station(2)
			for _, tier in { 5, #Training.GEARS } do
				local look = BaseLook.station(tier)
				T.expect(look.base ~= nil, "socle coloré au palier " .. tier)
				local _, saturation = look.plankAlt:ToHSV()
				T.expect(saturation >= 0.35, "planches trop pâles au palier " .. tier)
				T.expect(look.plankAlt ~= stone.plankAlt, "mêmes planches que la pierre au palier " .. tier)
			end
		end)
		T.it("ajoute étincelles (Diamond) puis liseré néon (Neon) aux derniers paliers", function()
			T.expect(not BaseLook.station(4).sparkle, "pas d'étincelles en or")
			T.expect(BaseLook.station(5).sparkle, "étincelles en diamant")
			T.expect(BaseLook.station(5).glow == nil, "pas de néon en diamant")
			T.expect(BaseLook.station(6).glow ~= nil, "néon au palier Neon")
			T.expect(BaseLook.station(#Training.GEARS).glow ~= nil, "néon au dernier palier")
		end)
		T.it("borne le palier demandé", function()
			T.expectEqual(BaseLook.station(0).gear, Training.GEARS[1].name)
			T.expectEqual(BaseLook.station(99).gear, Training.GEARS[#Training.GEARS].name)
		end)
	end)

	T.describe("BaseLook.rackTiers (mannequins du râtelier)", function()
		T.it("montre les trois premiers au départ, puis les trois derniers possédés", function()
			T.expectEqual(table.concat(BaseLook.rackTiers(1), ","), "1,2,3")
			T.expectEqual(table.concat(BaseLook.rackTiers(3), ","), "1,2,3")
			T.expectEqual(table.concat(BaseLook.rackTiers(5), ","), "3,4,5")
			local last = #Training.GEARS
			T.expectEqual(
				table.concat(BaseLook.rackTiers(last + 3), ","),
				(last - 2) .. "," .. (last - 1) .. "," .. last
			)
		end)
	end)

	T.describe("BaseLook.label (texte flottant de la base)", function()
		T.it("donne nom, revenu et Throw Power abrégés", function()
			local label = BaseLook.label("Manyonne", 223, 1234)
			T.expectEqual(label.title, "MANYONNE'S BASE")
			T.expectEqual(label.income, "$223/s")
			T.expectEqual(label.power, "💪 1.23K")
		end)
		T.it("affiche une base vide sans propriétaire", function()
			local label = BaseLook.label(nil, 500, 10)
			T.expectEqual(label.title, "EMPTY BASE")
			T.expectEqual(label.income, "$0/s")
			T.expectEqual(label.power, "")
		end)
		T.it("laisse la puissance vide avant le chargement et borne les valeurs négatives", function()
			local label = BaseLook.label("Bob", nil, nil)
			T.expectEqual(label.income, "$0/s")
			T.expectEqual(label.power, "")
			T.expectEqual(BaseLook.label("Bob", -5, -1).income, "$0/s")
			T.expectEqual(BaseLook.label("Bob", 3.6e6, 2e9).income, "$3.6M/s")
			T.expectEqual(BaseLook.label("Bob", 0, 2e9).power, "💪 2B")
		end)
		T.it(
			"ajoute le compteur de renaissances violet à côté de la Throw Power, seulement à partir d'une",
			function()
				T.expectEqual(BaseLook.label("Bob", 0, 1234, 0).power, "💪 1.23K")
				T.expectEqual(
					BaseLook.label("Bob", 0, 1234, 3).power,
					'💪 1.23K  <font color="#' .. loader:require("src/shared/Rebirth").COLOR_HEX .. '">🌟 3</font>'
				)
				T.expectEqual(BaseLook.label("Bob", 0, nil, 3).power, "", "rien avant le chargement")
				T.expectEqual(BaseLook.label(nil, 0, 10, 3).power, "", "base vide")
			end
		)
		T.it("affiche le record du propriétaire (#44), rien sans record ni propriétaire", function()
			T.expectEqual(BaseLook.label("Bob", 0, 10, 0, 3650).best, "🏆 BEST 3.6 km")
			T.expectEqual(BaseLook.label("Bob", 0, 10, 0, 145.7).best, "🏆 BEST 145 m")
			T.expectEqual(BaseLook.label("Bob", 0, 10, 0, 0).best, "")
			T.expectEqual(BaseLook.label("Bob", 0, 10).best, "", "données pas chargées")
			T.expectEqual(BaseLook.label(nil, 0, 10, 0, 3650).best, "", "base vide")
		end)
	end)
end
