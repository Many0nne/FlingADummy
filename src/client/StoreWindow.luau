-- Boutique Robux (#160), calée sur la « Boutique » de Throw a Seed (09) : bandeau rose à icône cadeau, une seule liste
-- qui défile (Packs, Passes, Boosts, Cash), chaque section titrée avec sa pastille (« Yours forever »), cartes à
-- vignette colorée (icône dessinée, emoji de repli), nom, effet et bouton violet au prix en Robux ; colonne d'onglets à
-- droite qui font défiler jusqu'à leur section (ancres). Pack de démarrage à compte à rebours, passes possédés (OWNED),
-- boosts en cours (minuteur sur la vignette), montant de l'argent rapide au revenu du moment. Achat : invite Roblox
-- (identifiant créé) ; article pas encore créé sur l'expérience (identifiant 0) : simulé par le serveur en Studio,
-- bouton inerte ailleurs. Popups d'achat attribué et de chance du serveur ; minuteurs des boosts dans le HUD (badges
-- calés sur la bannière CHANCE).
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Assets"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Store = require(Shared:WaitForChild("Store"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local HEADER = { Color3.fromRGB(255, 90, 150), Color3.fromRGB(215, 30, 95) } -- bandeau rose de 09
local PRICE = Color3.fromRGB(170, 60, 240) -- bouton de prix violet de 09
local OWNED = Color3.fromRGB(60, 190, 80)
local SOON = Color3.fromRGB(120, 122, 132) -- article pas encore créé (hors Studio)
local ROBUX = utf8.char(0xE002) -- icône Robux des polices Roblox
local WINDOW = Vector2.new(780, 470)
local TAB_WIDTH = 86
local GAP = 10
local CARD_HEIGHT = 196
local PACK_HEIGHT = 176
local CARD_DARK = Color3.fromRGB(28, 24, 40) -- bas des cartes, teintées en haut de la couleur de l'article
local GOLD_RIM = Color3.fromRGB(255, 232, 120) -- liseré doré de l'offre mise en avant (cadre de l'œuf de 02)
local BREATH = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local SPIN = TweenInfo.new(14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
-- Scintillement : apparaît et disparaît en 0,9 s, puis reste éteint 1,6 s (étincelles éparses, pas un clignotant)
local TWINKLE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, true, 1.6)
local TAB_DIM = Color3.fromRGB(44, 38, 62) -- onglets inactifs éteints vers le fond de la colonne (09)
local TAB_SWAP = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Dessin d'une vignette : icône (nom de UIKit.icon), emoji de repli, dégradé du fond
type Art = { art: string, icon: string, colors: { Color3 } }

export type Hooks = {
	popup: (options: UIKit.PopupOptions) -> (),
}

