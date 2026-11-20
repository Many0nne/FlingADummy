-- Fenêtres de la collection, calées sur Throw a Seed (09) : « My Dummies » (bouton Dummies, panneau à droite comme
-- « Mes plantes » : posés puis stock, rendu, rareté, $/s, badge PLACED, Place / Remove / Sell, « Place best » et total
-- $/s en haut), fenêtre de vente du stand SELL (vente à l'unité, « Sell all » par rareté en boutons colorés, deux clics
-- pour confirmer), Index (raretés en onglets à gauche comme 09, silhouettes noires et « ??? » pour les jamais obtenus,
-- compteur « x / 21 »). Invites du hub : stand SELL (ouvre la vente), pad d'achat de présentoir (refus affiché si
-- l'argent manque, popup à l'achat). Listes en grille verticale (ScrollingFrame Y, #45). Le client lit la collection
-- dans les attributs publiés par Server.BaseService et n'envoie que des intentions (remote Inventory).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))

local UIKit = require(script.Parent.UIKit)

type Entry = Collection.Entry

local C = UIKit.COLORS
local ROW_HEIGHT = 84
local ROW_COLOR = Color3.fromRGB(62, 67, 82)
local WELL_COLOR = Color3.fromRGB(28, 31, 40)
local CONFIRM_TIME = 2.5 -- s pour confirmer un « Sell all » (deuxième clic)
local INDEX_CELL = Vector2.new(152, 232)

export type Hooks = {
	toggle: (name: string) -> (), -- ouvre ou ferme une fenêtre du HUD (et ferme les autres)
	expectGain: (amount: number, from: Vector2) -> (), -- argent attendu d'une vente : « +$N » qui vole au compteur
	popup: (options: UIKit.PopupOptions) -> (), -- popup de palier (« NEW DISPLAY! »)
	dummiesButton: GuiObject, -- bouton Dummies (pastille « ! » : un mannequin du stock peut être posé)
}

-- Ligne affichée (inventaire ou vente) : mannequin courant et éléments à mettre à jour
type RowUI = {
	frame: Frame,
	viewport: ViewportFrame,
	name: TextLabel,
	info: TextLabel,
	income: TextLabel,
	count: TextLabel,
	placed: Frame,
	primary: TextButton?,
	sell: TextButton,
	entry: Entry,
	display: number?,
}

type IndexCell = {
	frame: Frame,
	viewport: ViewportFrame,
	odds: TextLabel,
	name: TextLabel,
	best: TextLabel,
	check: TextLabel,
}

local CollectionWindows = {}

local player: Player
local remotes: Remotes.Remotes
local hooks: Hooks
local frames: { [string]: Frame } = {}
local meshed: boolean? = nil -- forme (maillée ou blocs) des rendus 3D déjà construits
-- Inventaire
local inventoryList: ScrollingFrame
local inventoryRows: { [string]: RowUI } = {}
local summaryLabel: TextLabel
local totalLabel: TextLabel
local placeBestButton: TextButton
local inventoryEmpty: TextLabel
-- Vente
local sellList: ScrollingFrame
local sellRows: { [string]: RowUI } = {}
local sellEmpty: TextLabel
local rarityButtons: { TextButton } = {}
local confirmRarity: number? = nil
local confirmUntil = 0
-- Index
local indexTab = 1
local indexTabs: { TextButton } = {}
local indexCells: { IndexCell } = {}
local indexGrid: ScrollingFrame
local indexTitle: TextLabel
local indexFill: Frame
local indexCount: TextLabel
local indexFooter: TextLabel
local indexShown: string? = nil -- onglet et découvertes des rendus construits
local knownDisplays: number? = nil

-- Cette méthode permet de relire la collection du joueur (stock, base, présentoirs achetés, Index) dans ses attributs
-- lorsque une fenêtre ou la pastille se rafraîchissent ; même forme que les données du serveur (Inventory.Data).
local function state(): Inventory.Data
	return {
		base = Inventory.decodeBase(player:GetAttribute("BaseDummies")),
		displays = (player:GetAttribute("Displays") :: number?) or GameConfig.DISPLAY_START,
		stock = Inventory.decodeList(player:GetAttribute("Stock")),
		index = Inventory.decodeIndex(player:GetAttribute("DummyIndex")),
		last = nil,
	}
end

-- Cette méthode permet de savoir si la première pose du tutoriel reste à faire (à la main, sur un présentoir) lorsque
-- les boutons Place et « Place best » se rafraîchissent.
local function firstPlacePending(): boolean
	return Tutorial.current((player:GetAttribute("Tutorial") :: number?) or 0) == "Place"
end

-- Cette méthode permet d'habiller un bouton (texte, couleur) et de le rendre inerte ou non lorsque sa ligne se
-- rafraîchit.
local function setButton(button: TextButton, text: string, color: Color3, enabled: boolean)
	button.Text = text
	button.BackgroundColor3 = if enabled then color else C.locked
	button:SetAttribute("Disabled", not enabled)
end

-- Cette méthode permet d'envoyer une action de collection au serveur lorsque le joueur clique un bouton.
local function send(action: string, arg: any)
	remotes.Inventory:FireServer(action, arg)
end

-- Cette méthode permet de vendre un mannequin (ou une rareté) en annonçant l'argent attendu, qui volera du bouton au
-- compteur quand le serveur l'aura crédité, lorsque le joueur clique Sell.
local function sellFrom(button: GuiObject, amount: number, action: string, arg: any)
	hooks.expectGain(amount, button.AbsolutePosition + button.AbsoluteSize / 2)
	UIKit.playSound("Cash")
	send(action, arg)
end

-- Cette méthode permet de construire une liste défilante verticale de lignes dans `parent` lorsque une fenêtre est
-- construite.
local function verticalList(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local list = UIKit.create("ScrollingFrame", {
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.white,
		ZIndex = 11,
		Parent = parent,
	})
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = list,
	})
	UIKit.create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = list,
	})
	return list
