-- Retard d'affichage des mannequins en vol (#84, logique pure, testée). Le mannequin est simulé par le serveur et
-- s'affiche chez chaque client en retard (tampon d'interpolation du moteur et latence : ≈ 0,25 à 0,4 s mesurées), alors
-- que le serveur décide qu'un piège agit à l'instant présent (Shared.Traps.active). Pour que la pièce du piège frappe
-- quand le mannequin affiché la touche, chaque client anime les pièges sur l'horloge du serveur décalée de ce retard
-- (Client.TrapMotion).
--
-- Mesure : le serveur envoie, SAMPLE_RATE fois par seconde, l'heure serveur et la position du torse de chaque vol
-- (remote FlightClock, Server.LaunchService). Le client retrouve l'heure serveur de la position qu'il affiche (point le
-- plus proche sur la trajectoire échantillonnée) : le retard est l'écart avec l'heure serveur présente. Lissé et borné
-- (0 à MAX), il varie au plus de MAX_RATE s par seconde : la pièce ralentit ou accélère un peu, sans saut. Sans
-- mannequin à suivre (hors vol, au repos), le dernier retard lissé est gardé. Exception : la toute première mesure de
-- la session est prise telle quelle (sinon les pièges du premier vol resteraient décalés pendant plus d'une seconde).
local DisplayLag = {}

DisplayLag.SAMPLE_RATE = 20 -- échantillons (heure serveur, position du torse) envoyés par seconde et par vol
DisplayLag.KEEP = 1.2 -- échantillons gardés (s) : plus que le retard au plus (MAX)
DisplayLag.MAX = 0.6 -- retard au plus (s)
DisplayLag.MATCH = 6 -- écart (studs) au-delà duquel la position affichée n'est pas sur la trajectoire échantillonnée
DisplayLag.MIN_SPAN = 0.3 -- pas plus court (studs) entre deux échantillons : mannequin presque arrêté, heure imprécise
-- Position affichée à moins de AHEAD studs du dernier échantillon : mannequin arrêté là, heure ambiguë (pas de mesure)
DisplayLag.AHEAD = 1
-- Projection admise au-delà des bouts d'un pas (part du pas) : plus loin, la position est sur un pas voisin trop court
-- (mannequin lent, pas ignoré), et le bout du pas donnerait une heure trop ancienne
DisplayLag.EDGE = 0.1
DisplayLag.SMOOTH = 0.5 -- constante de temps du lissage (s)
DisplayLag.MAX_RATE = 0.3 -- variation au plus du retard appliqué (s par seconde) : pièces à 70-130 % de leur vitesse

-- Trajectoire récente d'un mannequin, vue par le serveur : heures et positions croissantes dans le temps
export type Track = { times: { number }, positions: { Vector3 } }

-- Retard appliqué (`lag`) et dernier retard mesuré (`target`, s) ; `measured` : au moins une mesure reçue
export type Clock = { lag: number, target: number, measured: boolean }

-- Cette méthode permet de créer la trajectoire vide d'un mannequin lorsque son premier échantillon arrive.
function DisplayLag.track(): Track
	return { times = {}, positions = {} }
end

-- Cette méthode permet d'ajouter l'échantillon (`time`, `position`) à la trajectoire lorsqu'il arrive du serveur ;
-- un échantillon arrivé dans le désordre (remote non fiable) est ignoré, les plus vieux que KEEP sont oubliés.
function DisplayLag.push(track: Track, time: number, position: Vector3)
	local times = track.times
	local count = #times
	if count > 0 and time <= times[count] then
		return
	end
	table.insert(times, time)
	table.insert(track.positions, position)
	local drop = 0
	while drop < #times - 2 and times[drop + 1] < time - DisplayLag.KEEP do
		drop += 1
	end
	if drop > 0 then
		table.move(times, drop + 1, #times, 1)
		table.move(track.positions, drop + 1, #track.positions, 1)
		for i = #times, #times - drop + 1, -1 do
			times[i] = nil
			track.positions[i] = nil
		end
	end
end

-- Cette méthode permet de donner l'heure serveur où le mannequin était à `position` (sa position affichée) lorsque
-- l'on mesure le retard d'affichage ; nil si la position n'est en face d'aucun pas assez long de la trajectoire (à
-- MATCH studs près, EDGE près aux bouts) ou à moins de AHEAD studs du dernier échantillon. Le dernier pas se prolonge
-- d'un pas (échantillon suivant pas encore arrivé). Avec `now` (heure serveur présente), seules les heures de
-- `now` - MAX à `now` comptent.
function DisplayLag.shownAt(track: Track, position: Vector3, now: number?): number?
	local times, positions = track.times, track.positions
	local best, bestDistance = nil, DisplayLag.MATCH
	for i = 1, #times - 1 do
		local a, b = positions[i], positions[i + 1]
		local step = b - a
		local span = step.Magnitude
		if span >= DisplayLag.MIN_SPAN then
			local u = (position - a):Dot(step) / (span * span)
			local last = i == #times - 1
			if u >= -DisplayLag.EDGE and u <= (if last then 2 else 1 + DisplayLag.EDGE) then
				u = math.clamp(u, 0, if last then 2 else 1)
				local distance = (a + step * u - position).Magnitude
				local time = times[i] + (times[i + 1] - times[i]) * u
				local inWindow = not now or (time >= now - DisplayLag.MAX and time <= now)
				-- Le pas le plus proche ; à égalité, le plus récent (`<=`)
				if inWindow and distance <= bestDistance then
					best, bestDistance = time, distance
				end
			end
		end
	end
	-- Mannequin arrêté (ou presque) là où il est affiché : la fin de son dernier pas en mouvement colle à sa position
	-- et le retard mesuré grandirait sans fin (0,6 s mesurés en Studio après l'arrêt)
	local count = #positions
	if best and (positions[count] - position).Magnitude < DisplayLag.AHEAD then
		return nil
	end
	return best
end

-- Cette méthode permet de mesurer le retard d'affichage (s, borné de 0 à MAX) lorsque le client affiche le torse en
-- `position` à l'heure serveur `now` ; nil sans mesure possible (voir `shownAt`).
function DisplayLag.measure(track: Track, now: number, position: Vector3): number?
	local shown = DisplayLag.shownAt(track, position, now)
	if not shown then
		return nil
	end
	return math.clamp(now - shown, 0, DisplayLag.MAX)
end

-- Cette méthode permet de créer l'horloge décalée d'un client lorsqu'il démarre : retard nul tant qu'aucun vol n'a
-- été mesuré.
function DisplayLag.clock(): Clock
	return { lag = 0, target = 0, measured = false }
end

-- Cette méthode permet d'avancer le retard appliqué d'une image de `dt` s lorsque le client anime les pièges ;
-- `measured` = retard mesuré cette image (nil : le dernier est gardé). Rend le retard appliqué.
function DisplayLag.step(clock: Clock, measured: number?, dt: number): number
	if measured then
		clock.target = math.clamp(measured, 0, DisplayLag.MAX)
		if not clock.measured then
			-- Première mesure de la session : prise telle quelle
			clock.measured = true
			clock.lag = clock.target
			return clock.lag
		end
	end
	local move = (clock.target - clock.lag) * (1 - math.exp(-math.max(dt, 0) / DisplayLag.SMOOTH))
	local cap = DisplayLag.MAX_RATE * math.max(dt, 0)
	clock.lag = math.clamp(clock.lag + math.clamp(move, -cap, cap), 0, DisplayLag.MAX)
	return clock.lag
end

-- Cette méthode permet de donner l'attente (s, de 0 à MAX) avant de montrer un choc du serveur survenu à l'heure
-- serveur `at` lorsqu'il arrive à l'heure serveur `now` : le choc se voit quand le mannequin affiché y arrive.
function DisplayLag.wait(clock: Clock, at: number, now: number): number
	return math.clamp(at - DisplayLag.now(clock, now), 0, DisplayLag.MAX)
end

-- Cette méthode permet de donner l'heure à laquelle animer les pièges lorsque l'heure serveur est `now` : celle du
-- mannequin affiché.
function DisplayLag.now(clock: Clock, now: number): number
	return now - clock.lag
end

return DisplayLag
