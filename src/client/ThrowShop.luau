-- Boutique des mannequins à lancer (#14), calée sur le « Magasin de graines » de Throw a Seed (09) : bandeau rose,
-- une carte par mannequin teintée à sa couleur (nom, « 1.25x CHANCE » en jaune, rendu 3D, comportement en vol), bouton
-- EQUIPPED / EQUIP / prix (jaune s'il est abordable, rouge sinon) / cadenas pour ceux d'après. Ouverte par le stand
-- SHOP du hub ou le popup « NEW DUMMY! ». Le client n'envoie que des intentions (remote ThrowDummy), le serveur valide.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local HEADER = { Color3.fromRGB(255, 90, 150), Color3.fromRGB(215, 30, 95) } -- bandeau rose de 09
local AFFORDABLE = Color3.fromRGB(255, 200, 40) -- prix abordable (jaune, comme le « $1.2K » de 09)

export type Hooks = {
	popup: (options: UIKit.PopupOptions) -> (), -- popup de palier (« NEW DUMMY! », refus)
	money: () -> number, -- argent affiché (gains en vol pas encore arrivés exclus)
}

local ThrowShop = {}

local player: Player
local remotes: Remotes.Remotes
local hooks: Hooks
local frame: Frame
local cards: { UIKit.Card } = {}
local meshed: number? = nil -- étape des maillages des rendus déjà construits
local knownTier = math.huge -- mannequins possédés au chargement : les achats suivants s'annoncent

-- Cette méthode permet de lire les mannequins possédés et l'équipé (bornés au catalogue) lorsque la boutique se
-- rafraîchit ou qu'un bouton est cliqué.
local function levels(): (number, number)
	return ThrowDummies.sanitize(player:GetAttribute("ThrowTier"), player:GetAttribute("ThrowEquipped"))
end

-- Cette méthode permet de répondre au bouton de la carte `index` lorsque le joueur clique : équiper un mannequin
-- possédé, acheter le suivant (refus annoncé si l'argent manque).
local function onAction(index: number)
	local owned, equipped = levels()
	local state = ThrowDummies.cardState(owned, equipped, index)
	if state == "Owned" then
		remotes.ThrowDummy:FireServer("Equip", index)
		UIKit.playSound("Click", 1.1)
	elseif state == "Buy" then
		local dummy = ThrowDummies.LIST[index]
		if hooks.money() >= dummy.cost then
			remotes.ThrowDummy:FireServer("Buy", index)
		else
			hooks.popup({
				title = "NOT ENOUGH MONEY!",
				subtitle = dummy.name .. ": " .. Format.money(dummy.cost),
				colors = { Color3.fromRGB(255, 120, 110), C.red },
				rays = false,
				sparkles = false,
				duration = 1.6,
			})
			UIKit.playSound("Thud", 1.2)
		end
	end
end

-- Cette méthode permet de (re)construire les rendus 3D des cartes lorsque la boutique s'ouvre pour la première fois
-- ou que les maillages publiés arrivent.
local function buildModels()
	local stage = DummyShape.meshStage()
	if meshed == stage then
		return
	end
	meshed = stage
	for index, card in cards do
		UIKit.showModel(
			card.viewport,
			DummyShape.buildVisual(1, ThrowDummies.variant(index, true) :: DummyShape.Variant)
		)
	end
end

-- Cette méthode permet d'habiller le bouton d'une carte (texte, couleur, actif ou inerte) lorsque la carte se
-- rafraîchit.
local function setAction(card: UIKit.Card, text: string, color: Color3, enabled: boolean)
	card.action.Text = text
	card.action.BackgroundColor3 = color
	card.action:SetAttribute("Disabled", not enabled)
end

-- Cette méthode permet de rafraîchir les cartes (équipé, possédé, prix jaune ou rouge, cadenas) lorsque l'argent, les
-- achats ou l'équipé changent, boutique ouverte.
function ThrowShop.refresh()
	if not frame or not frame.Visible then
		return
	end
	buildModels()
	local owned, equipped = levels()
	local money = hooks.money()
	for index, card in cards do
		local dummy = ThrowDummies.LIST[index]
		local state = ThrowDummies.cardState(owned, equipped, index)
		local stroke = card.frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = if state == "Equipped" then C.green else C.ink
		stroke.Thickness = if state == "Equipped" then 4 else 3
		if state == "Equipped" then
			setAction(card, "EQUIPPED", C.equipped, false)
		elseif state == "Owned" then
			setAction(card, "EQUIP", C.green, true)
		elseif state == "Buy" then
			setAction(card, Format.money(dummy.cost), if money >= dummy.cost then AFFORDABLE else C.red, true)
		else
			setAction(card, "🔒 " .. Format.money(dummy.cost), C.locked, false)
		end
	end
end

-- Cette méthode permet d'annoncer un mannequin acheté (popup « NEW DUMMY! », nom et chance) lorsque le nombre de
-- mannequins possédés augmente après le chargement.
local function onTier()
	if player:GetAttribute("DataReady") ~= true then
		return -- sauvegarde pas encore chargée : seed() retiendra la valeur lue
	end
	local owned = levels()
	if owned > knownTier then
		local dummy = ThrowDummies.get(owned)
		hooks.popup({
			title = "NEW DUMMY!",
			tag = "NEW!",
			subtitle = dummy.name .. "  •  " .. Format.luck(dummy.luck) .. " CHANCE",
			subtitleColor = AFFORDABLE,
		})
		UIKit.playSound("LevelUp", 1.2)
	end
	knownTier = owned
end

-- Cette méthode permet de construire la fenêtre de la boutique (fermée) et de la brancher sur les attributs du joueur
-- lorsque le HUD est construit ; renvoie son cadre (ouvert et fermé par le HUD), `onClose` ferme la fenêtre.
function ThrowShop.init(
	localPlayer: Player,
	createdRemotes: Remotes.Remotes,
	gui: ScreenGui,
	createdHooks: Hooks,
	onClose: () -> ()
): Frame
	player = localPlayer
	remotes = createdRemotes
	hooks = createdHooks
	-- Quatre cartes visibles, la suite défile (comme les cinq graines de 09)
	local window = UIKit.window(gui, {
		name = "DummyShop",
		title = "Dummy Shop",
		icon = "shop",
		colors = HEADER,
		size = Vector2.new(880, 440),
	}, onClose)
	frame = window.frame
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
		Parent = window.body,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = row,
	})
	UIKit.create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = row })
	for index, dummy in ThrowDummies.LIST do
		local card = UIKit.card(row, index, function()
			onAction(index)
		end)
		card.title.Text = dummy.name
		card.rarity.Text = Format.luck(dummy.luck) .. " CHANCE"
		card.rarity.TextColor3 = AFFORDABLE
		card.stat.Text = dummy.behavior
		-- Carte teintée à la couleur du mannequin, claire en haut (cartes de couleur des graines de 09)
		local gradient = card.frame:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(dummy.card:Lerp(Color3.new(1, 1, 1), 0.45), dummy.card)
		end
		cards[index] = card
	end
	for _, attribute in { "ThrowTier", "ThrowEquipped", "Money" } do
		player:GetAttributeChangedSignal(attribute):Connect(ThrowShop.refresh)
	end
	-- Cette méthode permet de retenir les mannequins possédés au chargement lorsque les données du joueur sont prêtes
	-- (les valeurs sauvegardées ne s'annoncent pas, seuls les achats suivants).
	local function seed()
		knownTier = levels()
	end
	if player:GetAttribute("DataReady") == true then
		seed()
	end
	player:GetAttributeChangedSignal("DataReady"):Connect(seed)
	player:GetAttributeChangedSignal("ThrowTier"):Connect(onTier)
	return frame
end

return ThrowShop
