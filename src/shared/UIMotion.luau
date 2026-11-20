-- Courbes et règles pures des animations d'interface (#34, relevées sur les références 01 / 02 / 09) : étapes
-- d'échelle des pops (fenêtres, popups, boutons, compteurs), flottement et pulsation de la flèche d'objectif, texte de
-- la pastille rouge, regroupement des « +N » qui volent vers un compteur. Joué par Client.UIKit.
local UIMotion = {}

export type Key = { time: number, scale: number }

-- Étapes d'échelle : temps cumulé (s) et échelle atteinte à ce temps, la première donne l'échelle de départ
UIMotion.WINDOW_OPEN = {
	{ time = 0, scale = 0.6 },
	{ time = 0.16, scale = 1.05 },
	{ time = 0.25, scale = 1 },
} :: { Key }
UIMotion.WINDOW_CLOSE = {
	{ time = 0, scale = 1 },
	{ time = 0.12, scale = 0.6 },
} :: { Key }
UIMotion.POPUP_IN = {
	{ time = 0, scale = 0.3 },
	{ time = 0.18, scale = 1.15 },
	{ time = 0.28, scale = 0.95 },
	{ time = 0.36, scale = 1 },
} :: { Key }
UIMotion.COUNTER_BUMP = {
	{ time = 0, scale = 1 },
	{ time = 0.07, scale = 1.3 },
	{ time = 0.3, scale = 1 },
} :: { Key }

UIMotion.HOVER_SCALE = 1.06 -- bouton survolé
UIMotion.PRESS_SCALE = 0.92 -- bouton enfoncé, revient à 1 (ou 1,06 s'il est survolé) au relâché
UIMotion.PRESS_TIME = 0.06 -- s pour s'enfoncer
UIMotion.RELEASE_TIME = 0.22 -- s pour revenir (rebond)

UIMotion.FLOAT_SPEED = 4 -- rad/s du flottement de la flèche d'objectif
UIMotion.PULSE_PERIOD = 0.9 -- s entre deux pulsations de la flèche
UIMotion.PULSE_AMPLITUDE = 0.15 -- la flèche grossit jusqu'à 1,15

UIMotion.BADGE_MAX = 99 -- au-delà, la pastille affiche « 99+ »

-- Cette méthode permet de donner la durée totale d'une suite d'étapes d'échelle lorsque l'on enchaîne une animation.
function UIMotion.duration(keys: { Key }): number
	return keys[#keys].time
end

-- Cette méthode permet de lire l'échelle d'une suite d'étapes au temps `t` (interpolation douce entre deux étapes,
-- bornée aux extrémités) lorsque l'on vérifie une courbe ou que l'on l'échantillonne.
function UIMotion.sample(keys: { Key }, t: number): number
	if t <= keys[1].time then
		return keys[1].scale
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b.time then
			local k = (t - a.time) / (b.time - a.time)
			k = 1 - (1 - k) * (1 - k) -- Quad Out, comme les tweens qui la jouent
			return a.scale + (b.scale - a.scale) * k
		end
	end
	return keys[#keys].scale
end

-- Cette méthode permet de donner le décalage de flottement (-1 à 1) de la flèche d'objectif au temps `t` lorsque
-- l'image se prépare ; 0 si le mouvement réduit est demandé.
function UIMotion.float(t: number, reduced: boolean?): number
	if reduced then
		return 0
	end
	return math.sin(t * UIMotion.FLOAT_SPEED)
end

-- Cette méthode permet de donner l'échelle de pulsation (1 à 1 + PULSE_AMPLITUDE) de la flèche d'objectif au temps
-- `t` lorsque l'image se prépare ; 1 si le mouvement réduit est demandé.
function UIMotion.pulse(t: number, reduced: boolean?): number
	if reduced then
		return 1
	end
	local phase = (t % UIMotion.PULSE_PERIOD) / UIMotion.PULSE_PERIOD
	return 1 + UIMotion.PULSE_AMPLITUDE * (0.5 - 0.5 * math.cos(phase * 2 * math.pi))
end

-- Cette méthode permet de donner le texte de la pastille rouge (nombre, « 99+ », texte libre comme « ! ») lorsque
-- l'interface la met à jour ; nil pour la masquer (rien, 0 ou négatif).
function UIMotion.badgeText(value: (number | string)?): string?
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		return if value == "" then nil else value
	end
	local count = math.floor(value :: number)
	if count <= 0 then
		return nil
	elseif count > UIMotion.BADGE_MAX then
		return UIMotion.BADGE_MAX .. "+"
	end
	return tostring(count)
end

-- Regroupement des « +N » qui volent vers un compteur : un gain arrivé peu après le précédent rejoint son étiquette,
-- et jamais plus de `maxLabels` étiquettes en vol à la fois
export type Flight = { id: number, total: number, startedAt: number }
export type Batch = { window: number, flightTime: number, maxLabels: number, nextId: number, flights: { Flight } }

-- Cette méthode permet de créer le regroupeur des « +N » d'un compteur lorsque le HUD est construit ; `window` (s)
-- regroupe les gains rapprochés, `flightTime` (s) est la durée d'un vol.
function UIMotion.newBatch(window: number, flightTime: number, maxLabels: number): Batch
	return { window = window, flightTime = flightTime, maxLabels = maxLabels, nextId = 0, flights = {} }
end

-- Cette méthode permet de ranger un gain dans une étiquette lorsque le compteur reçoit `amount` à `now` : renvoie
-- "spawn" (nouvelle étiquette) ou "merge" (étiquette `id` existante, à réafficher avec `total`).
function UIMotion.push(batch: Batch, amount: number, now: number): (string, number, number)
	local active = {}
	for _, flight in batch.flights do
		if now - flight.startedAt < batch.flightTime then
			table.insert(active, flight)
		end
	end
	batch.flights = active
	local last = active[#active]
	if last and (now - last.startedAt < batch.window or #active >= batch.maxLabels) then
		last.total += amount
		return "merge", last.id, last.total
	end
	batch.nextId += 1
	table.insert(active, { id = batch.nextId, total = amount, startedAt = now })
	return "spawn", batch.nextId, amount
end

-- Cette méthode permet de donner le nombre d'icônes qui accompagnent un « +N » en vol (3 à 6, plus pour un gros
-- gain) lorsque l'étiquette part.
function UIMotion.burstSize(amount: number): number
	if amount <= 0 then
		return 0
	end
	return math.clamp(2 + math.floor(math.log10(math.max(amount, 1))), 3, 6)
end

return UIMotion
