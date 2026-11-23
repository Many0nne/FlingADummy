--# selene: allow(global_usage)
-- Mise en scène côté serveur de la vidéo de présentation (#225), Studio seulement : à coller dans le MCP Studio
-- (execute_luau, contexte Server, en Play avec l'attribut FreshPlayer de Workspace à true). Définit _G.FadVideo :
--   _G.FadVideo.dress()          habille le personnage du joueur en bacon hair (comme les vignettes de #178 : corps R15,
--                                « Pal Hair », tête classique souriante, haut sombre, avant-bras nus) ;
--   _G.FadVideo.wall()           dégage la piste autour du couloir de la place 2 et y monte un mur de briques à tenons
--                                (briques libres et légères : le mannequin le traverse et les projette) ;
--   _G.FadVideo.bot(power)       lance un mannequin de test du jeu depuis la place libre suivante (DebugLaunchBots :
--                                vol simulé par le serveur, sans copie locale en avance) ;
--   _G.FadVideo.track()          note la trajectoire du torse des mannequins lancés (_G.FadVideo.log).
-- Tout est jeté au Stop du playtest. Procédure : assets/store/video/README.md.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local V = _G.FadVideo or {}
_G.FadVideo = V

local SKIN = Color3.fromRGB(234, 184, 146)
local SHIRT = Color3.fromRGB(30, 32, 40)
local PANTS = Color3.fromRGB(45, 50, 62)
local HAIR = "63690008" -- Pal Hair
local FACE = "rbxasset://textures/face.png"

local BOT_LANE = -9 -- abscisse du couloir de la place 2 (premier mannequin de test, place 1 occupée par le joueur)
local WALL_Z = 188 -- le mannequin de test à puissance 10 y passe vers 8 studs de haut, juste avant d'atterrir
local BRICKS = { Color3.fromRGB(230, 90, 40), Color3.fromRGB(205, 70, 35), Color3.fromRGB(240, 115, 50) }

-- Cette méthode permet d'habiller le personnage du joueur en bacon hair lorsque la séance commence (à refaire après
-- une réapparition).
function V.dress(): string
	local player = Players:GetPlayers()[1]
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local desc = Instance.new("HumanoidDescription")
	desc.HairAccessory = HAIR
	humanoid:ApplyDescription(desc)
	local colors = character:FindFirstChildOfClass("BodyColors")
	if colors then
		colors:Destroy()
	end
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
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
	-- Tête classique souriante à la place de la tête maillée par défaut (visage neutre)
	local head = character:FindFirstChild("Head") :: BasePart
	for _, decal in head:GetChildren() do
		if decal:IsA("Decal") then
			decal:Destroy()
		end
	end
	head.Transparency = 1
	local old = character:FindFirstChild("ClassicHead")
	if old then
		old:Destroy()
	end
	local classic = Instance.new("Part")
	classic.Name = "ClassicHead"
	classic.Size = Vector3.new(2.4, 1.2, 1.2)
	classic.Color = SKIN
	classic.CanCollide = false
	classic.CanQuery = false
	classic.CanTouch = false
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
	classic.Parent = character
	return "habillé"
end

-- Cette méthode permet de retirer les obstacles et décors de la piste dans une boîte au sol (x, z) lorsqu'ils
-- masqueraient le mur ; les obstacles réapparaissent seuls après quelques secondes (appeler juste avant le lancer).
function V.clearCourse(x0: number, x1: number, z0: number, z1: number): number
	local count = 0
	for _, part in Workspace.Course:GetDescendants() do
		if part:IsA("BasePart") then
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
	end
	return count
end

-- Cette méthode permet de monter le mur de briques à tenons en travers du couloir de la place 2 (briques libres,
-- légères, posées en quinconce) lorsque la prise du mur se prépare.
function V.wall(): number
	local old = Workspace:FindFirstChild("FadWall")
	if old then
		old:Destroy()
	end
	local removed = V.clearCourse(BOT_LANE - 22, BOT_LANE + 22, WALL_Z - 14, WALL_Z + 26)
	local folder = Instance.new("Folder")
	folder.Name = "FadWall"
	local light = PhysicalProperties.new(0.12, 0.5, 0.1) -- assez légères pour que le mannequin perce le mur
	for row = 0, 7 do
		for col = -3, 3 do
			local half = row % 2 == 1
			if not (half and col == 3) then
				local x = BOT_LANE + col * 4 + (if half then 2 else 0)
				local brick = Instance.new("Part")
				brick.Name = "FadBrick"
				brick.Size = Vector3.new(3.96, 1.98, 2)
				brick.CFrame = CFrame.new(x, row * 2 + 1, WALL_Z)
				brick.Color = BRICKS[(row + col) % 3 + 1]
				brick.Material = Enum.Material.Plastic
				brick.MaterialVariant = "FadBrick"
				brick.CustomPhysicalProperties = light
				brick.Parent = folder
			end
		end
	end
	folder.Parent = Workspace
	return removed
end

-- Cette méthode permet de lancer un mannequin de test du jeu (puissance `power`, jauge pleine) lorsque la prise du
-- crash ou du mur commence.
function V.bot(power: number?)
	local player = Players:GetPlayers()[1]
	player:SetAttribute("DebugBotsPower", power or 10)
	player:SetAttribute("DebugLaunchBots", 1)
end

-- Cette méthode permet de noter la trajectoire (toutes les 0,05 s pendant 8 s, position et vitesse) du torse de
-- chaque mannequin lancé
-- lorsque l'on cherche où poser le mur ou la caméra.
function V.track()
	if V.trackConn then
		V.trackConn:Disconnect()
	end
	V.log = {}
	V.trackConn = Workspace.Course.Dummies.ChildAdded:Connect(function(model)
		local start = os.clock()
		local entry = { name = model.Name, points = {} }
		table.insert(V.log, entry)
		task.wait()
		local torso = model:FindFirstChild("Torso") :: BasePart?
		if not torso then
			return
		end
		local last = -1
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - start
			if t > 8 or not torso.Parent then
				conn:Disconnect()
				return
			end
			if t - last >= 0.05 then
				last = t
				local p = torso.Position
				local speed = torso.AssemblyLinearVelocity.Magnitude
				table.insert(entry.points, string.format("%.2f:%.0f,%.0f,%.0f|%.0f", t, p.X, p.Y, p.Z, speed))
			end
		end)
	end)
end

return "FadVideo prêt"
