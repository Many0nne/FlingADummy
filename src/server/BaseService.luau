-- Base du joueur : mannequins de collection gagnés au lancer (tirage « 1 en N », Shared.Collection), posés sur les
-- présentoirs de sa base (invite « Place » ou bouton AUTO), qui versent leur revenu chaque seconde : seule source
-- d'argent du jeu. Le mannequin gagné reste « en main » (attribut `PendingDummy`, « id:taille ») jusqu'à sa pose ;
-- un nouveau lancer le pose d'office. Base pleine : il remplace le moins rentable s'il rapporte plus, sinon il est
-- revendu (Collection.sellValue). Les mannequins posés sont construits par le serveur, visibles de tous.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Collection = require(Shared.Collection)
local CourseLayout = require(Shared.CourseLayout)
local DummyShape = require(Shared.DummyShape)
local Format = require(Shared.Format)
local GameConfig = require(Shared.GameConfig)
local Rarity = require(Shared.Rarity)

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

local BaseService = {}

local slots: { Slot } = {}
local slotOf: { [Player]: Slot } = {}
local shown: { [number]: { [number]: Model } } = {} -- mannequins posés, par place puis présentoir
local rng = Random.new()

-- Cette méthode permet d'écrire une entrée dans l'attribut `PendingDummy` (« id:taille ») lorsque le mannequin en
-- main change ; nil le retire.
local function entryKey(entry: Collection.Entry?): string?
	return if entry then entry.id .. ":" .. entry.size else nil
end

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

-- Cette méthode permet de reconstruire les mannequins posés d'une place (vide si personne ne l'occupe) et d'y
-- afficher le revenu de la base lorsque la base change, que son joueur arrive ou part, ou que les maillages arrivent.
local function render(slot: Slot, player: Player?)
	local previous: { [number]: Model } = shown[slot.index] or {}
	for _, model in previous do
		model:Destroy()
	end
	shown[slot.index] = {}
	local collection = if player then PlayerData.collection(player) else nil
	if not player or not collection or not player:GetAttribute("DataReady") then
		slot.base.income.Text = ""
		for _, top in slot.base.displays do
			top:SetAttribute("Occupied", nil)
		end
		return
	end
	for index, top in slot.base.displays do
		local entry = collection.base[index]
		-- Lu par le client : invite « Place » seulement sur les présentoirs libres
		top:SetAttribute("Occupied", if entry then true else nil)
		if entry then
			local model = buildDisplayed(entry, top, slot.base.facing)
			model.Parent = slot.base.model
			shown[slot.index][index] = model
		end
	end
	local income = Collection.baseIncome(collection.base, CourseLayout.DISPLAY_COUNT)
	player:SetAttribute("Income", income)
	slot.base.income.Text = Format.money(income) .. "/s"
end

-- Cette méthode permet de rendre la base d'un joueur lorsque sa collection change.
local function refresh(player: Player)
	local slot = slotOf[player]
	if slot then
		render(slot, player)
	end
	local collection = PlayerData.collection(player)
	player:SetAttribute("PendingDummy", entryKey(collection and collection.pending))
end

-- Cette méthode permet de tirer le mannequin gagné par un lancer (le premier est garanti : Collection.STARTER, taille
-- normale) à la CHANCE `luck`, de le mettre en main (un mannequin encore en main est d'abord posé d'office) et de
-- donner ce que l'écran de tirage révèle lorsque le mannequin lancé s'arrête ; nil si les données ne sont pas prêtes.
function BaseService.award(player: Player, luck: number): Prize?
	local collection = PlayerData.collection(player)
	if not collection or not player:GetAttribute("DataReady") then
		return nil
	end
	if collection.pending then
		BaseService.place(player, nil)
	end
	local draws = (player:GetAttribute("Draws") :: number?) or 0
	local entry = if draws == 0
		then { id = Collection.STARTER, size = 1 }
		else Collection.draw(luck, function()
			return rng:NextNumber()
		end)
	local isNew = not collection.discovered[entry.id]
	collection.discovered[entry.id] = true
	collection.pending = entry
	player:SetAttribute("Draws", draws + 1)
	refresh(player)
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

-- Cette méthode permet de poser le mannequin en main lorsque le joueur choisit un présentoir libre (`display`) ou
-- clique sur AUTO (`display` nil : Collection.autoSlot, revente si rien ne lui va) ; renvoie true si la base a changé.
function BaseService.place(player: Player, display: any): boolean
	local collection = PlayerData.collection(player)
	local entry = collection and collection.pending
	if not collection or not entry then
		return false
	end
	local capacity = CourseLayout.DISPLAY_COUNT
	local index: number?
	if display == nil then
		index = Collection.autoSlot(collection.base, capacity, entry)
	elseif typeof(display) == "number" and display == math.floor(display) and display >= 1 and display <= capacity then
		if collection.base[display] then
			return false -- présentoir occupé : la pose à la main ne remplace rien
		end
		index = display
	else
		return false
	end
	collection.pending = nil
	if index then
		local replaced = collection.base[index]
		if replaced then
			PlayerData.addMoney(player, Collection.sellValue(replaced))
		end
		collection.base[index] = entry
	else
		PlayerData.addMoney(player, Collection.sellValue(entry))
	end
	PlayerData.tutorialStep(player, "Place")
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
				print(string.format("[Mesure] premier équipement acheté à %.1f s de l'arrivée", os.clock() - joined))
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
			refresh(player)
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

-- Cette méthode permet de brancher la pose (remote PlaceDummy), le revenu et le suivi des joueurs lorsque le serveur
-- démarre (après SlotService, qui attribue les places).
function BaseService.init(builtSlots: { Slot }, placeRemote: RemoteEvent)
	slots = builtSlots
	placeRemote.OnServerEvent:Connect(function(player, display)
		BaseService.place(player, display)
	end)
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
		-- Studio : DebugPlace (n'importe quelle valeur) pose le mannequin en main avec AUTO
		Players.PlayerAdded:Connect(function(player)
			player:GetAttributeChangedSignal("DebugPlace"):Connect(function()
				if player:GetAttribute("DebugPlace") ~= nil then
					player:SetAttribute("DebugPlace", nil)
					BaseService.place(player, nil)
				end
			end)
		end)
	end
end

return BaseService
