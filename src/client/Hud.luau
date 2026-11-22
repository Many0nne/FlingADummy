-- HUD permanent au style des jeux de référence : boutons à icône (Index, Shop et Rebirth à gauche, Dummies à droite,
-- pastille « ! »), compteurs icône + valeur en bas à gauche (Throw Power, argent et revenu « +$N/s »), fenêtres à bandeau et
-- cartes d'objets (équipements d'entraînement ; collection, vente et Index : Client.CollectionWindows), barre
-- d'entraînement avec STOP, « +N EXP » qui
-- s'envole à chaque répétition, popups LEVEL UP! (Throw Power gagnée au niveau) / NEW EQUIPMENT!, popup « NEW GEAR! »
-- qui propose l'équipement suivant dès qu'il est abordable (bouton vers sa carte de la fenêtre) et popup
-- « NEW DUMMY! » qui annonce le mannequin à lancer suivant abordable (bouton SHOP vers la boutique, Client.ThrowShop).
-- Fenêtre REBIRTH :
-- Client.RebirthWindow. Invites du pad d'amélioration à côté de l'appareil (#159) : achat de l'équipement suivant
-- (même remote que la fenêtre) et ouverture de la fenêtre Training Gear.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local GearPad = require(Shared:WaitForChild("GearPad"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))
local Training = require(Shared:WaitForChild("Training"))
local TrainingBoost = require(Shared:WaitForChild("TrainingBoost"))
local TrainingLook = require(Shared:WaitForChild("TrainingLook"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))
local UIMotion = require(Shared:WaitForChild("UIMotion"))
local Overlay = require(Shared:WaitForChild("Overlay"))

local CollectionWindows = require(script.Parent.CollectionWindows)
local RebirthWindow = require(script.Parent.RebirthWindow)
local StoreWindow = require(script.Parent.StoreWindow)
local ThrowShop = require(script.Parent.ThrowShop)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local BUTTON_SIZE = 92 -- côté des boutons à icône à 720 px de haut (≈ 0,13 h, comme les références)
local MUSIC_SIZE = 64 -- bouton musique, plus discret, sous Dummies
local FLY_GROUP = 0.35 -- s : un gain arrivé moins de FLY_GROUP s après le précédent rejoint son « +N » en vol
local FLY_MAX = 3 -- « +N » en vol au plus par compteur

local Hud = {}

-- Appelée au clic du bouton musique (Client.Music.toggle, branché par l'amorçage du client)
Hud.onMusicToggle = nil :: (() -> ())?

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
local musicOff: Frame -- barre rouge en travers du bouton musique quand la musique est coupée
local windows: { [string]: Frame } = {}
local gearCards: { UIKit.Card } = {}
local gearRow: ScrollingFrame? -- rangée des cartes d'équipement (défile jusqu'au prochain achat à l'ouverture)
local modelsStage: number? = nil -- étape des gabarits (DummyShape.meshStage) des rendus 3D des cartes déjà construits
local trainBar: Frame
local leftColumn: Frame -- colonne Index / Shop / Rebirth, centrée verticalement
local BUTTON_GAP = 22 -- écart vertical entre deux boutons de la colonne de gauche
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
local bannerEndsAt = 0 -- bandeau d'annonce en haut de l'écran (Client.Announce) : les popups passent dessous
local BANNER_POPUP_Y = 160 -- px : centre d'un popup ouvert pendant un bandeau (au lieu de 92)
-- Ventes envoyées au serveur : leur argent volera du bouton au compteur quand il arrivera
type ExpectedGain = { amount: number, from: Vector2, untilTime: number }
local expectedGains: { ExpectedGain } = {}
local EXPECT_TIME = 3 -- s : une vente que le serveur n'a pas créditée dans ce délai ne vole plus
-- Popups d'offre (référence 09, « Nouvel équipement ! » / « Nouvelle graine débloquée ! ») : « NEW GEAR! » (équipement
-- d'entraînement, achat en un clic) ou « NEW DUMMY! » (mannequin à lancer, bouton vers la boutique), un seul à la fois ;
-- type et palier proposés, et paliers dont le joueur a fermé le popup, par type
type Offer = {
	frame: Frame,
	button: TextButton,
	viewport: ViewportFrame,
	title: TextLabel,
	name: TextLabel,
	stat: TextLabel,
	gradients: { UIGradient },
}
local offer: Offer
local offerKind: string? = nil -- "Gear" | "Dummy"
local offerTier: number? = nil
local offerStage = 0 -- étape des gabarits (DummyShape.meshStage) du rendu 3D de l'offre affichée
local soundedOffer: string? = nil
local dismissedOffers: { [string]: { [number]: boolean } } = { Gear = {}, Dummy = {} }
local OFFER_SCALE = 0.8 -- échelle du popup d'offre (440 × 136 dessiné, 352 × 109 affiché à 720 px de haut)
local OFFER_TOP = 40 -- px : haut du popup d'offre
Hud.OFFER_SCALE = OFFER_SCALE -- la flèche du tutoriel posée sur l'offre compense cette échelle
Hud.OFFER_BOTTOM = OFFER_TOP + math.round(136 * OFFER_SCALE) -- px : bas du popup d'offre (le texte de l'objectif passe dessous)
local OFFER_COLORS = {
	Gear = { Color3.fromRGB(150, 60, 230), Color3.fromRGB(255, 70, 170) },
	Dummy = { Color3.fromRGB(255, 90, 150), Color3.fromRGB(215, 30, 95) },
}

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
	-- Cible ouverte avant de fermer les autres : jamais d'instant sans fenêtre, où l'offre surgirait (Visible → refresh)
	if open then
		UIKit.openWindow(target)
	end
	for _, window in windows do
		if window ~= target or not open then
			UIKit.closeWindow(window, window ~= target)
		end
	end
	if open then
		-- Boutiques longues (#94) : ouvertes sur le prochain achat
		if name == "Shop" and gearRow then
			UIKit.scrollToCard(gearRow, math.min(stat("GearTier", 1) + 1, #Training.GEARS))
		elseif name == "DummyShop" then
			ThrowShop.scrollToNext()
		end
		RebirthWindow.refresh()
	end
	Hud.refresh()
	CollectionWindows.refresh() -- les fenêtres de collection ne suivent que leurs attributs : rafraîchies à l'ouverture
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

-- Cette méthode permet de construire les boutons à icône (Index, Shop et Rebirth à gauche avec reflet sur Shop,
-- Dummies à droite avec reflet) lorsque le HUD est construit ; ancrés au centre, ils grossissent sur place au survol.
-- Rebirth n'apparaît qu'après le premier lancer (Hud.refresh), comme le bouton Renaissance de la référence 12.
local function buildButtons()
	local gap = BUTTON_GAP
	local left = UIKit.create("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE * 2 + gap),
		BackgroundTransparency = 1,
		Parent = root,
	})
	leftColumn = left
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
		toggle("Store") -- boutique Robux (#160) ; Training Gear s'ouvre au pad devant l'appareil (#159)
	end)
	anchors.Rebirth = UIKit.iconButton("rebirth", "Rebirth", BUTTON_SIZE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, BUTTON_SIZE * 2.5 + gap * 2),
		Visible = false,
		Parent = left,
	}, function()
		toggle("Rebirth")
	end)
	anchors.Dummies = UIKit.iconButton("dummies", "Dummies", BUTTON_SIZE, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Shine = true,
		Parent = root,
	}, function()
		toggle("Dummies")
	end)
	-- Bouton musique (muet), sous Dummies ; barre rouge en travers quand la musique est coupée
	local music = UIKit.iconButton("music", "Music", MUSIC_SIZE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -14 - BUTTON_SIZE / 2, 0.5, BUTTON_SIZE / 2 + gap + MUSIC_SIZE / 2),
		Parent = root,
	}, function()
		if Hud.onMusicToggle then
			Hud.onMusicToggle()
		end
	end)
	musicOff = UIKit.create("Frame", {
		Name = "Off",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(1.05, 0, 0, 9),
		Rotation = -45,
		BackgroundColor3 = C.red,
		Visible = false,
		ZIndex = 4,
		Parent = music,
	})
	UIKit.corner(musicOff, 4)
	UIKit.outline(musicOff, 2)
