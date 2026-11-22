-- Vols simulés pour l'anneau propulseur de la Moon Base (#98) : hauteur du torse au passage de chaque site du piège
-- « Booster » et taux de passage dans le cerceau, avec le plan de vol du serveur (Shared.FlightGhost.path : sans obstacle
-- ni piège). Partagé par tools/booster-ring.luau (tableaux avant / après) et tests/specs/BoosterRing.spec.luau (le
-- recalage du cerceau). Population : puissances de POWER_MIN à POWER_MAX (progression géométrique) × jauge de 0 à 1
-- (l'aiguille court en triangle : valeurs équiréparties) ; seuls comptent les vols encore en l'air au passage du site.
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local BoosterRingSim = {}

BoosterRingSim.POWER_MIN = 1e3
BoosterRingSim.POWER_MAX = 1e11 -- au-delà, le vol touche le sol au bout de la piste
BoosterRingSim.POWER_STEP = 1.25 -- raison de la progression des puissances simulées
BoosterRingSim.GAUGE_STEP = 0.05
BoosterRingSim.HORIZON = 30 -- durée simulée au plus (s)
BoosterRingSim.ORIGIN = Vector3.new(0, 5.3, -5.7) -- main de l'avatar au lâcher (Shared.ThrowStart, mesuré en Studio)

export type Flight = { positions: { Vector3 } }

-- Cette méthode permet de charger les modules du jeu utilisés par la simulation lorsque l'outil ou le test démarre
-- (`loader` : tests/lib/Loader).
function BoosterRingSim.modules(loader: any): { [string]: any }
	local modules = {}
	for _, name in
		{ "Economy", "FlightGhost", "GameConfig", "Gauge", "ThrowDummies", "TrackPlan", "Traps" }
	do
		modules[name] = loader:require("src/shared/" .. name)
	end
	return modules
end

-- Cette méthode permet de donner les distances (m) des sites du piège « Booster » lorsque l'on mesure ou que l'on
-- vérifie le cerceau ; une boîte par colonne, toutes à la même hauteur.
function BoosterRingSim.sites(m: { [string]: any }): { number }
	local sites = {}
	for _, site in m.TrackPlan.sites(m.GameConfig.COURSE_LENGTH) do
		if site.kind == "Trap" and site.name == "Booster" then
			table.insert(sites, site.z)
		end
	end
	return sites
end

-- Cette méthode permet de simuler les vols du mannequin lancé `thrown` (Shared.ThrowDummies) pour toutes les puissances
-- (raison `step`) et jauges (pas `gaugeStep`) lorsque l'on cherche où ils passent au-dessus des sites.
function BoosterRingSim.flights(m: { [string]: any }, thrown: any, step: number?, gaugeStep: number?): { Flight }
	assert((step or BoosterRingSim.POWER_STEP) > 1, "raison des puissances > 1")
	assert((gaugeStep or BoosterRingSim.GAUGE_STEP) > 0, "pas de jauge > 0")
	local flights: { Flight } = {}
	local pitch = math.rad(m.GameConfig.LAUNCH_PITCH_DEG)
	local power = BoosterRingSim.POWER_MIN
	while power <= BoosterRingSim.POWER_MAX do
		local gauge = 0
		while gauge <= 1 + 1e-9 do
			local speed = m.Economy.launchSpeed(power) * m.Gauge.launchFactor(gauge)
			table.insert(
				flights,
				m.FlightGhost.path(
					BoosterRingSim.ORIGIN,
					Vector3.new(0, speed * math.sin(pitch), speed * math.cos(pitch)),
					m.GameConfig.GRAVITY,
					thrown,
					BoosterRingSim.HORIZON
				)
			)
			gauge += gaugeStep or BoosterRingSim.GAUGE_STEP
		end
		power *= step or BoosterRingSim.POWER_STEP
	end
	return flights
end

-- Cette méthode permet de donner la hauteur du torse (studs) quand le vol passe la distance `z` (m), nil s'il touche le
-- sol avant (la trajectoire s'arrête au premier contact), lorsque l'on cherche s'il traverse l'anneau de ce site.
function BoosterRingSim.heightAt(flight: Flight, z: number): number?
	local positions = flight.positions
	for i = 2, #positions do
		local a, b = positions[i - 1], positions[i]
		if b.Z >= z then
			return a.Y + (b.Y - a.Y) * (z - a.Z) / math.max(b.Z - a.Z, 1e-9)
		end
	end
	return nil
end

-- Cette méthode permet de donner les hauteurs du torse (triées) des vols en l'air au passage du site `z` lorsque l'on
-- mesure leur dispersion.
function BoosterRingSim.heights(flights: { Flight }, z: number): { number }
	local list = {}
	for _, flight in flights do
		local height = BoosterRingSim.heightAt(flight, z)
		if height then
			table.insert(list, height)
		end
	end
	table.sort(list)
	return list
end

-- Cette méthode permet de donner la part (0 à 1) des hauteurs `heights` comprises entre `bottom` et `top` (ouverture
-- de l'anneau) lorsque l'on mesure le taux de passage d'un site.
function BoosterRingSim.share(heights: { number }, bottom: number, top: number): number
	local hit = 0
	for _, height in heights do
		if height >= bottom and height <= top then
			hit += 1
		end
	end
	return if #heights > 0 then hit / #heights else 0
end

return BoosterRingSim
