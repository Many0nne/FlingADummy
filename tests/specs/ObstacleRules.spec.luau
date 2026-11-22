-- Obstacles partagés : pièce déplacée, délai de réapparition, ordre de bas en haut, objet projeté compté pour le vol le
-- plus proche.
return function(T, Loader)
	local loader = Loader.new()
	local ObstacleRules = loader:require("src/shared/ObstacleRules")
	local GameConfig = loader:require("src/shared/GameConfig")

	T.describe("ObstacleRules.isDisplaced", function()
		local home = CFrame.new(10, 2, 50)
		T.it("ignore une pièce juste bousculée", function()
			T.expect(not ObstacleRules.isDisplaced(home, home), "immobile")
			T.expect(not ObstacleRules.isDisplaced(home, home + Vector3.new(0.5, 0, 0.5)), "poussée de 0,7 stud")
			T.expect(not ObstacleRules.isDisplaced(home, home * CFrame.Angles(0, math.rad(10), 0)), "tournée de 10°")
		end)
		T.it("repère une pièce déplacée ou renversée", function()
			T.expect(ObstacleRules.isDisplaced(home, home + Vector3.new(0, 0, 3)), "déplacée de 3 studs")
			T.expect(ObstacleRules.isDisplaced(home, home * CFrame.Angles(math.rad(90), 0, 0)), "renversée")
			T.expect(ObstacleRules.isDisplaced(home, home * CFrame.Angles(0, math.rad(45), 0)), "tournée de 45°")
		end)
	end)

	T.describe("ObstacleRules.isDue", function()
		T.it("attend RESPAWN_DELAY après le dernier choc", function()
			T.expect(not ObstacleRules.isDue(nil, 100), "jamais touché")
			T.expect(not ObstacleRules.isDue(100, 100 + GameConfig.RESPAWN_DELAY - 0.1), "trop tôt")
			T.expect(ObstacleRules.isDue(100, 100 + GameConfig.RESPAWN_DELAY), "dû")
			T.expect(GameConfig.RESPAWN_DELAY >= 2 and GameConfig.RESPAWN_DELAY <= 10, "quelques secondes")
		end)
	end)

	T.describe("ObstacleRules.respawnOrder", function()
		T.it("ne rend que les pièces déplacées, de bas en haut puis de gauche à droite", function()
			local homes = {
				CFrame.new(0, 6, 0),
				CFrame.new(4, 2, 0),
				CFrame.new(-4, 2, 0),
				CFrame.new(0, 10, 0),
				CFrame.new(8, 2, 0),
			}
			local order = ObstacleRules.respawnOrder(homes, { true, true, true, true, false })
			T.expectEqual(#order, 4)
			T.expectEqual(order[1], 3)
			T.expectEqual(order[2], 2)
			T.expectEqual(order[3], 1)
			T.expectEqual(order[4], 4)
		end)
		T.it("rend une liste vide si rien n'a bougé", function()
			T.expectEqual(#ObstacleRules.respawnOrder({ CFrame.new() }, { false }), 0)
		end)
	end)

	T.describe("ObstacleRules.claimant", function()
		T.it("compte l'objet pour le mannequin le plus proche, s'il est assez près", function()
			local flights = { Vector3.new(-21, 3, 90), Vector3.new(7, 3, 92), Vector3.new(21, 40, 300) }
			T.expectEqual(ObstacleRules.claimant(Vector3.new(5, 2, 90), flights), 2)
			T.expectEqual(ObstacleRules.claimant(Vector3.new(-18, 2, 91), flights), 1)
			T.expectEqual(ObstacleRules.claimant(Vector3.new(0, 2, 600), flights), nil)
			T.expectEqual(ObstacleRules.claimant(Vector3.new(0, 2, 90), {}), nil)
		end)
	end)

	T.describe("ObstacleRules.staggeredWall (#114)", function()
		local span = GameConfig.SLOT_COUNT * GameConfig.SLOT_SPACING
		local gap = 0.04
		-- Murs des thèmes (Server.ThemeObstacles : Wall, IceWall), puis d'autres largeurs de brique
		local walls = {
			{ brick = Vector3.new(3.96, 3, 2.5), rows = 7 },
			{ brick = Vector3.new(4, 4, 3), rows = 4 },
		}
		for width = 2, 6, 0.37 do
			table.insert(walls, { brick = Vector3.new(width, 2, 2), rows = 6 })
		end

		T.it("pose chaque brique sur celles de la rangée du dessous (centre au-dessus de leur appui)", function()
			for _, wall in walls do
				local bricks = ObstacleRules.staggeredWall(span, wall.brick, wall.rows, gap)
				for _, brick in bricks do
					if brick.row > 0 then
						local low, high = math.huge, -math.huge
						for _, under in bricks do
							local overlap = math.min(brick.x + brick.width / 2, under.x + under.width / 2)
								- math.max(brick.x - brick.width / 2, under.x - under.width / 2)
							if under.row == brick.row - 1 and overlap > 0 then
								low = math.min(low, under.x - under.width / 2)
								high = math.max(high, under.x + under.width / 2)
							end
						end
						T.expect(
							brick.x >= low and brick.x <= high,
							string.format(
								"brique %.2f de la rangée %d en porte-à-faux (appui %.2f à %.2f)",
								brick.x,
								brick.row,
								low,
								high
							)
						)
					end
				end
			end
		end)

		T.it("garde les rangées dans la largeur, sans briques qui se chevauchent", function()
			for _, wall in walls do
				local bricks = ObstacleRules.staggeredWall(span, wall.brick, wall.rows, gap)
				local byRow = {}
				for _, brick in bricks do
					T.expect(math.abs(brick.x) + brick.width / 2 <= span / 2 + 1e-6, "hors des colonnes")
					T.expect(brick.width >= wall.brick.X / 2 - gap, "brique trop étroite")
					byRow[brick.row] = byRow[brick.row] or {}
					table.insert(byRow[brick.row], brick)
				end
				for row = 0, wall.rows - 1 do
					local list = byRow[row]
					table.sort(list, function(a, b)
						return a.x < b.x
					end)
					for i = 2, #list do
						local space = (list[i].x - list[i].width / 2) - (list[i - 1].x + list[i - 1].width / 2)
						T.expect(space >= gap - 1e-6, "briques collées rangée " .. row)
					end
					-- Rangées décalées aussi larges que les autres : demi-briques aux deux bouts
					local first, last = list[1], list[#list]
					local edge = byRow[0][1].x - byRow[0][1].width / 2
					T.expect(math.abs((first.x - first.width / 2) - edge) < 1e-6, "bord gauche rangée " .. row)
					T.expect(math.abs((last.x + last.width / 2) + edge) < 1e-6, "bord droit rangée " .. row)
				end
			end
		end)
	end)
end
