-- Règles des obstacles partagés (logique pure, testée) : une pièce est « déplacée » quand elle a quitté sa place,
-- l'obstacle réapparaît RESPAWN_DELAY après son dernier choc, pièce par pièce de bas en haut, et chaque objet projeté
-- est compté pour le vol le plus proche. Disposition des murs en quinconce (rien en porte-à-faux).
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

-- Brique d'un mur en quinconce : centre (x le long du mur, centré sur 0 ; y au-dessus du sol) et largeur
export type WallBrick = { x: number, y: number, width: number, row: number }

-- Cette méthode permet de disposer un mur en quinconce de `rows` rangées de briques `brick` (largeur X, hauteur Y) sur
-- `span` studs, avec un jeu `gap` entre deux briques, lorsque l'on monte un mur de thème : les rangées décalées ont une
-- demi-brique à chaque bout, si bien qu'aucune brique n'est en porte-à-faux (#114 : la brique du bout de la rangée du
-- haut tombait seule au démarrage).
function ObstacleRules.staggeredWall(span: number, brick: Vector3, rows: number, gap: number): { WallBrick }
	local step = brick.X + gap
	local count = math.floor(span / step)
	-- Rangées centrées sur la largeur (la largeur d'une brique ne divise pas toujours `span`)
	local left = -span / 2 + (span - count * step) / 2
	local half = (brick.X - gap) / 2
	local bricks = {}
	for row = 0, rows - 1 do
		local y = brick.Y / 2 + row * (brick.Y + gap)
		if row % 2 == 0 then
			for col = 0, count - 1 do
				table.insert(bricks, { x = left + step / 2 + col * step, y = y, width = brick.X, row = row })
			end
		else
			table.insert(bricks, { x = left + gap / 2 + half / 2, y = y, width = half, row = row })
			for col = 0, count - 2 do
				table.insert(bricks, { x = left + step + col * step, y = y, width = brick.X, row = row })
			end
			table.insert(bricks, { x = -(left + gap / 2 + half / 2), y = y, width = half, row = row })
		end
	end
	return bricks
end

return ObstacleRules
