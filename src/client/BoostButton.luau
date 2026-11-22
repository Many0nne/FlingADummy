-- Bouton « 2x TRAINING! » de l'entraînement (#119, Shared.TrainingBoost) : à l'annonce du serveur, un gros bouton rond
-- vert (icône de puissance, « 2x », bandeau « TRAINING! ») surgit en rebond à un endroit au hasard du centre de l'écran,
-- entouré d'un anneau jaune qui se vide en BOOST_OFFER_TIME s (grammaire des boosts « x2 Training » de 01 et 02).
-- Cliqué : le serveur valide, puis popup « 2x TRAINING! », barre de durée « 2x 0:24 » à droite du STOP (au-dessus de
-- la barre d'EXP), contour doré et étincelles sur l'avatar (étincelles coupées en mouvement réduit). Raté : il
-- disparaît. Rien d'autre ne bouge : pas de boucle par image, un minuteur pendant le bonus.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local TrainingBoost = require(Shared:WaitForChild("TrainingBoost"))
local UIMotion = require(Shared:WaitForChild("UIMotion"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local RING = 184 -- px : diamètre extérieur de l'anneau de compte à rebours
local RING_WIDTH = 10 -- px : épaisseur de l'anneau
local DISC = 140 -- px : diamètre du bouton
-- Zone d'apparition (centre du bouton, fraction de l'écran) : sous les popups du haut, au-dessus du STOP, de la barre
-- d'EXP et des « +N EXP », loin des colonnes de boutons
local AREA_X = { 0.3, 0.7 }
local AREA_Y = { 0.42, 0.58 }
local GOLD = Color3.fromRGB(255, 200, 40)
local MIN_SHOWN = 0.4 -- s : une annonce qui laisse moins de temps que ça n'est pas montrée (clic impossible à temps)

local BoostButton = {}

type Hooks = {
	trainBar: Frame, -- barre d'entraînement du HUD (STOP, barre d'EXP)
	popup: (UIKit.PopupOptions) -> (),
}

local player: Player
local remote: RemoteEvent
local hooks: Hooks
local holder: Frame -- bouton, anneau et bandeau
local disc: TextButton
local halves: { UIGradient } = {} -- moitiés droite puis gauche de l'anneau
local offerId: number? = nil -- apparition affichée (nil : bouton caché)
local offerToken = 0 -- invalide la disparition programmée d'une apparition remplacée ou cliquée
local pill: Frame -- barre de durée du bonus
local pillFill: Frame
local pillLabel: TextLabel
local shownEnds: number? = nil -- fin du bonus affichée (temps serveur)
local aura: { Instance } = {} -- contour et étincelles de l'avatar pendant le bonus

-- Cette méthode permet de construire une moitié de l'anneau (cadre qui coupe la moitié `side` d'un cercle tracé en
-- jaune, dégradé de transparence à bord franc qui tourne pour la vider) lorsque le bouton est construit.
local function buildHalf(ring: Frame, side: string): UIGradient
	local right = side == "Right"
	local clip = UIKit.create("Frame", {
		Name = side,
		Position = UDim2.fromScale(if right then 0.5 else 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = ring,
	})
	-- Contour tracé hors du cadre : le cercle est réduit de l'épaisseur pour que l'anneau tienne dans RING
	local inner = RING - 2 * RING_WIDTH
	local circle = UIKit.create("Frame", {
		Position = UDim2.fromOffset(RING_WIDTH - (if right then RING / 2 else 0), RING_WIDTH),
		Size = UDim2.fromOffset(inner, inner),
		BackgroundTransparency = 1,
		Parent = clip,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = circle })
	local stroke = UIKit.outline(circle, RING_WIDTH, C.yellow)
	-- Opaque sur la moitié gauche à 0° ; 180° : moitié droite (sens horaire)
	return UIKit.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.499, 0),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = if right then 180 else 0,
		Parent = stroke,
	})
end

-- Cette méthode permet de construire le bouton (caché) : anneau sombre et anneau jaune, disque vert à icône et
-- « 2x », bandeau « TRAINING! » lorsque le client démarre.
local function buildButton(gui: ScreenGui, onClick: () -> ())
	holder = UIKit.create("Frame", {
		Name = "BoostButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(RING, RING + 26),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	local ring = UIKit.create("Frame", {
		Name = "Ring",
		Size = UDim2.fromOffset(RING, RING),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = holder,
	})
	-- Piste sombre sous l'anneau : la part écoulée reste visible
	local track = UIKit.create("Frame", {
		Position = UDim2.fromOffset(RING_WIDTH, RING_WIDTH),
		Size = UDim2.fromOffset(RING - 2 * RING_WIDTH, RING - 2 * RING_WIDTH),
		BackgroundTransparency = 1,
		Parent = ring,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = track })
	UIKit.outline(track, RING_WIDTH, C.ink).Transparency = 0.35
	halves = { buildHalf(ring, "Right"), buildHalf(ring, "Left") }
	disc = UIKit.button({
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(RING / 2, RING / 2),
		Size = UDim2.fromOffset(DISC, DISC),
		Radius = DISC / 2,
		Text = "",
		ZIndex = 21,
		Shine = true,
		Parent = holder,
	}, onClick)
	-- Contour épais des boutons d'offre des références
	for _, child in disc:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child.Thickness = 5
		end
	end
	UIKit.icon("power", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromScale(0.46, 0.46),
		ZIndex = 22,
		Parent = disc,
	})
	UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(1, 0.36),
		Text = "2x",
		TextSize = 46,
		StrokeThickness = 3,
		ZIndex = 22,
		Parent = disc,
	})
	local ribbon = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(RING + 40, 44),
		Text = "TRAINING!",
		TextSize = 38,
		StrokeThickness = 3,
		ZIndex = 23,
		Parent = holder,
	})
	UIKit.gradientText(ribbon, C.yellow, C.orange)
