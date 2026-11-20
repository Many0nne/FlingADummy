-- Objectif du moment (texte en haut au centre, comme « Lancer à nouveau » / « Acheter une barre de traction » dans les
-- jeux de référence) et cible désignée : une pièce du décor (flèche au-dessus, chevrons au sol) ou un bouton du HUD.
--
-- Point d'accroche des cibles du décor : toute BasePart portant le tag `ObjectiveTarget` (CollectionService) et
-- l'attribut `Objective` (« Throw » zone de lancer, « Train » appareil d'entraînement ; d'autres valeurs pour #13 /
-- #14). Facultatifs : `Slot` (place du lobby : la cible ne vaut que pour le joueur de cette place) et `OwnerUserId`
-- (cible d'un seul joueur). Sans l'un ni l'autre, la cible est partagée et le joueur suit la plus proche. `Span`
-- (studs) : cible allongée sur l'axe X (bande de lancer) ; la flèche et les chevrons visent son point le plus proche
-- du joueur, à `Span` au plus de son centre.
local Objectives = {}

Objectives.TAG = "ObjectiveTarget"

export type State = {
	action: string?, -- attribut Action du joueur : nil, "Holding", "Training"
	laneState: string?, -- attribut LaneState : "Ready", "Flying", "Result"
	thrown: boolean, -- a lancé depuis son dernier gain de Throw Power
	canBuyGear: boolean,
	canBuyDummy: boolean,
}

export type Objective = {
	id: string,
	text: string,
	target: string?, -- valeur de l'attribut Objective de la cible du décor
	button: string?, -- bouton du HUD désigné : "Shop", "Dummies"
}

export type Candidate = { position: Vector3, slot: number?, owner: number? }

local THROW = { id = "Throw", text = "Throw your dummy!", target = "Throw" }
local TRAIN = { id = "Train", text = "Train!", target = "Train" }
local BUY_GEAR = { id = "BuyGear", text = "Buy better gear!", button = "Shop" }
local BUY_DUMMY = { id = "BuyDummy", text = "Buy a better dummy!", button = "Dummies" }

-- Cette méthode permet de choisir l'objectif (achats, puis alternance lancer / entraînement) lorsque l'état du joueur
-- change ; nil quand l'écran est occupé (jauge, vol, résultat, séance d'entraînement où seul STOP reste).
function Objectives.pick(state: State): Objective?
	if state.laneState == "Flying" or state.laneState == "Result" then
		return nil
	end
	if state.action == "Holding" or state.action == "Training" then
		return nil
	end
	if state.canBuyGear then
		return BUY_GEAR
	end
	if state.canBuyDummy then
		return BUY_DUMMY
	end
	return if state.thrown then TRAIN else THROW
end

-- Cette méthode permet de choisir, parmi les cibles d'un type, celle que suit le joueur (la sienne, ou la plus
-- proche des cibles partagées) lorsque la flèche et les chevrons se placent ; nil si aucune ne lui est ouverte.
function Objectives.chooseTarget(candidates: { Candidate }, slot: number?, userId: number, from: Vector3): Candidate?
	local best, bestDistance = nil, math.huge
	for _, candidate in candidates do
		if candidate.slot ~= nil and candidate.slot ~= slot then
			continue
		end
		if candidate.owner ~= nil and candidate.owner ~= userId then
			continue
		end
		local distance = (candidate.position - from).Magnitude
		if distance < bestDistance then
			best, bestDistance = candidate, distance
		end
	end
	return best
end

-- Cette méthode permet de donner le point visé d'une cible centrée en `center` lorsque la flèche se place depuis
-- `from` : le centre, ou pour une cible allongée sur X (`span` > 0) son point le plus proche du joueur.
function Objectives.aimPoint(center: Vector3, span: number?, from: Vector3): Vector3
	if not span or span <= 0 then
		return center
	end
	return Vector3.new(math.clamp(from.X, center.X - span, center.X + span), center.Y, center.Z)
end

-- Cette méthode permet de placer les chevrons au sol entre le joueur et la cible lorsque le tracé se met à jour :
-- positions (au sol) espacées de `spacing`, décalées de `phase` (0-1) pour défiler vers la cible, en laissant
-- `gap` studs libres à chaque bout ; au plus `max` chevrons.
function Objectives.chevrons(
	from: Vector3,
	to: Vector3,
	spacing: number,
	gap: number,
	phase: number,
	max: number
): { Vector3 }
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	local points = {}
	if length <= gap * 2 then
		return points
	end
	local direction = flat / length
	local d = gap + (phase % 1) * spacing
	while d <= length - gap and #points < max do
		local t = d / length
		table.insert(points, Vector3.new(from.X, from.Y + (to.Y - from.Y) * t, from.Z) + direction * d)
		d += spacing
	end
	return points
end

return Objectives