end

-- Cette méthode permet de construire une ligne de mannequin (rendu dans un puits sombre, badge PLACED, nombre de
-- doublons, nom, rareté et taille, $/s, boutons à droite) comme les lignes de « Mes plantes » (09) lorsque une liste
-- montre un mannequin de plus ; `withPrimary` ajoute le bouton Place / Remove au-dessus de Sell.
local function newRow(list: ScrollingFrame, entry: Entry, withPrimary: boolean): RowUI
	local frame = UIKit.create("Frame", {
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		BackgroundColor3 = ROW_COLOR,
		ZIndex = 12,
		Parent = list,
	})
	UIKit.corner(frame, 10)
	UIKit.outline(frame, 3)
	local well = UIKit.create("Frame", {
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.fromOffset(70, 70),
		BackgroundColor3 = WELL_COLOR,
		ZIndex = 13,
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
		ZIndex = 14,
		Parent = well,
	})
	-- « DANS LE JARDIN ✓ » de la référence : badge vert en bas du rendu
	local placed = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(66, 20),
		BackgroundColor3 = C.green,
		Visible = false,
		ZIndex = 15,
		Parent = well,
	})
	UIKit.corner(placed, 6)
	UIKit.outline(placed, 2)
	UIKit.text({ Size = UDim2.fromScale(1, 1), Text = "PLACED", TextSize = 15, ZIndex = 16, Parent = placed })
	local count = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 0),
		Size = UDim2.fromOffset(40, 22),
		TextSize = 20,
		TextColor3 = C.yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 16,
		Parent = well,
	})
	local textWidth = UDim2.new(1, -226, 0, 0)
	local name = UIKit.text({
		Position = UDim2.fromOffset(88, 6),
		Size = textWidth + UDim2.fromOffset(0, 26),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 13,
		Parent = frame,
	})
	local info = UIKit.text({
		Position = UDim2.fromOffset(88, 33),
		Size = textWidth + UDim2.fromOffset(0, 18),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = frame,
	})
	local income = UIKit.text({
		Position = UDim2.fromOffset(88, 53),
		Size = textWidth + UDim2.fromOffset(0, 24),
		TextSize = 21,
		TextColor3 = C.green,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = frame,
	})
	local row: RowUI
	local primary: TextButton? = nil
	if withPrimary then
		primary = UIKit.button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 7),
			Size = UDim2.fromOffset(122, 32),
			TextSize = 18,
			ZIndex = 13,
			Parent = frame,
		}, function()
			if row.display then
				send("Remove", row.display)
			else
				send("Place", Inventory.key(row.entry))
			end
		end)
	end
	local sell = UIKit.button({
		AnchorPoint = Vector2.new(1, if withPrimary then 0 else 0.5),
		Position = if withPrimary then UDim2.new(1, -8, 0, 45) else UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(122, if withPrimary then 32 else 40),
		TextSize = 18,
		ZIndex = 13,
		Parent = frame,
	}, function()
		if not row.display then
			sellFrom(row.sell, Inventory.sellValue(row.entry), "Sell", Inventory.key(row.entry))
		end
	end)
	row = {
		frame = frame,
		viewport = viewport,
		name = name,
		info = info,
		income = income,
		count = count,
		placed = placed,
		primary = primary,
		sell = sell,
		entry = entry,
		display = nil,
	}
	UIKit.showModel(viewport, DummyShape.buildVisual(1, Collection.variant(entry) :: any))
	return row
