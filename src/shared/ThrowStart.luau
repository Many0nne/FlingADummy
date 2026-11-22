-- Départ d'un lancer (#144, logique pure, testée) : point de départ (main de l'avatar au lâcher), direction et vitesse.
-- Le serveur en décide (Server.LaunchService) ; le lanceur fait le même calcul au lâcher (Client.LaunchGhost) pour
-- afficher le départ sans attendre la réponse du serveur, puis se recale sur celui du serveur à son arrivée.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Gauge = require(Shared:WaitForChild("Gauge"))

local ThrowStart = {}

local PITCH = math.rad(GameConfig.LAUNCH_PITCH_DEG)

-- Direction du lancer, commune à toutes les places : le long de la piste (+Z), inclinée de LAUNCH_PITCH_DEG
ThrowStart.DIRECTION = Vector3.new(0, math.sin(PITCH), math.cos(PITCH))

-- Cette méthode permet de donner le point de départ du mannequin (main de l'avatar au lâcher : au-dessus du
-- HumanoidRootPart, côté du bras droit) lorsque l'avatar est en `rootPosition` et regarde vers `look`.
function ThrowStart.origin(rootPosition: Vector3, look: Vector3): Vector3
	local flat = Vector3.new(look.X, 0, look.Z)
	local forward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local right = forward:Cross(Vector3.yAxis)
	return rootPosition
		+ Vector3.new(0, GameConfig.THROW_HEIGHT, 0)
		+ forward * GameConfig.THROW_FORWARD
		+ right * GameConfig.THROW_SIDE
end

-- Cette méthode permet de donner la vitesse de départ (studs/s) d'un lancer à la puissance `power` avec la jauge
-- arrêtée à `gauge` (0-1) lorsque le mannequin part.
function ThrowStart.speed(power: number, gauge: number): number
	return Economy.launchSpeed(power) * Gauge.launchFactor(gauge)
end

return ThrowStart
