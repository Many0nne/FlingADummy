-- Animation de construction quand une base change de palier visuel (#122, Shared.BaseLook) : les anciennes pièces
-- (clôture, décor) s'enfoncent en s'effaçant, puis les nouvelles tombent en place une à une depuis l'entrée, avec un
-- petit rebond, poussière et chocs de briques ; le sol change de couleur à mi-parcours et les confettis jaillissent à
-- la fin. Le serveur pose l'état final tout de suite (Server.CourseBuilder.styleBase) ; chaque client anime un double
-- à partir de l'état répliqué (Client.BaseFx). Mouvement réduit : simple fondu court. La même animation sert quand la
-- base s'agrandit d'une rangée (#212, terrain allongé pendant le fondu du sol) ; un présentoir acheté tombe à sa place.
-- Logique pure (testée) : ordre et instants des pièces, durée totale bornée, courbes de chute et d'enfoncement,
-- départs des présentoirs qui tombent, profondeur du terrain qui s'allonge.

local BaseUpgrade = {}

BaseUpgrade.BASE_TAG = "PlayerBase" -- modèle d'une base (attributs ci-dessous)
BaseUpgrade.AT_ATTRIBUTE = "UpgradeAt" -- heure serveur du changement de palier (Workspace:GetServerTimeNow)
BaseUpgrade.FROM_PLOT_ATTRIBUTE = "UpgradeFromPlot" -- couleur du sol avant le changement
BaseUpgrade.STAGE_ATTRIBUTE = "Stage" -- étage d'une pièce de l'habillage (0 : au sol, 1 : posé dessus, 2 : en haut)
BaseUpgrade.STORE = "BaseUpgrades" -- dossier de ReplicatedStorage où l'ancien habillage attend les clients
BaseUpgrade.KEEP = 5 -- s pendant lesquelles le serveur garde l'ancien habillage

BaseUpgrade.OUT_TIME = 0.35 -- s : les anciennes pièces s'enfoncent et s'effacent
BaseUpgrade.SINK_DEPTH = 3 -- studs d'enfoncement des anciennes pièces
BaseUpgrade.FALL_TIME = 0.45 -- s de chute d'une pièce, rebond compris
BaseUpgrade.DROP_HEIGHT = 12 -- studs au-dessus de sa place d'où tombe une pièce
BaseUpgrade.BOUNCE_SHARE = 0.25 -- part de la chute consacrée au rebond
BaseUpgrade.BOUNCE_HEIGHT = 0.6 -- studs du rebond à l'arrivée
BaseUpgrade.STEP = 0.03 -- s entre deux départs (avant de borner la durée)
BaseUpgrade.SETTLE = 0.15 -- s entre la dernière arrivée et les confettis
BaseUpgrade.MIN_TOTAL = 1.5 -- durée totale bornée (s)
BaseUpgrade.MAX_TOTAL = 2.3
BaseUpgrade.FLOOR_TIME = 0.4 -- s de fondu du sol, au milieu des chutes
BaseUpgrade.FADE_TIME = 0.3 -- mouvement réduit : fondu des pièces et du sol
BaseUpgrade.MAX_AGE = 1 -- s : un changement plus ancien (client arrivé après, retard) s'affiche tel quel

-- Base qui s'agrandit (#212) : à l'ouverture d'une rangée, l'habillage est refait avec l'animation ci-dessus et le
-- terrain s'allonge vers le fond pendant le fondu du sol ; chaque présentoir acheté tombe à sa place (même chute)
BaseUpgrade.FROM_DEPTH_ATTRIBUTE = "UpgradeFromDepth" -- profondeur du terrain avant l'agrandissement
-- Terrain tel que le serveur l'a posé (couleur, profondeur) : le client y revient même après des changements
-- rapprochés, quand ses propres valeurs animées masquent celles reçues
BaseUpgrade.PLOT_COLOR_ATTRIBUTE = "PlotColor"
BaseUpgrade.PLOT_DEPTH_ATTRIBUTE = "PlotDepth"
BaseUpgrade.DROP_ATTRIBUTE = "DropAt" -- sur le dessus d'un présentoir : heure serveur où il commence à tomber
BaseUpgrade.ROW_DROP_DELAY = 1 -- s : le présentoir d'une rangée qui s'ouvre attend que le terrain soit allongé
BaseUpgrade.DROP_STAGGER = 0.08 -- s entre deux présentoirs ouverts d'un coup (passe Big Base)
BaseUpgrade.MAX_LEAD = 2.5 -- s : avance maximale d'une chute annoncée (au-delà, l'heure est tenue pour fausse)

-- Pièce de l'habillage à animer : position (centre) et étage (on pose le sol avant ce qui est dessus)
export type Piece = { position: Vector3, stage: number }

-- Déroulé d'une animation : départ de la chute de chaque pièce (même indice que les pièces), durée d'une chute,
-- durée de la sortie des anciennes pièces, fondu du sol, fin (confettis)
export type Plan = {
	starts: { number },
	fall: number,
	out: number,
	floorStart: number,
	floorEnd: number,
	finish: number,
	reduced: boolean,
}

-- Cette méthode permet de donner le déroulé de l'animation de `pieces` (étage puis distance à l'entrée `gate`, sur
-- le sol) lorsque la base change de palier ; `reduced` : tout en fondu court, sans chute.
function BaseUpgrade.plan(pieces: { Piece }, gate: Vector3, reduced: boolean): Plan
	local count = #pieces
	if reduced then
		local starts = table.create(count, 0)
		local fade = BaseUpgrade.FADE_TIME
		return {
			starts = starts,
			fall = fade,
			out = fade,
			floorStart = 0,
			floorEnd = fade,
			finish = fade,
			reduced = true,
		}
	end
	local order = table.create(count, 0)
	local distance = table.create(count, 0)
	for index, piece in pieces do
		order[index] = index
		local flat = piece.position - gate
		distance[index] = math.sqrt(flat.X * flat.X + flat.Z * flat.Z)
	end
	table.sort(order, function(a, b)
		local sa, sb = pieces[a].stage, pieces[b].stage
		if sa ~= sb then
			return sa < sb
		end
		if distance[a] ~= distance[b] then
			return distance[a] < distance[b]
		end
		return a < b
	end)
	-- Fenêtre des départs bornée : durée totale entre MIN_TOTAL et MAX_TOTAL quel que soit le nombre de pièces
	local fixed = BaseUpgrade.OUT_TIME + BaseUpgrade.FALL_TIME + BaseUpgrade.SETTLE
	local window =
		math.clamp((count - 1) * BaseUpgrade.STEP, BaseUpgrade.MIN_TOTAL - fixed, BaseUpgrade.MAX_TOTAL - fixed)
	local starts = table.create(count, 0)
	for rank, index in order do
		local share = if count > 1 then (rank - 1) / (count - 1) else 0
		starts[index] = BaseUpgrade.OUT_TIME + window * share
	end
	local last = if count > 1 then window else 0
	local finish = math.clamp(fixed + last, BaseUpgrade.MIN_TOTAL, BaseUpgrade.MAX_TOTAL)
	local floorStart = BaseUpgrade.OUT_TIME + window / 2
	return {
		starts = starts,
		fall = BaseUpgrade.FALL_TIME,
		out = BaseUpgrade.OUT_TIME,
		floorStart = floorStart,
		floorEnd = floorStart + BaseUpgrade.FLOOR_TIME,
		finish = finish,
		reduced = false,
	}
