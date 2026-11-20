-- Constantes de jeu partagées par le serveur et le client (équilibrage, géométrie de la carte, rythme de la boucle).
-- stylua: ignore
local GameConfig = {
	-- Carte : lobby de SLOT_COUNT joueurs, une piste partagée (canyon en gradins), axe +Z, départ à z = 0
	SLOT_COUNT          = 4,      -- places par serveur (MaxPlayers du projet Rojo) : base, appareil, colonne d'obstacles
	SLOT_SPACING        = 14,     -- largeur d'une colonne d'obstacles (points de lancer de test), axe X (studs)
	TRACK_WIDTH         = 80,     -- largeur du fond du canyon (studs)
	COURSE_LENGTH       = 2400,   -- longueur de la piste, axe +Z (studs = mètres affichés)
	SIDE_WALL_HEIGHT    = 260,    -- paroi invisible au-dessus des gradins : garde les mannequins dans le canyon
	HUB_WIDTH           = 180,    -- hub (bases et leurs appareils) derrière la zone de lancer, axe X
	HUB_DEPTH           = 130,    -- profondeur du hub, axe -Z, depuis l'arrière de la zone de lancer
	LAUNCH_DEPTH        = 16,     -- profondeur de la zone de lancer commune (z de -16 à 0)

	-- Lancer : bande commune au bord de la piste (z de -BAND_DEPTH à 0), le joueur s'y fige jusqu'au lancer
	BAND_DEPTH          = 8,      -- profondeur de la bande de lancer (studs)
	BAND_SPACING        = 5,      -- écart minimal entre deux joueurs figés sur la bande, axe X (studs)
	BAND_MARGIN         = 3,      -- un joueur figé reste à cette distance des bords de la bande (studs)
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
	-- Vérification par le serveur : il recalcule l'instant du clic depuis l'ouverture de la jauge (lâcher et latence
	-- déduits) et garde la valeur du client si elle est atteignable dans cette fenêtre, sinon la sienne
	GAUGE_MAX_LAG       = 0.4,    -- latence aller-retour prise en compte au plus (s)
	GAUGE_LAG_TOLERANCE = 0.12,   -- marge autour de la latence mesurée (gigue, cadence réseau, s)
	GAUGE_RELEASE_SLACK = 0.25,   -- retard possible du lâcher après THROW_RELEASE_TIME (= RELEASE_GRACE du client, s)

	-- Entraînement
	START_POWER         = 10,     -- Throw Power de départ
	REP_TIME            = 0.8,    -- durée d'une répétition (s)
	LEVEL_BASE_EXP      = 3,      -- EXP du premier niveau d'entraînement (3 répétitions avec l'équipement de départ)
	LEVEL_EXP_GROWTH    = 1.2,    -- EXP demandée × 1,2 par niveau

	-- Économie
	VALUE_STEP          = 0.25,   -- multiplicateur de gains + 0,25 par niveau de valeur du mannequin
	VALUE_MAX_LEVEL     = 50,
	VALUE_BASE_COST     = 250,
	VALUE_COST_GROWTH   = 1.7,
	MONEY_PER_METER     = 1,
	MONEY_PER_BONE      = 10,
	MONEY_PER_SMASH     = 5,

	-- Dégâts
	BONE_IMPACT_DV      = 70,     -- variation de vitesse d'un membre en une frame qui casse un os (studs/s)
	DOUBLE_BONE_DV      = 150,    -- au-delà : deux os d'un coup
	MAX_BONES_PER_LIMB  = 3,
	IMPACT_GRACE_TIME   = 0.25,   -- pas de dégâts juste après le lancer (vitesse imposée)

	-- Obstacles partagés : une pièce déplacée réapparaît à sa place
	RESPAWN_DELAY       = 5,      -- délai après le dernier choc subi par l'obstacle (s)
	RESPAWN_STAGGER     = 0.05,   -- écart entre deux pièces qui réapparaissent (s)

	-- Fin de vol
	REST_SPEED          = 3,      -- vitesse du torse en dessous de laquelle le mannequin est arrêté
	REST_TIME           = 1.0,    -- durée d'arrêt avant de compter le résultat (s)
	MAX_FLIGHT_TIME     = 16,
	KILL_Y              = -40,    -- mannequin tombé du parcours
	RESULT_TIME         = 4.5,    -- durée de la cérémonie de résultat avant le lancer suivant (s)
	SMASH_SPEED         = 7,      -- une caisse ou une brique qui dépasse cette vitesse compte comme détruite
}

return GameConfig
