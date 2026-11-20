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
end
