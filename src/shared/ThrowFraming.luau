-- Cadrages de la caméra au lancer (logique pure, testée, #158) : prise sur la bande (derrière l'épaule droite, regard
-- dans l'axe de la piste, comme 09 à la jauge), gros plan du geste (côté du bras qui lance, Client.ThrowCinematic), et
-- passage de l'un à l'autre sans saut : la caméra tourne autour de l'avatar (angle, rayon et hauteur interpolés) au
-- lieu de couper au travers. Lu par Client.FlightCamera. Repère du personnage : X à droite, Y en haut, -Z devant.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local ThrowFraming = {}

-- Gros plan du geste (valeurs d'avant #158, réglées sur 01) : départ, arrivée, point visé, inclinaison finale
ThrowFraming.CLOSE_FROM = Vector3.new(5.6, 2.9, -3.2)
ThrowFraming.CLOSE_TO = Vector3.new(4.5, 2.6, -2.5)
ThrowFraming.CLOSE_FOCUS = Vector3.new(0.5, 2.6, 0)
ThrowFraming.CLOSE_FOV = 50
ThrowFraming.CLOSE_ROLL = math.rad(-5)
ThrowFraming.MIN_FOCUS = 4 -- point visé implicite d'un cadrage quelconque, au moins à cette distance (studs)

-- Cette méthode permet de donner l'avancement adouci (0 → 1, départ et arrivée sans à-coup) d'un fondu de `duration`
-- secondes lorsque `elapsed` secondes sont passées ; une durée nulle (mouvement réduit) donne la coupe directe.
function ThrowFraming.progress(elapsed: number, duration: number): number
	if duration <= 0 then
		return 1
	end
	local k = math.clamp(elapsed / duration, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Cette méthode permet de donner la position de la caméra et son point visé sur la bande lorsque le joueur tient le
-- mannequin (`root` : CFrame du HumanoidRootPart, tourné face à la piste par le serveur).
function ThrowFraming.band(root: CFrame): (Vector3, Vector3)
	local side, height = GameConfig.BAND_CAM_SIDE, GameConfig.BAND_CAM_HEIGHT
	local position = root:PointToWorldSpace(Vector3.new(side, height, GameConfig.BAND_CAM_BACK))
	-- Point visé décalé du même côté : regard parallèle à la piste, avatar à gauche du centre
	local focus = root:PointToWorldSpace(Vector3.new(side, height - GameConfig.BAND_CAM_DIP, -GameConfig.BAND_CAM_LOOK))
	return position, focus
end

-- Cette méthode permet de donner la position, le point visé et l'inclinaison du gros plan du geste lorsque `eased`
-- (0 → 1) en est l'avancement ; `base` est le repère du personnage figé au clic.
function ThrowFraming.closeUp(base: CFrame, eased: number): (Vector3, Vector3, number)
	local position = base:PointToWorldSpace(ThrowFraming.CLOSE_FROM:Lerp(ThrowFraming.CLOSE_TO, eased))
	return position, base:PointToWorldSpace(ThrowFraming.CLOSE_FOCUS), ThrowFraming.CLOSE_ROLL * eased
end

-- Cette méthode permet de donner un point visé pour un cadrage quelconque (caméra libre) lorsqu'un fondu en part :
-- devant la caméra, à la distance de l'avatar (`pivot`), pour qu'il reste à l'image pendant le fondu.
function ThrowFraming.focusOf(view: CFrame, pivot: Vector3): Vector3
	local distance = math.max((pivot - view.Position).Magnitude, ThrowFraming.MIN_FOCUS)
	return view.Position + view.LookVector * distance
end

-- Cette méthode permet de ramener un angle (radians) entre -π et π lorsqu'un fondu tourne au plus court.
local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Cette méthode permet de donner le cap (autour de Y) et l'inclinaison d'une direction lorsqu'un fondu interpole un
-- regard ou une position autour de l'avatar.
local function heading(v: Vector3): (number, number)
	return math.atan2(v.X, v.Z), math.atan2(v.Y, Vector3.new(v.X, 0, v.Z).Magnitude)
end

-- Cette méthode permet de donner la position et le point visé de la caméra pendant un fondu (avancement `k`, 0 → 1)
-- d'un cadrage à un autre autour de l'avatar (`pivot`) lorsqu'elle entre sur la bande ou passe au gros plan : la
-- position tourne autour de lui au plus court (angle, rayon, hauteur), le regard tourne d'autant, plus l'écart qui
-- reste au plus court ; il tourne ainsi à vitesse régulière et l'avatar reste à l'image.
function ThrowFraming.blend(
	fromPosition: Vector3,
	fromFocus: Vector3,
	toPosition: Vector3,
	toFocus: Vector3,
	pivot: Vector3,
	k: number
): (Vector3, Vector3)
	if k >= 1 then
		return toPosition, toFocus
	elseif k <= 0 then
		return fromPosition, fromFocus
	end
	local a, b = fromPosition - pivot, toPosition - pivot
	local angleA, angleB = heading(a), heading(b)
	local turn = wrap(angleB - angleA)
	local angle = angleA + turn * k
	local radiusA = Vector3.new(a.X, 0, a.Z).Magnitude
	local radius = radiusA + (Vector3.new(b.X, 0, b.Z).Magnitude - radiusA) * k
	local position = pivot + Vector3.new(math.sin(angle) * radius, a.Y + (b.Y - a.Y) * k, math.cos(angle) * radius)

	local lookA, lookB = fromFocus - fromPosition, toFocus - toPosition
	local yawA, pitchA = heading(lookA)
	local yawB, pitchB = heading(lookB)
	local yaw = yawA + (turn + wrap(yawB - yawA - turn)) * k
	local pitch = pitchA + (pitchB - pitchA) * k
	local distance = lookA.Magnitude + (lookB.Magnitude - lookA.Magnitude) * k
	local look = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	return position, position + look * distance
end

return ThrowFraming
