-- Jauge de charge : aiguille en onde triangle, facteur de vitesse et zone PERFECT.
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

-- Cette méthode permet de savoir si le lancer est PERFECT lorsque la jauge est relâchée en haut.
function Gauge.isPerfect(v: number): boolean
	return v >= GameConfig.PERFECT_THRESHOLD
end

return Gauge
