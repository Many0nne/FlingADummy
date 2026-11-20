-- HUD permanent au style des jeux de référence : boutons à icône (Index et Shop à gauche, Dummies à droite, pastille
-- « ! »), compteurs icône + valeur en bas à gauche (Throw Power, argent et revenu « +$N/s »), fenêtres à bandeau et
-- cartes d'objets (équipements d'entraînement, mannequins, index), barre d'entraînement avec STOP, « +1 EXP » qui
-- s'envole à chaque répétition, popups LEVEL UP! (Throw Power gagnée au niveau) / NEW EQUIPMENT!.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Training = require(Shared:WaitForChild("Training"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local BUTTON_SIZE = 92 -- côté des boutons à icône à 720 px de haut (≈ 0,13 h, comme les références)
local INDEX_SLOTS = 8 -- cases de l'index en attendant la collection (#13)

local Hud = {}

local player: Player
local gui: ScreenGui
local root: Frame -- tout le HUD permanent, masqué pendant le vol
local powerLabel: TextLabel
local moneyLabel: TextLabel
local anchors: { [string]: GuiObject } = {} -- éléments que l'objectif peut désigner
local badges: { [string]: Frame } = {}
local windows: { [string]: Frame } = {}
local gearCards: { UIKit.Card } = {}
local dummyCard: UIKit.Card
local lockedViewports: { ViewportFrame } = {} -- mannequins à venir (#14), en silhouette
local modelsMeshed: boolean? = nil -- forme (maillée ou blocs) des rendus 3D des cartes déjà construits
local trainBar: Frame
local trainLevel: TextLabel
local trainFill: Frame
local trainCount: TextLabel
local lastPower = 0
local levelGain = 0 -- Throw Power versée au dernier niveau d'entraînement, pas encore annoncée
local levelUpPending = false -- niveau arrivé avant sa Throw Power (ordre de réplication non garanti)
local LEVEL_GAIN_WAIT = 0.5 -- attente maximale de la Throw Power d'un niveau avant de l'annoncer quand même (s)
local knownLevel = math.huge -- palier d'entraînement et équipement déjà annoncés (aucun avant le chargement)
local knownTier = math.huge
local popupEndsAt = 0

-- Cette méthode permet de lire un attribut numérique du joueur (valeur par défaut si absent) lorsque le HUD se
-- rafraîchit.
local function stat(name: string, default: number): number
	return (player:GetAttribute(name) :: number?) or default
end

-- Cette méthode permet d'ouvrir une fenêtre (et de fermer les autres) ou de la refermer lorsque le joueur clique sur
-- son bouton ; aucune ne s'ouvre pendant la jauge (elle la couvrirait et capterait le clic de lancer).
local function toggle(name: string)
	local target = windows[name]
	local open = not target.Visible and player:GetAttribute("Action") ~= "Holding"
	for _, window in windows do
		window.Visible = false
	end
	target.Visible = open
	if open then
		UIKit.pop(target, 0.7)
		Hud.refresh()
	end
end

-- Cette méthode permet de créer une ligne de compteur (icône dessinée + valeur à contour) en bas à gauche lorsque le
-- HUD est construit.
local function counter(parent: Instance, order: number, icon: string, color: Color3): TextLabel
	local row = UIKit.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(300, 40),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.icon(icon, { Size = UDim2.fromOffset(40, 40), Parent = row })
	return UIKit.text({
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 32,
		TextColor3 = color,
		Parent = row,
	})
end

-- Cette méthode permet de construire les deux compteurs (puissance, argent et revenu) en bas à gauche lorsque le HUD
-- est construit.
local function buildCounters()
	local counters = UIKit.create("Frame", {
		Name = "Counters",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -14),
		Size = UDim2.fromOffset(320, 88),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Parent = counters,
	})
	powerLabel = counter(counters, 1, "power", C.cyan)
	moneyLabel = counter(counters, 2, "cash", C.white)
end

