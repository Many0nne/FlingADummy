-- Habillage des pièges signatures (#33), en blocs à tenons : un modèle par colonne d'obstacles, centré sur la boîte de
-- déclenchement (Shared.TrackPlan). Tout est décor (ancré, sans collision) : l'effet du piège sur le mannequin est une
-- règle (Shared.Traps), appliquée par Server.LaunchService. Les pièces mobiles (pales, rondin, presse, diable…) sont
-- des modèles étiquetés Traps.MOTION_TAG que chaque client anime (Client.TrapMotion) : rien ne se réplique à chaque image.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrackPlan = require(ReplicatedStorage.Shared.TrackPlan)
local Traps = require(ReplicatedStorage.Shared.Traps)
local Build = require(script.Parent.Build)

type TrapBox = TrackPlan.TrapBox

local TrapProps = {}

local rgb = Color3.fromRGB
local WHITE, BLACK = rgb(250, 250, 250), rgb(35, 35, 40)
local YELLOW, RED = rgb(255, 210, 40), rgb(235, 50, 45)
local METAL = rgb(150, 155, 165)

-- Cette méthode permet de poser un bloc décoratif (repère local `at` du piège, rotation locale en degrés) lorsque l'on
-- habille un piège.
local function put(
	parent: Instance,
	at: CFrame,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	rotation: Vector3?
): Part
	local cframe = at * CFrame.new(offset)
	if rotation then
		cframe *= CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	end
	return Build.block(parent, size, cframe, color, false)
end

-- Cette méthode permet de poser un bloc lumineux (Neon) lorsque l'on habille un piège (lave, réacteur, voyant).
local function glow(
	parent: Instance,
	at: CFrame,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	rotation: Vector3?
): Part
	local p = put(parent, at, size, offset, color, rotation)
	p.Material = Enum.Material.Neon
	p.MaterialVariant = ""
	return p
end

-- Cette méthode permet de créer le modèle d'une pièce mobile (pivot au repère `pivot`) que chaque client anime
-- (`motion`, axe local, amplitude, période) lorsque l'on habille un piège ; renvoie le modèle à remplir.
local function moving(
	parent: Instance,
	pivot: CFrame,
	motion: string,
	axis: Vector3,
	amplitude: number,
	period: number
): Model
	local model = Instance.new("Model")
	model.Name = "Moving"
	local anchor = Build.decor({
		Name = "Pivot",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = pivot,
		Transparency = 1,
		Parent = model,
	})
	model.PrimaryPart = anchor
	-- Diffusé d'un bloc (instance streaming) : une pièce arrivée après les autres ne garde pas un décalage
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Motion", motion)
	model:SetAttribute("Axis", axis)
	model:SetAttribute("Amplitude", amplitude)
	model:SetAttribute("Period", period)
	model:SetAttribute("Home", pivot)
	CollectionService:AddTag(model, Traps.MOTION_TAG)
	model.Parent = parent
	return model
end

-- Cette méthode permet d'ajouter un émetteur de particules permanent (vent, bulles, confettis…) à une pièce lorsque
-- l'on habille un piège.
local function particles(part: BasePart, props: { [string]: any })
	local emitter = Instance.new("ParticleEmitter")
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = part
end

local builders: { [string]: (model: Model, at: CFrame, box: TrapBox) -> () } = {}

-- Cette méthode permet de monter un trampoline (pieds noirs, cadre bleu, ressorts jaunes, toile noire qui ondule) dans la
-- boîte lorsque la piste est construite.
builders.Trampoline = function(model, at)
	local blue = rgb(50, 140, 255)
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		put(model, at, Vector3.new(0.8, 2.6, 0.8), Vector3.new(corner.X * 5, 1.3, corner.Z * 4), BLACK)
	end
	for _, side in { -1, 1 } do
		put(model, at, Vector3.new(11.6, 0.8, 1.2), Vector3.new(0, 2.9, side * 4.4), blue)
		put(model, at, Vector3.new(1.2, 0.8, 9.6), Vector3.new(side * 5.4, 2.9, 0), blue)
		for i = -2, 2 do
			put(model, at, Vector3.new(0.4, 0.3, 0.9), Vector3.new(i * 2.2, 3.1, side * 3.6), YELLOW)
		end
	end
	local mat = moving(model, at * CFrame.new(0, 2.9, 0), "Bob", Vector3.yAxis, -0.5, 0.9)
	put(mat, at, Vector3.new(9.6, 0.2, 7.2), Vector3.new(0, 2.9, 0), rgb(40, 40, 50))
	glow(mat, at, Vector3.new(3, 0.25, 3), Vector3.new(0, 2.95, 0), rgb(255, 230, 80))
end

-- Cette méthode permet de dresser un ventilateur géant (pied, carter rouge carré incliné vers le ciel, pales blanches
-- qui tournent, souffle de particules) au début de la boîte lorsque la piste est construite.
builders.Fan = function(model, at, box)
	local back = -box.size.Z / 2 - 1.5
	local tilt = CFrame.Angles(math.rad(-25), 0, 0) -- regarde vers +Z et un peu vers le haut
	local hub = at * CFrame.new(0, 7, back) * tilt
	put(model, at, Vector3.new(3, 4.5, 3), Vector3.new(0, 2.25, back - 1), rgb(70, 72, 80))
	for _, side in { -1, 1 } do
		put(model, hub, Vector3.new(1.2, 12, 1.4), Vector3.new(side * 5.4, 0, 0), RED)
		put(model, hub, Vector3.new(12, 1.2, 1.4), Vector3.new(0, side * 5.4, 0), RED)
	end
	put(model, hub, Vector3.new(1.8, 1.8, 2.4), Vector3.new(0, 0, -0.6), rgb(70, 72, 80))
	-- Pales : tournent autour de l'axe du carter (Z local)
	local blades = moving(model, hub, "Spin", Vector3.zAxis, 0, 0.35)
	for i = 0, 3 do
		put(
			blades,
			hub * CFrame.Angles(0, 0, math.rad(i * 90)),
			Vector3.new(1.6, 4.6, 0.3),
			Vector3.new(0, 2.6, 0.2),
			WHITE
		)
	end
	local nozzle = put(model, hub, Vector3.new(9, 9, 0.2), Vector3.new(0, 0, 1), WHITE)
	nozzle.Transparency = 1
	particles(nozzle, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
		Transparency = NumberSequence.new(0.6, 1),
		Size = NumberSequence.new(1.5, 4),
		Lifetime = NumberRange.new(0.6, 0.9),
		Rate = 14,
		Speed = NumberRange.new(30, 40),
		SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Back, -- +Z local : vers la piste
	})