end

-- Cette méthode permet de construire la barre de durée du bonus (pastille dorée « 2x 0:24 » qui se vide, à droite du
-- STOP, au-dessus de la barre d'EXP) lorsque le client démarre.
local function buildPill(trainBar: Frame)
	pill = UIKit.create("Frame", {
		Name = "BoostTimer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(138, 44),
		BackgroundColor3 = Color3.fromRGB(120, 60, 10),
		Visible = false,
		Parent = trainBar,
	})
	UIKit.corner(pill, 10)
	UIKit.outline(pill, 3)
	pillFill = UIKit.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.orange,
		Parent = pill,
	})
	UIKit.corner(pillFill, 10)
	UIKit.shade(pillFill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	pillLabel = UIKit.text({
		Size = UDim2.fromScale(1, 1),
		Text = "2x 0:30",
		TextSize = 28,
		ZIndex = 2,
		Parent = pill,
	})
end

-- Cette méthode permet de cacher le bouton (rétréci, sauf en mouvement réduit) lorsque l'apparition est cliquée,
-- ratée ou annulée.
local function hideButton()
	offerId = nil
	offerToken += 1
	if not holder.Visible then
		return
	end
	if UIKit.reducedMotion() then
		holder.Visible = false
		return
	end
	local token = offerToken
	UIKit.scaleTo(holder, 0, 0.15, Enum.EasingStyle.Back)
	task.delay(0.16, function()
		if token == offerToken then
			holder.Visible = false
		end
	end)
end

-- Cette méthode permet de vider l'anneau dans le sens horaire depuis midi (moitié droite, puis moitié gauche) en
-- `left` s, à partir de la part déjà écoulée, lorsque le bouton apparaît pour l'apparition `token`.
local function drainRing(token: number, left: number)
	local total = GameConfig.BOOST_OFFER_TIME
	local elapsed = math.clamp(1 - left / total, 0, 1) -- part du tour déjà écoulée (annonce arrivée en retard)
	local right, leftHalf = halves[1], halves[2]
	-- Cette méthode permet de vider la moitié gauche (rotation 0 → 180) depuis la part `from` du tour lorsque la
	-- moitié droite est vide.
	local function drainLeft(from: number)
		leftHalf.Rotation = (from - 0.5) * 360
		TweenService:Create(leftHalf, TweenInfo.new((1 - from) * total, Enum.EasingStyle.Linear), { Rotation = 180 })
			:Play()
	end
	if elapsed >= 0.5 then
		right.Rotation = 360
		drainLeft(elapsed)
		return
	end
	right.Rotation, leftHalf.Rotation = 180 + elapsed * 360, 0
	local first = TweenService:Create(right, TweenInfo.new((0.5 - elapsed) * total, Enum.EasingStyle.Linear), {
		Rotation = 360,
	})
	first.Completed:Once(function()
		if token == offerToken then
			drainLeft(0.5)
		end
	end)
	first:Play()
end

-- Cette méthode permet de montrer l'apparition `id` (endroit au hasard, rebond, son, anneau qui se vide) lorsque le
-- serveur l'annonce pendant la séance ; elle disparaît seule à `deadline` (fin de l'affichage en temps serveur), quand
-- le serveur cesse d'attendre le clic.
local function showOffer(id: number, deadline: unknown)
	local left = TrainingBoost.offerTimeLeft(deadline, Workspace:GetServerTimeNow())
	-- Annonce arrivée trop tard pour être cliquée à temps : rien à montrer
	if player:GetAttribute("Action") ~= "Training" or left < MIN_SHOWN then
		return
	end
	offerId = id
	offerToken += 1
	local token = offerToken
	holder.Position = UDim2.fromScale(
		AREA_X[1] + (AREA_X[2] - AREA_X[1]) * math.random(),
		AREA_Y[1] + (AREA_Y[2] - AREA_Y[1]) * math.random()
	)
	holder.Visible = true
	disc:SetAttribute("Disabled", nil)
	if UIKit.reducedMotion() then
		UIKit.scaleOf(holder).Scale = 1
	else
		UIKit.playKeys(holder, UIMotion.POPUP_IN)
	end
	UIKit.playSound("BoostAppear", 1.3)
	drainRing(token, left)
	task.delay(left, function()
		if token == offerToken then
			hideButton()
		end
	end)
