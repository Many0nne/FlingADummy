-- Briques de construction du décor généré par le code : pièces ancrées, blocs aux matériaux « briques à tenons »
-- (MaterialVariant synchronisés par Rojo dans MaterialService), textes sur panneaux et étiquettes flottantes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurfaceGap = require(ReplicatedStorage.Shared.SurfaceGap)

local Build = {}

-- Zone de pose en cours (Build.within, Build.keep, Build.settled) et pièces posées depuis son ouverture, ajustées à sa
-- fermeture : un bloc qui affleure un bloc déjà posé de la zone ressort un peu (#93)
local placed: SurfaceGap.Area? = nil
local adjust = true -- faux : les pièces s'ajoutent à la zone telles quelles (Build.keep)
local pending: { Part } = {}

-- Matériaux des jeux de référence (01 / 09) : tenons en relief teintés par la couleur de la pièce
-- (assets/course/build_textures.py ; MaterialVariant dans default.project.json, cartes publiées sur le compte)
Build.CHECKER = "FadChecker" -- damier marqué de carreaux de 8 studs à 4 × 4 tenons : sol
Build.WALL = "FadWall" -- même damier, plus doux : parois en gradins et herbe qui les coiffe
Build.BRICK = "FadBrick" -- un tenon tous les 2 studs : accessoires, obstacles, végétation voxel
Build.FINE = "FadBrickFine" -- mêmes cartes, un tenon par stud : objets à l'échelle de l'avatar (appareil d'entraînement)

-- Cette méthode permet de savoir si une pièce de la zone est toujours un bloc visible lorsqu'une nouvelle pièce s'y
-- compare (une pièce devenue cylindre, boule ou invisible depuis ne compte plus).
local function visibleBlock(entry: SurfaceGap.Placed): boolean
	local part = entry.part
	return part == nil or (part.Shape == Enum.PartType.Block and part.Transparency < 1)
end

-- Cette méthode permet de créer une pièce ancrée avec ses propriétés lorsque le décor est construit ; `Variant`
-- (Build.CHECKER, Build.WALL, Build.BRICK, Build.FINE) pose le matériau à tenons.
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
	if placed then
		table.insert(pending, p)
	end
	-- Parent en dernier : la pièce entre dans le monde déjà configurée
	p.Parent = props.Parent
	return p
end

-- Cette méthode permet d'exécuter `fn(...)` dans la zone `area`, puis d'ajuster (si `settle`) et d'y ajouter ses blocs
-- visibles, une fois leurs formes et positions définitives ; un appel imbriqué reste dans la zone en cours.
local function run(area: SurfaceGap.Area, settle: boolean, fn: (...any) -> ...any, ...: any): ...any
	if placed then
		return fn(...)
	end
	placed, adjust = area, settle
	local results = table.pack(xpcall(fn, debug.traceback, ...))
	if results[1] then
		for _, p in pending do
			if p.Parent and p.Shape == Enum.PartType.Block and p.Transparency < 1 then
				if adjust then
					local size, cframe = SurfaceGap.settle(area, p.Size, p.CFrame, visibleBlock)
					p.Size = size
					p.CFrame = cframe
				end
				SurfaceGap.add(area, p.Size, p.CFrame, p)
			end
		end
	end
	placed, adjust = nil, true
	table.clear(pending)
	if not results[1] then
		error(results[2], 0)
	end
	return table.unpack(results, 2, results.n)
end

-- Cette méthode permet de poser des éléments voisins (`fn(...)`) contre les blocs de `area` lorsqu'ils se chevauchent :
-- chaque bloc qui affleure un bloc de la zone ressort de SurfaceGap.STEP et s'y ajoute.
function Build.within(area: SurfaceGap.Area, fn: (...any) -> ...any, ...: any): ...any
	assert(placed == nil or placed == area, "Build.within : une autre zone est en cours de pose")
	return run(area, true, fn, ...)
end

-- Cette méthode permet d'ajouter à `area`, sans les ajuster, les blocs d'une structure réglée à la main (gradins) que
-- d'autres éléments toucheront ensuite (Build.within).
function Build.keep(area: SurfaceGap.Area, fn: (...any) -> ...any, ...: any): ...any
	assert(placed == nil, "Build.keep : pas dans un élément en cours de pose")
	return run(area, false, fn, ...)
end

-- Cette méthode permet de poser un élément de décor d'un tenant (`fn(...)`) lorsque ses blocs se chevauchent : un bloc
-- qui affleure un bloc déjà posé de l'élément en ressort de SurfaceGap.STEP.
function Build.settled(fn: (...any) -> ...any, ...: any): ...any
	return run(placed or SurfaceGap.area(), true, fn, ...)
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