end

-- Cette méthode permet de monter un rondin qui balance entre deux troncs (poutre, cordes, rondin rayé) au-dessus de la
-- boîte lorsque la piste est construite.
builders.SwingLog = function(model, at, box)
	local top = box.size.Y + 3
	local bark = rgb(125, 80, 40)
	for _, side in { -1, 1 } do
		put(model, at, Vector3.new(2, top, 2), Vector3.new(side * 6.5, top / 2, 0), bark)
	end
	put(model, at, Vector3.new(15, 1.6, 1.6), Vector3.new(0, top, 0), rgb(150, 95, 50))
	-- Rondin suspendu : balance dans l'axe de la piste, entre les troncs (qu'il ne traverse pas) ; au passage il dévie le
	-- mannequin vers l'extérieur de la colonne (Shared.Traps)
	local swing = moving(model, at * CFrame.new(0, top, 0), "Swing", Vector3.xAxis, 50, 2.2)
	for _, x in { -3.5, 3.5 } do
		put(swing, at, Vector3.new(0.4, top - 6, 0.4), Vector3.new(x, top - (top - 6) / 2, 0), rgb(235, 215, 165))
	end
	local logY = 5
	put(swing, at, Vector3.new(10, 3, 3), Vector3.new(0, logY, 0), rgb(150, 95, 50))
	for _, x in { -5.1, 5.1 } do
		put(swing, at, Vector3.new(0.3, 2.6, 2.6), Vector3.new(x, logY, 0), rgb(230, 190, 130))
	end
	put(swing, at, Vector3.new(10.1, 0.6, 3.1), Vector3.new(0, logY, 0), RED)
end

