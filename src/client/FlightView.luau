-- Écran de vol : bandes noires de cinéma, bannière CHANCE (« 1.36X », qui monte avec la distance et les crashs ; badge
-- du multiplicateur du mannequin à lancer, « RUBBER 1.25x ») et zone traversée, compteurs en direct (distance, os, objets) et panneau radio du mannequin (membres colorés selon leur gravité).
-- À l'arrêt du mannequin (détecté ici, sans attendre le serveur) : trèfle et CHANCE finale « X1.36 » au-dessus de lui,
-- titre du crash dessous (« BRUTAL! »), comme le « X1.22 » de 09 ; la radio reste quelques secondes dans son coin avec
-- le bilan (os, objets, blessures, cause) pendant que le tirage (Client.Prize) enchaîne.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrashTitle = require(Shared:WaitForChild("CrashTitle"))
local Damage = require(Shared:WaitForChild("Damage"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local UIMotion = require(Shared:WaitForChild("UIMotion"))
local Zones = require(Shared:WaitForChild("Zones"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local XRAY_SCALE = 32 -- pixels par stud du mannequin
local XRAY_TOP = 2.85 -- haut de la tête (studs)
local BONE_COLOR = Color3.fromRGB(190, 230, 255)
local LAUNCH_GRACE = 0.5 -- s après le lancer pendant lesquels on ne cherche pas l'arrêt
local REST_CONFIRM = 0.15 -- s sous REST_SPEED avant d'afficher la CHANCE finale (évite le sommet d'un rebond)
local RESUME_CONFIRM = 0.4 -- s au-dessus de REST_SPEED avant de reprendre le vol (pas de clignotement sur une glissade)
local TAG_MIN = 0.9 -- s minimum de « X1.36 » à l'écran avant le tirage
local REPORT_TIME = 3 -- s de radio et bilan après le comptage (dans leur coin pendant le suspense du tirage)
local TAG_OFFSET = 4.5 -- studs au-dessus du torse

local FlightView = {}

local root: Frame
local bars: { Frame } = {}
local distanceLabel: TextLabel
local bonesLabel: TextLabel
local smashedLabel: TextLabel
local chanceBox: Frame
local chanceLabel: TextLabel
local luckBadge: Frame
local luckLabel: TextLabel
local zoneBanner: Frame
local zoneLabel: TextLabel
local xray: Frame
local xrayLimbs: { [string]: Frame } = {}
local xrayCount: TextLabel
local report: Frame
local reportStats: TextLabel
local reportInjury: TextLabel
local tag: BillboardGui
local tagBody: Frame
local tagChance: TextLabel
local tagTitle: TextLabel
local tagRecord: TextLabel
local connections: { RBXScriptConnection } = {}
local currentZone = 1
local flightModel: Model? = nil
local token = 0
local restSince: number? = nil -- os.clock() du début de l'arrêt en cours
local moveSince: number? = nil -- os.clock() depuis lequel le mannequin « arrêté » bouge de nouveau
local landedAt: number? = nil -- os.clock() de l'affichage de la CHANCE finale
local stoppedAt: number? = nil -- os.clock() de l'arrêt du mannequin (début de l'immobilité)
local settled = false -- résultat du serveur reçu : l'arrêt est définitif
local stopEstimated = false -- arrêt pas vu par le client, instant estimé (mesure approximative)

-- Cette méthode permet de construire le panneau radio (silhouette du mannequin) en bas à droite et le bilan à sa
-- gauche lorsque l'écran de vol est construit.
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
	-- Bilan de fin de vol, collé à gauche de la radio (même habillage)
	report = UIKit.create("Frame", {
		Name = "Report",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -196, 1, -110),
		Size = UDim2.fromOffset(300, 150),
		BackgroundColor3 = Color3.fromRGB(18, 38, 66),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = parent,
	})
	UIKit.corner(report, 16)
	UIKit.outline(report, 3, Color3.fromRGB(120, 200, 255))
	reportStats = UIKit.text({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 34),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = report,
	})
	reportInjury = UIKit.text({
		Position = UDim2.fromOffset(12, 44),
		Size = UDim2.new(1, -24, 1, -52),
		TextSize = 20,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(255, 210, 200),
		Parent = report,
	})
end

