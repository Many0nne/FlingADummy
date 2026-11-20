-- Cérémonie de résultat : titre selon la violence du crash, lignes de gains qui tombent une à une, total qui grimpe,
-- phrase de blessure et cause, badge de record. Dure un peu moins que RESULT_TIME.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Zones = require(Shared:WaitForChild("Zones"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local LINE_DELAY = 0.4
local COUNT_TIME = 0.8

-- Titre selon le score de crash (os + objets / 2), du plus faible au plus fort
local TITLES = {
	{ score = 0, text = "OUCH!", color = Color3.fromRGB(255, 255, 255) },
	{ score = 4, text = "NICE CRASH!", color = Color3.fromRGB(120, 220, 255) },
	{ score = 10, text = "BRUTAL!", color = Color3.fromRGB(255, 170, 60) },
	{ score = 18, text = "DEVASTATING!", color = Color3.fromRGB(255, 90, 60) },
	{ score = 28, text = "CATASTROPHIC!", color = Color3.fromRGB(230, 60, 255) },
}

local ResultScreen = {}

local panel: Frame
local titleLabel: TextLabel
local linesFrame: Frame
local totalLabel: TextLabel
local injuryLabel: TextLabel
local recordBadge: TextLabel
local token = 0

-- Cette méthode permet de choisir le titre du résultat lorsque l'on connaît le nombre d'os et d'objets.
local function titleFor(bones: number, smashed: number)
	local score = bones + smashed / 2
	local chosen = TITLES[1]
	for _, entry in TITLES do
		if score >= entry.score then
			chosen = entry
		end
	end
	return chosen
end

-- Cette méthode permet de construire le panneau de résultat au centre de l'écran lorsque le client démarre.
local function build(gui: ScreenGui)
	panel = UIKit.create("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(560, 420),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = gui,
	})
	UIKit.corner(panel, 20)
	UIKit.outline(panel, 4)
	titleLabel = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(560, 70),
		TextSize = 64,
		StrokeThickness = 5,
		Rotation = -3,
		Parent = panel,
	})
	recordBadge = UIKit.text({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 30, 0, 52),
		Size = UDim2.fromOffset(220, 40),
		Text = "NEW RECORD!",
		TextSize = 32,
		TextColor3 = C.gold,
		Rotation = 8,
		Parent = panel,
	})
	linesFrame = UIKit.create("Frame", {
		Position = UDim2.fromOffset(30, 46),
		Size = UDim2.new(1, -60, 0, 190),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.create(
		"UIListLayout",
		{ Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = linesFrame }
	)
	totalLabel = UIKit.text({
		Position = UDim2.fromOffset(0, 240),
		Size = UDim2.new(1, 0, 0, 74),
		TextSize = 72,
		TextColor3 = C.green,
		StrokeThickness = 5,
		Parent = panel,
	})
	injuryLabel = UIKit.text({
		Position = UDim2.fromOffset(20, 320),
		Size = UDim2.new(1, -40, 0, 84),
		TextSize = 24,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(255, 210, 200),
		Parent = panel,
	})
end

-- Cette méthode permet d'ajouter une ligne de gain (libellé à gauche, montant à droite) qui rebondit lorsque la
-- cérémonie avance.
local function addLine(order: number, left: string, right: string, color: Color3)
	local row = UIKit.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = linesFrame,
	})
	UIKit.text({
		Size = UDim2.fromScale(0.65, 1),
		Text = left,
		TextSize = 28,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.35, 1),
		Text = right,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	UIKit.pop(row, 1.4)
	UIKit.playSound("Click", 1 + order * 0.08)
end

-- Cette méthode permet de faire grimper le total affiché jusqu'au gain lorsque toutes les lignes sont tombées.
local function countUp(total: number, current: number)
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if current ~= token then
			connection:Disconnect()
			return
		end
		local k = math.clamp((os.clock() - start) / COUNT_TIME, 0, 1)
		totalLabel.Text = "+" .. Format.money(total * (1 - (1 - k) ^ 3))
		if k >= 1 then
			connection:Disconnect()
			UIKit.pop(totalLabel, 1.4)
		end
	end)
end

-- Cette méthode permet de jouer la cérémonie de résultat lorsque le serveur envoie les gains du lancer.
function ResultScreen.show(result: any)
	token += 1
	local current = token
	for _, child in linesFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local title = titleFor(result.bones or 0, result.smashed or 0)
	titleLabel.Text = title.text
	titleLabel.TextColor3 = title.color
	recordBadge.Visible = result.record == true
	totalLabel.Text = ""
	injuryLabel.Text = ""
	panel.Visible = true
	UIKit.pop(panel, 0.5)
	UIKit.pop(titleLabel, 2)

	local lines = {
		{ Format.meters(result.distance or 0), Format.money(result.distanceMoney or 0), C.white },
		{ "🦴 " .. (result.bones or 0) .. " bones", Format.money(result.bonesMoney or 0), C.bone },
		{ "💥 " .. (result.smashed or 0) .. " smashed", Format.money(result.smashMoney or 0), C.smash },
	}
	local zone = Zones.LIST[result.zone or 1]
	if zone and zone.multiplier ~= 1 then
		table.insert(lines, { string.upper(zone.name), "x" .. zone.multiplier, zone.color })
	end
	if result.valueMultiplier and result.valueMultiplier ~= 1 then
		table.insert(lines, { "Dummy value", string.format("x%.2f", result.valueMultiplier), C.green })
	end
	task.spawn(function()
		for order, line in lines do
			task.wait(LINE_DELAY)
			if current ~= token then
				return
			end
			addLine(order, line[1], line[2], line[3])
		end
		task.wait(LINE_DELAY)
		if current ~= token then
			return
		end
		UIKit.playSound("Cash")
		countUp(result.total or 0, current)
		local injury = result.injuries or ""
		if result.cause then
			injury = injury .. "\n<i>" .. result.cause .. "</i>"
		end
		injuryLabel.Text = injury
	end)
end

-- Cette méthode permet de masquer le panneau de résultat lorsque le couloir redevient prêt.
function ResultScreen.hide()
	token += 1
	panel.Visible = false
end

-- Cette méthode permet de construire le panneau de résultat dans le ScreenGui du jeu lorsque le client démarre.
function ResultScreen.init(gui: ScreenGui)
	build(gui)
end

return ResultScreen
