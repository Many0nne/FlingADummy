-- Tirage « 1 en N » et pose du mannequin gagné, calés sur les références. Suspense (09 et 01) : silhouette noire
-- debout au point d'atterrissage et cote qui défile en continu (« 1 IN 1 » → 2 → 3 … de plus en plus lentement,
-- Collection.climbOdds) ; à chaque palier atteint la silhouette se change en candidat plus rare (teaseSequence), chaque
-- palier marqué d'un éclair blanc, d'étincelles, d'un anneau, d'une secousse et d'une exclamation colorée en haut
-- (« Lucky! 1 IN 10 » → « Super lucky! 1 IN 150 »), puis roulement (la silhouette tremble) et révélation : éclair
-- plein écran, mannequin en couleurs qui grossit, rayons ; rareté, nom, « NEW! », $/s et cote une seule fois, en haut
-- au centre (comme 09) ; bouton GO BACK. De retour au hub, panneau « Place your … » en bas au centre : la première
-- pose se fait à la main (tutoriel : flèche vers un présentoir libre, invite « Place »). Ensuite la pose s'appuie sur
-- la barre d'outils (#54) : mannequin équipé près d'un présentoir libre → invite « Place » ; le bouton AUTO, dans sa
-- base ou tout près, pose le mannequin tenu, sinon le dernier gagné. La barre d'outils n'apparaît qu'au hub, libre.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BackpackPlan = require(Shared:WaitForChild("BackpackPlan"))
local Collection = require(Shared:WaitForChild("Collection"))
local CourseLayout = require(Shared:WaitForChild("CourseLayout"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))

local FlightCamera = require(script.Parent.FlightCamera)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local FEET = 3.82 -- du centre du torse au bas des pieds, échelle 1 (Shared.DummyShape)
local HEIGHT = 6.7 -- hauteur du mannequin debout, échelle 1 (studs)
local TEASE_FIRST = 0.45 -- silhouette seule avant le premier palier (s)
local TEASE_PAUSE = 0.45 -- arrêt sur chaque palier atteint (éclair, exclamation) avant que la cote reparte (s)
local TICK_GAP = 0.045 -- écart minimal entre deux tics du compteur de cote (s)
local DRUMROLL = 1.1 -- roulement avant la révélation : la silhouette tremble de plus en plus (s)
local AUTO_CLOSE = 5 -- GO BACK automatique après la révélation (s)
local PROMPT_REFRESH = 0.25 -- s entre deux mises à jour des invites « Place »
local AUTO_BOTTOM = 96 -- marge du bouton AUTO au bas de l'écran (px) : au-dessus de la barre d'outils Roblox
local BLACK = Color3.fromRGB(12, 12, 16)
-- Exclamation de chaque palier selon la rareté du candidat (« Super chanceux ! », « Chance incroyable ! » de 01)
local EXCLAIM =
	{ "Hmm…", "Lucky!", "Super lucky!", "Incredible luck!", "LEGENDARY LUCK!", "MYTHIC LUCK!", "SECRET!!!" }

local Prize = {}