-- Cette méthode permet de construire l'étiquette « 🍀 X1.36 » + titre du crash, ancrée au-dessus du mannequin
-- arrêté, au style de la bannière CHANCE (même police, même vert), lorsque le client démarre.
local function buildTag(screen: ScreenGui)
	tag = UIKit.create("BillboardGui", {
		Name = "LandingChance",
		Size = UDim2.fromOffset(340, 170),
		StudsOffsetWorldSpace = Vector3.new(0, TAG_OFFSET, 0),
		AlwaysOnTop = true,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = screen.Parent,
	})
	tagBody = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = tag,
	})
	tagRecord = UIKit.text({
		Size = UDim2.new(1, 0, 0, 36),
		Text = "NEW RECORD!",
		TextSize = 32,
		TextColor3 = C.gold,
		Rotation = 4,
		Visible = false,
		Parent = tagBody,
	})
	tagChance = UIKit.text({
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 80),
		TextSize = 72,
		StrokeThickness = 4,
		Parent = tagBody,
	})
	UIKit.gradientText(tagChance, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 255, 140))
	tagTitle = UIKit.text({
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 44),
		TextSize = 38,
		StrokeThickness = 3,
		Rotation = -3,
		Parent = tagBody,
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
	-- Bannière CHANCE des références (« 1.36X / CHANCE / Prairie ») : gros multiplicateur qui monte, zone dessous
	chanceBox = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(240, 96),
		BackgroundColor3 = Color3.fromRGB(255, 230, 120),
		BackgroundTransparency = 0.15,
		Parent = root,
	})
	UIKit.corner(chanceBox, 14)
	UIKit.outline(chanceBox, 3)
	UIKit.shade(chanceBox, Color3.fromRGB(255, 245, 190), Color3.fromRGB(240, 190, 60))
	chanceLabel = UIKit.text({
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.new(1, 0, 0, 64),
		TextSize = 62,
		StrokeThickness = 4,
		Parent = chanceBox,
	})
	UIKit.gradientText(chanceLabel, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 255, 140))
	UIKit.text({
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "CHANCE",
		TextSize = 24,
		Parent = chanceBox,
	})
	-- Badge du mannequin à lancer, collé en biais au coin de la bannière (multiplicateur compris dans la CHANCE)
	luckBadge = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, -18, 0, 6),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Rotation = 8,
		BackgroundColor3 = C.green,
		Visible = false,
		ZIndex = 3,
		Parent = chanceBox,
	})
	UIKit.corner(luckBadge, 15)
	UIKit.outline(luckBadge, 3)
	UIKit.create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = luckBadge })
	luckLabel = UIKit.text({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 20,
		ZIndex = 4,
		Parent = luckBadge,
	})
	zoneBanner = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 156),
		Size = UDim2.fromOffset(260, 42),
		BackgroundColor3 = Zones.LIST[1].color,
		Parent = root,
	})
	UIKit.corner(zoneBanner, 21)
	UIKit.outline(zoneBanner, 3)
	-- Texte réduit seulement s'il ne tient pas (« HAUNTED CASTLE », #97) ; 28 px pour les autres noms
	zoneLabel = UIKit.text({
		Size = UDim2.new(1, -20, 1, -4),
		Position = UDim2.fromOffset(10, 2),
		TextScaled = true,
		Parent = zoneBanner,
	})
	UIKit.create("UITextSizeConstraint", { MaxTextSize = 28, Parent = zoneLabel })
	local stats = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 206),
		Size = UDim2.fromOffset(640, 40),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 24),
		Parent = stats,
	})
	distanceLabel = UIKit.text({ Size = UDim2.fromOffset(190, 40), TextSize = 32, Parent = stats })
	bonesLabel = UIKit.text({ Size = UDim2.fromOffset(190, 40), TextSize = 32, TextColor3 = C.bone, Parent = stats })
	smashedLabel = UIKit.text({ Size = UDim2.fromOffset(190, 40), TextSize = 32, TextColor3 = C.smash, Parent = stats })
	buildXray(root)
	buildTag(gui)
end

-- Cette méthode permet d'afficher la zone atteinte (nom, couleur) lorsque le mannequin en franchit une nouvelle.
local function showZone(index: number)
	local zone = Zones.LIST[index]
	zoneBanner.BackgroundColor3 = zone.color
	zoneLabel.Text = "🍀 " .. string.upper(zone.name)
	if index > currentZone then
		UIKit.pop(zoneBanner, 1.5)
		UIKit.pop(chanceBox, 1.25)
		UIKit.playSound("LevelUp", 1.4)
	end
	currentZone = index
end

-- Cette méthode permet d'afficher la CHANCE du lancer (« 1.36X ») lorsque le serveur la met à jour pendant le vol.
local function showChance(chance: number)
	chanceLabel.Text = string.format("%.2fX", chance)
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

