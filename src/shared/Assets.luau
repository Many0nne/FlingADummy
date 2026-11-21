-- Ids des assets publiés sur le compte propriétaire de l'expérience (sources : assets/dummy, Shared.AnimationData).
-- 0 = pas encore publié : le jeu se rabat sur les blocs du gabarit (mannequin) et, dans Studio seulement, sur les
-- clips construits à la volée (animations).
local Assets = {}

-- Maillages du mannequin : une MeshPart par pièce du gabarit (assets/dummy/export/dummy.fbx) et par pièce ajoutée des
-- modèles de collection (assets/dummy/export/collection.fbx, noms de Shared.DummyModels.ADDONS)
Assets.DUMMY_MESHES = {
	Torso = 133613233785754,
	Head = 86063091423662,
	LeftUpperArm = 114304624461467,
	LeftLowerArm = 106034197377217,
	RightUpperArm = 135967918758689,
	RightLowerArm = 90031260387163,
	LeftUpperLeg = 137052938845723,
	LeftLowerLeg = 119226912137255,
	RightUpperLeg = 88314334717160,
	RightLowerLeg = 80862197937671,
	-- Pièces ajoutées (modèle 108181194581833)
	biker_Helmet = 72603942987074,
	biker_HelmetStripe = 72593580889562,
	biker_Jacket = 85042081997354,
	biker_Rivets = 75445054811018,
	biker_Visor = 111031508865922,
	cosmic_CosmicMoons = 81209447936711,
	cosmic_GalaxyArmsA = 88503844117695,
	cosmic_GalaxyArmsB = 102488592747626,
	cosmic_GalaxyCore = 111150776289228,
	cosmic_GalaxyDisc = 101596805117750,
	cosmic_StarCrown = 133482983831534,
	diamond_Crystals = 79515566364798,
	diamond_FloatGem = 76095615417073,
	diamond_ShoulderGemL = 81205187289563,
	diamond_ShoulderGemR = 76666281035912,
	diamond_Tiara = 86999517929458,
	galaxy_LifePack = 72964417035895,
	galaxy_Moons = 95606263737588,
	galaxy_PackLights = 82182056397244,
	galaxy_PlanetRing = 109702940391996,
	galaxy_SpaceHelmet = 92244841608085,
	galaxy_SuitCollar = 75298972164922,
	ghost_GhostEyes = 73113760382289,
	ghost_GhostTail = 97274294494910,
	ghost_Lantern = 80372453727629,
	ghost_LanternFlame = 94654272792936,
	ghost_ShackleL = 100623916657455,
	ghost_ShackleR = 87784562066513,
	ghost_Wisps = 95236856060998,
	gold_CoinRing = 128355433596091,
	gold_GoldChain = 79254768235723,
	gold_HatTrim = 70822517618940,
	gold_MoneyBag = 86025014624815,
	gold_MoneyMark = 135612890162211,
	gold_TopHat = 77239574891547,
	hero_Cape = 117765756987403,
	hero_Emblem = 102698639077751,
	hero_EmblemDisc = 114428819648933,
	hero_Mask = 123208649816370,
	hero_MaskEyes = 124398959180561,
	ice_IceBootL = 140539542312676,
	ice_IceBootR = 123805574550304,
	ice_IceCrown = 88894329538215,
	ice_IceShoulderL = 72333200010509,
	ice_IceShoulderR = 77544654275062,
	ice_IceWings = 87475041070958,
	king_Crown = 79894126191951,
	king_CrownGems = 124315892817095,
	king_Ermine = 112279222928006,
	king_Robe = 78228488698481,
	king_Scepter = 124003952042474,
	king_ScepterGem = 92694779937186,
	king_SunHalo = 126655587375851,
	king_Throne = 90175106826221,
	king_ThroneCushion = 110771993938161,
	lava_BouldersL = 79130840514357,
	lava_BouldersR = 135650581333216,
	lava_Flames = 99860499896689,
	lava_HornTips = 82199327530156,
	lava_Horns = 121220409852946,
	lava_MagmaOrbit = 117941753670682,
	mint_Deck = 115291795657610,
	mint_Headphones = 120426589794026,
	mint_Wheels = 123760274794682,
	neon_CyberVisor = 91777380015455,
	neon_Mohawk = 98113518335387,
	neon_NeonLines = 136411107672317,
	neon_NeonPadL = 95466517207112,
	neon_NeonPadR = 131719088474131,
	neon_RingA = 94993901478858,
	neon_RingB = 100279951376620,
	nerd_Backpack = 123848055931840,
	nerd_BowTie = 137010022456891,
	nerd_Glasses = 82978768485533,
	nerd_Lenses = 108640423320925,
	ocean_DiveHelmet = 71063498009972,
	ocean_FlipperL = 83204922132276,
	ocean_FlipperR = 129635345448176,
	ocean_Portholes = 132997396107823,
	ocean_Tanks = 130750057221126,
	ocean_Valves = 95579402243452,
	pilot_AviatorCap = 89935223234998,
	pilot_GoggleLens = 111970022929900,
	pilot_Goggles = 117780844184592,
	pilot_Jetpack = 83907536245418,
	pilot_Scarf = 112401400868860,
	pilot_Wings = 129052897970058,
	rookie_FloatyL = 77542013180178,
	rookie_FloatyR = 114947179590302,
	rookie_Helmet = 128289280381744,
	royal_HelmSlit = 71390860000845,
	royal_KnightHelm = 97269842987698,
	royal_PauldronL = 87941329413562,
	royal_PauldronR = 102515581495385,
	royal_Plume = 81217204476493,
	royal_RoyalCape = 133534121428416,
	royal_ShieldFace = 102364658644901,
	royal_ShieldRim = 83181318603543,
	royal_Sword = 94978390413435,
	toxic_Barrel = 90644868422869,
	toxic_BarrelGoo = 92540477498867,
	toxic_GasMask = 138548115612629,
	toxic_MaskLenses = 102356630374072,
	toxic_Slime = 74028130900120,
	traffic_Cone = 131548208781044,
	traffic_ConeStripes = 111688873005621,
	traffic_Vest = 128859512624471,
	traffic_VestStripes = 137907726690005,
	void_Accretion = 91055940235879,
	void_VoidCore = 76163491197755,
	void_VoidCracks = 109443894240085,
	void_VoidEyes = 111925772390292,
	void_VoidHorns = 135862782262574,
	void_VoidShards = 107942316468581,
} :: { [string]: number }

