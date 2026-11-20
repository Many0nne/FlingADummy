-- HUD permanent au style des jeux de référence : boutons à icône (Index et Shop à gauche, Dummies à droite, pastille
-- « ! »), compteurs icône + valeur en bas à gauche (Throw Power, argent et revenu « +$N/s »), fenêtres à bandeau et
-- cartes d'objets (équipements d'entraînement, mannequins, index), barre d'entraînement avec STOP, « +N EXP » qui
-- s'envole à chaque répétition, popups LEVEL UP! (Throw Power gagnée au niveau) / NEW EQUIPMENT!, et popup « NEW GEAR! »
-- qui propose l'équipement suivant dès qu'il est abordable (achat en un clic).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Training = require(Shared:WaitForChild("Training"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))
local UIMotion = require(Shared:WaitForChild("UIMotion"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local BUTTON_SIZE = 92 -- côté des boutons à icône à 720 px de haut (≈ 0,13 h, comme les références)
local INDEX_SLOTS = 8 -- cases de l'index en attendant son contenu (#52)
local FLY_GROUP = 0.35 -- s : un gain arrivé moins de FLY_GROUP s après le précédent rejoint son « +N » en vol
local FLY_MAX = 3 -- « +N » en vol au plus par compteur

local Hud = {}

local player: Player
local gui: ScreenGui
local root: Frame -- tout le HUD permanent, masqué pendant le vol
local hudScale: UIScale
local powerLabel: TextLabel
local moneyLabel: TextLabel
-- Compteurs qui reçoivent des « +N » volants : le gain n'est ajouté au chiffre affiché qu'à l'arrivée du « +N »
type Flight = { label: TextLabel?, total: number }
type Counter = {
	label: TextLabel,
	icon: GuiObject,
	iconName: string,
	color: Color3,
	flash: Color3,
	format: (number) -> string,
	batch: UIMotion.Batch,
	pending: number,
	flights: { [number]: Flight },
}
local counters: { [string]: Counter } = {}
local anchors: { [string]: GuiObject } = {} -- éléments que l'objectif peut désigner
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
local lastMoney = 0
local seeded = false -- valeurs sauvegardées chargées : les gains suivants volent vers les compteurs
local levelGain = 0 -- Throw Power versée au dernier niveau d'entraînement, pas encore annoncée
local levelUpPending = false -- niveau arrivé avant sa Throw Power (ordre de réplication non garanti)
local LEVEL_GAIN_WAIT = 0.5 -- attente maximale de la Throw Power d'un niveau avant de l'annoncer quand même (s)
local REP_DEBOUNCE = 0.3 -- une répétition peut changer TrainExp et TrainLevel : un seul « +N EXP » (s, < REP_TIME)
local lastRepFloat = 0
local knownLevel = math.huge -- palier d'entraînement et équipement déjà annoncés (aucun avant le chargement)
local knownTier = math.huge
local popupEndsAt = 0
-- Popup « NEW GEAR! » (référence 09, « Nouvel équipement ! ») : palier proposé, et paliers dont le joueur l'a fermé
type Offer = { frame: Frame, button: TextButton, viewport: ViewportFrame, name: TextLabel, stat: TextLabel }
local offer: Offer
local offerTier: number? = nil
local dismissedOffers: { [number]: boolean } = {}

-- Cette méthode permet de lire un attribut numérique du joueur (valeur par défaut si absent) lorsque le HUD se
-- rafraîchit.
local function stat(name: string, default: number): number
	return (player:GetAttribute(name) :: number?) or default
end

-- Cette méthode permet d'ouvrir une fenêtre (et de fermer les autres) ou de la refermer lorsque le joueur clique sur
-- son bouton ; aucune ne s'ouvre pendant la jauge (elle la couvrirait et capterait le clic de lancer).
local function toggle(name: string)
	local target = windows[name]
	local open = not UIKit.isWindowOpen(target) and player:GetAttribute("Action") ~= "Holding"
	for _, window in windows do
		if window ~= target or not open then
			UIKit.closeWindow(window, window ~= target)
		end
	end
	if open then
		UIKit.openWindow(target)
	end
	Hud.refresh()
end

-- Cette méthode permet de créer une ligne de compteur (icône dessinée + valeur à contour, ancrée à gauche pour
-- gonfler vers la droite) en bas à gauche lorsque le HUD est construit ; `kind` est l'attribut du joueur compté.
local function counter(
	parent: Instance,
	order: number,
	kind: string,
	icon: string,
	color: Color3,
	flash: Color3,
	format: (number) -> string
): TextLabel
	local row = UIKit.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(300, 40),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local iconLabel = UIKit.icon(icon, { Size = UDim2.fromOffset(40, 40), Parent = row })
	local label = UIKit.text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 46, 0.5, 0),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 32,
		TextColor3 = color,
		Parent = row,
	})
	counters[kind] = {
		label = label,
		icon = iconLabel,
		iconName = icon,
		color = color,
		flash = flash,
		format = format,
		-- Vol compté un peu plus court que l'animation : un gain tardif ouvre un nouveau « +N » plutôt que de
		-- rejoindre une étiquette déjà arrivée
		batch = UIMotion.newBatch(FLY_GROUP, UIKit.FLY_DURATION - 0.05, FLY_MAX),
		pending = 0,
		flights = {},
	}
	return label
