-- Constantes de jeu partagées par le serveur et le client (équilibrage, géométrie des couloirs, rythme de la boucle).
-- stylua: ignore
local GameConfig = {
	-- Couloirs
	LANE_COUNT          = 6,      -- un couloir par joueur (MaxPlayers du projet Rojo)
	LANE_SPACING        = 70,     -- écart entre deux couloirs, axe X (studs)
	LANE_WIDTH          = 44,     -- largeur du sol d'un couloir (studs)
	COURSE_LENGTH       = 720,    -- longueur du parcours, axe +Z (studs = mètres affichés)
	SIDE_WALL_HEIGHT    = 60,

	-- Canon
	LAUNCH_PITCH_DEG    = 30,     -- angle du tir au-dessus de l'horizontale
	MUZZLE_HEIGHT       = 7,      -- hauteur de la bouche du canon au-dessus du sol
	GRAVITY             = 120,    -- Workspace.Gravity (196,2 par défaut) : vols plus longs, plus lisibles

	-- Économie
	BASE_LAUNCH_SPEED   = 125,    -- vitesse de lancer au niveau 1 de puissance (studs/s)
	POWER_GROWTH        = 1.12,   -- vitesse x1,12 par niveau de puissance
	POWER_MAX_LEVEL     = 15,
	VALUE_STEP          = 0.25,   -- multiplicateur de gains + 0,25 par niveau de valeur
	VALUE_MAX_LEVEL     = 30,
	POWER_BASE_COST     = 100,
	POWER_COST_GROWTH   = 1.55,
	VALUE_BASE_COST     = 150,
	VALUE_COST_GROWTH   = 1.6,
	MONEY_PER_METER     = 1,
	MONEY_PER_BONE      = 10,
	MONEY_PER_SMASH     = 5,
	PERFECT_BONUS       = 1.2,

	-- Jauge
	GAUGE_PERIOD        = 1.1,    -- durée d'un aller-retour de l'aiguille (s)
	GAUGE_MIN_FACTOR    = 0.55,   -- fraction de la vitesse quand l'aiguille est en bas
	PERFECT_THRESHOLD   = 0.9,    -- jauge à partir de laquelle le lancer est PERFECT

	-- Dégâts
	BONE_IMPACT_DV      = 70,     -- variation de vitesse d'un membre en une frame qui casse un os (studs/s)
	DOUBLE_BONE_DV      = 150,    -- au-delà : deux os d'un coup
	MAX_BONES_PER_LIMB  = 3,
	IMPACT_GRACE_TIME   = 0.25,   -- pas de dégâts juste après le tir (le canon impose la vitesse)

	-- Fin de vol
	REST_SPEED          = 3,      -- vitesse du torse en dessous de laquelle le mannequin est arrêté
	REST_TIME           = 1.2,    -- durée d'arrêt avant de compter le résultat (s)
	MAX_FLIGHT_TIME     = 14,
	KILL_Y              = -40,    -- mannequin tombé du parcours
	RESULT_TIME         = 2.6,    -- durée d'affichage du résultat avant le lancer suivant (s)
	SMASH_SPEED         = 7,      -- une caisse ou une brique qui dépasse cette vitesse compte comme détruite
}

return GameConfig