-- Carte d'un article : bouton de prix, vignette (minuteur d'un boost en cours), titre (montant de l'argent rapide)
type Card = { item: Store.Item, frame: Frame, button: TextButton, badge: TextLabel?, title: TextLabel }

local StoreWindow = {}

local player: Player
local remotes: Remotes.Remotes
local hooks: Hooks
local frame: Frame
local list: ScrollingFrame
local cards: { Card } = {}
local headers: { [string]: Frame } = {}
-- Onglets de la colonne de droite : bouton, couleur pleine de la section, halo derrière l'icône
local tabs: { [string]: { button: TextButton, color: Color3, halo: ImageLabel? } } = {}
local activeTab: string? = nil
local starterCard: Frame
local starterTimer: TextLabel
local starterEmpty: TextLabel
local timers: Frame
local timerBadges: { [string]: { frame: Frame, label: TextLabel } } = {}

-- Cette méthode permet de lire les passes du joueur (attribut Passes) lorsque les cartes ou les minuteurs se
-- rafraîchissent.
local function passes(): { [string]: boolean }
	return Store.decodePasses(player:GetAttribute("Passes"))
end

-- Cette méthode permet de donner les secondes restantes d'une fin en temps serveur (nil si passée ou absente) lorsque
-- un minuteur s'affiche.
local function left(ends: any): number?
	if type(ends) ~= "number" then
		return nil
	end
	local rest = ends - Workspace:GetServerTimeNow()
	return if rest > 0 then rest else nil
end

-- Cette méthode permet de répondre au bouton de prix d'un article lorsque le joueur clique : invite d'achat Roblox,
-- simulation en Studio si l'article n'est pas encore créé, sinon message « bientôt ».
local function buy(item: Store.Item)
	if item.kind == "Pass" and passes()[item.id] then
		return
	end
	if item.assetId ~= 0 then
		if Store.promptedByServer(item) then
			-- Offre unique : le serveur la revérifie avant d'ouvrir l'invite (#176)
			remotes.Store:FireServer("Buy", item.id)
		elseif item.kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, item.assetId)
		else
			MarketplaceService:PromptProductPurchase(player, item.assetId)
		end
		UIKit.playSound("Click", 1.1)
	elseif RunService:IsStudio() then
		remotes.Store:FireServer("Buy", item.id)
		UIKit.playSound("Click", 1.1)
	else
		hooks.popup({
			title = "COMING SOON!",
			subtitle = item.name,
			colors = { Color3.fromRGB(255, 120, 110), C.red },
			rays = false,
			sparkles = false,
			duration = 1.6,
		})
		UIKit.playSound("Thud", 1.2)
	end
end

-- Cette méthode permet de poser le bouton de prix violet (« R$ 249 ») d'une carte lorsque la fenêtre se construit.
local function priceButton(parent: Instance, item: Store.Item, props: { [string]: any }): TextButton
	local options: { [string]: any } = {
		BackgroundColor3 = PRICE,
		Text = ROBUX .. " " .. Format.thousands(item.price),
		TextSize = 24,
		ZIndex = 14,
		Parent = parent,
	}
	for key, value in props do
		options[key] = value
	end
	return UIKit.button(options, function()
		buy(item)
	end)
end

-- Cette méthode permet de poser l'icône d'une vignette avec son ombre portée, dans un cadre qui respire tant que la
-- boutique est ouverte, lorsque une vignette se construit ; `scale` : taille de l'icône rapportée à la hauteur.
local function artwork(parent: GuiObject, art: Art, scale: number, position: UDim2?): Frame
	local holder = UIKit.create("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 14,
		Parent = parent,
	})
	local icon = UIKit.icon(art.art, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale, scale),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 15,
		Parent = holder,
	}, art.icon)
	if icon:IsA("ImageLabel") then
		-- Ombre portée : même image en noir, décalée vers le bas à droite
		local shadow = icon:Clone()
		shadow.ImageColor3 = Color3.new(0, 0, 0)
		shadow.ImageTransparency = 0.6
		shadow.Position = UDim2.new(0.5, 4, 0.5, 5)
		shadow.ZIndex = 14
		shadow.Parent = holder
	end
	local breath = UIKit.create("UIScale", { Parent = holder })
	UIKit.loopWhileShown(frame, breath, { Scale = 1.07 }, BREATH, (#cards % 6) * 0.2)
	return holder
end

-- Cette méthode permet de poser la vignette colorée d'un article (dégradé, soleil et halo derrière l'icône, faisceaux
-- depuis le coin haut gauche, brillant, grosse icône à ombre portée) lorsque une carte se construit ; renvoie la
-- vignette. `compact` (mini-cartes du pack) : halo seul, sans faisceaux, pour ne pas charger une petite vignette.
local function tile(parent: Instance, art: Art, props: { [string]: any }, scale: number?, compact: boolean?): Frame
	local options: { [string]: any } = { BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 13, Parent = parent }
	for key, value in props do
		options[key] = value
	end
	local box = UIKit.create("Frame", options)
	UIKit.corner(box, 8)
	UIKit.outline(box, 2)
	UIKit.create("UIGradient", { Color = ColorSequence.new(art.colors[1], art.colors[2]), Rotation = 90, Parent = box })
	-- Lumière rognée à la vignette : soleil et halo derrière l'icône (02, fondus avant les coins), faisceaux en coin
	local light = UIKit.create("Frame", {
		Name = "Light",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 13,
		Parent = box,
	})
	if compact then
		UIKit.burst(light, { size = 1, alpha = 0.7, halo = 0.3, zIndex = 13 })
	else
		UIKit.burst(light, { size = 0.95, alpha = 0.55, halo = 0.3, zIndex = 13 })
		UIKit.sheen(light, 8, 0.4, 13)
	end
	UIKit.gloss(box, 8, 0.28)
	artwork(box, art, scale or 1.05)
	return box
end

-- Cette méthode permet de poser le titre d'une section (icône, nom, pastille sombre à droite) lorsque la liste se
-- construit ; renvoie la ligne (ancre de son onglet).
local function sectionHeader(section: any, order: number): Frame
	local row = UIKit.create("Frame", {
		Name = section.id .. "Header",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		ZIndex = 12,
		Parent = list,
	})
	UIKit.icon(section.art, {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 13,
		Parent = row,
	}, section.icon)
	UIKit.text({
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -220, 1, 0),
		Text = section.title,
		TextSize = 30,
		StrokeThickness = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = row,
	})
	local pill = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(160, 28),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		ZIndex = 13,
		Parent = row,
	})
	UIKit.corner(pill, 14)
	UIKit.text({ Size = UDim2.fromScale(1, 1), Text = section.note, TextSize = 17, ZIndex = 14, Parent = pill })
	return row