local player: Player
local remotes: Remotes.Remotes
local gui: ScreenGui
local token = 0
local showing = false -- tirage à l'écran (GO BACK pas encore envoyé)
local worldModel: Model? = nil
local glow: Highlight? = nil -- contour de la silhouette, à la couleur du palier
-- Suspense (haut de l'écran) : exclamation et cote du palier
local tease: Frame
local exclaimLabel: TextLabel
local teaseOdds: TextLabel
local flash: Frame -- éclair blanc plein écran de la révélation
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
local placeAuto: TextButton
local placeKey: string? = nil
local lastPromptRefresh = 0
local backpackShown: boolean? = nil -- barre d'outils Roblox affichée (dernier état demandé)
local glows: { [Instance]: Highlight } = {} -- présentoirs libres en surbrillance pendant qu'on tient un mannequin

-- Cette méthode permet de relire le dernier mannequin gagné encore à poser (« id:taille », il est dans le stock)
-- lorsque l'attribut PendingDummy change ; nil s'il n'y en a pas ou qu'il est illisible.
local function pendingEntry(): Collection.Entry?
	return Inventory.parseKey(player:GetAttribute("PendingDummy"))
end

-- Cette méthode permet de donner le mannequin que le joueur tient (outil du Backpack équipé) lorsque les invites
-- « Place » et le bouton AUTO se mettent à jour ; nil s'il n'en tient pas.
local function heldEntry(): Collection.Entry?
	local _, key = BackpackPlan.held(player.Character)
	return Inventory.parseKey(key)
end

-- Cette méthode permet de savoir si la première pose du tutoriel reste à faire (panneau « Place your … », pose à la
-- main du dernier gagné) lorsque le panneau et les invites se mettent à jour.
local function firstPlacePending(): boolean
	return Tutorial.current((player:GetAttribute("Tutorial") :: number?) or 0) == "Place"
end

-- Cette méthode permet de donner le mannequin que l'invite « Place » et AUTO poseraient lorsque l'on les met à jour :
-- celui que le joueur tient, sinon le dernier gagné (AUTO, et invite pendant la première pose du tutoriel).
local function toPlace(): (Collection.Entry?, boolean)
	local held = if firstPlacePending() then nil else heldEntry()
	if held then
		return held, true
	end
	return pendingEntry(), false
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
	local scale = Collection.scale(entry)
	local variant: any = Collection.variant(entry)
	if silhouette then
		variant = { color = BLACK, accessories = variant.accessories, accessoryColor = BLACK, hidden = variant.hidden }
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

-- Cette méthode permet de faire grossir un mannequin du tirage (depuis `from` de sa taille, petit rebond) lorsqu'il
-- apparaît : silhouette d'un nouveau palier, ou mannequin révélé.
local function growIn(model: Model, from: number?)
	local low = from or 0.6
	local start = os.clock()
	model:ScaleTo(low)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - start) / 0.3, 0, 1)
		if not model.Parent then
			connection:Disconnect()
			return
		end
		-- Dépasse un peu (1,08) à 70 % puis revient à 1
		local value = if k < 0.7 then low + (1.08 - low) * (k / 0.7) else 1.08 - 0.08 * ((k - 0.7) / 0.3)
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

-- Cette méthode permet de faire éclater un palier du suspense au centre `center` (éclair blanc qui gonfle et
-- s'efface, gerbe d'étincelles, contour de la silhouette qui flashe) lorsque la silhouette change de candidat.
local function burst(center: Vector3, scale: number, color: Color3)
	local ball = UIKit.create("Part", {
		Name = "TeaseBurst",
		Shape = Enum.PartType.Ball,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = Color3.new(1, 1, 1),
		Transparency = 0.1,
		Size = Vector3.one * 2,
		Position = center,
		Parent = Workspace,
	})
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * (7 * scale + 2),
		Transparency = 1,
	}):Play()
	local holder = UIKit.create("Attachment", { WorldPosition = center, Parent = Workspace.Terrain })
	local sparks = UIKit.create("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.new(1, 1, 1), color),
		LightEmission = 1,
		Size = NumberSequence.new(0.9 * scale, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(10 * scale, 22 * scale),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Enabled = false,
		Parent = holder,
	})
	sparks:Emit(28)
	if glow then
		glow.OutlineColor = color
		glow.FillTransparency = 0.1
		TweenService:Create(glow, TweenInfo.new(0.4), { FillTransparency = 1 }):Play()
	end
	task.delay(1.2, function()
		ball:Destroy()
		holder:Destroy()
	end)
end