end

-- Cette méthode permet de donner la hauteur (studs) d'une pièce au-dessus de sa place lorsque sa chute en est à
-- `alpha` (0 : départ, 1 : posée) : chute accélérée, puis petit rebond qui retombe à 0.
function BaseUpgrade.dropOffset(alpha: number): number
	local a = math.clamp(alpha, 0, 1)
	local fall = 1 - BaseUpgrade.BOUNCE_SHARE
	if a < fall then
		local t = a / fall
		return BaseUpgrade.DROP_HEIGHT * (1 - t * t)
	end
	local t = (a - fall) / BaseUpgrade.BOUNCE_SHARE
	return BaseUpgrade.BOUNCE_HEIGHT * math.sin(math.pi * t)
end

-- Cette méthode permet de savoir si une pièce touche le sol (fin de la chute, avant le rebond) lorsque sa chute passe
-- de `before` à `after` (poussière et choc de briques à cet instant).
function BaseUpgrade.landed(before: number, after: number): boolean
	local fall = 1 - BaseUpgrade.BOUNCE_SHARE
	return before < fall and after >= fall
end

-- Cette méthode permet de donner l'enfoncement (studs, négatif) et la transparence d'une ancienne pièce lorsque sa
-- sortie en est à `alpha` (0 : en place, 1 : disparue).
function BaseUpgrade.sink(alpha: number): (number, number)
	local a = math.clamp(alpha, 0, 1)
	return -BaseUpgrade.SINK_DEPTH * a * a, a
end

-- Cette méthode permet de savoir si un changement de palier fait à l'heure serveur `at` est assez récent pour être
-- animé lorsque le client le reçoit à l'heure serveur `now` (sinon : état final directement).
function BaseUpgrade.isFresh(at: any, now: number): boolean
	return typeof(at) == "number" and now - at <= BaseUpgrade.MAX_AGE and now - at >= -BaseUpgrade.MAX_AGE
end

-- Cette méthode permet de donner l'instant (s après l'achat) où commence la chute de chacun des `count` présentoirs
-- ouverts par un achat, l'un après l'autre, après l'allongement du terrain si `rowOpened` (#212).
function BaseUpgrade.dropDelays(count: number, rowOpened: boolean): { number }
	local first = if rowOpened then BaseUpgrade.ROW_DROP_DELAY else 0
	local delays = table.create(count, 0)
	for index = 1, count do
		delays[index] = first + (index - 1) * BaseUpgrade.DROP_STAGGER
	end
	return delays
end

-- Cette méthode permet de savoir si la chute d'un présentoir annoncée pour l'heure serveur `at` est à jouer lorsque le
-- client la reçoit à l'heure serveur `now` : pas encore finie (sinon il est déjà posé) et pas trop loin dans le futur.
function BaseUpgrade.dropFresh(at: any, now: number): boolean
	return typeof(at) == "number" and now - at <= BaseUpgrade.FALL_TIME and at - now <= BaseUpgrade.MAX_LEAD
end

-- Cette méthode permet de donner la profondeur du terrain pendant l'agrandissement (de `from` à `to`) lorsque le fondu
-- du sol en est à `share` (0 à 1), en douceur au départ et à l'arrivée.
function BaseUpgrade.plotDepth(from: number, to: number, share: number): number
	local s = math.clamp(share, 0, 1)
	return from + (to - from) * s * s * (3 - 2 * s)
end

return BaseUpgrade
