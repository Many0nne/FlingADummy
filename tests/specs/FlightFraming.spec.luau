-- Cadrage de la caméra de vol (#88) : bas comme avant au ras du sol, plongeant en altitude (piste dans toute l'image,
-- pas de ciel), distance bornée, transition sans saut.
return function(T, Loader)
	local loader = Loader.new()
	local FlightFraming = loader:require("src/shared/FlightFraming")

	local FOV = 70 -- champ de vision vertical de la caméra de vol (Client.FlightCamera, BASE_FOV)

	-- Cette méthode permet de donner la plongée (degrés) du regard de la caméra vers le torse lorsque l'on vérifie
	-- ce que voit le haut de l'image.
	local function lookPitch(offset: Vector3): number
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		return math.deg(math.atan2(offset.Y, flat))
	end

	T.describe("FlightFraming.offset", function()
		T.it("garde au ras du sol le cadrage d'avant #88 (arrière, côté, un peu au-dessus)", function()
			local offset = FlightFraming.offset(3, 60)
			local before = Vector3.new(16, 10, -26)
			T.expect((offset - before).Magnitude < 4, string.format("écart %.1f studs", (offset - before).Magnitude))
			T.expect(offset.X > 0 and offset.Z < 0, "derrière, sur le côté")
		end)

		T.it("plonge vers la piste quand le mannequin monte : le haut de l'image reste sous l'horizon", function()
			for _, height in { 160, 300, 470, 2000 } do
				local pitch = lookPitch(FlightFraming.offset(height, 150))
				T.expect(
					pitch - FOV / 2 > 10,
					string.format("à %d studs : haut de l'image à %.0f°", height, pitch - FOV / 2)
				)
			end
			-- Ras du sol : on voit encore loin devant (horizon dans l'image)
			T.expect(lookPitch(FlightFraming.offset(2, 100)) < FOV / 2, "horizon visible en vol bas")
		end)

		T.it("plonge de plus en plus et se recentre dans l'axe de la piste avec l'altitude", function()
			local previous = FlightFraming.offset(0, 100)
			for height = 5, 400, 5 do
				local offset = FlightFraming.offset(height, 100)
				T.expect(lookPitch(offset) >= lookPitch(previous) - 1e-9, "plongée croissante à " .. height)
				T.expect(offset.X / -offset.Z <= previous.X / -previous.Z + 1e-9, "côté décroissant à " .. height)
				-- Sans saut : quelques studs au plus entre deux hauteurs voisines
				T.expect((offset - previous).Magnitude < 2, "transition douce à " .. height)
				previous = offset
			end
		end)

		T.it("borne la distance au torse quelle que soit la vitesse", function()
			for _, speed in { 0, 50, 120, 250, 600, 5000 } do
				for _, height in { 0, 80, 500 } do
					local distance = FlightFraming.offset(height, speed).Magnitude
					T.expect(
						-- Vector3 en float32 : tolérance au millième
						distance >= FlightFraming.MIN_DISTANCE - 1e-3 and distance <= FlightFraming.MAX_DISTANCE + 1e-3,
						string.format("%.1f studs à %d studs/s", distance, speed)
					)
				end
			end
			T.expect(FlightFraming.distance(300) > FlightFraming.distance(50), "recule avec la vitesse")
		end)

		T.it("reste derrière et au-dessus du torse (jamais sous la piste)", function()
			for _, height in { 0, 1, 20, 100, 1000 } do
				local offset = FlightFraming.offset(height, 100)
				T.expect(offset.Z < 0, "derrière")
				T.expect(height + offset.Y > 5, "au-dessus de la piste")
			end
		end)
	end)
end
