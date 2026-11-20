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

return Gauge
