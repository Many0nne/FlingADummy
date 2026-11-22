-- Faces confondues (#93) : deux faces de même sens dans le même plan qui se recouvrent scintillent ; une pièce posée qui
-- en affleure une autre ressort de SurfaceGap.STEP (Server.Build, à la pose d'un élément du décor).
return function(T, Loader)
	local loader = Loader.new()
	local SurfaceGap = loader:require("src/shared/SurfaceGap")

	-- Cette méthode permet de savoir si deux boîtes ont des faces qui scintillent lorsqu'un test vérifie une pose.
	local function clashing(a, b): boolean
		for _, fa in SurfaceGap.faces(a) do
			for _, fb in SurfaceGap.faces(b) do
				if SurfaceGap.clash(fa, fb) then
					return true
				end
			end
		end
		return false
	end

	-- Cette méthode permet de poser `size` en `cframe` après les boîtes `boxes` lorsqu'un test vérifie l'ajustement ;
	-- renvoie la boîte posée.
	local function settle(boxes, size, cframe)
		local placed = {}
		for _, box in boxes do
			table.insert(placed, SurfaceGap.place(box.size, box.cframe))
		end
		local newSize, newCFrame = SurfaceGap.settle(placed, size, cframe)
		return { size = newSize, cframe = newCFrame }
	end

	T.describe("SurfaceGap.clash", function()
		local base = { size = Vector3.new(6, 4, 6), cframe = CFrame.new(0, 2, 0) }
		T.it("repère deux blocs qui se recouvrent avec un côté dans le même plan", function()
			local top = { size = Vector3.new(3, 3, 3), cframe = CFrame.new(1.5, 3.5, 0) } -- côté +X à x = 3, comme la base
			T.expect(clashing(base, top), "côtés confondus")
		end)
		T.it("laisse deux blocs empilés ou côte à côte (faces opposées, bords qui se touchent)", function()
			T.expect(not clashing(base, { size = Vector3.new(6, 2, 6), cframe = CFrame.new(0, 5, 0) }), "empilés")
			T.expect(
				not clashing(base, { size = Vector3.new(6, 4, 6), cframe = CFrame.new(6, 2, 0) }),
				"côte à côte"
			)
		end)
		T.it("laisse deux faces écartées d'au moins MIN_GAP, arrondis compris", function()
			local inset = { size = Vector3.new(3, 3, 3), cframe = CFrame.new(1.5 - 0.0499, 3.5, 0) }
			T.expect(not clashing(base, inset), "écart de 0,05 (arrondi)")
		end)
		T.it("repère deux blocs tournés de la même façon", function()
			local turn = CFrame.Angles(0, math.rad(30), 0)
			local a = { size = Vector3.new(4, 1, 1), cframe = turn }
			local b = { size = Vector3.new(1, 1, 4), cframe = turn * CFrame.new(0, 0, 1.5) }
			T.expect(clashing(a, b), "dessus confondus")
		end)
	end)

	T.describe("SurfaceGap.settle", function()
		local base = { size = Vector3.new(6, 4, 6), cframe = CFrame.new(0, 2, 0) }
		T.it("fait ressortir de STEP la face qui affleure, sans bouger les autres", function()
			local placed = settle({ base }, Vector3.new(3, 3, 3), CFrame.new(1.5, 3.5, 0))
			T.expect(not clashing(base, placed), "plus de faces confondues")
			T.expect(math.abs(placed.size.X - (3 + SurfaceGap.STEP)) < 1e-6, "un STEP sur X : " .. placed.size.X)
			T.expect(math.abs(placed.size.Y - 3) < 1e-6 and math.abs(placed.size.Z - 3) < 1e-6, "Y et Z inchangés")
			local right = placed.cframe.Position.X + placed.size.X / 2
			T.expect(math.abs(right - (3 + SurfaceGap.STEP)) < 1e-6, "le côté ressort : " .. right)
			local left = placed.cframe.Position.X - placed.size.X / 2
			T.expect(math.abs(left - 0) < 1e-6, "l'autre côté ne bouge pas : " .. left)
		end)
		T.it("ne touche pas un bloc qui n'affleure rien", function()
			local placed = settle({ base }, Vector3.new(2, 2, 2), CFrame.new(0, 5, 0))
			T.expect(placed.size == Vector3.new(2, 2, 2) and placed.cframe == CFrame.new(0, 5, 0), "inchangé")
		end)
		T.it("règle une croix de deux bras de même section (deux faces avancent)", function()
			local arm = { size = Vector3.new(3, 0.8, 0.8), cframe = CFrame.new() }
			local placed = settle({ arm }, Vector3.new(0.8, 3, 0.8), CFrame.new())
			T.expect(not clashing(arm, placed), "croix sans faces confondues")
			T.expect(math.abs(placed.size.Z - (0.8 + 2 * SurfaceGap.STEP)) < 1e-6, "avant et arrière avancent")
			T.expect(placed.cframe.Position.Magnitude < 1e-6, "toujours centré")
		end)
		T.it("règle une pile de blocs qui affleurent tous le même plan", function()
			local boxes = {}
			for i = 1, 6 do
				local placed = settle(boxes, Vector3.new(4, 1, 1), CFrame.new(0, 0, 0) * CFrame.new(0, 0, i * 0.3))
				for _, other in boxes do
					T.expect(not clashing(other, placed), "bloc " .. i)
				end
				table.insert(boxes, placed)
			end
		end)
	end)
end
