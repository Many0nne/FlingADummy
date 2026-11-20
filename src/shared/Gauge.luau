-- Jauge de charge : aiguille en onde triangle et facteur de vitesse (pas de zone PERFECT : le haut est le max).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Gauge = {}

-- Cette méthode permet de donner la position de l'aiguille (0 → 1 → 0) lorsque la charge dure `t` secondes.
function Gauge.value(t: number): number
	local phase = (t % GameConfig.GAUGE_PERIOD) / GameConfig.GAUGE_PERIOD
	return if phase < 0.5 then phase * 2 else 2 - phase * 2
end

-- Cette méthode permet de convertir la jauge en fraction de la vitesse du canon lorsque le joueur relâche.
function Gauge.launchFactor(v: number): number
	local min = GameConfig.GAUGE_MIN_FACTOR
	return min + (1 - min) * math.clamp(v, 0, 1)
end

-- Cette méthode permet de donner les valeurs extrêmes de l'aiguille sur l'intervalle de temps [a, b] lorsque le
-- serveur vérifie une valeur reçue (bornes et sommets de l'onde triangle compris).
function Gauge.range(a: number, b: number): (number, number)
	local period = GameConfig.GAUGE_PERIOD
	if b - a >= period then
		return 0, 1
	end
	local va, vb = Gauge.value(a), Gauge.value(b)
	local low, high = math.min(va, vb), math.max(va, vb)
	-- Sommets (valeur 1) en P/2 + kP, creux (valeur 0) en kP
	if period / 2 + math.ceil((a - period / 2) / period) * period <= b then
		high = 1
	end
	if math.ceil(a / period) * period <= b then
		low = 0
	end
	return low, high
end

-- Cette méthode permet de retenir la valeur d'un lancer lorsque le serveur la reçoit `elapsed` secondes après avoir
-- ouvert la jauge, avec une latence aller-retour mesurée `lag` : la valeur du client si elle est atteignable par un
-- clic dans la fenêtre (lâcher de l'animation et latence déduits, avec tolérance), sinon celle du serveur. Renvoie
-- la valeur retenue et si celle du client a été acceptée.
function Gauge.verify(claimed: number, elapsed: number, lag: number): (number, boolean)
	local measured = math.clamp(lag, 0, GameConfig.GAUGE_MAX_LAG)
	-- Instant du clic estimé par le serveur, depuis l'apparition de la jauge chez le client
	local click = elapsed - GameConfig.THROW_RELEASE_TIME - measured
	local tolerance = GameConfig.GAUGE_LAG_TOLERANCE
	local from = math.max(0, click - GameConfig.GAUGE_RELEASE_SLACK - tolerance)
	local to = math.max(0, click + tolerance)
	local low, high = Gauge.range(from, to)
	local value = math.clamp(claimed, 0, 1)
	if value >= low - 1e-3 and value <= high + 1e-3 then
		return value, true
	end
	return Gauge.value(math.max(0, click)), false
end

return Gauge