-- Cette méthode permet de lever une vague en blocs (bleus de plus en plus clairs, crête d'écume blanche qui ondule) au
-- fond de la boîte lorsque la piste est construite.
builders.Wave = function(model, at, box)
	local blues = { rgb(30, 120, 220), rgb(45, 155, 235), rgb(70, 190, 245), rgb(120, 215, 250) }
	local back = -box.size.Z / 2
	local swell = moving(model, at, "Bob", Vector3.zAxis, 1.2, 1.6)
	for i, color in blues do
		local h = 2 + i * 1.6
		put(swell, at, Vector3.new(11.6, h, 2), Vector3.new(0, h / 2, back + (i - 1) * 2 + 1), color)
	end
	-- Crête qui se recourbe vers l'avant
	put(swell, at, Vector3.new(11.6, 1.6, 3), Vector3.new(0, 8.6, back + 7), rgb(120, 215, 250))
	put(swell, at, Vector3.new(11.6, 1, 2.4), Vector3.new(0, 9.7, back + 7.6), WHITE)
	local foam = put(model, at, Vector3.new(11.6, 0.3, box.size.Z), Vector3.new(0, 0.15, 0), rgb(170, 230, 255))
	foam.Transparency = 0.3
	particles(foam, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(WHITE),
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.5, 1),
		Rate = 10,
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Top,
	})
end

-- Cette méthode permet de faire tourner une tornade de sable (anneaux translucides de plus en plus larges vers le haut,
-- poussière) sur la boîte lorsque la piste est construite.
builders.Twister = function(model, at, box)
	local sand = rgb(235, 200, 130)
	local funnel = moving(model, at, "Spin", Vector3.yAxis, 0, 1.2)
	local rings = 9
	for i = 0, rings - 1 do
		local y = 1 + i * (box.size.Y - 2) / rings
		local width = 2 + i * 1.1
		local ring = put(
			funnel,
			at * CFrame.Angles(0, math.rad(i * 23), 0),
			Vector3.new(width, 3, width),
			Vector3.new(0, y, 0),
			sand
		)
		ring.Transparency = 0.35 + i * 0.03
	end
	local base = put(model, at, Vector3.new(6, 0.4, 6), Vector3.new(0, 0.2, 0), Build.shade(sand, 0.85))
	particles(base, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(sand),
		Transparency = NumberSequence.new(0.4, 1),
		Size = NumberSequence.new(3, 8),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 8,
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(15, 15),
		EmissionDirection = Enum.NormalId.Top,
		RotSpeed = NumberRange.new(-180, 180),
	})
end

-- Cette méthode permet de monter une presse hydraulique (portique jaune et noir, vérin, plateau d'acier qui s'abat)
-- au-dessus de la boîte lorsque la piste est construite.
builders.Press = function(model, at, box)
	local top = box.size.Y + 4
	for _, side in { -1, 1 } do
		put(model, at, Vector3.new(1.6, top, 2.4), Vector3.new(side * 6.4, top / 2, 0), YELLOW)
		for y = 2, top - 2, 4 do
			put(model, at, Vector3.new(1.7, 1.4, 2.5), Vector3.new(side * 6.4, y, 0), BLACK)
		end
	end
	put(model, at, Vector3.new(14.4, 2.4, 3), Vector3.new(0, top + 1.2, 0), YELLOW)
	put(model, at, Vector3.new(10, 0.4, 8), Vector3.new(0, 0.2, 0), rgb(90, 90, 100))
	-- Plateau et vérin : descendent jusqu'à poser le plateau sur la tôle du sol (amplitude négative sur Y)
	local ram = moving(model, at * CFrame.new(0, top - 1, 0), "Press", Vector3.yAxis, -(top - 5), Traps.PRESS_PERIOD)
	put(ram, at, Vector3.new(1.6, 3, 1.6), Vector3.new(0, top - 1.5, 0), METAL)
	put(ram, at, Vector3.new(10, 1.6, 7.6), Vector3.new(0, top - 3.8, 0), rgb(110, 115, 125))
	put(ram, at, Vector3.new(10.2, 0.4, 7.8), Vector3.new(0, top - 4.4, 0), RED)
end