end

-- Cette méthode permet de poser une grille de cartes (`columns` par rangée) pour les articles d'une section lorsque la
-- liste se construit.
local function grid(items: { Store.Item }, order: number, columns: number)
	local holder = UIKit.create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 12,
		Parent = list,
	})
	UIKit.create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(GAP, GAP),
		-- 1 px de marge : l'arrondi des cellules en échelle renvoyait la dernière colonne à la ligne
		CellSize = UDim2.new(1 / columns, -GAP * (columns - 1) / columns - 1, 0, CARD_HEIGHT),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	for index, item in items do
		local card = UIKit.create("Frame", {
			Name = item.id,
			LayoutOrder = index,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 12,
			Parent = holder,
		})
		UIKit.corner(card, 10)
		UIKit.outline(card, 3)
		UIKit.create("UIGradient", {
			Color = ColorSequence.new(item.colors[2]:Lerp(CARD_DARK, 0.6), CARD_DARK),
			Rotation = 90,
			Parent = card,
		})
		local picture = tile(card, item, {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 84),
		})
		local badge: TextLabel? = nil
		if item.boost or item.id == "ServerLuck" or item.throws then
			-- Boost en cours (minuteur) ou lancers chanceux restants, en bas de la vignette
			badge = UIKit.text({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.new(1, -8, 0, 22),
				TextSize = 18,
				Visible = false,
				ZIndex = 15,
				Parent = picture,
			})
		end
		if item.best then
			local ribbon = UIKit.create("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 4, 0, -6),
				Size = UDim2.fromOffset(104, 22),
				Rotation = 8,
				BackgroundColor3 = Color3.fromRGB(255, 200, 40),
				ZIndex = 16,
				Parent = card,
			})
			UIKit.corner(ribbon, 6)
			UIKit.outline(ribbon, 2)
			UIKit.text({
				Size = UDim2.fromScale(1, 1),
				Text = "BEST VALUE",
				TextSize = 15,
				ZIndex = 17,
				Parent = ribbon,
			})
		end
		local title = UIKit.text({
			Position = UDim2.fromOffset(4, 94),
			Size = UDim2.new(1, -8, 0, 24),
			Text = item.name,
			TextSize = 22,
			TextScaled = true,
			TextWrapped = false,
			ZIndex = 13,
			Parent = card,
		})
		UIKit.create("UITextSizeConstraint", { MaxTextSize = 22, Parent = title })
		UIKit.text({
			Position = UDim2.fromOffset(6, 118),
			Size = UDim2.new(1, -12, 0, 32),
			Text = item.text,
			TextSize = 14,
			TextWrapped = true,
			StrokeThickness = 1,
			TextColor3 = Color3.fromRGB(220, 220, 235),
			ZIndex = 13,
			Parent = card,
		})
		local button = priceButton(card, item, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, 36),
		})
		table.insert(cards, { item = item, frame = card, button = button, badge = badge, title = title })
	end