-- Cette méthode permet de remplacer la silhouette du tirage par celle d'un candidat (`step`), contour lumineux à la
-- couleur de sa rareté, lorsque le suspense passe au palier suivant.
local function showSilhouette(step: Collection.TeaseStep, ground: Vector3)
	if worldModel then
		worldModel:Destroy()
	end
	local model = buildStanding({ id = step.id, size = step.size }, ground, true)
	worldModel = model
	glow = UIKit.create("Highlight", {
		DepthMode = Enum.HighlightDepthMode.Occluded,
		FillColor = Color3.new(1, 1, 1),
		FillTransparency = 1,
		OutlineColor = Rarity.get(step.rarity).color,
		OutlineTransparency = 0,
		Parent = model,
	})
	growIn(model, 0.8)
end

-- Cette méthode permet de faire trembler la silhouette de plus en plus fort pendant `duration` s (roulement avant la
-- révélation) lorsque le dernier palier est affiché ; s'arrête si le tirage est interrompu (`current` périmé).
local function drumroll(model: Model, scale: number, duration: number, current: number)
	local base = model:GetPivot()
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - start) / duration
		if k >= 1 or current ~= token or not model.Parent then
			connection:Disconnect()
			if model.Parent then
				model:PivotTo(base)
			end
			return
		end
		local amount = 0.04 + 0.22 * k * k
		local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2 * amount * scale
		model:PivotTo(base + offset)
		FlightCamera.shake(0.02 + 0.05 * k)
	end)
end

-- Cette méthode permet de faire défiler la cote affichée de `from` à `to` (vite puis de plus en plus lentement, un
-- tic à chaque chiffre, de plus en plus aigu) lorsque le suspense monte vers le palier `index` ; cède jusqu'à la fin
-- et renvoie false si le tirage a été interrompu.
local function climb(from: number, to: number, index: number, current: number): boolean
	local duration = Collection.climbTime(from, to)
	local start = os.clock()
	local last = from
	local lastTick = 0
	while true do
		if current ~= token then
			return false
		end
		local t = (os.clock() - start) / duration
		local value = Collection.climbOdds(from, to, t)
		if value ~= last then
			last = value
			teaseOdds.Text = "1 IN " .. Format.short(value)
			local now = os.clock()
			if now - lastTick >= TICK_GAP then
				lastTick = now
				UIKit.playSound("Click", 0.7 + 0.25 * index + 0.4 * math.min(t, 1))
			end
		end
		if t >= 1 then
			return true
		end
		task.wait()
	end
end