-- Cette méthode permet de monter un aimant de grue (pylône en treillis, flèche, câble, électroaimant rouge à voyant)
-- au-dessus de la boîte lorsque la piste est construite.
builders.Magnet = function(model, at, box)
	local top = box.size.Y + 4
	put(model, at, Vector3.new(2.4, top, 2.4), Vector3.new(6.2, top / 2, -2), YELLOW)
	for y = 3, top - 3, 5 do
		put(model, at, Vector3.new(2.5, 0.6, 2.5), Vector3.new(6.2, y, -2), BLACK)
	end
	put(model, at, Vector3.new(10, 1.8, 1.8), Vector3.new(2, top, -2), YELLOW)
	put(model, at, Vector3.new(1.8, 1.8, 4), Vector3.new(-2.4, top, -0.2), YELLOW)
	local magnet = moving(model, at * CFrame.new(-2.4, top, 0), "Swing", Vector3.zAxis, 6, 3)
	local cableLength = top - box.size.Y * 0.55
	put(magnet, at, Vector3.new(0.3, cableLength, 0.3), Vector3.new(-2.4, top - cableLength / 2, 0), BLACK)
	local bottom = top - cableLength
	put(magnet, at, Vector3.new(6, 1.4, 6), Vector3.new(-2.4, bottom - 0.7, 0), RED)
	glow(magnet, at, Vector3.new(6.2, 0.4, 6.2), Vector3.new(-2.4, bottom - 1.5, 0), rgb(120, 220, 255))
end

-- Cette méthode permet de construire un tremplin de saut à ski (rampe blanche en marches qui monte vers l'avant, rails
-- bleus, drapeaux) dans la boîte lorsque la piste est construite.
builders.SkiJump = function(model, at, box)
	local steps = 6
	local depth = box.size.Z / steps
	local height = box.size.Y - 1
	for i = 1, steps do
		local h = height * i / steps
		put(model, at, Vector3.new(9, h, depth), Vector3.new(0, h / 2, -box.size.Z / 2 + (i - 0.5) * depth), WHITE)
		for _, side in { -1, 1 } do
			put(
				model,
				at,
				Vector3.new(0.8, 0.8, depth),
				Vector3.new(side * 4.9, h + 0.2, -box.size.Z / 2 + (i - 0.5) * depth),
				rgb(60, 140, 255)
			)
		end
	end
	for _, side in { -1, 1 } do
		put(model, at, Vector3.new(0.3, 5, 0.3), Vector3.new(side * 5.6, height + 2.5, box.size.Z / 2 - 0.5), BLACK)
		put(model, at, Vector3.new(0.2, 1.4, 2), Vector3.new(side * 5.6, height + 4.3, box.size.Z / 2 - 1.5), RED)
	end
end

-- Cette méthode permet de creuser un bassin de lave (margelle de basalte, lave lumineuse qui ondule, bulles) dans la
-- boîte lorsque la piste est construite.
builders.Lava = function(model, at, box)
	local basalt = rgb(70, 50, 55)
	local w, d = 11.6, box.size.Z
	for _, side in { -1, 1 } do
		put(model, at, Vector3.new(w, 1.2, 1.2), Vector3.new(0, 0.6, side * (d / 2 - 0.6)), basalt)
		put(model, at, Vector3.new(1.2, 1.2, d), Vector3.new(side * (w / 2 - 0.6), 0.6, 0), basalt)
	end
	local surface = moving(model, at, "Bob", Vector3.yAxis, 0.3, 1.4)
	local lava = glow(surface, at, Vector3.new(w - 2.4, 0.6, d - 2.4), Vector3.new(0, 0.5, 0), rgb(255, 110, 20))
	glow(surface, at, Vector3.new(3, 0.65, 2), Vector3.new(-2, 0.52, 1), rgb(255, 200, 40))
	particles(lava, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 60, 20)),
		LightEmission = 1,
		Size = NumberSequence.new(1.5, 0),
		Lifetime = NumberRange.new(0.5, 1),
		Rate = 12,
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
	})
end

