-- Lancer : figé par le serveur sur la bande de lancer, le joueur voit une jauge verticale dont l'aiguille court toute
-- seule, caméra resserrée derrière l'épaule (Client.FlightCamera.band, #158) ; un clic (toucher, Espace) l'arrête (son et rebond), la cinématique démarre (gros plan, bandes noires),
-- l'avatar joue son geste de lancer et le mannequin part au lâcher avec la valeur de la jauge (vérifiée par le
-- serveur). Anime aussi le reflet de la bande, localement.
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseLayout = require(Shared:WaitForChild("CourseLayout"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Gauge = require(Shared:WaitForChild("Gauge"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CharacterPoser = require(script.Parent.CharacterPoser)
local FlightCamera = require(script.Parent.FlightCamera)
local LaunchGhost = require(script.Parent.LaunchGhost)
local ThrowCinematic = require(script.Parent.ThrowCinematic)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local GAUGE_HEIGHT = 320 -- ≈ 0,45 h à 720 px, comme les références
local GAUGE_WIDTH = 64
local SHINE_SWEEP = 2.2 -- durée du passage du reflet sur la bande (s)
local SHINE_REACH = 1.5 -- décalage du dégradé aux deux bouts : le reflet sort entièrement de la bande
local SHINE_PAUSE = 1.4 -- pause entre deux passages (s)

local ThrowController = {}

-- Branché par l'amorçage du client : départ affiché dès le lâcher, jauge arrêtée à `gauge` (#144)
ThrowController.onReleased = nil :: ((gauge: number) -> ())?

local player: Player
local remotes: Remotes.Remotes
local frame: Frame
local needle: Frame
local valueLabel: TextLabel
local promptLabel: TextLabel
local shownAt = 0
local locked: number? = nil -- valeur figée par le clic, en attendant le lâcher
local shining: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- reflets déjà animés

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

-- Cette méthode permet de savoir si l'avatar du joueur est en vie lorsque la jauge s'affiche ou reçoit un clic : mort
-- sur la bande, il reste en prise côté serveur jusqu'à sa réapparition.
local function alive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Cette méthode permet de donner la position courante de l'aiguille (0-1) lorsque la jauge est affichée.
local function currentValue(): number
	return locked or Gauge.value(os.clock() - shownAt)
end

-- Cette méthode permet de resserrer la caméra derrière l'épaule, vers le bout de la piste (#158), lorsque le joueur
-- est figé sur la bande (le serveur l'a déjà tourné face à la piste) ou y est remis en prise (lancer refusé, THROW
-- AGAIN).
local function frameBand()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		FlightCamera.band(root)
	end
end

-- Cette méthode permet de faire glisser en boucle le reflet de la bande de lancer (un seul dégradé, animé par ce
-- client : rien ne passe par le réseau) lorsqu'il apparaît dans le monde.
local function animateShine(gradient: Instance)
	if not gradient:IsA("UIGradient") or shining[gradient] then
		return
	end
	shining[gradient] = true
	gradient.Offset = Vector2.new(-SHINE_REACH, 0)
	local tween = TweenService:Create(
		gradient,
		TweenInfo.new(SHINE_SWEEP, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, SHINE_PAUSE),
		{ Offset = Vector2.new(SHINE_REACH, 0) }
	)
	tween:Play()
	-- Bande sortie du monde (streaming) : l'animation s'arrête, une nouvelle repartira à son retour
	local connection
	connection = gradient.AncestryChanged:Connect(function()
		if not gradient:IsDescendantOf(game) then
			tween:Cancel()
			connection:Disconnect()
			shining[gradient] = nil
		end
	end)
end

local refresh: () -> ()

-- Cette méthode permet d'arrêter l'aiguille, de démarrer la cinématique et le geste lorsque le joueur clique pendant
-- qu'il tient le mannequin ; renvoie true si le clic a servi.
local function trigger(): boolean
	local character = player.Character
	if not frame.Visible or locked or CharacterPoser.isThrowing() or not character or not alive() then
		return false
	end
	local value = currentValue()
	locked = value
	remotes.GaugeStop:FireServer() -- le serveur note l'heure d'arrivée du clic (anti-triche de la jauge)
	UIKit.playSound("GaugeStop")
	UIKit.pop(needle, 1.5)
	UIKit.pop(frame, 1.12) -- petit rebond de toute la jauge
	ThrowCinematic.play(character)
	CharacterPoser.playThrow(function()
		remotes.Launch:FireServer(value)
		ThrowCinematic.release()
		if ThrowController.onReleased then
			ThrowController.onReleased(value)
		end
	end, function()
		-- Geste fini : lancer parti (la jauge se cache au vol) ou refusé (caméra rendue, jauge réarmée) ; tant que le
		-- décoratif lâché vole sans réponse du serveur (#144), la jauge attend
		-- Cette méthode permet de clore le geste lorsque la réponse du serveur est connue.
		local function settle()
			if player:GetAttribute("LaneState") ~= "Flying" then
				if LaunchGhost.anticipating() then
					task.delay(0.1, settle) -- borné : Client.LaunchGhost s'arrête au plus HANDOFF_TIME après le lâcher
					return
				end
				-- Toujours en prise : la caméra revient sur la bande depuis le gros plan ou le vol effacé, sans passer
				-- par la caméra libre (champ de vision compris)
				local holding = player:GetAttribute("Action") == "Holding"
				ThrowCinematic.abort(holding)
				CharacterPoser.handOff()
				if holding then
					frameBand()
				end
			end
			locked = nil
			refresh()
		end
		settle()
	end)
	return true
end

-- Cette méthode permet d'afficher la jauge lorsque le serveur fige le joueur sur la bande, et de la masquer après.
function refresh()
	-- Lancer accepté : LaneState passe à Flying avant qu'Action ne soit vidé (ordre des signaux) ; la jauge et la
	-- caméra de la bande ne reviennent pas entre les deux
	local holding = player:GetAttribute("Action") == "Holding"
		and player:GetAttribute("LaneState") ~= "Flying"
		and alive()
	if holding and not frame.Visible then
		shownAt = os.clock()
		locked = nil
		frame.Visible = true
		UIKit.pop(frame, 0.6)
		frameBand()
	elseif not holding and frame.Visible and not CharacterPoser.isThrowing() then
		frame.Visible = false
		FlightCamera.leaveBand() -- sorti de la bande sans lancer ; sans effet si le geste a pris la caméra
	end
end

-- Cette méthode permet de brancher la jauge sur l'état du joueur et sur le clic, le toucher et Espace, et le reflet de
-- la bande, lorsque le client démarre.
function ThrowController.init(localPlayer: Player, createdRemotes: Remotes.Remotes, gui: ScreenGui)
	player = localPlayer
	remotes = createdRemotes
	build(gui)
	ThrowCinematic.init(gui)
	player:GetAttributeChangedSignal("Action"):Connect(refresh)
	-- Mort sur la bande : jauge masquée et caméra libre rendue sans attendre la réapparition
	-- Cette méthode permet de surveiller la mort de l'avatar lorsqu'il apparaît.
	local function watchDeath(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(refresh)
		end
	end
	player.CharacterAdded:Connect(watchDeath)
	if player.Character then
		task.spawn(watchDeath, player.Character)
	end
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
	-- Espace passe par une action prioritaire : sur la bande, elle lance au lieu de sauter
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

	CollectionService:GetInstanceAddedSignal(CourseLayout.BAND_SHINE_TAG):Connect(animateShine)
	for _, gradient in CollectionService:GetTagged(CourseLayout.BAND_SHINE_TAG) do
		animateShine(gradient)
	end
end

return ThrowController