end

-- Cette méthode permet de poser une mini-carte du contenu du pack de démarrage (étiquette, vignette, légende, comme
-- le « Pack de démarrage » de 09) lorsque la carte du pack se construit.
local function packItem(parent: Instance, index: number, art: Art, tag: string, caption: string)
	local box = UIKit.create("Frame", {
		Name = "Content" .. index,
		Position = UDim2.fromOffset(172 + (index - 1) * 78, 50),
		Size = UDim2.fromOffset(72, 116),
		BackgroundColor3 = Color3.fromRGB(70, 26, 30),
		BackgroundTransparency = 0.25,
		ZIndex = 13,
		Parent = parent,
	})
	UIKit.corner(box, 8)
	UIKit.outline(box, 2)
	UIKit.text({
		Position = UDim2.fromOffset(0, 1),
		Size = UDim2.new(1, 0, 0, 18),
		Text = tag,
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 230, 90),
		ZIndex = 14,
		Parent = box,
	})
	tile(box, art, { Position = UDim2.fromOffset(5, 20), Size = UDim2.fromOffset(62, 62), ZIndex = 14 }, 0.95, true)
	UIKit.text({
		Position = UDim2.fromOffset(2, 84),
		Size = UDim2.new(1, -4, 0, 30),
		Text = caption,
		TextSize = 14,
		TextWrapped = true,
		ZIndex = 14,
		Parent = box,
	})
end

-- Étincelles autour du cadeau du pack : position (fraction du cadre du cadeau), taille en px, décalage du scintillement
local TWINKLES = {
	{ x = 0.1, y = 0.16, size = 30, delay = 0 },
	{ x = 0.92, y = 0.1, size = 22, delay = 0.7 },
	{ x = 0.96, y = 0.76, size = 32, delay = 1.3 },
	{ x = 0.06, y = 0.82, size = 20, delay = 0.4 },
}

-- Cette méthode permet de faire scintiller quelques étincelles à quatre branches autour du cadeau, tant que la
-- boutique est ouverte, lorsque la carte du pack se construit ; rien en mouvement réduit.
local function twinkles(hero: Frame)
	local uri = Assets.uri(Assets.FX_TEXTURES.star)
	if not uri then
		return
	end
	for _, spot in TWINKLES do
		local star = UIKit.create("ImageLabel", {
			Name = "Twinkle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot.x, spot.y),
			Size = UDim2.fromOffset(spot.size, spot.size),
			BackgroundTransparency = 1,
			Image = uri,
			ImageColor3 = Color3.fromRGB(255, 250, 220),
			ZIndex = 16,
			Parent = hero,
		})
		local scale = UIKit.create("UIScale", { Scale = 0, Parent = star })
		UIKit.loopWhileShown(frame, scale, { Scale = 1 }, TWINKLE, spot.delay)
	end
end

