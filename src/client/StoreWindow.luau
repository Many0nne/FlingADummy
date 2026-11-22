-- Boutique Robux (#160), calée sur la « Boutique » de Throw a Seed (09) : bandeau rose à icône cadeau, une seule liste
-- qui défile (Packs, Passes, Boosts, Cash), chaque section titrée avec sa pastille (« Yours forever »), cartes à
-- vignette colorée (icône dessinée, emoji de repli), nom, effet et bouton violet au prix en Robux ; colonne d'onglets à droite qui font défiler
-- jusqu'à leur section (ancres). Pack de démarrage à compte à rebours, passes possédés (OWNED), boosts en cours (minuteur
-- sur la vignette), montant de l'argent rapide au revenu du moment. Achat : invite Roblox (identifiant créé) ; article
-- pas encore créé sur l'expérience (identifiant 0) : simulé par le serveur en Studio, bouton inerte ailleurs. Popups
-- d'achat attribué et de chance du serveur ; minuteurs des boosts dans le HUD (badges calés sur la bannière CHANCE).
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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
local PACK_HEIGHT = 150

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
local tabs: { [string]: TextButton } = {}
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

-- Cette méthode permet de poser la vignette colorée d'un article (dégradé, icône au centre) lorsque une carte se
-- construit ; renvoie la vignette.
local function tile(parent: Instance, item: Store.Item, props: { [string]: any }): Frame
	local options: { [string]: any } = { BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 13, Parent = parent }
	for key, value in props do
		options[key] = value
	end
	local box = UIKit.create("Frame", options)
	UIKit.corner(box, 8)
	UIKit.outline(box, 2)
	UIKit.create(
		"UIGradient",
		{ Color = ColorSequence.new(item.colors[1], item.colors[2]), Rotation = 90, Parent = box }
	)
	UIKit.icon(item.art, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		ZIndex = 14,
		Parent = box,
	}, item.icon)
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
			BackgroundColor3 = Color3.fromRGB(46, 40, 64),
			ZIndex = 12,
			Parent = holder,
		})
		UIKit.corner(card, 10)
		UIKit.outline(card, 3)
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

-- Cette méthode permet de poser la carte large du pack de démarrage (vignette, contenu, compte à rebours, prix barré,
-- remise) et le message qui la remplace une fois l'offre passée lorsque la liste se construit.
local function starterPack(order: number)
	local item = Store.get("StarterPack") :: Store.Item
	starterCard = UIKit.create("Frame", {
		Name = "StarterPack",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, PACK_HEIGHT),
		BackgroundColor3 = Color3.fromRGB(120, 30, 70),
		ZIndex = 12,
		Parent = list,
	})
	UIKit.corner(starterCard, 10)
	UIKit.outline(starterCard, 3)
	UIKit.shade(starterCard, Color3.fromRGB(255, 120, 170), Color3.fromRGB(160, 30, 90))
	tile(starterCard, item, { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(134, 134) })
	UIKit.text({
		Position = UDim2.fromOffset(154, 8),
		Size = UDim2.new(1, -340, 0, 34),
		Text = "STARTER PACK",
		TextSize = 30,
		StrokeThickness = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = starterCard,
	})
	local lines = {
		"🎲 " .. Store.STARTER.throws .. " Lucky Throws",
		"🍀 15 min 2x Luck",
		"💰 15 min 2x Money",
		"💵 " .. (Store.STARTER.minutes // 60) .. " h of cash",
	}
	for index, line in lines do
		UIKit.text({
			Position = UDim2.fromOffset(156 + ((index - 1) % 2) * 170, 46 + ((index - 1) // 2) * 28),
			Size = UDim2.fromOffset(166, 26),
			Text = line,
			TextSize = 18,
			StrokeThickness = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 13,
			Parent = starterCard,
		})
	end
	starterTimer = UIKit.text({
		Position = UDim2.fromOffset(154, 106),
		Size = UDim2.new(1, -340, 0, 30),
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 230, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = starterCard,
	})
	-- Prix barré (valeur du contenu) et remise, au-dessus du bouton violet
	local was = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(150, 28),
		Text = ROBUX .. " " .. Store.STARTER_WAS,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(230, 200, 210),
		ZIndex = 13,
		Parent = starterCard,
	})
	UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0, 3),
		BackgroundColor3 = C.red,
		BorderSizePixel = 0,
		Rotation = -8,
		ZIndex = 14,
		Parent = was,
	})
	local off = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 46),
		Size = UDim2.fromOffset(150, 26),
		BackgroundColor3 = Color3.fromRGB(255, 200, 40),
		ZIndex = 13,
		Parent = starterCard,
	})
	UIKit.corner(off, 6)
	UIKit.outline(off, 2)
	local percent = math.floor((1 - item.price / Store.STARTER_WAS) * 100 + 0.5)
	UIKit.text({ Size = UDim2.fromScale(1, 1), Text = percent .. "% OFF!", TextSize = 18, ZIndex = 14, Parent = off })
	local button = priceButton(starterCard, item, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -10),
		Size = UDim2.fromOffset(160, 46),
		TextSize = 28,
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
	for id, tab in tabs do
		local stroke = tab:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == current then Color3.new(1, 1, 1) else C.ink
		end
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
		UIKit.icon(section.art, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(46, 46),
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
		tabs[section.id] = tab
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
		starterTimer.Text = "⏰ Ends in " .. Store.clock(starter)
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
