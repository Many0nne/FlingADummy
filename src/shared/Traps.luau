-- Pièges signatures des thèmes (logique pure, testée) : chaque piège fait réagir le mannequin autrement qu'un objet
-- cassable (rebond, souffle, coup de rondin, presse, aimant…). Le serveur (Server.LaunchService) le déclenche quand le
-- torse traverse sa boîte (une fois par vol et par piège), remplace la vitesse du mannequin par `Traps.react`, casse
-- `bones` os sur les membres les plus proches et annonce le choc ; chaque client joue son son, ses particules et son
-- popup (`label`). Les pièges ne collisionnent pas : leur effet est cette règle, pas la physique.
local Traps = {}

export type Kind = {
	label: string, -- popup au point de déclenchement (« BOING! »)
	sound: string, -- son joué par le client (Shared.Sounds)
	burst: string, -- gerbe de particules jouée par le client (Client.Effects)
	height: number?, -- hauteur de la boîte au-dessus du sol (studs) ; nil = colonne haute (hauteur des vitres)
	depth: number, -- profondeur de la boîte, axe Z (studs)
	keep: number, -- part de la vitesse horizontale gardée
	forward: number, -- vitesse ajoutée vers l'avant de la piste (+Z, studs/s)
	side: number, -- vitesse donnée sur le côté, vers l'extérieur de la colonne (studs/s)
	up: number, -- vitesse verticale minimale vers le haut ; négative : vitesse imposée vers le bas (presse)
	restitution: number, -- part de la vitesse verticale d'arrivée renvoyée vers le haut (rebond)
	spin: number, -- rotation donnée au mannequin (rad/s, axe vertical)
	bones: number, -- os cassés au déclenchement (membres les plus proches)
}