end

-- Cette méthode permet de construire les deux compteurs (puissance, argent et revenu) en bas à gauche lorsque le HUD
-- est construit.
local function buildCounters()
	local row = UIKit.create("Frame", {
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
		Parent = row,
	})
	powerLabel = counter(row, 1, "ThrowPower", "power", C.cyan, C.white, Format.short)
	moneyLabel = counter(row, 2, "Money", "cash", C.white, C.yellow, Format.money)
end

-- Cette méthode permet de construire les boutons à icône (Index et Shop à gauche avec reflet sur Shop, Dummies à
-- droite avec reflet) lorsque le HUD est construit ; ancrés au centre, ils grossissent sur place au survol.
local function buildButtons()
	local gap = 22
	local left = UIKit.create("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE * 2 + gap),
		BackgroundTransparency = 1,
		Parent = root,
	})
	anchors.Index = UIKit.iconButton("index", "Index", BUTTON_SIZE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, BUTTON_SIZE / 2),
		Parent = left,
	}, function()
		toggle("Index")
	end)
	anchors.Shop = UIKit.iconButton("shop", "Shop", BUTTON_SIZE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, BUTTON_SIZE * 1.5 + gap),
		Shine = true,
		Parent = left,
	}, function()
		toggle("Shop")
	end)
	anchors.Dummies = UIKit.iconButton("dummies", "Dummies", BUTTON_SIZE, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Shine = true,
		Parent = root,
	}, function()
		toggle("Dummies")
	end)
end

-- Cette méthode permet de construire le popup « NEW GEAR! » (bandeau dégradé et croix, rendu 3D, nom, prix et gain,
-- bouton vert UPGRADE qui achète directement, comme « Nouvel équipement ! » de la référence 09) lorsque le HUD est construit.
local function buildGearOffer()
	local frame = UIKit.create("Frame", {
		Name = "GearOffer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(440, 136),
		BackgroundColor3 = C.panel,
		Visible = false,
		ZIndex = 15,
		Parent = root,
	})
	UIKit.corner(frame, 12)
	UIKit.outline(frame, 4)
	local header = UIKit.create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 15,
		Parent = frame,
	})
	UIKit.corner(header, 12)
	UIKit.create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(150, 60, 230), Color3.fromRGB(255, 70, 170)),
		Parent = header,
	})
	-- Bas du bandeau droit, cerné d'un trait épais (comme les fenêtres)
	local flat = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 15,
		Parent = header,
	})
	UIKit.create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(150, 60, 230), Color3.fromRGB(255, 70, 170)),
		Parent = flat,
	})
	UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = C.ink,
		BorderSizePixel = 0,
		ZIndex = 16,
		Parent = header,
	})
	UIKit.text({
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -60, 1, 0),
		Text = "NEW GEAR!",
		TextSize = 28,
		StrokeThickness = 2.5,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 17,
		Parent = header,
	})
	UIKit.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = C.red,
		Text = "X",
		TextSize = 22,
		ZIndex = 17,
		Parent = header,
	}, function()
		if offerTier then
			dismissedOffers[offerTier] = true
		end
		Hud.refresh()
	end)
	local well = UIKit.create("Frame", {
		Position = UDim2.fromOffset(10, 48),
		Size = UDim2.fromOffset(78, 78),
		BackgroundColor3 = Color3.fromRGB(28, 31, 40),
		ZIndex = 16,
		Parent = frame,
	})
	UIKit.corner(well, 8)
	UIKit.outline(well, 2)
	local viewport = UIKit.create("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1.5, 1),
		ZIndex = 17,
		Parent = well,
	})
	UIKit.text({
		Position = UDim2.fromOffset(98, 50),
		Size = UDim2.fromOffset(190, 18),
		Text = "You can now buy",
		TextSize = 17,
		TextColor3 = Color3.fromRGB(190, 195, 210),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 17,
		Parent = frame,
	})
	local name = UIKit.text({
		Position = UDim2.fromOffset(98, 68),
		Size = UDim2.fromOffset(190, 30),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 17,
		Parent = frame,
	})
	local statLabel = UIKit.text({
		Position = UDim2.fromOffset(98, 100),
		Size = UDim2.fromOffset(190, 22),
		TextSize = 18,
		TextColor3 = C.green,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 17,
		Parent = frame,
	})
	local button = UIKit.button({
		Name = "Upgrade",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0, 88),
		Size = UDim2.fromOffset(136, 50),
		Text = "UPGRADE",
		TextSize = 26,
		Shine = true,
		ZIndex = 17,
		Parent = frame,
	}, function()
		if offerTier == stat("GearTier", 1) + 1 then
			Hud.onBuy("Gear")
		end
	end)
	offer = { frame = frame, button = button, viewport = viewport, name = name, stat = statLabel }
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
		UIKit.closeWindow(windows.Shop)
		Hud.refresh()
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
		UIKit.closeWindow(windows.Dummies)
	end)
	windows.Dummies = dummies.frame
	local dummyRow = cardRow(dummies.body)
	dummyCard = UIKit.card(dummyRow, 1, function() end)
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
		UIKit.closeWindow(windows.Index)
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

