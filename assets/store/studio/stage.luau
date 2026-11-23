--# selene: allow(global_usage)
-- Mise en scène des captures de la page du jeu (#178), Studio seulement : à coller tel quel dans le MCP Studio
-- (execute_luau, contexte Server, en Play avec l'attribut FreshPlayer de Workspace à true), une fois par séance.
-- Définit _G.FadStore :
--   _G.FadStore.shot("<nom>")  retire les pièces de la piste devant la caméra (les obstacles réapparaissent seuls :
--                              appeler juste avant la capture ; le décor retiré ne revient qu'au Stop), pose la scène de la prise (dossier Workspace.StoreScene) et la pièce de
--                              cadrage StoreCamera (attributs From, At, Fov) que suit camera.luau côté client ;
--   _G.FadStore.clear()        retire la scène.
-- Mannequins construits comme en jeu (Shared.DummyShape, déclinaisons de Shared.Collection et Shared.ThrowDummies),
-- avatar bacon hair (corps R15 par défaut, « Pal Hair », tête classique souriante) posé articulation par articulation.
-- Tout est jeté au Stop du playtest. Procédure : assets/store/README.md.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Collection = require(Shared.Collection)
local DummyShape = require(Shared.DummyShape)
local ThrowDummies = require(Shared.ThrowDummies)

local S = {}

local SKIN = Color3.fromRGB(234, 184, 146)
local SHIRT = Color3.fromRGB(30, 32, 40)
local PANTS = Color3.fromRGB(45, 50, 62)
local HAIR = "63690008" -- Pal Hair : la coiffure « bacon hair » des avatars des vignettes de référence
local FACE = "rbxasset://textures/face.png" -- visage souriant classique
local FEET = 3.82 -- du centre du torse au bas des pieds, échelle 1 (Shared.DummyShape)

-- Poses de l'avatar : rotation (degrés X, Y, Z) de chaque articulation (AnimationConstraint.Transform des avatars R15
-- récents). Face à la caméra, le bras gauche de l'avatar est à droite de l'image.
local POSES = {
	releaseL = { -- vient de lancer vers le haut à droite de l'image : bras gauche levé
		LeftShoulder = { 25, 0, -150 },
		LeftElbow = { 15, 0, 0 },
		RightShoulder = { 0, 0, 35 },
		RightElbow = { 35, 0, 0 },
		Waist = { 0, -14, 7 },
		Neck = { 10, 14, 0 },
		RightHip = { 0, 0, 8 },
		LeftHip = { 0, 0, -8 },
	},
	throwR = { -- de trois-quarts, bras droit tendu vers le mannequin en vol
		RightShoulder = { 105, 0, 0 },
		LeftShoulder = { -45, 0, -25 },
		LeftElbow = { 25, 0, 0 },
		Waist = { 0, -12, 0 },
		Neck = { 12, 10, 0 },
		RightHip = { -20, 0, 0 },
		LeftHip = { 25, 0, 0 },
		LeftKnee = { -25, 0, 0 },
	},
	cheer = { -- bras levés, victoire
		RightShoulder = { 0, 0, 150 },
		LeftShoulder = { 0, 0, -150 },
		RightElbow = { 20, 0, 0 },
		LeftElbow = { 20, 0, 0 },
		Neck = { 8, 0, 0 },
		RightHip = { 0, 0, 8 },
		LeftHip = { 0, 0, -8 },
	},
}

-- Membres du mannequin en vol (pose en étoile) : pièces tournées ensemble autour de leur rotule (Shared.DummyShape)
local STAR = {
	{
		pieces = { "LeftUpperArm", "LeftLowerArm" },
		pivot = Vector3.new(-1.45, 1.05, 0),
		angle = Vector3.new(20, 0, -140),
	},
	{
		pieces = { "RightUpperArm", "RightLowerArm" },
		pivot = Vector3.new(1.45, 1.05, 0),
		angle = Vector3.new(-20, 0, 125),
	},
	{
		pieces = { "LeftUpperLeg", "LeftLowerLeg" },
		pivot = Vector3.new(-0.5, -1.2, 0),
		angle = Vector3.new(-30, 0, -30),
	},
	{
		pieces = { "RightUpperLeg", "RightLowerLeg" },
		pivot = Vector3.new(0.5, -1.2, 0),
		angle = Vector3.new(25, 0, 20),
	},
	{ pieces = { "Head" }, pivot = Vector3.new(0, 1.28, 0), angle = Vector3.new(-15, 0, 10) },
}

local scene: Folder? = nil

-- Cette méthode permet de convertir un triplet de degrés en rotation lorsque l'on pose une articulation.
local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Cette méthode permet de donner le repère d'un objet posé en `position`, tourné à plat vers `toward` lorsque l'on
-- place un mannequin face à la caméra.
function S.facing(position: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(toward.X, position.Y, toward.Z))
end

-- Cette méthode permet de construire un mannequin (collection : id texte, à lancer : indice) à l'échelle voulue, pose
-- en étoile si `star`, puis de le poser à `cframe` (torse) lorsque l'on monte une prise.
function S.dummy(key: string | number, scale: number, cframe: CFrame, star: boolean?): Model
	local variant = if type(key) == "string"
		then Collection.variant({ id = key, size = 1 })
		else ThrowDummies.variant(key)
	local model = DummyShape.buildVisual(scale, variant)
	model.Name = "Store_" .. tostring(key)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	if star then
		for _, limb in STAR do
			local pivot = limb.pivot * scale
			local turn = CFrame.new(pivot) * angles(limb.angle.X, limb.angle.Y, limb.angle.Z) * CFrame.new(-pivot)
			for _, name in limb.pieces do
				local part = model:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					part.CFrame = turn * part.CFrame
				end
			end
		end
	end
	model:PivotTo(cframe)
	model.Parent = scene
	return model
end

-- Cette méthode permet de remplacer la tête maillée par défaut (texturée, visage neutre, couleur ignorée) par une tête
-- classique couleur peau au visage souriant lorsque l'on habille l'avatar.
local function classicHead(model: Model)
	local head = model:FindFirstChild("Head") :: BasePart
	for _, decal in head:GetChildren() do
		if decal:IsA("Decal") then
			decal:Destroy()
		end
	end
	head.Transparency = 1
	local classic = Instance.new("Part")
	classic.Name = "ClassicHead"
	classic.Size = Vector3.new(2.4, 1.2, 1.2)
	classic.Color = SKIN
	classic.CanCollide = false
	classic.Massless = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = classic
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = FACE
	face.Face = Enum.NormalId.Front
	face.Parent = classic
	classic.CFrame = head.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = classic
	weld.Parent = classic
	classic.Parent = model
end

-- Cette méthode permet de construire l'avatar bacon hair des vignettes (pose `pose`, racine ancrée à `cframe`)
-- lorsque l'on monte une prise.
function S.avatar(pose: string, cframe: CFrame): Model
	local desc = Instance.new("HumanoidDescription")
	desc.HairAccessory = HAIR
	local ok, built = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[store] avatar sans cheveux : " .. tostring(built))
		desc.HairAccessory = ""
		built = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end
	local model = built :: Model
	model.Name = "StoreAvatar"
	-- Couleurs posées sur les pièces : la description ne colore pas la tête maillée par défaut
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part:FindFirstAncestorOfClass("Accessory") then
			local name = part.Name
			if name:find("Hand") or name:find("LowerArm") then
				part.Color = SKIN
			elseif name:find("Torso") or name:find("UpperArm") then
				part.Color = SHIRT
			elseif name:find("Leg") or name:find("Foot") then
				part.Color = PANTS
			end
		end
	end
	local colors = model:FindFirstChildOfClass("BodyColors")
	if colors then
		colors:Destroy()
	end
	classicHead(model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	local joints = POSES[pose] or {}
	for _, joint in model:GetDescendants() do
		local rot = joints[joint.Name]
		if rot and joint:IsA("AnimationConstraint") then
			joint.IsKinematic = true
			joint.Transform = angles(rot[1], rot[2], rot[3])
		elseif rot and joint:IsA("Motor6D") then
			joint.C0 *= angles(rot[1], rot[2], rot[3])
		end
	end
	model:PivotTo(cframe)
	model.Parent = scene
	return model
end

-- Cette méthode permet de poser la pièce de cadrage suivie par le client (caméra en `from`, visée `at`, champ `fov`)
-- lorsque la scène d'une prise est prête.
function S.camera(from: Vector3, at: Vector3, fov: number)
	local part = Instance.new("Part")
	part.Name = "StoreCamera"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = at
	part:SetAttribute("From", from)
	part:SetAttribute("At", at)
	part:SetAttribute("Fov", fov)
	part.Parent = scene
end

-- Cette méthode permet de retirer les obstacles et décors de la piste dans une boîte au sol (x, z) lorsqu'ils
-- masqueraient la scène ; les obstacles réapparaissent seuls, le décor retiré ne revient qu'au Stop du playtest.
function S.clearCourse(x0: number, x1: number, z0: number, z1: number): number
	local count = 0
	for _, part in Workspace.Course:GetDescendants() do
		if not part:IsA("BasePart") then
			continue -- dossiers et modèles : pas de position
		end
		local p = part.Position
		if
			part.Name ~= "Track"
			and p.X > x0
			and p.X < x1
			and p.Z > z0
			and p.Z < z1
			and p.Y > 0.3
			and part.Size.Magnitude < 60
		then
			part:Destroy()
			count += 1
		end
	end
	return count
end

-- Cette méthode permet de retirer la scène en cours lorsque la séance se termine ou qu'une autre prise commence.
function S.clear()
	if scene then
		scene:Destroy()
		scene = nil
	end
end

-- Prises : chacune pose sa scène puis sa caméra (début du canyon, Meadow ; sol à y = 0, piste vers +Z)
local SHOTS = {}

-- Icône : avatar bacon hair bras levé, Crash Dummy qui s'envole, Crash King sur son trône (assets/store/captures/icon.jpg)
-- Cette méthode permet de poser la scène de l'icône lorsque la prise « icon » est demandée.
function SHOTS.icon()
	local from, at = Vector3.new(0.4, 4.5, 3), Vector3.new(-0.6, 8.3, 30)
	local av = Vector3.new(2.3, 2.9, 11.5)
	S.avatar("releaseL", CFrame.lookAt(av, av + Vector3.new(-0.4, 0, -1)))
	S.dummy(1, 0.8, CFrame.new(2.4, 11.4, 18) * angles(0, -20, -40), true)
	S.dummy("king", 2.5, S.facing(Vector3.new(-4.6, FEET * 2.5, 34), from))
	S.camera(from, at, 46)
end

-- Vignette mystère : avatar de trois-quarts qui lance, Crash Dummy en vol, moitié droite libre pour la silhouette
-- ajoutée au montage (assets/store/captures/mystery.jpg)
-- Cette méthode permet de poser la scène de la vignette mystère lorsque la prise « mystery » est demandée.
function SHOTS.mystery()
	local from, at = Vector3.new(0, 4.5, 3), Vector3.new(0, 7, 30)
	local av = Vector3.new(6.2, 2.9, 15)
	S.avatar("throwR", CFrame.lookAt(av, av + Vector3.new(-0.8, 0, -0.6)))
	S.dummy(1, 0.85, CFrame.new(0.5, 9.5, 19) * angles(0, 10, 70), true)
	S.camera(from, at, 50)
end

-- Vignette du lancer : avatar de dos sur la bande, Crash Dummy au sommet de sa course, Infinite Crash King géant au
-- bout du canyon (assets/store/captures/arc.jpg)
-- Cette méthode permet de poser la scène de la vignette du lancer lorsque la prise « arc » est demandée.
function SHOTS.arc()
	local from, at = Vector3.new(9, 8.5, -24), Vector3.new(0, 9, 40)
	local av = Vector3.new(5, 2.9, -8)
	S.avatar("throwR", CFrame.lookAt(av, av + Vector3.new(-0.2, 0, 1)))
	S.dummy(1, 1, CFrame.new(14, 15.8, 13) * angles(-20, 0, -70), true)
	S.dummy("infinite_king", 5, S.facing(Vector3.new(-8, FEET * 5, 72), from))
	S.camera(from, at, 55)
end

local BRICKS = { Color3.fromRGB(230, 90, 40), Color3.fromRGB(205, 70, 35), Color3.fromRGB(240, 115, 50) }

-- Cette méthode permet de poser une brique à tenons du décor (variante de matériau FadBrick) lorsque l'on monte le mur
-- de la vignette de casse.
local function brick(size: Vector3, cframe: CFrame, color: Color3)
	local part = Instance.new("Part")
	part.Name = "StoreBrick"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Plastic
	part.MaterialVariant = "FadBrick"
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Parent = scene
end

-- Vignette de casse : le Crash Dummy traverse un mur de briques à tenons, débris projetés vers la caméra
-- (assets/store/captures/smash.jpg)
-- Cette méthode permet de poser la scène de la vignette de casse lorsque la prise « smash » est demandée.
function SHOTS.smash()
	local rng = Random.new(11)
	local wallZ, hole = 30, Vector2.new(0, 7.5)
	for row = 0, 7 do
		for col = -5, 5 do
			local x, y = col * 4 + (row % 2) * 2 - 1, row * 2 + 1
			if (Vector2.new(x, y) - hole).Magnitude > 5.2 then
				brick(Vector3.new(4, 2, 2), CFrame.new(x, y, wallZ), BRICKS[(row + col) % 3 + 1])
			end
		end
	end
	local placed = 0
	while placed < 20 do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(4.5, 11)
		local pos = Vector3.new(math.cos(a) * r, 7.5 + math.sin(a) * r * 0.75, rng:NextNumber(20, 28))
		if pos.Y > 0.5 then
			local spin = CFrame.Angles(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3))
			brick(Vector3.new(4, 2, 2) * rng:NextNumber(0.55, 0.9), CFrame.new(pos) * spin, BRICKS[placed % 3 + 1])
			placed += 1
		end
	end
	S.dummy(1, 1.25, CFrame.new(0.8, 7.6, 18.5) * angles(10, 15, -20), true)
	S.camera(Vector3.new(4, 6.5, 4), Vector3.new(0, 7.5, 30), 55)
end

-- Vignette de la collection : avatar bras levés devant trois mannequins rares géants
-- (assets/store/captures/collection.jpg)
-- Cette méthode permet de poser la scène de la vignette de la collection lorsque la prise « collection » est
-- demandée.
function SHOTS.collection()
	local from, at = Vector3.new(0, 4.5, 3), Vector3.new(-1, 9, 34)
	S.avatar("cheer", S.facing(Vector3.new(5.4, 2.9, 11.5), from))
	S.dummy("omega_void", 2, S.facing(Vector3.new(2, FEET * 2, 31), from))
	S.dummy("infinite_king", 2.4, S.facing(Vector3.new(-8, FEET * 2.4, 37), from))
	S.dummy("infinite_cosmic", 2, S.facing(Vector3.new(-15.5, FEET * 2, 31), from))
	S.camera(from, at, 55)
end

-- Cette méthode permet de poser la prise `name` (obstacles retirés, scène et caméra) lorsque le MCP la demande.
function S.shot(name: string): number
	S.clear()
	local build = SHOTS[name]
	if not build then
		warn("[store] prise inconnue : " .. name)
		return 0
	end
	local removed = S.clearCourse(-34, 34, 4, 120)
	local folder = Instance.new("Folder")
	folder.Name = "StoreScene"
	folder.Parent = Workspace
	scene = folder
	build()
	print(
		string.format(
			"[store] %s prête (maillages : étape %d, %d obstacles retirés)",
			name,
			DummyShape.meshStage(),
			removed
		)
	)
	return removed
end

S.SHOTS = SHOTS
S.POSES = POSES
S.FEET = FEET
_G.FadStore = S
print("[store] FadStore prêt")
