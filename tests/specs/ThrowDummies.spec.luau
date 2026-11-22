-- Boutique de mannequins à lancer (#14) : catalogue, achat séquentiel, équipement, popup « NEW DUMMY! », multiplicateur
-- de chance, comportements en vol (os fragiles, portance, poussée), lecture des sauvegardes.
return function(T, Loader)
	local loader = Loader.new()
	local ThrowDummies = loader:require("src/shared/ThrowDummies")
	local Economy = loader:require("src/shared/Economy")
	local Format = loader:require("src/shared/Format")
	local fs = require("@lune/fs")

	local LIST = ThrowDummies.LIST

	T.describe("ThrowDummies.LIST (catalogue)", function()
		T.it("le premier offert, prix et chance strictement croissants, jusqu'à 100-150x (#94)", function()
			T.expectEqual(ThrowDummies.SHOWCASE, 6)
			T.expect(#LIST >= 15, "taille " .. #LIST)
			T.expectEqual(LIST[1].cost, 0)
			T.expectEqual(LIST[1].luck, 1)
			for i = 2, #LIST do
				T.expect(LIST[i].cost > LIST[i - 1].cost, "prix " .. i)
				T.expect(LIST[i].luck > LIST[i - 1].luck, "chance " .. i)
			end
			T.expect(LIST[#LIST].luck >= 100 and LIST[#LIST].luck <= 150, "dernier : " .. LIST[#LIST].luck)
		end)
		T.it("deuxième mannequin comme la graine 1.25x de 09 ($1.2K) : entre $1K et $2K", function()
			T.expectEqual(LIST[2].luck, 1.25)
			T.expect(LIST[2].cost >= 1000 and LIST[2].cost <= 2000, "prix " .. LIST[2].cost)
		end)
		T.it("suite générée : le prix de sa ligne de EXTENDED, nombre rond (2 chiffres significatifs)", function()
			for index, spec in ThrowDummies.EXTENDED do
				local dummy = LIST[ThrowDummies.SHOWCASE + index]
				T.expectEqual(dummy.cost, spec.cost, dummy.id)
				T.expectEqual(dummy.luck, spec.luck, dummy.id)
				local magnitude = 10 ^ (math.floor(math.log10(spec.cost)) - 1)
				T.expect(spec.cost % magnitude == 0, dummy.id .. " rond : " .. spec.cost)
			end
		end)
		T.it("mannequins dessinés : chacun a un comportement en vol distinct (un seul réglage propre)", function()
			local seen = {}
			for i = 1, ThrowDummies.SHOWCASE do
				local dummy = LIST[i]
				T.expect(not seen[dummy.behavior], "comportement en double : " .. dummy.behavior)
				seen[dummy.behavior] = true
				local physics = dummy.physics
				local standard = LIST[1].physics
				local own = 0
				if physics.density ~= standard.density or physics.elasticity ~= standard.elasticity then
					own += 1
				end
				if dummy.boneFactor > 1 then
					own += 1
				end
				if dummy.lift > 0 then
					own += 1
				end
				if dummy.thrust > 0 then
					own += 1
				end
				if (dummy.bounce or 0) > 0 then
					own += 1
				end
				if i == 2 then
					own -= 1 -- le caoutchouc : physique et rebond forment un seul comportement
				end
				T.expectEqual(own, if i == 1 then 0 else 1, dummy.id)
			end
		end)
		T.it("suite générée : comportement et physique d'un mannequin dessiné, sans les cumuler", function()
			local byBehavior = {}
			for i = 2, ThrowDummies.SHOWCASE do
				byBehavior[LIST[i].behavior] = LIST[i]
			end
			for i = ThrowDummies.SHOWCASE + 1, #LIST do
				local dummy = LIST[i]
				local base = byBehavior[dummy.behavior]
				T.expect(base ~= nil, dummy.id .. " : comportement " .. dummy.behavior)
				T.expectEqual(dummy.physics, base.physics, dummy.id .. " physique")
				T.expectEqual(dummy.boneFactor, base.boneFactor, dummy.id .. " os")
				T.expectEqual(dummy.lift, base.lift, dummy.id .. " portance")
				T.expectEqual(dummy.thrust, base.thrust, dummy.id .. " poussée")
				T.expectEqual(dummy.bounce, base.bounce, dummy.id .. " rebond")
				T.expectEqual(#(dummy.blocks or {}), #(base.blocks or {}), dummy.id .. " blocs")
				T.expect(string.find(dummy.name, base.name, 1, true) ~= nil, dummy.name)
			end
		end)
		T.it("identifiants et noms uniques, couleur de carte pour chacun", function()
			local ids, names = {}, {}
			for _, dummy in LIST do
				T.expect(not ids[dummy.id] and not names[dummy.name], dummy.id)
				ids[dummy.id], names[dummy.name] = true, true
				T.expect(typeof(dummy.card) == "Color3", dummy.id)
			end
		end)
	end)

	T.describe("Signes de rang (#127)", function()
		T.it("rang croissant avec la chance : rien avant 13x, 3 pour les trois derniers", function()
			local previous = 0
			for _, dummy in LIST do
				local rank = ThrowDummies.rank(dummy.luck)
				T.expect(rank >= previous, dummy.id)
				previous = rank
				T.expectEqual(dummy.ornaments ~= nil, rank > 0, dummy.id .. " signes")
			end
			T.expectEqual(ThrowDummies.rank(LIST[#LIST].luck), 3)
			T.expectEqual(ThrowDummies.rank(LIST[#LIST - 2].luck), 3)
			T.expectEqual(ThrowDummies.rank(LIST[ThrowDummies.SHOWCASE + 1].luck), 0)
		end)
		T.it("plus de signes et d'effets à chaque rang, transmis par la déclinaison", function()
			local count = { [0] = 0 }
			for index, dummy in LIST do
				local rank = ThrowDummies.rank(dummy.luck)
				local n = #(dummy.ornaments or {}) + #(dummy.effects or {})
				count[rank] = n
				local variant = ThrowDummies.variant(index)
				T.expectEqual(#(variant.blocks or {}), #(dummy.blocks or {}) + #(dummy.ornaments or {}), dummy.id)
				T.expectEqual(variant.effects, dummy.effects, dummy.id)
			end
			T.expect(
				count[1] > count[0] and count[2] > count[1] and count[3] > count[2],
				"rangs de plus en plus riches"
			)
		end)
	end)

	T.describe("ThrowDummies.act (achat séquentiel, équipement)", function()
		T.it("achète seulement le suivant, avec l'argent, et l'équipe", function()
			local result = ThrowDummies.act(1, 1, LIST[2].cost, "Buy", 2)
			T.expect(result ~= nil, "achat du suivant")
			T.expectEqual(result.owned, 2)
			T.expectEqual(result.equipped, 2)
			T.expectEqual(result.cost, LIST[2].cost)
		end)
		T.it("refuse un achat hors ordre, déjà possédé ou sans l'argent", function()
			T.expectEqual(ThrowDummies.act(1, 1, 1e12, "Buy", 3), nil, "saute un niveau")
			T.expectEqual(ThrowDummies.act(3, 1, 1e12, "Buy", 2), nil, "déjà possédé")
			T.expectEqual(ThrowDummies.act(1, 1, LIST[2].cost - 1, "Buy", 2), nil, "argent insuffisant")
			T.expectEqual(ThrowDummies.act(#LIST, 1, 1e12, "Buy", #LIST + 1), nil, "au-delà du catalogue")
		end)
		T.it("équipe un mannequin possédé, autre que l'équipé, sans rien payer", function()
			local result = ThrowDummies.act(3, 3, 0, "Equip", 1)
			T.expect(result ~= nil, "équiper un possédé")
			T.expectEqual(result.owned, 3)
			T.expectEqual(result.equipped, 1)
			T.expectEqual(result.cost, 0)
			T.expectEqual(ThrowDummies.act(3, 3, 1e12, "Equip", 4), nil, "pas possédé")
			T.expectEqual(ThrowDummies.act(3, 2, 1e12, "Equip", 2), nil, "déjà équipé")
		end)
		T.it("ignore les demandes mal formées du client", function()
			for _, bad in { 0, -1, 2.5, 0 / 0, math.huge, "2", true, nil } do
				T.expectEqual(ThrowDummies.act(6, 1, 1e12, "Equip", bad), nil, tostring(bad))
				T.expectEqual(ThrowDummies.act(1, 1, 1e12, "Buy", bad), nil, tostring(bad))
			end
			T.expectEqual(ThrowDummies.act(1, 1, 1e12, "Sell", 2), nil, "action inconnue")
			T.expectEqual(ThrowDummies.act(1, 1, 1e12, nil, 2), nil, "action absente")
		end)
		T.it("le serveur passe par ThrowDummies.act (aucune confiance dans le client)", function()
			local source = fs.readFile("src/server/PlayerData.luau")
			T.expect(string.find(source, "ThrowDummies.act(", 1, true) ~= nil, "PlayerData.throwDummy valide par act")
		end)
	end)

	T.describe("ThrowDummies.cardState et offer (boutique, popup « NEW DUMMY! »)", function()
		T.it("équipé, possédé, suivant à acheter, verrouillé après", function()
			T.expectEqual(ThrowDummies.cardState(3, 2, 2), "Equipped")
			T.expectEqual(ThrowDummies.cardState(3, 2, 1), "Owned")
			T.expectEqual(ThrowDummies.cardState(3, 2, 3), "Owned")
			T.expectEqual(ThrowDummies.cardState(3, 2, 4), "Buy")
			T.expectEqual(ThrowDummies.cardState(3, 2, 5), "Locked")
		end)
		T.it("propose le suivant dès qu'il est abordable, sauf si le joueur a fermé son popup", function()
			T.expectEqual(ThrowDummies.offer(1, LIST[2].cost - 1, {}), nil)
			T.expectEqual(ThrowDummies.offer(1, LIST[2].cost, {}), 2)
			T.expectEqual(ThrowDummies.offer(1, LIST[2].cost, { [2] = true }), nil)
			T.expectEqual(ThrowDummies.offer(2, 1e12, { [2] = true }), 3, "le suivant revient")
			T.expectEqual(ThrowDummies.offer(#LIST, 1e12, {}), nil, "tout acheté")
		end)
	end)

	T.describe("ThrowDummies.sanitize (sauvegardes)", function()
		T.it("borne possédés et équipé au catalogue, l'équipé aux possédés", function()
			local owned, equipped = ThrowDummies.sanitize(nil, nil)
			T.expectEqual(owned, 1)
			T.expectEqual(equipped, 1)
			owned, equipped = ThrowDummies.sanitize(99, 50)
			T.expectEqual(owned, #LIST)
			T.expectEqual(equipped, #LIST)
			owned, equipped = ThrowDummies.sanitize(2, 4)
			T.expectEqual(owned, 2)
			T.expectEqual(equipped, 2)
			owned, equipped = ThrowDummies.sanitize(0 / 0, "x")
			T.expectEqual(owned, 1)
			T.expectEqual(equipped, 1)
		end)
	end)

	T.describe("Chance et comportements en vol", function()
		T.it("le multiplicateur du mannequin multiplie la CHANCE du vol", function()
			local base = Economy.chance({ distance = 300, bones = 4, smashed = 6 })
			for _, dummy in LIST do
				local c = Economy.chance({ distance = 300, bones = 4, smashed = 6, luck = dummy.luck })
				T.expectNear(c.total, base.total * dummy.luck, 0.006 * dummy.luck + 0.006, dummy.id)
				T.expectEqual(c.luck, dummy.luck)
			end
		end)
		T.it("un mannequin fragile casse ses os sur des chocs plus faibles", function()
			local glass = LIST[3]
			T.expect(glass.boneFactor > 1, "verre fragile")
			T.expectEqual(ThrowDummies.boneImpact(glass, 40), 40 * glass.boneFactor)
			T.expectEqual(ThrowDummies.boneImpact(LIST[1], 40), 40)
		end)
		T.it("le planeur porte seulement quand il redescend", function()
			local glider
			for _, dummy in LIST do
				if dummy.lift > 0 then
					glider = dummy
				end
			end
			T.expect(glider ~= nil, "un planeur")
			local up = ThrowDummies.flightAccel(glider, Vector3.new(0, 30, 80), Vector3.zAxis, 2, 120)
			local down = ThrowDummies.flightAccel(glider, Vector3.new(0, -30, 80), Vector3.zAxis, 2, 120)
			local ground = ThrowDummies.flightAccel(glider, Vector3.new(0, -1, 20), Vector3.zAxis, 5, 120)
			T.expectEqual(up, Vector3.zero)
			T.expectNear(down.Y, 120 * glider.lift)
			T.expectEqual(ground, Vector3.zero, "pas au sol")
		end)
		T.it("le réacteur pousse vers l'avant à plat, seulement au départ", function()
			local rocket
			for _, dummy in LIST do
				if dummy.thrust > 0 then
					rocket = dummy
				end
			end
			T.expect(rocket ~= nil, "un réacteur")
			local pitched = Vector3.new(0, math.sin(math.rad(32)), math.cos(math.rad(32)))
			local early = ThrowDummies.flightAccel(rocket, Vector3.new(0, 20, 90), pitched, 0.2, 120)
			T.expectNear(early.Y, 0, 1e-3)
			T.expectNear(early.Z, rocket.thrust, 1e-3)
			local late = ThrowDummies.flightAccel(rocket, Vector3.new(0, 20, 90), pitched, rocket.thrustTime + 0.1, 120)
			T.expectEqual(late, Vector3.zero)
		end)
		T.it("le caoutchouc rebondit vers le haut en gardant son élan vers l'avant, seulement au sol", function()
			local rubber = LIST[2]
			T.expect((rubber.bounce or 0) > 0, "rebondissant")
			local before = Vector3.new(0, -60, 80)
			local stopped = Vector3.new(3, 0, 20)
			local out = ThrowDummies.bounce(rubber, before, stopped, Vector3.zAxis) :: any
			T.expect(out ~= nil, "rebond au sol")
			T.expectNear(out.Y, 60 * rubber.bounce, 1e-3)
			T.expectNear(out.Z, 80 * rubber.bounce, 1e-3)
			T.expectNear(out.X, 3, 1e-3)
			T.expectEqual(
				ThrowDummies.bounce(rubber, Vector3.new(0, -10, 80), stopped, Vector3.zAxis),
				nil,
				"chute faible"
			)
			T.expectEqual(ThrowDummies.bounce(rubber, before, Vector3.new(0, -50, 80), Vector3.zAxis), nil, "en l'air")
			T.expectEqual(ThrowDummies.bounce(LIST[1], before, stopped, Vector3.zAxis), nil, "pas rebondissant")
		end)
		T.it("le Crash Dummy n'a aucun comportement propre", function()
			T.expectEqual(
				ThrowDummies.flightAccel(LIST[1], Vector3.new(0, -50, 90), Vector3.zAxis, 0.1, 120),
				Vector3.zero
			)
		end)
	end)

	T.describe("Affichage", function()
		T.it("multiplicateur écrit comme les graines de 09 (1.0x, 1.25x, 2.0x)", function()
			T.expectEqual(Format.luck(1), "1.0x")
			T.expectEqual(Format.luck(1.25), "1.25x")
			T.expectEqual(Format.luck(1.5), "1.5x")
			T.expectEqual(Format.luck(2), "2.0x")
		end)
		T.it("déclinaison : verre remplacé par du néon dans les fenêtres, blocs transmis", function()
			local Enum = require("@lune/roblox").Enum
			local glassIndex
			for i, dummy in LIST do
				if dummy.material == Enum.Material.Glass then
					glassIndex = i
				end
			end
			T.expect(glassIndex ~= nil, "un mannequin de verre")
			T.expectEqual(ThrowDummies.variant(glassIndex).material, Enum.Material.Glass)
			T.expectEqual(ThrowDummies.variant(glassIndex, true).material, Enum.Material.Neon)
			T.expectEqual(ThrowDummies.variant(2).blocks, LIST[2].blocks)
		end)
	end)
end
