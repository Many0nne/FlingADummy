-- Trajectoire du vol (#113, logique pure, testée) : hauteur plafonnée et glissade bornée. Le mannequin part comme
-- avant (vitesse de la puissance et de la jauge, LAUNCH_PITCH_DEG) ; si son sommet naturel dépasse le plafond
-- (APEX_HEIGHT), sa montée est freinée pour s'arrêter au plafond, il y file à plat puis retombe pour toucher le sol là
-- où l'aurait posé l'arc naturel : la puissance en trop part en distance, pas en hauteur, et la caméra reste près de la
-- piste. Après le premier choc (sol ou obstacle), frein fort au sol (GROUND_BRAKE) et vitesse latérale amortie : la
-- glissade ne dépend que de la vitesse. Le plafond tient jusqu'à ce qu'un piège projette le mannequin (son rebond peut
-- le passer, c'est voulu). Lu par Server.LaunchService (une frame à la fois) et tools/progression.luau.
-- Comportements des mannequins à lancer (#130) : chacun gagne une part fixe de la portée naturelle (`Behavior`), à
-- puissance et jauge égales, sans passer le plafond : le réacteur pousse vers l'avant (croisière plus longue), le
-- planeur redescend du plafond à vitesse lente, le caoutchouc rebondit plusieurs fois sans frein au sol. Le plan
-- calcule la poussée, la vitesse de descente et la vitesse des rebonds qui donnent cette part à toute puissance.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FlightArc = {}

FlightArc.HOLD_GAIN = 4 -- rappel vers le plafond pendant la croisière (1/s)
FlightArc.HOLD_MAX = 15 -- vitesse verticale de rappel au plus (studs/s)
FlightArc.IMPACT_DV = 60 -- choc du torse en une frame (studs/s) qui compte comme premier contact
FlightArc.GROUND_HEIGHT = 4 -- torse plus bas que ça (studs au-dessus de la piste) : premier contact au sol
FlightArc.CRUISE_MARGIN = 10 -- une montée qui retombe plus bas que le plafond moins ça (studs) ne croise pas
FlightArc.TRAP_COAST = 0.5 -- après un piège, l'élan n'est pas freiné pendant ce temps (s) : sa poussée se voit
FlightArc.GLIDE_GAIN = 10 -- rappel vers la vitesse de descente du planeur (1/s)
FlightArc.TORSO_REST = 1 -- hauteur du torse posé sur la piste (studs) : vitesse de chute au premier rebond
FlightArc.BOUNCE_RESTITUTION = 0.6 -- part de la vitesse de chute rendue vers le haut à chaque rebond
FlightArc.BOUNCE_MIN_FALL = 20 -- chute (studs/s) arrêtée net en une frame qui compte comme un rebond au sol
FlightArc.BOUNCE_DETECT = 0.75 -- un rebond prévu est reconnu dès 75 % de BOUNCE_MIN_FALL (sol un peu plus haut, frames)
FlightArc.BOUNCE_STOP = -2 -- vitesse verticale (studs/s) au-dessus de laquelle la chute est arrêtée

-- "Rise" : montée freinée vers le plafond ; "Cruise" : à plat au plafond ; "Free" : arc naturel ou chute après la
-- croisière ; "Landed" : après le premier choc, frein au sol et amortissement latéral
export type Phase = "Rise" | "Cruise" | "Free" | "Landed"

-- Comportement d'un mannequin à lancer (Shared.ThrowDummies) : part de la portée naturelle gagnée par chaque effet
export type Behavior = {
	glide: number, -- planeur : part gagnée par la descente lente depuis le sommet (0 : aucune)
	thrust: number, -- réacteur : part gagnée par la poussée vers l'avant
	thrustTime: number, -- durée de la poussée depuis le lâcher (s)
	bounce: number, -- caoutchouc : part gagnée par les rebonds après le premier contact
}

export type Plan = {
	capped: boolean, -- le sommet naturel dépasse le plafond
	ceiling: number, -- plafond (studs au-dessus de la piste)
	apex: number, -- sommet visé : plafond, ou sommet naturel en dessous
	airTime: number, -- durée de l'arc naturel jusqu'au premier contact (s)
	natural: number, -- portée de l'arc naturel sans comportement (studs) : la référence des parts gagnées
	range: number, -- distance au premier contact au sol, depuis le départ, le long de la piste (studs)
	drop: number?, -- vol plafonné : distance depuis le départ où la croisière finit et la chute commence
	boost: number, -- réacteur : poussée vers l'avant (studs/s²) pendant `boostTime` (0 : aucune)
	boostTime: number,
	sink: number?, -- planeur : vitesse de descente tenue (studs/s)
	bounceSpeed: number?, -- caoutchouc : élan vers l'avant pendant les rebonds (studs/s)
	bounceUps: { number }, -- vitesses de départ vers le haut des rebonds prévus, dans l'ordre (studs/s)
	bounceTime: number, -- durée des rebonds prévus (s)
	reach: number, -- distance où la glissade commence (premier contact, plus les rebonds)
	landingSpeed: number, -- élan vers l'avant quand la glissade commence (studs/s)
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
	bouncing: boolean?, -- rebond du caoutchouc en cours (FlightArc.bounceTime) : pas de frein sur l'élan
	dt: number,
	gravity: number,
}

local NONE: Behavior = { glide = 0, thrust = 0, thrustTime = 0, bounce = 0 }

-- Cette méthode permet de donner la vitesse de descente tenue qui fait durer `duration` s la descente de `height`
-- studs (chute libre jusqu'à cette vitesse, puis vitesse constante) lorsque le plan d'un planeur se calcule.
local function sinkFor(height: number, duration: number, gravity: number): number
	return gravity * (duration - math.sqrt(math.max(duration * duration - 2 * height / gravity, 0)))
end

-- Cette méthode permet de donner les vitesses de départ des rebonds (BOUNCE_RESTITUTION de chaque chute de plus de
-- BOUNCE_MIN_FALL) lorsque le plan d'un mannequin qui touche le sol en tombant à `fall` studs/s se calcule.
local function bounceSpeeds(fall: number): { number }
	local ups = {}
	while fall > FlightArc.BOUNCE_MIN_FALL do
		fall *= FlightArc.BOUNCE_RESTITUTION
		table.insert(ups, fall)
	end
	return ups
end

-- Cette méthode permet de donner le plan d'un vol (sommet, distance au premier contact, fin de la croisière, réglages
-- du comportement) lorsqu'il part à `forwardSpeed` le long de la piste et `upSpeed` vers le haut, depuis `height`
-- studs, sous `gravity`, avec le comportement `behavior` du mannequin lancé (aucun par défaut).
function FlightArc.plan(
	forwardSpeed: number,
	upSpeed: number,
	height: number,
	gravity: number,
	behavior: Behavior?,
	ceiling: number?
): Plan
	local top = ceiling or GameConfig.APEX_HEIGHT -- `ceiling` : autre plafond (tests)
	local b = behavior or NONE
	local vy = upSpeed
	local apex = height + math.max(vy, 0) ^ 2 / (2 * gravity)
	-- Contact quand le torse descend sous GROUND_HEIGHT
	local drop0 = math.max(height - FlightArc.GROUND_HEIGHT, 0)
	local airTime = (vy + math.sqrt(vy * vy + 2 * gravity * drop0)) / gravity
	local natural = forwardSpeed * airTime
	local capped = apex > top and height < top
	local peak = if capped then top else apex
	local fallHeight = math.max(peak - FlightArc.GROUND_HEIGHT, 0)
	local fallTime = math.sqrt(2 * fallHeight / gravity)

	-- Réacteur : poussée qui ajoute `thrust` × la portée naturelle au moment où l'arc naturel toucherait le sol
	local boost, boostTime = 0, 0
	if b.thrust > 0 and b.thrustTime > 0 and airTime > 0 then
		boostTime = math.min(b.thrustTime, airTime)
		boost = b.thrust * natural / ((airTime - boostTime / 2) * boostTime)
	end
	local speedAfter = forwardSpeed + boost * boostTime
	-- Cette méthode permet de donner la distance parcourue le long de la piste `t` s après le lâcher (poussée comprise)
	-- lorsque le plan place la fin de la croisière et le contact.
	local function along(t: number): number
		local pushed = if t < boostTime then t * t / 2 else boostTime * (t - boostTime / 2)
		return forwardSpeed * t + boost * pushed
	end

	-- Planeur : descente depuis le sommet allongée de `glide` × la durée de l'arc naturel
	local descent = fallTime
	local sink: number? = nil
	if b.glide > 0 and fallHeight > 0 then
		descent = fallTime + b.glide * airTime
		sink = sinkFor(fallHeight, descent, gravity)
	end

	local range, drop
	if capped then
		-- Montée freinée régulièrement de `vy` à 0 sur (top - height), croisière, puis descente depuis le plafond
		local riseTime = 2 * (top - height) / vy
		local dropTime = math.max(airTime - fallTime, riseTime)
		drop = along(dropTime)
		range = along(dropTime + descent)
	else
		range = along(airTime - fallTime + descent)
	end

	-- Caoutchouc : rebonds à élan constant, réglé pour ajouter `bounce` × la portée naturelle à l'arrêt (rebonds puis
	-- glissade plus courte, sur sol plat) : v × durée + v² / (2 × GROUND_BRAKE) = part + glissade sans rebond
	local bounceSpeed: number?, bounceUps, bounceTime = nil, {}, 0
	if b.bounce > 0 then
		local fall = math.sqrt(2 * gravity * math.max(peak - FlightArc.TORSO_REST, 0))
		bounceUps = bounceSpeeds(if sink then math.min(fall, sink) else fall)
		for _, up in bounceUps do
			bounceTime += 2 * up / gravity
		end
		if bounceTime > 0 then
			local brake = GameConfig.GROUND_BRAKE
			local wanted = b.bounce * natural + FlightArc.slide(speedAfter)
			local speed = brake * (math.sqrt(bounceTime * bounceTime + 2 * wanted / brake) - bounceTime)
			bounceSpeed = math.min(speed, speedAfter)
		end
	end

	return {
		capped = capped,
		ceiling = top,
		apex = peak,
		airTime = airTime,
		natural = natural,
		range = range,
		drop = drop,
		boost = boost,
		boostTime = boostTime,
		sink = sink,
		bounceSpeed = bounceSpeed,
		bounceUps = bounceUps,
		bounceTime = bounceTime,
		reach = range + (bounceSpeed or 0) * bounceTime,
		landingSpeed = bounceSpeed or speedAfter,
	}
end

-- Cette méthode permet de donner la phase de départ d'un vol lorsqu'il part : montée freinée s'il est plafonné, arc
-- naturel sinon.
function FlightArc.startPhase(plan: Plan): Phase
	return if plan.capped then "Rise" else "Free"
end

-- Cette méthode permet de donner l'accélération propre du mannequin (portance du planeur, sauf juste après un piège :
-- `coasting` ; poussée du réacteur `elapsed` s après le lâcher) lorsque le serveur avance le vol d'une frame.
function FlightArc.accel(
	plan: Plan,
	velocity: Vector3,
	forward: Vector3,
	elapsed: number,
	gravity: number,
	coasting: boolean?
): Vector3
	local accel = Vector3.zero
	local sink = plan.sink
	-- Pas de portance pendant la poussée d'un piège (presse qui écrase, trampoline) : son effet se voit
	if sink and velocity.Y < -sink and not coasting then
		accel += Vector3.new(0, gravity + FlightArc.GLIDE_GAIN * (-sink - velocity.Y), 0)
	end
	if plan.boost > 0 and elapsed < plan.boostTime then
		local flat = Vector3.new(forward.X, 0, forward.Z)
		if flat.Magnitude > 1e-3 then
			accel += flat.Unit * plan.boost
		end
	end
	return accel
end

-- Cette méthode permet de donner la vitesse après le rebond `done + 1` du plan (chute `fall` au plus fort, arrêtée cette
-- frame au sol, torse à `height` : `before` → `after`) lorsque le serveur avance un mannequin rebondissant ; nil sinon.
function FlightArc.bounce(
	plan: Plan,
	before: Vector3,
	after: Vector3,
	forward: Vector3,
	fall: number?,
	done: number?,
	height: number?
): Vector3?
	local speed = plan.bounceSpeed
	local up = plan.bounceUps[(done or 0) + 1]
	local flat = Vector3.new(forward.X, 0, forward.Z)
	-- Chute la plus forte depuis le dernier rebond : les membres touchent souvent avant le torse, qui ralentit sur
	-- plusieurs frames
	local falling = math.max(fall or 0, -before.Y)
	-- Au sol seulement (`height`) : ni le dessus d'un obstacle haut, ni la croisière au plafond
	local raised = height ~= nil and height >= GameConfig.BRAKE_HEIGHT
	if
		not speed
		or not up
		or raised
		or falling <= FlightArc.BOUNCE_MIN_FALL * FlightArc.BOUNCE_DETECT
		or before.Y >= FlightArc.BOUNCE_STOP
		or after.Y < FlightArc.BOUNCE_STOP
		or flat.Magnitude < 1e-3
	then
		return nil
	end
	flat = flat.Unit
	local horizontal = Vector3.new(after.X, 0, after.Z)
	local ahead = horizontal:Dot(flat)
	local lateral = horizontal - flat * ahead
	-- Élan et hauteur réglés par le plan à chaque rebond, même après un obstacle qui l'a ralenti ou un contact amorti
	-- par les membres : la distance ne dépend pas des caisses touchées entre deux rebonds. Jamais plus haut que la
	-- chute (petite chute sur une caisse basse), et pas de poussée vers l'avant contre une paroi qui l'a renvoyé
	local push = if ahead < 0 then ahead else speed
	return flat * push + lateral + Vector3.new(0, math.min(up, falling), 0)
end

-- Cette méthode permet de donner la durée en l'air d'un rebond qui repart à `velocity` (plus une marge de 3 frames
-- pour le contact suivant) lorsque le serveur décide jusqu'à quand l'élan n'est pas freiné.
function FlightArc.bounceTime(velocity: Vector3, gravity: number): number
	return 2 * math.max(velocity.Y, 0) / gravity + 0.05
end

-- Cette méthode permet de donner la vitesse après le frein au sol (élan le long de la piste réduit de GROUND_BRAKE ×
-- `dt` sous BRAKE_HEIGHT, vitesse latérale amortie) après le premier contact ; rien juste après un piège (`coasting`),
-- pas de frein sur l'élan pendant les rebonds (`bouncing`).
function FlightArc.brake(
	velocity: Vector3,
	forward: Vector3,
	height: number,
	dt: number,
	coasting: boolean?,
	bouncing: boolean?
): Vector3
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local ahead = flat:Dot(forward)
	if coasting then
		return velocity
	end
	local lateral = (flat - forward * ahead) * math.exp(-GameConfig.LATERAL_DAMP * dt)
	if height < GameConfig.BRAKE_HEIGHT and not bouncing then
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
		local bouncing = state.bouncing == true
		change += FlightArc.brake(velocity, state.forward, state.height, state.dt, state.coasting, bouncing) - velocity
	end
	return phase, change
end

return FlightArc