-- Cette méthode permet de remplir l'étiquette (« 🍀 X1.36 », titre du crash) et la ligne de bilan (distance, os,
-- objets) lorsque le mannequin s'arrête ou que le résultat du serveur arrive.
local function fillLanding(chance: number, distance: number, bones: number, smashed: number)
	tagChance.Text = "🍀 " .. Format.multiplier(chance)
	local title = CrashTitle.titleFor(bones, smashed)
	tagTitle.Text = title.text
	UIKit.gradientText(tagTitle, title.color:Lerp(Color3.new(1, 1, 1), 0.6), title.color)
	reportStats.Text = Format.meters(distance) .. "   🦴 " .. bones .. "   💥 " .. smashed
end

-- Cette méthode permet de lire un attribut numérique du mannequin lancé lorsque l'étiquette ou le bilan se remplit ;
-- 0 sans mannequin.
local function attribute(name: string): number
	local model = flightModel
	return (model and (model:GetAttribute(name) :: number?)) or 0
end

-- Cette méthode permet de montrer ou ranger les bandes noires et les compteurs du vol lorsque le mannequin s'arrête
-- (`flying` faux) ou repart avant que le serveur ait compté le lancer.
local function showFlightHud(flying: boolean)
	for _, bar in bars do
		TweenService:Create(bar, TweenInfo.new(0.3), { Size = UDim2.fromScale(1, if flying then 0.09 else 0) }):Play()
	end
	distanceLabel.Visible = flying
	chanceBox.Visible = flying
	zoneBanner.Visible = flying
	bonesLabel.Visible = flying
	smashedLabel.Visible = flying
end

-- Cette méthode permet de passer en fin de vol (bandes et compteurs rangés, « X1.36 » au-dessus du mannequin, bilan
-- à côté de la radio) lorsque le mannequin vient de s'arrêter, ou que le résultat arrive sans arrêt détecté (vol
-- trop long, chute).
local function land()
	if landedAt then
		return
	end
	local now = os.clock()
	local stopped = stoppedAt or now
	landedAt = now
	stoppedAt = stopped
	local model = flightModel
	local torso = model and model:FindFirstChild("Torso")
	showFlightHud(false)
	fillLanding(attribute("Chance"), attribute("Distance"), attribute("Bones"), attribute("Smashed"))
	reportInjury.Text = ""
	tagRecord.Visible = false
	report.Visible = true
	UIKit.pop(report, 1.2)
	if torso and torso:IsA("BasePart") then
		tag.Adornee = torso
		tag.Enabled = true
		UIKit.playKeys(tagBody, UIMotion.POPUP_IN)
		UIKit.playSound("LevelUp", 1.3)
	end
	if RunService:IsStudio() then
		print(string.format("[Landing] arrêt t=%.3f, X affiché t=%.3f", stopped, now))
	end
end

-- Cette méthode permet de revenir à l'écran de vol lorsque le mannequin repart après un faux arrêt (calé un instant
-- contre un obstacle), tant que le serveur n'a pas compté le lancer.
local function resume()
	landedAt = nil
	stoppedAt = nil
	restSince = nil
	moveSince = nil
	FlightView.hideTag()
	report.Visible = false
	showFlightHud(true)
	if RunService:IsStudio() then
		print("[Landing] le mannequin repart, vol repris")
	end
end

-- Cette méthode permet de guetter l'arrêt du mannequin (torse sous REST_SPEED pendant REST_CONFIRM) à chaque frame
-- pendant le vol, pour afficher la CHANCE finale sans attendre la seconde d'arrêt du serveur ; s'il repart (au-dessus
-- de REST_SPEED pendant RESUME_CONFIRM, même seuil que le serveur) avant le résultat, le vol reprend. Attend que le
-- torse soit répliqué (2 s au plus).
local function watchRest(model: Model, launchedAt: number)
	local current = token
	task.spawn(function()
		local torso = model:WaitForChild("Torso", 2)
		if current ~= token or settled or not (torso and torso:IsA("BasePart")) then
			return
		end
		table.insert(
			connections,
			RunService.Heartbeat:Connect(function()
				if settled or not torso.Parent then
					return
				end
				local speed = torso.AssemblyLinearVelocity.Magnitude
				local now = os.clock()
				if landedAt then
					if speed < GameConfig.REST_SPEED then
						moveSince = nil
						return
					end
					moveSince = moveSince or now
					if now - (moveSince :: number) >= RESUME_CONFIRM then
						resume()
					end
					return
				end
				if now - launchedAt < LAUNCH_GRACE or speed >= GameConfig.REST_SPEED then
					restSince = nil
					return
				end
				restSince = restSince or now
				if now - (restSince :: number) >= REST_CONFIRM then
					stoppedAt = restSince
					land()
				end
			end)
		)
	end)
