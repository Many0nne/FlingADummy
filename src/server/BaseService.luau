-- Base du joueur : mannequins de collection gagnés au lancer (tirage « 1 en N », Shared.Collection), gardés en stock
-- (Shared.Inventory) et posés sur les présentoirs de sa base, qui versent leur revenu chaque seconde : seule source
-- d'argent du jeu. Le dernier gagné est proposé à la pose (attribut `PendingDummy`, invite « Place » ou bouton AUTO) ;
-- un nouveau lancer l'ajoute simplement au stock, rien ne se perd. Fenêtres de collection (remote Inventory) : poser,
-- retirer, vendre, « Place best ». Pad « 6 > 7 » devant la base : achat du présentoir suivant. Le serveur publie la
-- collection dans des attributs du joueur (Stock, BaseDummies, Displays, DummyIndex) que le client affiche. Les
-- mannequins posés sont construits par le serveur, visibles de tous.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Collection = require(Shared.Collection)
local CourseLayout = require(Shared.CourseLayout)
local DummyShape = require(Shared.DummyShape)
local Format = require(Shared.Format)
local GameConfig = require(Shared.GameConfig)
local Inventory = require(Shared.Inventory)
local Rarity = require(Shared.Rarity)
local Tutorial = require(Shared.Tutorial)

local CourseBuilder = require(script.Parent.CourseBuilder)
local PlayerData = require(script.Parent.PlayerData)

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

local BaseService = {}

-- Mannequin construit sur un présentoir, avec la clé de son entrée (reconstruit seulement si elle change)
type Shown = { key: string, model: Model }

local slots: { Slot } = {}
local slotOf: { [Player]: Slot } = {}
local shown: { [number]: { [number]: Shown } } = {} -- mannequins posés, par place puis présentoir
local rng = Random.new()

-- Cette méthode permet de construire le mannequin posé sur un présentoir (pièces ancrées sans collision, regard vers
-- l'entrée de la base, nom coloré et revenu au-dessus) lorsque la base est rendue.
local function buildDisplayed(entry: Collection.Entry, top: BasePart, facing: number): Model
	local size = Collection.SIZES[entry.size]
	local dummy = Collection.get(entry.id) :: Collection.Dummy
	local scale = size.scale
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
	model:PivotTo(CFrame.lookAt(position, position + Vector3.new(facing, 0, 0)))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(8, 2.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4 * scale + 1.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
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
-- invite ni objectif) lorsque la base est rendue.
local function styleDisplay(slot: Slot, display: number, unlocked: boolean)
	local top = slot.base.displays[display]
	local pedestal = slot.base.pedestals[display]
	top.Color = if unlocked then slot.color else LOCKED_COLOR
	top.Transparency = if unlocked then 0 else LOCKED_TRANSPARENCY
	pedestal.Transparency = if unlocked then 0 else LOCKED_TRANSPARENCY
	top:SetAttribute("Locked", if unlocked then nil else true)
end

-- Cette méthode permet d'afficher sur le pad d'achat le présentoir suivant et son prix (« 6 > 7 », « $1K »), ou MAX,
-- lorsque la base change ; le client n'active l'invite que pour le propriétaire tant que le maximum n'est pas atteint.
local function stylePad(slot: Slot, displays: number?)
	local pad = slot.base.pad
	local price = if displays then Inventory.displayPrice(displays) else nil
	local count = displays or GameConfig.DISPLAY_START
	if displays and not price then
		pad.title.Text = "MAX"
		pad.price.Text = count .. " / " .. CourseLayout.DISPLAY_MAX
	else
		pad.title.Text = count .. " > " .. (count + 1)
		pad.price.Text = Format.money(price or Inventory.displayPrice(count) or 0)
	end
	pad.prompt:SetAttribute("Price", price)
	pad.prompt:SetAttribute("Maxed", if displays and not price then true else nil)
end

-- Cette méthode permet de reconstruire les mannequins posés d'une place (vide si personne ne l'occupe), d'habiller ses
-- présentoirs et son pad, et d'y afficher le revenu de la base lorsque la base change, que son joueur arrive ou part,
-- ou que les maillages arrivent (`force` : tout reconstruire).
local function render(slot: Slot, player: Player?, force: boolean?)
	local current: { [number]: Shown } = shown[slot.index] or {}
	shown[slot.index] = current
	local data = if player then PlayerData.collection(player) else nil
	local ready = player ~= nil and data ~= nil and player:GetAttribute("DataReady") == true
	local displays = if ready and data then data.displays else GameConfig.DISPLAY_START
	for display, top in slot.base.displays do
		local unlocked = display <= displays
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
	stylePad(slot, if ready and data then data.displays else nil)
	if not ready or not data or not player then
		slot.base.income.Text = ""
		return
	end
	local income = Inventory.income(data)
	player:SetAttribute("Income", income)
	slot.base.income.Text = Format.money(income) .. "/s"
