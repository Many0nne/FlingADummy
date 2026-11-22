-- Départ d'un lancer (#144) : point de départ, direction et vitesse, calculés à l'identique par le serveur et par le
-- lanceur au lâcher.
return function(T, Loader)
	local loader = Loader.new()
	local Economy = loader:require("src/shared/Economy")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Gauge = loader:require("src/shared/Gauge")
	local ThrowStart = loader:require("src/shared/ThrowStart")

	T.describe("ThrowStart", function()
		T.it("lance le long de la piste, incliné de LAUNCH_PITCH_DEG", function()
			local d = ThrowStart.DIRECTION
			T.expectNear(d.Magnitude, 1, 1e-6)
			T.expectNear(d.X, 0)
			T.expectNear(math.deg(math.atan2(d.Y, d.Z)), GameConfig.LAUNCH_PITCH_DEG, 1e-6)
		end)

		T.it("part de la main droite de l'avatar (au-dessus, devant, à droite), quel que soit son regard", function()
			local root = Vector3.new(10, 3, -8)
			local origin = ThrowStart.origin(root, Vector3.new(0, 0, 1))
			-- Regard vers +Z : la droite de l'avatar est -X
			T.expectNear(origin.X, root.X - GameConfig.THROW_SIDE, 1e-4)
			T.expectNear(origin.Y, root.Y + GameConfig.THROW_HEIGHT, 1e-4)
			T.expectNear(origin.Z, root.Z + GameConfig.THROW_FORWARD, 1e-4)
			-- Regard incliné : seule sa direction à plat compte
			local tilted = ThrowStart.origin(root, Vector3.new(0, 0.6, 0.8))
			T.expectNear((tilted - origin).Magnitude, 0, 1e-4)
			-- Regard vertical (dégénéré) : repli sur la piste
			local up = ThrowStart.origin(root, Vector3.yAxis)
			T.expectNear((up - origin).Magnitude, 0, 1e-4)
		end)

		T.it("donne la vitesse de la puissance et de la jauge", function()
			for _, power in { GameConfig.START_POWER, 1e4, 22e6 } do
				for _, gauge in { 0, 0.35, 1 } do
					T.expectNear(
						ThrowStart.speed(power, gauge),
						Economy.launchSpeed(power) * Gauge.launchFactor(gauge),
						1e-9
					)
				end
			end
		end)
	end)
end