end

-- Cette méthode permet d'afficher l'état du bouton musique (barre rouge en travers si coupée) lorsque le muet change.
function Hud.setMusicOff(off: boolean)
	musicOff.Visible = off
end

-- Cette méthode permet de construire le popup d'offre (bandeau dégradé et croix, rendu 3D, nom, prix et gain, bouton
-- vert : UPGRADE qui achète l'équipement directement, ou SHOP qui ouvre la boutique des mannequins à lancer, comme
-- « Nouvel équipement ! » et « Nouvelle graine débloquée ! » de la référence 09) lorsque le HUD est construit.
local function buildGearOffer()
	-- Support transparent (ouvert et fermé en pop) autour du panneau réduit à OFFER_SCALE : popup à la taille de celui
	-- de 09 (≈ un quart de la largeur), qui masque moins le texte flottant de la base vue de près
	local holder = UIKit.create("Frame", {
		Name = "GearOffer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, OFFER_TOP),
		Size = UDim2.fromOffset(math.round(440 * OFFER_SCALE), math.round(136 * OFFER_SCALE)),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 15,
		Parent = root,
	})
	local frame = UIKit.create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 136),
		BackgroundColor3 = C.panel,
		ZIndex = 15,
		Parent = holder,
	})
	UIKit.create("UIScale", { Scale = OFFER_SCALE, Parent = frame })
	UIKit.corner(frame, 12)
	UIKit.outline(frame, 4)
	local header = UIKit.create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 15,
		Parent = frame,
	})
	UIKit.corner(header, 12)
	local headerGradient = UIKit.create("UIGradient", {
		Color = ColorSequence.new(OFFER_COLORS.Gear[1], OFFER_COLORS.Gear[2]),
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
	local flatGradient = UIKit.create("UIGradient", {
		Color = ColorSequence.new(OFFER_COLORS.Gear[1], OFFER_COLORS.Gear[2]),
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
	local title = UIKit.text({
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
		if offerKind and offerTier then
			dismissedOffers[offerKind][offerTier] = true
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
		if offerKind == "Gear" then
			-- Fenêtre Training Gear ouverte sur la carte de l'équipement (#159) : l'achat se fait sur sa carte
			if not UIKit.isWindowOpen(windows.Shop) then
				toggle("Shop")
			end
		elseif offerKind == "Dummy" and offerTier then
			dismissedOffers.Dummy[offerTier] = true -- vu dans la boutique : l'offre ne revient pas à sa fermeture
			Hud.openDummyShop()
		end
	end)
	offer = {
		frame = holder,
		button = button,
		viewport = viewport,
		title = title,
		name = name,
		stat = statLabel,
		gradients = { headerGradient, flatGradient },
	}
end

-- Cette méthode permet de construire la fenêtre des équipements d'entraînement lorsque le HUD est construit (fenêtres de
-- collection : Client.CollectionWindows).
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
	local rowFrame = UIKit.cardGrid(shop.body, 3) -- 3 cartes par rangée, défilement vertical (#45)
	gearRow = rowFrame
	for tier in Training.GEARS do
		gearCards[tier] = UIKit.card(rowFrame, tier, function()
			if tier == stat("GearTier", 1) + 1 then
				Hud.onBuy("Gear")
			end
		end)
	end
end

-- Cette méthode permet de construire le rendu 3D d'un équipement (look du palier, Shared.TrainingLook ; néon à la place
-- du verre et du champ de force, qui ne se rendent pas en ViewportFrame) lorsqu'une carte ou le popup « NEW GEAR! »
-- l'affichent (pièces ajoutées au repos en mouvement réduit : Client.DummyFx).
local function gearModel(tier: number): Model
	local model = DummyShape.buildVisual(1, TrainingLook.variant(tier, "viewport") :: DummyShape.Variant)
	DummyShape.viewportSafe(model)
	return model
end

-- Cette méthode permet de (re)construire les rendus 3D des cartes (mannequins soulevés) lorsque une
-- fenêtre s'ouvre pour la première fois ou que les maillages publiés viennent d'arriver.
local function buildModels()
	local stage = DummyShape.meshStage()
	if modelsStage == stage then
		return
	end
	modelsStage = stage
	for tier, card in gearCards do
		UIKit.showModel(card.viewport, gearModel(tier))
	end
end

-- Cette méthode permet de reconstruire les rendus 3D d'une fenêtre ouverte lorsque les gabarits maillés du mannequin
-- arrivent (dossier créé puis marqué Ready par Server.DummyAssets).
local function watchTemplates()
	-- Cette méthode permet de rafraîchir les fenêtres lorsque le dossier des gabarits passe à Ready.
	local function watch(folder: Instance)
		for _, attribute in { "Ready", DummyShape.COMPLETE } do
			folder:GetAttributeChangedSignal(attribute):Connect(function()
				Hud.refresh()
				CollectionWindows.refresh()
			end)
		end
		-- Dossier répliqué déjà marqué (arrivé après le HUD) : aucun changement d'attribut ne viendra
		if folder:GetAttribute("Ready") then
			Hud.refresh()
			CollectionWindows.refresh()
		end
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
		-- Plus d'équipements que de raretés (#94) : les derniers « Infinity + », « Infinity ++ »…
		card.rarity.Text = rarity.name
			.. (if tier > #Rarity.LIST then " " .. string.rep("+", tier - #Rarity.LIST) else "")
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

-- Cette méthode permet d'habiller le popup d'offre pour le type `kind` (titre, couleurs du bandeau, bouton) et le
-- palier `tier` (nom, prix et gain, rendu 3D) lorsque l'offre affichée change.
local function dressOffer(kind: string, tier: number)
	local colors = OFFER_COLORS[kind]
	for _, gradient in offer.gradients do
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
	if kind == "Gear" then
		local gear = Training.GEARS[tier]
		offer.title.Text = "NEW GEAR!"
		offer.button.Text = "UPGRADE"
		offer.name.Text = gear.name
		offer.stat.Text = Format.money(gear.cost) .. "  •  +" .. Format.short(gear.gain) .. " EXP / rep"
		UIKit.showModel(offer.viewport, gearModel(tier))
	else
		local dummy = ThrowDummies.LIST[tier]
		offer.title.Text = "NEW DUMMY!"
		offer.button.Text = "SHOP"
		offer.name.Text = dummy.name
		offer.stat.Text = Format.money(dummy.cost) .. "  •  " .. Format.luck(dummy.luck) .. " CHANCE"
		UIKit.showModel(
			offer.viewport,
			DummyShape.buildVisual(1, ThrowDummies.variant(tier, true) :: DummyShape.Variant)
		)
	end
end

-- Cette méthode permet d'afficher, de mettre à jour ou de masquer le popup d'offre lorsque l'argent affiché, les
-- achats ou l'état du joueur changent, écran libre (ni fenêtre ni bandeau, Shared.Overlay) : l'équipement suivant
-- s'il est abordable (« NEW GEAR! », d'abord : étape du tutoriel), sinon le mannequin à lancer suivant
-- (« NEW DUMMY! ») ; pas une offre fermée par le joueur. Revenue après une fenêtre ou un popup, elle ne resonne pas.
local function refreshOffer(money: number, cost: number?)
	local free = seeded
		and player:GetAttribute("LaneState") == "Ready"
		and player:GetAttribute("Action") ~= "Holding"
		and Overlay.offer({ windowOpen = Hud.isWindowOpen(), bannerShown = os.clock() < bannerEndsAt })
	local kind, tier = nil, nil
	if free then
		tier = Tutorial.gearOffer(stat("GearTier", 1), cost, money, dismissedOffers.Gear)
		kind = if tier then "Gear" else nil
		if not tier then
			local owned = ThrowDummies.sanitize(player:GetAttribute("ThrowTier"), nil)
			tier = ThrowDummies.offer(owned, money, dismissedOffers.Dummy)
			kind = if tier then "Dummy" else nil
		end
	end
	local stage = DummyShape.meshStage()
	if kind == offerKind and tier == offerTier then
		if kind and tier and stage ~= offerStage then
			-- Maillages arrivés pendant l'offre : rendu 3D refait avec les pièces ajoutées du look (#118), sans son
			offerStage = stage
			dressOffer(kind, tier)
		end
		return
	end
	offerKind, offerTier, offerStage = kind, tier, stage
	if not kind or not tier then
		UIKit.closeWindow(offer.frame, player:GetAttribute("LaneState") ~= "Ready")
		return
	end
	dressOffer(kind, tier)
	UIKit.openWindow(offer.frame, false)
	local key = kind .. tier
	if key ~= soundedOffer then
		soundedOffer = key -- offre déjà annoncée : pas de nouveau son quand elle revient après un bandeau
		UIKit.playSound("LevelUp", 1.4)
	end
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
	-- Pastille du bouton Shop : pack de démarrage en offre (boutique Robux, #160)
	UIKit.setBadge(anchors.Shop, if StoreWindow.starterOffered() then "!" else nil)
	if windows.Shop.Visible then
		buildModels()
		refreshGear(money)
	end
	refreshOffer(money, gearCost)
	ThrowShop.refresh()
	-- Bouton Rebirth dès le premier lancer (objectif visible tôt), pastille quand la renaissance est possible
	local rebirthShown = stat("Draws", 0) > 0 or stat("Rebirths", 0) > 0
	anchors.Rebirth.Visible = rebirthShown
	local buttons = if rebirthShown then 3 else 2
	leftColumn.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE * buttons + BUTTON_GAP * (buttons - 1))
	UIKit.setBadge(anchors.Rebirth, if RebirthWindow.isReady() then "!" else nil)
	RebirthWindow.checkReady()
	RebirthWindow.refresh() -- argent affiché : un gain en vol qui arrive ne change aucun attribut
end

-- Cette méthode permet de faire s'envoler « +N EXP » (EXP de l'équipement, en orange pendant le bonus « 2x TRAINING! »)
-- au-dessus de la barre d'entraînement lorsque l'avatar termine une répétition, comme « +1 d'EXP » de la référence 01.
local function floatExp(amount: number, boosted: boolean)
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
		TextSize = if boosted then 36 else 32,
		TextColor3 = if boosted then C.orange else C.cyan,
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
	local needed = Training.expForLevel(level, stat("GearTier", 1))
	trainLevel.Text = "Level " .. level
	trainCount.Text = Format.short(exp) .. "/" .. Format.short(needed)
	TweenService:Create(trainFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(math.min(exp / needed, 1), 1) }):Play()
end

-- Cette méthode permet d'annoncer une répétition terminée (« +N EXP ») lorsque l'EXP ou le niveau d'entraînement
-- change pendant la séance ; une seule annonce si les deux changent ensemble.
local function onRepProgress()
	if player:GetAttribute("Action") == "Training" and os.clock() - lastRepFloat > REP_DEBOUNCE then
		lastRepFloat = os.clock()
		local multiplier = TrainingBoost.grantedMultiplier(player:GetAttribute("TrainBoostEnds"))
		floatExp(Training.gear(stat("GearTier", 1)).gain * multiplier, multiplier > 1)
	end
end

-- Cette méthode permet d'afficher la barre d'entraînement et de masquer le HUD en vol et pendant le tirage lorsque
-- l'action du joueur ou l'état du couloir changent.
local function refreshState()
	local action = player:GetAttribute("Action")
	local state = player:GetAttribute("LaneState")
	trainBar.Visible = action == "Training"
	-- Écran dégagé pendant le vol, l'atterrissage, la silhouette et la révélation, jusqu'au GO BACK (#60, comme 09 et 01)
	root.Visible = state ~= "Flying" and state ~= "Result"
	if state == "Flying" or state == "Result" or action == "Holding" then
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
	if os.clock() < bannerEndsAt and not options.position then
		options.position = UDim2.new(0.5, 0, 0, BANNER_POPUP_Y)
	end
	local duration = UIKit.popup(gui, options)
	popupEndsAt = math.max(popupEndsAt, os.clock() + duration)
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

-- Cette méthode permet de donner la barre d'entraînement (STOP et barre d'EXP, visible pendant la séance) lorsque le
-- bouton « 2x TRAINING! » y pose la barre de durée du bonus.
function Hud.trainBar(): Frame
	return trainBar
end

-- Cette méthode permet de donner l'élément du HUD que l'objectif désigne (« Shop », « Dummies ») lorsque la
-- flèche d'interface se place ; nil s'il n'existe pas.
function Hud.anchor(name: string): GuiObject?
	return anchors[name]
end

-- Cette méthode permet de donner le bouton UPGRADE du popup « NEW GEAR! » lorsque la flèche du tutoriel cherche où
-- pointer ; nil quand le popup n'est pas affiché.
function Hud.offerButton(): GuiObject?
	return if offerKind == "Gear" and offerTier ~= nil then offer.button else nil
end

-- Cette méthode permet d'ouvrir la boutique des mannequins à lancer (et de fermer les autres fenêtres) lorsque le
-- joueur déclenche l'invite du stand SHOP ou clique SHOP du popup « NEW DUMMY! » ; sans effet si elle est ouverte.
function Hud.openDummyShop()
	if not UIKit.isWindowOpen(windows.DummyShop) then
		toggle("DummyShop")
	end
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

-- Cette méthode permet d'annoncer une vente envoyée au serveur (argent attendu, position du bouton à l'écran) lorsque
-- le joueur vend : à l'arrivée de l'argent, un « +$N » vole du bouton au compteur.
function Hud.expectGain(amount: number, from: Vector2)
	if amount > 0 then
		table.insert(expectedGains, { amount = amount, from = from, untilTime = os.clock() + EXPECT_TIME })
	end
end

-- Cette méthode permet d'afficher un popup de palier (« NEW DISPLAY! », refus d'achat) lorsque un autre module
-- l'annonce.
function Hud.popup(options: UIKit.PopupOptions)
	showPopup(options)
