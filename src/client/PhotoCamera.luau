-- Cadrage des prises de vue des planches de référence (#121, Studio seulement) : quand Server.PhotoStudio a posé la
-- prise demandée par l'attribut PhotoShot de Workspace, la caméra se fige sur sa pièce de cadrage (champ
-- Shared.PlanchePlan.FOV, largeur voulue sur toute l'image), l'interface et l'avatar local se cachent ; l'attribut
-- retiré rend la caméra, l'interface et l'avatar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local PlanchePlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlanchePlan"))

local PhotoCamera = {}

local FRAME_TIMEOUT = 10 -- s d'attente de la pièce de cadrage répliquée

local player = Players.LocalPlayer
local hiddenGuis: { ScreenGui } = {}
local savedFov: number? = nil
local coreSaved: { [Enum.CoreGuiType]: boolean }? = nil -- interface de Roblox avant la séance
local topbarSaved = true -- barre du haut de Roblox avant la séance
local token = 0 -- invalide une attente de cadrage dépassée par une nouvelle prise

-- Cette méthode permet de cacher (ou de rendre) l'interface du joueur et son avatar lorsqu'une séance de prises de vue
-- commence ou se termine.
local function hideScene(hidden: boolean)
	-- Interface de Roblox (chat, liste des joueurs, barre d'outils, boutons du haut) : état d'avant rendu à la fin
	if hidden and not coreSaved then
		local saved = {}
		for _, kind in Enum.CoreGuiType:GetEnumItems() do
			if kind ~= Enum.CoreGuiType.All then
				saved[kind] = StarterGui:GetCoreGuiEnabled(kind)
			end
		end
		coreSaved = saved
		local ok, topbar = pcall(StarterGui.GetCore, StarterGui, "TopbarEnabled")
		topbarSaved = if ok then topbar ~= false else true
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)
	elseif not hidden and coreSaved then
		for kind, enabled in coreSaved do
			StarterGui:SetCoreGuiEnabled(kind, enabled)
		end
		coreSaved = nil
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", topbarSaved)
	end
	if hidden then
		-- Rescannée à chaque prise : une fenêtre ouverte pendant la séance (annonce, popup) est cachée aussi
		for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
			if gui:IsA("ScreenGui") and gui.Enabled and not table.find(hiddenGuis, gui) then
				gui.Enabled = false
				table.insert(hiddenGuis, gui)
			end
		end
	else
		for _, gui in hiddenGuis do
			gui.Enabled = true
		end
		table.clear(hiddenGuis)
	end
	local character = player.Character
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

-- Cette méthode permet de figer la caméra sur la pièce de cadrage `frame` lorsque la prise est prête : la largeur
-- voulue remplit toute l'image, au champ PlanchePlan.FOV.
local function aim(frame: BasePart)
	local camera = Workspace.CurrentCamera
	local width = frame:GetAttribute("Width") :: number
	local viewport = camera.ViewportSize
	local distance = PlanchePlan.distance(width, viewport.X / viewport.Y)
	savedFov = savedFov or camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = PlanchePlan.FOV
	camera.CFrame = CFrame.lookAt(frame.Position - frame.CFrame.LookVector * distance, frame.Position)
	hideScene(true)
	print(
		string.format(
			"[planches] caméra sur %s (image %dx%d)",
			tostring(frame:GetAttribute("Shot")),
			viewport.X,
			viewport.Y
		)
	)
end

-- Cette méthode permet de rendre la caméra au jeu, l'interface et l'avatar lorsque la séance se termine.
local function release()
	if savedFov == nil and coreSaved == nil then
		return -- pas de séance en cours : la caméra du jeu (vol, cinématique) n'est pas touchée
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	if savedFov then
		camera.FieldOfView = savedFov
		savedFov = nil
	end
	hideScene(false)
end

-- Cette méthode permet d'attendre la pièce de cadrage de la prise `shot` (posée par le serveur, répliquée) puis d'y
-- figer la caméra lorsque l'attribut PhotoShot change.
local function follow(shot: string, current: number)
	-- Scène au-dessus du hub : demandée au streaming si elle est activée
	pcall(player.RequestStreamAroundAsync, player, Workspace.CurrentCamera.CFrame.Position)
	local started = os.clock()
	while current == token and os.clock() - started < FRAME_TIMEOUT do
		local scene = Workspace:FindFirstChild("PhotoStudio")
		local frame = scene and scene:FindFirstChild(PlanchePlan.FRAME)
		if frame and frame:IsA("BasePart") and frame:GetAttribute("Shot") == shot then
			pcall(player.RequestStreamAroundAsync, player, frame.Position)
			aim(frame)
			return
		end
		task.wait(0.1)
	end
	if current == token then
		warn("[planches] cadrage introuvable pour " .. shot)
	end
end

-- Cette méthode permet de suivre l'attribut PhotoShot de Workspace lorsque le client démarre en Studio.
function PhotoCamera.init()
	Workspace:GetAttributeChangedSignal(PlanchePlan.SHOT):Connect(function()
		token += 1
		local shot = Workspace:GetAttribute(PlanchePlan.SHOT)
		if type(shot) == "string" and shot ~= "" then
			task.spawn(follow, shot, token)
		else
			release()
		end
	end)
end

return PhotoCamera
