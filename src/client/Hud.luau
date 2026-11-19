-- HUD permanent : compteurs Throw Power et argent (bas gauche), bouton et fenêtre des améliorations (gauche), barre
-- d'entraînement avec STOP, gains de puissance qui s'envolent, popups LEVEL UP / NEW GEAR, consigne du moment.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Training = require(Shared:WaitForChild("Training"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS

type Card = { title: TextLabel, detail: TextLabel, buy: TextButton }

local Hud = {}

local player: Player
local gui: ScreenGui
local root: Frame -- tout le HUD permanent, masqué pendant le vol
local powerLabel: TextLabel
local moneyLabel: TextLabel
local upgradesButton: TextButton
local badge: Frame
local window: Frame
local gearCard: Card
local valueCard: Card
local trainBar: Frame
local trainLevel: TextLabel
local trainFill: Frame
local trainCount: TextLabel
local hint: TextLabel
local lastPower = 0
local levelStartPower = 0

-- Cette méthode permet de lire un attribut numérique du joueur (valeur par défaut si absent) lorsque le HUD se
-- rafraîchit.
local function stat(name: string, default: number): number
	return (player:GetAttribute(name) :: number?) or default
end

-- Cette méthode permet de créer une pastille de compteur (icône + valeur) en bas à gauche lorsque le HUD est construit.
local function counter(parent: Instance, order: number, icon: string, color: Color3): TextLabel
	local pill = UIKit.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(230, 52),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.25,
		Parent = parent,
	})
	UIKit.corner(pill, 26)
	UIKit.outline(pill, 3)
	UIKit.text({ Size = UDim2.fromOffset(52, 52), Text = icon, TextSize = 32, Parent = pill })
	return UIKit.text({
		Position = UDim2.fromOffset(52, 0),
		Size = UDim2.new(1, -62, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 34,
		TextColor3 = color,
		Parent = pill,
	})
end

-- Cette méthode permet de construire une carte d'amélioration (titre, détail, bouton d'achat) dans la fenêtre lorsque
-- le HUD est construit.
local function card(parent: Instance, order: number, kind: string, color: Color3): Card
	local frame = UIKit.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = Color3.fromRGB(55, 60, 78),
		Parent = parent,
	})
	UIKit.corner(frame, 14)
	UIKit.outline(frame, 3)
	local title = UIKit.text({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -200, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 30,
		TextColor3 = color,
		Parent = frame,
	})
	local detail = UIKit.text({
		Position = UDim2.fromOffset(16, 48),
		Size = UDim2.new(1, -200, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = UIKit.BODY_FONT,
		TextSize = 22,
		TextWrapped = true,
		Parent = frame,
	})
	local buy = UIKit.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(170, 70),
		TextSize = 30,
		Parent = frame,
	}, function()
		Hud.onBuy(kind)
	end)
	return { title = title, detail = detail, buy = buy }
end