-- Cette méthode permet de construire les boutons à icône (Index et Shop à gauche, Dummies à droite, comme Index /
-- Boutique / Animaux des références) lorsque le HUD est construit.
local function buildButtons()
	local left = UIKit.create("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE * 2 + 22),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 22),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = left,
	})
	anchors.Index = UIKit.iconButton("index", "Index", BUTTON_SIZE, { LayoutOrder = 1, Parent = left }, function()
		toggle("Index")
	end)
	anchors.Shop = UIKit.iconButton("shop", "Shop", BUTTON_SIZE, { LayoutOrder = 2, Parent = left }, function()
		toggle("Shop")
	end)
	anchors.Dummies = UIKit.iconButton("dummies", "Dummies", BUTTON_SIZE, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Parent = root,
	}, function()
		toggle("Dummies")
	end)
	badges.Shop = UIKit.badge(anchors.Shop)
	badges.Dummies = UIKit.badge(anchors.Dummies)
end

-- Cette méthode permet de créer une rangée défilante de cartes dans le corps d'une fenêtre lorsque la fenêtre est
-- construite.
local function cardRow(body: Frame): ScrollingFrame
	local row = UIKit.create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.white,
		ZIndex = 11,
		Parent = body,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = row,
	})
	UIKit.create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = row,
	})
	return row
end

-- Cette méthode permet de construire les fenêtres (équipements d'entraînement, mannequins, index) lorsque le HUD est
-- construit.
local function buildWindows()
	local size = Vector2.new(680, 440) -- ≈ 0,6 h de haut à 720 px, 3 cartes visibles (référence 01)
	local shop = UIKit.window(gui, {
		name = "Shop",
		title = "Training Gear",
		icon = "shop",
		colors = { Color3.fromRGB(150, 60, 230), Color3.fromRGB(255, 70, 170) },
		size = size,
	}, function()
		windows.Shop.Visible = false
	end)
	windows.Shop = shop.frame
	local gearRow = cardRow(shop.body)
	for tier in Training.GEARS do
		gearCards[tier] = UIKit.card(gearRow, tier, function()
			if tier == stat("GearTier", 1) + 1 then
				Hud.onBuy("Gear")
			end
		end)
	end

	local dummies = UIKit.window(gui, {
		name = "Dummies",
		title = "Dummies",
		icon = "dummies",
		colors = { Color3.fromRGB(255, 150, 20), Color3.fromRGB(255, 215, 50) },
		size = size,
	}, function()
		windows.Dummies.Visible = false
	end)
	windows.Dummies = dummies.frame
	local dummyRow = cardRow(dummies.body)
	dummyCard = UIKit.card(dummyRow, 1, function()
		Hud.onBuy("Value")
	end)
	for order = 2, 3 do
		local locked = UIKit.card(dummyRow, order, function() end)
		locked.title.Text = "???"
		locked.rarity.Text = "Coming soon"
		locked.stat.Text = "???"
		locked.action.Text = "LOCKED"
		locked.action.BackgroundColor3 = C.equipped
		locked.action:SetAttribute("Disabled", true)
		locked.viewport.ImageColor3 = Color3.new(0, 0, 0)
		table.insert(lockedViewports, locked.viewport)
	end

	local index = UIKit.window(gui, {
		name = "Index",
		title = "Index",
		icon = "index",
		colors = { Color3.fromRGB(40, 110, 255), Color3.fromRGB(60, 210, 255) },
		size = size,
	}, function()
		windows.Index.Visible = false
	end)
	windows.Index = index.frame
	UIKit.text({
		Size = UDim2.new(1, 0, 0, 26),
		Text = "Throw your dummy to discover new ones!",
		TextSize = 22,
		ZIndex = 12,
		Parent = index.body,
	})
	local grid = UIKit.create("Frame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = index.body,
	})
	UIKit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(128, 116),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for slot = 1, INDEX_SLOTS do
		local cell = UIKit.create("Frame", {
			LayoutOrder = slot,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 12,
			Parent = grid,
		})
		UIKit.corner(cell, 10)
		UIKit.outline(cell, 3)
		UIKit.shade(cell, Color3.fromRGB(236, 238, 244), Color3.fromRGB(176, 182, 194))
		UIKit.text({ Size = UDim2.fromScale(1, 1), Text = "?", TextSize = 56, ZIndex = 13, Parent = cell })
	end
end

