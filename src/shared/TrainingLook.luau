-- Look des mannequins d'entraînement (#118, retour de la sprint review 2 : « ceux de l'entraînement manquent de style »).
-- Chaque palier de Training Gear habille le corps de sa couleur et de son matériau (Shared.Training) avec une famille de
-- la collection (pièces ajoutées et effets de Shared.DummyModels, thème de Shared.DummyAura), tirée vers sa teinte comme
-- les mannequins générés (Shared.DummyFamilies), et une aura de rareté de plus en plus fournie aux hauts paliers.
-- Trois usages : soulevé par l'avatar (Client.CharacterPoser), suspendu au râtelier de l'appareil (Server.CourseBuilder,
-- sans particules ni pièces trop larges pour les crochets) et rendu dans les cartes du HUD (sans effets).
-- Logique pure (testée) : les modules qui construisent passent la déclinaison à Shared.DummyShape.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DummyAura = require(Shared:WaitForChild("DummyAura"))
local DummyModels = require(Shared:WaitForChild("DummyModels"))
local Training = require(Shared:WaitForChild("Training"))

local TrainingLook = {}

local rgb = Color3.fromRGB
local M = Enum.Material

-- Groupes de pièces d'une couleur secondaire (noms de Shared.DummyShape.PIECES), comme Shared.DummyFamilies.TRIMS
TrainingLook.TRIMS = {
	gloves = { "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg" },
} :: { [string]: { string } }

-- Look d'un palier : famille de la collection (`keep` : sous-ensemble de ses pièces ajoutées, nil : toutes), teinte
-- `accent` des pièces ajoutées (part `tint`), couleurs imposées à certaines pièces (`colors`), matériau des pièces
-- ajoutées, lueur des effets, aura (rareté de Shared.DummyAura.rarity, sans aura sous 3), gants et bottes (`trim`).
export type Look = {
	family: string,
	keep: { string }?,
	accent: Color3,
	tint: number,
	colors: { [string]: Color3 }?,
	accessoryMaterial: Enum.Material?,
	glow: Color3,
	aura: number,
	trim: Color3?,
}

-- Un look par palier de Training.GEARS, du bois à l'Infinite : familles toutes différentes, de la plus sobre (casque et
-- brassards du débutant) aux plus chargées (galaxie du Plasma, trou noir doré de l'Infinite), aucune paire famille ×
-- couleur déjà dans la collection.
TrainingLook.LOOKS = {
	-- Wooden : casque et brassards de débutant en bois sombre
	{
		family = "rookie",
		accent = rgb(125, 80, 45),
		tint = 0.75,
		accessoryMaterial = M.Wood,
		glow = rgb(255, 210, 150),
		aura = 0,
	},
	-- Stone : golem, cornes et rochers sur les épaules, gants et bottes de pierre sombre
	{
		family = "lava",
		keep = { "lava_Horns", "lava_HornTips", "lava_BouldersL", "lava_BouldersR" },
		accent = rgb(105, 108, 118),
		tint = 0.85,
		accessoryMaterial = M.Slate,
		glow = rgb(210, 210, 220),
		aura = 0,
		trim = rgb(95, 98, 108),
	},
	-- Iron : chevalier en acier, plumet, cape et écu rouges
	{
		family = "royal",
		accent = rgb(175, 180, 192),
		tint = 0.85,
		colors = {
			royal_Plume = rgb(225, 35, 45),
			royal_RoyalCape = rgb(200, 30, 40),
			royal_ShieldFace = rgb(200, 30, 40),
		},
		glow = rgb(220, 225, 235),
		aura = 0,
	},
	-- Gold : haut-de-forme, chaîne, anneau de pièces et sac d'or
	{ family = "gold", accent = rgb(255, 185, 30), tint = 0.3, glow = rgb(255, 225, 110), aura = 3 },
	-- Diamond : cristaux, gemme flottante et diadème
	{ family = "diamond", accent = rgb(80, 205, 255), tint = 0.35, glow = rgb(150, 240, 255), aura = 4 },
	-- Neon : cyber-armure, ailes et anneaux cyan sur corps magenta
	{
		family = "neon",
		accent = rgb(40, 235, 255),
		tint = 0.85,
		accessoryMaterial = M.Neon,
		glow = rgb(255, 110, 225),
		aura = 4,
	},
	-- Cosmic : scaphandre, anneau de planète et lunes, teintés violet et rose
	{ family = "galaxy", accent = rgb(205, 130, 255), tint = 0.45, glow = rgb(200, 150, 255), aura = 5 },
	-- Ruby : couronne, ailes et épaulières de cristal rouge, gants grenat
	{
		family = "ice",
		accent = rgb(255, 70, 105),
		tint = 0.85,
		glow = rgb(255, 90, 120),
		aura = 5,
		trim = rgb(140, 10, 40),
	},
	-- Emerald : héros à cape et masque d'or, gants vert sombre
	{
		family = "hero",
		accent = rgb(255, 195, 40),
		tint = 0.8,
		accessoryMaterial = M.Foil,
		glow = rgb(120, 255, 170),
		aura = 6,
		trim = rgb(15, 115, 65),
	},
	-- Plasma : disque de galaxie, couronne d'étoiles, armure et lunes d'énergie cyan sur corps bleu électrique
	{
		family = "cosmic",
		accent = rgb(90, 230, 255),
		tint = 0.85,
		accessoryMaterial = M.Neon,
		glow = rgb(110, 210, 255),
		aura = 6,
	},
	-- Omega : roi noir (sans trône) à couronne, sceptre et robe rouges, gants néon rouge
	{
		family = "king",
		keep = {
			"king_Crown",
			"king_CrownGems",
			"king_CrownSapphires",
			"king_CrownPearls",
			"king_Robe",
			"king_RobeTrim",
			"king_Ermine",
			"king_ErmineSpots",
			"king_Scepter",
			"king_ScepterGem",
			"king_SunHalo",
		},
		accent = rgb(255, 40, 40),
		tint = 0.85,
		glow = rgb(255, 70, 50),
		aura = 7,
		trim = rgb(255, 45, 35),
	},
	-- Infinite : trou noir d'or (cœur, anneaux d'accrétion, couronne, ailes et éclats dorés), gants d'or
	{
		family = "void",
		accent = rgb(255, 165, 45),
		tint = 0.85,
		accessoryMaterial = M.Foil,
		glow = rgb(255, 180, 90),
		aura = 8,
		trim = rgb(255, 190, 40),
	},
} :: { Look }

