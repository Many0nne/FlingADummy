-- Constantes de jeu partagées par le serveur et le client (équilibrage, géométrie de la carte, rythme de la boucle).
-- stylua: ignore
local GameConfig = {
	-- Carte : lobby de SLOT_COUNT joueurs, une piste partagée (canyon en gradins), axe +Z, départ à z = 0
	SLOT_COUNT          = 4,      -- places par serveur (MaxPlayers du projet Rojo) : base, appareil, colonne d'obstacles
	SLOT_SPACING        = 14,     -- largeur d'une colonne d'obstacles (points de lancer de test), axe X (studs)
	TRACK_WIDTH         = 80,     -- largeur du fond du canyon (studs)
	COURSE_LENGTH       = 6000,   -- longueur de la piste, axe +Z (studs = mètres affichés ; 2 400 avant #97)
	SIDE_WALL_HEIGHT    = 260,    -- paroi invisible au-dessus des gradins : garde les mannequins dans le canyon
	HUB_WIDTH           = 256,    -- hub derrière la zone de lancer, axe X : 4 bases côte à côte, stands et tableaux (#120)
	HUB_DEPTH           = 112,    -- profondeur du hub, axe -Z, depuis l'arrière de la zone de lancer (130 avant #120, 96 avant #156)
	LAUNCH_DEPTH        = 16,     -- profondeur de la zone de lancer commune (z de -16 à 0)

	-- Lancer : bande commune au bord de la piste (z de -BAND_DEPTH à 0), le joueur s'y fige jusqu'au lancer
	BAND_DEPTH          = 16,     -- profondeur de la bande : toute la zone de lancer, jusqu'au hub (studs)
	BAND_SPACING        = 5,      -- écart minimal entre deux joueurs figés sur la bande, axe X (studs)
	BAND_MARGIN         = 3,      -- un joueur figé reste à cette distance des bords de la bande, en X et en Z (studs)
	THROW_HEIGHT        = 2.3,    -- départ du mannequin au-dessus du HumanoidRootPart (main au lâcher, mesuré)
	THROW_FORWARD       = 0.3,    -- départ du mannequin devant le HumanoidRootPart (main au lâcher, mesuré)
	THROW_SIDE          = 2.1,    -- départ du mannequin à droite du HumanoidRootPart (main qui lance, mesuré)
	LAUNCH_PITCH_DEG    = 32,     -- angle du lancer au-dessus de l'horizontale
	GRAVITY             = 120,    -- Workspace.Gravity (196,2 par défaut) : vols plus longs, plus lisibles
	SPEED_BASE          = 130,    -- vitesse de lancer à la puissance de départ (studs/s ; 110 avant #113, glissade bornée)
	SPEED_PER_LOG       = 38,     -- + 38 studs/s chaque fois que la puissance est multipliée par e (30 avant #113)…
	SPEED_KNEE_POWER    = 10000,  -- … jusqu'à cette puissance (≈ 1,2 km : premier kilomètre inchangé, #157)…
	SPEED_PER_LOG_FAR   = 28,     -- … puis + 28 par facteur e : bout de piste vers la fin des équipements (#157)
	THROW_RELEASE_TIME  = 0.7,    -- lâcher dans l'animation de lancer (marqueur Release, s) : republier Throw si modifié
	RELEASE_LEAD_MAX    = 0.4,    -- départ affiché dès le lâcher (#144) : avance sur le serveur (latence aller-retour) prise au plus (s) ; au-delà, maintien à la main

	-- Caméra de la bande (#158, Shared.ThrowFraming) : resserrée derrière l'épaule droite tant que le joueur tient le
	-- mannequin, cadrage de 09 à la jauge (avatar à gauche du centre, regard dans l'axe de la piste)
	BAND_CAM_IN         = 0.35,   -- fondu de la caméra libre au cadrage de la bande (s ; coupe directe en mouvement réduit)
	BAND_CAM_OUT        = 0.25,   -- retour à la caméra libre si le joueur quitte la bande sans lancer (s)
	BAND_CAM_FOV        = 55,     -- champ de vision du cadrage (caméra libre : 70)
	BAND_CAM_SIDE       = 2.2,    -- caméra à droite du HumanoidRootPart, côté du bras qui lance (studs)
	BAND_CAM_HEIGHT     = 2,      -- caméra au-dessus du HumanoidRootPart (studs) : juste sous le haut de la tête
	BAND_CAM_BACK       = 10,     -- caméra derrière le HumanoidRootPart (studs)
	BAND_CAM_LOOK       = 80,     -- point visé devant le joueur, dans l'axe de la piste (studs)
	BAND_CAM_DIP        = 1.5,    -- point visé plus bas que la caméra (studs) : regard presque à l'horizontale
	THROW_CAM_BLEND     = 0.45,   -- passage du cadrage de la bande au gros plan du geste (s, Client.ThrowCinematic)

	-- Vol plafonné et glissade bornée (#113, Shared.FlightArc)
	APEX_HEIGHT         = 100,    -- hauteur max du vol (studs au-dessus de la piste) : au-delà, la puissance part en distance
	GROUND_BRAKE        = 600,    -- frein au sol après le premier contact (studs/s²) : glissade = vitesse² / 1 200
	BRAKE_HEIGHT        = 6,      -- le frein agit sous cette hauteur du torse (studs) : pas en l'air après un rebond
	LATERAL_DAMP        = 6,      -- amortissement de la vitesse latérale après le premier contact (1/s) : reste dans sa colonne

	-- Jauge (1 clic : l'aiguille court toute seule, le clic l'arrête)
	GAUGE_PERIOD        = 1.2,    -- durée d'un aller-retour de l'aiguille (s)
	GAUGE_MIN_FACTOR    = 0.6,    -- fraction de la vitesse quand l'aiguille est en bas
	GAUGE_STEPS         = 20,     -- valeur affichée à côté de l'aiguille : +1 à +20
	-- Vérification par le serveur : il recalcule l'instant du clic depuis l'ouverture de la jauge (arrivée du GaugeStop
	-- moins la latence ; sans GaugeStop, arrivée du Launch moins lâcher et latence) et garde la valeur du client si elle
	-- est atteignable dans cette fenêtre, sinon la sienne
	GAUGE_MAX_LAG       = 1.0,    -- latence aller-retour (GetNetworkPing) prise en compte au plus (s)
	GAUGE_LAG_TOLERANCE = 0.12,   -- marge autour de la latence mesurée (gigue, cadence réseau, s)
	GAUGE_RELEASE_SLACK = 0.25,   -- retard possible du lâcher après THROW_RELEASE_TIME (lâcher de secours du client, repli sans GaugeStop, s)

	-- Entraînement
	START_POWER         = 10,     -- Throw Power de départ
	REP_TIME            = 0.8,    -- durée d'une répétition (s)
	LEVEL_BASE_EXP      = 3,      -- EXP du premier niveau d'entraînement (3 répétitions avec l'équipement de départ)
	LEVEL_EXP_GROWTH    = 1.2,    -- EXP demandée × 1,2 par niveau…
	LEVEL_MAX_REPS      = 12,     -- … plafonnée à 12 répétitions de l'équipement du joueur (#15 : niveaux de 10 s au plus)
	-- Bouton « 2x TRAINING! » (#119, Shared.TrainingBoost) : temps d'entraînement cumulé sur les séances du joueur
	BOOST_INTERVAL_MIN  = 12,     -- s d'entraînement entre deux apparitions, au moins… (25 avant #155)
	BOOST_INTERVAL_MAX  = 20,     -- … au plus (tiré au hasard ; compté après le bouton raté ou la fin du bonus ; 40 avant #155)
	BOOST_OFFER_TIME    = 3,      -- durée d'affichage du bouton (s, anneau de compte à rebours)
	BOOST_CLICK_SLACK   = 0.5,    -- clic encore accepté par le serveur après la fin de l'affichage (latence, s)
	BOOST_TIME          = 8,      -- durée du bonus (s ; s'arrête avec la séance ; 30 avant #155)
	BOOST_MULTIPLIER    = 2,      -- EXP par répétition (donc Throw Power) × 2 pendant le bonus, sans cumul

	-- CHANCE du lancer (le lancer ne rapporte pas d'argent : il fait gagner un mannequin de collection)
	CHANCE_PER_BONE     = 0.02,   -- + 2 % de chance par os cassé
	CHANCE_PER_SMASH    = 0.01,   -- + 1 % de chance par objet détruit
	SIZE_LUCK_POWER     = 0.5,    -- la taille (Big, Huge…) se tire à chance ^ 0,5 : moins poussée que la rareté

	-- Base : mannequins de collection posés sur des présentoirs, seule source d'argent
	INCOME_TICK         = 1,      -- versement du revenu de la base (s)
	SELL_MINUTES        = 2,      -- prix de vente d'un mannequin (stand SELL, inventaire) : 2 min de son revenu
	INVENTORY_MAX       = 200,    -- mannequins en stock au plus ; au-delà, le moins rentable est vendu d'office
	DISPLAY_START       = 8,      -- présentoirs d'une base neuve (6 avant #156, comme les 8 emplacements de jardin de 09)
	-- Présentoirs 9 à 30 (pad « 8 > 9 » devant la base), un achat de plus entre deux équipements ou mannequins à lancer :
	-- 9 à 11 vers 9, 21 et 47 min (prix des anciens 7 à 9), puis 12 à 30 de 69 min à 9,8 h (#156, joueur simulé)
	DISPLAY_PRICES      = { 450e3, 7e6, 70e6,
	                        220e6, 240e6, 260e6, 310e6, 660e6, 980e6, 1.2e9, 1.7e9, 2.2e9, 2.8e9,
	                        3.3e9, 4.6e9, 5.5e9, 8.4e9, 16e9, 20e9, 28e9, 51e9, 81e9 },

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
	MAX_FLIGHT_TIME     = 20,     -- garde-fou (s) : un vol de 4,4 B met 10 à 12 s jusqu'au bout des 6 km (#113 ; 22 s avant)
	KILL_Y              = -40,    -- mannequin tombé du parcours
	RESULT_MAX_TIME     = 20,     -- résultat et tirage : fin forcée si le client ne signale pas GO BACK (s, minimum ; plus long selon la rareté : Shared.RevealPlan.resultTime)
	RESULT_CLEAR_TIME   = 4.5,    -- mannequin d'un joueur parti pendant son résultat retiré après ce délai (s)
	SMASH_SPEED         = 7,      -- une caisse ou une brique qui dépasse cette vitesse compte comme détruite
}

return GameConfig
