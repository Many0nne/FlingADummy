-- Tours de piste (#224, logique pure, testée) : à la ligne d'arrivée (COURSE_LENGTH), un portail renvoie le mannequin au
-- début de son couloir pour un tour de plus (« LAP 2 », « LAP 3 »…). La distance au-delà du bout suit sa propre échelle :
-- la portée « virtuelle » du lancer (point de chute du plan Shared.FlightArc, comportement compris, plus SLIDE_SHARE de la
-- glissade théorique, sans paroi) donne un tour de plus chaque fois qu'elle est multipliée par RATIO (≈ un tour par
-- POWER_PER_LAP de puissance, pour tous les mannequins à lancer : leurs parts de portée sont fixes). Continue, tour
-- partiel compris. Au portail, le serveur relance le mannequin depuis la sortie (EXIT_Z, EXIT_HEIGHT, PITCH_DEG plus
-- tendu qu'au lâcher : un tour dure moins longtemps) avec la vitesse qui pose son point de chute à la distance restante.
-- Lu par Server.LaunchService, Shared.Economy (CHANCE au-delà du bout) et tools/ProgressionSim.luau.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FlightArc = require(Shared:WaitForChild("FlightArc"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Laps = {}

Laps.LENGTH = GameConfig.COURSE_LENGTH -- longueur d'un tour (studs = mètres affichés)
Laps.MAX = 10 -- tours au plus : au dernier, le portail ne renvoie plus (paroi du bout)
-- Échelle d'après le portail : portée virtuelle × RATIO = un tour de plus (calée au joueur simulé : 1 à 2 tours de plus
-- vers la puissance d'avant la première renaissance). Un facteur 10 de puissance multiplie la portée virtuelle par ≈ 1,15
-- au bout de la piste (vitesse + 28 par facteur e) : RATIO = 1,15^log10(POWER_PER_LAP)
Laps.POWER_PER_LAP = 3.5 -- repère de conception : un tour de plus par × 3,5 de puissance environ
Laps.RATIO = 1.08
-- CHANCE des zones au-delà du bout : FINAL_CHANCE × CHANCE_PER_LAP par tour de plus (continue, tour partiel compris)
Laps.CHANCE_PER_LAP = 1.7
-- Part de la glissade freinée théorique comptée dans la portée virtuelle (0,3 à 0,75 mesuré par #113)
Laps.SLIDE_SHARE = 0.4
-- Sortie du portail : au début de la piste, au-dessus de la bande de lancer franchie (les joueurs sont en z < 0)
Laps.EXIT_Z = 12 -- distance de la sortie depuis le départ (studs)
Laps.EXIT_HEIGHT = 30 -- hauteur de la sortie au-dessus de la piste (studs)
Laps.PITCH_DEG = 15 -- angle de la relance (32° au lâcher) : vol plus tendu, tour de 6 km en ≈ 6 s au lieu de 8,5
Laps.MIN_RUN = 40 -- un mannequin qui passe le portail sans réserve repart au moins de cette distance (studs)
Laps.SPEED_MAX = 20000 -- borne haute de la recherche de vitesse (studs/s)

-- Cette méthode permet de donner la portée virtuelle d'un vol (point où la glissade commence, plus SLIDE_SHARE de la
-- glissade théorique, depuis le départ, le long de la piste) lorsque l'on estime où il s'arrêterait sans paroi.
function Laps.virtual(plan: FlightArc.Plan): number
	return plan.reach + Laps.SLIDE_SHARE * FlightArc.slide(plan.landingSpeed)
end

-- Cette méthode permet de donner la distance totale prévue d'un lancer (tours compris) lorsque sa portée virtuelle, depuis
-- le départ de la piste, vaut `reach` : la même en deçà du bout, puis un tour de plus par facteur RATIO.
function Laps.total(reach: number): number
	local length = Laps.LENGTH
	if reach <= length then
		return math.max(reach, 0)
	end
	local extra = math.log(reach / length) / math.log(Laps.RATIO)
	return length * math.min(1 + extra, Laps.MAX)
end

-- Cette méthode permet de donner le tour en cours (1 au premier) lorsque le mannequin a parcouru `distance` au total.
function Laps.lapOf(distance: number): number
	return math.clamp(math.floor(math.max(distance, 0) / Laps.LENGTH) + 1, 1, Laps.MAX)
end

-- Cette méthode permet de donner la distance parcourue dans le tour en cours lorsque le mannequin a parcouru
-- `distance` au total (zone affichée, décor sous le mannequin).
function Laps.within(distance: number): number
	return math.max(distance, 0) - (Laps.lapOf(distance) - 1) * Laps.LENGTH
end

-- Cette méthode permet de donner le multiplicateur de la CHANCE des zones au-delà du bout de la piste lorsque le
-- mannequin a parcouru `distance` au total (1 en deçà).
function Laps.chanceFactor(distance: number): number
	local beyond = math.max(distance - Laps.LENGTH, 0) / Laps.LENGTH
	return Laps.CHANCE_PER_LAP ^ beyond
end

-- Cette méthode permet de donner le plan d'une relance depuis la sortie du portail à `speed` studs/s (PITCH_DEG,
-- comportement `behavior`) lorsque l'on cherche la vitesse d'un tour.
local function relaunchPlan(speed: number, behavior: FlightArc.Behavior?, gravity: number): FlightArc.Plan
	local pitch = math.rad(Laps.PITCH_DEG)
	return FlightArc.plan(speed * math.cos(pitch), speed * math.sin(pitch), Laps.EXIT_HEIGHT, gravity, behavior)
end

-- Cette méthode permet de donner la relance d'un tour (vitesse le long de la piste, vers le haut, et son plan) qui pose
-- la portée virtuelle `run` studs après la sortie (MIN_RUN au moins) lorsque le mannequin passe le portail.
function Laps.relaunch(run: number, behavior: FlightArc.Behavior?, gravity: number): (number, number, FlightArc.Plan)
	local target = math.max(run, Laps.MIN_RUN)
	local low, high = 0, Laps.SPEED_MAX
	for _ = 1, 40 do
		local mid = (low + high) / 2
		if Laps.virtual(relaunchPlan(mid, behavior, gravity)) < target then
			low = mid
		else
			high = mid
		end
	end
	local speed = (low + high) / 2
	local pitch = math.rad(Laps.PITCH_DEG)
	return speed * math.cos(pitch), speed * math.sin(pitch), relaunchPlan(speed, behavior, gravity)
end

-- Cette méthode permet d'estimer la durée d'un tour (premier contact, rebonds, glissade freinée, plus REST_TIME pour le
-- dernier) lorsque l'on vérifie que le vol reste court ; `last` : le mannequin s'arrête dans ce tour.
function Laps.duration(plan: FlightArc.Plan, last: boolean): number
	if not last then
		-- Tour complet : jusqu'au portail, à la vitesse de croisière (montée comprise dans le temps de contact)
		return plan.contactTime * math.min(Laps.LENGTH / math.max(plan.range, 1), 1)
	end
	return plan.contactTime + plan.bounceTime + plan.landingSpeed / GameConfig.GROUND_BRAKE + GameConfig.REST_TIME
end

return Laps
