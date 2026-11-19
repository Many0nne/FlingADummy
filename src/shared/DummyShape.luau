-- Gabarit du mannequin de crash-test (pièces, rotules, couleurs, cibles), partagé par le mannequin physique du serveur
-- et les mannequins décoratifs du client (tenu au-dessus de la tête, poids d'entraînement).
-- Studs, debout, centre du torse à l'origine.
local DummyShape = {}

DummyShape.YELLOW = Color3.fromRGB(255, 205, 40)
DummyShape.DARK = Color3.fromRGB(45, 47, 55)

local ARM = Vector3.new(0.8, 1.2, 0.8)
local LEG = Vector3.new(0.95, 1.3, 0.95)

export type Piece = { name: string, size: Vector3, position: Vector3, color: Color3, shape: Enum.PartType? }

DummyShape.PIECES = {
	{ name = "Torso", size = Vector3.new(2, 2.4, 1.1), position = Vector3.new(0, 0, 0), color = DummyShape.YELLOW },
	{
		name = "Head",
		size = Vector3.new(1.5, 1.5, 1.5),
		position = Vector3.new(0, 2.1, 0),
		color = DummyShape.YELLOW,
		shape = Enum.PartType.Ball,
	},
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

-- Cette méthode permet de peindre une cible de crash-test (disque jaune à deux quartiers noirs) sur une face d'une
-- pièce lorsque l'on habille le mannequin.
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

-- Cette méthode permet de construire un mannequin décoratif soudé (une seule pièce mobile, sans masse ni collision)
-- lorsque le client affiche un mannequin tenu ou soulevé ; `material` et `color` remplacent le jaune (équipement).
function DummyShape.buildVisual(scale: number, color: Color3?, material: Enum.Material?): Model
	local model = Instance.new("Model")
	model.Name = "VisualDummy"
	local root: BasePart? = nil
	for _, piece in DummyShape.PIECES do
		local p = Instance.new("Part")
		p.Name = piece.name
		p.Size = piece.size * scale
		p.CFrame = CFrame.new(piece.position * scale)
		p.Shape = piece.shape or Enum.PartType.Block
		p.Color = if color and piece.color == DummyShape.YELLOW then color else piece.color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.CastShadow = true
		p.Parent = model
		if piece.name == "Torso" then
			root = p
			DummyShape.addTarget(p, Enum.NormalId.Front)
		elseif root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
		end
	end
	model.PrimaryPart = root
	return model
end

return DummyShape