-- Cette méthode permet de construire la fenêtre des améliorations (équipement d'entraînement, valeur du mannequin)
-- lorsque le HUD est construit.
local function buildWindow()
	window = UIKit.create("Frame", {
		Name = "Upgrades",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 360),
		BackgroundColor3 = C.panel,
		Visible = false,
		Parent = gui,
	})
	UIKit.corner(window, 18)
	UIKit.outline(window, 4)
	local header = UIKit.create("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = C.yellow,
		Parent = window,
	})
	UIKit.corner(header, 18)
	UIKit.text({ Size = UDim2.fromScale(1, 1), Text = "UPGRADES", TextSize = 44, Parent = header })
	UIKit.button({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = C.red,
		Text = "X",
		TextSize = 30,
		Parent = window,
	}, function()
		window.Visible = false
	end)
	local cards = UIKit.create("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(20, 84),
		Size = UDim2.new(1, -40, 1, -100),
		BackgroundTransparency = 1,
		Parent = window,
	})
	UIKit.create("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = cards })
	gearCard = card(cards, 1, "Gear", C.yellow)
	valueCard = card(cards, 2, "Value", C.green)
end

-- Cette méthode permet de rafraîchir compteurs, cartes d'amélioration et pastille « ! » lorsque l'argent, la
-- puissance, l'équipement ou la valeur changent.
local function refreshEconomy()
	local money = stat("Money", 0)
	moneyLabel.Text = Format.money(money)
	powerLabel.Text = Format.short(stat("ThrowPower", GameConfig.START_POWER))

	local tier = stat("GearTier", 1)
	local gear = Training.gear(tier)
	local gearCost = Training.nextGearCost(tier)
	gearCard.title.Text = "TRAINING GEAR"
	if gearCost then
		local nextGear = Training.gear(tier + 1)
		gearCard.detail.Text = string.format(
			"%s <b>+%s</b>/rep  →  %s <b>+%s</b>/rep",
			gear.name,
			Format.short(gear.gain),
			nextGear.name,
			Format.short(nextGear.gain)
		)
		gearCard.buy.Text = Format.money(gearCost)
	else
		gearCard.detail.Text = string.format("%s <b>+%s</b>/rep", gear.name, Format.short(gear.gain))
		gearCard.buy.Text = "MAXED"
	end

	local level = stat("ValueLevel", 1)
	local valueCost = Economy.valueCost(level)
	valueCard.title.Text = "DUMMY VALUE  Lv " .. level
	valueCard.detail.Text = string.format(
		"Payout <b>x%.2f</b>  →  <b>x%.2f</b>",
		Economy.valueMultiplier(level),
		Economy.valueMultiplier(level + 1)
	)
	valueCard.buy.Text = if valueCost then Format.money(valueCost) else "MAXED"

	local canGear = gearCost ~= nil and money >= gearCost
	local canValue = valueCost ~= nil and money >= valueCost
	gearCard.buy.BackgroundColor3 = if canGear then C.green else C.locked
	valueCard.buy.BackgroundColor3 = if canValue then C.green else C.locked
	badge.Visible = canGear or canValue
end

-- Cette méthode permet de faire s'envoler un gain (« +3 💪 ») au-dessus de la barre d'entraînement lorsque la
-- puissance augmente.
local function floatGain(amount: number)
	local label = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, math.random(-60, 60), 1, -150),
		Size = UDim2.fromOffset(200, 40),
		Text = "+" .. Format.short(amount) .. " 💪",
		TextSize = 34,
		TextColor3 = C.yellow,
		Parent = gui,
	})
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = label.Position - UDim2.fromOffset(0, 90),
		TextTransparency = 1,
	}):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.9), { Transparency = 1 }):Play()
	end
	task.delay(1, function()
		label:Destroy()
	end)
end

-- Cette méthode permet de rafraîchir la barre d'entraînement (niveau, répétitions) lorsque la progression change.
local function refreshTraining()
	local level = stat("TrainLevel", 1)
	local reps = stat("TrainReps", 0)
	local needed = Training.repsForLevel(level)
	trainLevel.Text = "LEVEL " .. level
	trainCount.Text = reps .. " / " .. needed
	TweenService:Create(trainFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(reps / needed, 1) }):Play()
end

-- Cette méthode permet d'afficher la consigne et la barre d'entraînement adaptées à l'action du joueur lorsque son
-- action ou l'état du couloir changent.
local function refreshState()
	local action = player:GetAttribute("Action")
	local state = player:GetAttribute("LaneState")
	trainBar.Visible = action == "Training"
	root.Visible = state ~= "Flying"
	hint.Visible = action == nil and state == "Ready"
end

-- Cette méthode permet de construire la barre d'entraînement (niveau, progression, STOP) en bas de l'écran lorsque
-- le HUD est construit.
local function buildTrainBar(onStop: () -> ())
	trainBar = UIKit.create("Frame", {
		Name = "TrainBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(520, 100),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UIKit.button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(170, 44),
		BackgroundColor3 = C.red,
		Text = "STOP",
		Parent = trainBar,
	}, onStop)
	local track = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = C.panel,
		Parent = trainBar,
	})
	UIKit.corner(track, 12)
	UIKit.outline(track, 3)
	trainFill = UIKit.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.blue,
		Parent = track,
	})
	UIKit.corner(trainFill, 12)
	trainLevel = UIKit.text({
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromScale(0.5, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 26,
		ZIndex = 2,
		Parent = track,
	})
	trainCount = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 26,
		ZIndex = 2,
		Parent = track,
	})