-- Cette méthode permet de (re)construire les rendus 3D des cartes (mannequins soulevés, mannequin lancé) lorsque une
-- fenêtre s'ouvre pour la première fois ou que les maillages publiés viennent d'arriver.
local function buildModels()
	local meshed = DummyShape.isMeshed()
	if modelsMeshed == meshed then
		return
	end
	modelsMeshed = meshed
	for tier, card in gearCards do
		local gear = Training.GEARS[tier]
		-- Verre et champ de force ne se rendent pas en ViewportFrame : néon de la même couleur à la place
		local material = if gear.material == Enum.Material.Glass or gear.material == Enum.Material.ForceField
			then Enum.Material.Neon
			else gear.material
		UIKit.showModel(card.viewport, DummyShape.buildVisual(1, { color = gear.color, material = material }))
	end
	UIKit.showModel(dummyCard.viewport, DummyShape.buildVisual(1))
	for _, viewport in lockedViewports do
		UIKit.showModel(viewport, DummyShape.buildVisual(1))
	end
end

-- Cette méthode permet de reconstruire les rendus 3D d'une fenêtre ouverte lorsque les gabarits maillés du mannequin
-- arrivent (dossier créé puis marqué Ready par Server.DummyAssets).
local function watchTemplates()
	-- Cette méthode permet de rafraîchir les fenêtres lorsque le dossier des gabarits passe à Ready.
	local function watch(folder: Instance)
		folder:GetAttributeChangedSignal("Ready"):Connect(Hud.refresh)
	end
	local folder = ReplicatedStorage:FindFirstChild(DummyShape.TEMPLATES)
	if folder then
		watch(folder)
	else
		local connection
		connection = ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == DummyShape.TEMPLATES then
				connection:Disconnect()
				watch(child)
			end
		end)
	end
end

-- Cette méthode permet d'habiller le bouton d'action d'une carte (texte, couleur) lorsque la carte se rafraîchit ;
-- `enabled` à false le rend inerte (pas de son ni d'enfoncement : possédé, équipé, verrouillé, au maximum).
local function setAction(card: UIKit.Card, text: string, color: Color3, enabled: boolean)
	card.action.Text = text
	card.action.BackgroundColor3 = color
	card.action:SetAttribute("Disabled", not enabled)
end

-- Cette méthode permet de rafraîchir les cartes d'équipement (possédé, équipé, prix vert ou rouge) lorsque l'argent
-- ou l'équipement changent.
local function refreshGear(money: number)
	local owned = stat("GearTier", 1)
	for tier, card in gearCards do
		local gear = Training.GEARS[tier]
		local rarity = Rarity.get(tier)
		card.title.Text = (string.gsub(gear.name, " Dummy$", ""))
		card.rarity.Text = rarity.name
		card.rarity.TextColor3 = rarity.color
		-- Throw Power mise de côté à chaque répétition (versée au niveau), pas de l'EXP : cyan comme le compteur de puissance
		card.stat.Text = "+" .. Format.short(gear.gain) .. " Power / rep"
		card.stat.TextColor3 = C.cyan
		card.stat.TextSize = 20
		local stroke = card.frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = if tier == owned then C.green else C.ink
		stroke.Thickness = if tier == owned then 4 else 3
		if tier < owned then
			setAction(card, "OWNED", C.equipped, false)
		elseif tier == owned then
			setAction(card, "EQUIPPED", C.equipped, false)
		elseif tier == owned + 1 then
			setAction(card, Format.money(gear.cost), if money >= gear.cost then C.green else C.red, true)
		else
			setAction(card, "🔒 " .. Format.money(gear.cost), C.locked, false)
		end
	end
end

-- Cette méthode permet de rafraîchir la carte du mannequin lancé (valeur, prix de l'amélioration) lorsque l'argent
-- ou la valeur changent.
local function refreshDummy(money: number)
	local level = stat("ValueLevel", 1)
	local cost = Economy.valueCost(level)
	dummyCard.title.Text = "Crash Dummy"
	dummyCard.rarity.Text = "Lv " .. level
	dummyCard.rarity.TextColor3 = C.yellow
	dummyCard.stat.Text = string.format("Value x%.2f", Economy.valueMultiplier(level))
	if cost then
		setAction(dummyCard, "UPGRADE " .. Format.money(cost), if money >= cost then C.green else C.red, true)
	else
		setAction(dummyCard, "MAXED", C.equipped, false)
	end
end

-- Cette méthode permet de rafraîchir compteurs, cartes et pastilles « ! » lorsque l'argent, la puissance,
-- l'équipement, la valeur ou le revenu changent.
function Hud.refresh()
	local money = stat("Money", 0)
	-- Revenu collé au montant, en plus petit et en vert (comme « $64 +$1 » de la référence 02), seulement s'il existe
	local income = stat("Income", 0)
	moneyLabel.Text = Format.money(money)
		.. if income > 0
			then string.format(' <font size="22" color="#50D746">%s</font>', Format.perSecond(income))
			else ""
	powerLabel.Text = Format.short(stat("ThrowPower", GameConfig.START_POWER))

	local gearCost = Training.nextGearCost(stat("GearTier", 1))
	local valueCost = Economy.valueCost(stat("ValueLevel", 1))
	badges.Shop.Visible = gearCost ~= nil and money >= gearCost
	badges.Dummies.Visible = valueCost ~= nil and money >= valueCost
	if windows.Shop.Visible or windows.Dummies.Visible then
		buildModels()
		refreshGear(money)
		refreshDummy(money)
	end
end

-- Cette méthode permet de faire s'envoler « +1 EXP » au-dessus de la barre d'entraînement lorsque l'avatar termine une
-- répétition (la barre de niveau prend +1 en même temps, comme « +1 d'EXP » de la référence 01).
local function floatExp()
	local holder = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, math.random(-90, 90), 1, -130),
		Size = UDim2.fromOffset(150, 40),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local label = UIKit.text({
		Size = UDim2.fromScale(1, 1),
		Text = "+1 EXP",
		TextSize = 32,
		TextColor3 = C.cyan,
		Parent = holder,
	})
	TweenService:Create(holder, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = holder.Position - UDim2.fromOffset(0, 90),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.9), { Transparency = 1 }):Play()
	end
	task.delay(1, function()
		holder:Destroy()
	end)
end

-- Cette méthode permet de rafraîchir la barre d'entraînement (niveau, répétitions) lorsque la progression change.
local function refreshTraining()
	local level = stat("TrainLevel", 1)
	local reps = stat("TrainReps", 0)
	local needed = Training.repsForLevel(level)
	trainLevel.Text = "Level " .. level
	trainCount.Text = reps .. "/" .. needed
	TweenService:Create(trainFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(reps / needed, 1) }):Play()
