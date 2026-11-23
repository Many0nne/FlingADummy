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

-- Entrée d'une base (#198) : deux piliers coiffés d'un linteau, au bout des clôtures de l'entrée ; chapeau sous le
-- linteau (nil : sans), bannières à la couleur de la place sur l'avant des piliers, étoiles lumineuses du linteau
-- (blanches sur un linteau doré : elles s'en détachent)
export type Gate = {
	pillar: Color3,
	lintel: Color3,
	star: Color3,
	cap: Color3?,
	height: number,
	width: number,
	banners: boolean,
}

BaseLook.GATES = {
	wood = {
		pillar = rgb(185, 130, 75),
		lintel = rgb(230, 185, 120),
		star = rgb(255, 215, 40),
		height = 10,
		width = 2,
		banners = false,
	},
	stone = {
		pillar = rgb(150, 152, 165),
		lintel = rgb(200, 202, 212),
		star = rgb(255, 215, 40),
		height = 11,
		width = 2.4,
		banners = false,
	},
	noble = {
		pillar = rgb(150, 152, 165),
		lintel = rgb(255, 200, 40),
		star = rgb(255, 255, 255),
		cap = rgb(255, 200, 40),
		height = 11.5,
		width = 2.6,
		banners = true,
	},
	gold = {
		pillar = rgb(255, 190, 30),
		lintel = rgb(255, 225, 90),
		star = rgb(255, 255, 255),
		cap = rgb(255, 245, 170),
		height = 12.5,
		width = 2.8,
		banners = true,
	},
} :: { [string]: Gate }

-- Épaisseur du linteau de l'entrée : fine, et entrée haute (#208), pour que le linteau ne masque pas le mannequin du
-- présentoir 1 (échelle 1 dégagée à hauteur de joueur et en plongée ; mesures dans la PR)
BaseLook.LINTEL_HEIGHT = 1.0
BaseLook.STAR_SPACING = 1.75 -- d'une étoile du linteau à la suivante (studs) : 0,3 stud d'écart entre deux
BaseLook.TOWER_RATIO = 2.5 -- hauteur d'une tour d'angle / hauteur des poteaux de la clôture

-- Palier visuel d'une base. `plot` : sol (nil = couleur de la place, en tapis) ; `gate` : entrée (GATES) ; `stars` :
-- étoiles sur le linteau de l'entrée (rang du palier, lisible de loin) ; `lanterns` : 0, 2 (entrée) ou 6 (entrée et
-- coins) ; `postLanterns` : en plus, une lanterne tous les N poteaux de clôture (nil : sans) ; `flowers` : massifs
-- fleuris le long des clôtures ; `bushes` : buissons voxel au bout des massifs ; `corners` : élément en hauteur aux
-- deux coins du fond (nil, "tree" : arbre voxel, "tower" : tour à la matière de la clôture, bannière et drapeau à la
-- couleur de la place) ; `flags` : drapeaux à la couleur de la place aux coins (au sommet des tours au fond) ;
-- `pedestal` : socle des présentoirs (nil : pierre claire) ; `collar` : bandeau autour du haut des socles (nil :
-- sans) ; `displays` : présentoirs achetés à partir desquels la base prend ce palier.
export type BaseTier = {
	name: string,
	displays: number,
	fence: string,
	plot: Color3?,
	gate: string,
	stars: number,
	lanterns: number,
	postLanterns: number?,
	flowers: boolean,
	bushes: boolean,
	corners: string?,
	flags: boolean,
	pedestal: Color3?,
	collar: Color3?,
}

-- Paliers par nombre de présentoirs (#156 : 8 au départ, jusqu'à 30) : Garden au premier achat (≈ 9 min), Stone vers
-- 70 min, Noble vers 2 h, Golden vers 4,5 h de jeu simulées (un palier par présentoir de 6 à 10 avant #156). Entourage
-- enrichi à chaque palier (#198, comme les jardins de 09 : lanternes sur les poteaux, buissons et arbres voxel).
BaseLook.BASE_TIERS = {
	{
		name = "Wood",
		displays = GameConfig.DISPLAY_START,
		fence = "wood",
		plot = rgb(175, 115, 65),
		gate = "wood",
		stars = 1,
		lanterns = 0,
		flowers = false,
		bushes = false,
		flags = false,
	},
	{
		name = "Garden",
		displays = 9,
		fence = "wood",
		plot = rgb(175, 115, 65),
		gate = "wood",
		stars = 2,
		lanterns = 2,
		flowers = true,
		bushes = true,
		flags = false,
	},
	{
		name = "Stone",
		displays = 12,
		fence = "stone",
		plot = rgb(205, 205, 215),
		gate = "stone",
		stars = 3,
		lanterns = 6,
		flowers = true,
		bushes = true,
		corners = "tree",
		flags = false,
	},
	{
		name = "Noble",
		displays = 18,
		fence = "stoneGold",
		plot = rgb(235, 200, 140),
		gate = "noble",
		stars = 4,
		lanterns = 6,
		postLanterns = 4,
		flowers = true,
		bushes = true,
		corners = "tower",
		flags = true,
		collar = rgb(255, 200, 40),
	},
	{
		name = "Golden",
		displays = 25,
		fence = "gold",
		plot = nil,
		gate = "gold",
		stars = 5,
		lanterns = 6,
		postLanterns = 2,
		flowers = true,
		bushes = true,
		corners = "tower",
		flags = true,
		pedestal = rgb(250, 245, 230),
		collar = rgb(255, 200, 40),
	},
} :: { BaseTier }

-- Cette méthode permet de donner les rangs (0 à `count`) des poteaux d'un tronçon de clôture qui portent une lanterne
-- lorsque le palier en met une tous les `every` poteaux : symétriques depuis les deux bouts, jamais aux bouts (coins
-- et entrée ont les leurs).
function BaseLook.lanternPosts(count: number, every: number?): { number }
	local posts = {}
	if not every or every < 1 then
		return posts
	end
	for i = 1, count - 1 do
		local fromEnd = math.min(i, count - i)
		if fromEnd % every == 0 then
			table.insert(posts, i)
		end
	end
	return posts
end

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

-- Cette méthode permet de donner le palier visuel `tier` de la base, sa clôture et son entrée lorsque l'on construit
-- la base.
function BaseLook.base(tier: number): (BaseTier, Fence, Gate)
	local look = BaseLook.BASE_TIERS[math.clamp(tier, 1, #BaseLook.BASE_TIERS)]
	return look, BaseLook.FENCES[look.fence], BaseLook.GATES[look.gate]
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
