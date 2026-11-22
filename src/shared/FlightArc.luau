-- Trajectoire du vol (#113, logique pure, testée) : hauteur plafonnée et glissade bornée. Le mannequin part comme
-- avant (vitesse de la puissance et de la jauge, LAUNCH_PITCH_DEG) ; si son sommet naturel dépasse le plafond
-- (APEX_HEIGHT), sa montée est freinée pour s'arrêter au plafond, il y file à plat puis retombe pour toucher le sol là
-- où l'aurait posé l'arc naturel : la puissance en trop part en distance, pas en hauteur, et la caméra reste près de la
-- piste. Après le premier choc (sol ou obstacle), frein fort au sol (GROUND_BRAKE) et vitesse latérale amortie : la
-- glissade ne dépend que de la vitesse. Le plafond tient jusqu'à ce qu'un piège projette le mannequin (son rebond peut
-- le passer, c'est voulu). Lu par Server.LaunchService (une frame à la fois) et tools/progression.luau.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FlightArc = {}

FlightArc.HOLD_GAIN = 4 -- rappel vers le plafond pendant la croisière (1/s)
FlightArc.HOLD_MAX = 15 -- vitesse verticale de rappel au plus (studs/s)
FlightArc.IMPACT_DV = 60 -- choc du torse en une frame (studs/s) qui compte comme premier contact
FlightArc.GROUND_HEIGHT = 4 -- torse plus bas que ça (studs au-dessus de la piste) : premier contact au sol
FlightArc.CRUISE_MARGIN = 10 -- une montée qui retombe plus bas que le plafond moins ça (studs) ne croise pas
FlightArc.TRAP_COAST = 0.5 -- après un piège, l'élan n'est pas freiné pendant ce temps (s) : sa poussée se voit

-- "Rise" : montée freinée vers le plafond ; "Cruise" : à plat au plafond ; "Free" : arc naturel ou chute après la
-- croisière ; "Landed" : après le premier choc, frein au sol et amortissement latéral
export type Phase = "Rise" | "Cruise" | "Free" | "Landed"

export type Plan = {
	capped: boolean, -- le sommet naturel dépasse le plafond
	ceiling: number, -- plafond (studs au-dessus de la piste)
	apex: number, -- sommet visé : plafond, ou sommet naturel en dessous
	range: number, -- distance au premier contact au sol, depuis le départ, le long de la piste (studs)
	drop: number?, -- vol plafonné : distance depuis le départ où la croisière finit et la chute commence
}

export type State = {
	phase: Phase,
	along: number, -- distance parcourue depuis le départ, le long de la piste (studs)
	height: number, -- hauteur du torse au-dessus de la piste (studs)
	velocity: Vector3, -- vitesse du torse
	forward: Vector3, -- direction de la piste, à plat, unitaire
	armed: boolean, -- passé le délai de grâce du lancer (IMPACT_GRACE_TIME)
	impact: boolean, -- le torse vient de subir un choc (plus de IMPACT_DV en une frame)
	trapped: boolean, -- un piège a projeté le mannequin : plus de plafond
	coasting: boolean, -- un piège vient d'agir (moins de TRAP_COAST s) : pas de frein sur l'élan
	dt: number,
	gravity: number,
}

-- Cette méthode permet de donner le plan d'un vol (sommet, distance au premier contact, fin de la croisière)
-- lorsqu'il part à `forwardSpeed` le long de la piste et `upSpeed` vers le haut, depuis `height` studs, sous `gravity`.
function FlightArc.plan(forwardSpeed: number, upSpeed: number, height: number, gravity: number, ceiling: number?): Plan
	local top = ceiling or GameConfig.APEX_HEIGHT -- `ceiling` : autre plafond (tests)
	local vy = upSpeed
	local apex = height + math.max(vy, 0) ^ 2 / (2 * gravity)
	-- Contact quand le torse descend sous GROUND_HEIGHT
	local drop0 = math.max(height - FlightArc.GROUND_HEIGHT, 0)
	local airTime = (vy + math.sqrt(vy * vy + 2 * gravity * drop0)) / gravity
	local range = forwardSpeed * airTime
	if apex <= top or height >= top then
		return { capped = false, ceiling = top, apex = apex, range = range }
	end
	-- Montée freinée régulièrement de `vy` à 0 sur (top - height), puis chute libre depuis le plafond
	local rise = forwardSpeed * 2 * (top - height) / vy
	local fall = forwardSpeed * math.sqrt(2 * (top - FlightArc.GROUND_HEIGHT) / gravity)
	local drop = math.max(range - fall, rise)
	return { capped = true, ceiling = top, apex = top, range = drop + fall, drop = drop }
end

-- Cette méthode permet de donner la phase de départ d'un vol lorsqu'il part : montée freinée s'il est plafonné, arc
-- naturel sinon.
function FlightArc.startPhase(plan: Plan): Phase
	return if plan.capped then "Rise" else "Free"
end

-- Cette méthode permet de donner la vitesse après le frein au sol (élan le long de la piste réduit de GROUND_BRAKE ×
-- `dt` sous BRAKE_HEIGHT, sauf `coasting`, vitesse latérale amortie partout) lorsque le mannequin a touché le sol.
function FlightArc.brake(velocity: Vector3, forward: Vector3, height: number, dt: number, coasting: boolean?): Vector3
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local ahead = flat:Dot(forward)
	local lateral = (flat - forward * ahead) * math.exp(-GameConfig.LATERAL_DAMP * dt)
	if height < GameConfig.BRAKE_HEIGHT and not coasting then
		local slowed = math.max(math.abs(ahead) - GameConfig.GROUND_BRAKE * dt, 0)
		ahead = if ahead < 0 then -slowed else slowed
	end
	return forward * ahead + lateral + Vector3.new(0, velocity.Y, 0)
end

-- Cette méthode permet de donner la glissade d'un mannequin qui touche le sol à `speed` studs/s le long de la piste
-- (frein seul, sans frottement ni obstacle) lorsque l'on estime la distance d'un lancer.
function FlightArc.slide(speed: number): number
	return speed * speed / (2 * GameConfig.GROUND_BRAKE)
end

-- Cette méthode permet de donner le freinage vertical (studs/s², en plus de la gravité) qui arrête une montée à
-- `vy` studs/s pile au plafond, `remaining` studs plus haut, lorsque le mannequin monte vers le plafond.
local function ceilingBrake(vy: number, remaining: number, gravity: number): number
	if vy <= 0 then
		return 0
	end
	return math.max(vy * vy / (2 * math.max(remaining, 0.5)) - gravity, 0)
end

-- Cette méthode permet d'avancer le contrôle du vol d'une frame (changement de phase, variation de vitesse à ajouter à
-- toutes les pièces) lorsque le serveur suit le mannequin ; `plan` vient de FlightArc.plan au départ.
function FlightArc.step(plan: Plan, state: State): (Phase, Vector3)
	local phase = state.phase
	local velocity = state.velocity
	if phase ~= "Landed" and state.armed and (state.height < FlightArc.GROUND_HEIGHT or state.impact) then
		phase = "Landed"
	end
	if (phase == "Rise" or phase == "Cruise") and plan.drop and state.along >= plan.drop then
		phase = "Free"
	end
	local remaining = plan.ceiling - state.height
	if phase == "Rise" and (velocity.Y <= 0 or remaining <= 0.5) then
		-- Montée stoppée loin du plafond (accroc, frame longue) : chute libre, pas de remontée sans cause visible
		phase = if remaining <= FlightArc.CRUISE_MARGIN then "Cruise" else "Free"
	end
	if phase == "Cruise" then
		local target = math.clamp(remaining * FlightArc.HOLD_GAIN, -FlightArc.HOLD_MAX, FlightArc.HOLD_MAX)
		return phase, Vector3.new(0, target - velocity.Y + state.gravity * state.dt, 0)
	end
	local change = Vector3.zero
	if not state.trapped then
		-- Plafond : sans effet sur un arc qui culmine plus bas (freinage nécessaire inférieur à la gravité)
		change = Vector3.new(0, -ceilingBrake(velocity.Y, remaining, state.gravity) * state.dt, 0)
	end
	if phase == "Landed" then
		change += FlightArc.brake(velocity, state.forward, state.height, state.dt, state.coasting) - velocity
	end
	return phase, change
end

return FlightArc
