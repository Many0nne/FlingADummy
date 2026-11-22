-- Progression visible depuis le hub (#61, #91, #92), comme les jardins et barres de 01 / 09 : la base change d'aspect à
-- chaque présentoir acheté (clôture bois → pierre → métal doré, sol, décor), l'appareil d'entraînement s'habille aux
-- couleurs du Training Gear acheté, et un texte flottant au-dessus de la base donne nom, revenu, Throw Power et
-- renaissances.
-- Logique pure (testée) : Server.CourseBuilder construit d'après ces paliers.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Rebirth = require(Shared:WaitForChild("Rebirth"))
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
-- aux quatre coins ; `arch` : arche d'entrée à la couleur de la place ; `displays` : présentoirs achetés à partir
-- desquels la base prend ce palier.
export type BaseTier = {
	name: string,
	displays: number,
	fence: string,
	plot: Color3?,
	lanterns: number,
	flowers: boolean,
	flags: boolean,
	arch: boolean,
}

-- Paliers par nombre de présentoirs (#156 : 8 au départ, jusqu'à 30) : Garden au premier achat (≈ 9 min), Stone vers
-- 70 min, Noble vers 2 h, Golden vers 4,5 h de jeu simulées (un palier par présentoir de 6 à 10 avant #156)
BaseLook.BASE_TIERS = {
	{
		name = "Wood",
		displays = 8,
		fence = "wood",
		plot = rgb(175, 115, 65),
		lanterns = 0,
		flowers = false,
		flags = false,
		arch = false,
	},
	{
		name = "Garden",
		displays = 9,
		fence = "wood",
		plot = rgb(175, 115, 65),
		lanterns = 2,
		flowers = true,
		flags = false,
		arch = false,
	},
	{
		name = "Stone",
		displays = 12,
		fence = "stone",
		plot = rgb(205, 205, 215),
		lanterns = 6,
		flowers = true,
		flags = false,
		arch = false,
	},
	{
		name = "Noble",
		displays = 18,
		fence = "stoneGold",
		plot = rgb(235, 200, 140),
		lanterns = 6,
		flowers = true,
		flags = true,
		arch = false,
	},
	{
		name = "Golden",
		displays = 25,
		fence = "gold",
		plot = nil,
		lanterns = 6,
		flowers = true,
		flags = true,
		arch = true,
	},
} :: { BaseTier }

-- Habillage de l'appareil d'entraînement : planches du podium (deux tons), montants et marches du râtelier, socle (nil :
-- pierre claire), couleur des pièces ajoutées (`accent`), liseré lumineux (néon, nil : sans), étincelles autour du
-- râtelier, pièces ajoutées du palier et de tous les précédents (`pieces`, noms de STATION_PIECES)
export type StationLook = {
	gear: string,
	plank: Color3,
	plankAlt: Color3,
	post: Color3,
	postDark: Color3,
	base: Color3?,
	accent: Color3,
	glow: Color3?,
	sparkle: boolean,
	pieces: { [string]: boolean },
}

-- Pièces ajoutées à l'appareil (#118, retour de la sprint review 2 : « pas juste changer de couleur ») : chaque palier
-- ajoute la sienne à celles des précédents, la plus riche au dernier (palier = rang dans la liste + 1, le bois n'a rien).
-- Pièces en métal, en or ou en pierre à leur couleur ; cristaux, néons, gemmes, éclairs et halo à la couleur du palier.
BaseLook.STATION_PIECES = {
	"plinths", -- Stone : socles de pierre au pied des montants
	"rivets", -- Iron : frettes et rivets de fer sur les montants
	"finials", -- Gold : pommeaux dorés sur les montants, bandeau doré sur la traverse
	"crystals", -- Diamond : grappes de cristaux sur le podium
	"tubes", -- Neon : tubes néon sur les montants, liseré néon (bordure du podium, sous la traverse)
	"orbit", -- Cosmic : planète annelée et étoiles au-dessus de la traverse
	"gems", -- Ruby : gemmes serties dans la traverse et les socles
	"crest", -- Emerald : blason à gemme au centre de la traverse
	"arcs", -- Plasma : éclairs entre pommeaux et étoiles, lumière
	"halo", -- Omega : halo derrière la planète, pointes de couronne sur les montants
	"aura", -- Infinite : anneau lumineux au sol, colonnes de lumière aux coins
}

-- Tons de l'appareil par palier : couleur des pièces ajoutées, et tons qui remplacent ceux dérivés de la couleur du
-- mannequin quand ils se confondraient (Diamond et Infinite clairs comme la pierre de loin, #118)
-- stylua: ignore
BaseLook.STATION_TONES = {
	{ accent = rgb(120, 75, 40) },                                                -- Wooden
	{ accent = rgb(120, 122, 132) },                                              -- Stone
	{ accent = rgb(190, 195, 205) },                                              -- Iron
	{ accent = rgb(255, 215, 60),  plankAlt = rgb(255, 165, 25) },                -- Gold
	{ accent = rgb(140, 245, 255), plank = rgb(60, 190, 255), plankAlt = rgb(150, 235, 255), base = rgb(25, 90, 190) }, -- Diamond
	{ accent = rgb(255, 95, 225) },                                               -- Neon
	{ accent = rgb(200, 150, 255) },                                              -- Cosmic
	{ accent = rgb(255, 60, 95) },                                                -- Ruby
	{ accent = rgb(70, 255, 160) },                                               -- Emerald
	{ accent = rgb(90, 225, 255) },                                               -- Plasma
	{ accent = rgb(255, 45, 35),   base = rgb(70, 12, 18) },                      -- Omega
	{ accent = rgb(255, 130, 20),  plank = rgb(255, 245, 230), plankAlt = rgb(255, 190, 55), post = rgb(255, 195, 60), postDark = rgb(235, 125, 30), base = rgb(255, 175, 40) }, -- Infinite
} :: { { [string]: Color3 } }

-- Cette méthode permet de donner une teinte plus sombre (facteur < 1) ou plus claire (> 1) d'une couleur lorsque l'on
-- dérive les tons de l'appareil d'entraînement de la couleur de l'équipement.
local function shade(color: Color3, factor: number): Color3
	return Color3.new(math.min(color.R * factor, 1), math.min(color.G * factor, 1), math.min(color.B * factor, 1))
end

-- Cette méthode permet de donner le palier visuel de la base lorsque son propriétaire a acheté jusqu'à `displays`
-- présentoirs : le plus haut dont le seuil est atteint (1 en dessous du premier, sans données).
function BaseLook.baseTier(displays: number?): number
	local count = math.floor(displays or GameConfig.DISPLAY_START)
	local tier = 1
	for index, look in BaseLook.BASE_TIERS do
		if count >= look.displays then
			tier = index
		end
	end
	return tier
end

-- Cette méthode permet de donner le palier visuel `tier` de la base et sa clôture lorsque l'on construit la base.
function BaseLook.base(tier: number): (BaseTier, Fence)
	local look = BaseLook.BASE_TIERS[math.clamp(tier, 1, #BaseLook.BASE_TIERS)]
	return look, BaseLook.FENCES[look.fence]
end

-- Cette méthode permet de donner l'habillage de l'appareil d'entraînement lorsque son propriétaire possède le Training
-- Gear du palier `tier` (couleur du mannequin acheté, pièces ajoutées des paliers atteints ; liseré néon dès le Neon,
-- étincelles dès le Diamond).
function BaseLook.station(tier: number): StationLook
	local clamped = math.clamp(tier, 1, #Training.GEARS)
	local gear = Training.GEARS[clamped]
	local tones = BaseLook.STATION_TONES[clamped]
	local pieces = {}
	for index, name in BaseLook.STATION_PIECES do
		pieces[name] = index < clamped
	end
	return {
		gear = gear.name,
		plank = tones.plank or gear.color,
		plankAlt = tones.plankAlt or shade(gear.color, 1.18),
		post = tones.post or shade(gear.color, 0.92),
		postDark = tones.postDark or shade(gear.color, 0.7),
		base = tones.base,
		accent = tones.accent,
		glow = if pieces.tubes then tones.accent else nil,
		sparkle = clamped >= 5,
		pieces = pieces,
	}
end

-- Cette méthode permet de donner les paliers des trois mannequins suspendus au râtelier lorsque le propriétaire
-- possède le palier `tier` : les trois derniers paliers (1, 2, 3 tant qu'il en possède moins de 3), le sien au bout.
function BaseLook.rackTiers(tier: number): { number }
	local last = math.clamp(math.max(tier, 3), 3, #Training.GEARS)
	return { last - 2, last - 1, last }
end

-- Texte flottant au-dessus d'une base : nom (« MANYONNE'S BASE »), revenu (« $223/s »), record (« 🏆 BEST 3.6 km »,
-- #44 : vu de tous) et Throw Power (« 💪 1.2K »)
export type Label = { title: string, income: string, best: string, power: string }

-- Taille du texte flottant : en studs plus une marge en pixels (lisible de loin), bornée en largeur (#150) pour que
-- les textes des bases voisines (48 studs d'un centre à l'autre, Shared.CourseLayout.BASE_PITCH) ne se chevauchent pas
BaseLook.LABEL_STUDS = Vector2.new(14, 9.4)
BaseLook.LABEL_PIXELS = Vector2.new(110, 82)
BaseLook.LABEL_SPAN = 44 -- largeur maximale (studs, à la distance du texte) : 4 studs d'écart entre deux textes

-- Cette méthode permet de donner la taille en pixels du texte flottant d'une base vu à la profondeur `depth` (studs)
-- par une caméra de `unit` pixels par stud à 1 stud, lorsque le client l'ajuste à chaque image (#150).
function BaseLook.labelPixels(depth: number, unit: number): Vector2
	local perStud = unit / math.max(depth, 1)
	local size = BaseLook.LABEL_STUDS * perStud + BaseLook.LABEL_PIXELS
	local cap = BaseLook.LABEL_SPAN * perStud
	if size.X > cap then
		size *= cap / size.X
	end
	return size
end

-- Cette méthode permet de savoir si deux étiquettes (centre et taille à l'écran, en pixels) se chevauchent lorsque le
-- client masque l'étiquette d'un mannequin posé qui passerait devant le texte d'une base (#150).
function BaseLook.overlaps(centerA: Vector2, sizeA: Vector2, centerB: Vector2, sizeB: Vector2): boolean
	local gap = (centerA - centerB)
	local reach = (sizeA + sizeB) / 2
	return math.abs(gap.X) < reach.X and math.abs(gap.Y) < reach.Y
end

BaseLook.VIP_HEX = "FFC828" -- badge VIP doré du texte flottant (passe VIP de la boutique Robux)

-- Cette méthode permet de donner les lignes du texte flottant d'une base lorsque son propriétaire ou ses valeurs
-- changent ; `owner` nil : base vide ; `power` nil (données pas chargées) : ligne vide ; `rebirths` > 0 : compteur
-- violet « 🌟 3 » à côté de la Throw Power (ligne en RichText) ; `best` sous 1 m ou nil : pas de ligne de record ;
-- `vip` (passe VIP, #160) : badge « VIP » doré devant le titre (ligne en RichText).
function BaseLook.label(
	owner: string?,
	income: number?,
	power: number?,
	rebirths: number?,
	best: number?,
	vip: boolean?
): Label
	if not owner then
		return { title = "EMPTY BASE", income = "$0/s", best = "", power = "" }
	end
	local powerText = if power then "💪 " .. Format.short(math.max(0, power)) else ""
	if power and rebirths and rebirths >= 1 then
		powerText ..= string.format('  <font color="#%s">🌟 %d</font>', Rebirth.COLOR_HEX, math.floor(rebirths))
	end
	return {
		title = (if vip then string.format('<font color="#%s">VIP</font> ', BaseLook.VIP_HEX) else "") .. string.upper(
			owner
		) .. "'S BASE",
		income = Format.money(math.max(0, income or 0)) .. "/s",
		best = if best and best >= 1 then "🏆 BEST " .. Format.distance(best) else "",
		power = powerText,
	}
end

return BaseLook
