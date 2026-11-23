-- Garde-fou du décor (#93, #38) : construit tout le décor généré sous Lune (Server.CourseBuilder : hub, bases, zone de
-- lancer, piste, gradins, accessoires, obstacles des thèmes, pièges ; tests/lib/DecorBuild) et cherche les faces
-- confondues visibles (tests/lib/Coplanar, règle Shared.SurfaceGap) : deux pièces dont des faces de même sens sont dans
-- le même plan et se recouvrent scintillent quand la caméra bouge. Limites : seuls les blocs (Part de forme Block) sont
-- contrôlés (pas les cylindres, boules, coins ni maillages) ; les accessoires semés au hasard le sont pour un tirage
-- (Random simulé), les règles de pose (Build.settled, Build.within) valent pour tous.
return function(T, Loader, Lib)
	local scene = Lib.DecorBuild.build(Loader)
	local SurfaceGap = scene.loader:require("src/shared/SurfaceGap")
	local CourseLayout = scene.loader:require("src/shared/CourseLayout")
	local BaseLook = scene.loader:require("src/shared/BaseLook")
	local Training = scene.loader:require("src/shared/Training")
	local CourseBuilder = scene.CourseBuilder

	-- Cette méthode permet de n'afficher que les `capacity` premiers présentoirs d'une base, comme le fait
	-- Server.BaseService (les autres ne sont pas achetés, #212), lorsque le test contrôle les bases.
	local function showDisplays(slot, capacity: number)
		for index in slot.base.displays do
			CourseBuilder.showDisplay(slot, index, index <= capacity)
		end
	end

	-- Cette méthode permet de résumer les faces confondues trouvées sous `roots` (5 au plus) lorsqu'un test échoue.
	local function check(roots: { any }): (number, string)
		local boxes = {}
		for _, root in roots do
			for _, box in Lib.DecorBuild.boxes(root) do
				table.insert(boxes, box)
			end
		end
		local hits = Lib.Coplanar.find(boxes, SurfaceGap)
		local lines = {}
		for i = 1, math.min(#hits, 5) do
			local hit = hits[i]
			table.insert(
				lines,
				string.format(
					"%s / %s (écart %.3f, en %.1f %.1f %.1f)",
					hit.a.label,
					hit.b.label,
					hit.gap,
					hit.at.X,
					hit.at.Y,
					hit.at.Z
				)
			)
		end
		return #hits, table.concat(lines, " | ")
	end

	T.describe("DecorFaces (#93)", function()
		T.it("aucune face confondue visible dans le décor construit", function()
			for _, slot in scene.built.slots do
				showDisplays(slot, slot.base.capacity)
			end
			local count, detail = check({ scene.course })
			T.expectEqual(count, 0, detail)
		end)

		T.it(
			"bases et appareils d'entraînement à tous les paliers, d'une rangée à la base agrandie (#212)",
			function()
				local slot = scene.built.slots[1]
				local columns = CourseLayout.DISPLAY_COLUMNS
				-- Une rangée, une rangée et un présentoir, rangée en cours à moitié, base pleine, Big Base
				for _, capacity in
					{ columns, columns + 1, 2 * columns + 3, CourseLayout.DISPLAY_MAX, CourseLayout.DISPLAY_ROOM }
				do
					for tier = 1, #BaseLook.BASE_TIERS do
						CourseBuilder.styleBase(slot, tier, capacity)
						showDisplays(slot, capacity)
						local count, detail = check({ slot.base.model })
						T.expectEqual(
							count,
							0,
							string.format("base palier %d à %d présentoirs : %s", tier, capacity, detail)
						)
					end
				end
				for tier = 1, #Training.GEARS do
					CourseBuilder.styleStation(slot, tier)
					local count, detail = check({ slot.trainer.model })
					T.expectEqual(count, 0, string.format("appareil palier %d : %s", tier, detail))
				end
			end
		)
	end)
end
