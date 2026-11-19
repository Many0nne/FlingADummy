-- Interface construite en code : argent, compteurs de vol, améliorations, jauge de charge et panneau de résultat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 210, 60)
local PANEL = Color3.fromRGB(25, 27, 35)
local BUY = Color3.fromRGB(60, 190, 90)
local LOCKED = Color3.fromRGB(85, 88, 98)

local Hud = {}

local player: Player
local gui: ScreenGui
local moneyLabel: TextLabel
local counters: Frame
local distanceLabel: TextLabel
local bonesLabel: TextLabel
local smashedLabel: TextLabel
local gaugeFrame: Frame
local needle: Frame
local fill: Frame
local hint: TextLabel
local resultFrame: Frame
local resultScale: UIScale
local resultTotal: TextLabel
local resultDetail: TextLabel
local resultPerfect: TextLabel
local upgradeButtons: { [string]: TextButton } = {}
local dummyConnections: { RBXScriptConnection } = {}
local resultToken = 0

-- Cette méthode permet de créer une instance d'interface avec ses propriétés lorsque l'on construit le HUD.
local function create(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

-- Cette méthode permet d'arrondir les coins d'un cadre lorsque l'on construit un panneau.
local function round(parent: Instance, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

-- Cette méthode permet de créer un texte au style du jeu (police ronde, contour sombre) lorsque l'on construit le HUD.
local function text(props: { [string]: any }): TextLabel
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.4,
		TextSize = 24,
	})
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

-- Cette méthode permet d'adapter l'échelle du HUD à la taille de l'écran lorsque la fenêtre change (mobile compris).
local function bindScale(scale: UIScale)
	local camera = Workspace.CurrentCamera
	local function update()
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.6, 1.3)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
end

-- Cette méthode permet de rafraîchir argent et boutons d'amélioration lorsque l'argent ou un niveau change.
local function refreshEconomy()
	local money = (player:GetAttribute("Money") :: number?) or 0
	moneyLabel.Text = Format.money(money)
	for kind, button in upgradeButtons do
		local level = player:GetAttribute(kind .. "Level") or 1
		local cost = Economy.upgradeCost(kind, level)
		local effect
		if kind == "Power" then
			effect = string.format(
				"Speed %d → %d",
				math.floor(Economy.launchSpeed(level)),
				math.floor(Economy.launchSpeed(math.min(level + 1, Economy.maxLevel(kind))))
			)
		else
			effect = string.format(
				"Payout ×%.2f → ×%.2f",
				Economy.valueMultiplier(level),
				Economy.valueMultiplier(math.min(level + 1, Economy.maxLevel(kind)))
			)
		end
		local title = if kind == "Power" then "CANNON POWER" else "DUMMY VALUE"
		local price = if cost then Format.money(cost) else "MAX"
		button.Text = string.format(
			'<font size="20">%s  Lv %d</font>\n<font size="16" color="#DDE3F0">%s</font>\n<font size="24">%s</font>',
			title,
			level,
			if cost then effect else "Maxed out",
			price
		)
		local affordable = cost ~= nil and money >= cost
		button.BackgroundColor3 = if affordable then BUY else LOCKED
		button.AutoButtonColor = affordable
	end
end

-- Cette méthode permet d'afficher la jauge ou les compteurs selon l'état du couloir lorsque LaneState change.
local function refreshState()
	local state = player:GetAttribute("LaneState")
	gaugeFrame.Visible = state == "Ready"
	hint.Visible = state == "Ready"
	if state == "Ready" then
		counters.Visible = false
		Hud.setGauge(0)
	end
end

-- Cette méthode permet de construire les boutons d'amélioration à droite de l'écran lorsque le HUD est créé.
local function buildUpgrades(root: Instance, onBuy: (string) -> ())
	local column = create("Frame", {
		Name = "Upgrades",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(240, 212),
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = column })
	for order, kind in { "Power", "Value" } do
		local button = create("TextButton", {
			Name = kind,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 100),
			Font = FONT,
			RichText = true,
			TextColor3 = WHITE,
			TextStrokeTransparency = 0.5,
			TextSize = 20,
			BackgroundColor3 = LOCKED,
			Parent = column,
		})
		round(button, 14)
		create("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(15, 15, 20),
			Thickness = 3,
			Parent = button,
		})
		button.Activated:Connect(function()
			onBuy(kind)
		end)
		upgradeButtons[kind] = button
	end
end

-- Cette méthode permet de construire la jauge de charge en bas de l'écran lorsque le HUD est créé.
local function buildGauge(root: Instance)
	gaugeFrame = create("Frame", {
		Name = "Gauge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -48),
		Size = UDim2.fromOffset(460, 38),
		BackgroundColor3 = PANEL,
		Parent = root,
	})
	round(gaugeFrame, 10)
	create("UIStroke", { Color = WHITE, Thickness = 3, Parent = gaugeFrame })
	fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		Parent = gaugeFrame,
	})
	round(fill, 10)
	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 200, 90)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(250, 210, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 80, 50)),
		}),
		Parent = fill,
	})
	local perfect = create("Frame", {
		Name = "PerfectZone",
		Position = UDim2.fromScale(GameConfig.PERFECT_THRESHOLD, 0),
		Size = UDim2.fromScale(1 - GameConfig.PERFECT_THRESHOLD, 1),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
		Parent = gaugeFrame,
	})
	text({
		Name = "PerfectLabel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.fromOffset(90, 20),
		Text = "PERFECT",
		TextColor3 = GOLD,
		TextSize = 16,
		Parent = perfect,
	})
	needle = create("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 6, 1, 14),
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = gaugeFrame,
	})
	create("UIStroke", { Color = PANEL, Thickness = 2, Parent = needle })
	hint = text({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -98),
		Size = UDim2.fromOffset(460, 30),
		Text = "HOLD TO CHARGE · RELEASE TO FIRE",
		TextSize = 26,
		Parent = root,
	})
