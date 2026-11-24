-- Portails des tours de piste (#224) : à la ligne d'arrivée, un grand portail en briques à tenons aux couleurs de
-- l'arc-en-ciel (piliers et linteau empilés, comme les blocs saturés des jeux de référence 01 et 09), rideau violet
-- lumineux et tourbillon néon qui tourne, où le mannequin entre ; au début de la piste, juste après la bande de lancer,
-- un portail de sortie plus petit d'où il ressort pour le tour suivant (Shared.Laps). Rien n'arrête le mannequin :
-- pièces traversables, le passage est décidé par Server.LaunchService (ligne d'arrivée franchie). Portails à la demande
-- (#231) : ils ne sont pas posés sur la piste, mais rangés en modèles de référence (ReplicatedStorage.PortalTemplates, Server.init)
-- que chaque client ouvre le temps d'un passage, puis referme (Client.PortalFx : tourbillon animé par le client).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Laps = require(Shared.Laps)
local Zones = require(Shared.Zones)

local Build = require(script.Parent.Build)

local Portals = {}

Portals.BRICK = 8 -- côté des briques des piliers (studs) : le décor au pied des parois s'arrête avant eux
-- Briques des piliers et du linteau, de bas en haut (arc-en-ciel saturé)
local RAINBOW = {
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(255, 150, 30),
	Color3.fromRGB(255, 220, 50),
	Color3.fromRGB(80, 210, 70),
	Color3.fromRGB(60, 150, 255),
	Color3.fromRGB(170, 70, 255),
}
local CURTAIN = Color3.fromRGB(150, 60, 255) -- rideau du portail (violet de Client.FlightView, badge « LAP »)
local SWIRL = { Color3.fromRGB(255, 80, 220), Color3.fromRGB(80, 230, 255) } -- bras du tourbillon, en alternance
local BRICK = Portals.BRICK
local WALL_GAP = 2 -- piliers écartés des parois du canyon (studs) : pas de face confondue avec leurs coulures

-- Mesures d'un portail : `half` (demi-largeur intérieure), `bottom` et `top` (hauteurs du rideau), `swirl` (rayon)
type Shape = { half: number, bottom: number, top: number, swirl: number, z: number, arms: number }

-- Cette méthode permet de créer le modèle d'une pièce mobile qui tourne autour de l'axe de la piste (pivot `pivot`,
-- un tour en `period` s, animée par Client.PortalFx) lorsque l'on pose le tourbillon d'un portail ; renvoie le modèle.
local function spinner(parent: Instance, pivot: CFrame, period: number): Model
	local model = Instance.new("Model")
	model.Name = "Swirl"
	local anchor = Build.decor({
		Name = "Pivot",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = pivot,
		Transparency = 1,
		Parent = model,
	})
	model.PrimaryPart = anchor
	model:SetAttribute("Period", period)
	model.Parent = parent
	return model
end

-- Cette méthode permet de poser un bloc lumineux traversable (Neon) lorsque l'on habille le rideau ou le tourbillon.
local function glow(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, transparency: number?): Part
	local part = Build.decor({
		Name = "Glow",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0,
		CastShadow = false,
		Parent = parent,
	})
	return part
end

-- Cette méthode permet de dresser un portail (piliers et linteau en briques arc-en-ciel, rideau violet, tourbillon,
-- étincelles aspirées) de mesures `shape` lorsque la piste est construite ; renvoie le modèle.
local function portal(parent: Instance, name: string, shape: Shape): Model
	local model = Instance.new("Model")
	model.Name = name
	local z, half = shape.z, shape.half
	local pillarX = half + BRICK / 2
	-- Piliers : briques empilées du sol au-dessus du rideau, couleurs décalées d'un pilier à l'autre
	local count = math.ceil(shape.top / BRICK)
	for _, side in { -1, 1 } do
		for i = 0, count - 1 do
			local color = RAINBOW[(i + (if side < 0 then 0 else 3)) % #RAINBOW + 1]
			Build.block(
				model,
				Vector3.new(BRICK, BRICK, BRICK),
				CFrame.new(side * pillarX, (i + 0.5) * BRICK, z),
				color,
				false
			)
		end
	end
	-- Linteau : une rangée de briques par-dessus, piliers compris
	local top = count * BRICK
	local span = 2 * (half + BRICK)
	local bricks = math.max(math.floor(span / BRICK + 0.5), 1)
	local width = span / bricks
	for i = 0, bricks - 1 do
		Build.block(
			model,
			Vector3.new(width, BRICK, BRICK),
			CFrame.new(-span / 2 + (i + 0.5) * width, top + BRICK / 2, z),
			RAINBOW[i % #RAINBOW + 1],
			false
		)
	end
	-- Rideau lumineux entre les piliers, et tourbillon néon devant lui (côté du départ)
	local height = shape.top - shape.bottom
	local curtain =
		glow(model, Vector3.new(2 * half, height, 0.4), CFrame.new(0, shape.bottom + height / 2, z), CURTAIN, 0.55)
	local hub = CFrame.new(0, shape.bottom + height / 2, z - 0.6)
	local swirl = spinner(model, hub, 2.4)
	local segments = 6
	for arm = 0, shape.arms - 1 do
		for k = 1, segments do
			local angle = 2 * math.pi * arm / shape.arms + k * 0.42
			local radius = shape.swirl * k / segments
			local size = 1.2 + 2.4 * k / segments
			glow(
				swirl,
				Vector3.new(size * 2.2, size, 0.4),
				hub * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0) * CFrame.Angles(0, 0, math.rad(70)),
				SWIRL[arm % #SWIRL + 1]
			)
		end
	end
	glow(model, Vector3.new(4, 4, 0.5), hub * CFrame.new(0, 0, -0.1), Color3.new(1, 1, 1))
	-- Étincelles aspirées vers le cœur du portail
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(SWIRL[1], Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(1.6, 0)
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Rate = 30
	sparks.Speed = NumberRange.new(-14, -6)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Parent = curtain
	local light = Instance.new("PointLight")
	light.Color = CURTAIN
	light.Range = 60
	light.Brightness = 2
	light.Parent = curtain
	-- Pivot au cœur du rideau : le client ouvre le portail depuis son centre
	model.WorldPivot = CFrame.new(0, shape.bottom + height / 2, z)
	model.Parent = parent
	return model
end

-- Cette méthode permet de dresser le portail de la ligne d'arrivée (rideau du sol au-dessus du plafond du vol, panneau
-- « FINISH 6 KM » au linteau) lorsque les modèles de référence sont rangés.
local function buildFinish(parent: Instance)
	local half = GameConfig.TRACK_WIDTH / 2 - BRICK - WALL_GAP
	local model = portal(parent, "FinishPortal", {
		half = half,
		bottom = 0,
		top = GameConfig.APEX_HEIGHT + 20,
		swirl = half - 2,
		z = GameConfig.COURSE_LENGTH,
		arms = 4,
	})
	local last = Zones.LIST[#Zones.LIST]
	local top = math.ceil((GameConfig.APEX_HEIGHT + 20) / BRICK) * BRICK
	local board = Build.block(
		model,
		Vector3.new(40, 9, 1),
		CFrame.new(0, top + BRICK + 5, GameConfig.COURSE_LENGTH - 1),
		last.color,
		false
	)
	Build.surfaceText(board, Enum.NormalId.Front, string.format("FINISH %g KM  >>  NEXT LAP", Laps.LENGTH / 1000))
end

-- Cette méthode permet de dresser le portail de sortie au début de la piste (rideau autour de la hauteur de sortie,
-- au-dessus des joueurs de la bande) lorsque les modèles de référence sont rangés.
local function buildExit(parent: Instance)
	local half = GameConfig.TRACK_WIDTH / 2 - BRICK - WALL_GAP
	portal(parent, "ExitPortal", {
		half = half,
		bottom = Laps.EXIT_HEIGHT - 12,
		top = Laps.EXIT_HEIGHT + 16,
		swirl = 12,
		z = Laps.EXIT_Z,
		arms = 3,
	})
end

-- Cette méthode permet de ranger les modèles de référence des deux portails (FinishPortal, ExitPortal, à leur place
-- sur la piste) dans `parent` (PortalTemplates) lorsque le serveur démarre (#231 : ouverts par Client.PortalFx).
function Portals.build(parent: Instance)
	local old = parent:FindFirstChild("PortalTemplates")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PortalTemplates"
	Build.settled(buildFinish, folder)
	Build.settled(buildExit, folder)
	folder.Parent = parent
end

return Portals
