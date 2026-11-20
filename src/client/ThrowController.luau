-- Lancer : sur la zone de lancer, une jauge verticale apparaît et son aiguille court toute seule ; un clic (toucher,
-- Espace) l'arrête, la cinématique démarre (gros plan, bandes noires), l'avatar joue son geste de lancer et le
-- mannequin part au lâcher avec la valeur de la jauge.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Gauge = require(Shared:WaitForChild("Gauge"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CharacterPoser = require(script.Parent.CharacterPoser)
local ThrowCinematic = require(script.Parent.ThrowCinematic)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local GAUGE_HEIGHT = 300

local ThrowController = {}

local player: Player
local remotes: Remotes.Remotes
local frame: Frame
local needle: Frame
local valueLabel: TextLabel
local promptLabel: TextLabel
local shownAt = 0
local locked: number? = nil -- valeur figée par le clic, en attendant le lâcher

-- Cette méthode permet de construire la jauge verticale (dégradé, zone PERFECT, aiguille, valeur) lorsque le client
-- démarre.
local function build(gui: ScreenGui)
	frame = UIKit.create("Frame", {
		Name = "ThrowGauge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 150, 0.5, -20),
		Size = UDim2.fromOffset(64, GAUGE_HEIGHT),
		BackgroundColor3 = C.white,
		Visible = false,
		Parent = gui,
	})
	UIKit.corner(frame, 32)
	UIKit.outline(frame, 5)
	UIKit.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 230, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 215, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 70, 50)),
		}),
		Rotation = 90,
		Parent = frame,
	})
	-- Graduations
	for i = 1, 9 do
		UIKit.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, i / 10),
			Size = UDim2.new(1, -12, 0, 3),
			BackgroundColor3 = C.ink,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Parent = frame,
		})
	end
	local perfect = UIKit.create("Frame", {
		Name = "Perfect",
		Size = UDim2.fromScale(1, 1 - GameConfig.PERFECT_THRESHOLD),
		BackgroundColor3 = C.gold,
		Parent = frame,
	})
	UIKit.corner(perfect, 32)
	UIKit.text({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(-14, 14),
		Size = UDim2.fromOffset(130, 30),
		Text = "PERFECT",
		TextSize = 26,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})
	needle = UIKit.create("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 22, 0, 12),
		BackgroundColor3 = C.white,
		ZIndex = 3,
		Parent = frame,
	})
	UIKit.corner(needle, 6)
	UIKit.outline(needle, 3)
	valueLabel = UIKit.text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 12, 0.5, 0),
		Size = UDim2.fromOffset(90, 40),
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = needle,
	})
	promptLabel = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 22),
		Size = UDim2.fromOffset(360, 40),
		Text = if UserInputService.TouchEnabled then "Tap to throw!" else "Click to throw!",
		TextSize = 36,
		Parent = frame,
	})
end

-- Cette méthode permet de donner la position courante de l'aiguille (0-1) lorsque la jauge est affichée.
local function currentValue(): number
	return locked or Gauge.value(os.clock() - shownAt)
end

-- Cette méthode permet de tourner l'avatar et la caméra vers la piste lorsque le joueur prend le mannequin en main.
local function faceTrack()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local position = root.Position
	root.CFrame = CFrame.lookAt(position, position + Vector3.zAxis)
	local camera = Workspace.CurrentCamera
	camera.CFrame = CFrame.lookAt(position + Vector3.new(5, 7, -15), position + Vector3.new(0, 4, 25))
end

-- Cette méthode permet d'immobiliser l'avatar pendant le geste (ou de lui rendre ses déplacements) lorsque le
-- lancer commence ou finit : quitter la zone de lancer en plein geste ferait refuser le lancer par le serveur.
local function setRooted(character: Model, rooted: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if rooted then
		humanoid:SetAttribute("WalkSpeedBeforeThrow", humanoid.WalkSpeed)
		humanoid.WalkSpeed = 0
	else
		local speed = humanoid:GetAttribute("WalkSpeedBeforeThrow")
		if typeof(speed) == "number" then
			humanoid.WalkSpeed = speed
		end
		humanoid:SetAttribute("WalkSpeedBeforeThrow", nil)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not rooted)
end

local refresh: () -> ()

-- Cette méthode permet d'arrêter l'aiguille, de démarrer la cinématique et le geste lorsque le joueur clique pendant
-- qu'il tient le mannequin ; renvoie true si le clic a servi.
local function trigger(): boolean
	local character = player.Character
	if not frame.Visible or locked or CharacterPoser.isThrowing() or not character then
		return false
	end
	local value = currentValue()
	locked = value
	UIKit.pop(needle, 1.5)
	if Gauge.isPerfect(value) then
		UIKit.banner(frame.Parent :: Instance, "PERFECT!", nil, C.gold, 210)
	end
	ThrowCinematic.play(character)
	setRooted(character, true)
	CharacterPoser.playThrow(function()
		remotes.Launch:FireServer(value)
		ThrowCinematic.release()
	end, function()
		-- Geste fini : lancer parti (la jauge se cache au vol) ou refusé (caméra rendue, jauge réarmée)
		setRooted(character, false)
		if player:GetAttribute("LaneState") ~= "Flying" then
			ThrowCinematic.abort()
		end
		locked = nil
		refresh()
	end)
	return true
end

-- Cette méthode permet d'afficher ou de masquer la jauge lorsque le joueur entre sur la zone de lancer ou la quitte.
function refresh()
	local holding = player:GetAttribute("Action") == "Holding"
	if holding and not frame.Visible then
		shownAt = os.clock()
		locked = nil
		frame.Visible = true
		UIKit.pop(frame, 0.6)
		faceTrack()
	elseif not holding and frame.Visible and not CharacterPoser.isThrowing() then
		frame.Visible = false
	end
end

-- Cette méthode permet de brancher la jauge sur l'état du joueur et sur le clic, le toucher et Espace lorsque le
-- client démarre.
function ThrowController.init(localPlayer: Player, createdRemotes: Remotes.Remotes, gui: ScreenGui)
	player = localPlayer
	remotes = createdRemotes
	build(gui)
	ThrowCinematic.init(gui)
	player:GetAttributeChangedSignal("Action"):Connect(refresh)
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Flying" then
			frame.Visible = false
		end
		refresh()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		local kind = input.UserInputType
		if not processed and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			trigger()
		end
	end)
	-- Espace passe par une action prioritaire : sur la zone de lancer, elle lance au lieu de sauter
	ContextActionService:BindActionAtPriority("ThrowDummy", function(_, state)
		if state == Enum.UserInputState.Begin and trigger() then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)

	RunService.RenderStepped:Connect(function()
		if frame.Visible then
			local value = currentValue()
			needle.Position = UDim2.fromScale(0.5, 1 - value)
			valueLabel.Text = "+" .. (1 + math.floor(value * (GameConfig.GAUGE_STEPS - 1) + 0.5))
			valueLabel.TextColor3 = if Gauge.isPerfect(value) then C.gold else C.white
			promptLabel.Visible = locked == nil
		end
	end)
end

return ThrowController
