-- Mise en scène du tirage selon la rareté du mannequin gagné (#67) : la révélation monte en spectacle par paliers,
-- jusqu'à la séquence complète du secret de la référence 09 (vidéo du testeur : silhouette et cote qui grimpe, écran
-- noir et phrase lettre à lettre, décor dédié, portail, pluie de pièces, « SECRET!! » et cote complète).
--   1. Common / Uncommon : révélation vive (éclair, éclat, son).
--   2. Rare / Epic : la silhouette hésite entre 2 ou 3 formes pendant le roulement, cote qui grimpe, confettis de la
--      couleur de la rareté.
--   3. Legendary / Mythic : ciel qui s'assombrit, rayons et colonne de lumière sur la silhouette, cote qui grimpe
--      longtemps, explosion de particules, forte secousse.
--   4. Secret : palier 3, puis séquence complète (CINEMATIC).
-- Logique pure (paliers, durées, hésitation, phrase, annonce serveur, délai de fin forcée, rareté forcée en Studio) ;
-- la mise en scène est dans Client.Prize et Client.RevealFx.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local DummyModels = require(Shared:WaitForChild("DummyModels"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local RevealPlan = {}

export type Tier = {
	name: string,
	climbFactor: number, -- multiplie la durée de montée de la cote (Collection.climbTime)
	pause: number, -- arrêt sur chaque palier atteint (s)
	drumroll: number, -- roulement avant la révélation (s)
	forms: number, -- formes entre lesquelles la silhouette hésite pendant le roulement, gagnant compris (0 : aucune)
	confetti: number, -- confettis de la couleur de la rareté à la révélation
	darkSky: boolean, -- ciel qui s'assombrit dès la silhouette
	rays: boolean, -- rayons et colonne de lumière sur la silhouette
	explosion: boolean, -- explosion de particules à la révélation
	shake: number, -- secousse de la caméra à la révélation
	cinematic: boolean, -- séquence complète du secret (CINEMATIC)
	autoClose: number, -- GO BACK automatique après la révélation (s)
}

export type Step = { name: string, duration: number }
export type Swap = { at: number, form: number }
export type Announcement = { player: string, name: string, rarity: number, odds: number }

-- stylua: ignore
RevealPlan.TIERS = {
	{ name = "Bright",  climbFactor = 1,    pause = 0.45, drumroll = 1.1, forms = 0, confetti = 0,   darkSky = false, rays = false, explosion = false, shake = 0.8, cinematic = false, autoClose = 5 },
	{ name = "Hesitate", climbFactor = 1.15, pause = 0.5,  drumroll = 1.8, forms = 3, confetti = 60,  darkSky = false, rays = false, explosion = false, shake = 1.1, cinematic = false, autoClose = 5 },
	{ name = "Storm",   climbFactor = 1.6,  pause = 0.6,  drumroll = 2.2, forms = 3, confetti = 100, darkSky = true,  rays = true,  explosion = true,  shake = 2,   cinematic = false, autoClose = 6 },
	{ name = "Secret",  climbFactor = 1.6,  pause = 0.6,  drumroll = 2.2, forms = 3, confetti = 120, darkSky = true,  rays = true,  explosion = true,  shake = 2.4, cinematic = true,  autoClose = 8 },
} :: { Tier }

-- Étapes de la séquence du secret, après le roulement (s)
RevealPlan.CINEMATIC = {
	{ name = "Blackout", duration = 3.4 }, -- écran noir et phrase lettre à lettre
	{ name = "Stage", duration = 3 }, -- décor dédié (tapis rouge, colonnes, lumière dorée), caméra le long du tapis
	{ name = "Portal", duration = 2.2 }, -- portail qui s'ouvre au bout du tapis
	{ name = "Coins", duration = 1.4 }, -- le mannequin sort du portail, pluie de pièces
	{ name = "Banner", duration = 2.6 }, -- « SECRET!! » géant et cote complète
} :: { Step }

RevealPlan.TEASE_FIRST = 0.45 -- silhouette seule avant le premier palier (s)
RevealPlan.SKIP_AFTER = 1 -- le tirage se passe au clic après ce délai (s)
RevealPlan.ANNOUNCE_MIN = 5 -- rareté à partir de laquelle le serveur annonce le tirage à tous (Legendary)
RevealPlan.TYPE_RATE = 20 -- lettres par seconde de la phrase du secret
RevealPlan.RESULT_MARGIN = 5 -- s ajoutées à la durée maximale du tirage : CHANCE finale à l'arrêt, latence
local MAX_CLIMBS = 4 -- au plus 3 candidats puis le gagné (Collection.teaseSteps)
local MAX_CLIMB_TIME = 1.5 -- plafond de Collection.climbTime (s)
local FIRST_GAP = 0.09 -- premier écart entre deux formes pendant l'hésitation (s), puis de plus en plus long
local GAP_GROWTH = 1.3
local SETTLE = 0.3 -- part finale du roulement où la silhouette reste sur le gagné

-- Phrase de l'écran noir, propre à chaque secret (« THE KINGDOM HAS FOUND ITS KING… » de la référence)
RevealPlan.SECRET_LINES = {
	king = "THE CRASH KINGDOM HAS FOUND ITS KING...",
	void = "SOMETHING STIRS IN THE VOID...",
	cosmic = "THE STARS HAVE ALIGNED...",
} :: { [string]: string }
RevealPlan.SECRET_LINE_DEFAULT = "SOMETHING LEGENDARY APPROACHES..."

-- Cette méthode permet de donner l'indice du palier de mise en scène (1 à 4) d'une rareté lorsque le tirage se joue.
function RevealPlan.tierOf(rarity: number): number
	local index = math.clamp(math.floor(rarity), 1, #Rarity.LIST)
	if index >= 7 then
		return 4
	end
	return math.ceil(index / 2)
end

-- Cette méthode permet de donner le palier de mise en scène d'une rareté lorsque le tirage se joue.
function RevealPlan.get(rarity: number): Tier
	return RevealPlan.TIERS[RevealPlan.tierOf(rarity)]
end

-- Cette méthode permet de donner la durée (s) de la montée de la cote de `from` à `to` pour un mannequin de rareté
-- `rarity` lorsque le suspense passe au palier suivant : plus rare, plus longue.
function RevealPlan.climbTime(rarity: number, from: number, to: number): number
	return Collection.climbTime(from, to) * RevealPlan.get(rarity).climbFactor
end

-- Cette méthode permet de calculer la durée du suspense (silhouette seule, montées de la cote et arrêts sur chaque
-- palier, roulement) d'une suite de paliers lorsque l'on mesure ou planifie le tirage.
function RevealPlan.teaseTime(rarity: number, sequence: { Collection.TeaseStep }): number
	local tier = RevealPlan.get(rarity)
	local total = RevealPlan.TEASE_FIRST + tier.drumroll
	local shown = 1
	for _, step in sequence do
		total += RevealPlan.climbTime(rarity, shown, step.odds) + tier.pause
		shown = step.odds
	end
	return total
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

-- Cette méthode permet de donner la durée maximale (s) d'un tirage de rareté `rarity`, du début de la silhouette au
-- GO BACK automatique, lorsque le serveur fixe sa fin forcée : 4 montées au plafond.
function RevealPlan.maxDuration(rarity: number): number
	local tier = RevealPlan.get(rarity)
	local total = RevealPlan.TEASE_FIRST
		+ MAX_CLIMBS * (MAX_CLIMB_TIME * tier.climbFactor + tier.pause)
		+ tier.drumroll
		+ tier.autoClose
	if tier.cinematic then
		total += RevealPlan.cinematicTime()
	end
	return total
end

-- Cette méthode permet de donner le délai (s) au bout duquel le serveur clôt le résultat sans GO BACK lorsque le
-- tirage d'un mannequin de rareté `rarity` commence : jamais sous GameConfig.RESULT_MAX_TIME.
function RevealPlan.resultTime(rarity: number?): number
	local needed = math.ceil(RevealPlan.maxDuration(rarity or 1) + RevealPlan.RESULT_MARGIN)
	return math.max(GameConfig.RESULT_MAX_TIME, needed)
end

-- Cette méthode permet de choisir les paliers de la suite entre lesquels la silhouette hésite (indices dans
-- `sequence`, le gagné en dernier) lorsque le roulement commence ; vide si le palier n'hésite pas ou s'il n'y a pas
-- d'autre candidat.
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

-- Cette méthode permet de planifier l'hésitation de la silhouette entre `count` formes pendant `duration` s (changements
-- rapides puis de plus en plus lents, le dernier sur le gagné, forme `count`, avant la fin) lorsque le roulement
-- commence ; vide pour moins de 2 formes.
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

-- Cette méthode permet de donner les effets ajoutés à la silhouette d'un palier à rayons (gloire de rayons derrière,
-- colonne de lumière, poussières, à la couleur `color` de la rareté : préréglages de Shared.DummyShape) lorsque la
-- silhouette d'un Legendary ou plus apparaît ; vide sinon.
function RevealPlan.teaseEffects(rarity: number, color: Color3): { DummyModels.Effect }
	if not RevealPlan.get(rarity).rays then
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

-- Cette méthode permet de donner la phrase de l'écran noir d'un secret lorsque sa séquence commence.
function RevealPlan.secretLine(id: string): string
	return RevealPlan.SECRET_LINES[id] or RevealPlan.SECRET_LINE_DEFAULT
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

-- Cette méthode permet d'écrire le texte du bandeau d'annonce (« Ana pulled a LEGENDARY Gold Dummy! 1 IN 4K »)
-- lorsque l'annonce d'un tirage arrive ; `odds` déjà abrégée par l'appelant.
function RevealPlan.announceText(player: string, name: string, rarity: number, odds: string): string
	return string.format("%s pulled a %s %s! 1 IN %s", player, string.upper(Rarity.get(rarity).name), name, odds)
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
	return { player = data.player, name = data.name, rarity = data.rarity, odds = data.odds }
end

-- Cette méthode permet de donner le mannequin imposé au prochain tirage par l'attribut de test `DebugPrize` (Studio)
-- lorsque le serveur tire : rareté 1 à 7 ou son nom (« Legendary » : un mannequin de cette rareté au hasard, taille
-- normale), ou clé « id:taille » ; nil si la valeur est absente ou illisible.
function RevealPlan.debugEntry(value: any, roll: () -> number): Collection.Entry?
	local rarity: number? = nil
	if type(value) == "number" then
		rarity = math.floor(value)
	elseif type(value) == "string" then
		local entry = Inventory.parseKey(value)
		if entry then
			return entry
		end
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
