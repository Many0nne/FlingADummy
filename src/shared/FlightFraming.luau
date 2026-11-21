-- Cadrage de la caméra de vol (logique pure, testée, #88) : la caméra vise le torse du mannequin (centre de l'image)
-- depuis l'arrière, un peu sur le côté ; plus il monte, plus elle plonge vers la piste et se recentre derrière lui,
-- comme la caméra de suivi des jeux de référence (01, 09) : à toute altitude, la piste remplit l'image devant le
-- mannequin au lieu du ciel. La distance suit la vitesse, bornée. Lu par Client.FlightCamera.
local FlightFraming = {}

FlightFraming.LOW_HEIGHT = 10 -- en dessous (studs au-dessus de la piste) : cadrage bas, celui d'avant #88
FlightFraming.HIGH_HEIGHT = 160 -- au-dessus : cadrage plongeant
FlightFraming.LOW_PITCH = 18 -- plongée du cadrage bas (degrés sous l'horizontale)
FlightFraming.HIGH_PITCH = 52 -- plongée du cadrage plongeant : le haut de l'image (FOV 70) reste sur la piste
FlightFraming.LOW_YAW = 32 -- écart sur le côté (+X) du cadrage bas (degrés)
FlightFraming.HIGH_YAW = 10 -- écart sur le côté du cadrage plongeant : presque dans l'axe de la piste
FlightFraming.MIN_DISTANCE = 30 -- distance caméra-torse au repos (studs)
FlightFraming.MAX_DISTANCE = 44 -- distance au plus vite : le mannequin reste gros même à 250 studs/s
FlightFraming.PER_SPEED = 0.06 -- distance ajoutée par stud/s de vitesse

-- Cette méthode permet de donner la part du cadrage plongeant (0 au ras du sol, 1 en altitude, transition douce)
-- lorsque le mannequin est à `height` studs au-dessus de la piste.
function FlightFraming.blend(height: number): number
	local k =
		math.clamp((height - FlightFraming.LOW_HEIGHT) / (FlightFraming.HIGH_HEIGHT - FlightFraming.LOW_HEIGHT), 0, 1)
	return k * k * (3 - 2 * k)
end

-- Cette méthode permet de donner la distance caméra-torse (studs) lorsque le mannequin vole à `speed` studs/s.
function FlightFraming.distance(speed: number): number
	return math.clamp(
		FlightFraming.MIN_DISTANCE + math.max(speed, 0) * FlightFraming.PER_SPEED,
		FlightFraming.MIN_DISTANCE,
		FlightFraming.MAX_DISTANCE
	)
end

-- Cette méthode permet de donner la plongée de la caméra (radians sous l'horizontale) lorsque le mannequin est à
-- `height` studs au-dessus de la piste.
function FlightFraming.pitch(height: number): number
	local k = FlightFraming.blend(height)
	return math.rad(FlightFraming.LOW_PITCH + (FlightFraming.HIGH_PITCH - FlightFraming.LOW_PITCH) * k)
end

-- Cette méthode permet de donner la position de la caméra par rapport au torse (arrière = -Z, côté = +X) lorsque le
-- mannequin est à `height` studs au-dessus de la piste et vole à `speed` studs/s ; la caméra vise le torse.
function FlightFraming.offset(height: number, speed: number): Vector3
	local k = FlightFraming.blend(height)
	local pitch = FlightFraming.pitch(height)
	local yaw = math.rad(FlightFraming.LOW_YAW + (FlightFraming.HIGH_YAW - FlightFraming.LOW_YAW) * k)
	local distance = FlightFraming.distance(speed)
	local flat = distance * math.cos(pitch)
	return Vector3.new(flat * math.sin(yaw), distance * math.sin(pitch), -flat * math.cos(yaw))
end

return FlightFraming
