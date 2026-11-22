-- Départ du vol vu par le lanceur (#117, logique pure, testée). Le mannequin est simulé par le serveur : chez le client,
-- un assemblage qui vient d'apparaître reste figé à sa première position le temps que le tampon d'interpolation du
-- moteur se remplisse (200 à 290 ms mesurées en Studio), puis il est affiché en retard. Le départ du vol étant décidé par
-- le plan (Shared.FlightArc : arc, montée freinée, croisière, poussée, sans choc avant le premier contact), le client
-- rejoue ce plan et affiche le mannequin en avance sur la copie répliquée : il quitte la main sans s'arrêter, puis
-- son avance se résorbe en douceur jusqu'à rejoindre la copie du serveur (Client.LaunchGhost). L'avance est un écart
-- de temps sur la trajectoire du plan, pas un lissage de position : distance, chocs et résultat restent ceux du
-- serveur. Trajectoire : gravité, comportement et contrôle FlightArc à chaque pas, comme Server.LaunchService, sans
-- obstacle, jusqu'au premier contact. Le temps de la copie répliquée se retrouve d'après sa distance le long de la
-- piste. Elle reprend la main quand l'avance est résorbée ou n'existe plus (le moteur la fait défiler ≈ 4 % plus vite
-- pour réduire son retard), et, après une résorption forcée de BLEND_TIME, quand elle quitte le plan (choc, piège :
-- la position fait foi, la vitesse vue par le client n'est pas celle de l'instant affiché), au premier contact ou
-- passé TIMEOUT.
--
-- Départ anticipé (#144) : le lanceur n'attend plus la réponse du serveur (un aller-retour, ≈ 350 ms à 150 ms de
-- latence simulée) pour voir partir le mannequin. Au lâcher, l'affichage part sur le plan calculé par le client
-- (Shared.ThrowStart), la copie répliquée étant tenue pour figée au départ (`ahead`) ; à l'arrivée du départ du serveur,
-- le temps affiché se recale sur son plan (`rebase`, même distance le long de la piste, l'écart restant se résorbe en
-- RECALE_TIME). L'avance à résorber grandit de cet aller-retour : la vitesse d'affichage ne descend pas sous
-- MIN_RATE, et une latence au-delà de GameConfig.RELEASE_LEAD_MAX est un court maintien à la main (`hold`).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FlightArc = require(Shared:WaitForChild("FlightArc"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FlightGhost = {}

FlightGhost.DT = 1 / 60 -- pas de la trajectoire simulée (celui du serveur)
FlightGhost.HORIZON = 3 -- durée simulée au plus (s) : l'avance est résorbée bien avant
FlightGhost.GAIN = 3 -- l'avance (s) ralentit l'affichage de GAIN × avance (1/s) : main rendue en 0,9-1,2 s (Studio, #117)
FlightGhost.MIN_RATE = 0.5 -- vitesse d'affichage au plus lent (#144 : l'avance d'un aller-retour se résorbe sans quasi-arrêt)
FlightGhost.MAX_LEAD = 0.7 -- avance (s) où le plancher MIN_RATE s'annule (copie répliquée qui n'arrive pas) …
FlightGhost.FLOOR_FADE = 0.2 -- … progressivement sur cet écart (s) : l'avance reste bornée
FlightGhost.MAX_RATE = 1.5 -- vitesse de rattrapage au plus, quand l'affichage est en retard sur la copie
FlightGhost.MOVED = 0.5 -- la copie répliquée a quitté sa première position (studs) : elle est diffusée
FlightGhost.DONE = 0.5 -- écart (studs) sous lequel l'affichage rend la main à la copie répliquée
FlightGhost.LEAD_DONE = 0.02 -- avance restante (s) résorbée en BLEND_TIME : pas de longue fin exponentielle
FlightGhost.DEVIATION = 8 -- écart de la copie répliquée avec le plan (studs) : choc, piège
FlightGhost.BLEND_TIME = 0.15 -- résorption forcée de l'écart restant (choc, fin du plan, s)
FlightGhost.TIMEOUT = 3 -- au-delà (s depuis le départ affiché), l'affichage rend la main
FlightGhost.TRANSITION = 0.15 -- passage de la main au vol (point de départ, orientation, échelle du décoratif, s)
FlightGhost.RECALE_TIME = 0.35 -- résorption de l'écart entre le départ prévu par le client et celui du serveur (s)

-- Trajectoire du plan, échantillonnée tous les `dt` depuis le lâcher (temps 0 au point de départ)
export type Path = {
	origin: Vector3,
	flat: Vector3, -- direction de la piste, à plat, unitaire
	dt: number,
	positions: { Vector3 },
	velocities: { Vector3 },
	along: { number }, -- distance le long de la piste depuis le départ (croissante)
}

-- Cette méthode permet de donner la trajectoire prévue d'un vol (mannequin lancé `behavior`) lorsqu'il part de `origin`
-- à `velocity`, jusqu'au premier contact ou `horizon` s.
function FlightGhost.path(
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	behavior: FlightArc.Behavior?,
	horizon: number?
): Path
	local dt = FlightGhost.DT
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local flat = if horizontal.Magnitude > 1e-3 then horizontal.Unit else Vector3.zAxis
	local forward = if velocity.Magnitude > 1e-3 then velocity.Unit else flat
	local plan = FlightArc.plan(horizontal.Magnitude, velocity.Y, origin.Y, gravity, behavior)
	local phase = FlightArc.startPhase(plan)
	local path: Path = {
		origin = origin,
		flat = flat,
		dt = dt,
		positions = { origin },
		velocities = { velocity },
		along = { 0 },
	}
	local position, v = origin, velocity
	local steps = math.floor((horizon or FlightGhost.HORIZON) / dt + 0.5)
	for step = 1, steps do
		local t = step * dt
		-- Pas de physique (gravité), puis contrôle du vol au Heartbeat du serveur
		v -= Vector3.new(0, gravity * dt, 0)
		position += v * dt
		local armed = t > GameConfig.IMPACT_GRACE_TIME
		local change = FlightArc.accel(plan, v, forward, t, gravity, false, dt) * dt
		local control
		phase, control = FlightArc.step(plan, {
			phase = phase,
			along = (position - origin):Dot(flat),
			height = position.Y,
			velocity = v + change,
			forward = flat,
			armed = armed,
			impact = false,
			trapped = false,
			coasting = false,
			bouncing = false,
			dt = dt,
			gravity = gravity,
		})
		if phase == "Landed" then
			break -- premier contact : la suite dépend du sol et des obstacles, le plan ne la prévoit pas
		end
		v += change + control
		local along = math.max((position - origin):Dot(flat), path.along[#path.along])
		table.insert(path.positions, position)
		table.insert(path.velocities, v)
		table.insert(path.along, along)
	end
	return path
end

-- Cette méthode permet de donner la durée prévue (s) d'une trajectoire lorsque l'on borne le temps affiché.
function FlightGhost.duration(path: Path): number
	return (#path.positions - 1) * path.dt
end

-- Cette méthode permet de donner la position et la vitesse prévues `time` s après le lâcher (interpolées entre deux
-- pas, bornées à la trajectoire) lorsque l'on place le mannequin affiché.
function FlightGhost.sample(path: Path, time: number): (Vector3, Vector3)
	local count = #path.positions
	local x = math.clamp(time / path.dt, 0, count - 1)
	local index = math.min(math.floor(x), count - 2)
	if index < 0 then
		return path.positions[1], path.velocities[1]
	end
	local k = x - index
	local a, b = index + 1, index + 2
	return path.positions[a]:Lerp(path.positions[b], k), path.velocities[a]:Lerp(path.velocities[b], k)
end

-- Cette méthode permet de retrouver le temps du vol d'une position (vrai en second : au-delà de la trajectoire)
-- lorsque l'on situe la copie répliquée sur la trajectoire.
function FlightGhost.timeAt(path: Path, position: Vector3): (number, boolean)
	local along = (position - path.origin):Dot(path.flat)
	local list = path.along
	local count = #list
	if along <= list[1] then
		return 0, false
	end
	if along >= list[count] then
		return (count - 1) * path.dt, along > list[count]
	end
	-- Recherche dichotomique du pas qui encadre la distance
	local low, high = 1, count
	while high - low > 1 do
		local mid = (low + high) // 2
		if list[mid] <= along then
			low = mid
		else
			high = mid
		end
	end
	local span = list[high] - list[low]
	local k = if span > 1e-6 then (along - list[low]) / span else 0
	return (low - 1 + k) * path.dt, false
end

-- Cette méthode permet de donner la vitesse d'avancée du temps affiché (1 : temps réel) lorsque l'affichage a `lead`
-- s d'avance sur la copie répliquée : il ralentit à mesure que l'avance grandit et rattrape un retard.
function FlightGhost.rate(lead: number): number
	local floor = FlightGhost.MIN_RATE * math.clamp((FlightGhost.MAX_LEAD - lead) / FlightGhost.FLOOR_FADE, 0, 1)
	return math.clamp(1 - FlightGhost.GAIN * lead, floor, FlightGhost.MAX_RATE)
end

-- Cette méthode permet de donner le maintien à la main (s) avant le départ affiché lorsque la latence aller-retour
-- `ping` (s) dépasse l'avance prise au plus (GameConfig.RELEASE_LEAD_MAX).
function FlightGhost.hold(ping: number): number
	return math.max(0, ping - GameConfig.RELEASE_LEAD_MAX)
end

-- Cette méthode permet de donner le décalage à ajouter à la copie répliquée (située à `replicated` s sur la
-- trajectoire) pour l'afficher à `shown` s lorsque le mannequin du lanceur est en avance.
function FlightGhost.offset(path: Path, shown: number, replicated: number): Vector3
	local a = FlightGhost.sample(path, shown)
	local b = FlightGhost.sample(path, replicated)
	return a - b
end

-- Cette méthode permet de savoir si la copie répliquée (à `position`, temps `replicated`) est à plus de DEVIATION du
-- plan lorsque l'on décide de rendre la main.
function FlightGhost.deviates(path: Path, replicated: number, position: Vector3): boolean
	local expected = FlightGhost.sample(path, replicated)
	return (position - expected).Magnitude > FlightGhost.DEVIATION
end

-- Suivi de l'affichage anticipé d'un vol (un par lancer du joueur local)
export type State = {
	shown: number, -- temps du vol affiché (s après le lâcher)
	rate: number, -- vitesse d'avancée du temps affiché à la dernière image (FlightGhost.rate)
	elapsed: number, -- temps depuis l'apparition de la copie répliquée (s)
	start: Vector3?, -- première position de la copie répliquée
	moved: boolean, -- la copie répliquée a quitté sa première position
	fading: number?, -- résorption forcée en cours : temps restant (s)
	fadeFrom: Vector3, -- écart au début de la résorption forcée
	done: boolean, -- l'affichage a rendu la main à la copie répliquée
	hold: number, -- maintien à la main avant le départ affiché (s, #144)
	correction: Vector3, -- écart ajouté à l'affichage, qui se résorbe (point de départ, recalage sur le serveur)
	correctionTime: number, -- durée de sa résorption (s)
	correctionLeft: number, -- temps restant (s)
}

-- Cette méthode permet de démarrer le suivi de l'affichage anticipé lorsque la copie répliquée apparaît, ou dès le
-- lâcher (#144) : `hold` s de maintien à la main, `start` écart du décoratif lâché au point de départ prévu.
function FlightGhost.new(hold: number?, start: Vector3?): State
	return {
		shown = 0,
		rate = 1,
		elapsed = 0,
		start = nil,
		moved = false,
		fading = nil,
		fadeFrom = Vector3.zero,
		done = false,
		hold = hold or 0,
		correction = start or Vector3.zero,
		correctionTime = FlightGhost.TRANSITION,
		correctionLeft = if start then FlightGhost.TRANSITION else 0,
	}
end

-- Cette méthode permet de donner le temps (s) depuis le départ affiché (maintien à la main déduit) lorsque l'on dose
-- le passage de la main au vol.
function FlightGhost.flying(state: State): number
	return math.max(0, state.elapsed - state.hold)
end

-- Cette méthode permet de donner l'écart ajouté à l'affichage à cet instant (résorption sans à-coup, vitesse nulle au
-- début et à la fin) lorsque l'on place le mannequin affiché.
function FlightGhost.correction(state: State): Vector3
	if state.correctionLeft <= 0 then
		return Vector3.zero
	end
	local k = 1 - state.correctionLeft / state.correctionTime
	return state.correction * (1 - k * k * (3 - 2 * k))
end

-- Cette méthode permet d'avancer la résorption de l'écart ajouté de `dt` s lorsque l'affichage avance d'une image.
local function settle(state: State, dt: number)
	if state.correctionLeft > 0 then
		state.correctionLeft = math.max(0, state.correctionLeft - dt)
	end
end

-- Cette méthode permet d'avancer d'une image de `dt` s l'affichage anticipé avant que la copie répliquée ne prenne le
-- relais (tenue pour figée au départ) et de donner la position du torse affiché lorsque le lanceur vient de lâcher.
function FlightGhost.ahead(path: Path, state: State, dt: number): Vector3
	state.elapsed += dt
	if state.elapsed > state.hold then
		state.rate = FlightGhost.rate(state.shown + dt)
		state.shown = math.min(state.shown + state.rate * dt, FlightGhost.duration(path))
		settle(state, dt)
	end
	return (FlightGhost.sample(path, state.shown)) + FlightGhost.correction(state)
end

-- Cette méthode permet de passer l'affichage du plan prévu par le client (`from`) à celui du serveur (`to`) sans saut
-- (même distance le long de la piste, écart restant résorbé en RECALE_TIME) lorsque le départ du serveur arrive.
function FlightGhost.rebase(state: State, from: Path, to: Path)
	local position = FlightGhost.sample(from, state.shown) + FlightGhost.correction(state)
	local time = FlightGhost.timeAt(to, position)
	state.shown = time
	state.correction = position - FlightGhost.sample(to, time)
	state.correctionTime = math.max(FlightGhost.RECALE_TIME, state.correctionLeft)
	state.correctionLeft = state.correctionTime
end

-- Cette méthode permet de donner la vitesse du mannequin affiché (copie répliquée à `replicated`) lorsque la caméra
-- prolonge son mouvement : plan au temps affiché et à sa cadence, ou copie moins l'écart qui se résorbe.
function FlightGhost.velocity(path: Path, state: State, replicated: Vector3): Vector3
	if state.done then
		return replicated
	end
	if state.fading then
		return replicated - state.fadeFrom / FlightGhost.BLEND_TIME
	end
	local _, velocity = FlightGhost.sample(path, state.shown)
	return velocity * state.rate
end

-- Cette méthode permet d'avancer l'affichage anticipé d'une image de `dt` s (copie répliquée à `replicated`) et de
-- donner le décalage à lui ajouter lorsque le client dessine le vol ; zéro une fois la main rendue (`state.done`).
function FlightGhost.advance(path: Path, state: State, replicated: Vector3, dt: number): Vector3
	if state.done then
		return Vector3.zero
	end
	state.elapsed += dt
	settle(state, dt)
	local start = state.start or replicated
	state.start = start
	if not state.moved and (replicated - start).Magnitude > FlightGhost.MOVED then
		state.moved = true
	end
	local fading = state.fading
	if fading then
		fading -= dt
		if fading <= 0 then
			state.done = true
			return Vector3.zero
		end
		state.fading = fading
		return state.fadeFrom * (fading / FlightGhost.BLEND_TIME)
	end
	local replicatedTime, beyond = FlightGhost.timeAt(path, replicated)
	-- Avance qu'aurait l'affichage s'il avançait en temps réel cette image (sinon une image d'avance resterait)
	local lead = state.shown + dt - replicatedTime
	state.rate = FlightGhost.rate(lead)
	state.shown = math.min(state.shown + state.rate * dt, FlightGhost.duration(path))
	local offset = FlightGhost.offset(path, state.shown, replicatedTime) + FlightGhost.correction(state)
	if
		beyond
		or replicatedTime >= FlightGhost.duration(path)
		or FlightGhost.deviates(path, replicatedTime, replicated)
		or FlightGhost.flying(state) > FlightGhost.TIMEOUT
	then
		state.fading = FlightGhost.BLEND_TIME
		state.fadeFrom = offset
		return offset
	end
	if state.moved and offset.Magnitude < FlightGhost.DONE then
		state.done = true
		return Vector3.zero
	end
	-- Plus d'avance : la copie répliquée défile un peu plus vite que le temps réel le temps de réduire son retard
	-- (≈ 4 % mesurés), l'affichage resterait juste derrière elle ; l'écart se résorbe vers l'avant. Presque plus
	-- d'avance (LEAD_DONE) : le reste se résorbe de même, sans attendre la fin de la décroissance
	if state.moved and state.shown - replicatedTime < FlightGhost.LEAD_DONE then
		state.fading = FlightGhost.BLEND_TIME
		state.fadeFrom = offset
	end
	return offset
end

return FlightGhost
