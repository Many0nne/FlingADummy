-- Jeu sur écran tactile (#19) : échelle du HUD selon l'écran, zone tactile minimale des boutons, moments où le
-- joystick et le bouton de saut se cachent (le joueur ne peut pas bouger : un toucher n'importe où sert au jeu).
local TouchLayout = {}

TouchLayout.MIN_TARGET = 44 -- px d'écran : zone tactile minimale d'un bouton (recommandation Apple, reprise par Roblox)
TouchLayout.MIN_SCALE = 0.5
TouchLayout.MAX_SCALE = 1.3
-- Écran de référence du HUD (1280 × 720) ; sur écran tactile, cadre plus petit pour grossir l'interface d'un téléphone
-- en paysage (≈ 0,6 au lieu de 0,54 à 390 px de haut), assez haut pour la plus haute fenêtre (My Dummies, 560)
TouchLayout.DESIGN = { width = 1280, height = 720 }
TouchLayout.TOUCH_DESIGN = { width = 1180, height = 650 }

-- Cette méthode permet de donner l'échelle du HUD pour un écran de `width` × `height` px lorsque la fenêtre change ;
-- `touch` : écran tactile.
function TouchLayout.hudScale(width: number, height: number, touch: boolean): number
	local design = if touch then TouchLayout.TOUCH_DESIGN else TouchLayout.DESIGN
	local scale = math.min(width / design.width, height / design.height)
	return math.clamp(scale, TouchLayout.MIN_SCALE, TouchLayout.MAX_SCALE)
end

export type Rect = { x0: number, y0: number, x1: number, y1: number }

-- Cette méthode permet d'arrêter la zone tactile `zone` du bouton `own` à mi-distance du voisin `other` le long de
-- `axis` lorsque la zone empiète sur lui ; jamais en deçà du bouton lui-même.
local function clip(zone: Rect, own: Rect, other: Rect, axis: "x" | "y")
	if axis == "x" then
		if other.x0 >= own.x1 then
			zone.x1 = math.max(own.x1, math.min(zone.x1, (own.x1 + other.x0) / 2))
		else
			zone.x0 = math.min(own.x0, math.max(zone.x0, (other.x1 + own.x0) / 2))
		end
	elseif other.y0 >= own.y1 then
		zone.y1 = math.max(own.y1, math.min(zone.y1, (own.y1 + other.y0) / 2))
	else
		zone.y0 = math.min(own.y0, math.max(zone.y0, (other.y1 + own.y0) / 2))
	end
end

-- Cette méthode permet de donner la zone tactile d'un bouton `own` (px d'écran) : au moins MIN_TARGET de côté, centrée,
-- mais arrêtée à mi-chemin des boutons voisins `others` (un PLACE et un SELL empilés ne se volent pas leurs touchers)
-- lorsque la zone tactile du bouton se cale.
function TouchLayout.padRect(own: Rect, others: { Rect }): Rect
	local cx, cy = (own.x0 + own.x1) / 2, (own.y0 + own.y1) / 2
	local half = TouchLayout.MIN_TARGET / 2
	local zone = {
		x0 = math.min(own.x0, cx - half),
		y0 = math.min(own.y0, cy - half),
		x1 = math.max(own.x1, cx + half),
		y1 = math.max(own.y1, cy + half),
	}
	for _, other in others do
		local overlaps = zone.x0 < other.x1 and other.x0 < zone.x1 and zone.y0 < other.y1 and other.y0 < zone.y1
		if overlaps then
			local gapX = math.max(other.x0 - own.x1, own.x0 - other.x1)
			local gapY = math.max(other.y0 - own.y1, own.y0 - other.y1)
			-- Séparés le long de l'axe où l'écart est le plus grand ; boutons qui se chevauchent déjà : rien à faire
			if gapX >= 0 or gapY >= 0 then
				clip(zone, own, other, if gapX >= gapY then "x" else "y")
			end
		end
	end
	return zone
end

-- Cette méthode permet de savoir si le joueur ne peut pas bouger (figé sur la bande, vol, résultat, tirage) lorsque ses
-- attributs changent : le joystick et le bouton de saut se cachent alors.
function TouchLayout.movementLocked(action: string?, laneState: string?, prizePhase: string?): boolean
	return action == "Holding" or laneState == "Flying" or laneState == "Result" or prizePhase ~= nil
end

return TouchLayout