end

-- Cette méthode permet de donner la ligne « BIG · RARE » (taille si elle n'est pas normale, rareté) et sa couleur
-- lorsque une ligne ou une case nomme un mannequin.
local function rarityLine(entry: Entry): (string, Color3)
	local dummy = Collection.get(entry.id) :: Collection.Dummy
	local tier = Rarity.get(dummy.rarity)
	local size = Collection.SIZES[entry.size]
	local text = if size.name ~= "" then string.upper(size.name) .. " · " .. string.upper(tier.name) else tier.name
	return string.upper(text), tier.color
end

-- Cette méthode permet de mettre une ligne à jour (textes, badge, boutons selon qu'elle est posée ou en stock)
-- lorsque la collection change ; `data` sert à savoir où Place irait.
local function fillRow(row: RowUI, view: Inventory.Row, data: Inventory.Data)
	row.entry = view.entry
	row.display = view.display
	row.name.Text = Collection.label(view.entry)
	local line, color = rarityLine(view.entry)
	row.info.Text = line
	row.info.TextColor3 = color
	row.income.Text = Format.money(Collection.income(view.entry)) .. "/s"
	row.count.Text = if view.count > 1 then "x" .. view.count else ""
	row.placed.Visible = view.display ~= nil
	local price = Inventory.sellValue(view.entry)
	if view.display then
		setButton(row.sell, "SELL", C.red, false) -- un posé ne se vend pas : le retirer d'abord
	else
		-- Première pose du tutoriel : le mannequin gagné se pose, il ne se vend pas
		setButton(row.sell, "SELL " .. Format.money(price), C.red, not firstPlacePending())
	end
	local primary = row.primary
	if not primary then
		return
	end
	if view.display then
		setButton(primary, "REMOVE", C.blue, #data.stock < GameConfig.INVENTORY_MAX)
	elseif firstPlacePending() then
		setButton(primary, "PLACE", C.green, false) -- première pose : à la main, sur un présentoir
	elseif Inventory.autoTarget(data, view.entry) == nil then
		setButton(primary, "BASE FULL", C.green, false)
	else
		setButton(primary, "PLACE", C.green, true)
	end
end

-- Cette méthode permet d'aligner les lignes d'une liste sur `views` (lignes réutilisées par clé, rendus 3D construits
-- une seule fois, lignes en trop détruites) lorsque la collection change.
local function syncRows(
	pool: { [string]: RowUI },
	list: ScrollingFrame,
	views: { Inventory.Row },
	data: Inventory.Data,
	withPrimary: boolean
)
	local used: { [string]: boolean } = {}
	for order, view in views do
		local rowKey = (if view.display then "P" .. view.display .. "|" else "S") .. view.key
		local row = pool[rowKey]
		if not row then
			row = newRow(list, view.entry, withPrimary)
			pool[rowKey] = row
		end
		row.frame.LayoutOrder = order
		fillRow(row, view, data)
		used[rowKey] = true
	end
	for rowKey, row in pool do
		if not used[rowKey] then
			row.frame:Destroy()
			pool[rowKey] = nil
		end
	end
end

-- Cette méthode permet de rafraîchir la fenêtre « My Dummies » (compteurs, total $/s, « Place best », lignes) lorsque
-- la collection change ou que la fenêtre s'ouvre.
local function refreshInventory(data: Inventory.Data)
	local placed = 0
	for display = 1, data.displays do
		if data.base[display] then
			placed += 1
		end
	end
	summaryLabel.Text = string.format("IN YOUR BASE %d/%d    INVENTORY %d", placed, data.displays, #data.stock)
	totalLabel.Text = Format.perSecond(Inventory.income(data))
	-- « Place best » seulement s'il changerait quelque chose (essayé sur une copie)
	local probe = state()
	local useful = not firstPlacePending() and Inventory.placeBest(probe)
	setButton(placeBestButton, "PLACE BEST", C.orange, useful)
	local views = Inventory.rows(data.base, data.displays, data.stock)
	syncRows(inventoryRows, inventoryList, views, data, true)
	inventoryEmpty.Visible = #views == 0
end

-- Cette méthode permet de rafraîchir la fenêtre de vente (boutons « Sell all » par rareté, lignes du stock) lorsque
-- le stock change ou que la fenêtre s'ouvre.
local function refreshSell(data: Inventory.Data)
	local counts: { number } = {}
	local totals: { number } = {}
	for _, entry in data.stock do
		local rarity = (Collection.get(entry.id) :: Collection.Dummy).rarity
		counts[rarity] = (counts[rarity] or 0) + 1
		totals[rarity] = (totals[rarity] or 0) + Inventory.sellValue(entry)
	end
	if os.clock() > confirmUntil then
		confirmRarity = nil
	end
	for rarity, button in rarityButtons do
		local tier = Rarity.get(rarity)
		local count = counts[rarity] or 0
		local text = if confirmRarity == rarity
			then "SURE?\n" .. Format.money(totals[rarity] or 0)
			else string.upper(tier.name) .. "\nx" .. count
		setButton(button, text, tier.color, count > 0 and not firstPlacePending())
	end
	local views = Inventory.rows({}, 0, data.stock)
	syncRows(sellRows, sellList, views, data, false)
	sellEmpty.Visible = #views == 0
end

-- Cette méthode permet de rafraîchir l'Index (onglets et leurs compteurs, cases de la rareté choisie : rendu et nom,
-- ou silhouette noire et « ??? », meilleure taille, compteur « x / 21 ») lorsque l'Index change ou que l'onglet change.
local function refreshIndex(data: Inventory.Data)
	local found, total = 0, #Collection.DUMMIES
	local perRarity: { [number]: { found: number, total: number } } = {}
	for _, dummy in Collection.DUMMIES do
		local tally = perRarity[dummy.rarity] or { found = 0, total = 0 }
		perRarity[dummy.rarity] = tally
		tally.total += 1
		if data.index[dummy.id] then
			tally.found += 1
			found += 1
		end
	end
	for rarity, tab in indexTabs do
		local tally = perRarity[rarity] or { found = 0, total = 0 }
		tab.Text = string.format("%s  %d/%d", Rarity.get(rarity).name, tally.found, tally.total)
		local stroke = tab:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = if rarity == indexTab then C.white else C.ink
		stroke.Thickness = if rarity == indexTab then 4 else 3
	end
	local tier = Rarity.get(indexTab)
	local tally = perRarity[indexTab] or { found = 0, total = 0 }
	indexTitle.Text = tier.name
	indexTitle.TextColor3 = tier.color
	indexCount.Text = tally.found .. "/" .. tally.total
	indexFill.Size = UDim2.fromScale(if tally.total > 0 then tally.found / tally.total else 0, 1)
	indexFooter.Text = string.format("Unlocked: %d / %d", found, total)
	-- Cases : reconstruites seulement si l'onglet, les découvertes ou la forme des rendus changent
	local list: { Collection.Dummy } = {}
	local signature = { tostring(indexTab), tostring(meshed) }
	for _, dummy in Collection.DUMMIES do
		if dummy.rarity == indexTab then
			table.insert(list, dummy)
			table.insert(signature, dummy.id .. "=" .. tostring(data.index[dummy.id]))
		end
	end
	local key = table.concat(signature, ",")
	if key == indexShown then
		return
	end
	indexShown = key
	for _, cell in indexCells do
		cell.frame:Destroy()
	end
	table.clear(indexCells)
	for order, dummy in list do
		local best = data.index[dummy.id]
		local frame = UIKit.create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = WELL_COLOR,
			ZIndex = 12,
			Parent = indexGrid,
		})
		UIKit.corner(frame, 10)
		UIKit.outline(frame, 3)
		UIKit.create("UIGradient", {
			Color = ColorSequence.new(tier.color:Lerp(WELL_COLOR, 0.55), WELL_COLOR),
			Rotation = 90,
			Parent = frame,
		})
		local odds = UIKit.text({
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -40, 0, 20),
			Text = "1 IN " .. Format.short(Collection.odds({ id = dummy.id, size = 1 })),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 13,
			Parent = frame,
		})
		local check = UIKit.text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 2),
			Size = UDim2.fromOffset(28, 26),
			Text = if best then "✔" else "",
			TextSize = 24,
			TextColor3 = C.green,
			ZIndex = 13,
			Parent = frame,
		})
		local viewport = UIKit.create("ViewportFrame", {
			Position = UDim2.fromOffset(8, 28),
			Size = UDim2.new(1, -16, 0, 136),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(170, 170, 170),
			LightColor = Color3.new(1, 1, 1),
			LightDirection = Vector3.new(-1, -1.5, 1),
			-- Jamais obtenu : silhouette noire (référence 09)
			ImageColor3 = if best then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
			ZIndex = 13,
			Parent = frame,
		})
		local name = UIKit.text({
			Position = UDim2.fromOffset(4, 168),
			Size = UDim2.new(1, -8, 0, 26),
			Text = if best then dummy.name else "???",
			TextSize = 21,
			TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 13,
			Parent = frame,
		})
		local bestSize = if best then Collection.SIZES[best] else nil
		local bestLabel = UIKit.text({
			Position = UDim2.fromOffset(4, 196),
			Size = UDim2.new(1, -8, 0, 20),
			Text = if bestSize then "Best: " .. (if bestSize.name ~= "" then bestSize.name else "Normal") else "",
			TextSize = 16,
			TextColor3 = C.yellow,
			ZIndex = 13,
			Parent = frame,
		})
		UIKit.showModel(viewport, DummyShape.buildVisual(1, Collection.variant({ id = dummy.id, size = 1 }) :: any))
		table.insert(
			indexCells,
			{ frame = frame, viewport = viewport, odds = odds, name = name, best = bestLabel, check = check }
		)
	end