-- Cette méthode permet de construire le rendu 3D d'un équipement (néon à la place du verre et du champ de force, qui
-- ne se rendent pas en ViewportFrame) lorsqu'une carte ou le popup « NEW GEAR! » l'affichent.
local function gearModel(tier: number): Model
	local gear = Training.GEARS[tier]
	local material = if gear.material == Enum.Material.Glass or gear.material == Enum.Material.ForceField
		then Enum.Material.Neon
		else gear.material
	return DummyShape.buildVisual(1, { color = gear.color, material = material })
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
		UIKit.showModel(card.viewport, gearModel(tier))
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
		card.stat.Text = "+" .. Format.short(gear.gain) .. " EXP / rep"
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

-- Cette méthode permet d'habiller la carte du mannequin lancé (le seul en attendant la boutique de mannequins, #14)
-- lorsque sa fenêtre s'ouvre.
local function refreshDummy()
	dummyCard.title.Text = "Crash Dummy"
	dummyCard.rarity.Text = "Starter"
	dummyCard.rarity.TextColor3 = C.yellow
	dummyCard.stat.Text = "x1 CHANCE"
	setAction(dummyCard, "EQUIPPED", C.equipped, false)
end

-- Cette méthode permet d'afficher, de mettre à jour ou de masquer le popup « NEW GEAR! » lorsque l'argent affiché,
-- l'équipement ou l'état du joueur changent : palier suivant abordable, pas fermé par le joueur, écran libre.
local function refreshOffer(money: number, cost: number?)
	local free = seeded
		and player:GetAttribute("LaneState") == "Ready"
		and player:GetAttribute("Action") ~= "Holding"
		and not UIKit.isWindowOpen(windows.Shop)
	local tier = if free then Tutorial.gearOffer(stat("GearTier", 1), cost, money, dismissedOffers) else nil
	if tier == offerTier then
		return
	end
	offerTier = tier
	if not tier then
		UIKit.closeWindow(offer.frame, player:GetAttribute("LaneState") ~= "Ready")
		return
	end
	local gear = Training.GEARS[tier]
	offer.name.Text = gear.name
	offer.stat.Text = Format.money(gear.cost) .. "  •  +" .. Format.short(gear.gain) .. " EXP / rep"
	UIKit.showModel(offer.viewport, gearModel(tier))
	UIKit.openWindow(offer.frame, false)
	UIKit.playSound("LevelUp", 1.4)
end