-- Atlas (assets/dummy/export/dummy_atlas.png) : zones transparentes = couleur de la pièce, noir, cibles. Posé par
-- Shared.DummySurface (SurfaceAppearance) : changer aussi son ColorMap (un test vérifie qu'ils concordent)
Assets.DUMMY_TEXTURE = 84498910179411

-- Animations de l'avatar (assets/anim/export/<Nom>.rbxm)
Assets.ANIMATIONS = {
	Hold = 134156774546186,
	Train = 72035491380919,
	Throw = 98953473271707,
	Carry = 119120800969306,
} :: { [string]: number }

-- Icônes d'interface (assets/icons/export/<nom>.png, rendues par assets/icons/build_icons.py). 0 = pas encore
-- publiée : l'interface se rabat sur un emoji (UIKit.icon)
Assets.ICONS = {
	shop = 101689173634398,
	index = 116421262439716,
	dummies = 133877981616877,
	power = 131493315088212,
	cash = 137592441201082,
	arrow = 75483474828645,
	music = 120854274168520,
} :: { [string]: number }

-- Icônes des mannequins dans la barre d'outils (Backpack, #54), une par rareté (indice de Shared.Rarity) : buste du
-- mannequin à la couleur de la rareté (assets/icons/export/rarity<N>.png). 0 = pas encore publiée : la barre affiche
-- le nom du mannequin
Assets.RARITY_ICONS = {
	121103961543132,
	136941604812875,
	112130684550806,
	123056701284362,
	84656443866104,
	92332277678523,
	90361378631041,
} :: { number }

-- Icônes propres à chaque mannequin dans la barre d'outils (id de Shared.Collection → image) : buste tiré de son
-- aperçu (assets/icons/export/dummy_<id>.png, rendues par assets/icons/dummy_icons.py, #66). Absente : la barre se
-- rabat sur l'icône de rareté
Assets.DUMMY_ICONS = {
	crash = 75117156684238,
	rookie = 91496007428605,
	traffic = 139087297795175,
	mint = 98239130900546,
	biker = 124763321088624,
	nerd = 135624067143395,
	ocean = 73249684987387,
	hero = 135595863944604,
	pilot = 96291151732091,
	ice = 110856743810232,
	toxic = 84844069508364,
	royal = 99837358844655,
	gold = 107984916653684,
	lava = 92562583434996,
	diamond = 120237455060707,
	galaxy = 138779750456287,
	ghost = 107227277089764,
	neon = 105178381185614,
	king = 85935165508603,
	void = 124469685391140,
	cosmic = 124075369111069,
} :: { [string]: number }

-- Cette méthode permet de donner l'URI d'un asset publié lorsque l'on le charge ; nil s'il n'est pas publié.
function Assets.uri(id: number?): string?
	if not id or id == 0 then
		return nil
	end
	return "rbxassetid://" .. id
end

return Assets