end

-- Cette méthode permet de réserver le haut de l'écran pour `duration` s à partir de maintenant (0 : libéré ;
-- l'objectif se tait, les popups passent dessous) lorsque un bandeau d'annonce s'affiche ou s'en va.
function Hud.reserveTop(duration: number)
	bannerEndsAt = math.max(bannerEndsAt, os.clock() + duration) -- prolongée, jamais raccourcie (fête et bandeau)
	Hud.refresh() -- l'offre « NEW GEAR! » s'efface sous le bandeau, puis revient
	task.delay(duration + 0.05, Hud.refresh)
end

-- Cette méthode permet de savoir si un popup de palier occupe le haut de l'écran lorsque l'objectif s'affiche.
function Hud.isPopupShown(): boolean
	return os.clock() < popupEndsAt or os.clock() < bannerEndsAt
end

-- Cette méthode permet de savoir si une fenêtre du HUD (boutiques, collection, Index) est à l'écran, animation de
-- fermeture comprise, lorsque l'offre ou l'objectif se demandent s'ils peuvent s'afficher (Shared.Overlay).
function Hud.isWindowOpen(): boolean
	for _, window in windows do
		if UIKit.isWindowOpen(window) or window.Visible then
			return true
		end
	end
	return false
end

-- Cette méthode permet de savoir si le popup d'offre (« NEW GEAR! » / « NEW DUMMY! ») est à l'écran, animation de
-- fermeture comprise, lorsque le texte de l'objectif, dessiné au même endroit, se place.
function Hud.isOfferShown(): boolean
	return offer.frame.Visible
