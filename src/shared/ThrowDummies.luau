-- Boutique de mannequins à lancer (#14, l'équivalent des graines de la référence 09) : catalogue, achat séquentiel
-- (le suivant se débloque quand le précédent est acheté), équipement, multiplicateur de chance du vol et comportement
-- physique de chacun. Logique pure, partagée par le serveur (validation, vol) et le client (boutique, mannequin tenu).
-- Distincts des mannequins de collection (Shared.Collection) : on les possède une fois pour toutes, on en lance un.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
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
	blocks: { Block }?,
	card: Color3, -- teinte de la carte de la boutique (cartes colorées par niveau, référence 09)
	physics: Physics,
	boneFactor: number, -- multiplie la violence des chocs pour casser les os (fragile > 1)
	lift: number, -- part de la gravité compensée quand il redescend (planeur)
	thrust: number, -- poussée vers l'avant au départ (studs/s²)
	thrustTime: number, -- durée de la poussée (s)
	bounce: number?, -- rebond : part de la vitesse de chute rendue vers le haut et de l'élan vers l'avant gardée au sol
}

-- Le mannequin de crash-test d'origine (Server.DummyFactory avant #14) : lourd, il garde son élan
local STANDARD: Physics = { density = 1.5, friction = 0.3, elasticity = 0.3, frictionWeight = 1, elasticityWeight = 1 }

local rgb = Color3.fromRGB
local GLIDE_MIN_FALL = 4 -- vitesse de chute (studs/s) au-delà de laquelle le planeur porte : pas au sol
local BOUNCE_MIN_FALL = 20 -- chute (studs/s) arrêtée net en une frame qui compte comme un rebond au sol
local BOUNCE_STOP = -2 -- vitesse verticale (studs/s) au-dessus de laquelle la chute est arrêtée

-- Six mannequins, prix ×12 à ×25 entre niveaux et chance 1x → 3x (comme les graines de 09 : 1.0x, 1.25x, 1.5x, 2.0x,
-- $1.2K, $15K, $300K) ; prix provisoires, recalés par #15 (économie)
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
		lift = 0,
		thrust = 0,
		thrustTime = 0,
	},
	{
		id = "rubber",
		name = "Rubber Dummy",
		cost = 1200,
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
		-- Caoutchouc : presque sans frottement, et chaque rebond au sol rend 85 % de la chute vers le haut en gardant
		-- 85 % de l'élan vers l'avant (le rebond physique seul le renvoyait n'importe où, sans gagner de distance)
		physics = { density = 1.2, friction = 0.05, elasticity = 0.8, frictionWeight = 100, elasticityWeight = 100 },
		boneFactor = 0.8,
		lift = 0,
		thrust = 0,
		thrustTime = 0,
		bounce = 0.85,
	},
	{
		id = "glass",
		name = "Glass Dummy",
		cost = 15000,
		luck = 1.5,
		behavior = "Fragile",
		color = rgb(150, 235, 255),
		material = Enum.Material.Glass,
		blocks = {
			-- Étiquette « FRAGILE » rouge sur le torse
			{
				piece = "Torso",
				size = Vector3.new(1.4, 0.45, 0.1),
				offset = Vector3.new(0, 0.3, -0.58),
				color = rgb(230, 40, 40),
			},
		},
		card = rgb(140, 220, 255),
		physics = STANDARD,
		-- Os en verre : un choc moitié moins fort suffit à casser (+2 % de chance par os)
		boneFactor = 2,
		lift = 0,
		thrust = 0,
		thrustTime = 0,
	},
	{
		id = "steel",
		name = "Steel Dummy",
		cost = 300000,
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
		lift = 0,
		thrust = 0,
		thrustTime = 0,
	},
	{
		id = "glider",
		name = "Glider Dummy",
		cost = 4000000,
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
		-- Plane : 70 % de la gravité compensée quand il redescend
		lift = 0.7,
		thrust = 0,
		thrustTime = 0,
	},
	{
		id = "rocket",
		name = "Rocket Dummy",
		cost = 50000000,
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
		lift = 0,
		-- Réacteur : poussée vers l'avant pendant la première seconde du vol
		thrust = 60,
		thrustTime = 1,
	},
} :: { Dummy }

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

-- Cette méthode permet de donner l'accélération propre au mannequin en vol (portance du planeur dès qu'il descend
-- plus vite que GLIDE_MIN_FALL, en l'air comme en glissade sur une pente ; poussée du réacteur au départ, vers l'avant
-- à plat `forward`) lorsque le serveur avance le vol d'une frame ; `elapsed` : temps depuis le lancer (s).
function ThrowDummies.flightAccel(
	dummy: Dummy,
	velocity: Vector3,
	forward: Vector3,
	elapsed: number,
	gravity: number
): Vector3
	local accel = Vector3.zero
	if dummy.lift > 0 and velocity.Y < -GLIDE_MIN_FALL then
		accel += Vector3.new(0, gravity * dummy.lift, 0)
	end
	if dummy.thrust > 0 and elapsed < dummy.thrustTime then
		local flat = Vector3.new(forward.X, 0, forward.Z)
		if flat.Magnitude > 1e-3 then
			accel += flat.Unit * dummy.thrust
		end
	end
	return accel
end

-- Cette méthode permet de donner la vitesse du torse après un rebond au sol d'un mannequin rebondissant (chute de plus
-- de BOUNCE_MIN_FALL arrêtée en une frame : `before` → `after`) lorsque le serveur avance le vol ; nil sans rebond.
function ThrowDummies.bounce(dummy: Dummy, before: Vector3, after: Vector3, forward: Vector3): Vector3?
	local keep = dummy.bounce
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if not keep or keep <= 0 or before.Y > -BOUNCE_MIN_FALL or after.Y < BOUNCE_STOP or flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit
	local ahead = Vector3.new(after.X, 0, after.Z):Dot(flat)
	local lateral = Vector3.new(after.X, 0, after.Z) - flat * ahead
	local kept = math.max(ahead, Vector3.new(before.X, 0, before.Z):Dot(flat) * keep)
	return flat * kept + lateral + Vector3.new(0, math.max(after.Y, -before.Y * keep), 0)
end

-- Cette méthode permet de donner la déclinaison d'affichage du mannequin `index` (Shared.DummyShape.Variant : couleur,
-- matériau, couleurs par pièce, blocs) lorsque le serveur le construit pour le lancer ou que le client l'affiche ;
-- `viewport` remplace le verre (invisible dans un ViewportFrame) par du néon.
function ThrowDummies.variant(index: number, viewport: boolean?): { [string]: any }
	local dummy = ThrowDummies.get(index)
	local material = dummy.material
	if viewport and material == Enum.Material.Glass then
		material = Enum.Material.Neon
	end
	return {
		color = dummy.color,
		material = material,
		pieceColors = dummy.pieceColors,
		blocks = dummy.blocks,
	}
end

return ThrowDummies