end

-- Cette méthode permet d'adapter l'échelle du HUD à la taille de l'écran lorsque la fenêtre change (mobile compris).
local function bindScale(scale: UIScale)
	local camera = Workspace.CurrentCamera
	local function update()
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.55, 1.3)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
end

-- Cette méthode permet de donner le ScreenGui du jeu (créé par Hud.init) lorsqu'un autre module y ajoute ses éléments.
function Hud.screen(): ScreenGui
	return gui
end

-- Cette méthode permet de recevoir un achat demandé par l'interface ; remplacée par init.client (envoi au serveur).
function Hud.onBuy(_kind: string) end

-- Cette méthode permet de construire le HUD et de le brancher sur les attributs du joueur lorsque le client démarre ;
-- `onStop` arrête l'entraînement.
function Hud.init(localPlayer: Player, onStop: () -> ())
	player = localPlayer
	gui = UIKit.create("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	bindScale(UIKit.create("UIScale", { Parent = gui }))
	root = UIKit.create("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local counters = UIKit.create("Frame", {
		Name = "Counters",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(240, 116),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Parent = counters,
	})
	powerLabel = counter(counters, 1, "💪", C.yellow)
	moneyLabel = counter(counters, 2, "💵", C.green)

	upgradesButton = UIKit.button({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = C.blue,
		Text = "⬆️\n<font size='18'>UPGRADES</font>",
		TextSize = 40,
		Radius = 18,
		Parent = root,
	}, function()
		window.Visible = not window.Visible
		if window.Visible then
			UIKit.pop(window, 0.7)
		end
	end)
	badge = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.red,
		Visible = false,
		Parent = upgradesButton,
	})
	UIKit.corner(badge, 15)
	UIKit.outline(badge, 2)
	UIKit.text({ Size = UDim2.fromScale(1, 1), Text = "!", TextSize = 24, Parent = badge })

	hint = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(760, 34),
		Font = UIKit.BODY_FONT,
		TextSize = 26,
		Text = "Stand on the <font color='#FFD23C'>yellow pad</font> to throw  ·  "
			.. "<font color='#FFD23C'>💪 Train</font> to throw farther",
		Parent = root,
	})

	buildWindow()
	buildTrainBar(onStop)

	lastPower = stat("ThrowPower", GameConfig.START_POWER)
	levelStartPower = lastPower
	for _, attribute in { "Money", "GearTier", "ValueLevel" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshEconomy)
	end
	player:GetAttributeChangedSignal("ThrowPower"):Connect(function()
		local power = stat("ThrowPower", GameConfig.START_POWER)
		if power > lastPower and player:GetAttribute("Action") == "Training" then
			floatGain(power - lastPower)
			UIKit.pop(powerLabel, 1.2)
		end
		lastPower = power
		refreshEconomy()
	end)
	player:GetAttributeChangedSignal("TrainLevel"):Connect(function()
		local power = stat("ThrowPower", GameConfig.START_POWER)
		UIKit.banner(gui, "LEVEL UP!", "Throw Power +" .. Format.short(power - levelStartPower))
		levelStartPower = power
		UIKit.playSound("LevelUp")
		refreshTraining()
	end)
	player:GetAttributeChangedSignal("TrainReps"):Connect(refreshTraining)
	player:GetAttributeChangedSignal("GearTier"):Connect(function()
		local gear = Training.gear(stat("GearTier", 1))
		UIKit.banner(gui, "NEW GEAR!", gear.name .. "  +" .. Format.short(gear.gain) .. " per rep", C.green)
		UIKit.playSound("LevelUp", 1.2)
	end)
	player:GetAttributeChangedSignal("Money"):Connect(function()
		UIKit.pop(moneyLabel, 1.15)
	end)
	player:GetAttributeChangedSignal("Action"):Connect(refreshState)
	player:GetAttributeChangedSignal("LaneState"):Connect(refreshState)
	refreshEconomy()
	refreshTraining()
	refreshState()
end

return Hud