-- Cette méthode permet de poser la carte large du pack de démarrage (cadeau sur rayons tournants, mini-cartes du
-- contenu, compte à rebours, prix barré, ruban de remise, cadre doré : « Pack de démarrage » de 09, « Œuf fantastique »
-- de 02) et le message qui la remplace une fois l'offre passée lorsque la liste se construit.
local function starterPack(order: number)
	local item = Store.get("StarterPack") :: Store.Item
	starterCard = UIKit.create("Frame", {
		Name = "StarterPack",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, PACK_HEIGHT),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 12,
		Parent = list,
	})
	UIKit.corner(starterCard, 12)
	UIKit.outline(starterCard, 3)
	UIKit.create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 196, 64), Color3.fromRGB(236, 92, 28)),
		Rotation = 90,
		Parent = starterCard,
	})
	local light = UIKit.create("Frame", {
		Name = "Light",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 12,
		Parent = starterCard,
	})
	local center = UDim2.fromOffset(88, PACK_HEIGHT / 2)
	-- Soleil chaud qui tourne lentement derrière le cadeau, halo crème au centre (« Œuf fantastique » de 02)
	local burst = UIKit.burst(light, {
		position = center,
		size = 0.62,
		color = Color3.fromRGB(255, 244, 196),
		alpha = 0.3,
		halo = 0.1,
		zIndex = 12,
	})
	UIKit.loopWhileShown(frame, burst, { Rotation = 360 }, SPIN)
	-- Bords assombris : la lumière se concentre sur le cadeau et le contenu (profondeur)
	local shadow = UIKit.light("vignette", {
		Size = UDim2.fromScale(1, 1),
		ImageColor3 = Color3.fromRGB(90, 20, 0),
		ImageTransparency = 0.35,
		ZIndex = 12,
		Parent = light,
	})
	if shadow then
		UIKit.corner(shadow, 12)
	end
	-- Liseré doré intérieur
	local rim = UIKit.create("Frame", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundTransparency = 1,
		ZIndex = 12,
		Parent = starterCard,
	})
	UIKit.corner(rim, 9)
	UIKit.outline(rim, 2.5, GOLD_RIM)
	local hero = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = starterCard,
	})
	artwork(hero, item, 1)
	twinkles(hero)
	local title = UIKit.text({
		Position = UDim2.fromOffset(172, 8),
		Size = UDim2.new(1, -340, 0, 38),
		Text = "STARTER PACK",
		TextSize = 34,
		StrokeThickness = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 14,
		Parent = starterCard,
	})
	UIKit.gradientText(title, Color3.new(1, 1, 1), Color3.fromRGB(255, 236, 120))
	local starter = Store.STARTER
	local contents: { { art: Art, tag: string, caption: string } } = {
		{ art = Store.get("LuckyThrow1") :: Store.Item, tag = "x" .. starter.throws, caption = "Lucky Throws" },
		{ art = Store.get("Luck2x") :: Store.Item, tag = (starter.boosts.Luck2 // 60) .. "m", caption = "2x Luck" },
		{ art = Store.get("Money2x") :: Store.Item, tag = (starter.boosts.Money // 60) .. "m", caption = "2x Money" },
		{ art = Store.get("CashSmall") :: Store.Item, tag = (starter.minutes // 60) .. "h", caption = "Cash" },
	}
	for index, content in contents do
		packItem(starterCard, index, content.art, content.tag, content.caption)
	end
	-- Colonne de droite : compte à rebours, prix barré, ruban de remise, bouton violet
	local pill = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(148, 28),
		BackgroundColor3 = Color3.fromRGB(40, 20, 26),
		ZIndex = 13,
		Parent = starterCard,
	})
	UIKit.corner(pill, 14)
	starterTimer = UIKit.text({
		Size = UDim2.fromScale(1, 1),
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 230, 90),
		ZIndex = 14,
		Parent = pill,
	})
	local was = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 40),
		Size = UDim2.fromOffset(148, 28),
		Text = ROBUX .. " " .. Store.STARTER_WAS,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(255, 225, 205),
		ZIndex = 13,
		Parent = starterCard,
	})
	UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.6, 0, 0, 3),
		BackgroundColor3 = C.red,
		BorderSizePixel = 0,
		Rotation = -8,
		ZIndex = 14,
		Parent = was,
	})
	local off = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0, 92),
		Size = UDim2.fromOffset(124, 28),
		Rotation = 8,
		BackgroundColor3 = C.red,
		ZIndex = 15,
		Parent = starterCard,
	})
	UIKit.corner(off, 6)
	UIKit.outline(off, 2.5)
	UIKit.gloss(off, 6, 0.3)
	local percent = math.floor((1 - item.price / Store.STARTER_WAS) * 100 + 0.5)
	UIKit.text({ Size = UDim2.fromScale(1, 1), Text = percent .. "% OFF!", TextSize = 20, ZIndex = 16, Parent = off })
	local button = priceButton(starterCard, item, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -10),
		Size = UDim2.fromOffset(148, 48),
		TextSize = 30,
	})
	UIKit.addShine(button)
	table.insert(cards, { item = item, frame = starterCard, button = button, title = was })
	starterEmpty = UIKit.text({
		Name = "NoPack",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 36),
		Text = "New packs coming soon!",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(200, 200, 215),
		Visible = false,
		ZIndex = 13,
		Parent = list,
	})