-- Cette méthode permet de rafraîchir compteurs, cartes et pastilles « ! » lorsque l'argent, la puissance,
-- l'équipement, la valeur ou le revenu changent.
function Hud.refresh()
	-- Argent affiché (gains en vol pas encore arrivés) : pastilles et prix suivent le compteur, pas l'attribut
	local money = math.max(0, stat("Money", 0) - counters.Money.pending)
	-- Revenu collé au montant, en plus petit et en vert (comme « $64 +$1 » de la référence 02), seulement s'il existe
	local income = stat("Income", 0)
	moneyLabel.Text = Format.money(money)
		.. if income > 0
			then string.format(' <font size="22" color="#50D746">%s</font>', Format.perSecond(income))
			else ""
	powerLabel.Text =
		Format.short(math.max(0, stat("ThrowPower", GameConfig.START_POWER) - counters.ThrowPower.pending))

	local gearCost = Training.nextGearCost(stat("GearTier", 1))
	UIKit.setBadge(anchors.Shop, if gearCost ~= nil and money >= gearCost then "!" else nil)
	if windows.Shop.Visible or windows.Dummies.Visible then
		buildModels()
		refreshGear(money)
		refreshDummy()
	end
	refreshOffer(money, gearCost)
end

-- Cette méthode permet de faire s'envoler « +N EXP » (EXP de l'équipement) au-dessus de la barre d'entraînement lorsque
-- l'avatar termine une répétition, comme « +1 d'EXP » de la référence 01.
local function floatExp(amount: number)
	local holder = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, math.random(-90, 90), 1, -130),
		Size = UDim2.fromOffset(150, 40),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local label = UIKit.text({
		Size = UDim2.fromScale(1, 1),
		Text = "+" .. Format.short(amount) .. " EXP",
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

-- Cette méthode permet de rafraîchir la barre d'entraînement (niveau, EXP du niveau) lorsque la progression change.
local function refreshTraining()
	local level = stat("TrainLevel", 1)
	local exp = stat("TrainExp", 0)
	local needed = Training.expForLevel(level)
	trainLevel.Text = "Level " .. level
	trainCount.Text = Format.short(exp) .. "/" .. Format.short(needed)
	TweenService:Create(trainFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(math.min(exp / needed, 1), 1) }):Play()
end

-- Cette méthode permet d'annoncer une répétition terminée (« +N EXP ») lorsque l'EXP ou le niveau d'entraînement
-- change pendant la séance ; une seule annonce si les deux changent ensemble.
local function onRepProgress()
	if player:GetAttribute("Action") == "Training" and os.clock() - lastRepFloat > REP_DEBOUNCE then
		lastRepFloat = os.clock()
		floatExp(Training.gear(stat("GearTier", 1)).gain)
	end
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
			UIKit.closeWindow(window, true)
		end
	end
	Hud.refresh() -- popup « NEW GEAR! » seulement écran libre
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
local function showPopup(options: UIKit.PopupOptions)
	local duration = UIKit.popup(gui, options)
	popupEndsAt = os.clock() + duration
end

-- Cette méthode permet de faire voler un gain (« +N » et icônes) de `from` (pixels d'écran) au compteur `kind`,
-- regroupé avec un gain rapproché, lorsque l'argent ou la puissance augmentent ; le chiffre n'avance qu'à l'arrivée.
local function flyGain(kind: string, amount: number, from: Vector2)
	local c = counters[kind]
	c.pending += amount
	local action, id = UIMotion.push(c.batch, amount, os.clock())
	local existing = c.flights[id]
	if action == "merge" and existing and existing.label then
		-- Total tenu par l'étiquette (un achat a pu l'entamer), pas par le regroupeur
		existing.total += amount
		existing.label.Text = "+" .. c.format(existing.total)
		return
	end
	local flight: Flight = { total = amount }
	c.flights[id] = flight
	flight.label = UIKit.flyGain({
		from = from,
		target = c.label,
		iconTarget = c.icon,
		text = "+" .. c.format(amount),
		color = if kind == "Money" then C.green else c.color,
		icon = c.iconName,
		icons = UIMotion.burstSize(amount),
		scale = hudScale.Scale,
		onIcon = function()
			UIKit.playKeys(c.label, UIMotion.COUNTER_BUMP)
		end,
		onArrive = function()
			if c.flights[id] == flight then
				c.flights[id] = nil
			end
			c.pending = math.max(0, c.pending - flight.total)
			Hud.refresh()
			if flight.total > 0 then
				UIKit.bump(c.label, c.flash)
			end
		end,
	})
end

-- Cette méthode permet de retirer des gains en attente ce qui a été dépensé lorsque le compteur `kind` baisse sous eux
-- (achat, remise à zéro) ; les étiquettes les plus récentes sont réduites d'abord.
local function clampPending(kind: string, value: number)
	local c = counters[kind]
	local excess = c.pending - math.max(0, value)
	if excess <= 0 then
		return
	end
	c.pending -= excess
	local ids = {}
	for id in c.flights do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return a > b
	end)
	for _, id in ids do
		local flight = c.flights[id]
		local cut = math.min(flight.total, excess)
		if cut > 0 then
			flight.total -= cut
			excess -= cut
			if flight.label then
				flight.label.Text = "+" .. c.format(flight.total)
				flight.label.Visible = flight.total > 0 -- tout dépensé : plus rien à faire voler
			end
		end
	end