end

-- Cette méthode permet de mettre la pastille « ! » du bouton Dummies lorsque un mannequin du stock peut être posé
-- (présentoir acheté libre) et que la première pose du tutoriel est faite.
local function refreshBadge(data: Inventory.Data)
	local free = false
	for display = 1, data.displays do
		if not data.base[display] then
			free = true
			break
		end
	end
	UIKit.setBadge(hooks.dummiesButton, if free and #data.stock > 0 and not firstPlacePending() then "!" else nil)
end

-- Cette méthode permet de rafraîchir la pastille et les fenêtres de collection ouvertes lorsque la collection du
-- joueur change, qu'une fenêtre s'ouvre ou que les maillages arrivent.
function CollectionWindows.refresh()
	if not player then
		return
	end
	local data = state()
	refreshBadge(data)
	local visible = frames.Dummies.Visible or frames.Sell.Visible or frames.Index.Visible
	if not visible then
		return
	end
	-- Maillages arrivés : les rendus en blocs sont refaits
	local nowMeshed = DummyShape.isMeshed()
	if meshed ~= nowMeshed then
		meshed = nowMeshed
		for _, pool in { inventoryRows, sellRows } do
			for rowKey, row in pool do
				row.frame:Destroy()
				pool[rowKey] = nil
			end
		end
		indexShown = nil
	end
	if frames.Dummies.Visible then
		refreshInventory(data)
	end
	if frames.Sell.Visible then
		refreshSell(data)
	end
	if frames.Index.Visible then
		refreshIndex(data)
	end
end

-- Cette méthode permet de construire la fenêtre « My Dummies » (panneau à droite, à côté du bouton Dummies, comme
-- « Mes plantes » de 09) lorsque le HUD est construit.
local function buildInventory(gui: ScreenGui, rightInset: number)
	local window = UIKit.window(gui, {
		name = "Dummies",
		title = "My Dummies",
		icon = "dummies",
		colors = { Color3.fromRGB(255, 150, 20), Color3.fromRGB(255, 215, 50) },
		size = Vector2.new(500, 560),
	}, function()
		hooks.toggle("Dummies")
	end)
	window.frame.AnchorPoint = Vector2.new(1, 0.5)
	window.frame.Position = UDim2.new(1, -rightInset, 0.5, 0)
	frames.Dummies = window.frame
	local body = window.body
	summaryLabel = UIKit.text({
		Size = UDim2.new(0.62, 0, 0, 24),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = body,
	})
	totalLabel = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.38, 0, 0, 24),
		TextSize = 22,
		TextColor3 = C.green,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 12,
		Parent = body,
	})
	placeBestButton = UIKit.button({
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.orange,
		Text = "PLACE BEST",
		TextSize = 26,
		Shine = true,
		ZIndex = 12,
		Parent = body,
	}, function()
		send("PlaceBest")
	end)
	inventoryList = verticalList(body, UDim2.fromOffset(0, 84), UDim2.new(1, 0, 1, -84))
	inventoryEmpty = UIKit.text({
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 60),
		Text = "No dummies yet!\nThrow your dummy to win one.",
		TextSize = 22,
		ZIndex = 12,
		Visible = false,
		Parent = body,
	})