end

-- Cette méthode permet de faire défiler la liste jusqu'à la section `id` lorsque le joueur clique son onglet.
local function scrollTo(id: string)
	local header = headers[id]
	if not header then
		return
	end
	local target = header.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
	local maxY = math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)
	local goal = Vector2.new(0, math.clamp(target, 0, maxY))
	if UIKit.reducedMotion() then
		list.CanvasPosition = goal
	else
		TweenService:Create(list, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { CanvasPosition = goal }):Play()
	end
	UIKit.playSound("Click", 1.2)
end

-- Cette méthode permet d'allumer l'onglet actif (couleur pleine, cerné de blanc, agrandi, halo derrière l'icône) et
-- d'éteindre les autres (couleur assombrie, plus petits, comme les onglets de 09) lorsque la section affichée change.
local function setTab(tab: { button: TextButton, color: Color3, halo: ImageLabel? }, active: boolean)
	local button = tab.button
	local goal = {
		BackgroundColor3 = if active then tab.color else tab.color:Lerp(TAB_DIM, 0.55),
		Size = if active then UDim2.fromOffset(TAB_WIDTH - 8, 84) else UDim2.fromOffset(TAB_WIDTH - 16, 76),
	}
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if active then Color3.new(1, 1, 1) else C.ink
	end
	local still = UIKit.reducedMotion() or not frame.Visible
	if still then
		button.BackgroundColor3 = goal.BackgroundColor3
		button.Size = goal.Size
	else
		TweenService:Create(button, TAB_SWAP, goal):Play()
	end
	if tab.halo then
		local transparency = if active then 0.2 else 1
		if still then
			tab.halo.ImageTransparency = transparency
		else
			TweenService:Create(tab.halo, TAB_SWAP, { ImageTransparency = transparency }):Play()
		end
	end
end

-- Cette méthode permet d'éclairer l'onglet de la section affichée en haut de la liste lorsque le joueur fait défiler.
local function highlightTab()
	local current = Store.SECTIONS[1].id
	for _, section in Store.SECTIONS do
		local header = headers[section.id]
		if header and header.AbsolutePosition.Y - list.AbsolutePosition.Y <= 60 then
			current = section.id
		end
	end
	-- Bas de la liste atteint : la dernière section (trop courte pour monter en haut) est la section affichée
	if list.CanvasPosition.Y >= list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y - 2 then
		current = Store.SECTIONS[#Store.SECTIONS].id
	end
	if current == activeTab then
		return
	end
	activeTab = current
	for id, tab in tabs do
		setTab(tab, id == current)
	end
end

-- Cette méthode permet de poser la colonne d'onglets (Packs, Passes, Boosts, Cash) à droite de la liste lorsque la
-- fenêtre se construit.
local function buildTabs(body: Frame)
	local column = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, TAB_WIDTH, 1, 0),
		BackgroundColor3 = Color3.fromRGB(30, 26, 42),
		ZIndex = 12,
		Parent = body,
	})
	UIKit.corner(column, 10)
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = column,
	})
	UIKit.create("UIPadding", { PaddingTop = UDim.new(0, 6), Parent = column })
	for order, section in Store.SECTIONS do
		local tab = UIKit.button({
			Name = section.id .. "Tab",
			LayoutOrder = order,
			Size = UDim2.fromOffset(TAB_WIDTH - 12, 80),
			BackgroundColor3 = section.colors[2],
			Text = "",
			ZIndex = 13,
			Parent = column,
		}, function()
			scrollTo(section.id)
		end)
		-- Faisceaux en coin sur tous les onglets ; halo blanc derrière l'icône de l'onglet actif seulement
		UIKit.sheen(tab, 8, 0.55, 13)
		local halo = UIKit.light("halo", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 30),
			Size = UDim2.fromOffset(76, 76),
			ImageTransparency = 0.2,
			ZIndex = 13,
			Parent = tab,
		})
		UIKit.icon(section.art, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 30),
			Size = UDim2.fromOffset(48, 48),
			ZIndex = 14,
			Parent = tab,
		}, section.icon)
		UIKit.text({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -4, 0, 22),
			Text = section.title == "Gamepasses" and "Passes" or section.title,
			TextSize = 18,
			ZIndex = 14,
			Parent = tab,
		})
		tabs[section.id] = { button = tab, color = section.colors[2], halo = halo }
	end
