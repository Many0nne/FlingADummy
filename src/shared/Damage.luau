-- Dégâts du mannequin : os cassés par choc, gravité par membre (contusion, cassé, broyé), teinte, phrase de
-- blessure et cause du crash.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Damage = {}

-- Gravité d'un membre selon ses os cassés : 1 contusion, 2 cassé, 3 broyé
Damage.SEVERITY = { "Bruised", "Broken", "Shattered" }

-- Teinte d'un membre par gravité (1, 2, 3)
Damage.TINTS = {
	Color3.fromRGB(255, 140, 30),
	Color3.fromRGB(225, 40, 30),
	Color3.fromRGB(110, 10, 15),
}

-- Nom lisible de chaque pièce du mannequin, dans l'ordre d'affichage des phrases
Damage.LIMB_LABELS = {
	Head = "skull",
	Torso = "ribs",
	LeftUpperArm = "left arm",
	LeftLowerArm = "left forearm",
	RightUpperArm = "right arm",
	RightLowerArm = "right forearm",
	LeftUpperLeg = "left thigh",
	LeftLowerLeg = "left shin",
	RightUpperLeg = "right thigh",
	RightLowerLeg = "right shin",
}

local LIMB_ORDER = {
	"Head",
	"Torso",
	"LeftUpperArm",
	"RightUpperArm",
	"LeftLowerArm",
	"RightLowerArm",
	"LeftUpperLeg",
	"RightUpperLeg",
	"LeftLowerLeg",
	"RightLowerLeg",
}

-- Libellé de l'objet heurté pour la phrase de cause : vitres, obstacles des thèmes (Server.ThemeObstacles), pièges
-- (Shared.Traps), sol
Damage.CAUSE_LABELS = {
	Glass = "Went through a window",
	Ground = "Hit the ground",
	-- Obstacles cassables
	Wall = "Hit a brick wall",
	Crates = "Crashed into crates",
	Car = "Smashed into a car",
	Sign = "Crashed through a sign",
	HayBales = "Plowed through hay bales",
	Tractor = "Smashed into a tractor",
	Fence = "Broke through a fence",
	Logs = "Hit a log pile",
	Beehives = "Knocked over beehives",
	Sandcastle = "Flattened a sandcastle",
	Surfboards = "Wiped out on surfboards",
	Barrels = "Crashed into barrels",
	Cactus = "Hugged a cactus",
	Scaffolding = "Brought down scaffolding",
	Cones = "Bowled over traffic cones",
	Tires = "Bounced off a tire stack",
	Snowmen = "Plowed through snowmen",
	IceWall = "Hit an ice wall",
	LavaRocks = "Hit molten rocks",
	BasaltWall = "Hit a basalt wall",
	CandyCanes = "Snapped candy canes",
	MarshmallowWall = "Hit a marshmallow wall",
	ToyBlocks = "Toppled toy blocks",
	ToySoldiers = "Knocked down toy soldiers",
	Satellites = "Crashed into a satellite",
	Rover = "Smashed into a moon rover",
	-- Pièges
	Trampoline = "Bounced off a trampoline",
	Fan = "Blown away by a giant fan",
	SwingLog = "Whacked by a swinging log",
	Wave = "Wiped out by a wave",
	Twister = "Caught in a twister",
	Press = "Squashed by a hydraulic press",
	Magnet = "Yanked by a crane magnet",
	SkiJump = "Flew off a ski jump",
	Lava = "Bounced off lava",
	Cannon = "Fired from a confetti cannon",
	JackBox = "Popped by a jack-in-the-box",
	Booster = "Blasted through a booster ring",
}
local CAUSE_LABELS = Damage.CAUSE_LABELS

-- Cette méthode permet de compter les os cassés par un choc lorsque la vitesse d'un membre varie de `dv` en une frame.
function Damage.bonesForImpact(dv: number): number
	if dv >= GameConfig.DOUBLE_BONE_DV then
		return 2
	elseif dv >= GameConfig.BONE_IMPACT_DV then
		return 1
	end
	return 0
end

-- Cette méthode permet de donner la couleur d'un membre lorsque `bones` de ses os sont cassés (jaune → rouge sombre).
function Damage.tint(baseColor: Color3, bones: number): Color3
	if bones <= 0 then
		return baseColor
	end
	return Damage.TINTS[math.min(bones, #Damage.TINTS)]
end

-- Cette méthode permet d'écrire la phrase de blessure (« Shattered skull, broken left arm ») lorsque le résultat
-- s'affiche ; les membres les plus touchés d'abord, `limit` au plus (3 par défaut).
function Damage.describe(bonesByLimb: { [string]: number }, limit: number?): string
	local injured = {}
	for order, limb in LIMB_ORDER do
		local bones = bonesByLimb[limb] or 0
		if bones > 0 then
			table.insert(injured, { limb = limb, bones = math.min(bones, #Damage.SEVERITY), order = order })
		end
	end
	if #injured == 0 then
		return "Not a scratch!"
	end
	table.sort(injured, function(a, b)
		if a.bones ~= b.bones then
			return a.bones > b.bones
		end
		return a.order < b.order
	end)
	local parts = {}
	for i = 1, math.min(#injured, limit or 3) do
		local entry = injured[i]
		local severity = Damage.SEVERITY[entry.bones]
		local text = (if i == 1 then severity else string.lower(severity)) .. " " .. Damage.LIMB_LABELS[entry.limb]
		table.insert(parts, text)
	end
	return table.concat(parts, ", ")
end

-- Cette méthode permet d'écrire la cause du plus gros choc (« Hit a brick wall at 140 km/h ») lorsque le résultat
-- s'affiche ; `speed` en studs/s (1 stud = 1 m).
function Damage.cause(kind: string, speed: number): string
	local label = CAUSE_LABELS[kind] or CAUSE_LABELS.Ground
	return string.format("%s at %d km/h", label, math.floor(speed * 3.6 + 0.5))
end

return Damage