end

-- Cette méthode permet de construire la fenêtre de vente du stand SELL (boutons « Sell all » colorés par rareté, puis
-- le stock et ses prix) lorsque le HUD est construit.
local function buildSell(gui: ScreenGui)
	local window = UIKit.window(gui, {
		name = "Sell",
		title = "Sell Dummies",
		icon = "cash",
		colors = { Color3.fromRGB(220, 40, 50), Color3.fromRGB(255, 120, 60) },
		size = Vector2.new(680, 500),
	}, function()
		hooks.toggle("Sell")
	end)
	frames.Sell = window.frame
	local body = window.body
	UIKit.text({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "SELL ALL",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = body,
	})
	local strip = UIKit.create("Frame", {
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = body,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = strip,
	})
	local width = math.floor((656 - 6 * (#Rarity.LIST - 1)) / #Rarity.LIST)
	for rarity in Rarity.LIST do
		local button: TextButton
		button = UIKit.button({
			LayoutOrder = rarity,
			Size = UDim2.fromOffset(width, 50),
			TextSize = 15,
			ZIndex = 12,
			Parent = strip,
		}, function()
			-- Deux clics : le premier demande confirmation (« SURE? » et le total), le second vend
			if confirmRarity == rarity and os.clock() <= confirmUntil then
				confirmRarity = nil
				local total = 0
				for _, entry in state().stock do
					if (Collection.get(entry.id) :: Collection.Dummy).rarity == rarity then
						total += Inventory.sellValue(entry)
					end
				end
				sellFrom(button, total, "SellRarity", rarity)
			else
				confirmRarity = rarity
				confirmUntil = os.clock() + CONFIRM_TIME
				task.delay(CONFIRM_TIME + 0.05, CollectionWindows.refresh)
			end
			CollectionWindows.refresh()
		end)
		rarityButtons[rarity] = button
	end
	sellList = verticalList(body, UDim2.fromOffset(0, 86), UDim2.new(1, 0, 1, -86))
	sellEmpty = UIKit.text({
		Position = UDim2.fromOffset(0, 130),
		Size = UDim2.new(1, 0, 0, 60),
		Text = "Nothing to sell!\nPlaced dummies must be removed first.",
		TextSize = 22,
		ZIndex = 12,
		Visible = false,
		Parent = body,
	})
end

-- Cette méthode permet de construire l'Index (onglets de rareté à gauche, titre et barre « x/3 », grille des
-- mannequins de la rareté, total « Unlocked: x / 21 » en bas, comme l'Index de 09) lorsque le HUD est construit.
local function buildIndex(gui: ScreenGui)
	local window = UIKit.window(gui, {
		name = "Index",
		title = "Index",
		icon = "index",
		colors = { Color3.fromRGB(40, 110, 255), Color3.fromRGB(60, 210, 255) },
		size = Vector2.new(700, 470),
	}, function()
		hooks.toggle("Index")
	end)
	frames.Index = window.frame
	local body = window.body
	local tabs = UIKit.create("Frame", {
		Size = UDim2.new(0, 160, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = body,
	})
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabs,
	})
	for rarity, tier in Rarity.LIST do
		indexTabs[rarity] = UIKit.button({
			LayoutOrder = rarity,
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundColor3 = tier.color:Lerp(Color3.new(0, 0, 0), 0.25),
			TextSize = 18,
			ZIndex = 12,
			Parent = tabs,
		}, function()
			indexTab = rarity
			CollectionWindows.refresh()
		end)
	end
	local right = UIKit.create("Frame", {
		Position = UDim2.fromOffset(172, 0),
		Size = UDim2.new(1, -172, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = body,
	})
	indexTitle = UIKit.text({
		Size = UDim2.new(0.5, 0, 0, 30),
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = right,
	})
	local bar = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 3),
		Size = UDim2.fromOffset(180, 24),
		BackgroundColor3 = Color3.fromRGB(28, 31, 40),
		ZIndex = 12,
		Parent = right,
	})
	UIKit.corner(bar, 6)
	UIKit.outline(bar, 2)
	indexFill = UIKit.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.green,
		ZIndex = 13,
		Parent = bar,
	})
	UIKit.corner(indexFill, 6)
	indexCount = UIKit.text({ Size = UDim2.fromScale(1, 1), TextSize = 18, ZIndex = 14, Parent = bar })
	indexGrid = UIKit.create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 1, -82),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.white,
		ZIndex = 11,
		Parent = right,
	})
	UIKit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(INDEX_CELL.X, INDEX_CELL.Y),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = indexGrid,
	})
	local footer = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Color3.fromRGB(28, 31, 40),
		ZIndex = 12,
		Parent = right,
	})
	UIKit.corner(footer, 8)
	UIKit.outline(footer, 2)
	UIKit.icon("index", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 13,
		Parent = footer,
	})
	indexFooter = UIKit.text({
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -52, 1, 0),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = footer,
	})
