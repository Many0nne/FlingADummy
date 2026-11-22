-- Animation de construction d'une base qui monte de palier (#122) : ordre et instants d'arrivée des pièces, durée
-- totale bornée, courbes de chute et d'enfoncement, fraîcheur du changement.
return function(T, Loader)
	local loader = Loader.new()
	local BaseUpgrade = loader:require("src/shared/BaseUpgrade")

	local gate = Vector3.new(0, 0, 17)

	-- Cette méthode permet de fabriquer `count` pièces au sol alignées depuis l'entrée lorsqu'un test a besoin d'un
	-- habillage de taille donnée.
	local function row(count: number, stage: number?)
		local pieces = {}
		for i = 1, count do
			table.insert(pieces, { position = Vector3.new(0, 2, 17 - i), stage = stage or 0 })
		end
		return pieces
	end

	T.describe("BaseUpgrade.plan (durée)", function()
		T.it("tient la durée totale entre 1,5 et 2,5 s quel que soit le nombre de pièces", function()
			for _, count in { 0, 1, 2, 5, 20, 60, 200 } do
				local plan = BaseUpgrade.plan(row(count), gate, false)
				T.expect(plan.finish >= 1.5 and plan.finish <= 2.5, count .. " pièces : " .. plan.finish .. " s")
				for index, start in plan.starts do
					T.expect(start >= plan.out - 1e-9, count .. " pièces : départ avant la sortie des anciennes")
					T.expect(
						start + plan.fall <= plan.finish + 1e-9,
						count .. " pièces : pièce " .. index .. " après la fin"
					)
				end
			end
		end)
		T.it("fait le fondu du sol pendant les chutes, avant la fin", function()
			local plan = BaseUpgrade.plan(row(40), gate, false)
			T.expect(plan.floorStart > plan.out, "sol après la sortie des anciennes pièces")
			T.expect(plan.floorEnd <= plan.finish, "sol fini avant les confettis")
			T.expect(plan.floorEnd > plan.floorStart, "fondu non nul")
		end)
		T.it("borne la durée pour un habillage complet (Golden : ~80 pièces)", function()
			local plan = BaseUpgrade.plan(row(80), gate, false)
			T.expectNear(plan.finish, BaseUpgrade.MAX_TOTAL, 1e-9)
		end)
	end)

	T.describe("BaseUpgrade.plan (ordre)", function()
		T.it("pose les pièces une à une depuis l'entrée", function()
			local pieces = {
				{ position = Vector3.new(0, 0, -15), stage = 0 }, -- fond
				{ position = Vector3.new(5, 0, 16), stage = 0 }, -- près de l'entrée
				{ position = Vector3.new(18, 0, 0), stage = 0 }, -- côté
			}
			local plan = BaseUpgrade.plan(pieces, gate, false)
			T.expect(plan.starts[2] < plan.starts[3], "entrée avant le côté")
			T.expect(plan.starts[3] < plan.starts[1], "côté avant le fond")
		end)
		T.it("pose le sol (poteaux) avant ce qui est dessus (lisses), puis le haut (lanternes)", function()
			local pieces = {
				{ position = Vector3.new(0, 6, 16), stage = 2 },
				{ position = Vector3.new(0, 2, 16), stage = 1 },
				{ position = Vector3.new(0, 2, -16), stage = 0 },
			}
			local plan = BaseUpgrade.plan(pieces, gate, false)
			T.expect(plan.starts[3] < plan.starts[2], "étage 0 avant étage 1, même loin de l'entrée")
			T.expect(plan.starts[2] < plan.starts[1], "étage 1 avant étage 2")
		end)
		T.it("décale chaque départ (pas deux pièces à la fois)", function()
			local plan = BaseUpgrade.plan(row(30), gate, false)
			local seen = {}
			for _, start in plan.starts do
				T.expect(not seen[start], "deux départs au même instant")
				seen[start] = true
			end
		end)
	end)

	T.describe("BaseUpgrade.plan (mouvement réduit)", function()
		T.it("fond tout en même temps, en un fondu court", function()
			local plan = BaseUpgrade.plan(row(40), gate, true)
			T.expect(plan.reduced)
			T.expectNear(plan.finish, BaseUpgrade.FADE_TIME, 1e-9)
			for _, start in plan.starts do
				T.expectEqual(start, 0)
			end
			T.expectEqual(#plan.starts, 40)
		end)
	end)

	T.describe("BaseUpgrade.dropOffset / landed / sink", function()
		T.it("part de haut, touche le sol, rebondit un peu puis se pose", function()
			T.expectNear(BaseUpgrade.dropOffset(0), BaseUpgrade.DROP_HEIGHT)
			local touch = 1 - BaseUpgrade.BOUNCE_SHARE
			T.expectNear(BaseUpgrade.dropOffset(touch), 0, 1e-6)
			T.expectNear(BaseUpgrade.dropOffset(1), 0, 1e-6)
			local peak = BaseUpgrade.dropOffset(touch + BaseUpgrade.BOUNCE_SHARE / 2)
			T.expectNear(peak, BaseUpgrade.BOUNCE_HEIGHT, 1e-6)
			-- Chute monotone jusqu'au sol
			local last = math.huge
			for i = 0, 20 do
				local value = BaseUpgrade.dropOffset(touch * i / 20)
				T.expect(value <= last + 1e-9, "chute monotone")
				last = value
			end
			T.expectEqual(BaseUpgrade.dropOffset(-1), BaseUpgrade.DROP_HEIGHT)
			T.expectNear(BaseUpgrade.dropOffset(2), 0, 1e-6)
		end)
		T.it("signale l'impact une seule fois", function()
			local hits = 0
			local before = -1
			for i = 0, 30 do
				local alpha = i / 30
				if BaseUpgrade.landed(before, alpha) then
					hits += 1
				end
				before = alpha
			end
			T.expectEqual(hits, 1)
		end)
		T.it("enfonce et efface les anciennes pièces", function()
			local depth, fade = BaseUpgrade.sink(0)
			T.expectNear(depth, 0)
			T.expectNear(fade, 0)
			depth, fade = BaseUpgrade.sink(1)
			T.expectNear(depth, -BaseUpgrade.SINK_DEPTH)
			T.expectNear(fade, 1)
		end)
	end)

	T.describe("BaseUpgrade.isFresh (joueur arrivé après : état final)", function()
		T.it("anime un changement récent, pas un ancien ni une valeur absente", function()
			T.expect(BaseUpgrade.isFresh(100, 100.2))
			T.expect(not BaseUpgrade.isFresh(100, 100 + BaseUpgrade.MAX_AGE + 0.1))
			T.expect(not BaseUpgrade.isFresh(nil, 100))
			T.expect(not BaseUpgrade.isFresh("100", 100))
		end)
	end)
end