end

-- Cette méthode permet d'afficher l'écran de vol et de le brancher sur le mannequin lancé lorsque le serveur annonce
-- le lancer.
function FlightView.show(model: Model)
	FlightView.hide()
	flightModel = model
	currentZone = 1
	local function update()
		distanceLabel.Text = Format.meters((model:GetAttribute("Distance") :: number?) or 0)
		local bones = (model:GetAttribute("Bones") :: number?) or 0
		bonesLabel.Text = "🦴 " .. bones .. " BONES"
		smashedLabel.Text = "💥 " .. ((model:GetAttribute("Smashed") :: number?) or 0) .. " SMASHED"
		xrayCount.Text = bones .. " BONES"
		showChance((model:GetAttribute("Chance") :: number?) or 1)
		local zone = (model:GetAttribute("Zone") :: number?) or 1
		if zone ~= currentZone then
			showZone(zone)
		end
		if landedAt and not settled then
			fillLanding(attribute("Chance"), attribute("Distance"), bones, attribute("Smashed"))
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
	-- Multiplicateur du mannequin lancé (boutique, #14), déjà compté dans la CHANCE affichée
	local luck = (model:GetAttribute("Luck") :: number?) or 1
	local thrown = model:GetAttribute("Thrown")
	luckBadge.Visible = luck > 1
	if luck > 1 then
		local short = if typeof(thrown) == "string" then string.upper((string.gsub(thrown, " Dummy$", ""))) else ""
		luckLabel.Text = string.format("%s %s", short, Format.luck(luck))
	end
	showZone(1)
	update()
	watchRest(model, os.clock())
	root.Visible = true
	for _, bar in bars do
		bar.Size = UDim2.fromScale(1, 0)
		TweenService:Create(bar, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 0.09) }):Play()
	end
end

-- Cette méthode permet de figer l'étiquette et le bilan sur le résultat du serveur (CHANCE comptée, blessures, cause)
-- lorsqu'il arrive, et de donner le délai (s) avant le tirage pour que « X1.36 » reste au moins TAG_MIN à l'écran.
function FlightView.settle(result: any): number
	if not landedAt then
		-- Arrêt pas vu par le client (latence, chute, vol trop long) : estimé REST_TIME avant le comptage du serveur
		stoppedAt = os.clock() - GameConfig.REST_TIME
		stopEstimated = true
	end
	land()
	settled = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	fillLanding(result.total or 1, result.distance or 0, result.bones or 0, result.smashed or 0)
	tagRecord.Visible = result.record == true
	if result.record == true then
		UIKit.pop(tagRecord, 1.8)
	end
	local injury = result.injuries or ""
	if result.cause then
		injury = injury .. (if injury ~= "" then "\n" else "") .. "<i>" .. result.cause .. "</i>"
	end
	if result.record == true then
		injury = '<font color="#'
			.. C.gold:ToHex()
			.. '">NEW RECORD!</font>'
			.. (if injury ~= "" then "\n" else "")
			.. injury
	end
	reportInjury.Text = injury
	local current = token
	task.delay(REPORT_TIME, function()
		if current == token then
			xray.Visible = false
			report.Visible = false
		end
	end)
	if not tag.Enabled then
		return 0
	end
	return math.max(0, TAG_MIN - (os.clock() - (landedAt :: number)))
end

-- Cette méthode permet de donner l'instant (os.clock) de l'arrêt du mannequin lorsque l'on mesure le délai jusqu'au
-- tirage ; nil avant l'arrêt, et vrai en second si l'instant est estimé (arrêt pas vu par le client).
function FlightView.stoppedAt(): (number?, boolean)
	return stoppedAt, stopEstimated
end

-- Cette méthode permet de retirer l'étiquette « X1.36 » lorsque la silhouette du tirage apparaît.
function FlightView.hideTag()
	tag.Enabled = false
	(tag :: any).Adornee = nil
end

-- Cette méthode permet de masquer l'écran de vol, l'étiquette et le bilan lorsque le couloir redevient prêt ou qu'un
-- nouveau vol commence.
function FlightView.hide()
	token += 1
	flightModel = nil
	restSince = nil
	moveSince = nil
	landedAt = nil
	stoppedAt = nil
	settled = false
	stopEstimated = false
	FlightView.hideTag()
	root.Visible = false
	distanceLabel.Visible = true
	chanceBox.Visible = true
	zoneBanner.Visible = true
	bonesLabel.Visible = true
	smashedLabel.Visible = true
	xray.Visible = true
	report.Visible = false
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
