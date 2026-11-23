-- Mise en scène du tirage selon la rareté du mannequin gagné (#67) : la révélation monte en spectacle par paliers,
-- jusqu'à la séquence complète du secret de la référence 09 (vidéo du testeur : silhouette et cote qui grimpe, écran
-- noir et phrase lettre à lettre, décor dédié, portail, pluie de pièces, « SECRET!! » et cote complète).
--   1. Common / Uncommon : révélation vive (éclair, éclat, son).
--   2. Rare / Epic : la silhouette hésite entre 2 ou 3 formes pendant le roulement, cote qui grimpe, confettis de la
--      couleur de la rareté.
--   3. Legendary / Mythic : ciel qui s'assombrit, rayons et colonne de lumière sur la silhouette, long roulement,
--      explosion de particules, forte secousse.
--   4. Secret et au-delà (Divine … Infinity, #94) : palier 3, puis séquence complète (CINEMATIC).
-- Pendant le suspense, ciel, rayons et contour suivent le palier affiché (cote atteinte), jamais la rareté gagnée
-- (#201 : teaseCues). Le rythme aussi (#204) : chaque montée de la cote et chaque arrêt prennent le palier du candidat
-- visé (`climbFactor`, `pause`) ; seuls le roulement et la séquence du secret, une fois la cote finale affichée,
-- dépendent de la rareté gagnée. Le tirage ne se passe pas (#197) : seuls GO BACK et THROW AGAIN, à la fin, rendent la
-- main.
-- Logique pure (paliers, durées, hésitation, phrase, annonce serveur, délai de fin forcée, rareté forcée en Studio) ;
-- la mise en scène est dans Client.Prize et Client.RevealFx.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local DummyFamilies = require(Shared:WaitForChild("DummyFamilies"))
local DummyModels = require(Shared:WaitForChild("DummyModels"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local RevealPlan = {}

export type Tier = {
	name: string,
	climbFactor: number, -- multiplie la durée d'une montée de la cote vers un candidat de ce palier (Collection.climbTime)
	pause: number, -- arrêt sur un candidat de ce palier, une fois atteint (s)
	drumroll: number, -- roulement avant la révélation, rareté gagnée (s)
	forms: number, -- formes entre lesquelles la silhouette hésite pendant le roulement, gagnant compris (0 : aucune)
	confetti: number, -- confettis de la couleur de la rareté à la révélation
	darkSky: boolean, -- ciel qui s'assombrit dès la silhouette
	rays: boolean, -- rayons et colonne de lumière sur la silhouette
	explosion: boolean, -- explosion de particules à la révélation
	shake: number, -- secousse de la caméra à la révélation
	cinematic: boolean, -- séquence complète du secret (CINEMATIC)
	autoClose: number, -- GO BACK automatique après la révélation (s)
}

-- Effets du suspense pour le palier affiché (#201) : rareté affichée, couleur du contour, ciel, rayons
export type Cues = { rarity: number, outline: Color3, darkSky: boolean, rays: boolean }

-- Rythme d'un palier du suspense (#204) : montée de la cote, arrêt une fois atteint, instant où il est atteint (s)
export type Pace = { climb: number, pause: number, reached: number }

export type Step = { name: string, duration: number }
export type Swap = { at: number, form: number }
export type Announcement = { userId: number?, player: string, name: string, rarity: number, odds: number }

-- stylua: ignore
RevealPlan.TIERS = {
	{ name = "Bright",   climbFactor = 1,    pause = 0.45, drumroll = 1.1, forms = 0, confetti = 0,   darkSky = false, rays = false, explosion = false, shake = 0.8, cinematic = false, autoClose = 5 },
	{ name = "Hesitate", climbFactor = 1.05, pause = 0.5,  drumroll = 1.8, forms = 3, confetti = 60,  darkSky = false, rays = false, explosion = false, shake = 1.1, cinematic = false, autoClose = 5 },
	{ name = "Storm",    climbFactor = 1.1,  pause = 0.55, drumroll = 2,   forms = 3, confetti = 100, darkSky = true,  rays = true,  explosion = true,  shake = 2,   cinematic = false, autoClose = 6 },
	{ name = "Secret",   climbFactor = 1.1,  pause = 0.55, drumroll = 1.5, forms = 3, confetti = 120, darkSky = true,  rays = true,  explosion = true,  shake = 2.4, cinematic = true,  autoClose = 8 },
} :: { Tier }
-- Secret : roulement plus court que Storm, la séquence complète prend le relais du suspense (#204)

-- Étapes de la séquence du secret, après le roulement (s) ; resserrées par #204 (12,6 → 8,6 s)
RevealPlan.CINEMATIC = {
	{ name = "Blackout", duration = 3 }, -- écran noir et phrase lettre à lettre
	{ name = "Stage", duration = 1.8 }, -- décor dédié (tapis rouge, colonnes, lumière dorée), caméra le long du tapis
	{ name = "Portal", duration = 1.3 }, -- portail qui s'ouvre au bout du tapis
	{ name = "Coins", duration = 0.9 }, -- le mannequin sort du portail, pluie de pièces
	{ name = "Banner", duration = 1.6 }, -- « SECRET!! » géant et cote complète
} :: { Step }

RevealPlan.TEASE_FIRST = 0.45 -- silhouette seule avant le premier palier (s)
RevealPlan.ANNOUNCE_MIN = 5 -- rareté à partir de laquelle le serveur annonce le tirage à tous (Legendary)
RevealPlan.TYPE_RATE = 28 -- lettres par seconde de la phrase du secret
-- Part de l'écran noir sans frappe (s) : 0,35 de fondu au noir avant la première lettre, 0,65 de fondu de sortie
RevealPlan.BLACKOUT_FRAME = 1
RevealPlan.READ_TIME = 0.8 -- phrase entière lisible au moins ce temps avant le fondu de sortie (s)
RevealPlan.RESULT_MARGIN = 5 -- s ajoutées à la durée maximale du tirage : CHANCE finale à l'arrêt, latence
local MAX_CLIMBS = 4 -- au plus 3 candidats puis le gagné (Collection.teaseSteps)
local MAX_CLIMB_TIME = 1.5 -- plafond d'une montée, palier du candidat compris (s)
local FIRST_GAP = 0.09 -- premier écart entre deux formes pendant l'hésitation (s), puis de plus en plus long
local GAP_GROWTH = 1.3
local SETTLE = 0.3 -- part finale du roulement où la silhouette reste sur le gagné

-- Phrase de l'écran noir, propre à chaque secret (« THE KINGDOM HAS FOUND ITS KING… » de la référence)
RevealPlan.SECRET_LINES = {
	king = "THE CRASH KINGDOM HAS ITS KING...",
	void = "SOMETHING STIRS IN THE VOID...",
	cosmic = "THE STARS HAVE ALIGNED...",
} :: { [string]: string }
RevealPlan.SECRET_LINE_DEFAULT = "SOMETHING LEGENDARY APPROACHES..."
-- Phrase des raretés au-delà de Secret (#94, indice de Shared.Rarity), avant celle de la famille du mannequin généré
RevealPlan.RARITY_LINES = {
	[8] = "THE HEAVENS HAVE OPENED...",
	[9] = "A NEW STAR IS BORN...",
	[10] = "REALITY BEGINS TO BEND...",
	[11] = "THERE IS NO END...",
} :: { [number]: string }

-- Cette méthode permet de donner l'indice du palier de mise en scène (1 à 4) d'une rareté lorsque le tirage se joue.
function RevealPlan.tierOf(rarity: number): number
	local index = math.clamp(math.floor(rarity), 1, #Rarity.LIST)
	if index >= Rarity.SECRET then
		return 4
	end
	return math.ceil(index / 2)
end

-- Cette méthode permet de donner le palier de mise en scène d'une rareté lorsque le tirage se joue.
function RevealPlan.get(rarity: number): Tier
	return RevealPlan.TIERS[RevealPlan.tierOf(rarity)]
end

-- Cette méthode permet de donner la durée (s) de la montée de la cote de `from` à `to` vers un candidat de rareté
-- `target` (jamais la rareté gagnée, #204) lorsque le suspense passe au palier suivant : plus rare, plus longue, 1,5 s
-- au plus.
function RevealPlan.climbTime(target: number, from: number, to: number): number
	return math.min(Collection.climbTime(from, to) * RevealPlan.get(target).climbFactor, MAX_CLIMB_TIME)
end

-- Cette méthode permet de donner l'arrêt (s) sur un candidat de rareté `target` lorsque la cote vient de l'atteindre.
function RevealPlan.pauseOf(target: number): number
	return RevealPlan.get(target).pause
end

-- Cette méthode permet de donner le rythme du suspense de `sequence` (par palier : durée de la montée, arrêt, instant
-- où la cote l'atteint depuis la silhouette ; puis début du roulement) lorsque le client le joue ou qu'on le mesure :
-- rythme du candidat visé, jamais de la rareté gagnée (#204).
function RevealPlan.pace(sequence: { Collection.TeaseStep }): ({ Pace }, number)
	local list: { Pace } = {}
	local at = RevealPlan.TEASE_FIRST
	local shown = 1
	for _, step in sequence do
		local climb = RevealPlan.climbTime(step.rarity, shown, step.odds)
		local pause = RevealPlan.pauseOf(step.rarity)
		at += climb
		table.insert(list, { climb = climb, pause = pause, reached = at })
		at += pause
		shown = step.odds
	end
	return list, at
end

-- Cette méthode permet de calculer la durée du suspense (silhouette seule, montées de la cote et arrêts sur chaque
-- palier au rythme du candidat visé, roulement de la rareté gagnée `rarity`) lorsque l'on mesure ou planifie le tirage.
function RevealPlan.teaseTime(rarity: number, sequence: { Collection.TeaseStep }): number
	local _, drumroll = RevealPlan.pace(sequence)
	return drumroll + RevealPlan.get(rarity).drumroll
end

-- Cette méthode permet de donner la durée de la séquence du secret (écran noir à « SECRET!! ») lorsque l'on planifie
-- le tirage d'un secret.
function RevealPlan.cinematicTime(): number
	local total = 0
	for _, step in RevealPlan.CINEMATIC do
		total += step.duration
	end
	return total
end

-- Cette méthode permet de donner la durée (s) de la séquence du secret jouée pour une rareté (0 sans séquence)
-- lorsque l'on calcule la durée d'un tirage.
local function cinematicOf(rarity: number): number
	return if RevealPlan.get(rarity).cinematic then RevealPlan.cinematicTime() else 0
end

-- Cette méthode permet de donner la durée (s) du tirage d'un mannequin de rareté `rarity` jusqu'aux textes de la
-- révélation et à GO BACK (suspense, puis séquence du secret) lorsque l'on mesure l'attente imposée au joueur.
function RevealPlan.revealTime(rarity: number, sequence: { Collection.TeaseStep }): number
	return RevealPlan.teaseTime(rarity, sequence) + cinematicOf(rarity)
end

-- Cette méthode permet de donner la durée maximale (s) d'un tirage de rareté `rarity`, du début de la silhouette au
-- GO BACK automatique, lorsque le serveur fixe sa fin forcée : 4 montées au plafond, chacune suivie de l'arrêt du
-- palier gagné (un candidat n'est jamais plus rare que le gagné).
function RevealPlan.maxDuration(rarity: number): number
	local tier = RevealPlan.get(rarity)
	local total = RevealPlan.TEASE_FIRST + MAX_CLIMBS * (MAX_CLIMB_TIME + tier.pause) + tier.drumroll + tier.autoClose
	return total + cinematicOf(rarity)
end

-- Cette méthode permet de donner le délai (s) au bout duquel le serveur clôt le résultat sans GO BACK lorsque le
-- tirage d'un mannequin de rareté `rarity` commence : jamais sous GameConfig.RESULT_MAX_TIME.
function RevealPlan.resultTime(rarity: number?): number
	local needed = math.ceil(RevealPlan.maxDuration(rarity or 1) + RevealPlan.RESULT_MARGIN)
	return math.max(GameConfig.RESULT_MAX_TIME, needed)
end

-- Cette méthode permet de choisir les paliers de `sequence` entre lesquels la silhouette hésite (gagné en dernier ; vide
-- sans hésitation ou sans autre candidat) lorsque le roulement commence.
function RevealPlan.forms(rarity: number, sequence: { Collection.TeaseStep }): { number }
	local count = math.min(RevealPlan.get(rarity).forms, #sequence)
	if count < 2 then
		return {}
	end
	local list = {}
	for index = #sequence - count + 1, #sequence do
		table.insert(list, index)
	end
	return list
end

-- Cette méthode permet de planifier les changements de forme (rapides puis lents, le dernier sur le gagné `count`)
-- pendant `duration` s lorsque le roulement commence ; vide sous 2 formes.
function RevealPlan.hesitation(count: number, duration: number): { Swap }
	if count < 2 or duration <= 0 then
		return {}
	end
	local limit = duration * (1 - SETTLE)
	local times = {}
	local at = 0
	local gap = FIRST_GAP
	while at + gap <= limit do
		at += gap
		table.insert(times, at)
		gap *= GAP_GROWTH
	end
	local swaps = {}
	local total = #times
	for k, time in times do
		-- Forme qui tourne dans l'ordre et tombe sur le gagné (count) au dernier changement
		table.insert(swaps, { at = time, form = (k - total - 1) % count + 1 })
	end
	return swaps
end

-- Cette méthode permet de donner la rareté affichée pendant le suspense lorsque `reached` paliers de `sequence` sont
-- atteints : Common (« 1 IN 1 ») avant le premier, puis celle du dernier candidat atteint, jamais celle du gagné avant.
function RevealPlan.shownRarity(sequence: { Collection.TeaseStep }, reached: number): number
	local step = sequence[math.min(reached, #sequence)]
	return if reached >= 1 and step then step.rarity else 1
end

-- Cette méthode permet de donner les effets du suspense (contour, ciel, rayons) du palier affiché `shown` lorsque la
-- cote atteint un palier ou que la silhouette apparaît (#201) : rien qui en dise plus que la cote affichée.
function RevealPlan.teaseCues(shown: number): Cues
	local tier = RevealPlan.get(shown)
	local rarity = math.clamp(math.floor(shown), 1, #Rarity.LIST)
	return { rarity = rarity, outline = Rarity.get(rarity).color, darkSky = tier.darkSky, rays = tier.rays }
end

-- Cette méthode permet de donner les effets ajoutés à la silhouette du palier affiché `shown` dès Legendary (gloire
-- de rayons, colonne de lumière, poussières, couleur `color`) lorsque la cote l'atteint ; vide sinon.
function RevealPlan.teaseEffects(shown: number, color: Color3): { DummyModels.Effect }
	if not RevealPlan.teaseCues(shown).rays then
		return {}
	end
	local white = Color3.new(1, 1, 1)
	local ground = Vector3.new(0, -3.7, 0)
	return {
		{
			kind = "particles",
			preset = "rays",
			piece = "Torso",
			offset = Vector3.new(0, 0.6, 0.9),
			color = color,
			color2 = white,
			size = 1.6,
		},
		{ kind = "beam", piece = "Torso", offset = ground, color = white, color2 = color, height = 40, width = 6 },
		{
			kind = "particles",
			preset = "motes",
			piece = "Torso",
			offset = ground,
			color = color,
			color2 = white,
			rate = 2,
		},
	} :: { any }
end

-- Cette méthode permet de donner la phrase de l'écran noir d'un secret lorsque sa séquence commence : la sienne, sinon
-- celle de sa rareté au-delà de Secret, sinon celle de sa famille (mannequin généré, « golden_void » → void).
function RevealPlan.secretLine(id: string): string
	local own = RevealPlan.SECRET_LINES[id]
	if own then
		return own
	end
	local dummy = Collection.get(id)
	local byRarity = dummy and RevealPlan.RARITY_LINES[dummy.rarity]
	if byRarity then
		return byRarity
	end
	local family = DummyFamilies.parse(id)
	return (family and RevealPlan.SECRET_LINES[family]) or RevealPlan.SECRET_LINE_DEFAULT
end

-- Cette méthode permet de donner le début de `text` écrit au bout de `elapsed` s (TYPE_RATE lettres par seconde,
-- caractères UTF-8 entiers) lorsque la phrase du secret s'écrit lettre à lettre.
function RevealPlan.typed(text: string, elapsed: number): string
	local count = math.floor(math.max(elapsed, 0) * RevealPlan.TYPE_RATE)
	local length = utf8.len(text) or #text
	if count >= length then
		return text
	elseif count <= 0 then
		return ""
	end
	local stop = utf8.offset(text, count + 1)
	return string.sub(text, 1, (stop or #text + 1) - 1)
end

-- Cette méthode permet de savoir si le serveur annonce à tous un tirage de rareté `rarity` lorsque le mannequin est
-- gagné (Legendary et plus).
function RevealPlan.announces(rarity: number): boolean
	return rarity >= RevealPlan.ANNOUNCE_MIN
end

-- Cette méthode permet d'écrire le texte d'une annonce (« Ana pulled a LEGENDARY Gold Dummy! 1 IN 4K » ; rareté et nom
-- à la couleur `hex` si donnée, en RichText) lorsque le bandeau ou le chat l'affiche ; `odds` déjà abrégée.
function RevealPlan.announceText(player: string, name: string, rarity: number, odds: string, hex: string?): string
	local prize = string.upper(Rarity.get(rarity).name) .. " " .. name
	if hex then
		prize = string.format('<font color="#%s">%s</font>', hex, prize)
	end
	return string.format("%s pulled a %s! 1 IN %s", player, prize, odds)
end

-- Cette méthode permet de lire une annonce reçue du serveur (nil si elle est mal formée) lorsque le client la reçoit.
function RevealPlan.parseAnnouncement(data: any): Announcement?
	if
		type(data) ~= "table"
		or type(data.player) ~= "string"
		or type(data.name) ~= "string"
		or type(data.rarity) ~= "number"
		or type(data.odds) ~= "number"
	then
		return nil
	end
	local userId = if type(data.userId) == "number" then data.userId else nil
	return { userId = userId, player = data.player, name = data.name, rarity = data.rarity, odds = data.odds }
end

-- Cette méthode permet de donner le mannequin imposé par `DebugPrize` (rareté 1-11, son nom ou « id:taille » ; nil si
-- absent ou illisible) lorsque le serveur tire en Studio.
function RevealPlan.debugEntry(value: any, roll: () -> number): Collection.Entry?
	local rarity: number? = nil
	if type(value) == "number" then
		rarity = math.floor(value)
	elseif type(value) == "string" then
		local entry = Inventory.parseKey(value)
		if entry then
			return entry
		end
		rarity = tonumber(value)
		for index, tier in Rarity.LIST do
			if string.lower(tier.name) == string.lower(value) then
				rarity = index
			end
		end
	end
	if not rarity or rarity < 1 or rarity > #Rarity.LIST then
		return nil
	end
	local pool = {}
	for _, dummy in Collection.DUMMIES do
		if dummy.rarity == rarity then
			table.insert(pool, dummy)
		end
	end
	if #pool == 0 then
		return nil
	end
	local pick = pool[math.clamp(math.floor(roll() * #pool) + 1, 1, #pool)]
	return { id = pick.id, size = 1 }
end

return RevealPlan
