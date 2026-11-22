-- Boutique de mannequins à lancer (#14, l'équivalent des graines de la référence 09) : catalogue, achat séquentiel
-- (le suivant se débloque quand le précédent est acheté), équipement, multiplicateur de chance du vol et comportement
-- physique de chacun. Logique pure, partagée par le serveur (validation, vol) et le client (boutique, mannequin tenu).
-- Distincts des mannequins de collection (Shared.Collection) : on les possède une fois pour toutes, on en lance un.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DummyFamilies = require(Shared:WaitForChild("DummyFamilies"))
local DummyModels = require(Shared:WaitForChild("DummyModels"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))

local ThrowDummies = {}

ThrowDummies.SHOP_TAG = "ShopStand" -- invite du stand SHOP du hub (ouvre la boutique)
ThrowDummies.DISPLAY_TAG = "ShopDisplay" -- socles de vitrine du stand SHOP (attribut Index) : le client y fait tourner le mannequin

-- Pièce en blocs soudée à une pièce du corps (aile, réacteur, plaques) : type de Shared.DummyShape, qui la construit
export type Block = DummyShape.Block

-- Propriétés physiques des 10 pièces du mannequin lancé (PhysicalProperties) : densité, frottement, rebond, poids
export type Physics = {
	density: number,
	friction: number,
	elasticity: number,
	frictionWeight: number,
	elasticityWeight: number,
}

export type Dummy = {
	id: string,
	name: string,
	cost: number, -- prix d'achat en $ (le premier est offert)
	luck: number, -- multiplicateur de la CHANCE du vol
	behavior: string, -- comportement en vol, affiché sur la carte
	color: Color3, -- corps
	material: Enum.Material?,
	pieceColors: { [string]: Color3 }?,
	blocks: { Block }?, -- pièces du comportement (ailes, réacteur, lest), une par mannequin dessiné
	ornaments: { Block }?, -- signes de rang des derniers mannequins (couronne, auréole : RANKS)
	effects: { DummyModels.Effect }?, -- éclats et lumière des derniers rangs (RANKS)
	card: Color3, -- teinte de la carte de la boutique (cartes colorées par niveau, référence 09)
	physics: Physics,
	boneFactor: number, -- multiplie la violence des chocs pour casser les os (fragile > 1)
	-- Comportement en vol (Shared.FlightArc.Behavior, #130) : part de la portée naturelle gagnée à puissance et jauge
	-- égales, réglages de la poussée, de la descente et des rebonds calculés par FlightArc.plan
	glide: number, -- planeur : part gagnée par la descente lente depuis le plafond
	thrust: number, -- réacteur : part gagnée par la poussée vers l'avant
	thrustTime: number, -- durée de la poussée depuis le lâcher (s)
	bounce: number, -- caoutchouc : part gagnée par les rebonds
}

-- Le mannequin de crash-test d'origine (Server.DummyFactory avant #14) : lourd, il garde son élan
local STANDARD: Physics = { density = 1.5, friction = 0.3, elasticity = 0.3, frictionWeight = 1, elasticityWeight = 1 }

local rgb = Color3.fromRGB

-- Six mannequins, chance 1x → 3x (comme les graines de 09 : 1.0x, 1.25x, 1.5x, 2.0x) ; prix calés par le joueur simulé
-- (#15, tools/progression.luau) entre ceux des équipements d'entraînement (Shared.Training) : un achat toutes les 1 à
-- 5 min la première heure, sans mur
ThrowDummies.LIST = {
	{
		id = "crash",
		name = "Crash Dummy",
		cost = 0,
		luck = 1,
		behavior = "Classic",
		color = rgb(255, 205, 40),
		card = rgb(205, 210, 220),
		physics = STANDARD,
		boneFactor = 1,
		glide = 0,
		thrust = 0,
		thrustTime = 0,
		bounce = 0,
	},
	{
		id = "rubber",
		name = "Rubber Dummy",
		cost = 1500,
		luck = 1.25,
		behavior = "Bouncy",
		color = rgb(255, 95, 175),
		pieceColors = {
			LeftLowerArm = rgb(255, 235, 80),
			RightLowerArm = rgb(255, 235, 80),
			LeftLowerLeg = rgb(255, 235, 80),
			RightLowerLeg = rgb(255, 235, 80),
		},
		blocks = {
			-- Pompon de ballon gonflable sur la tête
			{
				piece = "Head",
				size = Vector3.new(0.5, 0.5, 0.5),
				offset = Vector3.new(0, 0.98, 0),
				color = rgb(255, 235, 80),
			},
		},
		card = rgb(255, 150, 205),
		-- Caoutchouc : presque sans frottement ; chaque rebond au sol rend 60 % de la chute vers le haut (4 rebonds depuis
		-- le plafond), à élan constant et sans frein au sol, pour + 15 % de la portée naturelle à l'arrêt (#130)
		physics = { density = 1.2, friction = 0.05, elasticity = 0.8, frictionWeight = 100, elasticityWeight = 100 },
		boneFactor = 0.8,
		glide = 0,
		thrust = 0,
		thrustTime = 0,
		bounce = 0.15,
	},
	{
		id = "glass",
		name = "Glass Dummy",
		cost = 40000,
		luck = 1.5,
		behavior = "Fragile",
		color = rgb(150, 235, 255),
		material = Enum.Material.Glass,
		blocks = {
			-- Étiquette « FRAGILE » rouge sur le ventre, sous la cible du torse
			{
				piece = "Torso",
				size = Vector3.new(1.4, 0.38, 0.1),
				offset = Vector3.new(0, -0.72, -0.58),
				color = rgb(230, 40, 40),
			},
		},
		card = rgb(140, 220, 255),
		physics = STANDARD,
		-- Os en verre : un choc moitié moins fort suffit à casser (+2 % de chance par os)
		boneFactor = 2,
		glide = 0,
		thrust = 0,
		thrustTime = 0,
		bounce = 0,
	},
	{
		id = "steel",
		name = "Steel Dummy",
		cost = 250000,
		luck = 2,
		behavior = "Heavy",
		color = rgb(130, 138, 150),
		material = Enum.Material.DiamondPlate,
		blocks = {
			-- Plaques de lest boulonnées sur le torse et les cuisses
			{
				piece = "Torso",
				size = Vector3.new(2.15, 0.6, 1.25),
				offset = Vector3.new(0, -0.5, 0),
				color = rgb(60, 64, 72),
				material = Enum.Material.Metal,
			},
			{
				piece = "LeftUpperLeg",
				size = Vector3.new(1.05, 0.4, 1.05),
				offset = Vector3.new(0, 0.2, 0),
				color = rgb(60, 64, 72),
				material = Enum.Material.Metal,
			},
			{
				piece = "RightUpperLeg",
				size = Vector3.new(1.05, 0.4, 1.05),
				offset = Vector3.new(0, 0.2, 0),
				color = rgb(60, 64, 72),
				material = Enum.Material.Metal,
			},
		},
		card = rgb(150, 160, 175),
		-- Acier : 5 fois plus dense, il défonce les obstacles au lieu d'y rebondir
		physics = { density = 8, friction = 0.4, elasticity = 0.05, frictionWeight = 1, elasticityWeight = 100 },
		boneFactor = 1,
		glide = 0,
		thrust = 0,
		thrustTime = 0,
		bounce = 0,
	},
	{
		id = "glider",
		name = "Glider Dummy",
		cost = 1200000,
		luck = 2.5,
		behavior = "Glides",
		color = rgb(110, 220, 90),
		blocks = {
			-- Ailes de deltaplane dans le dos, d'une main à l'autre
			{
				piece = "Torso",
				size = Vector3.new(6, 0.2, 1.8),
				offset = Vector3.new(0, 0.7, 0.7),
				color = rgb(255, 140, 30),
			},
			{
				piece = "Torso",
				size = Vector3.new(4, 0.25, 1.2),
				offset = Vector3.new(0, 0.82, 0.7),
				color = rgb(255, 255, 255),
			},
		},
		card = rgb(130, 230, 110),
		physics = STANDARD,
		boneFactor = 1,
		-- Plane : redescend du plafond à vitesse tenue (≈ 40 studs/s), pour + 20 % de la portée naturelle (#130)
		glide = 0.2,
		thrust = 0,
		thrustTime = 0,
		bounce = 0,
	},
	{
		id = "rocket",
		name = "Rocket Dummy",
		cost = 3000000,
		luck = 3,
		behavior = "Jetpack",
		color = rgb(235, 60, 55),
		pieceColors = { Head = rgb(255, 255, 255) },
		blocks = {
			-- Réacteur dorsal : deux tuyères et leur réservoir
			{
				piece = "Torso",
				size = Vector3.new(1.6, 1.6, 0.6),
				offset = Vector3.new(0, 0.1, 0.85),
				color = rgb(240, 240, 245),
				material = Enum.Material.Metal,
			},
			{
				piece = "Torso",
				size = Vector3.new(0.5, 0.6, 0.5),
				offset = Vector3.new(-0.45, -0.95, 0.85),
				color = rgb(60, 60, 70),
				material = Enum.Material.Metal,
			},
			{
				piece = "Torso",
				size = Vector3.new(0.5, 0.6, 0.5),
				offset = Vector3.new(0.45, -0.95, 0.85),
				color = rgb(60, 60, 70),
				material = Enum.Material.Metal,
			},
		},
		card = rgb(255, 150, 70),
		physics = STANDARD,
		boneFactor = 1,
		glide = 0,
		-- Réacteur : poussée vers l'avant pendant les 2 premières secondes (montée et début de la croisière), pour
		-- + 20 % de la portée naturelle (#130)
		thrust = 0.2,
		thrustTime = 2,
		bounce = 0,
	},
} :: { Dummy }

-- Mannequins dessinés exposés sur le stand SHOP du hub (plateaux et vitrine, Server.Props.shopStand) : les suivants
-- ne sont que dans la boutique
ThrowDummies.SHOWCASE = #ThrowDummies.LIST

-- Suite du catalogue (#94), jusqu'à 135x comme les graines de Throw a Seed : chacun reprend le comportement et la
-- physique d'un mannequin dessiné (rebond, verre, lest, ailes, réacteur, sans les cumuler) sous une palette de
-- Shared.DummyFamilies (« Ruby Rubber Dummy »). Prix calés par le joueur simulé (#15, tools/progression.luau ; Amber
-- Glider, Golden Rocket et Frost Rubber recalés par #133 : pas plus de 6 min entre deux achats la première heure), en
-- alternance avec les équipements d'entraînement : courbe et temps estimés dans docs/design.md, section « Progression
-- longue ».
-- stylua: ignore
ThrowDummies.EXTENDED = {
	{ luck = 4,   base = "rubber", palette = "ruby",        cost = 12e6 },
	{ luck = 5,   base = "glass",  palette = "emerald",     cost = 25e6 },
	{ luck = 6.5, base = "steel",  palette = "sapphire",    cost = 35e6 },
	{ luck = 8,   base = "glider", palette = "amber",       cost = 100e6 },
	{ luck = 10,  base = "rocket", palette = "golden",      cost = 140e6 },
	{ luck = 13,  base = "rubber", palette = "frost",       cost = 450e6 },
	{ luck = 17,  base = "glass",  palette = "magma",       cost = 1e9 },
	{ luck = 22,  base = "steel",  palette = "shadow",      cost = 5e9 },
	{ luck = 30,  base = "glider", palette = "radiant",     cost = 9e9 },
	{ luck = 40,  base = "rocket", palette = "starlight",   cost = 15e9 },
	{ luck = 55,  base = "rubber", palette = "nebula",      cost = 30e9 },
	{ luck = 75,  base = "glass",  palette = "plasma",      cost = 80e9 },
	{ luck = 100, base = "glider", palette = "quantum",     cost = 120e9 },
	{ luck = 135, base = "rocket", palette = "infinite",    cost = 200e9 },
}

-- Signes de rang de la suite du catalogue (#127), comme les graines de plus en plus riches de Throw a Seed (09) : sans
-- eux, Radiant Glider ou Infinite Rocket ressemblaient au Glider et au Rocket de départ. Chance minimale de chaque rang :
-- 1 bandeau d'or et gemme au front, 2 couronne et éclats, 3 auréole de néon et lumière. En blocs (visibles dans les
-- fenêtres, contrairement aux particules).
ThrowDummies.RANKS = { 13, 30, 75 }

local GOLD = rgb(255, 195, 45)

-- Cette méthode permet de donner le rang d'un mannequin à lancer (0 : aucun signe, puis 1 à 3) selon sa chance `luck`
-- lorsque l'on habille la suite du catalogue.
function ThrowDummies.rank(luck: number): number
	local rank = 0
	for i, threshold in ThrowDummies.RANKS do
		if luck >= threshold then
			rank = i
		end
	end
	return rank
end

-- Cette méthode permet de donner les blocs des signes de rang (repère de conception de la tête : avant vers -Z, tête de
-- 1,5 stud) d'un mannequin de rang `rank` à la lueur `glow` lorsque l'on construit la suite du catalogue.
local function ornaments(rank: number, glow: Color3): { Block }
	local list: { Block } = {}
	-- Cette méthode permet d'ajouter un bloc posé sur la tête lorsque l'on dresse la liste des signes.
	local function add(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material)
		table.insert(list, { piece = "Head", size = size, offset = offset, color = color, material = material })
	end
	if rank >= 1 then
		add(Vector3.new(1.62, 0.28, 1.62), Vector3.new(0, 0.5, 0), GOLD, Enum.Material.Foil) -- bandeau
		add(Vector3.new(0.34, 0.26, 0.1), Vector3.new(0, 0.5, -0.84), glow, Enum.Material.Neon) -- gemme au front
	end
	if rank >= 2 then
		for _, x in { -0.67, 0.67 } do
			for _, z in { -0.67, 0.67 } do
				add(Vector3.new(0.28, 0.42, 0.28), Vector3.new(x, 0.85, z), GOLD, Enum.Material.Foil) -- pointes
			end
		end
		add(Vector3.new(0.3, 0.55, 0.28), Vector3.new(0, 0.9, -0.67), GOLD, Enum.Material.Foil) -- pointe du front
	end
	if rank >= 3 then
		-- Auréole carrée au-dessus de la couronne
		for _, z in { -0.62, 0.62 } do
			add(Vector3.new(1.42, 0.2, 0.2), Vector3.new(0, 1.55, z), glow, Enum.Material.Neon)
		end
		for _, x in { -0.62, 0.62 } do
			add(Vector3.new(0.2, 0.2, 1.04), Vector3.new(x, 1.55, 0), glow, Enum.Material.Neon)
		end
	end
	return list
end

-- Cette méthode permet de donner les effets des signes de rang (éclats au rang 2, étoiles et lumière au rang 3, à la
-- lueur `glow`) lorsque l'on construit la suite du catalogue ; nil sous le rang 2.
local function rankEffects(rank: number, glow: Color3): { DummyModels.Effect }?
	if rank < 2 then
		return nil
	end
	local effects: { DummyModels.Effect } = {
		{ kind = "particles", preset = "sparkle", piece = "Torso", offset = Vector3.zero, color = glow, color2 = GOLD },
	}
	if rank >= 3 then
		table.insert(effects, {
			kind = "particles",
			preset = "stars",
			piece = "Head",
			offset = Vector3.new(0, 1.55, 0),
			color = glow,
			color2 = GOLD,
			rate = 0.6,
		})
		table.insert(effects, {
			kind = "light",
			piece = "Torso",
			offset = Vector3.new(0, 0, -1.5),
			color = glow,
			range = 10,
			brightness = 1.5,
		})
	end
	return effects
end

-- Cette méthode permet de construire un mannequin de la suite du catalogue (comportement de `base`, couleurs et
-- matériau de la palette, blocs teintés) lorsque le catalogue se construit.
local function extend(base: Dummy, spec: { luck: number, base: string, palette: string, cost: number }): Dummy
	local palette = DummyFamilies.PALETTES[spec.palette]
	assert(palette, "ThrowDummies : palette inconnue " .. spec.palette)
	local blocks: { Block }? = nil
	if base.blocks then
		local tinted: { Block } = {}
		for _, block in base.blocks do
			local copy = table.clone(block)
			copy.color = block.color:Lerp(palette.accent, palette.tint)
			copy.material = palette.accessoryMaterial or block.material
			table.insert(tinted, copy)
		end
		blocks = tinted
	end
	local pieceColors: { [string]: Color3 }? = nil
	if base.pieceColors then
		local colors: { [string]: Color3 } = {}
		for piece, color in base.pieceColors do
			colors[piece] = color:Lerp(palette.accent, palette.tint)
		end
		pieceColors = colors
	end
	local dummy = table.clone(base)
	dummy.id = spec.palette .. "_" .. base.id
	dummy.name = palette.name .. " " .. base.name
	dummy.cost = spec.cost
	dummy.luck = spec.luck
	dummy.color = palette.body
	-- Le verre et le lest gardent leur matière (comportement lisible), les autres prennent celle de la palette
	dummy.material = base.material or palette.material
	dummy.pieceColors = pieceColors
	dummy.blocks = blocks
	local rank = ThrowDummies.rank(spec.luck)
	dummy.ornaments = if rank > 0 then ornaments(rank, palette.glow) else nil
	dummy.effects = rankEffects(rank, palette.glow)
	dummy.card = palette.body:Lerp(Color3.new(1, 1, 1), 0.35)
	return dummy
end

do
	local byId: { [string]: Dummy } = {}
	for _, dummy in ThrowDummies.LIST do
		byId[dummy.id] = dummy
	end
	for _, spec in ThrowDummies.EXTENDED do
		local base = byId[spec.base]
		assert(base, "ThrowDummies : mannequin de base inconnu " .. spec.base)
		table.insert(ThrowDummies.LIST, extend(base, spec))
	end
end

-- Cette méthode permet de donner le mannequin `index` du catalogue (borné) lorsque l'on lance, affiche ou valide.
function ThrowDummies.get(index: number): Dummy
	return ThrowDummies.LIST[math.clamp(math.floor(index), 1, #ThrowDummies.LIST)]
end

-- Cette méthode permet de savoir si `value` désigne un mannequin du catalogue (entier dans la liste) lorsque le serveur
-- reçoit une demande du client.
function ThrowDummies.isIndex(value: any): boolean
	return typeof(value) == "number" and value == math.floor(value) and ThrowDummies.LIST[value] ~= nil
end

-- Cette méthode permet de donner le prix du mannequin suivant lorsque le joueur en possède `owned` (les premiers de la
-- liste) ; nil quand il les a tous.
function ThrowDummies.nextCost(owned: number): number?
	local nextDummy = ThrowDummies.LIST[owned + 1]
	return if nextDummy then nextDummy.cost else nil
end

-- Cette méthode permet de savoir si le joueur (`owned` mannequins, `money` $) peut acheter le mannequin `index`
-- lorsqu'il clique son prix : seulement le suivant (achat séquentiel), et s'il a l'argent.
function ThrowDummies.canBuy(owned: number, index: any, money: number): boolean
	return ThrowDummies.isIndex(index) and index == owned + 1 and money >= ThrowDummies.LIST[index].cost
end

-- Cette méthode permet de savoir si le joueur (`owned` mannequins) peut équiper le mannequin `index` lorsqu'il clique
-- EQUIP : seulement un mannequin possédé.
function ThrowDummies.canEquip(owned: number, index: any): boolean
	return ThrowDummies.isIndex(index) and index <= owned
end

export type Purchase = { owned: number, equipped: number, cost: number }

-- Cette méthode permet d'appliquer une demande de la boutique (`action` = "Buy" : le suivant seulement, avec l'argent,
-- aussitôt équipé ; "Equip" : un mannequin possédé, autre que l'équipé) lorsque le serveur la reçoit ; renvoie le
-- nouvel état et la dépense, ou nil si la demande est refusée.
function ThrowDummies.act(owned: number, equipped: number, money: number, action: any, index: any): Purchase?
	if action == "Buy" and ThrowDummies.canBuy(owned, index, money) then
		return { owned = index, equipped = index, cost = ThrowDummies.LIST[index].cost }
	elseif action == "Equip" and ThrowDummies.canEquip(owned, index) and index ~= equipped then
		return { owned = owned, equipped = index, cost = 0 }
	end
	return nil
end

-- Cette méthode permet de choisir le mannequin que propose le popup « NEW DUMMY! » lorsque l'argent ou les achats
-- changent : le suivant s'il est abordable et que le joueur n'a pas fermé son popup, sinon nil.
function ThrowDummies.offer(owned: number, money: number, dismissed: { [number]: boolean }): number?
	return Tutorial.gearOffer(owned, ThrowDummies.nextCost(owned), money, dismissed)
end

-- Cette méthode permet de donner l'état de la carte du mannequin `index` lorsque la boutique se rafraîchit :
-- "Equipped", "Owned" (bouton EQUIP), "Buy" (le suivant : prix jaune ou rouge) ou "Locked" (après le suivant).
function ThrowDummies.cardState(owned: number, equipped: number, index: number): string
	if index == equipped then
		return "Equipped"
	elseif index <= owned then
		return "Owned"
	elseif index == owned + 1 then
		return "Buy"
	end
	return "Locked"
end

-- Cette méthode permet de lire un niveau sauvegardé ou répliqué (nombre possédé, mannequin équipé) lorsque l'on
-- charge les données : entier dans le catalogue, `owned` au plus pour l'équipé ; 1 sinon.
function ThrowDummies.sanitize(owned: any, equipped: any): (number, number)
	local count = if typeof(owned) == "number" and owned == owned
		then math.clamp(math.floor(owned), 1, #ThrowDummies.LIST)
		else 1
	local current = if typeof(equipped) == "number" and equipped == equipped
		then math.clamp(math.floor(equipped), 1, count)
		else 1
	return count, current
end

-- Cette méthode permet de donner la violence d'un choc vue par les os du mannequin (`dv` × fragilité) lorsque le
-- serveur décide si un os casse.
function ThrowDummies.boneImpact(dummy: Dummy, dv: number): number
	return dv * dummy.boneFactor
end

-- Cette méthode permet de donner la déclinaison d'affichage du mannequin `index` (Shared.DummyShape.Variant : couleur,
-- matériau, couleurs par pièce, blocs du comportement puis signes de rang, effets) lorsque le serveur le construit pour
-- le lancer ou que le client l'affiche ; `viewport` remplace le verre (invisible dans un ViewportFrame) par du néon.
function ThrowDummies.variant(index: number, viewport: boolean?): { [string]: any }
	local dummy = ThrowDummies.get(index)
	local material = dummy.material
	if viewport and material == Enum.Material.Glass then
		material = Enum.Material.Neon
	end
	local blocks = dummy.blocks
	if dummy.ornaments then
		local all: { Block } = table.clone(blocks or {})
		table.move(dummy.ornaments, 1, #dummy.ornaments, #all + 1, all)
		blocks = all
	end
	return {
		color = dummy.color,
		material = material,
		pieceColors = dummy.pieceColors,
		blocks = blocks,
		effects = if viewport then nil else dummy.effects, -- particules et lumière ne se rendent pas en fenêtre
	}
end

return ThrowDummies
