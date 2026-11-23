--# selene: allow(global_usage)
-- Caméra, interface et musique du tournage de la vidéo de présentation (#225), Studio seulement : à coller une fois par
-- séance dans le MCP Studio (execute_luau, contexte Client, en Play). Cache l'interface (celle du jeu, y compris les
-- fenêtres ouvertes plus tard, celle de Roblox, les panneaux flottants et la flèche de l'objectif), coupe la musique du
-- jeu (posée au montage, d'un seul tenant), puis, tant que _G.FadCam.shot est posé, impose à chaque image le cadrage
-- qu'il calcule (les scripts du jeu remettent la caméra en Custom : le cadrage est reposé après eux). Sans prise, la
-- caméra du jeu reprend la main (lancer). _G.FadCam.flash() affiche une image magenta plein écran : repère de début de
-- prise retrouvé au montage (assets/store/video/edit.py).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera
local BINDING = "FadVideo"
local HIDDEN_GUIS = { "ObjectiveArrow", "LandingChance" } -- panneaux du joueur attachés au monde, réactivés par le jeu

local C = _G.FadCam or {}
_G.FadCam = C

-- Cette méthode permet de cacher un panneau flottant ou une interface lorsque elle apparaît pendant la séance.
local function hide(instance: Instance)
	local screen = instance:IsA("ScreenGui") and instance.Name ~= "FadMarker"
	if screen or instance:IsA("BillboardGui") then
		(instance :: any).Enabled = false
	end
end

for _, screen in gui:GetChildren() do
	hide(screen)
end
for _, name in HIDDEN_GUIS do
	local panel = gui:FindFirstChild(name)
	if panel then
		panel.Parent = nil -- le jeu le réactive à chaque image : retiré de l'affichage
	end
end
for _, item in Workspace:GetDescendants() do
	hide(item)
end
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)
for _, connection in C.hooks or {} do
	connection:Disconnect()
end
C.hooks = {
	gui.ChildAdded:Connect(function(child)
		if table.find(HIDDEN_GUIS, child.Name) then
			task.defer(function()
				child.Parent = nil
			end)
		else
			hide(child)
		end
	end),
	Workspace.DescendantAdded:Connect(hide),
}

-- Écran du repère : un cadre magenta plein écran, montré au début de chaque prise
local marker = gui:FindFirstChild("FadMarker") :: ScreenGui?
if not marker then
	local screen = Instance.new("ScreenGui")
	screen.Name = "FadMarker"
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 1000
	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 0, 255)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screen
	screen.Parent = gui
	marker = screen
end

-- Cette méthode permet d'afficher le repère magenta pendant `seconds` lorsque une prise commence.
function C.flash(seconds: number?)
	local frame = (marker :: ScreenGui):FindFirstChild("Flash") :: Frame
	frame.Visible = true
	task.delay(seconds or 0.15, function()
		frame.Visible = false
	end)
end

-- Cette méthode permet de poser un cadrage fixe (caméra en `from`, visée `at`, champ `fov`) lorsque une prise n'a
-- pas besoin de mouvement de caméra.
function C.fixed(from: Vector3, at: Vector3, fov: number)
	C.shot = function()
		return CFrame.lookAt(from, at), fov
	end
end

-- Cette méthode permet de suivre de côté (décalage `offset`, lissage `sharp`) le torse du mannequin lancé que
-- `pick` préfère (premier venu sans `pick`) lorsque la prise filme un vol et son crash.
function C.chase(offset: Vector3, fov: number, sharp: number?, pick: ((Vector3, Vector3) -> boolean)?)
	local folder = Workspace.Course.Dummies
	local torso: BasePart? = nil
	local pos: Vector3? = nil
	local focus: Vector3? = nil
	local start = Vector3.new(-9, 6, -25)
	C.shot = function(dt: number)
		if not torso or not torso.Parent then
			torso = nil
			for _, model in folder:GetChildren() do
				local candidate = model:FindFirstChild("Torso") :: BasePart?
				if candidate and (not torso or (pick and pick(candidate.Position, torso.Position))) then
					torso = candidate
				end
			end
			if not torso then
				return CFrame.lookAt(start + offset, start + Vector3.new(0, 0, 20)), fov
			end
		end
		local p = (torso :: BasePart).Position
		local k = 1 - math.exp(-(sharp or 5) * dt)
		pos = if pos then pos:Lerp(p + offset, k) else p + offset
		focus = if focus then focus:Lerp(p, 1 - math.exp(-10 * dt)) else p
		return CFrame.lookAt(pos :: Vector3, focus :: Vector3), fov
	end
end

-- Cette méthode permet de rendre la caméra au jeu lorsque la prise suivante utilise la caméra du lancer.
function C.release()
	C.shot = nil
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end

pcall(RunService.UnbindFromRenderStep, RunService, BINDING)
RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Last.Value + 50, function(dt)
	-- Musique du jeu coupée (groupe « Music » de Client.Music) : elle est posée au montage
	local music = SoundService:FindFirstChild("Music")
	if music and music:IsA("SoundGroup") and music.Volume ~= 0 then
		music.Volume = 0
	end
	-- Flèche de l'objectif posée sur la piste (Workspace.ObjectiveMarkers)
	local markers = Workspace:FindFirstChild("ObjectiveMarkers")
	if markers then
		for _, part in markers:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			end
		end
	end
	local shot = C.shot
	if not shot then
		return
	end
	local ok, frame, fov = pcall(shot, dt)
	if not ok or not frame then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = frame
	camera.FieldOfView = fov or 50
end)

return string.format("caméra liée, image %dx%d", camera.ViewportSize.X, camera.ViewportSize.Y)
