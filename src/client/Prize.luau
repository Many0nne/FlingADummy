-- Tirage « 1 en N » et pose du mannequin gagné, au style de la référence 09 : après le résultat, silhouette noire du
-- mannequin debout au point d'atterrissage, cote qui grimpe en 1 à 3 paliers (« 1 IN 3 » → « 1 IN 40 »), puis
-- révélation (mannequin en couleurs, anneau et étincelles ; rareté, nom, « NEW! », $/s et cote en haut au centre),
-- bouton GO BACK. De retour au hub, panneau « Place your … » en bas au centre avec le bouton AUTO, et invite « Place »
-- sur les présentoirs libres de sa base tant que le mannequin gagné n'est pas posé.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Collection = require(Shared:WaitForChild("Collection"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local FlightCamera = require(script.Parent.FlightCamera)
local Hud = require(script.Parent.Hud)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local FEET = 3.82 -- du centre du torse au bas des pieds, échelle 1 (Shared.DummyShape)
local HEIGHT = 6.7 -- hauteur du mannequin debout, échelle 1 (studs)
local TEASE_FIRST = 0.5 -- silhouette seule avant la première cote (s)
local TEASE_STEP = 0.75 -- durée de chaque palier de cote (s)
local AUTO_CLOSE = 5 -- GO BACK automatique après la révélation (s)
local PROMPT_REFRESH = 0.25 -- s entre deux mises à jour des invites « Place »
local BLACK = Color3.fromRGB(12, 12, 16)

local Prize = {}

local player: Player
local remotes: Remotes.Remotes
local gui: ScreenGui
local token = 0
local showing = false -- tirage à l'écran (GO BACK pas encore envoyé)
local worldModel: Model? = nil
local oddsLabel: TextLabel? = nil
-- Révélation (haut de l'écran)
local reveal: Frame
local rarityLabel: TextLabel
local nameLabel: TextLabel
local newTag: TextLabel
local incomeLabel: TextLabel
local revealOdds: TextLabel
local goBack: TextButton
local rays: Frame? = nil
-- Panneau « Place your … »
local placePanel: Frame
local placeTitle: TextLabel
local placeHint: TextLabel
local placeViewport: ViewportFrame
local placeKey: string? = nil
local lastPromptRefresh = 0

-- Cette méthode permet de relire le mannequin en main (« id:taille ») lorsque l'attribut PendingDummy change ; nil
-- s'il n'y en a pas ou qu'il est illisible.
local function pendingEntry(): Collection.Entry?
	local text = player:GetAttribute("PendingDummy")
	if type(text) ~= "string" then
		return nil
	end
	local id, size = string.match(text, "^([%w_]+):(%d+)$")
	local entry = { id = id, size = tonumber(size) }
	return if Collection.isEntry(entry) then entry :: Collection.Entry else nil
end

-- Cette méthode permet de trouver le sol sous le point d'atterrissage (piste, gradins) lorsque le mannequin gagné
-- s'y dresse ; ignore les mannequins lancés et l'avatar.
local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	local ignore: { Instance } = {}
	for _, name in { "Dummies", "ObjectiveMarkers" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position else position - Vector3.new(0, 1.5, 0)
end

-- Cette méthode permet de construire le mannequin du tirage (en silhouette noire ou en couleurs) debout sur `ground`,
-- tourné vers la caméra (arrière de la piste), lorsque le tirage commence ou se révèle.
local function buildStanding(entry: Collection.Entry, ground: Vector3, silhouette: boolean): Model
	local scale = Collection.SIZES[entry.size].scale
	local variant: any = Collection.variant(entry)
	if silhouette then
		variant = { color = BLACK, accessories = variant.accessories, accessoryColor = BLACK }
	end
	local model = DummyShape.buildVisual(scale, variant)
	if silhouette then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Color = BLACK
				part.Material = Enum.Material.SmoothPlastic
			elseif part:IsA("SurfaceAppearance") or part:IsA("SurfaceGui") then
				part:Destroy()
			end
		end
	end
	local position = ground + Vector3.new(0, FEET * scale, 0)
	model:PivotTo(CFrame.lookAt(position, position - Vector3.zAxis));
	(model.PrimaryPart :: BasePart).Anchored = true
	model.Parent = Workspace
	return model
end

-- Cette méthode permet d'accrocher au-dessus du mannequin du tirage l'étiquette de cote (« 1 IN 40 ») lorsque la
-- silhouette apparaît.
local function attachOdds(model: Model, scale: number): TextLabel
	local billboard = UIKit.create("BillboardGui", {
		Size = UDim2.fromOffset(260, 70),
		StudsOffsetWorldSpace = Vector3.new(0, (HEIGHT - FEET) * scale + 1.6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = model.PrimaryPart,
		Parent = model,
	})
	return UIKit.text({ Size = UDim2.fromScale(1, 1), TextSize = 48, StrokeThickness = 4, Parent = billboard })
end

-- Cette méthode permet de faire grossir le mannequin révélé (de 60 % à sa taille, petit rebond) lorsque la
-- silhouette laisse place aux couleurs.
local function growIn(model: Model)
	local start = os.clock()
	model:ScaleTo(0.6)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - start) / 0.3, 0, 1)
		if not model.Parent then
			connection:Disconnect()
			return
		end
		-- Dépasse un peu (1,08) à 70 % puis revient à 1
		local value = if k < 0.7 then 0.6 + 0.48 * (k / 0.7) else 1.08 - 0.08 * ((k - 0.7) / 0.3)
		model:ScaleTo(math.max(value, 0.01))
		if k >= 1 then
			connection:Disconnect()
		end
	end)
