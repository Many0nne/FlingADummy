-- Écran de vol : bandes noires de cinéma, compteurs en direct (distance, os, objets), bannière de la zone traversée
-- (nom et multiplicateur) et panneau radio du mannequin (membres colorés selon leur gravité).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Damage = require(Shared:WaitForChild("Damage"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local Zones = require(Shared:WaitForChild("Zones"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local XRAY_SCALE = 32 -- pixels par stud du mannequin
local XRAY_TOP = 2.85 -- haut de la tête (studs)
local BONE_COLOR = Color3.fromRGB(190, 230, 255)

local FlightView = {}

local root: Frame
local bars: { Frame } = {}
local distanceLabel: TextLabel
local bonesLabel: TextLabel
local smashedLabel: TextLabel
local zoneBanner: Frame
local zoneLabel: TextLabel
local xray: Frame
local xrayLimbs: { [string]: Frame } = {}
local xrayCount: TextLabel
local connections: { RBXScriptConnection } = {}
local currentZone = 1

-- Cette méthode permet de construire le panneau radio (silhouette du mannequin) en bas à droite lorsque l'écran de
-- vol est construit.
local function buildXray(parent: Instance)
	xray = UIKit.create("Frame", {
		Name = "XRay",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -110),
		Size = UDim2.fromOffset(170, 300),
		BackgroundColor3 = Color3.fromRGB(18, 38, 66),
		BackgroundTransparency = 0.1,
		Parent = parent,
	})
	UIKit.corner(xray, 16)
	UIKit.outline(xray, 3, Color3.fromRGB(120, 200, 255))
	UIKit.text({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "X-RAY",
		TextSize = 24,
		TextColor3 = Color3.fromRGB(150, 220, 255),
		Parent = xray,
	})
	local body = UIKit.create("Frame", {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 230),
		BackgroundTransparency = 1,
		Parent = xray,
	})
	for _, piece in DummyShape.PIECES do
		local limb = UIKit.create("Frame", {
			Name = piece.name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, piece.position.X * XRAY_SCALE, 0, (XRAY_TOP - piece.position.Y) * XRAY_SCALE + 4),
			Size = UDim2.fromOffset(piece.size.X * XRAY_SCALE - 2, piece.size.Y * XRAY_SCALE - 2),
			BackgroundColor3 = BONE_COLOR,
			BackgroundTransparency = 0.35,
			Parent = body,
		})
		UIKit.corner(limb, 5)
		xrayLimbs[piece.name] = limb
	end
	xrayCount = UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 28,
		TextColor3 = C.bone,
		Parent = xray,
	})
end

-- Cette méthode permet de construire les bandes noires, les compteurs et la bannière de zone lorsque le client démarre.
local function build(gui: ScreenGui)
	root = UIKit.create("Frame", {
		Name = "Flight",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	for index, anchor in { 0, 1 } do
		bars[index] = UIKit.create("Frame", {
			AnchorPoint = Vector2.new(0, anchor),
			Position = UDim2.fromScale(0, anchor),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = root,
		})
	end
	distanceLabel = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(500, 80),
		TextSize = 80,
		StrokeThickness = 5,
		Parent = root,
	})
	zoneBanner = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 156),
		Size = UDim2.fromOffset(380, 46),
		BackgroundColor3 = Zones.LIST[1].color,
		Parent = root,
	})
	UIKit.corner(zoneBanner, 23)
	UIKit.outline(zoneBanner, 3)
	zoneLabel = UIKit.text({ Size = UDim2.fromScale(1, 1), TextSize = 28, Parent = zoneBanner })
	local stats = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 210),
		Size = UDim2.fromOffset(500, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 30),
		Parent = stats,
	})
	bonesLabel = UIKit.text({ Size = UDim2.fromOffset(220, 40), TextSize = 32, TextColor3 = C.bone, Parent = stats })
	smashedLabel = UIKit.text({ Size = UDim2.fromOffset(220, 40), TextSize = 32, TextColor3 = C.smash, Parent = stats })
	buildXray(root)
end

-- Cette méthode permet d'afficher la zone atteinte (nom, multiplicateur, couleur) lorsque le mannequin en franchit
-- une nouvelle.
local function showZone(index: number)
	local zone = Zones.LIST[index]
	zoneBanner.BackgroundColor3 = zone.color
	zoneLabel.Text = string.format("%s  x%s", string.upper(zone.name), zone.multiplier)
	if index > currentZone then
		UIKit.pop(zoneBanner, 1.5)
		UIKit.playSound("LevelUp", 1.4)
	end
	currentZone = index
end

-- Cette méthode permet de colorer un membre de la radio selon ses os cassés lorsque le serveur met à jour le membre.
local function paintLimb(name: string, bones: number)
	local limb = xrayLimbs[name]
	if not limb then
		return
	end
	if bones <= 0 then
		limb.BackgroundColor3 = BONE_COLOR
		limb.BackgroundTransparency = 0.35
	else
		limb.BackgroundColor3 = Damage.TINTS[math.min(bones, #Damage.TINTS)]
		limb.BackgroundTransparency = 0
		UIKit.pop(limb, 1.4)
	end
end

-- Cette méthode permet d'afficher l'écran de vol et de le brancher sur le mannequin lancé lorsque le serveur annonce
-- le lancer.
function FlightView.show(model: Model)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	currentZone = 1
	local function update()
		distanceLabel.Text = Format.meters((model:GetAttribute("Distance") :: number?) or 0)
		local bones = (model:GetAttribute("Bones") :: number?) or 0
		bonesLabel.Text = "🦴 " .. bones .. " BONES"
		smashedLabel.Text = "💥 " .. ((model:GetAttribute("Smashed") :: number?) or 0) .. " SMASHED"
		xrayCount.Text = bones .. " BONES"
		local zone = (model:GetAttribute("Zone") :: number?) or 1
		if zone ~= currentZone then
			showZone(zone)
		end
	end
	table.insert(connections, model.AttributeChanged:Connect(update))
	for name in xrayLimbs do
		local limb = model:FindFirstChild(name)
		paintLimb(name, 0)
		if limb then
			table.insert(
				connections,
				limb:GetAttributeChangedSignal("Bones"):Connect(function()
					paintLimb(name, (limb:GetAttribute("Bones") :: number?) or 0)
				end)
			)
		end
	end
	showZone(1)
	update()
	root.Visible = true
	for _, bar in bars do
		bar.Size = UDim2.fromScale(1, 0)
		TweenService:Create(bar, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 0.09) }):Play()
	end
end

-- Cette méthode permet de garder seulement le panneau radio (pour le résultat) lorsque le mannequin s'arrête.
function FlightView.settle()
	for _, bar in bars do
		TweenService:Create(bar, TweenInfo.new(0.3), { Size = UDim2.fromScale(1, 0) }):Play()
	end
	distanceLabel.Visible = false
	zoneBanner.Visible = false
	bonesLabel.Visible = false
	smashedLabel.Visible = false
end

-- Cette méthode permet de masquer l'écran de vol lorsque le couloir redevient prêt.
function FlightView.hide()
	root.Visible = false
	distanceLabel.Visible = true
	zoneBanner.Visible = true
	bonesLabel.Visible = true
	smashedLabel.Visible = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

-- Cette méthode permet de construire l'écran de vol dans le ScreenGui du jeu lorsque le client démarre.
function FlightView.init(gui: ScreenGui)
	build(gui)
end

return FlightView
