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

-- Cette méthode permet de retenir la valeur `claimed` d'un lancer reçu `elapsed` s après l'ouverture de la jauge (latence
-- `lag`) : celle du client si un clic dans la fenêtre l'atteint, sinon celle du serveur ; renvoie aussi l'acceptation.
-- `stopAt` (arrivée du GaugeStop, s après l'ouverture) réduit la fenêtre à la latence seule ; absent, hors de
-- [0, elapsed] ou en trop, le lâcher en retard est couvert (repli).
function Gauge.verify(claimed: number, elapsed: number, lag: number, stopAt: number?): (number, boolean)
	local measured = math.clamp(lag, 0, GameConfig.GAUGE_MAX_LAG)
	local tolerance = GameConfig.GAUGE_LAG_TOLERANCE
	local click, from, to
	if stopAt and stopAt >= 0 and stopAt <= elapsed then
		-- Clic estimé : arrivée du GaugeStop moins le trajet aller (demi aller-retour)
		click = stopAt - measured / 2
		from = math.max(0, click - tolerance)
	else
		-- Instant du clic estimé par le serveur, depuis l'apparition de la jauge chez le client
		click = elapsed - GameConfig.THROW_RELEASE_TIME - measured
		from = math.max(0, click - GameConfig.GAUGE_RELEASE_SLACK - tolerance)
	end
	to = math.max(0, click + tolerance)
	local low, high = Gauge.range(from, to)
	local value = math.clamp(claimed, 0, 1)
	if value >= low - 1e-3 and value <= high + 1e-3 then
		return value, true
	end
	return Gauge.value(math.max(0, click)), false
end

return Gauge
