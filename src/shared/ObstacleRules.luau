-- Règles des obstacles partagés (logique pure, testée) : une pièce est « déplacée » quand elle a quitté sa place,
-- l'obstacle réapparaît RESPAWN_DELAY après son dernier choc, pièce par pièce de bas en haut, et chaque objet projeté
-- est compté pour le vol le plus proche.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local ObstacleRules = {}

ObstacleRules.MOVE_TOLERANCE = 1.5 -- studs
ObstacleRules.TILT_TOLERANCE = math.cos(math.rad(20)) -- produit scalaire minimal entre axes d'origine et actuels
ObstacleRules.CLAIM_RADIUS = 30 -- un objet projeté plus loin que ça de tout mannequin n'est compté pour personne

-- Cette méthode permet de savoir si une pièce a quitté sa place (déplacée ou basculée) lorsque l'on surveille un
-- obstacle.
function ObstacleRules.isDisplaced(home: CFrame, current: CFrame): boolean
	if (current.Position - home.Position).Magnitude > ObstacleRules.MOVE_TOLERANCE then
		return true
	end
	return current.UpVector:Dot(home.UpVector) < ObstacleRules.TILT_TOLERANCE
		or current.LookVector:Dot(home.LookVector) < ObstacleRules.TILT_TOLERANCE
end

-- Cette méthode permet de savoir si un obstacle touché à `lastHit` doit réapparaître à `now` (aucun choc depuis
-- RESPAWN_DELAY).
function ObstacleRules.isDue(lastHit: number?, now: number): boolean
	return lastHit ~= nil and now - lastHit >= GameConfig.RESPAWN_DELAY
end

-- Cette méthode permet de donner l'ordre de réapparition des pièces déplacées (indices dans `homes`) : de bas en
-- haut, pour qu'une pièce ne réapparaisse jamais dans le vide, puis de gauche à droite.
function ObstacleRules.respawnOrder(homes: { CFrame }, displaced: { [number]: boolean }): { number }
	local order = {}
	for index in displaced do
		if displaced[index] then
			table.insert(order, index)
		end
	end
	table.sort(order, function(a, b)
		local pa, pb = homes[a].Position, homes[b].Position
		if math.abs(pa.Y - pb.Y) > 0.01 then
			return pa.Y < pb.Y
		end
		if math.abs(pa.X - pb.X) > 0.01 then
			return pa.X < pb.X
		end
		return a < b
	end)
	return order
end

-- Cette méthode permet de donner l'indice du mannequin en vol le plus proche de `position` (à moins de
-- CLAIM_RADIUS) lorsqu'un objet est projeté ; nil si aucun n'est assez près.
function ObstacleRules.claimant(position: Vector3, flights: { Vector3 }): number?
	local best, bestDistance = nil, ObstacleRules.CLAIM_RADIUS
	for index, flightPosition in flights do
		local distance = (flightPosition - position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

return ObstacleRules
