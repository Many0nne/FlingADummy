--# selene: allow(global_usage)
-- Caméra des captures de la page du jeu (#178), Studio seulement : à coller une fois par séance dans le MCP Studio
-- (execute_luau, contexte Client, en Play). Cache l'interface (celle du jeu, y compris les fenêtres ouvertes plus
-- tard, et celle de Roblox) et l'avatar du joueur, puis suit à chaque image la pièce StoreCamera posée par stage.luau
-- (attributs From, At, Fov) : les scripts du jeu remettent la caméra en Custom, le cadrage est donc reposé après eux.
-- Mettre RELEASE à true pour tout rendre en fin de séance (le Stop du playtest suffit aussi).
local RELEASE = false

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera
local BINDING = "FadStore"

-- Cette méthode permet de cacher (ou de rendre) l'interface et l'avatar local lorsque la séance commence ou finit.
local function hide(hidden: boolean)
	for _, screen in gui:GetChildren() do
		if screen:IsA("ScreenGui") then
			screen.Enabled = not hidden
		end
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, not hidden)
	pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", not hidden)
	local character = player.Character
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

pcall(RunService.UnbindFromRenderStep, RunService, BINDING)
if _G.FadStoreHook then
	_G.FadStoreHook:Disconnect()
	_G.FadStoreHook = nil
end

if RELEASE then
	hide(false)
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	return "rendu"
end

hide(true)
-- Fenêtre ouverte pendant la séance (révélation, annonce) : cachée dès son arrivée
_G.FadStoreHook = gui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") then
		child.Enabled = false
	end
end)
RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Last.Value + 50, function()
	local scene = Workspace:FindFirstChild("StoreScene")
	local frame = scene and scene:FindFirstChild("StoreCamera")
	if not frame then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = frame:GetAttribute("Fov")
	camera.CFrame = CFrame.lookAt(frame:GetAttribute("From"), frame:GetAttribute("At"))
end)
return string.format("caméra liée, image %dx%d", camera.ViewportSize.X, camera.ViewportSize.Y)