Traps.WIDTH = 12 -- largeur d'un piège : une colonne d'obstacles (SLOT_SPACING), moins un passage de 2 studs
Traps.FLOOR = -1 -- bas des boîtes : un mannequin couché au sol (torse à moins d'un stud) est dedans

-- stylua: ignore
Traps.KINDS = {
	-- Prairie : trampoline, renvoie le mannequin en l'air sans perdre son élan
	Trampoline = { label = "BOING!",    sound = "Boing",  burst = "Stars",    height = 5,   depth = 10,
	               keep = 0.9,  forward = 10,  side = 0,  up = 75,  restitution = 0.9, spin = 0,  bones = 1 },
	-- Ferme : ventilateur géant incliné, souffle vers l'avant et vers le haut
	Fan        = { label = "WHOOSH!",   sound = "Gust",   burst = "Wind",     height = 26,  depth = 14,
	               keep = 1,    forward = 25,  side = 0,  up = 30,  restitution = 0,   spin = 0,  bones = 1 },
	-- Forêt : rondin qui balance entre deux troncs, frappe de côté et coupe l'élan
	SwingLog   = { label = "WHACK!",    sound = "Whack",  burst = "Chips",    height = 16,  depth = 6,
	               keep = 0.75, forward = 0,   side = 35, up = 25,  restitution = 0,   spin = 6,  bones = 2 },
	-- Plage : vague qui emporte le mannequin au ras du sol
	Wave       = { label = "SPLASH!",   sound = "Splash", burst = "Splash",   height = 9,   depth = 10,
	               keep = 1,    forward = 30,  side = 0,  up = 18,  restitution = 0,   spin = 0,  bones = 1 },
	-- Désert : tornade de sable, aspire vers le haut en tournoyant
	Twister    = { label = "TWISTER!",  sound = "Gust",   burst = "Dust",     height = 45,  depth = 10,
	               keep = 0.7,  forward = 15,  side = 0,  up = 85,  restitution = 0,   spin = 20, bones = 1 },
	-- Chantier : presse hydraulique, écrase au sol
	Press      = { label = "SQUASH!",   sound = "Press",  burst = "Dust",     height = 11,  depth = 9,
	               keep = 0.3,  forward = 0,   side = 0,  up = -80, restitution = 0,   spin = 0,  bones = 3 },
	-- Casse : aimant de grue, arrache vers le haut et coupe net l'élan (le mannequin retombe sur place)
	Magnet     = { label = "CLANG!",    sound = "Clang",  burst = "Sparks",   height = 22,  depth = 8,
	               keep = 0.25, forward = 0,   side = 0,  up = 45,  restitution = 0,   spin = 4,  bones = 1 },
	-- Neige : tremplin de saut à ski, projette loin vers l'avant
	SkiJump    = { label = "AIR TIME!", sound = "Whoosh", burst = "Snow",     height = 7,   depth = 12,
	               keep = 1,    forward = 30,  side = 0,  up = 60,  restitution = 0,   spin = 0,  bones = 1 },
	-- Volcan : bassin de lave, rebond très haut (et brûlure)
	Lava       = { label = "SIZZLE!",   sound = "Sizzle", burst = "Fire",     height = 4,   depth = 10,
	               keep = 0.8,  forward = 0,   side = 0,  up = 90,  restitution = 1,   spin = 3,  bones = 2 },
	-- Bonbons : canon à confettis, tir tendu vers l'avant
	Cannon     = { label = "KABOOM!",   sound = "Cannon", burst = "Confetti", height = 9,   depth = 8,
	               keep = 1,    forward = 50,  side = 0,  up = 30,  restitution = 0,   spin = 0,  bones = 1 },
	-- Jouets : diable en boîte, éjecte à la verticale
	JackBox    = { label = "POP!",      sound = "Spring", burst = "Confetti", height = 8,   depth = 8,
	               keep = 0.7,  forward = 0,   side = 0,  up = 105, restitution = 0,   spin = 5,  bones = 1 },
	-- Base lunaire : anneau propulseur, énorme poussée vers l'avant
	Booster    = { label = "BOOST!",    sound = "Rocket", burst = "Sparks",   height = nil, depth = 6,
	               keep = 1,    forward = 70, side = 0,  up = 25,  restitution = 0,   spin = 0,  bones = 1 },
} :: { [string]: Kind }

Traps.MOTION_TAG = "TrapMotion" -- pièce mobile d'un piège (pale, rondin, presse…), animée par chaque client
Traps.MOTION_RANGE = 500 -- un client n'anime que les pièges à moins de 500 studs de sa caméra

-- Cette méthode permet de donner le décalage d'une pièce mobile de piège (repère de son pivot au repos) à l'instant `t`
-- lorsque le client l'anime : "Spin" tourne autour de `axis`, "Swing" balance de ±`amplitude` degrés, "Bob" monte et
-- descend de `amplitude` studs, "Press" descend d'un coup puis remonte lentement ; `period` en secondes.
function Traps.motion(motion: string, t: number, axis: Vector3, amplitude: number, period: number): CFrame
	local phase = (t / period) % 1
	if motion == "Spin" then
		return CFrame.fromAxisAngle(axis.Unit, 2 * math.pi * phase)
	elseif motion == "Swing" then
		return CFrame.fromAxisAngle(axis.Unit, math.rad(amplitude) * math.sin(2 * math.pi * phase))
	elseif motion == "Bob" then
		return CFrame.new(axis.Unit * amplitude * (0.5 - 0.5 * math.cos(2 * math.pi * phase)))
	elseif motion == "Press" then
		-- Chute en 15 % de la période, pause en bas, remontée sur le reste
		local down = if phase < 0.15 then (phase / 0.15) ^ 2 elseif phase < 0.3 then 1 else 1 - (phase - 0.3) / 0.7
		return CFrame.new(axis.Unit * amplitude * down)
	end
	return CFrame.identity
end

-- Cette méthode permet de calculer la vitesse du mannequin après le piège `kind` lorsqu'il le déclenche avec la
-- vitesse `velocity` ; `outward` (±1) = côté de la colonne où il passe (le rondin le pousse vers l'extérieur).
function Traps.react(kind: string, velocity: Vector3, outward: number): Vector3
	local def = Traps.KINDS[kind]
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z) * def.keep
		+ Vector3.new(outward * def.side, 0, def.forward)
	local vertical = if def.up < 0 then def.up else math.max(def.up, math.abs(velocity.Y) * def.restitution)
	return horizontal + Vector3.new(0, vertical, 0)
end

-- Cette méthode permet de savoir si le segment de `a` à `b` (trajet du torse pendant une frame) touche la boîte
-- axe-alignée (`center`, `size`) lorsque l'on cherche les pièges traversés ; un point immobile dedans compte.
function Traps.crosses(center: Vector3, size: Vector3, a: Vector3, b: Vector3): boolean
	local low, high = center - size / 2, center + size / 2
	local starts = { a.X, a.Y, a.Z }
	local deltas = { b.X - a.X, b.Y - a.Y, b.Z - a.Z }
	local lows = { low.X, low.Y, low.Z }
	local highs = { high.X, high.Y, high.Z }
	local enter, leave = 0, 1
	for axis = 1, 3 do
		local p, d = starts[axis], deltas[axis]
		if math.abs(d) < 1e-9 then
			if p < lows[axis] or p > highs[axis] then
				return false
			end
		else
			local t1, t2 = (lows[axis] - p) / d, (highs[axis] - p) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			enter = math.max(enter, t1)
			leave = math.min(leave, t2)
			if enter > leave then
				return false
			end
		end
	end
	return true
end

-- Cette méthode permet de donner le point de la boîte le plus proche de `position` lorsque l'on place le popup et
-- que l'on cherche les membres touchés par le piège.
function Traps.contact(center: Vector3, size: Vector3, position: Vector3): Vector3
	local low, high = center - size / 2, center + size / 2
	return Vector3.new(
		math.clamp(position.X, low.X, high.X),
		math.clamp(position.Y, low.Y, high.Y),
		math.clamp(position.Z, low.Z, high.Z)
	)
end

-- Cette méthode permet de choisir les `count` membres qui cassent (les plus proches du point de contact, un os
-- chacun, à nom égal par ordre alphabétique) lorsqu'un piège se déclenche ; `limbs` : position de chaque membre.
function Traps.nearestLimbs(limbs: { [string]: Vector3 }, contact: Vector3, count: number): { string }
	local names = {}
	for name in limbs do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		local da, db = (limbs[a] - contact).Magnitude, (limbs[b] - contact).Magnitude
		if math.abs(da - db) > 1e-6 then
			return da < db
		end
		return a < b
	end)
	local chosen = {}
	for i = 1, math.min(count, #names) do
		chosen[i] = names[i]
	end
	return chosen
end

return Traps
