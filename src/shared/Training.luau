-- Entraînement : l'avatar soulève un mannequin d'entraînement au-dessus de la tête ; chaque répétition donne l'EXP de
-- l'équipement (« +4 EXP / répétition » de la référence 09) qui remplit la barre de niveau, et chaque niveau franchi
-- (popup « LEVEL UP! ») donne autant de Throw Power que l'EXP qu'il demandait : puissance gagnée = EXP gagnée.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DummyFamilies = require(Shared:WaitForChild("DummyFamilies"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Training = {}

export type Gear = {
	name: string,
	gain: number, -- EXP par répétition (devient de la Throw Power au passage de niveau)
	cost: number, -- prix d'achat (le premier est offert)
	color: Color3,
	material: Enum.Material,
	scale: number, -- taille du mannequin soulevé
}

-- Paliers d'équipement : gain ≈ ×4 à ×9 par palier (calés sur Throw a Seed, #129 :
-- 1K de puissance à 3 min, 100K à 12 min) ; prix calés par le joueur simulé (#15, tools/progression.luau) pour
-- un achat (équipement, mannequin à lancer ou présentoir) toutes les 1 à 5 min la première heure, puis de plus en plus
-- espacés, sans mur : le ratio « prix du suivant / revenu » ne double jamais d'un achat au suivant
Training.GEARS = {
	{
		name = "Wooden Dummy",
		gain = 1,
		cost = 0,
		color = Color3.fromRGB(190, 140, 90),
		material = Enum.Material.Wood,
		scale = 0.55,
	},
	{
		name = "Stone Dummy",
		gain = 6,
		cost = 100,
		color = Color3.fromRGB(150, 150, 155),
		material = Enum.Material.Slate,
		scale = 0.6,
	},
	{
		name = "Iron Dummy",
		gain = 45,
		cost = 8000,
		color = Color3.fromRGB(110, 115, 125),
		material = Enum.Material.DiamondPlate,
		scale = 0.65,
	},
	{
		name = "Gold Dummy",
		gain = 400,
		cost = 120000,
		color = Color3.fromRGB(255, 200, 40),
		material = Enum.Material.Foil,
		scale = 0.7,
	},
	{
		name = "Diamond Dummy",
		gain = 2200,
		cost = 800000,
		color = Color3.fromRGB(120, 230, 255),
		material = Enum.Material.Glass,
		scale = 0.75,
	},
	{
		name = "Neon Dummy",
		gain = 9000,
		cost = 1800000,
		color = Color3.fromRGB(255, 70, 200),
		material = Enum.Material.Neon,
		scale = 0.8,
	},
	{
		name = "Cosmic Dummy",
		gain = 35000,
		cost = 4500000,
		color = Color3.fromRGB(110, 60, 255),
		-- Foil, plus le champ de force : invisible au râtelier et en fenêtre (#118)
		material = Enum.Material.Foil,
		scale = 0.9,
	},
} :: { Gear }

-- Suite des équipements (#94) : gain × GAIN_STEP par palier depuis Cosmic, couleur et matériau d'une palette de
-- Shared.DummyFamilies, à la taille de Cosmic (0,9 : plus grand, le mannequin soulevé traverserait la tête,
-- AnimationData.TRAIN) ; prix calés par #15, Plasma recalé par #133 (le dernier, condition de la renaissance, vient
-- après la plupart des mannequins à lancer : courbe dans docs/design.md, section « Progression longue »). `color`
-- remplace la couleur de la palette : le Plasma passe au bleu électrique, le magenta de sa palette le confondait avec
-- le Neon (#118).
-- stylua: ignore
Training.EXTENDED = {
	{ palette = "ruby",     cost = 20e6 },
	{ palette = "emerald",  cost = 50e6 },
	{ palette = "plasma",   cost = 200e6, color = Color3.fromRGB(40, 110, 255) },
	{ palette = "omega",    cost = 1.8e9 },
	{ palette = "infinite", cost = 50e9 },
} :: { { palette: string, cost: number, color: Color3? } }
Training.GAIN_STEP = 4

do
	local last = Training.GEARS[#Training.GEARS]
	local gain, scale = last.gain, last.scale
	for _, spec in Training.EXTENDED do
		local palette = DummyFamilies.PALETTES[spec.palette]
		assert(palette, "Training : palette inconnue " .. spec.palette)
		gain = DummyFamilies.nice(gain * Training.GAIN_STEP)
		table.insert(Training.GEARS, {
			name = palette.name .. " Dummy",
			gain = gain,
			cost = spec.cost,
			color = spec.color or palette.body,
			material = palette.material or Enum.Material.SmoothPlastic,
			scale = scale,
		})
	end
end

-- `exp` : EXP accumulée dans le niveau en cours (barre « x / y »)
export type Progress = { level: number, exp: number }

-- Cette méthode permet de donner l'EXP du niveau `level` avec l'équipement `tier` (× LEVEL_EXP_GROWTH par niveau,
-- plafonnée à LEVEL_MAX_REPS répétitions, #15) lorsque la barre est affichée ou le niveau franchi.
function Training.expForLevel(level: number, tier: number?): number
	local needed = math.ceil(GameConfig.LEVEL_BASE_EXP * GameConfig.LEVEL_EXP_GROWTH ^ (level - 1))
	return math.min(needed, GameConfig.LEVEL_MAX_REPS * Training.gear(tier or 1).gain)
end

-- Cette méthode permet de compter une répétition faite avec l'équipement du palier `tier` lorsque REP_TIME s'est écoulé ;
-- renvoie la progression (EXP en trop reportée, plusieurs niveaux possibles) et la Throw Power des niveaux franchis.
-- `multiplier` : EXP de la répétition × multiplier (bonus « 2x TRAINING! », Shared.TrainingBoost ; 1 par défaut).
function Training.completeRep(progress: Progress, tier: number, multiplier: number?): (Progress, number)
	local level, exp, power = progress.level, progress.exp + Training.gear(tier).gain * (multiplier or 1), 0
	while exp >= Training.expForLevel(level, tier) do
		local needed = Training.expForLevel(level, tier)
		exp -= needed
		power += needed
		level += 1
	end
	return { level = level, exp = exp }, power
end

-- Cette méthode permet de donner le prix du palier suivant lorsque le joueur possède le palier `tier` ; nil au dernier.
function Training.nextGearCost(tier: number): number?
	local nextGear = Training.GEARS[tier + 1]
	return if nextGear then nextGear.cost else nil
end

-- Cette méthode permet de donner l'équipement du palier `tier` (borné) lorsque l'on affiche ou simule l'entraînement.
function Training.gear(tier: number): Gear
	return Training.GEARS[math.clamp(tier, 1, #Training.GEARS)]
end

return Training
