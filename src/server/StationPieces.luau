-- Pièces ajoutées de l'appareil d'entraînement, palier par palier (#118) : socles de pierre, frettes et rivets, pommeaux
-- dorés, cristaux, tubes néon, planète annelée, gemmes, blason, éclairs, halo, aura au sol (liste et ordre :
-- Shared.BaseLook.STATION_PIECES). Chaque palier garde celles des précédents. Toutes fixes (rien ne bouge : pas d'effet
-- à couper en mouvement réduit), sans collision. Construites par Server.CourseBuilder dans le modèle de l'habillage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseLook = require(ReplicatedStorage.Shared.BaseLook)
local Build = require(script.Parent.Build)

local StationPieces = {}

-- Repère de l'appareil : sol et dessus du podium (-Z = face de l'avatar, côté hub), côté du podium, hauteur du podium,
-- profondeur du râtelier, écart des montants à l'axe, hauteur des montants, hauteur de la traverse
export type Frame = {
	floor: CFrame,
	top: CFrame,
	size: number,
	height: number,
	rackZ: number,
	postX: number,
	rackHeight: number,
	barY: number,
}

local rgb = Color3.fromRGB
local GOLD = rgb(255, 195, 45)
local METAL = rgb(70, 72, 80)
local POST_HALF = 0.8 -- demi-largeur d'un montant
local BAR_HALF = 0.45 -- demi-épaisseur de la traverse
local SIDES = { -1, 1 }