-- Au râtelier, les mannequins pendent à 2,1 studs l'un de l'autre (échelle 0,5) : les pièces ajoutées plus larges que
-- ça à l'échelle 1 (ailes, disques, lunes) déborderaient sur le voisin
TrainingLook.RACK_WIDTH = 4.2

-- Aura à partir de laquelle un mannequin d'entraînement a des effets (thème de sa famille et aura de rareté)
TrainingLook.FX_AURA = 3

-- Cette méthode permet de recolorer un effet repris de la famille (couleurs tirées vers la lueur du palier) lorsque l'on
-- construit la déclinaison d'un mannequin d'entraînement.
local function recolor(effect: DummyModels.Effect, glow: Color3): DummyModels.Effect
	local copy = table.clone(effect)
	copy.color = effect.color:Lerp(glow, 0.8)
	if effect.color2 then
		copy.color2 = effect.color2:Lerp(glow, 0.5)
	end
	return copy
end

-- Cette méthode permet de donner le look du palier `tier` (borné) lorsque l'on habille un mannequin d'entraînement.
function TrainingLook.look(tier: number): Look
	return TrainingLook.LOOKS[math.clamp(tier, 1, #TrainingLook.LOOKS)]
end

-- Cette méthode permet de donner la déclinaison (Shared.DummyShape.Variant) du mannequin d'entraînement du palier `tier`
-- lorsque l'on le construit : `mode` « lifted » (soulevé : effets sauf ceux posés au sol, sans particules si `still`,
-- mouvement réduit), « rack » (suspendu : lumières seulement, sans pièces trop larges) ou « viewport » (sans effets) ;
-- aucun effet sous FX_AURA.
function TrainingLook.variant(tier: number, mode: string, still: boolean?): { [string]: any }
	local gear = Training.gear(tier)
	local look = TrainingLook.look(tier)
	local base = DummyModels.LOOKS[look.family]
	assert(base, "TrainingLook : famille inconnue " .. look.family)
	local accessories: { string } = {}
	local accessoryColors: { [string]: Color3 } = {}
	for _, name in look.keep or base.accessories do
		local def = DummyModels.ADDONS[name]
		if def and not (mode == "rack" and def.size.X > TrainingLook.RACK_WIDTH) then
			table.insert(accessories, name)
			accessoryColors[name] = (look.colors or {})[name] or def.color:Lerp(look.accent, look.tint)
		end
	end
	local pieceColors: { [string]: Color3 }? = nil
	if base.pieceColors or look.trim then
		local colors: { [string]: Color3 } = {}
		for piece, color in base.pieceColors or {} do
			colors[piece] = color:Lerp(look.accent, look.tint)
		end
		if look.trim then
			for _, piece in TrainingLook.TRIMS.gloves do
				colors[piece] = look.trim
			end
		end
		pieceColors = colors
	end
	local effects: { DummyModels.Effect } = {}
	-- Effets dès l'or (aura de rareté) : les premiers paliers restent sobres, la progression se voit
	if mode ~= "viewport" and look.aura >= TrainingLook.FX_AURA then
		local all: { DummyModels.Effect } = {}
		for _, list in { base.effects or {}, DummyAura.THEMES[look.family] or {} } do
			for _, effect in list do
				table.insert(all, recolor(effect, look.glow))
			end
		end
		for _, effect in DummyAura.rarity(look.aura, look.glow) do
			table.insert(all, effect)
		end
		-- Suspendu ou soulevé, le mannequin est loin du sol : ni onde, ni flaque, ni colonne de lumière
		local quiet = mode == "rack" or still == true
		for _, effect in all do
			if not DummyAura.isGrounded(effect) and not (quiet and effect.kind ~= "light") then
				table.insert(effects, effect)
			end
		end
	end
	return {
		color = gear.color,
		material = if gear.material == M.SmoothPlastic then nil else gear.material,
		pieceColors = pieceColors,
		hidden = base.hidden,
		accessories = accessories,
		accessoryColors = accessoryColors,
		accessoryMaterial = look.accessoryMaterial,
		effects = if #effects > 0 then effects else nil,
	}
end

return TrainingLook
