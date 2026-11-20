-- Gabarit du mannequin de crash-test (pièces, rotules, couleurs, accessoires), partagé par le mannequin physique du
-- serveur et les mannequins décoratifs du client (tenu, poids d'entraînement). Studs, debout, centre du torse à
-- l'origine. Les pièces sont des MeshPart clonées depuis ReplicatedStorage.DummyTemplates (maillages Blender créés par
-- Server.DummyAssets) ; sans gabarits (assets non publiés, chargement raté) on se rabat sur des blocs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DummyShape = {}

DummyShape.YELLOW = Color3.fromRGB(255, 205, 40)
DummyShape.DARK = Color3.fromRGB(45, 47, 55)
DummyShape.ACCESSORY_COLOR = Color3.fromRGB(235, 60, 50)
DummyShape.TEMPLATES = "DummyTemplates"
-- SurfaceAppearance de l'atlas (Shared.DummySurface, synchronisée par Rojo) clonée dans chaque gabarit maillé
DummyShape.SURFACE = "DummySurface"

local ARM = Vector3.new(0.8, 1.2, 0.8)
local LEG = Vector3.new(0.95, 1.3, 0.95)

export type Piece = { name: string, size: Vector3, position: Vector3, color: Color3 }

-- Déclinaison (collection, boutique, équipement d'entraînement) : couleur des zones claires, matériau, accessoires
export type Variant = {
	color: Color3?,
	material: Enum.Material?,
	accessories: { string }?,
	accessoryColor: Color3?,
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

-- Accessoires (maillages du même FBX) : pièce porteuse, boîte, décalage du centre par rapport à la pièce
-- (valeurs de assets/dummy/export/accessories.json)
DummyShape.ACCESSORIES = {
	Helmet = { piece = "Head", size = Vector3.new(1.64, 0.68, 1.74), offset = Vector3.new(0, 0.71, -0.06) },
	Glasses = { piece = "Head", size = Vector3.new(1.6, 0.36, 0.52), offset = Vector3.new(0, 0.2, -0.56) },
	Cape = { piece = "Torso", size = Vector3.new(1.9, 2.96, 0.35), offset = Vector3.new(0, -0.27, 0.545) },
} :: { [string]: { piece: string, size: Vector3, offset: Vector3 } }

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
-- couleur de la déclinaison quand il est maillé (le noir est dans la texture), seules les zones jaunes en blocs.
function DummyShape.colorOf(piece: Piece, part: BasePart, variant: Variant?): Color3
	local tint = variant and variant.color
	if part:IsA("MeshPart") then
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
		p.Color = DummyShape.colorOf(piece, p, variant)
		p.Material = DummyShape.applyMaterial(p, variant)
		p.Parent = model
		parts[piece.name] = p
	end
	if not parts.Torso:IsA("MeshPart") then
		DummyShape.addTarget(parts.Torso, Enum.NormalId.Front)
		DummyShape.addTarget(parts.Torso, Enum.NormalId.Back)
	end
	return parts
end

-- Cette méthode permet de poser les accessoires d'une déclinaison sur un mannequin debout (soudés à leur pièce, sans
-- masse ni collision) lorsque l'on le construit ; ignorés sans maillages.
function DummyShape.addAccessories(model: Model, parts: { [string]: BasePart }, scale: number, variant: Variant?)
	if not variant or not variant.accessories then
		return
	end
	for _, name in variant.accessories do
		local def = DummyShape.ACCESSORIES[name]
		local carrier = def and parts[def.piece]
		local accessory = carrier and DummyShape.makePart(name, def.size * scale)
		if accessory then
			accessory.CFrame = carrier.CFrame * CFrame.new(def.offset * scale)
			accessory.Color = variant.accessoryColor or DummyShape.ACCESSORY_COLOR
			accessory.Massless = true
			accessory.CanCollide = false
			accessory.CanQuery = false
			accessory.CanTouch = false
			accessory:SetAttribute("Accessory", true)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = carrier
			weld.Part1 = accessory
			weld.Parent = accessory
			accessory.Parent = model
		end
	end
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
			if p ~= root and not p:FindFirstChildOfClass("WeldConstraint") then
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