end

-- Cette méthode permet d'annoncer le niveau d'entraînement franchi (« LEVEL UP! », Throw Power versée) lorsque le
-- niveau et sa Throw Power sont arrivés, dans un ordre ou dans l'autre.
local function announceLevelUp()
	levelUpPending = false
	showPopup({ title = "LEVEL UP!", subtitle = "Throw Power +" .. Format.short(levelGain), subtitleColor = C.cyan })
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

-- Cette méthode permet de donner le bouton UPGRADE du popup « NEW GEAR! » lorsque la flèche du tutoriel cherche où
-- pointer ; nil quand le popup n'est pas affiché.
function Hud.offerButton(): GuiObject?
	return if offerTier ~= nil then offer.button else nil
end

-- Cette méthode permet de donner le bouton d'achat de la carte visée (« Gear » : équipement suivant) lorsque la
-- flèche du tutoriel cherche où pointer ; nil si sa fenêtre n'est pas ouverte.
function Hud.buyButton(kind: string): GuiObject?
	if kind == "Gear" and UIKit.isWindowOpen(windows.Shop) then
		local card = gearCards[stat("GearTier", 1) + 1]
		return if card then card.action else nil
	end
	return nil
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
	hudScale = UIKit.create("UIScale", { Parent = gui })
	bindScale(hudScale)
	root = UIKit.create("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	buildCounters()
	buildButtons()
	buildGearOffer()
	buildWindows()
	buildTrainBar(onStop)

	lastPower = stat("ThrowPower", GameConfig.START_POWER)
	lastMoney = stat("Money", 0)
	for _, attribute in { "GearTier", "Income" } do
		player:GetAttributeChangedSignal(attribute):Connect(Hud.refresh)
	end
	player:GetAttributeChangedSignal("Money"):Connect(function()
		local money = stat("Money", 0)
		-- Le revenu de la base tombe tout seul chaque seconde (pas de « +N » volant) ; un achat entame les gains en vol
		if money < lastMoney then
			clampPending("Money", money)
			UIKit.pop(moneyLabel, 0.85) -- dépense : le compteur se tasse puis revient
		end
		lastMoney = money
		Hud.refresh()
	end)
	player:GetAttributeChangedSignal("ThrowPower"):Connect(function()
		local power = stat("ThrowPower", GameConfig.START_POWER)
		if power > lastPower and player:GetAttribute("Action") == "Training" then
			levelGain = power - lastPower
			if seeded then
				flyGain("ThrowPower", levelGain, trainBar.AbsolutePosition + trainBar.AbsoluteSize / 2)
			end
			if levelUpPending then
				announceLevelUp()
			end
		elseif power < lastPower then
			clampPending("ThrowPower", power)
		end
		lastPower = power
		Hud.refresh()
	end)
	-- Popups seulement pour un palier au-delà de ceux connus au chargement : les valeurs sauvegardées (répliquées
	-- avant, avec ou après DataReady) ne s'annoncent pas
	local function seed()
		seeded = true
		lastPower = stat("ThrowPower", GameConfig.START_POWER)
		lastMoney = stat("Money", 0)
		knownLevel = stat("TrainLevel", 1)
		knownTier = stat("GearTier", 1)
		Hud.refresh()
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
		onRepProgress()
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
	player:GetAttributeChangedSignal("TrainExp"):Connect(function()
		onRepProgress()
		refreshTraining()
	end)
	player:GetAttributeChangedSignal("GearTier"):Connect(function()
		local tier = stat("GearTier", 1)
		if tier <= knownTier then
			return
		end
		knownTier = tier
		local gear = Training.gear(tier)
		showPopup({
			title = "NEW EQUIPMENT!",
			tag = "NEW!",
			subtitle = gear.name .. "  +" .. Format.short(gear.gain) .. " EXP / rep",
		})
		UIKit.playSound("LevelUp", 1.2)
	end)
	player:GetAttributeChangedSignal("Action"):Connect(refreshState)
	player:GetAttributeChangedSignal("LaneState"):Connect(refreshState)
	watchTemplates()
	Hud.refresh()
	refreshTraining()
	refreshState()
end

return Hud
