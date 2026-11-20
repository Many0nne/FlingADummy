-- Briques de construction du décor généré par le code : pièces ancrées, blocs aux matériaux « briques à tenons »
-- (MaterialVariant synchronisés par Rojo dans MaterialService), textes sur panneaux et étiquettes flottantes.
local Build = {}

-- Matériaux des jeux de référence (01 / 09) : tenons en relief teintés par la couleur de la pièce
-- (assets/course/build_textures.py ; MaterialVariant dans default.project.json, cartes publiées sur le compte)
Build.CHECKER = "FadChecker" -- damier marqué de carreaux de 8 studs à 4 × 4 tenons : sol
Build.WALL = "FadWall" -- même damier, plus doux : parois en gradins et herbe qui les coiffe
Build.BRICK = "FadBrick" -- un tenon tous les 2 studs : accessoires, obstacles, végétation voxel

-- Cette méthode permet de créer une pièce ancrée avec ses propriétés lorsque le décor est construit ; `Variant`
-- (Build.CHECKER, Build.WALL, Build.BRICK) pose le matériau à tenons.
function Build.part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "Parent" and key ~= "Variant" then
			(p :: any)[key] = value
		end
	end
	if props.Variant then
		p.Material = Enum.Material.Plastic
		p.MaterialVariant = props.Variant
	end
	-- Parent en dernier : la pièce entre dans le monde déjà configurée
	p.Parent = props.Parent
	return p
end

-- Cette méthode permet de créer une pièce décorative sans collision ni requête lorsque l'on pose un élément que le
-- mannequin doit traverser (végétation au sol, marquages).
function Build.decor(props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return Build.part(props)
end

-- Cette méthode permet de poser un bloc à briques à tenons de taille `size` au repère `cframe` lorsque l'on assemble
-- un élément voxel ; `solid` = faux pour un bloc que le mannequin traverse.
function Build.block(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, solid: boolean?): Part
	local props = {
		Name = "Block",
		Size = size,
		CFrame = cframe,
		Color = color,
		Variant = Build.BRICK,
		CastShadow = true,
		Parent = parent,
	}
	if solid == false then
		return Build.decor(props)
	end
	return Build.part(props)
end

-- Cette méthode permet de poser un gros texte au style du jeu sur une face de pièce lorsque l'on habille un panneau.
function Build.surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = target
	return label
end

-- Cette méthode permet d'afficher un texte flottant au-dessus d'un point lorsque l'on pose un repère ou une enseigne.
function Build.billboard(
	parent: Instance,
	position: Vector3,
	text: string,
	size: Vector2,
	maxDistance: number?
): TextLabel
	local anchor =
		Build.decor({ Name = "Label", Size = Vector3.one, Position = position, Transparency = 1, Parent = parent })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 250
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.RichText = true
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	return label
end

-- Cette méthode permet de donner une teinte plus sombre (facteur < 1) ou plus claire (> 1) d'une couleur lorsque
-- l'on varie les tons d'un élément voxel.
function Build.shade(color: Color3, factor: number): Color3
	return Color3.new(math.min(color.R * factor, 1), math.min(color.G * factor, 1), math.min(color.B * factor, 1))
end

return Build