end

-- Cette méthode permet de rafraîchir les cartes (OWNED, minuteurs des boosts, lancers chanceux, montants de l'argent
-- rapide, offre du pack de démarrage) lorsque la fenêtre est ouverte, chaque demi-seconde et quand les achats changent.
function StoreWindow.refresh()
	if not frame or not frame.Visible then
		return
	end
	local owned = passes()
	local income = (player:GetAttribute("Income") :: number?) or 0
	for _, card in cards do
		local item = card.item
		if item.kind == "Pass" then
			local has = owned[item.id] == true
			card.button.Text = if has then "OWNED" else ROBUX .. " " .. Format.thousands(item.price)
			card.button.BackgroundColor3 = if has
				then OWNED
				elseif item.assetId == 0 and not RunService:IsStudio() then SOON
				else PRICE
			card.button:SetAttribute("Disabled", has)
		elseif item.assetId == 0 and not RunService:IsStudio() then
			card.button.BackgroundColor3 = SOON
		end
		if item.minutes and item.section == "Cash" then
			card.title.Text = Format.money(Store.cash(item.minutes, income))
		end
		local badge = card.badge
		if badge then
			local rest = if item.boost
				then left(player:GetAttribute("Boost" .. item.boost))
				elseif item.id == "ServerLuck" then left(Workspace:GetAttribute("ServerLuckEnds"))
				else nil
			local lucky = (player:GetAttribute("LuckyThrows") :: number?) or 0
			if rest then
				badge.Text = "ACTIVE " .. Store.clock(rest)
				badge.Visible = true
			elseif item.throws and lucky > 0 then
				badge.Text = lucky .. " LEFT"
				badge.Visible = true
			else
				badge.Visible = false
			end
		end
	end
	local starter = left(player:GetAttribute("StarterEnds"))
	starterCard.Visible = starter ~= nil
	starterEmpty.Visible = starter == nil
	if starter then
		starterTimer.Text = "Ends in " .. Store.clock(starter)
	end
	highlightTab()
end

-- Cette méthode permet de poser un badge de minuteur du HUD (pilule colorée à contour, comme les badges de la bannière
-- CHANCE) lorsque les minuteurs se construisent.
local function timerBadge(id: string, color: Color3, order: number)
	local badge = UIKit.create("Frame", {
		Name = id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		Visible = false,
		ZIndex = 3,
		Parent = timers,
	})
	UIKit.corner(badge, 15)
	UIKit.outline(badge, 3)
	UIKit.create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = badge })
	local label = UIKit.text({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 20,
		ZIndex = 4,
		Parent = badge,
	})
	timerBadges[id] = { frame = badge, label = label }
end

-- Cette méthode permet de mettre à jour les minuteurs du HUD (boosts en cours, chance du serveur, lancers chanceux
-- restants) lorsque l'horloge de l'interface tourne.
local function refreshTimers()
	for kind, boost in Store.BOOSTS do
		local badge = timerBadges[kind]
		local rest = left(player:GetAttribute("Boost" .. kind))
		badge.frame.Visible = rest ~= nil
		if rest then
			badge.label.Text = string.format("%s x%d  %s", boost.label, boost.multiplier, Store.clock(rest))
		end
	end
	local server = timerBadges.ServerLuck
	local rest = left(Workspace:GetAttribute("ServerLuckEnds"))
	server.frame.Visible = rest ~= nil
	if rest then
		server.label.Text = string.format("SERVER LUCK x%d  %s", Store.SERVER_LUCK, Store.clock(rest))
	end
	local lucky = (player:GetAttribute("LuckyThrows") :: number?) or 0
	timerBadges.Lucky.frame.Visible = lucky > 0
	timerBadges.Lucky.label.Text = string.format("🎲 LUCKY THROW x%d  (%d)", Store.LUCKY_THROW, lucky)
end

