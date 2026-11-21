-- Progression visible depuis le hub (#61, #91, #92), comme les jardins et barres de 01 / 09 : la base change d'aspect à
-- chaque présentoir acheté (clôture bois → pierre → métal doré, sol, décor), l'appareil d'entraînement s'habille aux
-- couleurs du Training Gear acheté, et un texte flottant au-dessus de la base donne nom, revenu et Throw Power.
-- Logique pure (testée) : Server.CourseBuilder construit d'après ces paliers.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Training = require(Shared:WaitForChild("Training"))

local BaseLook = {}

local rgb = Color3.fromRGB

-- Clôture d'une base : poteaux (hauteur, couleur), lisses, chapeau des poteaux (nil : sans), poteaux qui scintillent
export type Fence = {
	post: Color3,
	rail: Color3,
	cap: Color3?,
	height: number,
	width: number,
	shine: boolean,
}

BaseLook.FENCES = {
	wood = { post = rgb(185, 130, 75), rail = rgb(230, 185, 120), height = 4.4, width = 1.4, shine = false },
	stone = { post = rgb(150, 152, 165), rail = rgb(200, 202, 212), height = 5.2, width = 1.8, shine = false },
	stoneGold = {
		post = rgb(150, 152, 165),
		rail = rgb(200, 202, 212),
		cap = rgb(255, 200, 40),
		height = 5.2,
		width = 1.8,
		shine = false,
	},
	gold = {
		post = rgb(255, 190, 30),
		rail = rgb(255, 225, 90),
		cap = rgb(255, 245, 170),
		height = 6,
		width = 1.8,
		shine = true,
	},
} :: { [string]: Fence }

BaseLook.RAIL_RATIO = 0.57 -- largeur des lisses / largeur des poteaux (en retrait : pas de faces coplanaires)
BaseLook.CAP_HEIGHT = 0.6 -- épaisseur du chapeau d'un poteau
BaseLook.CAP_OVERHANG = 0.2 -- débord du chapeau de chaque côté du poteau

-- Cette méthode permet de donner la hauteur du haut d'un poteau (chapeau compris) lorsque l'on y pose une lanterne.
function BaseLook.postTop(fence: Fence): number
	return fence.height + (if fence.cap then BaseLook.CAP_HEIGHT else 0)
end

-- Palier visuel d'une base. `plot` : sol (nil = couleur de la place, en tapis) ; `lanterns` : 0, 2 (entrée) ou
-- 6 (entrée et coins) ; `flowers` : massifs fleuris le long des clôtures ; `flags` : drapeaux à la couleur de la place
-- aux quatre coins ; `arch` : arche d'entrée à la couleur de la place.
export type BaseTier = {
	name: string,
	fence: string,
	plot: Color3?,
	lanterns: number,
	flowers: boolean,
	flags: boolean,
	arch: boolean,
}

-- Un palier par présentoir acheté (6 au départ : palier 1 ; 10 : palier 5)
BaseLook.BASE_TIERS = {
	{
		name = "Wood",
		fence = "wood",
		plot = rgb(175, 115, 65),
		lanterns = 0,
		flowers = false,
		flags = false,
		arch = false,
	},
	{
		name = "Garden",
		fence = "wood",
		plot = rgb(175, 115, 65),
		lanterns = 2,
		flowers = true,
		flags = false,
		arch = false,
	},
	{
		name = "Stone",
		fence = "stone",
		plot = rgb(205, 205, 215),
		lanterns = 6,
		flowers = true,
		flags = false,
		arch = false,
	},
	{
		name = "Noble",
		fence = "stoneGold",
		plot = rgb(235, 200, 140),
		lanterns = 6,
		flowers = true,
		flags = true,
		arch = false,
	},
	{ name = "Golden", fence = "gold", plot = nil, lanterns = 6, flowers = true, flags = true, arch = true },
} :: { BaseTier }

-- Habillage de l'appareil d'entraînement : planches du podium (deux tons), montants et marches du râtelier, liseré
-- lumineux (néon, nil : sans), étincelles autour du râtelier
export type StationLook = {
	gear: string,
	plank: Color3,
	plankAlt: Color3,
	post: Color3,
	postDark: Color3,
	glow: Color3?,
	sparkle: boolean,
}

-- Cette méthode permet de donner une teinte plus sombre (facteur < 1) ou plus claire (> 1) d'une couleur lorsque l'on
-- dérive les tons de l'appareil d'entraînement de la couleur de l'équipement.
local function shade(color: Color3, factor: number): Color3
	return Color3.new(math.min(color.R * factor, 1), math.min(color.G * factor, 1), math.min(color.B * factor, 1))
end

-- Cette méthode permet de donner le palier visuel de la base lorsque son propriétaire a acheté jusqu'à `displays`
-- présentoirs (borné : DISPLAY_START et moins → 1, maximum → dernier palier).
function BaseLook.baseTier(displays: number?): number
	local count = displays or GameConfig.DISPLAY_START
	return math.clamp(math.floor(count) - GameConfig.DISPLAY_START + 1, 1, #BaseLook.BASE_TIERS)
end

-- Cette méthode permet de donner le palier visuel `tier` de la base et sa clôture lorsque l'on construit la base.
function BaseLook.base(tier: number): (BaseTier, Fence)
	local look = BaseLook.BASE_TIERS[math.clamp(tier, 1, #BaseLook.BASE_TIERS)]
	return look, BaseLook.FENCES[look.fence]
end

-- Cette méthode permet de donner l'habillage de l'appareil d'entraînement lorsque son propriétaire possède le Training
-- Gear du palier `tier` (couleur du mannequin acheté ; liseré néon dès le Neon, étincelles dès le Diamond).
function BaseLook.station(tier: number): StationLook
	local clamped = math.clamp(tier, 1, #Training.GEARS)
	local gear = Training.GEARS[clamped]
	return {
		gear = gear.name,
		plank = gear.color,
		plankAlt = shade(gear.color, 1.18),
		post = shade(gear.color, 0.92),
		postDark = shade(gear.color, 0.7),
		glow = if clamped >= 6 then shade(gear.color, 1.3) else nil,
		sparkle = clamped >= 5,
	}
end

-- Cette méthode permet de donner les paliers des trois mannequins suspendus au râtelier lorsque le propriétaire
-- possède le palier `tier` : les trois derniers paliers (1, 2, 3 tant qu'il en possède moins de 3), le sien au bout.
function BaseLook.rackTiers(tier: number): { number }
	local last = math.clamp(math.max(tier, 3), 3, #Training.GEARS)
	return { last - 2, last - 1, last }
end

-- Texte flottant au-dessus d'une base : nom (« MANYONNE'S BASE »), revenu (« $223/s ») et Throw Power (« 💪 1.2K »)
export type Label = { title: string, income: string, power: string }

-- Cette méthode permet de donner les trois lignes du texte flottant d'une base lorsque son propriétaire ou ses
-- valeurs changent ; `owner` nil : base vide ; `power` nil (données pas chargées) : ligne vide.
function BaseLook.label(owner: string?, income: number?, power: number?): Label
	if not owner then
		return { title = "EMPTY BASE", income = "$0/s", power = "" }
	end
	return {
		title = string.upper(owner) .. "'S BASE",
		income = Format.money(math.max(0, income or 0)) .. "/s",
		power = if power then "💪 " .. Format.short(math.max(0, power)) else "",
	}
end

return BaseLook