end

-- Cette méthode permet de faire jaillir au sol un anneau blanc qui s'élargit et s'efface (référence 09) lorsque le
-- mannequin se révèle.
local function ring(ground: Vector3, scale: number)
	local part = UIKit.create("Part", {
		Name = "RevealRing",
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.Neon,
		Color = Color3.new(1, 1, 1),
		Transparency = 0.2,
		Size = Vector3.new(0.2, 2, 2),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = Workspace,
	})
	local goal = 9 * scale + 6
	TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, goal, goal),
		Transparency = 1,
	}):Play()
	task.delay(0.8, function()
		part:Destroy()
	end)
end

-- Cette méthode permet de retirer le mannequin du tirage, l'écran de révélation et les rayons lorsque le tirage se
-- termine (GO BACK, fin forcée par le serveur, nouveau lancer).
local function cleanup()
	token += 1
	showing = false
	if worldModel then
		worldModel:Destroy()
		worldModel = nil
	end
	oddsLabel = nil
	if rays then
		rays:Destroy()
		rays = nil
	end
	UIKit.closeWindow(reveal, true)
	goBack.Visible = false
end

-- Cette méthode permet de clore le tirage et de rendre la main (le serveur ramène l'avatar au hub) lorsque le
-- joueur clique GO BACK ou que la révélation a assez duré.
local function finish()
	if not showing then
		return
	end
	cleanup()
	remotes.ResultDone:FireServer()
end

-- Cette méthode permet d'afficher la révélation (mannequin en couleurs, anneau, rayons et textes, GO BACK) lorsque la
-- dernière cote de la silhouette est passée.
local function showReveal(prize: any, entry: Collection.Entry, ground: Vector3, current: number)
	local scale = Collection.SIZES[entry.size].scale
	if worldModel then
		worldModel:Destroy()
	end
	local model = buildStanding(entry, ground, false)
	worldModel = model
	oddsLabel = attachOdds(model, scale);
	(oddsLabel :: TextLabel).Text = "1 IN " .. Format.short(prize.odds)
	growIn(model)
	ring(ground, scale)
	local tier = Rarity.get(prize.rarity)
	rarityLabel.Text = string.upper(tier.name)
	rarityLabel.TextColor3 = tier.color
	nameLabel.Text = prize.name
	UIKit.gradientText(nameLabel, Color3.new(1, 1, 1), tier.color:Lerp(Color3.new(1, 1, 1), 0.25))
	newTag.Visible = prize.isNew == true
	incomeLabel.Text = Format.money(prize.income) .. "/s"
	revealOdds.Text = "1 IN " .. Format.short(prize.odds)
	UIKit.openWindow(reveal, false)
	UIKit.pop(nameLabel, 1.8)
	if prize.isNew then
		UIKit.pop(newTag, 2)
	end
	rays = UIKit.rays(gui, {
		position = UDim2.new(0.5, 0, 0, 110),
		size = 360,
		duration = AUTO_CLOSE,
		color = tier.color,
		count = 12,
		zIndex = 0,
	})
	UIKit.sparkles(nameLabel, 6, Vector2.new(420, 60), 22, 0.1)
	UIKit.playSound("LevelUp")
	goBack.Visible = true
	UIKit.pop(goBack, 1.3)
	task.delay(AUTO_CLOSE, function()
		if current == token then
			finish()
		end
	end)
end

-- Cette méthode permet de jouer le tirage (silhouette, cotes qui grimpent, révélation) lorsque le résultat du lancer
-- a fini de compter ; sans mannequin gagné (données pas prêtes), rend la main tout de suite.
function Prize.play(result: any)
	cleanup()
	local current = token
	local prize = result and result.prize
	local entry = prize and { id = prize.id, size = prize.size }
	if not entry or not Collection.isEntry(entry) or typeof(result.landing) ~= "Vector3" then
		showing = true
		finish()
		return
	end
	showing = true
	local scale = Collection.SIZES[entry.size].scale
	local ground = groundAt(result.landing)
	FlightCamera.showcase(ground + Vector3.new(0, HEIGHT * scale / 2, 0), HEIGHT * scale)
	worldModel = buildStanding(entry, ground, true)
	local label = attachOdds(worldModel :: Model, scale)
	oddsLabel = label
	label.Text = ""
	task.spawn(function()
		task.wait(TEASE_FIRST)
		local steps = Collection.teaseSteps(prize.odds)
		if #steps == 0 then
			steps = { 1 }
		end
		for index, value in steps do
			if current ~= token then
				return
			end
			label.Text = if value <= 1 then "1 IN ?" else "1 IN " .. Format.short(value)
			UIKit.pop(label, 1.5)
			UIKit.playSound("Click", 0.9 + index * 0.15)
			task.wait(TEASE_STEP)
		end
		if current == token then
			showReveal(prize, entry :: Collection.Entry, ground, current)
		end
	end)
end

-- Cette méthode permet de construire l'écran de révélation (haut au centre) et le bouton GO BACK lorsque le client
-- démarre.
local function buildReveal()
	reveal = UIKit.create("Frame", {
		Name = "PrizeReveal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(520, 210),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	UIKit.create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = reveal,
	})
	rarityLabel = UIKit.text({
		LayoutOrder = 1,
		Size = UDim2.fromOffset(520, 30),
		TextSize = 28,
		ZIndex = 21,
		Parent = reveal,
	})
	nameLabel = UIKit.text({
		LayoutOrder = 2,
		Size = UDim2.fromOffset(520, 60),
		TextSize = 54,
		StrokeThickness = 4,
		ZIndex = 21,
		Parent = reveal,
	})
	newTag = UIKit.text({
		LayoutOrder = 3,
		Size = UDim2.fromOffset(520, 28),
		Text = "NEW!",
		TextSize = 28,
		TextColor3 = C.red,
		Rotation = -4,
		ZIndex = 21,
		Parent = reveal,
	})
	incomeLabel = UIKit.text({
		LayoutOrder = 4,
		Size = UDim2.fromOffset(520, 40),
		TextSize = 38,
		TextColor3 = C.green,
		StrokeThickness = 3,
		ZIndex = 21,
		Parent = reveal,
	})
	revealOdds = UIKit.text({
		LayoutOrder = 5,
		Size = UDim2.fromOffset(520, 40),
		TextSize = 36,
		StrokeThickness = 3,
		ZIndex = 21,
		Parent = reveal,
	})
	goBack = UIKit.button({
		Name = "GoBack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(220, 64),
		Text = "GO BACK",
		TextSize = 32,
		Shine = true,
		Visible = false,
		ZIndex = 21,
		Parent = gui,
	}, finish)
end

-- Cette méthode permet de construire le panneau « Place your … » (rendu 3D, titre, consigne, bouton AUTO) en bas au
-- centre lorsque le client démarre.
local function buildPlacePanel()
	placePanel = UIKit.create("Frame", {
		Name = "PlaceDummy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(470, 120),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	})
	UIKit.corner(placePanel, 14)
	UIKit.outline(placePanel, 4)
	local well = UIKit.create("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = Color3.fromRGB(28, 31, 40),
		ZIndex = 9,
		Parent = placePanel,
	})
	UIKit.corner(well, 10)
	UIKit.outline(well, 2)
	placeViewport = UIKit.create("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1.5, 1),
		ZIndex = 10,
		Parent = well,
	})
	placeTitle = UIKit.text({
		Position = UDim2.fromOffset(122, 10),
		Size = UDim2.fromOffset(330, 34),
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 10,
		Parent = placePanel,
	})
	placeHint = UIKit.text({
		Position = UDim2.fromOffset(122, 44),
		Size = UDim2.fromOffset(330, 20),
		TextSize = 17,
		TextColor3 = Color3.fromRGB(190, 195, 210),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
		Parent = placePanel,
	})
	local auto = UIKit.button({
		Name = "Auto",
		Position = UDim2.fromOffset(122, 68),
		Size = UDim2.fromOffset(150, 44),
		Text = "AUTO",
		TextSize = 28,
		Shine = true,
		ZIndex = 10,
		Parent = placePanel,
	}, function()
		remotes.PlaceDummy:FireServer(nil)
	end)
	Hud.setAnchor("Place", auto)
end

-- Cette méthode permet de donner les invites « Place » des présentoirs de la base du joueur lorsque l'on les met à
-- jour.
local function myPrompts(): { ProximityPrompt }
	local slot = player:GetAttribute("Slot")
	local list = {}
	for _, prompt in CollectionService:GetTagged(Collection.PROMPT_TAG) do
		if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("Slot") == slot then
			table.insert(list, prompt)
		end
	end
	return list
end

-- Cette méthode permet de savoir si le joueur est libre de poser (au hub, ni sur la bande ni à l'entraînement)
-- lorsque le panneau et les invites se mettent à jour.
local function canPlace(): boolean
	return player:GetAttribute("LaneState") == "Ready" and player:GetAttribute("Action") == nil and not showing
end

-- Cette méthode permet d'afficher ou de masquer le panneau « Place your … » (et son rendu 3D) lorsque le mannequin en
-- main ou l'état du joueur changent.
local function refreshPanel()
	local entry = pendingEntry()
	local visible = entry ~= nil and canPlace()
	if visible and entry then
		local key = entry.id .. ":" .. entry.size
		if key ~= placeKey then
			placeKey = key
			local dummy = Collection.get(entry.id) :: Collection.Dummy
			placeTitle.Text = "Place your " .. Collection.label(entry) .. "!"
			placeTitle.TextColor3 = Rarity.get(dummy.rarity).color
			UIKit.showModel(placeViewport, DummyShape.buildVisual(1, Collection.variant(entry) :: any))
		end
		local free = 0
		for _, prompt in myPrompts() do
			if not (prompt.Parent :: Instance):GetAttribute("Occupied") then
				free += 1
			end
		end
		placeHint.Text = if free > 0
			then "Walk to a display in your base, or press AUTO"
			else "Base full: AUTO swaps your worst dummy or sells it"
	end
	if visible and not placePanel.Visible then
		UIKit.openWindow(placePanel, false)
	elseif not visible and placePanel.Visible then
		UIKit.closeWindow(placePanel, true)
	end
end

-- Cette méthode permet d'activer l'invite « Place » des présentoirs libres de sa base (et de nommer le mannequin à
-- poser) lorsque le joueur tient un mannequin gagné ; Heartbeat, tous les PROMPT_REFRESH s.
local function refreshPrompts()
	if os.clock() - lastPromptRefresh < PROMPT_REFRESH then
		return
	end
	lastPromptRefresh = os.clock()
	local entry = pendingEntry()
	local open = entry ~= nil and canPlace()
	local name = if entry then Collection.label(entry) else ""
	for _, prompt in myPrompts() do
		local enabled = open and not (prompt.Parent :: Instance):GetAttribute("Occupied")
		if prompt.Enabled ~= enabled then
			prompt.Enabled = enabled
		end
		prompt.ObjectText = name
	end
	refreshPanel()
end

-- Cette méthode permet d'envoyer la pose sur un présentoir lorsque le joueur déclenche son invite « Place ».
local function bindPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt.Triggered:Connect(function()
		if prompt:GetAttribute("Slot") == player:GetAttribute("Slot") then
			remotes.PlaceDummy:FireServer(prompt:GetAttribute("Display"))
		end
	end)
end

-- Cette méthode permet de savoir si un tirage est à l'écran lorsque d'autres éléments (objectif) doivent se taire.
function Prize.isShowing(): boolean
	return showing
end

-- Cette méthode permet de construire l'écran du tirage et le panneau de pose, et de les brancher sur les attributs du
-- joueur et les invites des présentoirs lorsque le client démarre.
function Prize.init(localPlayer: Player, createdRemotes: Remotes.Remotes, screen: ScreenGui)
	player = localPlayer
	remotes = createdRemotes
	gui = screen
	buildReveal()
	buildPlacePanel()
	for _, prompt in CollectionService:GetTagged(Collection.PROMPT_TAG) do
		bindPrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal(Collection.PROMPT_TAG):Connect(bindPrompt)
	for _, attribute in { "PendingDummy", "LaneState", "Action", "Slot" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			lastPromptRefresh = 0
			refreshPrompts()
		end)
	end
	-- Fin du résultat imposée par le serveur (délai dépassé) : on range le tirage sans renvoyer GO BACK
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") ~= "Result" and showing then
			cleanup()
		end
	end)
	RunService.Heartbeat:Connect(refreshPrompts)
end

return Prize
