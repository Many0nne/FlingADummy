-- Effets des comportements en vol (#138, logique pure, testée) : quand allumer la flamme du Rocket, les traînées du
-- Glider et le « boing » de chaque rebond du Rubber. Chaque client recalcule le plan du vol (Shared.FlightArc) d'après
-- les attributs posés par le serveur sur le mannequin (point de départ, vitesse, mannequin lancé) et suit la position
-- **affichée** du torse (copie locale du lanceur, Client.LaunchGhost, sinon copie répliquée) : les effets tombent sur
-- ce que le joueur voit, pas sur la simulation du serveur qui la devance de 100 à 300 ms.
-- - Poussée : tant que le torse affiché n'a pas passé la distance du plan où elle finit (bornée dans le temps : un
--   piège peut la dévier), jamais rallumée.
-- - Glisse : planeur qui descend (plus vite que GLIDE_FALL) au-dessus du sol, jusqu'au premier contact.
-- - Rebond : le serveur compte les rebonds réglés (attribut `Bounces`, il les décide) ; le client joue le k-ième au
--   moment où le torse affiché repart vers le haut près du sol (apparié au compteur dans MATCH s), ou passé MATCH s sans
--   remontée vue (repli).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FlightArc = require(Shared:WaitForChild("FlightArc"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FlightFx = {}

FlightFx.BOOST_SLACK = 0.6 -- la flamme s'éteint au plus tard ce temps (s) après la fin prévue de la poussée
FlightFx.GLIDE_FALL = 8 -- descente (studs/s) au-delà de laquelle le planeur glisse
FlightFx.GLIDE_STOP = 3 -- descente sous laquelle la glisse s'arrête (hystérésis)
FlightFx.GLIDE_FLOOR = GameConfig.BRAKE_HEIGHT -- pas de traînée sous cette hauteur du torse (studs)
FlightFx.REBOUND_FALL = 12 -- chute (studs/s) avant une remontée qui compte comme rebond affiché
FlightFx.REBOUND_UP = 5 -- vitesse vers le haut (studs/s) qui marque la remontée
FlightFx.REBOUND_HEIGHT = 10 -- rebond affiché seulement près du sol (torse sous cette hauteur, studs)
FlightFx.MATCH = 0.4 -- écart au plus (s) entre le rebond compté par le serveur et la remontée affichée
FlightFx.SMOOTH = 0.08 -- constante de temps du lissage de la vitesse verticale (glisse, s)

-- Repères du plan utiles aux effets
export type Cues = {
	boostTime: number, -- durée de la poussée (s, 0 : pas de réacteur)
	boostAlong: number, -- distance le long de la piste où la poussée finit (studs)
	glide: boolean, -- planeur
	bounces: number, -- rebonds réglés prévus (0 : pas de caoutchouc)
}

-- Cette méthode permet de donner les repères des effets d'un vol (fin de la poussée, planeur, rebonds) lorsque le
-- client voit partir un mannequin lancé de `origin` à `velocity` sous `gravity`, avec le comportement `behavior`.
function FlightFx.cues(origin: Vector3, velocity: Vector3, gravity: number, behavior: FlightArc.Behavior?): Cues
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local plan = FlightArc.plan(horizontal, velocity.Y, origin.Y, gravity, behavior)
	local t = plan.boostTime
	return {
		boostTime = t,
		-- Même intégration que FlightArc.plan : vitesse de départ plus poussée constante pendant `t`
		boostAlong = if plan.boost > 0 then horizontal * t + plan.boost * t * t / 2 else 0,
		glide = plan.sink ~= nil,
		bounces = #plan.bounceUps,
	}
end

-- Suivi des effets d'un mannequin affiché (un par vol et par client)
export type Tracker = {
	cues: Cues,
	origin: Vector3,
	flat: Vector3, -- direction de la piste, à plat, unitaire
	time: number, -- temps depuis le début du suivi (s)
	previous: Vector3?, -- position affichée du torse à l'image précédente
	vy: number, -- vitesse verticale lissée (glisse)
	fall: number, -- chute la plus forte depuis la dernière remontée (studs/s, rebonds)
	boosting: boolean,
	boostDone: boolean, -- poussée finie : jamais rallumée
	gliding: boolean,
	glided: boolean, -- la glisse a déjà commencé une fois (souffle joué)
	landed: boolean, -- premier contact affiché : plus de glisse
	played: number, -- rebonds joués
	reboundAt: number?, -- remontée affichée pas encore appariée à un rebond du serveur (temps)
	waitingSince: number?, -- rebond du serveur pas encore vu remonter (temps)
}

-- Ce que le client doit jouer à cette image
export type Frame = {
	boosting: boolean, -- flamme et fumée allumées
	gliding: boolean, -- traînées allumées
	glideStart: boolean, -- la glisse commence (souffle)
	bounce: number?, -- rebond à jouer maintenant (rang, à partir de 1)
}

-- Cette méthode permet de démarrer le suivi des effets d'un vol lorsque le client voit apparaître le mannequin lancé
-- (repères `cues`, départ `origin`, vitesse de départ `velocity`).
function FlightFx.tracker(cues: Cues, origin: Vector3, velocity: Vector3): Tracker
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	return {
		cues = cues,
		origin = origin,
		flat = if horizontal.Magnitude > 1e-3 then horizontal.Unit else Vector3.zAxis,
		time = 0,
		previous = nil,
		vy = 0,
		fall = 0,
		boosting = cues.boostAlong > 0,
		boostDone = cues.boostAlong <= 0,
		gliding = false,
		glided = false,
		landed = false,
		played = 0,
		reboundAt = nil,
		waitingSince = nil,
	}
end

-- Cette méthode permet de faire avancer le suivi d'une image de `dt` s (torse affiché à `position`, `counted` rebonds
-- comptés par le serveur) et de donner les effets à jouer lorsque le client dessine le vol.
function FlightFx.step(tracker: Tracker, position: Vector3, dt: number, counted: number): Frame
	local cues = tracker.cues
	tracker.time += dt
	local now = tracker.time
	local previous = tracker.previous
	tracker.previous = position
	local raw = if previous and dt > 0 then (position.Y - previous.Y) / dt else 0
	local k = if dt > 0 then 1 - math.exp(-dt / FlightFx.SMOOTH) else 0
	tracker.vy += (raw - tracker.vy) * k
	local height = position.Y
	local frame: Frame = { boosting = false, gliding = false, glideStart = false, bounce = nil }

	-- Poussée : jusqu'à la distance du plan, bornée dans le temps
	if not tracker.boostDone then
		local along = (position - tracker.origin):Dot(tracker.flat)
		if along >= cues.boostAlong or now >= cues.boostTime + FlightFx.BOOST_SLACK then
			tracker.boostDone = true
		end
	end
	tracker.boosting = not tracker.boostDone
	frame.boosting = tracker.boosting

	-- Premier contact affiché (après le départ, qui peut partir bas), ou planeur descendu au plancher des traînées
	-- (posé sur un obstacle) : la descente planée est finie, les sauts sur les obstacles qui suivent n'en sont pas
	local floored = tracker.glided and height <= FlightFx.GLIDE_FLOOR
	if (now > GameConfig.IMPACT_GRACE_TIME and height < FlightArc.GROUND_HEIGHT) or floored then
		tracker.landed = true
	end
	if cues.glide and not tracker.landed then
		if tracker.gliding then
			tracker.gliding = tracker.vy < -FlightFx.GLIDE_STOP and height > FlightFx.GLIDE_FLOOR
		else
			tracker.gliding = tracker.vy < -FlightFx.GLIDE_FALL and height > FlightFx.GLIDE_FLOOR
			if tracker.gliding and not tracker.glided then
				tracker.glided = true
				frame.glideStart = true
			end
		end
	else
		tracker.gliding = false
	end
	frame.gliding = tracker.gliding

	if cues.bounces > 0 then
		-- Remontée affichée près du sol après une vraie chute (vitesse brute : un rebond tient en une image)
		if raw < 0 then
			tracker.fall = math.max(tracker.fall, -raw)
		elseif raw > FlightFx.REBOUND_UP then
			if tracker.fall > FlightFx.REBOUND_FALL and height < FlightFx.REBOUND_HEIGHT then
				tracker.reboundAt = now
			end
			tracker.fall = 0
		end
		local pending = math.min(counted, cues.bounces) > tracker.played
		if pending then
			tracker.waitingSince = tracker.waitingSince or now
			local seen = tracker.reboundAt ~= nil and now - tracker.reboundAt <= FlightFx.MATCH
			if seen or now - tracker.waitingSince > FlightFx.MATCH then
				tracker.played += 1
				tracker.reboundAt = nil
				tracker.waitingSince = nil
				frame.bounce = tracker.played
			end
		end
	end
	return frame
end

-- Cette méthode permet de donner la hauteur du son du k-ième rebond (de plus en plus aigu : rebonds de plus en plus
-- petits) lorsque le client joue un « boing ».
function FlightFx.boingPitch(k: number): number
	return 1 + 0.15 * (math.max(k, 1) - 1)
end

-- Cette méthode permet de donner la taille de l'éclat du k-ième rebond (1 au premier, puis de plus en plus petit, 0,4
-- au moins) lorsque le client joue un « boing ».
function FlightFx.bounceScale(k: number): number
	return math.max(1 - 0.2 * (math.max(k, 1) - 1), 0.4)
end

-- Réglages des effets selon le mouvement réduit : particules moins nombreuses, pas d'anneau qui s'étend
export type Profile = { rate: number, burst: number, ring: boolean }

-- Cette méthode permet de donner les réglages des effets de vol (débit des émetteurs, nombre de particules des éclats,
-- anneau de poussière) lorsque le client les crée ; `reduced` : mouvement réduit demandé par le joueur.
function FlightFx.profile(reduced: boolean): Profile
	if reduced then
		return { rate = 0.4, burst = 0.4, ring = false }
	end
	return { rate = 1, burst = 1, ring = true }
end

return FlightFx
