-- Entraînement : l'avatar soulève un mannequin d'entraînement au-dessus de la tête ; chaque répétition donne 1 EXP qui
-- remplit la barre de niveau et met de côté la Throw Power de l'équipement, versée d'un coup au niveau franchi (popup
-- « LEVEL UP! », comme les jeux de référence 01 / 09).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Training = {}

export type Gear = {
	name: string,
	gain: number, -- Throw Power par répétition, versée au passage de niveau
	cost: number, -- prix d'achat (le premier est offert)
	color: Color3,
	material: Enum.Material,
	scale: number, -- taille du mannequin soulevé
}

-- Paliers d'équipement : prix ×6 à ×17, gain ×3 à ×4,5 par palier (réglés sur le rythme de Throw a Seed)
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
		gain = 3,
		cost = 100,
		color = Color3.fromRGB(150, 150, 155),
		material = Enum.Material.Slate,
		scale = 0.6,
	},
	{
		name = "Iron Dummy",
		gain = 10,
		cost = 1500,
		color = Color3.fromRGB(110, 115, 125),
		material = Enum.Material.DiamondPlate,
		scale = 0.65,
	},
	{
		name = "Gold Dummy",
		gain = 40,
		cost = 25000,
		color = Color3.fromRGB(255, 200, 40),
		material = Enum.Material.Foil,
		scale = 0.7,
	},
	{
		name = "Diamond Dummy",
		gain = 160,
		cost = 150000,
		color = Color3.fromRGB(120, 230, 255),
		material = Enum.Material.Glass,
		scale = 0.75,
	},
	{
		name = "Neon Dummy",
		gain = 700,
		cost = 2000000,
		color = Color3.fromRGB(255, 70, 200),
		material = Enum.Material.Neon,
		scale = 0.8,
	},
	{
		name = "Cosmic Dummy",
		gain = 3000,
		cost = 25000000,
		color = Color3.fromRGB(110, 60, 255),
		material = Enum.Material.ForceField,
		scale = 0.9,
	},
} :: { Gear }

-- `bank` : Throw Power mise de côté depuis le début du niveau (gain de l'équipement tenu à chaque répétition)
export type Progress = { level: number, reps: number, bank: number? }

-- Cette méthode permet de donner le nombre de répétitions qui remplit le niveau `level` lorsque la barre est affichée.
function Training.repsForLevel(level: number): number
	return math.ceil(GameConfig.LEVEL_BASE_REPS * GameConfig.LEVEL_REPS_GROWTH ^ (level - 1))
end

-- Cette méthode permet d'ajouter une répétition à la progression lorsque l'avatar en termine une ; renvoie la nouvelle
-- progression et true si un niveau vient d'être franchi.
function Training.addRep(progress: Progress): (Progress, boolean)
	local reps = progress.reps + 1
	if reps >= Training.repsForLevel(progress.level) then
		return { level = progress.level + 1, reps = 0 }, true
	end
	return { level = progress.level, reps = reps }, false
end

-- Cette méthode permet de donner la Throw Power d'un niveau `level` entièrement fait avec l'équipement du palier `tier`
-- (gain par répétition × répétitions du niveau) lorsque l'on estime le rythme de l'entraînement.
function Training.levelPower(tier: number, level: number): number
	return Training.gear(tier).gain * Training.repsForLevel(level)
end

-- Cette méthode permet de compter une répétition faite avec l'équipement du palier `tier` lorsque REP_TIME s'est écoulé ;
-- renvoie la progression (gain mis de côté) et la Throw Power versée : tout le niveau quand il est franchi, 0 sinon.
function Training.completeRep(progress: Progress, tier: number): (Progress, number)
	local nextProgress, leveled = Training.addRep(progress)
	local bank = (progress.bank or 0) + Training.gear(tier).gain
	if leveled then
		nextProgress.bank = 0
		return nextProgress, bank
	end
	nextProgress.bank = bank
	return nextProgress, 0
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