end

-- Cette méthode permet de brancher une invite de pad d'achat de présentoir (active seulement sur le pad de sa base
-- tant que le maximum n'est pas atteint, prix affiché, achat envoyé au serveur, refus annoncé si l'argent manque)
-- lorsqu'elle apparaît.
local function bindPad(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	-- Cette méthode permet d'activer l'invite pour le propriétaire seulement et d'y afficher le prix lorsque le prix,
	-- le maximum ou la place du joueur changent.
	local function update()
		local price = prompt:GetAttribute("Price")
		prompt.Enabled = prompt:GetAttribute("Slot") == player:GetAttribute("Slot") and not prompt:GetAttribute("Maxed")
		prompt.ObjectText = if type(price) == "number" then Format.money(price) else ""
	end
	for _, attribute in { "Maxed", "Price" } do
		prompt:GetAttributeChangedSignal(attribute):Connect(update)
	end
	player:GetAttributeChangedSignal("Slot"):Connect(update)
	update()
	prompt.Triggered:Connect(function()
		local price = prompt:GetAttribute("Price")
		local money = (player:GetAttribute("Money") :: number?) or 0
		if prompt:GetAttribute("Slot") ~= player:GetAttribute("Slot") or type(price) ~= "number" then
			return
		end
		if money >= price then
			send("BuyDisplay")
		else
			hooks.popup({
				title = "NOT ENOUGH MONEY!",
				subtitle = "Next display: " .. Format.money(price),
				colors = { Color3.fromRGB(255, 120, 110), C.red },
				rays = false,
				sparkles = false,
				duration = 1.6,
			})
			UIKit.playSound("Thud", 1.2)
		end
	end)
end

-- Cette méthode permet d'ouvrir la fenêtre de vente lorsque le joueur déclenche l'invite du stand SELL.
local function bindSellStand(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function()
			if not UIKit.isWindowOpen(frames.Sell) then
				hooks.toggle("Sell")
			end
		end)
	end
end

-- Cette méthode permet d'annoncer un présentoir acheté (popup « NEW DISPLAY! ») lorsque le nombre de présentoirs
-- augmente après le chargement.
local function onDisplays()
	local displays = player:GetAttribute("Displays")
	if typeof(displays) ~= "number" then
		return
	end
	if knownDisplays and displays > knownDisplays then
		hooks.popup({ title = "NEW DISPLAY!", subtitle = "Your base now has " .. displays .. " displays" })
		UIKit.playSound("LevelUp", 1.2)
	end
	knownDisplays = displays
end

-- Cette méthode permet de construire les fenêtres de collection et de brancher les invites du hub et les attributs de
-- la collection lorsque le HUD est construit ; renvoie les fenêtres (Dummies, Sell, Index) que le HUD ouvre et ferme.
-- `rightInset` : marge à droite du panneau « My Dummies » (à gauche du bouton Dummies).
function CollectionWindows.init(
	localPlayer: Player,
	createdRemotes: Remotes.Remotes,
	gui: ScreenGui,
	rightInset: number,
	createdHooks: Hooks
): { [string]: Frame }
	player = localPlayer
	remotes = createdRemotes
	hooks = createdHooks
	buildInventory(gui, rightInset)
	buildSell(gui)
	buildIndex(gui)
	for _, attribute in { "Stock", "BaseDummies", "Displays", "DummyIndex", "Tutorial" } do
		player:GetAttributeChangedSignal(attribute):Connect(CollectionWindows.refresh)
	end
	player:GetAttributeChangedSignal("Displays"):Connect(onDisplays)
	onDisplays()
	for _, prompt in CollectionService:GetTagged(Collection.PAD_TAG) do
		bindPad(prompt)
	end
	CollectionService:GetInstanceAddedSignal(Collection.PAD_TAG):Connect(bindPad)
	for _, prompt in CollectionService:GetTagged(Collection.SELL_TAG) do
		bindSellStand(prompt)
	end
	CollectionService:GetInstanceAddedSignal(Collection.SELL_TAG):Connect(bindSellStand)
	CollectionWindows.refresh()
	return frames
end

return CollectionWindows