-- Cette méthode permet de retirer le mannequin du tirage, le suspense, l'écran de révélation et les rayons lorsque le
-- tirage se termine (GO BACK, fin forcée par le serveur, nouveau lancer).
local function cleanup()
	token += 1
	showing = false
	player:SetAttribute("PrizePhase", nil) -- phase du tirage, locale (Client.Music)
	if worldModel then
		worldModel:Destroy()
		worldModel = nil
	end
	glow = nil
	if rays then
		rays:Destroy()
		rays = nil
	end
	UIKit.closeWindow(tease, true)
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
	local size = Collection.SIZES[entry.size]
	local scale = Collection.scale(entry)
	if worldModel then
		worldModel:Destroy()
	end
	glow = nil
	local model = buildStanding(entry, ground, false)
	worldModel = model
	player:SetAttribute("PrizePhase", if prize.isNew then "RevealNew" else "Reveal") -- fanfare : nouveau seulement
	growIn(model)
	ring(ground, scale)
	burst(ground + Vector3.new(0, HEIGHT * scale / 2, 0), scale, Rarity.get(prize.rarity).color)
	FlightCamera.shake(0.6)
	-- Éclair blanc plein écran, comme le flash de révélation des références
	flash.BackgroundTransparency = 0.15
	flash.Visible = true
	local fade = TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 })
	fade.Completed:Once(function()
		flash.Visible = false
	end)
	fade:Play()
	UIKit.closeWindow(tease, true)
	local tier = Rarity.get(prize.rarity)
	-- « BIG · RARE » comme « Grand et rare » de 09 (taille seulement si elle n'est pas normale)
	rarityLabel.Text = if size.name ~= ""
		then string.upper(size.name) .. " · " .. string.upper(tier.name)
		else string.upper(tier.name)
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
	player:SetAttribute("PrizePhase", "Tease")
	local finalScale = Collection.scale(entry :: Collection.Entry)
	local ground = groundAt(result.landing)
	FlightCamera.showcase(ground + Vector3.new(0, HEIGHT * finalScale / 2, 0), HEIGHT * finalScale)
	local sequence = Collection.teaseSequence(entry :: Collection.Entry)
	-- Silhouette du premier candidat, seule un instant, avant le premier palier
	showSilhouette(sequence[1], ground)
	task.spawn(function()
		task.wait(TEASE_FIRST)
		-- La cote défile en continu depuis 1 ; chaque palier atteint change la silhouette en son candidat et éclate
		exclaimLabel.Text = ""
		teaseOdds.Text = "1 IN 1"
		teaseOdds.TextColor3 = Color3.new(1, 1, 1)
		UIKit.openWindow(tease, false)
		local shown = 1
		for index, step in sequence do
			if not climb(shown, step.odds, index, current) then
				return
			end
			shown = step.odds
			local scale = Collection.scale({ id = step.id, size = step.size })
			if index > 1 then
				showSilhouette(step, ground)
			end
			local tier = Rarity.get(step.rarity)
			burst(ground + Vector3.new(0, HEIGHT * scale / 2, 0), scale, tier.color)
			ring(ground, scale)
			FlightCamera.shake(0.25 + 0.2 * index)
			exclaimLabel.Text = EXCLAIM[math.clamp(step.rarity, 1, #EXCLAIM)]
			exclaimLabel.TextColor3 = tier.color
			teaseOdds.TextColor3 = tier.color:Lerp(Color3.new(1, 1, 1), 0.5)
			UIKit.pop(exclaimLabel, 1.6)
			UIKit.pop(teaseOdds, 1.4)
			UIKit.playSound("Whoosh", 1.2 + index * 0.15)
			task.wait(TEASE_PAUSE)
		end
		if current ~= token or not worldModel then
			return
		end
		-- Roulement : la dernière silhouette tremble de plus en plus, puis éclate en couleurs
		drumroll(worldModel :: Model, finalScale, DRUMROLL, current)
		UIKit.playSound("Crowd", 1.1)
		task.wait(DRUMROLL)
		if current == token then
			showReveal(prize, entry :: Collection.Entry, ground, current)
		end
	end)
end

-- Cette méthode permet de construire l'écran de révélation (suspense puis révélation, haut au centre), l'éclair
-- plein écran et le bouton GO BACK lorsque le client démarre.
local function buildReveal()
	tease = UIKit.create("Frame", {
		Name = "PrizeTease",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(560, 120),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	exclaimLabel = UIKit.text({
		Size = UDim2.new(1, 0, 0, 52),
		TextSize = 46,
		StrokeThickness = 4,
		Rotation = -3,
		ZIndex = 21,
		Parent = tease,
	})
	teaseOdds = UIKit.text({
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 60),
		TextSize = 56,
		StrokeThickness = 4,
		ZIndex = 21,
		Parent = tease,
	})
	flash = UIKit.create("Frame", {
		Name = "RevealFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 19,
		Parent = gui,
	})
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

-- Cette méthode permet de construire le panneau « Place your … » (rendu 3D, titre, consigne ; tutoriel seulement) et le
-- bouton AUTO compact, en bas au centre, lorsque le client démarre.
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
	-- Bouton AUTO compact, hors panneau : seul à l'écran une fois le tutoriel fini, au-dessus de la barre d'outils
	placeAuto = UIKit.button({
		Name = "Auto",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -AUTO_BOTTOM),
		Size = UDim2.fromOffset(130, 44),
		Text = "AUTO",
		TextSize = 28,
		Shine = true,
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	}, function()
		remotes.PlaceDummy:FireServer(nil)
	end)
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

-- Cette méthode permet d'afficher le panneau « Place your … » pendant l'étape « Place » du tutoriel, ou le bouton AUTO
-- près de sa base ensuite, lorsque le mannequin en main ou l'état du joueur changent.
local function refreshPanel()
	local free = canPlace()
	local firstPlace = firstPlacePending()
	-- Barre d'outils (Backpack) seulement au hub, libre : ni pendant la jauge, le vol, le tirage ou l'entraînement, ni
	-- pendant la première pose du tutoriel (le panneau « Place your … » occupe sa place)
	local showBar = free and not firstPlace
	if showBar ~= backpackShown then
		backpackShown = showBar
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, showBar)
	end
	local entry = pendingEntry()
	local ready = entry ~= nil and free
	local visible = ready and firstPlace
	-- Hors tutoriel : seul le bouton AUTO compact, dans sa base ou tout près
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local slot = player:GetAttribute("Slot")
	local near = root ~= nil and typeof(slot) == "number" and CourseLayout.isNearBase(slot, root.Position)
	-- AUTO pose le mannequin tenu, sinon le dernier gagné ; caché si la règle AUTO ne lui trouve aucun présentoir (base
	-- pleine de plus rentables : un clic ne ferait rien)
	local candidate = toPlace()
	local target = candidate
		and Inventory.autoTarget({
			base = Inventory.decodeBase(player:GetAttribute("BaseDummies")),
			displays = (player:GetAttribute("Displays") :: number?) or 0,
			stock = {},
			index = {},
		}, candidate)
	placeAuto.Visible = free and target ~= nil and near and not firstPlace
	if visible and entry then
		local key = Inventory.key(entry)
		if key ~= placeKey then
			placeKey = key
			local dummy = Collection.get(entry.id) :: Collection.Dummy
			placeTitle.Text = "Place your " .. Collection.label(entry) .. "!"
			placeTitle.TextColor3 = Rarity.get(dummy.rarity).color
			UIKit.showModel(placeViewport, DummyShape.buildVisual(1, Collection.variant(entry) :: any))
		end
		-- Tutoriel : pose à la main sur un présentoir libre
		placeHint.Text = "Walk to a glowing display in your base!"
	end
	if visible and not placePanel.Visible then
		UIKit.openWindow(placePanel, false)
	elseif not visible and placePanel.Visible then
		UIKit.closeWindow(placePanel, true)
	end
end

-- Cette méthode permet d'activer l'invite « Place » des présentoirs achetés libres de sa base (et de nommer le
-- mannequin à poser) lorsque le joueur a un mannequin gagné à poser ; Heartbeat, tous les PROMPT_REFRESH s.
local function refreshPrompts()
	if os.clock() - lastPromptRefresh < PROMPT_REFRESH then
		return
	end
	lastPromptRefresh = os.clock()
	-- Hors tutoriel, l'invite pose le mannequin tenu ; pendant la première pose, aussi le dernier gagné (panneau)
	local entry, held = toPlace()
	local open = entry ~= nil and canPlace() and (held or firstPlacePending())
	local name = if entry then Collection.label(entry) else ""
	for _, prompt in myPrompts() do
		local display = prompt.Parent :: Instance
		local enabled = open and not display:GetAttribute("Occupied") and not display:GetAttribute("Locked")
		if prompt.Enabled ~= enabled then
			prompt.Enabled = enabled
		end
		prompt.ObjectText = name
		-- Présentoirs libres en surbrillance (vu par ce joueur seulement) tant qu'il a un mannequin à poser
		local highlight = glows[display]
		if enabled and not highlight then
			glows[display] = UIKit.create("Highlight", {
				DepthMode = Enum.HighlightDepthMode.Occluded,
				FillColor = C.yellow,
				FillTransparency = 0.55,
				OutlineColor = Color3.new(1, 1, 1),
				Adornee = display,
				Parent = display,
			})
		elseif not enabled and highlight then
			highlight:Destroy()
			glows[display] = nil
		end
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
	for _, attribute in { "PendingDummy", "LaneState", "Action", "Slot", "Tutorial" } do
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
