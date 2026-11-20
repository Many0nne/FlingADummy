-- Coulées d'herbe des parois : blocs sur la grille du damier de la paroi (demi-carreaux), dans la longueur du bord, marches
-- plus étroites sous leur bloc, descente bornée sous la marche suivante.
return function(T, Loader)
	local loader = Loader.new()
	local Drips = loader:require("src/shared/Drips")
	local CourseLayout = loader:require("src/shared/CourseLayout")

	-- Cette méthode permet de créer un tirage pseudo-aléatoire reproductible (congruence linéaire) lorsque l'on fait
	-- varier les coulées d'un cas de test à l'autre.
	local function generator(seed: number)
		local state = seed
		local function real(): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
		local function int(a: number, b: number): number
			return a + math.floor(real() * (b - a + 1))
		end
		return int, real
	end

	-- Cette méthode permet de dire si `x` est un multiple de la grille (à l'arrondi près) lorsque l'on vérifie un calage.
	local function onGrid(x: number): boolean
		local r = x % Drips.GRID
		return r < 1e-6 or Drips.GRID - r < 1e-6
	end

	local cases = {
		{ origin = 0, length = 120 },
		{ origin = 40, length = 233 },
		{ origin = -50, length = 410 },
		{ origin = 1137.5, length = 97.3 },
		{ origin = -10, length = 6 },
	}

	T.describe("Drips.layout", function()
		T.it("cale chaque bloc sur la grille du damier et le garde dans le bord", function()
			for seed = 1, 40 do
				for _, case in cases do
					local int, real = generator(seed)
					for _, block in Drips.layout(case.origin, case.length, int, real) do
						T.expect(onGrid(case.origin + block.t), "début sur la grille")
						T.expect(onGrid(block.width) and block.width >= Drips.GRID, "largeur multiple de la grille")
						T.expect(block.t >= 0 and block.t + block.width <= case.length + 1e-6, "dans le bord")
						T.expect(block.top + block.height <= Drips.MAX_DROP, "descente bornée")
					end
				end
			end
		end)

		T.it("pose chaque marche du dessous sous son bloc, plus étroite d'un demi-carreau", function()
			local steps = 0
			for seed = 1, 40 do
				local int, real = generator(seed)
				local blocks = Drips.layout(0, 300, int, real)
				for i, block in blocks do
					if block.top > 0 then
						steps += 1
						local above = blocks[i - 1]
						T.expectEqual(above.top, 0)
						T.expectEqual(block.top, above.height)
						T.expectEqual(block.width, above.width - Drips.GRID)
						T.expect(block.t >= above.t and block.t + block.width <= above.t + above.width, "sous son bloc")
					end
				end
			end
			T.expect(steps > 0, "au moins une marche en escalier")
		end)

		T.it("reste au-dessus de la marche suivante des parois", function()
			T.expect(
				Drips.MAX_DROP + Drips.CLEARANCE < CourseLayout.TIER_HEIGHT,
				"descente au-dessus de la couverture de la marche du dessous"
			)
		end)

		T.it("ne pose rien sur un bord plus court qu'un demi-carreau", function()
			local int, real = generator(7)
			T.expectEqual(#Drips.layout(1, Drips.GRID - 0.5, int, real), 0)
		end)
	end)
end
