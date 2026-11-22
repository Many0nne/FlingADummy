-- Base du joueur : mannequins de collection gagnés au lancer (tirage « 1 en N », Shared.Collection), gardés en stock
-- (Shared.Inventory) et posés sur les présentoirs de sa base, qui versent leur revenu chaque seconde : seule source
-- d'argent du jeu. Chaque mannequin du stock est un outil du Backpack (Server.DummyTools) : équipé près d'un
-- présentoir libre, il se pose par l'invite « Place » ou le bouton AUTO ; sans mannequin équipé, AUTO pose le dernier
-- gagné (attribut `PendingDummy`), comme l'invite pendant la première pose du tutoriel. Un nouveau lancer l'ajoute au
-- stock, rien ne se perd. Fenêtres de collection (remote Inventory) : poser, retirer, vendre, « Place best ». Pad « 8 > 9 » devant la base : achat du présentoir suivant. Le serveur publie la
-- collection dans des attributs du joueur (Stock, BaseDummies, Displays, DummyIndex) que le client affiche. Les
-- mannequins posés sont construits par le serveur, visibles de tous. Boutique Robux (#160, Server.StoreService) : revenu
-- multiplié (2x Money, VIP, boost d'argent), base agrandie de 10 présentoirs (Big Base), badge VIP sur le texte.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local BackpackPlan = require(Shared.BackpackPlan)
local BaseLook = require(Shared.BaseLook)
local Collection = require(Shared.Collection)
local CourseLayout = require(Shared.CourseLayout)
local DummyShape = require(Shared.DummyShape)
local Format = require(Shared.Format)
local GameConfig = require(Shared.GameConfig)
local Inventory = require(Shared.Inventory)
local Rarity = require(Shared.Rarity)
local RevealPlan = require(Shared.RevealPlan)
local Store = require(Shared.Store)
local Tutorial = require(Shared.Tutorial)

local CourseBuilder = require(script.Parent.CourseBuilder)
local DummyTools = require(script.Parent.DummyTools)
local PlayerData = require(script.Parent.PlayerData)
local StoreService = require(script.Parent.StoreService)

type Slot = CourseBuilder.Slot

-- Mannequin gagné, tel que l'écran de tirage le révèle
export type Prize = {
	id: string,
	size: number,
	name: string, -- nom affiché, taille comprise (« Huge Gold Dummy »)
	rarity: number,
	income: number,
	odds: number, -- « 1 IN N »
	isNew: boolean,
}

local FEET = 3.82 -- du centre du torse au bas des pieds, échelle 1 (Shared.DummyShape)
local LOCKED_COLOR = Color3.fromRGB(120, 122, 132) -- présentoir pas encore acheté
local LOCKED_TRANSPARENCY = 0.55
-- Étiquette d'un mannequin posé (nom, $/s) : lue dans la base et devant elle, pas depuis la bande où elle encombrait
-- le texte de la base (#150 ; 120 studs avant)
local DISPLAY_LABEL_DISTANCE = 60
local SELL_BURST_REACH = 15 -- vente faite au stand SELL (invite à 10 studs, 4,5 devant l'émetteur) : éclat de pièces
local HEADSHOT = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150" -- portrait du propriétaire, au-dessus de sa base

local BaseService = {}

-- Mannequin construit sur un présentoir, avec la clé de son entrée (reconstruit seulement si elle change)
type Shown = { key: string, model: Model }

local slots: { Slot } = {}
local slotOf: { [Player]: Slot } = {}
-- Joueurs arrivés avant que SlotService leur donne une place : connexion à l'attribut Slot, coupée au départ
local waitingSlot: { [Player]: RBXScriptConnection } = {}
local shown: { [number]: { [number]: Shown } } = {} -- mannequins posés, par place puis présentoir
-- Palier visuel et présentoirs achetés de chaque base, pour le propriétaire chargé qui l'a (animation de construction
-- ou confettis seulement s'ils montent pour lui)
local styled: { [number]: { player: Player, tier: number, displays: number } } = {}
local rng = Random.new()

-- Cette méthode permet de construire le mannequin posé sur un présentoir (pièces ancrées sans collision, regard vers
-- l'entrée de la base, nom coloré et revenu au-dessus) lorsque la base est rendue.
local function buildDisplayed(entry: Collection.Entry, top: BasePart, facing: Vector3): Model
	local dummy = Collection.get(entry.id) :: Collection.Dummy
	local scale = Collection.displayScale(entry)
	local model = Instance.new("Model")
	model.Name = "Displayed_" .. entry.id
	local variant = Collection.variant(entry) :: DummyShape.Variant
	local parts = DummyShape.buildPieces(model, scale, variant)
	DummyShape.addAccessories(model, parts, scale, variant)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			for _, weld in p:GetChildren() do
				if weld:IsA("WeldConstraint") then
					weld:Destroy()
				end
			end
		end
	end
	model.PrimaryPart = parts.Torso
	local position = top.Position + Vector3.new(0, top.Size.Y / 2 + FEET * scale, 0)
	model:PivotTo(CFrame.lookAt(position, position + facing))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(8, 2.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4 * scale + 1.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = DISPLAY_LABEL_DISTANCE
	gui.Adornee = parts.Torso
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local color = Rarity.get(dummy.rarity).color:ToHex()
	label.Text = string.format(
		'<font color="#%s">%s</font>\n<font color="#5AEB50">%s</font>',
		color,
		Collection.label(entry),
		Format.money(Collection.income(entry)) .. "/s"
	)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = model
	return model
end

-- Cette méthode permet d'habiller un présentoir selon qu'il est acheté (couleur de la place) ou non (grisé, sans
-- invite ni objectif) lorsque la base est rendue ; ceux de Big Base (au-delà de DISPLAY_MAX) sont cachés et sans
-- collision quand la base n'est pas agrandie.
local function styleDisplay(slot: Slot, display: number, unlocked: boolean)
	local top = slot.base.displays[display]
	local pedestal = slot.base.pedestals[display]
	local hidden = display > CourseLayout.DISPLAY_MAX and not slot.base.big
	local open = unlocked and not hidden
	top.Color = if open then slot.color else LOCKED_COLOR
	top.Transparency = if hidden then 1 elseif open then 0 else LOCKED_TRANSPARENCY
	pedestal.Transparency = if hidden then 1 elseif open then 0 else LOCKED_TRANSPARENCY
	pedestal.CanCollide = not hidden
	top.CanCollide = not hidden
	top:SetAttribute("Locked", if open then nil else true)
end

-- Cette méthode permet d'afficher sur le pad d'achat le présentoir suivant et son prix (« 8 > 9 », « $450K »), ou MAX,
-- lorsque la base change ; le client n'active l'invite que pour le propriétaire tant que le maximum n'est pas atteint.
local function stylePad(slot: Slot, displays: number?, bonus: number?)
	local pad = slot.base.pad
	local price = if displays then Inventory.displayPrice(displays) else nil
	-- Big Base : les présentoirs offerts comptent dans « 18 > 19 » (le prix reste celui du prochain acheté)
	local count = (displays or GameConfig.DISPLAY_START) + (bonus or 0)
	if displays and not price then
		pad.title.Text = "MAX"
		pad.price.Text = count .. " / " .. (CourseLayout.DISPLAY_MAX + (bonus or 0))
	else
		pad.title.Text = count .. " > " .. (count + 1)
		pad.price.Text = Format.money(price or Inventory.displayPrice(count) or 0)
	end
	pad.prompt:SetAttribute("Price", price)
	pad.prompt:SetAttribute("Maxed", if displays and not price then true else nil)
end

-- Cette méthode permet d'afficher au-dessus de la base le portrait, le nom, le revenu, le record et la Throw Power de
-- son propriétaire (« EMPTY BASE » sans lui) lorsque la base change, qu'il arrive, part, ou que sa puissance ou son
-- record change.
local function updateLabel(slot: Slot, player: Player?)
	local ready = player ~= nil and player:GetAttribute("DataReady") == true
	local text = BaseLook.label(
		if player then player.DisplayName else nil,
		if ready and player then player:GetAttribute("Income") :: number? else 0,
		if ready and player then player:GetAttribute("ThrowPower") :: number? else nil,
		if ready and player then player:GetAttribute("Rebirths") :: number? else nil,
		if ready and player then player:GetAttribute("BestDistance") :: number? else nil,
		ready and player ~= nil and Store.decodePasses(player:GetAttribute("Passes")).VIP == true
	)
	local label = slot.base.label
	label.title.Text = text.title
	label.income.Text = text.income
	label.best.Text = text.best
	label.power.Text = text.power
	-- Joueurs de test de Studio (UserId négatif) : pas de portrait
	local portrait = player ~= nil and player.UserId > 0
	label.avatar.Visible = portrait
	label.avatar.Image = if player and portrait then string.format(HEADSHOT, player.UserId) else ""
end

-- Cette méthode permet d'habiller la base au palier de ses présentoirs achetés lorsque la base est rendue ; achat qui
-- monte de palier : animation de construction (confettis à la fin, Client.BaseFx), autre achat : confettis tout de suite.
local function styleTier(slot: Slot, player: Player?, ready: boolean, displays: number)
	local tier = BaseLook.baseTier(displays)
	local previous = styled[slot.index]
	local bought = ready and player ~= nil and previous ~= nil and previous.player == player
	local upgrade = bought and previous ~= nil and tier > previous.tier
	if ready and player then
		styled[slot.index] = { player = player, tier = tier, displays = displays }
	else
		styled[slot.index] = nil
	end
	local animated = CourseBuilder.styleBase(slot, tier, upgrade) and upgrade
	if bought and not animated and previous and displays > previous.displays then
		CourseBuilder.celebrate(slot.base.burst)
	end
end

-- Cette méthode permet de reconstruire les mannequins posés d'une place (vide si personne ne l'occupe), d'habiller ses
-- présentoirs, son pad et son palier visuel, et d'afficher au-dessus le texte de la base lorsque la base change, que
-- son joueur arrive ou part, ou que les maillages arrivent (`force` : tout reconstruire).
local function render(slot: Slot, player: Player?, force: boolean?)
	local current: { [number]: Shown } = shown[slot.index] or {}
	shown[slot.index] = current
	local data = if player then PlayerData.collection(player) else nil
	local ready = player ~= nil and data ~= nil and player:GetAttribute("DataReady") == true
	local displays = if ready and data then data.displays else GameConfig.DISPLAY_START
	local capacity = if ready and data then Inventory.capacity(data) else displays
	-- Big Base : base agrandie avant l'habillage du palier (clôture refaite à la bonne taille)
	CourseBuilder.setBaseBig(slot, ready and data ~= nil and data.bonus > 0)
	styleTier(slot, player, ready, displays)
	for display, top in slot.base.displays do
		local unlocked = display <= capacity
		styleDisplay(slot, display, unlocked)
		local entry = if ready and data and unlocked then data.base[display] else nil
		local key = if entry then Inventory.key(entry) else nil
		local existing = current[display]
		if existing and (force or existing.key ~= key) then
			existing.model:Destroy()
			current[display] = nil
		end
		if entry and not current[display] then
			local model = buildDisplayed(entry, top, slot.base.facing)
			model.Parent = slot.base.model
			current[display] = { key = key :: string, model = model }
		end
		-- Lu par le client : invite « Place » seulement sur les présentoirs achetés libres ; un présentoir libre est aussi
		-- la cible de l'objectif « Place your dummy! » (flèche et chevrons du tutoriel)
		top:SetAttribute("Occupied", if entry then true else nil)
		top:SetAttribute("Objective", if ready and unlocked and not entry then "Place" else nil)
	end
	stylePad(slot, if ready and data then data.displays else nil, if ready and data then data.bonus else nil)
	if ready and data and player then
		player:SetAttribute("Income", Inventory.income(data) * StoreService.incomeMultiplier(player))
	end
	updateLabel(slot, player)
end

-- Cette méthode permet de savoir si la première pose du tutoriel reste à faire (elle se fait à la main, sur un
-- présentoir) lorsque le joueur demande AUTO, Place ou « Place best ».
local function firstPlacePending(player: Player): boolean
	return Tutorial.current((player:GetAttribute("Tutorial") :: number?) or 0) == "Place"
end

-- Cette méthode permet de rendre la base d'un joueur et de publier sa collection dans ses attributs (stock, base,
-- présentoirs achetés, Index, dernier gagné) lorsque sa collection change.
local function refresh(player: Player, force: boolean?)
	local collection = PlayerData.collection(player)
	if collection then
		collection.bonus = StoreService.displayBonus(player) -- Big Base (boutique Robux)
	end
	local slot = slotOf[player]
	if slot then
		render(slot, player, force)
	end
	local data = PlayerData.collection(player)
	if not data or not player:GetAttribute("DataReady") then
		return -- rien de publié avant le chargement : le client ne voit pas une collection vide puis la vraie
	end
	Inventory.checkLast(data)
	-- Première pose du tutoriel (à la main) : il faut un mannequin proposé, sinon rien ne permet de poser (gagné puis
	-- parti avant de le poser, ou vendu) ; le plus récent du stock
	if not data.last and #data.stock > 0 and firstPlacePending(player) then
		local newest = data.stock[#data.stock]
		data.last = { id = newest.id, size = newest.size }
	end
	player:SetAttribute("Stock", Inventory.encodeList(data.stock))
	player:SetAttribute("BaseDummies", Inventory.encodeBase(data.base))
	player:SetAttribute("Displays", Inventory.capacity(data)) -- présentoirs utilisables (Big Base compris)
	player:SetAttribute("DummyIndex", Inventory.encodeIndex(data.index))
	player:SetAttribute("PendingDummy", if data.last then Inventory.key(data.last) else nil)
	DummyTools.sync(player, data.stock) -- un outil du Backpack par mannequin du stock
end

-- Cette méthode permet d'ajouter au stock (et à l'Index) un mannequin gagné, proposé ensuite à la pose, lorsque le
-- tirage le donne ; renvoie true s'il n'avait jamais été obtenu. Stock plein : le moins rentable est vendu d'office.
local function receive(player: Player, data: Inventory.Data, entry: Collection.Entry): boolean
	local isNew = Inventory.discover(data, entry)
	local sold = Inventory.add(data, entry)
	if sold > 0 then
		PlayerData.addMoney(player, sold)
	end
	data.last = { id = entry.id, size = entry.size }
	refresh(player)
	return isNew
end

-- Cette méthode permet de tirer le mannequin gagné par un lancer (le premier est garanti : Collection.STARTER, taille
-- normale) à la CHANCE `luck`, de l'ajouter au stock (le précédent, s'il n'a pas été posé, y reste) et de donner ce que
-- l'écran de tirage révèle lorsque le mannequin lancé s'arrête ; nil si les données ne sont pas prêtes.
function BaseService.award(player: Player, luck: number): Prize?
	local data = PlayerData.collection(player)
	if not data or not player:GetAttribute("DataReady") then
		return nil
	end
	local draws = (player:GetAttribute("Draws") :: number?) or 0
	local roll = function()
		return rng:NextNumber()
	end
	-- Studio : DebugPrize impose le prochain tirage (rareté 1-11 ou son nom, ou « id:taille »), puis s'efface
	-- (même au premier tirage, à la place du mannequin garanti)
	local debugValue = if RunService:IsStudio() then player:GetAttribute("DebugPrize") else nil
	local forced = if debugValue ~= nil then RevealPlan.debugEntry(debugValue, roll) else nil
	if debugValue ~= nil then
		player:SetAttribute("DebugPrize", nil)
		if not forced then
			warn("[Debug] DebugPrize illisible : " .. tostring(debugValue))
		end
	end
	local entry = if forced
		then forced
		elseif draws == 0 then { id = Collection.STARTER, size = 1 }
		else Collection.draw(luck, roll)
	player:SetAttribute("Draws", draws + 1)
	local isNew = receive(player, data, entry)
	local dummy = Collection.get(entry.id) :: Collection.Dummy
	return {
		id = entry.id,
		size = entry.size,
		name = Collection.label(entry),
		rarity = dummy.rarity,
		income = Collection.income(entry),
		odds = Collection.odds(entry),
		isNew = isNew,
	}
end

-- Cette méthode permet de savoir si le joueur peut utiliser AUTO lorsqu'il le demande : première pose du tutoriel
-- déjà faite à la main, et avatar dans sa base ou tout près.
local function canAuto(player: Player): boolean
	if firstPlacePending(player) then
		return false
	end
	local slot = slotOf[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- Marge pour la latence : l'avatar a pu bouger depuis le clic
	return slot ~= nil
		and root ~= nil
		and CourseLayout.isNearBase(slot.index, root.Position - (root.AssemblyLinearVelocity * 0.3), slot.base.big)
end

-- Cette méthode permet de poser le mannequin que le joueur tient (outil équipé), sinon le dernier gagné, lorsque le
-- joueur choisit un présentoir libre (`display`, ce qui compte pour le tutoriel) ou clique sur AUTO près de sa base
-- (`display` nil : Inventory.autoTarget ; base pleine et rien de moins rentable, il reste au stock) ; `force`
-- (serveur) passe outre ces conditions. Le mannequin posé quitte la main et le Backpack. Renvoie true si quelque chose
-- a changé.
function BaseService.place(player: Player, display: any, force: boolean?): boolean
	local data = PlayerData.collection(player)
	if not data or not player:GetAttribute("DataReady") then
		return false
	end
	local held, heldKey = DummyTools.equipped(player)
	local firstPlace = firstPlacePending(player)
	if firstPlace then
		held, heldKey = nil, nil -- première pose du tutoriel : le mannequin du panneau (dernier gagné)
	elseif display ~= nil and not force and not (heldKey and Inventory.findStock(data, heldKey)) then
		return false -- hors tutoriel, l'invite d'un présentoir pose seulement le mannequin tenu
	end
	local key = if heldKey and Inventory.findStock(data, heldKey)
		then heldKey
		elseif data.last then Inventory.key(data.last)
		else nil
	if not key then
		return false
	end
	if key ~= heldKey then
		held = nil -- le mannequin posé n'est pas celui que le joueur tient : il le garde en main
	end
	local position = Inventory.findStock(data, key)
	if not position then
		data.last = nil
		refresh(player)
		return false
	end
	if display == nil then
		if not force and not canAuto(player) then
			return false
		end
		if not Inventory.place(data, position, nil) then
			-- Base pleine et rien de moins rentable : il reste au stock ; tenu, il reste en main, sinon AUTO se ferme
			if held then
				return false
			end
			data.last = nil
			refresh(player)
			return true
		end
	elseif not Inventory.place(data, position, display) then
		return false -- présentoir occupé, pas acheté ou invalide : la pose à la main ne remplace rien
	else
		PlayerData.tutorialStep(player, "Place") -- seule une pose à la main compte (première pose du tutoriel)
	end
	if not held then
		data.last = nil -- le dernier gagné vient d'être posé (un doublon tenu posé le laisse proposé)
	end
	-- L'outil tenu part avec le mannequin posé (la synchronisation retirerait sinon un doublon rangé)
	if held then
		held:Destroy()
	end
	refresh(player)
	return true
end

-- Cette méthode permet d'appliquer une action de la fenêtre d'inventaire ou du stand SELL lorsque le client la
-- demande : "Place" (clé du stock, règle AUTO), "Remove" (présentoir), "Sell" (clé du stock), "SellRarity" (rareté),
-- "PlaceBest", "BuyDisplay" (pad de sa base). Le serveur valide tout ; renvoie true si la collection a changé.
function BaseService.act(player: Player, action: any, arg: any): boolean
	local data = PlayerData.collection(player)
	if not data or not player:GetAttribute("DataReady") then
		return false
	end
	local changed = false
	if action == "Place" or action == "Sell" then
		local position = if type(arg) == "string" then Inventory.findStock(data, arg) else nil
		if not position or (action == "Sell" and firstPlacePending(player)) then
			return false -- première pose du tutoriel : le mannequin gagné se pose, il ne se vend pas
		end
		if action == "Place" then
			changed = not firstPlacePending(player) and Inventory.place(data, position, nil) ~= nil
		else
			local money = Inventory.sell(data, position)
			PlayerData.addMoney(player, money)
			changed = true
		end
	elseif action == "Remove" then
		changed = Inventory.remove(data, arg)
	elseif action == "PlaceBest" then
		changed = not firstPlacePending(player) and Inventory.placeBest(data)
	elseif action == "BuyDisplay" then
		-- Le pad est devant la base : l'achat se fait sur place
		local slot = slotOf[player]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return slot ~= nil
			and root ~= nil
			and CourseLayout.isNearBase(slot.index, root.Position, slot.base.big)
			and BaseService.buyDisplay(player)
	elseif action == "SellRarity" then
		if typeof(arg) == "number" and Rarity.LIST[arg] and not firstPlacePending(player) then
			local count, total = Inventory.sellRarity(data, arg)
			PlayerData.addMoney(player, total)
			changed = count > 0
		end
	end
	if changed then
		refresh(player)
		if action == "Sell" or action == "SellRarity" then
			-- Éclat de pièces au-dessus du comptoir du stand SELL (joué par chaque client, Client.HubShops), pour une
			-- vente faite au stand : pas pour une vente depuis la fenêtre « My Dummies » loin de lui
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			for _, burst in CollectionService:GetTagged(CourseLayout.SELL_BURST_TAG) do
				if
					root
					and burst:IsA("BasePart")
					and (burst.Position - root.Position).Magnitude <= SELL_BURST_REACH
				then
					burst:SetAttribute("Sales", ((burst:GetAttribute("Sales") :: number?) or 0) + 1)
				end
			end
		end
	end
	return changed
end

-- Cette méthode permet d'acheter le présentoir suivant lorsque le joueur utilise le pad de sa base ; refusé sans
-- l'argent ou au maximum. Renvoie true si l'achat a eu lieu.
function BaseService.buyDisplay(player: Player): boolean
	local data = PlayerData.collection(player)
	if not data or not player:GetAttribute("DataReady") then
		return false
	end
	local price = Inventory.buyDisplay(data, (player:GetAttribute("Money") :: number?) or 0)
	if not price then
		return false
	end
	PlayerData.addMoney(player, -price)
	refresh(player)
	return true
end

-- Cette méthode permet de verser le revenu de la base à chaque joueur chargé lorsque l'horloge du revenu tourne.
local function payIncome()
	for player in slotOf do
		if player.Parent and player:GetAttribute("DataReady") then
			local income = (player:GetAttribute("Income") :: number?) or 0
			if income > 0 then
				PlayerData.addMoney(player, income)
			end
		end
	end
end

-- Cette méthode permet de suivre un joueur (sa place, sa base, le chargement de ses données) lorsqu'il arrive.
local function track(player: Player)
	local index = player:GetAttribute("Slot")
	local slot = if typeof(index) == "number" then slots[index] else nil
	if not slot then
		return
	end
	slotOf[player] = slot
	player:SetAttribute("Income", 0)
	DummyTools.track(player, function()
		local data = PlayerData.collection(player)
		return if data and player:GetAttribute("DataReady") then data.stock else nil
	end)
	if RunService:IsStudio() then
		-- Mesures du démarrage (cibles #13) : premier mannequin gagné < 25 s, premier équipement < 1 min
		local joined = os.clock()
		player:GetAttributeChangedSignal("Draws"):Connect(function()
			if player:GetAttribute("Draws") == 1 then
				print(string.format("[Mesure] premier mannequin gagné à %.1f s de l'arrivée", os.clock() - joined))
			end
		end)
		player:GetAttributeChangedSignal("GearTier"):Connect(function()
			if player:GetAttribute("GearTier") == 2 then
				print(
					string.format("[Mesure] premier équipement acheté à %.1f s de l'arrivée", os.clock() - joined)
				)
			end
		end)
	end
	-- Rendu dès l'arrivée (nom au-dessus de la base), puis au chargement des données
	refresh(player)
	player:GetAttributeChangedSignal("DataReady"):Connect(function()
		refresh(player)
	end)
	-- Boutique Robux : passes (revenu, Big Base, badge VIP) et boost d'argent qui commence ou finit
	for _, attribute in { "Passes", "BoostMoney" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if slotOf[player] == slot then
				refresh(player)
			end
		end)
	end
	-- Throw Power, renaissances et record en direct au-dessus de la base (entraînement, renaissance, lancer)
	for _, attribute in { "ThrowPower", "Rebirths", "BestDistance" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if slotOf[player] == slot then
				updateLabel(slot, player)
			end
		end)
	end
end

-- Cette méthode permet de reconstruire toutes les bases lorsque les maillages du mannequin arrivent (les bases
-- rendues avant sont en blocs).
local function watchTemplates()
	local function rerender()
		for player in slotOf do
			refresh(player, true)
		end
	end
	local function watch(folder: Instance)
		folder:GetAttributeChangedSignal("Ready"):Connect(rerender)
		-- Pièces ajoutées des modèles de collection chargées après le corps : les mannequins posés sans elles sont refaits
		folder:GetAttributeChangedSignal(DummyShape.COMPLETE):Connect(rerender)
		if folder:GetAttribute("Ready") then
			rerender()
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

-- Cette méthode permet d'habiller une base sans propriétaire comme s'il avait acheté `displays` présentoirs (palier
-- visuel, présentoirs achetés, pad) lorsque Studio la photographie (Server.PhotoStudio) ; nil la rend à son état vide.
function BaseService.showcase(slot: Slot, displays: number?)
	if displays == nil then
		render(slot, nil, true)
		return
	end
	CourseBuilder.styleBase(slot, BaseLook.baseTier(displays))
	for display in slot.base.displays do
		styleDisplay(slot, display, display <= displays)
	end
	stylePad(slot, displays)
end

-- Cette méthode permet de brancher en Studio les attributs de test (MCP) lorsque le joueur arrive : DebugPlace = n
-- pose le mannequin tenu, sinon le dernier gagné, sur le présentoir n (comme l'invite, sans ses conditions), toute
-- autre valeur avec AUTO sans condition ;
-- DebugGive = « id:taille » ajoute ce mannequin comme s'il venait d'être gagné ; DebugEquip = « id:taille » équipe
-- son outil du Backpack (« » déséquipe) ; DebugInventory = « Action » ou
-- « Action|argument » (actions de BaseService.act). DebugPrize (lu par BaseService.award au prochain tirage, pas
-- ici) : rareté 1-11 ou son nom (« Secret », « Divine ») ou « id:taille », impose le mannequin gagné par le prochain lancer.
local function bindDebug(player: Player)
	player:GetAttributeChangedSignal("DebugPlace"):Connect(function()
		local value = player:GetAttribute("DebugPlace")
		if value ~= nil then
			player:SetAttribute("DebugPlace", nil)
			BaseService.place(player, if typeof(value) == "number" then value else nil, true)
		end
	end)
	player:GetAttributeChangedSignal("DebugGive"):Connect(function()
		local entry = Inventory.parseKey(player:GetAttribute("DebugGive"))
		local data = PlayerData.collection(player)
		player:SetAttribute("DebugGive", nil)
		if entry and data and player:GetAttribute("DataReady") then
			receive(player, data, entry)
		end
	end)
	player:GetAttributeChangedSignal("DebugEquip"):Connect(function()
		local key = player:GetAttribute("DebugEquip")
		if key == nil then
			return
		end
		player:SetAttribute("DebugEquip", nil)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not humanoid or not backpack then
			return
		end
		if key == "" then
			humanoid:UnequipTools()
			return
		end
		for _, tool in backpack:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute(BackpackPlan.TOOL_ATTRIBUTE) == key then
				humanoid:EquipTool(tool)
				return
			end
		end
	end)
	player:GetAttributeChangedSignal("DebugInventory"):Connect(function()
		local value = player:GetAttribute("DebugInventory")
		if type(value) ~= "string" then
			return
		end
		player:SetAttribute("DebugInventory", nil)
		local action, arg = string.match(value, "^(%w+)|?(.*)$")
		local result = BaseService.act(player, action, tonumber(arg) or (if arg ~= "" then arg else nil))
		print(string.format("[Debug] %s -> %s", value, tostring(result)))
	end)
end

-- Cette méthode permet de brancher la pose (remote PlaceDummy), les actions de collection et l'achat de présentoir
-- (remote Inventory), le revenu et le suivi des joueurs lorsque le serveur démarre (après SlotService, qui attribue les
-- places).
function BaseService.init(builtSlots: { Slot }, placeRemote: RemoteEvent, inventoryRemote: RemoteEvent)
	slots = builtSlots
	placeRemote.OnServerEvent:Connect(function(player, display)
		BaseService.place(player, display)
	end)
	inventoryRemote.OnServerEvent:Connect(function(player, action, arg)
		BaseService.act(player, action, arg)
	end)
	for _, slot in slots do
		render(slot, nil)
	end
	-- Collection remplacée (DebugWipe) : base, attributs publiés et Backpack reconstruits
	PlayerData.onReset(function(player)
		refresh(player, true)
	end)
	-- Cette méthode permet de suivre un joueur dès que SlotService lui a donné une place, sans attente bloquante
	-- (lobby plein : jamais de place, la connexion est coupée au départ du joueur).
	local function trackWhenSlotted(player: Player)
		if typeof(player:GetAttribute("Slot")) == "number" then
			task.spawn(track, player)
			return
		end
		if waitingSlot[player] then
			return
		end
		waitingSlot[player] = player:GetAttributeChangedSignal("Slot"):Connect(function()
			if typeof(player:GetAttribute("Slot")) ~= "number" then
				return
			end
			local pending = waitingSlot[player]
			waitingSlot[player] = nil
			if pending then
				pending:Disconnect()
				task.defer(track, player)
			end
		end)
	end
	Players.PlayerAdded:Connect(trackWhenSlotted)
	for _, player in Players:GetPlayers() do
		trackWhenSlotted(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local slot = slotOf[player]
		slotOf[player] = nil
		local pending = waitingSlot[player]
		waitingSlot[player] = nil
		if pending then
			pending:Disconnect()
		end
		DummyTools.forget(player)
		if slot then
			render(slot, nil)
		end
	end)
	watchTemplates()
	task.spawn(function()
		while true do
			task.wait(GameConfig.INCOME_TICK)
			payIncome()
		end
	end)
	if RunService:IsStudio() then
		Players.PlayerAdded:Connect(bindDebug)
		for _, player in Players:GetPlayers() do
			bindDebug(player)
		end
	end
end

return BaseService