end

-- Cette méthode permet d'afficher la barre d'entraînement et de masquer le HUD en vol lorsque l'action du joueur ou
-- l'état du couloir changent.
local function refreshState()
	local action = player:GetAttribute("Action")
	local state = player:GetAttribute("LaneState")
	trainBar.Visible = action == "Training"
	root.Visible = state ~= "Flying"
	if state == "Flying" or action == "Holding" then
		for _, window in windows do
			window.Visible = false
		end
	end
end

-- Cette méthode permet de construire la barre d'entraînement (piste vert foncé, remplissage bleu, niveau et
-- répétitions) et le bouton rouge STOP au-dessus, en bas au centre, lorsque le HUD est construit.
local function buildTrainBar(onStop: () -> ())
	trainBar = UIKit.create("Frame", {
		Name = "TrainBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(440, 96),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	anchors.Stop = UIKit.button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(140, 44),
		BackgroundColor3 = C.red,
		Text = "STOP",
		TextSize = 28,
		Parent = trainBar,
	}, onStop)
	local track = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Color3.fromRGB(46, 84, 52),
		Parent = trainBar,
	})
	UIKit.corner(track, 8)
	UIKit.outline(track, 3)
	trainFill = UIKit.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.blue,
		Parent = track,
	})
	UIKit.corner(trainFill, 8)
	UIKit.shade(trainFill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 170))
	trainLevel = UIKit.text({
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromScale(0.6, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 24,
		ZIndex = 2,
		Parent = track,
	})
	trainCount = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.fromScale(0.4, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 24,
		ZIndex = 2,
		Parent = track,
	})
end

-- Cette méthode permet d'afficher un popup de palier et de retenir sa fin (l'objectif se tait pendant ce temps)
-- lorsque le joueur gagne un niveau ou un équipement.
local function showPopup(title: string, subtitle: string, subtitleColor: Color3?)
	local duration = UIKit.popup(gui, title, subtitle, subtitleColor)
	popupEndsAt = os.clock() + duration
end

