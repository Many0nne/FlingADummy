-- Gabarit du mannequin de crash-test (pièces, rotules, couleurs, accessoires), partagé par le mannequin physique du
-- serveur et les mannequins décoratifs du client (tenu, poids d'entraînement). Studs, debout, centre du torse à
-- l'origine. Les pièces sont des MeshPart clonées depuis ReplicatedStorage.DummyTemplates (maillages Blender créés par
-- Server.DummyAssets) ; sans gabarits (assets non publiés, chargement raté) on se rabat sur des blocs. Les modèles de
-- collection (#66) ajoutent des pièces maillées, des couleurs par pièce, des pièces masquées et des effets
-- (Shared.DummyModels, généré depuis assets/dummy/build_collection.py).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"))
local DummyModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DummyModels"))

local DummyShape = {}

DummyShape.YELLOW = Color3.fromRGB(255, 205, 40)
DummyShape.DARK = Color3.fromRGB(45, 47, 55)
DummyShape.TEMPLATES = "DummyTemplates"
-- SurfaceAppearance de l'atlas (Shared.DummySurface, synchronisée par Rojo) clonée dans chaque gabarit maillé
DummyShape.SURFACE = "DummySurface"
-- Pièces ajoutées animées (rotation, flottement) : animées côté client par Client.DummyFx
DummyShape.FX_TAG = "DummyFx"
DummyShape.FX_WELD = "FxWeld"

local ARM = Vector3.new(0.8, 1.2, 0.8)
local LEG = Vector3.new(0.95, 1.3, 0.95)

export type Piece = { name: string, size: Vector3, position: Vector3, color: Color3 }

-- Déclinaison (collection, boutique, équipement d'entraînement) : couleur des zones claires (et par pièce), matériau,
-- pièces masquées, pièces ajoutées (accessoires, couleur imposée pour la silhouette du tirage), effets
export type Variant = {
	color: Color3?,
	material: Enum.Material?,
	pieceColors: { [string]: Color3 }?,
	hidden: { string }?,
	accessories: { string }?,
	accessoryColor: Color3?,
	effects: { DummyModels.Effect }?,
}

-- Tailles = boîtes des maillages (assets/dummy/build_dummy.py vérifie qu'ils les remplissent exactement)
DummyShape.PIECES = {
	{ name = "Torso", size = Vector3.new(2, 2.4, 1.1), position = Vector3.new(0, 0, 0), color = DummyShape.YELLOW },
	{ name = "Head", size = Vector3.new(1.5, 1.5, 1.5), position = Vector3.new(0, 2.1, 0), color = DummyShape.YELLOW },
	{ name = "LeftUpperArm", size = ARM, position = Vector3.new(-1.45, 0.6, 0), color = DummyShape.YELLOW },
	{ name = "LeftLowerArm", size = ARM, position = Vector3.new(-1.45, -0.62, 0), color = DummyShape.DARK },
	{ name = "RightUpperArm", size = ARM, position = Vector3.new(1.45, 0.6, 0), color = DummyShape.YELLOW },
	{ name = "RightLowerArm", size = ARM, position = Vector3.new(1.45, -0.62, 0), color = DummyShape.DARK },
	{ name = "LeftUpperLeg", size = LEG, position = Vector3.new(-0.5, -1.85, 0), color = DummyShape.YELLOW },
	{ name = "LeftLowerLeg", size = LEG, position = Vector3.new(-0.5, -3.17, 0), color = DummyShape.DARK },
	{ name = "RightUpperLeg", size = LEG, position = Vector3.new(0.5, -1.85, 0), color = DummyShape.YELLOW },
	{ name = "RightLowerLeg", size = LEG, position = Vector3.new(0.5, -3.17, 0), color = DummyShape.DARK },
} :: { Piece }

-- parent, enfant, position de la rotule, demi-angle du cône (degrés), sens du membre (axe des attachements)
DummyShape.JOINTS = {
	{ "Torso", "Head", Vector3.new(0, 1.28, 0), 40, Vector3.yAxis },
	{ "Torso", "LeftUpperArm", Vector3.new(-1.45, 1.05, 0), 110, -Vector3.yAxis },
	{ "LeftUpperArm", "LeftLowerArm", Vector3.new(-1.45, -0.01, 0), 100, -Vector3.yAxis },
	{ "Torso", "RightUpperArm", Vector3.new(1.45, 1.05, 0), 110, -Vector3.yAxis },
	{ "RightUpperArm", "RightLowerArm", Vector3.new(1.45, -0.01, 0), 100, -Vector3.yAxis },
	{ "Torso", "LeftUpperLeg", Vector3.new(-0.5, -1.2, 0), 80, -Vector3.yAxis },
	{ "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.5, -2.51, 0), 100, -Vector3.yAxis },
	{ "Torso", "RightUpperLeg", Vector3.new(0.5, -1.2, 0), 80, -Vector3.yAxis },
	{ "RightUpperLeg", "RightLowerLeg", Vector3.new(0.5, -2.51, 0), 100, -Vector3.yAxis },
}

-- Pièces ajoutées des modèles de collection (maillages de assets/dummy/export/collection.fbx) : pièce porteuse, boîte,
-- décalage du centre par rapport à la pièce, couleur, matériau, animation
DummyShape.ACCESSORIES = DummyModels.ADDONS

-- Textures des effets : celles du jeu (Shared.Assets.FX_TEXTURES, assets/fx) une fois publiées, sinon une texture de
-- Roblox de forme proche
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FALLBACK = {
	star = SPARKLE,
	glow = SPARKLE,
	ring = SPARKLE,
	bubble = SPARKLE,
	flake = SPARKLE,
	note = SPARKLE,
	rays = SPARKLE,
	beam = SPARKLE,
}

-- Cette méthode permet de donner l'URI d'une texture d'effet (publiée, sinon celle de Roblox) lorsque l'on crée un
-- émetteur ou un faisceau ; une URI rbxasset:// passe telle quelle.
function DummyShape.fxTexture(name: string): string
	return Assets.uri(Assets.FX_TEXTURES[name]) or FALLBACK[name] or name
end

-- Particules des effets, tailles et vitesses en studs à l'échelle 1. `form` : courbe de taille (pop par défaut :
-- éclot puis s'éteint ; twinkle : scintille ; grow : s'élargit en s'effaçant, onde au sol ; faint : halo pâle fixe).
-- `flat` : couché à plat face au ciel (au sol) ; `locked` : suit la pièce ; `back` : dessiné derrière le mannequin ;
-- `down` : émis vers le bas (réacteur) ; `alpha` : transparence de départ.
DummyShape.PARTICLES = {
	sparkle = { texture = "star", size = 0.45, rate = 8, life = 1.2, speed = 1.5, spread = 180, light = 1 },
	stars = { texture = "star", size = 0.55, rate = 12, life = 1.6, speed = 2.5, spread = 180, light = 1 },
	glint = {
		texture = "star",
		size = 0.6,
		rate = 5,
		life = 0.8,
		speed = 3.5,
		spread = 180,
		light = 1,
		drag = 6,
		form = "twinkle",
	},
	burst = { texture = "star", size = 0.7, rate = 5, life = 1.1, speed = 8, spread = 180, light = 1, drag = 4 },
	fire = { texture = FIRE, size = 1.3, rate = 22, life = 0.7, speed = 4, spread = 15, light = 0.8, rise = 4 },
	jet = { texture = FIRE, size = 0.9, rate = 30, life = 0.35, speed = 9, spread = 8, light = 0.9, down = true },
	embers = { texture = "star", size = 0.25, rate = 10, life = 1.6, speed = 2, spread = 180, light = 1, rise = 3 },
	wisp = { texture = SMOKE, size = 1.6, rate = 6, life = 2, speed = 0.8, spread = 60, light = 0.6, rise = -0.5 },
	smoke = {
		texture = SMOKE,
		size = 1.2,
		rate = 4,
		life = 1.8,
		speed = 1.5,
		spread = 25,
		light = 0,
		rise = 1.5,
		alpha = 0.5,
	},
	vortex = { texture = "star", size = 0.5, rate = 16, life = 1, speed = 6, spread = 180, light = 1, drag = 5 },
	aura = {
		texture = "glow",
		size = 6,
		rate = 1.5,
		life = 1.5,
		speed = 0,
		spread = 0,
		light = 0.6,
		form = "faint",
		locked = true,
		alpha = 0.88,
	},
	motes = { texture = "glow", size = 0.4, rate = 10, life = 2.2, speed = 2.4, spread = 35, light = 1, rise = 0.4 },
	bubbles = { texture = "bubble", size = 0.45, rate = 4, life = 2.2, speed = 1.8, spread = 25, light = 0.3, rise = 1 },
	snow = { texture = "flake", size = 0.45, rate = 6, life = 2.6, speed = 1.4, spread = 180, light = 0.6, rise = -1.2 },
	notes = { texture = "note", size = 0.6, rate = 1.5, life = 2, speed = 1.6, spread = 35, light = 0.5, rise = 0.4 },
	-- Grands effets (anneau, flaque, rayons) : peu de particules à la fois et pâles, sinon le Bloom de l'éclairage
	-- blanchit toute la base
	ring = {
		texture = "ring",
		size = 4.5,
		rate = 0.7,
		life = 1.6,
		speed = 0,
		spread = 0,
		light = 0.7,
		form = "grow",
		flat = true,
		locked = true,
		alpha = 0.4,
	},
	pool = {
		texture = "glow",
		size = 3.5,
		rate = 1,
		life = 2,
		speed = 0,
		spread = 0,
		light = 0.5,
		form = "faint",
		flat = true,
		locked = true,
		alpha = 0.8,
	},
	rays = {
		texture = "rays",
		size = 6.5,
		rate = 0.5,
		life = 3,
		speed = 0,
		spread = 0,
		light = 0.5,
		form = "faint",
		locked = true,
		back = true,
		alpha = 0.65,
		spin = 18,
	},
} :: { [string]: { [string]: any } }

-- Cette méthode permet de donner la courbe de taille d'un émetteur (taille `size` en studs, forme du préréglage)
-- lorsque l'on crée l'émetteur d'un effet.
local function sizeCurve(form: string?, size: number): NumberSequence
	if form == "faint" then
		return NumberSequence.new(size * 0.8, size)
	elseif form == "grow" then
		return NumberSequence.new(size * 0.3, size)
	elseif form == "twinkle" then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, size),
			NumberSequenceKeypoint.new(0.5, size * 0.35),
			NumberSequenceKeypoint.new(0.75, size * 0.8),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.4),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
end

-- Cette méthode permet de peindre une cible de crash-test (disque jaune à deux quartiers noirs) sur une face d'une
-- pièce lorsque le mannequin est en blocs de repli (les maillages portent déjà leurs cibles).
function DummyShape.addTarget(part: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(100, 100)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.LightInfluence = 1
	local disc = Instance.new("CanvasGroup")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.42)
	disc.Size = UDim2.fromScale(0.62, 0.62)
	disc.SizeConstraint = Enum.SizeConstraint.RelativeYY
	disc.BackgroundColor3 = DummyShape.YELLOW
	disc.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	for _, quadrant in { Vector2.new(0, 0), Vector2.new(0.5, 0.5) } do
		local quarter = Instance.new("Frame")
		quarter.BorderSizePixel = 0
		quarter.BackgroundColor3 = Color3.new(0, 0, 0)
		quarter.Position = UDim2.fromScale(quadrant.X, quadrant.Y)
		quarter.Size = UDim2.fromScale(0.5, 0.5)
		quarter.Parent = disc
	end
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(0, 0, 0)
	ring.Thickness = 3
	ring.Parent = disc
	gui.Parent = part
end

-- Cette méthode permet de savoir si les gabarits maillés sont prêts lorsque l'on construit un mannequin.
function DummyShape.isMeshed(): boolean
	local folder = ReplicatedStorage:FindFirstChild(DummyShape.TEMPLATES)
	return folder ~= nil and folder:GetAttribute("Ready") == true
end

-- Cette méthode permet de créer une pièce (maillée si son gabarit existe, bloc sinon) à la taille voulue lorsque
-- l'on construit un mannequin ; nil pour un accessoire sans maillage.
function DummyShape.makePart(name: string, size: Vector3): BasePart?
	local folder = ReplicatedStorage:FindFirstChild(DummyShape.TEMPLATES)
	local template = folder and folder:GetAttribute("Ready") and folder:FindFirstChild(name)
	local part: BasePart
	if template then
		part = (template :: BasePart):Clone()
	elseif DummyShape.ACCESSORIES[name] then
		return nil
	else
		part = Instance.new("Part")
	end
	part.Name = name
	part.Size = size
	part.Material = Enum.Material.SmoothPlastic
	return part
end

-- Cette méthode permet de donner la couleur d'une pièce lorsque l'on habille un mannequin : tout le corps prend la
-- couleur de la déclinaison quand l'atlas est posé (le noir est dans la texture), seules les zones jaunes sinon.
function DummyShape.colorOf(piece: Piece, part: BasePart, variant: Variant?): Color3
	local tint = variant and (variant.pieceColors and variant.pieceColors[piece.name] or variant.color)
	if part:FindFirstChild(DummyShape.SURFACE) then
		return tint or DummyShape.YELLOW
	end
	return if tint and piece.color == DummyShape.YELLOW then tint else piece.color
end

-- Cette méthode permet de donner le matériau d'une pièce lorsque l'on habille un mannequin ; un matériau de
-- déclinaison retire l'atlas (une SurfaceAppearance masquerait le verre, le néon ou le champ de force).
function DummyShape.applyMaterial(part: BasePart, variant: Variant?): Enum.Material
	local material = variant and variant.material
	if not material or material == Enum.Material.SmoothPlastic then
		return Enum.Material.SmoothPlastic
	end
	local surface = part:FindFirstChild(DummyShape.SURFACE)
	if surface then
		surface:Destroy()
	end
	return material
end

-- Cette méthode permet de créer les pièces d'un mannequin debout à l'échelle `scale` (couleur, matériau, cibles des
-- blocs) lorsque le serveur ou le client en construit un ; renvoie les pièces par nom.
function DummyShape.buildPieces(model: Model, scale: number, variant: Variant?): { [string]: BasePart }
	local parts: { [string]: BasePart } = {}
	for _, piece in DummyShape.PIECES do
		local p = DummyShape.makePart(piece.name, piece.size * scale) :: BasePart
		p.CFrame = CFrame.new(piece.position * scale)
		p.Material = DummyShape.applyMaterial(p, variant) -- avant la couleur : retire l'atlas si besoin
		p.Color = DummyShape.colorOf(piece, p, variant)
		-- Pièce remplacée par une pièce ajoutée (queue du fantôme) : masquée seulement si les maillages des pièces
		-- ajoutées sont là, sinon le mannequin en blocs perdrait ses jambes sans rien à leur place
		if variant and variant.hidden and table.find(variant.hidden, piece.name) and DummyShape.isMeshed() then
			p.Transparency = 1
		end
		p.Parent = model
		parts[piece.name] = p
	end
	if not parts.Torso:IsA("MeshPart") then
		DummyShape.addTarget(parts.Torso, Enum.NormalId.Front)
		DummyShape.addTarget(parts.Torso, Enum.NormalId.Back)
	end
	return parts
end

-- Cette méthode permet de donner le décalage d'une pièce animée par rapport à sa pièce porteuse (position de repos
-- `base` à l'échelle de construction, multipliée par `scale`, flottement vertical puis rotation sur elle-même) à
-- l'instant `t` lorsque Client.DummyFx anime une pièce ajoutée.
function DummyShape.fxOffset(base: CFrame, scale: number, t: number, spin: Vector3?, bob: Vector2?): CFrame
	local position = base.Position * scale
	if bob and bob.Y > 0 then
		position += Vector3.new(0, bob.X * scale * math.sin(2 * math.pi * t / bob.Y), 0)
	end
	local offset = CFrame.new(position) * base.Rotation
	if spin and spin.Magnitude > 0 then
		offset *= CFrame.fromAxisAngle(spin.Unit, math.rad(spin.Magnitude * t))
	end
	return offset
end

-- Cette méthode permet de souder une pièce ajoutée à sa pièce porteuse lorsque l'on la pose : soudure fixe, ou Weld
-- nommé FX_WELD et étiquette FX_TAG si elle tourne ou flotte (attributs lus par Client.DummyFx ; position de repos et
-- amplitude du flottement à l'échelle de construction `scale`).
local function attachAddon(
	accessory: BasePart,
	carrier: BasePart,
	offset: CFrame,
	def: DummyModels.Addon,
	scale: number
)
	if def.spin or def.bob then
		local weld = Instance.new("Weld")
		weld.Name = DummyShape.FX_WELD
		weld.Part0 = carrier
		weld.Part1 = accessory
		weld.C0 = offset
		weld.Parent = accessory
		accessory:SetAttribute("FxBase", offset)
		if def.spin then
			accessory:SetAttribute("FxSpin", def.spin.axis.Unit * def.spin.speed)
		end
		if def.bob then
			accessory:SetAttribute("FxBob", Vector2.new(def.bob.amplitude * scale, def.bob.period))
		end
		accessory:AddTag(DummyShape.FX_TAG)
	else
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = carrier
		weld.Part1 = accessory
		weld.Parent = accessory
	end
end

-- Cette méthode permet de créer l'émetteur d'un effet de particules (préréglage de PARTICLES, deux couleurs, taille et
-- débit multipliés par l'effet, taille et vitesses à l'échelle) lorsque l'on pose les effets d'un mannequin ; nil
-- pour un préréglage inconnu.
function DummyShape.makeEmitter(effect: DummyModels.Effect, scale: number): ParticleEmitter?
	local preset = DummyShape.PARTICLES[effect.preset or ""]
	if not preset then
		return nil
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fx_" .. (effect.preset :: string)
	emitter.Texture = DummyShape.fxTexture(preset.texture)
	emitter.Color = ColorSequence.new(effect.color, effect.color2 or effect.color)
	emitter.LightEmission = preset.light
	emitter.LightInfluence = if preset.light > 0 then 0 else 1
	emitter.Size = sizeCurve(preset.form, preset.size * (effect.size or 1) * scale)
	local alpha = preset.alpha or (if preset.form == "faint" then 0.82 elseif preset.form == "grow" then 0.2 else 0.1)
	emitter.Transparency = NumberSequence.new(alpha, 1)
	emitter.Lifetime = NumberRange.new(preset.life * 0.7, preset.life * 1.3)
	emitter.Rate = preset.rate * (effect.rate or 1)
	if preset.flat then
		-- Couché face au ciel : orienté perpendiculairement à une vitesse verticale presque nulle
		emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		emitter.Speed = NumberRange.new(0.01)
	else
		emitter.Speed = NumberRange.new(preset.speed * 0.6 * scale, preset.speed * scale)
	end
	emitter.EmissionDirection = if preset.down then Enum.NormalId.Bottom else Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(preset.spread, preset.spread)
	emitter.Acceleration = Vector3.new(0, (preset.rise or 0) * scale, 0)
	emitter.Drag = preset.drag or 0
	local spin = preset.spin or 90
	emitter.RotSpeed = if preset.spin then NumberRange.new(spin) else NumberRange.new(-spin, spin)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.LockedToPart = preset.locked == true
	emitter.ZOffset = if preset.back then -2 else 0
	return emitter
end

-- Cette méthode permet de créer le faisceau d'un effet « beam » (colonne de lumière dressée de `height` studs au-dessus
-- de l'attachement, face à la caméra, texture qui défile vers le haut) lorsque l'on pose les effets d'un mannequin ;
-- renvoie le faisceau et l'attachement du haut.
function DummyShape.makeBeam(effect: DummyModels.Effect, scale: number, bottom: Attachment): (Beam, Attachment)
	local top = Instance.new("Attachment")
	top.Name = bottom.Name .. "Top"
	top.Position = bottom.Position + Vector3.new(0, (effect.height or 16) * scale, 0)
	local beam = Instance.new("Beam")
	beam.Name = "Fx_beam"
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Texture = DummyShape.fxTexture("beam")
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.TextureSpeed = 0.5
	beam.FaceCamera = true
	beam.Segments = 1
	local width = (effect.width or 3) * (effect.size or 1) * scale
	beam.Width0 = width
	beam.Width1 = width * 0.55
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Brightness = 1
	beam.Color = ColorSequence.new(effect.color, effect.color2 or effect.color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	return beam, top
end

-- Cette méthode permet de poser les effets d'une déclinaison (particules, lumières et faisceaux sur des attachements
-- des pièces porteuses) lorsque l'on habille un mannequin de collection.
function DummyShape.addEffects(parts: { [string]: BasePart }, scale: number, variant: Variant?)
	if not variant or not variant.effects then
		return
	end
	for index, effect in variant.effects do
		local carrier = parts[effect.piece]
		if not carrier then
			continue
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "Fx" .. index
		attachment.Position = effect.offset * scale
		if effect.kind == "light" then
			local light = Instance.new("PointLight")
			light.Color = effect.color
			light.Range = (effect.range or 12) * scale
			light.Brightness = effect.brightness or 2
			light.Shadows = false
			light.Parent = attachment
		elseif effect.kind == "particles" then
			local emitter = DummyShape.makeEmitter(effect, scale)
			if emitter then
				emitter.Parent = attachment
			end
		elseif effect.kind == "beam" then
			local beam, top = DummyShape.makeBeam(effect, scale, attachment)
			top.Parent = carrier
			beam.Parent = attachment
		end
		attachment.Parent = carrier
	end
end

-- Cette méthode permet de poser les pièces ajoutées d'une déclinaison sur un mannequin debout (soudées à leur pièce,
-- sans masse ni collision, couleur et matériau du modèle) puis ses effets lorsque l'on le construit ; pièces
-- ignorées sans maillages.
function DummyShape.addAccessories(model: Model, parts: { [string]: BasePart }, scale: number, variant: Variant?)
	if not variant then
		return
	end
	local names: { string } = variant.accessories or {}
	for _, name in names do
		local def = DummyShape.ACCESSORIES[name]
		local carrier = def and parts[def.piece]
		local accessory = carrier and DummyShape.makePart(name, def.size * scale)
		if accessory then
			local offset = CFrame.new(def.offset * scale)
			accessory.CFrame = carrier.CFrame * offset
			accessory.Color = variant.accessoryColor or def.color
			accessory.Material = def.material
			accessory.Transparency = def.transparency or 0
			accessory.Massless = true
			accessory.CanCollide = false
			accessory.CanQuery = false
			accessory.CanTouch = false
			accessory.CastShadow = def.material ~= Enum.Material.Neon
			accessory:SetAttribute("Accessory", true)
			attachAddon(accessory, carrier, offset, def, scale)
			accessory.Parent = model
		end
	end
	DummyShape.addEffects(parts, scale, variant)
end

-- Cette méthode permet de construire un mannequin décoratif soudé (une seule pièce mobile, sans masse ni collision)
-- lorsque le client affiche un mannequin tenu ou soulevé ; `variant` le décline (équipement d'entraînement).
function DummyShape.buildVisual(scale: number, variant: Variant?): Model
	local model = Instance.new("Model")
	model.Name = "VisualDummy"
	local parts = DummyShape.buildPieces(model, scale, variant)
	DummyShape.addAccessories(model, parts, scale, variant)
	local root = parts.Torso
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Anchored = false
			if
				p ~= root
				and not p:FindFirstChildOfClass("WeldConstraint")
				and not p:FindFirstChild(DummyShape.FX_WELD)
			then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	model.PrimaryPart = root
	return model
end

return DummyShape
