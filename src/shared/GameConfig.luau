-- Constantes de jeu partagées par le serveur et le client (équilibrage, géométrie des couloirs, rythme de la boucle).
-- stylua: ignore
local GameConfig = {
	-- Couloirs
	LANE_COUNT          = 6,      -- un couloir par joueur (MaxPlayers du projet Rojo)
	LANE_SPACING        = 70,     -- écart entre deux couloirs, axe X (studs)
	LANE_WIDTH          = 44,     -- largeur de la piste d'un couloir (studs)
	COURSE_LENGTH       = 2400,   -- longueur de la piste, axe +Z (studs = mètres affichés)
	SIDE_WALL_HEIGHT    = 24,     -- barrières latérales : retiennent le mannequin qui glisse
	HUB_DEPTH           = 60,     -- profondeur du hub (labo) derrière la piste

	-- Lancer
	PAD_Z               = -8,     -- centre de la zone de lancer de chaque couloir
	PAD_RADIUS          = 5,
	THROW_HEIGHT        = 2.3,    -- départ du mannequin au-dessus du HumanoidRootPart (main au lâcher, mesuré)
	THROW_FORWARD       = 0.3,    -- départ du mannequin devant le HumanoidRootPart (main au lâcher, mesuré)
	THROW_SIDE          = 2.1,    -- départ du mannequin à droite du HumanoidRootPart (main qui lance, mesuré)
	LAUNCH_PITCH_DEG    = 32,     -- angle du lancer au-dessus de l'horizontale
	GRAVITY             = 120,    -- Workspace.Gravity (196,2 par défaut) : vols plus longs, plus lisibles
	SPEED_BASE          = 110,    -- vitesse de lancer à la puissance de départ (studs/s)
	SPEED_PER_LOG       = 30,     -- + 30 studs/s chaque fois que la puissance est multipliée par e
	THROW_RELEASE_TIME  = 0.7,    -- lâcher dans l'animation de lancer (marqueur Release, s) : republier Throw si modifié

	-- Jauge (1 clic : l'aiguille court toute seule, le clic l'arrête)
	GAUGE_PERIOD        = 1.2,    -- durée d'un aller-retour de l'aiguille (s)
	GAUGE_MIN_FACTOR    = 0.6,    -- fraction de la vitesse quand l'aiguille est en bas
	GAUGE_STEPS         = 20,     -- valeur affichée à côté de l'aiguille : +1 à +20
	PERFECT_THRESHOLD   = 0.9,    -- jauge à partir de laquelle le lancer est PERFECT

	-- Entraînement
	START_POWER         = 10,     -- Throw Power de départ
	REP_TIME            = 0.8,    -- durée d'une répétition (s)
	LEVEL_BASE_REPS     = 3,      -- répétitions du premier niveau d'entraînement
	LEVEL_REPS_GROWTH   = 1.2,    -- répétitions × 1,2 par niveau

	-- Économie
	VALUE_STEP          = 0.25,   -- multiplicateur de gains + 0,25 par niveau de valeur du mannequin
	VALUE_MAX_LEVEL     = 50,
	VALUE_BASE_COST     = 250,
	VALUE_COST_GROWTH   = 1.7,
	MONEY_PER_METER     = 1,
	MONEY_PER_BONE      = 10,
	MONEY_PER_SMASH     = 5,
	PERFECT_BONUS       = 1.2,

	-- Dégâts
	BONE_IMPACT_DV      = 70,     -- variation de vitesse d'un membre en une frame qui casse un os (studs/s)
	DOUBLE_BONE_DV      = 150,    -- au-delà : deux os d'un coup
	MAX_BONES_PER_LIMB  = 3,
	IMPACT_GRACE_TIME   = 0.25,   -- pas de dégâts juste après le lancer (vitesse imposée)

	-- Fin de vol
	REST_SPEED          = 3,      -- vitesse du torse en dessous de laquelle le mannequin est arrêté
	REST_TIME           = 1.0,    -- durée d'arrêt avant de compter le résultat (s)
	MAX_FLIGHT_TIME     = 16,
	KILL_Y              = -40,    -- mannequin tombé du parcours
	RESULT_TIME         = 4.5,    -- durée de la cérémonie de résultat avant le lancer suivant (s)
	SMASH_SPEED         = 7,      -- une caisse ou une brique qui dépasse cette vitesse compte comme détruite
}

return GameConfig
