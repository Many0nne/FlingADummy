-- Catalogue étendu des mannequins de collection (#94) : du contenu en masse sans dessiner de nouvelle pièce, comme les
-- variantes « Emerald », « Ruby », « Diamond » des plantes de Throw a Seed. Chaque mannequin généré croise une
-- **famille** (un modèle existant de Shared.DummyModels : ses pièces ajoutées, pièces masquées et effets) et une
-- **palette** (couleur du corps, teinte et matériau des pièces ajoutées, couleur des effets). Sa cote et son revenu
-- suivent une règle par rareté : en haut de chacune des raretés existantes (au-dessus des mannequins dessinés), puis
-- quatre raretés au-delà de Secret jusqu'à « 1 IN 100T » (« 1 IN 50Qa » en taille Giant). Les 21 mannequins dessinés (Shared.Collection) ne changent
-- pas, ni leurs identifiants (sauvegardes). Courbe chiffrée : docs/design.md, section « Progression longue ».
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DummyAura = require(Shared:WaitForChild("DummyAura"))
local DummyModels = require(Shared:WaitForChild("DummyModels"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local DummyFamilies = {}

local rgb = Color3.fromRGB
local M = Enum.Material

export type Palette = {
	name: string, -- préfixe du nom (« Ruby Hero Dummy »)
	body: Color3, -- couleur du corps
	accent: Color3, -- teinte vers laquelle tirent les pièces ajoutées et les pièces colorées du corps
	tint: number, -- part de la teinte dans la couleur des pièces ajoutées (0 : couleur d'origine, 1 : uniforme)
	material: Enum.Material?, -- matériau du corps
	accessoryMaterial: Enum.Material?, -- matériau des pièces ajoutées (sinon le leur)
	glow: Color3, -- couleur des effets repris de la famille (particules, lumière)
}

-- Palettes, de la plus simple (plastique uni des raretés basses) à la plus folle (néon, métal, glace des raretés
-- au-delà de Secret). Ni verre ni champ de force : invisibles dans les fenêtres (ViewportFrame).
-- Vérifiées en jeu (#96) : ni corps ni teinte des pièces blancs en néon ou en Foil pâle (le Bloom en fait une tache
-- blanche), glaces assez bleues pour se détacher du ciel.
-- stylua: ignore
DummyFamilies.PALETTES = {
	pink      = { name = "Pink",      body = rgb(255, 130, 195), accent = rgb(255, 80, 160),  tint = 0.6,  glow = rgb(255, 150, 210) },
	sky       = { name = "Sky",       body = rgb(120, 205, 255), accent = rgb(60, 150, 255),  tint = 0.6,  glow = rgb(170, 225, 255) },
	lime      = { name = "Lime",      body = rgb(175, 240, 70),  accent = rgb(90, 200, 40),   tint = 0.6,  glow = rgb(210, 255, 120) },
	tangerine = { name = "Tangerine", body = rgb(255, 160, 50),  accent = rgb(255, 110, 20),  tint = 0.6,  glow = rgb(255, 200, 110) },
	grape     = { name = "Grape",     body = rgb(160, 100, 235), accent = rgb(110, 60, 200),  tint = 0.6,  glow = rgb(200, 160, 255) },
	cherry    = { name = "Cherry",    body = rgb(235, 50, 70),   accent = rgb(170, 20, 40),   tint = 0.6,  glow = rgb(255, 120, 130) },
	emerald   = { name = "Emerald",   body = rgb(40, 205, 115),  accent = rgb(20, 140, 80),   tint = 0.75, glow = rgb(120, 255, 170), accessoryMaterial = M.SmoothPlastic },
	ruby      = { name = "Ruby",      body = rgb(225, 30, 65),   accent = rgb(150, 10, 40),   tint = 0.75, glow = rgb(255, 90, 120) },
	sapphire  = { name = "Sapphire",  body = rgb(45, 90, 235),   accent = rgb(25, 50, 170),   tint = 0.75, glow = rgb(120, 170, 255) },
	amber     = { name = "Amber",     body = rgb(255, 175, 35),  accent = rgb(220, 110, 10),  tint = 0.75, glow = rgb(255, 210, 100) },
	shadow    = { name = "Shadow",    body = rgb(45, 40, 60),    accent = rgb(150, 60, 255),  tint = 0.8,  glow = rgb(170, 90, 255),  accessoryMaterial = M.Neon },
	silver    = { name = "Silver",    body = rgb(200, 205, 215), accent = rgb(170, 175, 190), tint = 0.85, glow = rgb(235, 240, 255), material = M.Metal, accessoryMaterial = M.Metal },
	golden    = { name = "Golden",    body = rgb(255, 200, 45),  accent = rgb(255, 180, 30),  tint = 0.9,  glow = rgb(255, 230, 120), material = M.Foil, accessoryMaterial = M.Foil },
	frost     = { name = "Frost",     body = rgb(120, 200, 255), accent = rgb(80, 170, 255),  tint = 0.85, glow = rgb(200, 240, 255), material = M.Ice, accessoryMaterial = M.Ice },
	magma     = { name = "Magma",     body = rgb(255, 95, 30),   accent = rgb(255, 60, 20),   tint = 0.8,  glow = rgb(255, 150, 40),  material = M.CrackedLava },
	radiant   = { name = "Radiant",   body = rgb(255, 220, 100), accent = rgb(255, 215, 80),  tint = 0.85, glow = rgb(255, 245, 180), accessoryMaterial = M.Neon },
	angelic   = { name = "Angelic",   body = rgb(230, 225, 250), accent = rgb(255, 210, 90),  tint = 0.85, glow = rgb(255, 250, 220), accessoryMaterial = M.Foil },
	starlight = { name = "Starlight", body = rgb(255, 160, 235), accent = rgb(255, 120, 220), tint = 0.8,  glow = rgb(255, 190, 245), accessoryMaterial = M.Neon },
	nebula    = { name = "Nebula",    body = rgb(120, 60, 220),  accent = rgb(255, 110, 220), tint = 0.8,  glow = rgb(220, 140, 255), material = M.Foil, accessoryMaterial = M.Neon },
	aurora    = { name = "Aurora",    body = rgb(70, 235, 200),  accent = rgb(150, 110, 255), tint = 0.8,  glow = rgb(140, 255, 220), accessoryMaterial = M.Neon },
	plasma    = { name = "Plasma",    body = rgb(255, 50, 200),  accent = rgb(80, 220, 255),  tint = 0.85, glow = rgb(255, 120, 230), material = M.Neon, accessoryMaterial = M.Neon },
	prism     = { name = "Prism",     body = rgb(170, 215, 255), accent = rgb(255, 150, 240), tint = 0.75, glow = rgb(230, 200, 255), material = M.Ice, accessoryMaterial = M.Neon },
	quantum   = { name = "Quantum",   body = rgb(20, 230, 255),  accent = rgb(170, 90, 255),  tint = 0.8,  glow = rgb(140, 245, 255), material = M.Neon, accessoryMaterial = M.Neon },
	solar     = { name = "Solar",     body = rgb(255, 150, 20),  accent = rgb(255, 240, 80),  tint = 0.85, glow = rgb(255, 200, 60),  material = M.Neon, accessoryMaterial = M.Foil },
	omega     = { name = "Omega",     body = rgb(25, 20, 30),    accent = rgb(255, 40, 40),   tint = 0.9,  glow = rgb(255, 70, 50),   material = M.Metal, accessoryMaterial = M.Neon },
	infinite  = { name = "Infinite",  body = rgb(255, 245, 230), accent = rgb(255, 120, 40),  tint = 0.85, glow = rgb(255, 180, 90),  accessoryMaterial = M.Foil },
} :: { [string]: Palette }

-- Mannequins générés, par rareté (indice de Shared.Rarity) : famille (id d'un mannequin dessiné) × palette, du moins
-- rare au plus rare. Familles de la même rareté pour les raretés dessinées, puis les plus chargées au-delà de Secret.
-- stylua: ignore
DummyFamilies.PAIRS = {
	{ { "rookie", "pink" } },
	{ { "nerd", "tangerine" }, { "mint", "grape" },      { "biker", "cherry" } },
	{ { "ocean", "emerald" },  { "hero", "ruby" },       { "pilot", "sapphire" } },
	{ { "ice", "shadow" },     { "royal", "amber" },     { "toxic", "ruby" } },
	{ { "gold", "shadow" },    { "diamond", "ruby" },    { "lava", "frost" } },
	{ { "ghost", "magma" },    { "galaxy", "golden" },   { "neon", "frost" } },
	{ { "king", "shadow" },    { "void", "golden" },     { "cosmic", "magma" } },
	{ { "royal", "angelic" },  { "galaxy", "radiant" },  { "hero", "angelic" },   { "diamond", "radiant" }, { "ghost", "angelic" },  { "king", "radiant" } },
	{ { "hero", "starlight" }, { "galaxy", "nebula" },   { "ghost", "aurora" },   { "cosmic", "starlight" }, { "king", "nebula" },  { "void", "starlight" } },
	{ { "ice", "prism" },      { "royal", "aurora" },    { "neon", "plasma" },    { "diamond", "prism" },   { "void", "plasma" },   { "cosmic", "quantum" } },
	{ { "galaxy", "solar" },   { "ghost", "omega" },     { "neon", "infinite" },  { "void", "omega" },      { "cosmic", "infinite" }, { "king", "infinite" } },
} :: { { { string } } }

-- Cotes « 1 en n » des raretés au-delà de Secret (indice de Shared.Rarity → plus courant, plus rare) : les mannequins
-- générés s'y répartissent en progression géométrique. Les raretés dessinées placent les leurs au-dessus de leurs
-- mannequins dessinés, en dessous de la rareté suivante.
-- Deux décades par rareté, espacées de deux décades : « 1 IN 100T » au plus en taille normale, « 1 IN 50Qa » en Giant.
DummyFamilies.RANGES = {
	[8] = { 5e6, 1e8 },
	[9] = { 5e8, 1e10 },
	[10] = { 5e10, 1e12 },
	[11] = { 5e12, 1e14 },
} :: { [number]: { number } }

-- Cette méthode permet d'arrondir un nombre à 2 chiffres significatifs (au moins 1 ; entier si `integer`) lorsque l'on
-- génère une cote ou un revenu lisible (« 1 IN 3.2M », « $45K/s »).
function DummyFamilies.nice(x: number, integer: boolean?): number
	if x < 1 then
		return 1
	end
	-- Une cote sous 10 garde sa décimale (6.3) : le tirage essaie du plus rare au plus courant, deux cotes à moins de 1
	-- d'écart sortiraient aussi souvent l'une que l'autre
	local magnitude = 10 ^ (math.floor(math.log10(x)) - 1)
	if integer then
		magnitude = math.max(magnitude, 1)
	end
	if magnitude < 1 then
		local per = math.floor(1 / magnitude + 0.5) -- 6.3 exactement, pas 6.300000000000001
		return math.floor(x * per + 0.5) / per
	end
	return math.floor(x / magnitude + 0.5) * magnitude
end

-- Cette méthode permet de donner le revenu de la règle ($/s, taille normale) du `rank`-ième mannequin (par cote
-- croissante) des `count` de la rareté `rarity` lorsque l'on génère un mannequin : progression géométrique dans la
-- plage de revenu de la rareté (Shared.Rarity), du plus courant au plus rare.
function DummyFamilies.bandIncome(rarity: number, rank: number, count: number): number
	local band = Rarity.get(rarity).income
	local t = if count > 1 then (rank - 1) / (count - 1) else 0
	return DummyFamilies.nice(band[1] * (band[2] / band[1]) ^ t, true)
end

-- Cette méthode permet d'interpoler une valeur en échelle logarithmique entre deux points (`a` → `b`, `t` de 0 à 1)
-- lorsque l'on place une cote ou un revenu entre deux bornes.
local function geometric(a: number, b: number, t: number): number
	return a * (b / a) ^ t
end

export type Spec = { id: string, name: string, rarity: number, income: number, n: number }

-- Cette méthode permet de générer les mannequins (identifiant, nom, rareté, revenu, cote) à partir des mannequins
-- dessinés `drawn` (Shared.Collection) lorsque le catalogue se construit : n et revenu croissants, rareté par rareté.
function DummyFamilies.specs(drawn: { Spec }): { Spec }
	local byId: { [string]: Spec } = {}
	local tops: { [number]: Spec } = {}
	for _, dummy in drawn do
		byId[dummy.id] = dummy
		local top = tops[dummy.rarity]
		if not top or dummy.n > top.n then
			tops[dummy.rarity] = dummy
		end
	end
	-- Cette méthode permet de donner la cote du plus courant d'une rareté (début de sa plage au-delà de Secret, sinon son
	-- mannequin dessiné le plus courant) lorsque l'on place les générés de la rareté précédente.
	local function floorOf(rarity: number): number?
		local range = DummyFamilies.RANGES[rarity]
		if range then
			return DummyFamilies.nice(range[1])
		end
		local low: Spec? = nil
		for _, dummy in drawn do
			if dummy.rarity == rarity and (not low or dummy.n < low.n) then
				low = dummy
			end
		end
		return if low then low.n else nil
	end
	local drawnCount: { [number]: number } = {}
	for _, dummy in drawn do
		drawnCount[dummy.rarity] = (drawnCount[dummy.rarity] or 0) + 1
	end
	local result: { Spec } = {}
	for rarity, pairs in DummyFamilies.PAIRS do
		local count = #pairs
		local range = DummyFamilies.RANGES[rarity]
		for i, pair in pairs do
			local family, paletteId = pair[1], pair[2]
			local palette = DummyFamilies.PALETTES[paletteId]
			local base = byId[family]
			assert(base and palette, "DummyFamilies : famille ou palette inconnue " .. family .. "/" .. paletteId)
			local n
			if range then
				n = DummyFamilies.nice(geometric(range[1], range[2], (i - 1) / math.max(count - 1, 1)))
			else
				-- Entre le plus rare des dessinés de la rareté et le plus courant de la suivante, sans les toucher
				local top = tops[rarity]
				local nextN = floorOf(rarity + 1)
				assert(top and nextN, "DummyFamilies : rareté sans bornes " .. rarity)
				n = DummyFamilies.nice(geometric(top.n, nextN, i / (count + 1)))
			end
			-- Au-dessus des dessinés de la rareté (cotes plus hautes), dans la plage de revenu de la rareté
			local below = drawnCount[rarity] or 0
			local income = DummyFamilies.bandIncome(rarity, below + i, below + count)
			table.insert(result, {
				id = paletteId .. "_" .. family,
				name = palette.name .. " " .. base.name,
				rarity = rarity,
				income = income,
				n = n,
			})
		end
	end
	return result
end

-- Cette méthode permet de recolorer un effet repris de la famille (couleurs tirées vers la lueur de la palette)
-- lorsque l'on habille un mannequin généré.
local function recolor(effect: DummyModels.Effect, glow: Color3): DummyModels.Effect
	local copy = table.clone(effect)
	copy.color = effect.color:Lerp(glow, 0.8)
	if effect.color2 then
		copy.color2 = effect.color2:Lerp(glow, 0.5)
	end
	return copy
end

-- Cette méthode permet de construire le look d'un mannequin généré (famille `family` × palette `paletteId`) lorsque le
-- catalogue se construit ; corps à la palette, pièces et effets de la famille tirés vers sa teinte et sa lueur.
function DummyFamilies.look(family: string, paletteId: string): DummyModels.Look
	local base = DummyModels.LOOKS[family]
	local palette = DummyFamilies.PALETTES[paletteId]
	assert(base and palette, "DummyFamilies.look : famille ou palette inconnue " .. family .. "/" .. paletteId)
	local accessoryColors: { [string]: Color3 } = {}
	for _, name in base.accessories do
		local def = DummyModels.ADDONS[name]
		if def then
			accessoryColors[name] = def.color:Lerp(palette.accent, palette.tint)
		end
	end
	local pieceColors: { [string]: Color3 }? = nil
	if base.pieceColors then
		local colors: { [string]: Color3 } = {}
		for piece, color in base.pieceColors do
			colors[piece] = color:Lerp(palette.accent, palette.tint)
		end
		pieceColors = colors
	end
	local effects: { DummyModels.Effect } = {}
	for _, list in { base.effects or {}, DummyAura.THEMES[family] or {} } do
		for _, effect in list do
			table.insert(effects, recolor(effect, palette.glow))
		end
	end
	local look: any = {
		color = palette.body,
		material = palette.material,
		pieceColors = pieceColors,
		hidden = base.hidden,
		accessories = base.accessories,
		accessoryColors = accessoryColors,
		accessoryMaterial = palette.accessoryMaterial,
		effects = if #effects > 0 then effects else nil,
	}
	return look
end

-- Cette méthode permet de donner la famille et la palette d'un mannequin généré (`id` = « palette_famille ») lorsque
-- l'on construit son look ; nil pour un mannequin dessiné.
function DummyFamilies.parse(id: string): (string?, string?)
	local paletteId, family = string.match(id, "^(%a+)_(%a+)$")
	if paletteId and family and DummyFamilies.PALETTES[paletteId] and DummyModels.LOOKS[family] then
		return family, paletteId
	end
	return nil, nil
end

return DummyFamilies