-- Cette méthode permet de poser une pièce décorative (sans collision, matériau `material`, lisse par défaut) lorsque
-- l'on ajoute une pièce de palier à l'appareil.
local function piece(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	return Build.decor({
		Name = "Piece",
		Shape = shape or Enum.PartType.Block,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CastShadow = material ~= Enum.Material.Neon,
		Parent = parent,
	})
end

-- Cette méthode permet de sertir une gemme (losange néon sur une monture dorée, face vers -Z) lorsque l'on pose les
-- gemmes ou le blason ; `size` = côté de la gemme.
local function gem(parent: Instance, at: CFrame, size: number, color: Color3)
	local turned = at * CFrame.Angles(0, 0, math.rad(45))
	piece(parent, Vector3.new(size + 0.25, size + 0.25, 0.12), turned, GOLD, Enum.Material.Foil)
	piece(parent, Vector3.new(size, size, 0.22), turned * CFrame.new(0, 0, -0.06), color, Enum.Material.Neon)
end

-- Cette méthode permet de poser une lumière ponctuelle de la couleur du palier dans une pièce lorsque l'appareil des
-- derniers paliers s'éclaire (éclairs, aura).
local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = false
	point.Parent = part
end

-- Cette méthode permet de donner le repère d'un point du râtelier (`x`, `y` au-dessus du podium, `dz` devant (< 0) ou
-- derrière l'axe des montants) lorsque l'on y accroche une pièce.
local function rackAt(f: Frame, x: number, y: number, dz: number): CFrame
	return f.top * CFrame.new(x, y, f.rackZ + dz)
end

-- Cette méthode permet de donner la hauteur du sommet des chapeaux en gradins des montants lorsque l'on pose ce qui les
-- coiffe (pommeaux, pointes).
local function capTop(f: Frame): number
	return f.rackHeight + 0.25 + 2 * 0.45 + 0.2
end

local BUILDERS: { [string]: (Model, Frame, BaseLook.StationLook) -> () } = {}

-- Cette méthode permet de poser les socles de pierre au pied des montants lorsque l'appareil atteint la pierre.
function BUILDERS.plinths(model: Model, f: Frame, look: BaseLook.StationLook)
	for _, side in SIDES do
		Build.decor({
			Name = "Piece",
			Size = Vector3.new(2.5, 1, 2.5),
			CFrame = rackAt(f, side * f.postX, 0.5, 0),
			Color = look.postDark,
			Variant = Build.FINE,
			CastShadow = true,
			Parent = model,
		})
	end
end

-- Cette méthode permet de poser frettes et rivets de fer sur les montants lorsque l'appareil atteint le fer.
function BUILDERS.rivets(model: Model, f: Frame, _look: BaseLook.StationLook)
	for _, side in SIDES do
		local x = side * f.postX
		for _, y in { 3, 4.6 } do
			piece(model, Vector3.new(1.8, 0.3, 1.8), rackAt(f, x, y, 0), METAL, Enum.Material.Metal)
		end
		for _, y in { 2.1, 3.8, 5 } do
			for _, dx in { -0.5, 0.5 } do
				piece(
					model,
					Vector3.new(0.3, 0.3, 0.3),
					rackAt(f, x + dx, y, -POST_HALF - 0.1),
					METAL,
					Enum.Material.Metal
				)
			end
		end
	end
end

-- Cette méthode permet de poser les pommeaux dorés sur les montants et le bandeau doré de la traverse lorsque
-- l'appareil atteint l'or.
function BUILDERS.finials(model: Model, f: Frame, _look: BaseLook.StationLook)
	for _, side in SIDES do
		piece(
			model,
			Vector3.new(1.1, 1.1, 1.1),
			rackAt(f, side * f.postX, capTop(f) + 0.45, 0),
			GOLD,
			Enum.Material.Foil,
			Enum.PartType.Ball
		)
	end
	local width = f.postX * 2 - 2 * POST_HALF
	piece(model, Vector3.new(width, 0.3, 0.12), rackAt(f, 0, f.barY + 0.28, -BAR_HALF - 0.06), GOLD, Enum.Material.Foil)
end

-- Cette méthode permet de poser deux grappes de cristaux sur le podium (coin avant gauche, côté droit) lorsque
-- l'appareil atteint le diamant.
function BUILDERS.crystals(model: Model, f: Frame, look: BaseLook.StationLook)
	for _, spot in { Vector3.new(-3.4, 0, -3.4), Vector3.new(3.5, 0, 0.6) } do
		local base = f.top * CFrame.new(spot)
		for _, c in
			{
				{ Vector3.new(0.7, 2, 0.7), Vector3.new(0, 0, 0), 0 },
				{ Vector3.new(0.55, 1.4, 0.55), Vector3.new(0.5, 0, 0.1), -22 },
				{ Vector3.new(0.5, 1.1, 0.5), Vector3.new(-0.45, 0, 0.3), 20 },
			}
		do
			local size: Vector3, offset: Vector3, tilt: number = c[1], c[2], c[3]
			local at = base * CFrame.new(offset) * CFrame.Angles(0, math.rad(45), math.rad(tilt))
			piece(model, size, at * CFrame.new(0, size.Y / 2 - 0.15, 0), look.accent, Enum.Material.Ice)
		end
	end
end

-- Cette méthode permet de poser un tube néon sur la face avant de chaque montant lorsque l'appareil atteint le néon
-- (le liseré de la bordure et de la traverse est posé avec le podium et le râtelier).
function BUILDERS.tubes(model: Model, f: Frame, look: BaseLook.StationLook)
	for _, side in SIDES do
		piece(
			model,
			Vector3.new(0.3, 4.6, 0.2),
			rackAt(f, side * f.postX, 3.6, -POST_HALF - 0.25),
			look.accent,
			Enum.Material.Neon
		)
	end
end

-- Cette méthode permet de poser au-dessus de la traverse une planète annelée et deux étoiles lorsque l'appareil atteint
-- le cosmique.
function BUILDERS.orbit(model: Model, f: Frame, look: BaseLook.StationLook)
	local center = rackAt(f, 0, 8.1, 0)
	piece(model, Vector3.new(1.4, 1.4, 1.4), center, look.plank, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local ring = center * CFrame.Angles(math.rad(-18), 0, math.rad(14)) * CFrame.Angles(0, 0, math.rad(90))
	piece(model, Vector3.new(0.12, 2.6, 2.6), ring, look.accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	for _, side in SIDES do
		local star = rackAt(f, side * 1.75, 8.4, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		piece(model, Vector3.new(0.45, 0.45, 0.45), star, look.accent, Enum.Material.Neon)
	end
end

-- Cette méthode permet de sertir des gemmes dans la traverse et la marche haute lorsque l'appareil atteint le rubis.
function BUILDERS.gems(model: Model, f: Frame, look: BaseLook.StationLook)
	for _, side in SIDES do
		gem(model, rackAt(f, side * 1.4, f.barY, -BAR_HALF - 0.06), 0.5, look.accent)
	end
	-- Contremarche de la marche haute (2/3 de la hauteur du podium, 1,2 stud de profondeur devant lui)
	local riser = f.floor * CFrame.new(0, f.height / 3, -f.size / 2 - 1.2 - 0.06)
	gem(model, riser, 0.42, look.accent)
end

-- Cette méthode permet de poser un blason doré à gemme au centre de la traverse lorsque l'appareil atteint l'émeraude.
function BUILDERS.crest(model: Model, f: Frame, look: BaseLook.StationLook)
	local at = rackAt(f, 0, f.barY + 0.25, -BAR_HALF - 0.12)
	piece(model, Vector3.new(1.5, 1.7, 0.2), at, GOLD, Enum.Material.Foil)
	piece(model, Vector3.new(1.1, 1.3, 0.1), at * CFrame.new(0, 0, -0.12), look.postDark)
	gem(model, at * CFrame.new(0, 0.05, -0.2), 0.6, look.accent)
end

-- Cette méthode permet de poser des éclairs néon le long de la face extérieure des montants, et une lumière, lorsque
-- l'appareil atteint le plasma.
function BUILDERS.arcs(model: Model, f: Frame, look: BaseLook.StationLook)
	local first: BasePart? = nil
	for _, side in SIDES do
		local x = side * (f.postX + POST_HALF + 0.15)
		local points = {}
		for i, y in { 1.6, 2.8, 4, 5.2, 6.4 } do
			table.insert(points, (f.top * CFrame.new(x, y, f.rackZ + (if i % 2 == 0 then 0.45 else -0.45))).Position)
		end
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local at = CFrame.lookAt((a + b) / 2, b)
			local bolt =
				piece(model, Vector3.new(0.22, 0.22, (b - a).Magnitude + 0.15), at, look.accent, Enum.Material.Neon)
			first = first or bolt
		end
	end
	if first then
		light(first, look.accent, 14, 1.5)
	end
end

-- Cette méthode permet de poser un halo néon derrière la planète et des pointes de couronne sur les montants lorsque
-- l'appareil atteint l'oméga.
function BUILDERS.halo(model: Model, f: Frame, look: BaseLook.StationLook)
	local center = rackAt(f, 0, 8.1, 0.4)
	local segments, radius = 12, 1.55
	for i = 1, segments do
		local angle = (i - 1) / segments * 2 * math.pi
		local at = center * CFrame.Angles(0, 0, angle) * CFrame.new(radius, 0, 0)
		piece(
			model,
			Vector3.new(0.25, 2 * math.pi * radius / segments + 0.05, 0.25),
			at,
			look.accent,
			Enum.Material.Neon
		)
	end
	-- Pointes aux coins du gradin du milieu des chapeaux
	local y = f.rackHeight + 0.25 + 0.45 + 0.225 + 0.3
	for _, side in SIDES do
		for _, dx in { -0.55, 0.55 } do
			for _, dz in { -0.55, 0.55 } do
				piece(
					model,
					Vector3.new(0.25, 0.6, 0.25),
					rackAt(f, side * f.postX + dx, y, dz),
					look.accent,
					Enum.Material.Neon
				)
			end
		end
	end
end

-- Cette méthode permet de poser l'aura de l'appareil (anneau néon au sol autour du podium, interrompu par les marches,
-- colonnes de lumière à pommeau doré aux quatre coins, lumière) lorsque l'appareil atteint l'Infinite.
function BUILDERS.aura(model: Model, f: Frame, look: BaseLook.StationLook)
	local ring = f.size / 2 + 0.75
	local length = 2 * ring + 0.35
	piece(model, Vector3.new(length, 0.16, 0.35), f.floor * CFrame.new(0, 0.08, ring), look.accent, Enum.Material.Neon)
	local stepHalf = 2.15 -- marches de 4 studs de large
	local span = (length / 2) - stepHalf
	for _, side in SIDES do
		piece(
			model,
			Vector3.new(0.35, 0.16, length),
			f.floor * CFrame.new(side * ring, 0.08, 0),
			look.accent,
			Enum.Material.Neon
		)
		piece(
			model,
			Vector3.new(span, 0.16, 0.35),
			f.floor * CFrame.new(side * (stepHalf + span / 2), 0.08, -ring),
			look.accent,
			Enum.Material.Neon
		)
	end
	local column: BasePart? = nil
	for _, sx in SIDES do
		for _, sz in SIDES do
			local foot = f.floor * CFrame.new(sx * ring, 0, sz * ring)
			column =
				piece(model, Vector3.new(0.45, 5, 0.45), foot * CFrame.new(0, 2.5, 0), look.accent, Enum.Material.Neon)
			piece(
				model,
				Vector3.new(0.9, 0.9, 0.9),
				foot * CFrame.new(0, 5.3, 0),
				GOLD,
				Enum.Material.Foil,
				Enum.PartType.Ball
			)
		end
	end
	if column then
		light(column, look.accent, 20, 2)
	end
end

-- Cette méthode permet de poser les pièces de palier de l'habillage `look` (celles de son palier et des précédents)
-- dans le modèle de l'habillage lorsque l'appareil est habillé ; renvoie le nombre de pièces posées.
function StationPieces.build(model: Model, f: Frame, look: BaseLook.StationLook): number
	local before = #model:GetChildren()
	for _, name in BaseLook.STATION_PIECES do
		if look.pieces[name] then
			local builder = BUILDERS[name]
			assert(builder, "StationPieces : pièce sans construction " .. name)
			builder(model, f, look)
		end
	end
	return #model:GetChildren() - before
end

return StationPieces
