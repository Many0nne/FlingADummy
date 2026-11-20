-- Cinématique du lancer (joueur local), sur le modèle de Throw Food For Animals : bandes noires, gros plan sur
-- l'avatar (FlightCamera.closeUp), traînées de vitesse à l'écran pendant le fouetté et traînée sur la main qui lance ;
-- tout se retire quand le mannequin du serveur part (finish) ou, à défaut, après un délai.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FlightCamera = require(script.Parent.FlightCamera)

local BAR_HEIGHT = 0.11 -- hauteur d'une bande noire (fraction de l'écran)
local BAR_IN = 0.18
local BAR_OUT = 0.35
local STREAK_COUNT = 22
local STREAK_START = 0.4 -- les traînées apparaissent à l'élan (s après le clic)
local STREAK_AFTER = 0.35 -- et durent après le lâcher (s)
local STREAK_SPEED = 3.2 -- largeurs d'écran par seconde
local TIMEOUT_AFTER_RELEASE = 1.5 -- fin forcée si le serveur n'a pas lancé le mannequin (s)
local STREAK_WHITE = Color3.fromRGB(255, 255, 255)
local STREAK_YELLOW = Color3.fromRGB(255, 225, 70)

type Streak = { frame: Frame, x: number, speed: number }

local ThrowCinematic = {}

local layer: Frame
local topBar: Frame
local bottomBar: Frame
local streaks: { Streak } = {}
local rng = Random.new()
local session = 0 -- incrémenté à chaque lancer : les délais d'un lancer précédent s'ignorent
local active = false
local streaksOn = false
local trail: Trail? = nil

-- Cette méthode permet de créer un cadre plein (bande, traînée) lorsque la cinématique se construit.
local function bar(name: string, anchorY: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, anchorY)
	frame.Position = UDim2.fromScale(0.5, anchorY)
	frame.Size = UDim2.fromScale(1, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.ZIndex = 50
	frame.Parent = layer
	return frame
end

-- Cette méthode permet de replacer une traînée à gauche de l'écran (hauteur, longueur, couleur au hasard) lorsqu'elle
-- sort à droite ou que les traînées démarrent ; elles filent dans le sens du lancer (vers la droite à l'écran).
local function respawn(streak: Streak, spread: boolean)
	local length = rng:NextNumber(0.12, 0.35)
	streak.x = if spread then rng:NextNumber(-0.4, 1) else -length - rng:NextNumber(0, 0.4)
	streak.speed = STREAK_SPEED * rng:NextNumber(0.7, 1.3)
	local frame = streak.frame
	frame.Size = UDim2.new(length, 0, 0, rng:NextInteger(2, 6))
	frame.Position = UDim2.fromScale(streak.x, rng:NextNumber(0.12, 0.88))
	frame.BackgroundColor3 = if rng:NextNumber() < 0.3 then STREAK_YELLOW else STREAK_WHITE
	frame.BackgroundTransparency = rng:NextNumber(0.15, 0.55)
end

-- Cette méthode permet d'afficher ou de masquer les traînées lorsque le geste atteint l'élan ou s'achève.
local function setStreaks(on: boolean)
	streaksOn = on
	for _, streak in streaks do
		if on then
			respawn(streak, true)
		end
		streak.frame.Visible = on
	end
end

-- Cette méthode permet d'ouvrir ou de fermer les bandes noires lorsque la cinématique commence ou finit.
local function setBars(on: boolean)
	local size = UDim2.fromScale(1, if on then BAR_HEIGHT else 0)
	local info = TweenInfo.new(if on then BAR_IN else BAR_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, frame in { topBar, bottomBar } do
		TweenService:Create(frame, info, { Size = size }):Play()
	end
end

-- Cette méthode permet d'accrocher une traînée lumineuse à la main droite lorsque le geste commence.
local function attachTrail(character: Model)
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "ThrowTrail0"
	a0.Position = Vector3.new(0, 0.35, 0)
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Name = "ThrowTrail1"
	a1.Position = Vector3.new(0, -0.35, 0)
	a1.Parent = hand
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.22
	t.LightEmission = 0.6
	t.FaceCamera = true
	t.Color = ColorSequence.new(STREAK_WHITE, STREAK_YELLOW)
	t.Transparency = NumberSequence.new(0.1, 1)
	t.WidthScale = NumberSequence.new(1, 0.2)
	t.Parent = hand
	trail = t
end

-- Cette méthode permet de retirer la traînée de la main lorsque le geste est fini.
local function detachTrail()
	local t = trail
	trail = nil
	if t then
		local hand = t.Parent
		t:Destroy()
		if hand then
			for _, name in { "ThrowTrail0", "ThrowTrail1" } do
				local attachment = hand:FindFirstChild(name)
				if attachment then
					attachment:Destroy()
				end
			end
		end
	end
end

-- Cette méthode permet de démarrer la cinématique lorsque le joueur clique pour lancer : bandes, gros plan jusqu'au
-- lâcher, traînée de la main, traînées d'écran à l'élan.
function ThrowCinematic.play(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	session += 1
	local id = session
	active = true
	setBars(true)
	FlightCamera.closeUp(root, GameConfig.THROW_RELEASE_TIME)
	detachTrail()
	attachTrail(character)
	task.delay(STREAK_START, function()
		if session == id and active then
			setStreaks(true)
		end
	end)
end

-- Cette méthode permet de marquer le lâcher (fin des traînées un peu après, fin forcée si le mannequin du serveur
-- n'arrive pas) lorsque le mannequin quitte la main.
function ThrowCinematic.release()
	local id = session
	task.delay(STREAK_AFTER, function()
		if session == id then
			setStreaks(false)
			detachTrail()
		end
	end)
	task.delay(TIMEOUT_AFTER_RELEASE, function()
		if session == id and active then
			ThrowCinematic.finish()
			FlightCamera.stop()
		end
	end)
end

-- Cette méthode permet de retirer les bandes lorsque le mannequin du serveur part (la caméra de vol prend le
-- relais) ou que le lancer est abandonné.
function ThrowCinematic.finish()
	if not active then
		return
	end
	active = false
	setBars(false)
end

-- Cette méthode permet d'arrêter la cinématique et de rendre la caméra lorsque le geste finit sans que le serveur
-- ait lancé le mannequin (lancer refusé) ; sans effet si le vol a déjà pris le relais.
function ThrowCinematic.abort()
	if not active then
		return
	end
	session += 1
	setStreaks(false)
	detachTrail()
	ThrowCinematic.finish()
	FlightCamera.stop()
end

-- Cette méthode permet de construire les bandes et les traînées (masquées) lorsque le client démarre.
function ThrowCinematic.init(gui: ScreenGui)
	layer = Instance.new("Frame")
	layer.Name = "ThrowCinematic"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 50
	layer.Parent = gui
	topBar = bar("TopBar", 0)
	bottomBar = bar("BottomBar", 1)
	for _ = 1, STREAK_COUNT do
		local frame = Instance.new("Frame")
		frame.Name = "Streak"
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0, 0.5)
		frame.ZIndex = 49
		frame.Visible = false
		frame.Parent = layer
		table.insert(streaks, { frame = frame, x = 0, speed = 0 })
	end
	RunService.RenderStepped:Connect(function(dt)
		if not streaksOn then
			return
		end
		for _, streak in streaks do
			streak.x += streak.speed * dt
			if streak.x > 1.05 then
				respawn(streak, false)
			end
			streak.frame.Position = UDim2.fromScale(streak.x, streak.frame.Position.Y.Scale)
		end
	end)
end

return ThrowCinematic