-- Cette méthode permet d'annoncer le niveau d'entraînement franchi (« LEVEL UP! », Throw Power versée) lorsque le
-- niveau et sa Throw Power sont arrivés, dans un ordre ou dans l'autre.
local function announceLevelUp()
	levelUpPending = false
	showPopup("LEVEL UP!", "Throw Power +" .. Format.short(levelGain), C.cyan)
	levelGain = 0
	UIKit.playSound("LevelUp")
end

-- Cette méthode permet d'adapter l'échelle du HUD à la taille de l'écran lorsque la fenêtre change (mobile compris).
local function bindScale(scale: UIScale)
	local camera = Workspace.CurrentCamera
	local function update()
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.5, 1.3)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
end

-- Cette méthode permet de donner le ScreenGui du jeu (créé par Hud.init) lorsqu'un autre module y ajoute ses éléments.
function Hud.screen(): ScreenGui
	return gui
end

-- Cette méthode permet de donner l'élément du HUD que l'objectif désigne (« Shop », « Dummies ») lorsque la
-- flèche d'interface se place ; nil s'il n'existe pas.
function Hud.anchor(name: string): GuiObject?
	return anchors[name]
end

-- Cette méthode permet de savoir si un popup de palier occupe le haut de l'écran lorsque l'objectif s'affiche.
function Hud.isPopupShown(): boolean
	return os.clock() < popupEndsAt
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
	buildCounters()
	buildButtons()
	buildWindows()
	buildTrainBar(onStop)

	lastPower = stat("ThrowPower", GameConfig.START_POWER)
	for _, attribute in { "Money", "GearTier", "ValueLevel", "Income" } do
		player:GetAttributeChangedSignal(attribute):Connect(Hud.refresh)
	end
	player:GetAttributeChangedSignal("ThrowPower"):Connect(function()
		local power = stat("ThrowPower", GameConfig.START_POWER)
		if power > lastPower and player:GetAttribute("Action") == "Training" then
			levelGain = power - lastPower
			UIKit.pop(powerLabel, 1.2)
			if levelUpPending then
				announceLevelUp()
			end
		end
		lastPower = power
		Hud.refresh()
	end)
	-- Popups seulement pour un palier au-delà de ceux connus au chargement : les valeurs sauvegardées (répliquées
	-- avant, avec ou après DataReady) ne s'annoncent pas
	local function seed()
		lastPower = stat("ThrowPower", GameConfig.START_POWER)
		knownLevel = stat("TrainLevel", 1)
		knownTier = stat("GearTier", 1)
	end
	if player:GetAttribute("DataReady") == true then
		seed()
	end
	player:GetAttributeChangedSignal("DataReady"):Connect(seed)
	player:GetAttributeChangedSignal("TrainLevel"):Connect(function()
		local level = stat("TrainLevel", 1)
		if level <= knownLevel then
			refreshTraining()
			return
		end
		knownLevel = level
		if levelGain > 0 then
			announceLevelUp()
		else
			levelUpPending = true -- la Throw Power du niveau arrive juste après
			task.delay(LEVEL_GAIN_WAIT, function()
				if levelUpPending then
					announceLevelUp()
				end
			end)
		end
		refreshTraining()
	end)
	player:GetAttributeChangedSignal("TrainReps"):Connect(function()
		-- Une répétition terminée change toujours TrainReps (+1, ou retour à 0 au passage de niveau)
		if player:GetAttribute("Action") == "Training" then
			floatExp()
		end
		refreshTraining()
	end)
	player:GetAttributeChangedSignal("GearTier"):Connect(function()
		local tier = stat("GearTier", 1)
		if tier <= knownTier then
			return
		end
		knownTier = tier
		local gear = Training.gear(tier)
		showPopup("NEW EQUIPMENT!", gear.name .. "  +" .. Format.short(gear.gain) .. " Throw Power / rep")
		UIKit.playSound("LevelUp", 1.2)
	end)
	player:GetAttributeChangedSignal("Money"):Connect(function()
		UIKit.pop(moneyLabel, 1.15)
	end)
	player:GetAttributeChangedSignal("Action"):Connect(refreshState)
	player:GetAttributeChangedSignal("LaneState"):Connect(refreshState)
	watchTemplates()
	Hud.refresh()
	refreshTraining()
	refreshState()
end

return Hud
