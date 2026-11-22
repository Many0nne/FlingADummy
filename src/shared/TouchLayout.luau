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

-- Cette méthode permet de donner l'avancée (unités de l'interface, à l'échelle `scale` des parents) qui porte un côté
-- de `size` px d'écran à MIN_TARGET px lorsque la zone tactile d'un bouton se cale ; 0 s'il est assez grand.
function TouchLayout.padExtra(size: number, scale: number): number
	if scale <= 0 then
		return 0
	end
	return math.max(0, TouchLayout.MIN_TARGET - size) / scale
end

-- Cette méthode permet de savoir si le joueur ne peut pas bouger (figé sur la bande, vol, résultat, tirage) lorsque ses
-- attributs changent : le joystick et le bouton de saut se cachent alors.
function TouchLayout.movementLocked(action: string?, laneState: string?, prizePhase: string?): boolean
	return action == "Holding" or laneState == "Flying" or laneState == "Result" or prizePhase ~= nil
end

return TouchLayout