-- Cette méthode permet de construire les minuteurs du HUD (colonne de badges en haut à gauche, sous les boutons de
-- Roblox, à droite de la colonne de boutons) dans `parent` (le HUD permanent, masqué pendant le vol) lorsque le HUD est construit.
local function buildTimers(parent: Instance)
	timers = UIKit.create("Frame", {
		Name = "StoreTimers",
		-- À droite de la colonne Index / Shop / Rebirth (92 px + marges), sous les boutons de Roblox
		Position = UDim2.fromOffset(120, 64),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = timers })
	for order, kind in Store.BOOST_ORDER do
		timerBadge(kind, Store.BOOSTS[kind].color, order)
	end
	timerBadge("ServerLuck", Color3.fromRGB(60, 160, 255), #Store.BOOST_ORDER + 1)
	timerBadge("Lucky", Color3.fromRGB(170, 90, 255), #Store.BOOST_ORDER + 2)
end

-- Cette méthode permet d'annoncer un achat attribué (popup à l'acheteur) ou une chance du serveur offerte par un
-- joueur (popup à tous) lorsque le serveur le signale.
local function onServer(kind: any, id: any, extra: any)
	local item = Store.get(id)
	if not item then
		return
	end
	if kind == "Granted" then
		local subtitle = item.name
		if type(extra) == "number" and extra > 0 then
			subtitle ..= "  •  +" .. Format.money(extra)
		end
		hooks.popup({ title = "THANK YOU!", tag = "NEW!", subtitle = subtitle })
		UIKit.playSound("LevelUp", 1.2)
	elseif kind == "ServerLuck" and type(extra) == "string" then
		hooks.popup({
			title = "SERVER LUCK!",
			subtitle = extra .. " gave everyone 2x luck!",
			colors = { Color3.fromRGB(140, 220, 255), Color3.fromRGB(40, 140, 255) },
		})
		UIKit.playSound("LevelUp", 1.1)
	end
	StoreWindow.refresh()
end

-- Cette méthode permet de construire la fenêtre Boutique (fermée) et les minuteurs du HUD (dans `hudRoot`), et de les
-- brancher sur les attributs du joueur lorsque le HUD est construit ; renvoie le cadre (ouvert et fermé par le HUD).
function StoreWindow.init(
	localPlayer: Player,
	createdRemotes: Remotes.Remotes,
	gui: ScreenGui,
	hudRoot: Instance,
	createdHooks: Hooks,
	onClose: () -> ()
): Frame
	player = localPlayer
	remotes = createdRemotes
	hooks = createdHooks
	local window = UIKit.window(gui, {
		name = "Store",
		title = "Shop",
		icon = "shop",
		colors = HEADER,
		size = WINDOW,
	}, onClose)
	frame = window.frame
	list = UIKit.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, -TAB_WIDTH - GAP, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 12,
		Parent = window.body,
	})
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	UIKit.create("UIPadding", {
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 2),
		Parent = list,
	})
	for index, section in Store.SECTIONS do
		local order = index * 10
		headers[section.id] = sectionHeader(section, order)
		if section.id == "Packs" then
			starterPack(order + 1)
		else
			grid(Store.section(section.id), order + 1, if section.id == "Cash" then 4 else 3)
		end
	end
	buildTabs(window.body)
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(highlightTab)
	buildTimers(hudRoot)
	for _, attribute in { "Passes", "LuckyThrows", "StarterEnds", "Income" } do
		player:GetAttributeChangedSignal(attribute):Connect(StoreWindow.refresh)
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(StoreWindow.refresh)
	remotes.Store.OnClientEvent:Connect(onServer)
	-- Horloge des minuteurs (HUD et cartes ouvertes) : deux fois par seconde suffit à un affichage en secondes
	task.spawn(function()
		while true do
			refreshTimers()
			StoreWindow.refresh()
			task.wait(0.5)
		end
	end)
	return frame
end

-- Cette méthode permet de savoir si le pack de démarrage est en offre lorsque le HUD pose la pastille du bouton Shop.
function StoreWindow.starterOffered(): boolean
	return player ~= nil and left(player:GetAttribute("StarterEnds")) ~= nil
end

return StoreWindow