-- Cette méthode permet de pointer un canon à confettis (affût sur roues, fût rayé rose et blanc incliné vers l'avant,
-- gueule dorée) au début de la boîte lorsque la piste est construite.
builders.Cannon = function(model, at, box)
	local pink = rgb(255, 110, 200)
	local back = -box.size.Z / 2 + 1.5
	for _, side in { -1, 1 } do
		put(model, at, Vector3.new(0.8, 3.6, 3.6), Vector3.new(side * 2.6, 1.8, back), rgb(150, 95, 50))
	end
	put(model, at, Vector3.new(4.4, 1.6, 3), Vector3.new(0, 3, back), rgb(110, 70, 40))
	-- Fût le long de +Z local, relevé de 30° vers l'avant de la piste
	local barrel = at * CFrame.new(0, 4.6, back) * CFrame.Angles(math.rad(-30), 0, 0)
	for i = 0, 3 do
		put(model, barrel, Vector3.new(3.2, 3.2, 1.5), Vector3.new(0, 0, i * 1.5), if i % 2 == 0 then pink else WHITE)
	end
	local mouth = put(model, barrel, Vector3.new(3.6, 3.6, 0.8), Vector3.new(0, 0, 6.1), rgb(255, 200, 50))
	particles(mouth, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 160)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 60)),
		}),
		Size = NumberSequence.new(0.7, 0.3),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 6,
		Speed = NumberRange.new(10, 16),
		SpreadAngle = Vector2.new(20, 20),
		Acceleration = Vector3.new(0, -20, 0),
		EmissionDirection = Enum.NormalId.Back,
	})
end

-- Cette méthode permet de poser un diable en boîte (caisse à damier, manivelle, ressort, tête de clown qui jaillit)
-- dans la boîte lorsque la piste est construite.
builders.JackBox = function(model, at)
	local colors = { rgb(255, 75, 75), rgb(50, 120, 240) }
	for i = 0, 1 do
		for j = 0, 1 do
			put(model, at, Vector3.new(3, 4, 3), Vector3.new((i - 0.5) * 3, 2, (j - 0.5) * 3), colors[(i + j) % 2 + 1])
		end
	end
	put(model, at, Vector3.new(1.2, 0.4, 0.4), Vector3.new(3.6, 2.6, 0), YELLOW)
	put(model, at, Vector3.new(0.4, 1.6, 0.4), Vector3.new(4.2, 2, 0), YELLOW)
	put(model, at, Vector3.new(6.4, 0.4, 3), Vector3.new(0, 4.3, -1.6), rgb(255, 200, 50), Vector3.new(-60, 0, 0))
	local jack = moving(model, at * CFrame.new(0, 4, 0), "Press", Vector3.yAxis, 4, 1.8)
	for k = 0, 3 do
		put(jack, at, Vector3.new(1.6, 0.4, 1.6), Vector3.new(0, 1 + k * 0.6, 0), METAL)
	end
	put(jack, at, Vector3.new(2.6, 2.6, 2.6), Vector3.new(0, 4, 0), WHITE)
	put(jack, at, Vector3.new(0.8, 0.8, 0.4), Vector3.new(0, 3.9, -1.4), RED)
	put(jack, at, Vector3.new(3.2, 1, 3.2), Vector3.new(0, 5.6, 0), rgb(120, 220, 110))
end

-- Cette méthode permet de dresser un anneau propulseur (cadre en blocs lunaires, anneaux de néon cyan qui pulsent sur
-- toute la hauteur de la colonne) sur la boîte lorsque la piste est construite.
builders.Booster = function(model, at, box)
	local frame = rgb(95, 75, 165)
	local h = box.size.Y + 1
	for _, side in { -1, 1 } do
		put(model, at, Vector3.new(1.2, h, 1.6), Vector3.new(side * 6.4, h / 2, 0), frame)
	end
	local pulse = moving(model, at, "Bob", Vector3.zAxis, 1.5, 0.6)
	local rings = math.max(2, math.floor(h / 14))
	for i = 1, rings do
		local y = (i - 0.5) * h / rings
		local ring = glow(pulse, at, Vector3.new(11.6, 0.6, 0.6), Vector3.new(0, y, 0), rgb(90, 230, 255))
		ring.Transparency = 0.2
	end
	glow(model, at, Vector3.new(11.6, 0.3, 4), Vector3.new(0, 0.15, 0), rgb(90, 230, 255))
end

-- Cette méthode permet d'habiller le piège d'une boîte (TrackPlan.trapBox) sous `parent` lorsque la piste est
-- construite ; un modèle par colonne.
function TrapProps.build(box: TrapBox, parent: Instance)
	local builder = builders[box.kind]
	if not builder then
		warn("[TrapProps] piège inconnu : " .. box.kind)
		return
	end
	local model = Instance.new("Model")
	model.Name = "Trap" .. box.kind
	model:SetAttribute("Trap", box.kind)
	builder(model, CFrame.new(box.x, 0, box.z), box)
	model.Parent = parent
end

return TrapProps