end

-- Cette méthode permet de savoir si la première pose du tutoriel reste à faire (elle se fait à la main, sur un
-- présentoir) lorsque le joueur demande AUTO, Place ou « Place best ».
local function firstPlacePending(player: Player): boolean
	return Tutorial.current((player:GetAttribute("Tutorial") :: number?) or 0) == "Place"
end

-- Cette méthode permet de rendre la base d'un joueur et de publier sa collection dans ses attributs (stock, base,
-- présentoirs achetés, Index, dernier gagné) lorsque sa collection change.
local function refresh(player: Player, force: boolean?)
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
	player:SetAttribute("Displays", data.displays)
	player:SetAttribute("DummyIndex", Inventory.encodeIndex(data.index))
	player:SetAttribute("PendingDummy", if data.last then Inventory.key(data.last) else nil)
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
	local entry = if draws == 0
		then { id = Collection.STARTER, size = 1 }
		else Collection.draw(luck, function()
			return rng:NextNumber()
		end)
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
		and CourseLayout.isNearBase(slot.index, root.Position - (root.AssemblyLinearVelocity * 0.3))
end

-- Cette méthode permet de poser le dernier mannequin gagné lorsque le joueur choisit un présentoir libre (`display`,
-- ce qui compte pour le tutoriel) ou clique sur AUTO près de sa base (`display` nil : Inventory.autoTarget ; base
-- pleine et rien de moins rentable, il reste au stock et le panneau se ferme) ; `force` (serveur) passe outre ces
-- conditions. Renvoie true si quelque chose a changé.
function BaseService.place(player: Player, display: any, force: boolean?): boolean
	local data = PlayerData.collection(player)
	local last = data and data.last
	if not data or not last or not player:GetAttribute("DataReady") then
		return false
	end
	local position = Inventory.findStock(data, Inventory.key(last))
	if not position then
		data.last = nil
		refresh(player)
		return false
	end
	if display == nil then
		if not force and not canAuto(player) then
			return false
		end
		Inventory.place(data, position, nil)
	elseif not Inventory.place(data, position, display) then
		return false -- présentoir occupé, pas acheté ou invalide : la pose à la main ne remplace rien
	else
		PlayerData.tutorialStep(player, "Place") -- seule une pose à la main compte (première pose du tutoriel)
	end
	data.last = nil
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
		return BaseService.buyDisplay(player)
	elseif action == "SellRarity" then
		if typeof(arg) == "number" and Rarity.LIST[arg] and not firstPlacePending(player) then
			local count, total = Inventory.sellRarity(data, arg)
			PlayerData.addMoney(player, total)
			changed = count > 0
		end
	end
	if changed then
		refresh(player)
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
	if player:GetAttribute("DataReady") then
		refresh(player)
	end
	player:GetAttributeChangedSignal("DataReady"):Connect(function()
		refresh(player)
	end)
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

-- Cette méthode permet de brancher en Studio les attributs de test (MCP) lorsque le joueur arrive : DebugPlace = n
-- pose le dernier gagné sur le présentoir n (comme l'invite), toute autre valeur avec AUTO sans condition ;
-- DebugGive = « id:taille » ajoute ce mannequin comme s'il venait d'être gagné ; DebugInventory = « Action » ou
-- « Action|argument » (actions de BaseService.act).
local function bindDebug(player: Player)
	player:GetAttributeChangedSignal("DebugPlace"):Connect(function()
		local value = player:GetAttribute("DebugPlace")
		if value ~= nil then
			player:SetAttribute("DebugPlace", nil)
			BaseService.place(player, if typeof(value) == "number" then value else nil, typeof(value) ~= "number")
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
	Players.PlayerAdded:Connect(function(player)
		-- SlotService pose l'attribut Slot dans son propre PlayerAdded : attendu s'il n'est pas encore là
		if player:GetAttribute("Slot") == nil then
			player:GetAttributeChangedSignal("Slot"):Wait()
		end
		track(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(track, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local slot = slotOf[player]
		slotOf[player] = nil
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
