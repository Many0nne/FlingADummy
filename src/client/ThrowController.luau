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
local GAUGE_HEIGHT = 320 -- ≈ 0,45 h à 720 px, comme les références
local GAUGE_WIDTH = 64

local ThrowController = {}

local player: Player
local remotes: Remotes.Remotes
local frame: Frame
local needle: Frame
local valueLabel: TextLabel
local promptLabel: TextLabel
local shownAt = 0
local locked: number? = nil -- valeur figée par le clic, en attendant le lâcher

-- Cette méthode permet de construire la jauge verticale au style des références (capsule à contour noir, dégradé
-- vert en haut → rouge en bas, traits sombres, curseur blanc, valeur « +N » à droite, consigne dessous) lorsque le
-- client démarre. Pas de zone PERFECT : le haut est le max.
local function build(gui: ScreenGui)
	frame = UIKit.create("Frame", {
		Name = "ThrowGauge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 110, 0.5, -30),
		Size = UDim2.fromOffset(GAUGE_WIDTH, GAUGE_HEIGHT),
		BackgroundColor3 = C.white,
		Visible = false,
		Parent = gui,
	})
	UIKit.corner(frame, GAUGE_WIDTH // 2)
	UIKit.outline(frame, 5)
	UIKit.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(125, 235, 95)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(215, 230, 70)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 175, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 60, 45)),
		}),
		Rotation = 90,
		Parent = frame,
	})
	-- Reflet vertical (relief de la capsule)
	local gloss = UIKit.create("Frame", {
		Position = UDim2.fromOffset(8, 14),
		Size = UDim2.new(0, 10, 1, -28),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Parent = frame,
	})
	UIKit.corner(gloss, 5)
	-- Traits sombres (4, comme les références)
	for i = 1, 4 do
		UIKit.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, i / 5),
			Size = UDim2.new(1, -4, 0, 3),
			BackgroundColor3 = C.ink,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Parent = frame,
		})
	end
	needle = UIKit.create("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 20, 0, 14),
		BackgroundColor3 = C.white,
		ZIndex = 3,
		Parent = frame,
	})
	UIKit.corner(needle, 7)
	UIKit.outline(needle, 3, Color3.fromRGB(60, 60, 70))
	valueLabel = UIKit.text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 10, 0.5, 0),
		Size = UDim2.fromOffset(90, 40),
		TextSize = 36,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = needle,
	})
	promptLabel = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 14),
		Size = UDim2.fromOffset(360, 40),
		Text = if UserInputService.TouchEnabled then "Tap to throw!" else "Click to throw!",
		TextSize = 34,
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
	faceTrack() -- le joueur a pu tourner sur la zone depuis l'apparition de la jauge
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
			CharacterPoser.handOff()
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
			promptLabel.Visible = locked == nil
		end
	end)
end

return ThrowController