end

-- Cette méthode permet de savoir si un bandeau d'annonce occupe le haut de l'écran lorsque l'objectif se place.
function Hud.isBannerShown(): boolean
	return os.clock() < bannerEndsAt
end

-- Cette méthode permet de savoir si un popup de palier (hors bandeau d'annonce) est à l'écran lorsque un bandeau
-- attend son tour.
function Hud.isLevelPopupShown(): boolean
	return os.clock() < popupEndsAt
end

-- Cette méthode permet de recevoir un achat demandé par l'interface ; remplacée par init.client (envoi au serveur).
function Hud.onBuy(_kind: string) end

-- Cette méthode permet de faire voler du bouton au compteur l'argent des ventes attendues lorsque l'argent augmente de
-- `gain` ; les ventes trop anciennes (refusées par le serveur) sont oubliées.
local function flyExpected(gain: number)
	local now = os.clock()
	local left = gain
	local kept = {}
	-- Montant exact, ou vente arrivée avec le revenu de la seconde : le revenu seul ne fait pas voler une vente
	local income = stat("Income", 0)
	for pass = 1, 2 do
		kept = {}
		for _, expected in expectedGains do
			local fits = if pass == 1 then expected.amount == left else expected.amount + income == left
			if now > expected.untilTime then
				continue
			elseif seeded and fits and left > 0 then
				left -= expected.amount
				flyGain("Money", expected.amount, expected.from)
			else
				table.insert(kept, expected)
			end
		end
		expectedGains = kept
	end
end

-- Cette méthode permet de brancher une invite « Upgrade » du pad d'amélioration (active sur le pad de sa place tant que
-- le dernier équipement n'est pas atteint ; achat envoyé au serveur, refus annoncé si l'argent manque) lorsqu'elle
-- apparaît.
local function bindGearBuy(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	-- Cette méthode permet d'activer l'invite pour le propriétaire seulement lorsque le maximum ou la place changent.
	local function update()
		prompt.Enabled = prompt:GetAttribute("Slot") == player:GetAttribute("Slot") and not prompt:GetAttribute("Maxed")
	end
	prompt:GetAttributeChangedSignal("Maxed"):Connect(update)
	player:GetAttributeChangedSignal("Slot"):Connect(update)
	update()
	prompt.Triggered:Connect(function()
		local price = prompt:GetAttribute("Price")
		if prompt:GetAttribute("Slot") ~= player:GetAttribute("Slot") or type(price) ~= "number" then
			return
		end
		-- Argent réel (attribut) : le serveur valide sur lui, pas sur le compteur affiché
		if stat("Money", 0) >= price then
			Hud.onBuy("Gear")
		else
			Hud.popup({
				title = "NOT ENOUGH MONEY!",
				subtitle = "Next gear: " .. Format.money(price),
				colors = { Color3.fromRGB(255, 120, 110), C.red },
				rays = false,
				sparkles = false,
				duration = 1.6,
			})
			UIKit.playSound("Thud", 1.2)
		end
	end)
end

-- Cette méthode permet de brancher une invite « View all » du pad d'amélioration (active sur le pad de sa place,
-- ouvre la fenêtre Training Gear) lorsqu'elle apparaît.
local function bindGearView(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	-- Cette méthode permet d'activer l'invite pour le propriétaire seulement lorsque la place du joueur change.
	local function update()
		prompt.Enabled = prompt:GetAttribute("Slot") == player:GetAttribute("Slot")
	end
	player:GetAttributeChangedSignal("Slot"):Connect(update)
	update()
	prompt.Triggered:Connect(function()
		if prompt:GetAttribute("Slot") == player:GetAttribute("Slot") and not UIKit.isWindowOpen(windows.Shop) then
			toggle("Shop")
		end
	end)
end

-- Cette méthode permet de construire le HUD et de le brancher sur les attributs du joueur lorsque le client démarre ;
-- `onStop` arrête l'entraînement, `remotes` sert aux fenêtres de collection.
function Hud.init(localPlayer: Player, onStop: () -> (), remotes: Remotes.Remotes)
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
	-- Fenêtres de collection : « My Dummies » à gauche du bouton Dummies (marge 14 + bouton + 16)
	for name, frame in
		CollectionWindows.init(player, remotes, gui, 30 + BUTTON_SIZE, {
			toggle = toggle,
			expectGain = Hud.expectGain,
			popup = Hud.popup,
			dummiesButton = anchors.Dummies,
		})
	do
		windows[name] = frame
	end
	-- Boutique des mannequins à lancer (stand SHOP, popup « NEW DUMMY! »)
	windows.DummyShop = ThrowShop.init(player, remotes, gui, {
		popup = Hud.popup,
		money = function()
			return math.max(0, stat("Money", 0) - counters.Money.pending)
		end,
	}, function()
		UIKit.closeWindow(windows.DummyShop)
		Hud.refresh()
	end)
	-- Boutique Robux (bouton Shop du menu de gauche, #160) et minuteurs de ses boosts dans le HUD
	windows.Store = StoreWindow.init(player, remotes, gui, root, { popup = Hud.popup }, function()
		UIKit.closeWindow(windows.Store)
		Hud.refresh()
	end)
	player:GetAttributeChangedSignal("StarterEnds"):Connect(Hud.refresh)
	-- Fenêtre REBIRTH (bouton du menu de gauche)
	windows.Rebirth = RebirthWindow.init(player, remotes, gui, {
		popup = Hud.popup,
		money = function()
			return math.max(0, stat("Money", 0) - counters.Money.pending)
		end,
		reserveTop = Hud.reserveTop,
		screenFree = function()
			local lane = player:GetAttribute("LaneState")
			return seeded
				and (lane == nil or lane == "Ready")
				and player:GetAttribute("Action") ~= "Holding"
				and not Hud.isPopupShown()
				and Overlay.offer({ windowOpen = Hud.isWindowOpen(), bannerShown = os.clock() < bannerEndsAt })
		end,
	}, function()
		UIKit.closeWindow(windows.Rebirth)
		Hud.refresh()
	end)
	buildTrainBar(onStop)
	-- Pads d'amélioration à côté des appareils (#159)
	for tag, bind in { [GearPad.BUY_TAG] = bindGearBuy, [GearPad.VIEW_TAG] = bindGearView } do
		for _, prompt in CollectionService:GetTagged(tag) do
			bind(prompt)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	end
	-- Fenêtre fermée (fin de l'animation) : l'offre masquée pendant qu'elle était à l'écran revient
	for _, window in windows do
		window:GetPropertyChangedSignal("Visible"):Connect(Hud.refresh)
	end

	lastPower = stat("ThrowPower", GameConfig.START_POWER)
	lastMoney = stat("Money", 0)
	for _, attribute in { "GearTier", "Income", "ThrowTier", "Draws" } do
		player:GetAttributeChangedSignal(attribute):Connect(Hud.refresh)
	end
	-- Cette méthode permet de réarmer les annonces de palier et les offres fermées lorsque la progression est remise à
	-- zéro (renaissance, ou DebugWipe : tirages revenus à 0).
	local function onProgressReset()
		if seeded then
			knownLevel = math.min(knownLevel, stat("TrainLevel", 1))
			knownTier = math.min(knownTier, stat("GearTier", 1))
			dismissedOffers = { Gear = {}, Dummy = {} }
		end
		Hud.refresh()
	end
	player:GetAttributeChangedSignal("Rebirths"):Connect(onProgressReset)
	player:GetAttributeChangedSignal("Draws"):Connect(function()
		if stat("Draws", 0) == 0 then
			onProgressReset()
		end
	end)
	player:GetAttributeChangedSignal("Money"):Connect(function()
		local money = stat("Money", 0)
		-- Le revenu de la base tombe tout seul chaque seconde (pas de « +N » volant) ; un achat entame les gains en vol
		if money < lastMoney then
			clampPending("Money", money)
			UIKit.pop(moneyLabel, 0.85) -- dépense : le compteur se tasse puis revient
		elseif money > lastMoney and #expectedGains > 0 then
			flyExpected(money - lastMoney)
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
			if seeded then
				knownLevel = math.min(knownLevel, level) -- niveau remis à zéro (renaissance)
			end
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
		-- L'EXP d'un niveau dépend de l'équipement (plafond de répétitions, Training.expForLevel)
		refreshTraining()
		local tier = stat("GearTier", 1)
		if tier <= knownTier then
			-- Équipement remis à zéro (renaissance) : les achats suivants s'annoncent de nouveau
			if seeded then
				knownTier = math.min(knownTier, tier)
			end
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