end

-- Cette méthode permet d'envoyer le clic de l'apparition affichée au serveur lorsque le joueur touche le bouton.
local function onClick()
	local id = offerId
	if not id then
		return
	end
	disc:SetAttribute("Disabled", true)
	remote:FireServer(id)
	hideButton()
end

-- Cette méthode permet d'habiller l'avatar pendant le bonus (contour doré, étincelles sauf en mouvement réduit) ou de
-- le déshabiller lorsque le bonus commence ou finit.
local function dressAvatar(on: boolean)
	for _, instance in aura do
		instance:Destroy()
	end
	aura = {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not on or not character or not root then
		return
	end
	table.insert(
		aura,
		UIKit.create("Highlight", {
			Name = "BoostGlow",
			FillColor = GOLD,
			FillTransparency = 0.8,
			OutlineColor = GOLD,
			OutlineTransparency = 0.1,
			DepthMode = Enum.HighlightDepthMode.Occluded,
			Parent = character,
		})
	)
	if not UIKit.reducedMotion() then
		table.insert(
			aura,
			UIKit.create("ParticleEmitter", {
				Name = "BoostSparkles",
				Texture = "rbxasset://textures/particles/sparkles_main.dds",
				Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 255, 200)),
				LightEmission = 1,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(0.6, 1),
				Rate = 18,
				Speed = NumberRange.new(3, 5),
				SpreadAngle = Vector2.new(180, 180),
				Parent = root,
			})
		)
	end
end

-- Cette méthode permet de suivre le bonus accordé par le serveur (attribut TrainBoostEnds) : popup et son au début,
-- barre de durée et avatar habillé pendant, tout retiré à la fin.
local function onBoostChanged()
	local ends = player:GetAttribute("TrainBoostEnds")
	local active = TrainingBoost.displayMultiplier(ends, Workspace:GetServerTimeNow()) > 1
	if not active then
		shownEnds = nil
		pill.Visible = false
		dressAvatar(false)
		return
	end
	local started = shownEnds == nil
	shownEnds = ends :: number
	local remaining = (ends :: number) - Workspace:GetServerTimeNow()
	pill.Visible = true
	pillFill.Size = UDim2.fromScale(math.clamp(remaining / GameConfig.BOOST_TIME, 0, 1), 1)
	TweenService:Create(pillFill, TweenInfo.new(math.max(remaining, 0), Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(0, 1),
	}):Play()
	pillLabel.Text = "2x " .. TrainingBoost.remainingText(remaining)
	if not started then
		return
	end
	hooks.popup({
		title = "2x TRAINING!",
		subtitle = string.format("EXP x%d for %ds", GameConfig.BOOST_MULTIPLIER, GameConfig.BOOST_TIME),
		subtitleColor = C.orange,
		colors = { Color3.fromRGB(150, 255, 110), Color3.fromRGB(40, 175, 60) },
	})
	UIKit.playSound("BoostStart", 1.5)
	if not UIKit.reducedMotion() then
		UIKit.playKeys(pill, UIMotion.POPUP_IN)
	end
	dressAvatar(true)
	-- Compte à rebours, une fois par seconde, tant que ce bonus dure
	task.spawn(function()
		while shownEnds == ends do
			local left = (ends :: number) - Workspace:GetServerTimeNow()
			if left <= 0 then
				onBoostChanged() -- fin vue avant l'attribut (séance encore ouverte) : barre retirée
				break
			end
			pillLabel.Text = "2x " .. TrainingBoost.remainingText(left)
			task.wait(math.min(left - math.floor(left) + 0.02, 1))
		end
	end)
end

-- Cette méthode permet de brancher le bouton « 2x TRAINING! » (annonces du serveur, clic, bonus accordé) lorsque le
-- HUD est construit ; `boostRemote` : remote TrainingBoost, `gui` : ScreenGui du HUD.
function BoostButton.init(localPlayer: Player, boostRemote: RemoteEvent, gui: ScreenGui, hudHooks: Hooks)
	player = localPlayer
	remote = boostRemote
	hooks = hudHooks
	buildButton(gui, onClick)
	buildPill(hooks.trainBar)
	remote.OnClientEvent:Connect(function(kind, id, deadline)
		if kind == "Offer" and typeof(id) == "number" then
			showOffer(id, deadline)
		elseif kind == "Cancel" then
			hideButton()
		end
	end)
	player:GetAttributeChangedSignal("Action"):Connect(function()
		if player:GetAttribute("Action") ~= "Training" then
			hideButton()
		end
	end)
	player:GetAttributeChangedSignal("TrainBoostEnds"):Connect(onBoostChanged)
	-- Avatar réapparu pendant un bonus (rare : la séance s'arrête) : contour remis ou retiré selon l'attribut
	player.CharacterAdded:Connect(function()
		dressAvatar(shownEnds ~= nil)
	end)
	onBoostChanged()
end

return BoostButton