end

-- Cette méthode permet de construire les compteurs de vol (distance, os, objets) en haut de l'écran lorsque le HUD
-- est créé.
local function buildCounters(root: Instance)
	counters = create("Frame", {
		Name = "Counters",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(720, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 30),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = counters,
	})
	distanceLabel = text({ LayoutOrder = 1, Size = UDim2.fromOffset(260, 70), TextSize = 64, Parent = counters })
	bonesLabel = text({
		LayoutOrder = 2,
		Size = UDim2.fromOffset(190, 70),
		TextSize = 34,
		TextColor3 = Color3.fromRGB(255, 120, 90),
		Parent = counters,
	})
	smashedLabel = text({
		LayoutOrder = 3,
		Size = UDim2.fromOffset(190, 70),
		TextSize = 34,
		TextColor3 = Color3.fromRGB(140, 210, 255),
		Parent = counters,
	})
end

-- Cette méthode permet de construire le panneau de résultat au centre de l'écran lorsque le HUD est créé.
local function buildResult(root: Instance)
	resultFrame = create("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(400, 230),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = root,
	})
	round(resultFrame, 18)
	create("UIStroke", { Color = GOLD, Thickness = 4, Parent = resultFrame })
	resultScale = create("UIScale", { Parent = resultFrame })
	resultPerfect = text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(200, 40),
		Text = "PERFECT!",
		TextColor3 = GOLD,
		TextSize = 36,
		Rotation = -4,
		Parent = resultFrame,
	})
	resultTotal = text({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 64),
		TextColor3 = GOLD,
		TextSize = 60,
		Parent = resultFrame,
	})
	resultDetail = text({
		Position = UDim2.fromOffset(20, 96),
		Size = UDim2.new(1, -40, 0, 120),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		Parent = resultFrame,
	})
end

-- Cette méthode permet de placer l'aiguille et le remplissage de la jauge lorsque la charge avance (v entre 0 et 1).
function Hud.setGauge(v: number)
	needle.Position = UDim2.fromScale(v, 0.5)
	fill.Size = UDim2.fromScale(v, 1)
end

-- Cette méthode permet de suivre en direct les compteurs d'un mannequin lancé lorsque le serveur annonce le lancer.
function Hud.setDummy(model: Model)
	for _, connection in dummyConnections do
		connection:Disconnect()
	end
	table.clear(dummyConnections)
	local function update()
		distanceLabel.Text = Format.meters((model:GetAttribute("Distance") :: number?) or 0)
		bonesLabel.Text = ((model:GetAttribute("Bones") :: number?) or 0) .. " BONES"
		smashedLabel.Text = ((model:GetAttribute("Smashed") :: number?) or 0) .. " SMASHED"
	end
	table.insert(dummyConnections, model.AttributeChanged:Connect(update))
	update()
	counters.Visible = true
end

-- Cette méthode permet d'afficher les gains d'un lancer pendant RESULT_TIME lorsque le serveur envoie le résultat.
function Hud.showResult(result: Economy.Payout)
	resultToken += 1
	local token = resultToken
	resultTotal.Text = "+" .. Format.money(result.total)
	local lines = {
		string.format("%s  →  %s", Format.meters(result.distance), Format.money(result.distanceMoney)),
		string.format("%d bones broken  →  %s", result.bones, Format.money(result.bonesMoney)),
		string.format("%d objects smashed  →  %s", result.smashed, Format.money(result.smashMoney)),
	}
	if result.multiplier ~= 1 then
		table.insert(lines, string.format('<font color="#FFD23C">Multiplier ×%.2f</font>', result.multiplier))
	end
	resultDetail.Text = table.concat(lines, "\n")
	resultPerfect.Visible = result.perfect
	resultFrame.Visible = true
	resultScale.Scale = 0.6
	TweenService:Create(resultScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(GameConfig.RESULT_TIME, function()
		if token == resultToken then
			resultFrame.Visible = false
		end
	end)
end

-- Cette méthode permet de construire le HUD et de le brancher sur les attributs du joueur lorsque le client démarre ;
-- `onBuy` reçoit "Power" ou "Value" quand le joueur clique sur une amélioration.
function Hud.init(localPlayer: Player, onBuy: (string) -> ())
	player = localPlayer
	gui = create("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	bindScale(create("UIScale", { Parent = gui }))

	local moneyFrame = create("Frame", {
		Name = "Money",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(280, 60),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	round(moneyFrame, 16)
	moneyLabel = text({ Size = UDim2.fromScale(1, 1), TextSize = 42, TextColor3 = GOLD, Parent = moneyFrame })

	buildCounters(gui)
	buildUpgrades(gui, onBuy)
	buildGauge(gui)
	buildResult(gui)

	for _, attribute in { "Money", "PowerLevel", "ValueLevel" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshEconomy)
	end
	player:GetAttributeChangedSignal("LaneState"):Connect(refreshState)
	refreshEconomy()
	refreshState()
end

return Hud
