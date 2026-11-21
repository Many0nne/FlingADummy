-- Objectif du tutoriel (4 étapes, Shared.Tutorial ; plus rien ensuite) au style des jeux de référence : texte blanc à contour en haut au centre, triangle jaune qui
-- flotte et pulse au-dessus de la cible (pièce du décor marquée, cf. Shared.Objectives) ou du bouton du HUD désigné, et file
-- de chevrons jaunes au sol qui défilent du joueur vers la cible.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Objectives = require(Shared:WaitForChild("Objectives"))
local Overlay = require(Shared:WaitForChild("Overlay"))
local Training = require(Shared:WaitForChild("Training"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))
local UIMotion = require(Shared:WaitForChild("UIMotion"))

local Hud = require(script.Parent.Hud)
local UIKit = require(script.Parent.UIKit)

local CHEVRON_COUNT = 12
local CHEVRON_SPACING = 3.5 -- studs entre deux chevrons
local CHEVRON_GAP = 2.5 -- studs laissés libres près du joueur et de la cible
local CHEVRON_SPEED = 6 -- studs/s de défilement vers la cible
local CHEVRON_ARM = 2.2 -- longueur d'une branche du chevron
local CHEVRON_WIDTH = 0.7 -- largeur d'une branche (chevrons francs, comme les références)
local CHEVRON_ANGLE = math.rad(42)
local ARROW_HEIGHT = 7 -- studs au-dessus de la cible
local ARROW_SIZE = 3 -- studs de côté de la flèche du décor (avant pulsation)
local ARROW_FLOAT = 0.5 -- studs de flottement de la flèche du décor
local HUD_ARROW_FLOAT = 8 -- px de flottement de la flèche d'interface
local TARGET_REFRESH = 0.2 -- s entre deux choix de cible
local LABEL_TOP = 36 -- px : haut du texte de l'objectif, écran libre

local Objective = {}

local player: Player
local label: TextLabel
local worldArrow: BillboardGui
local arrowAnchor: BasePart -- point invisible au-dessus de la cible : la flèche ne dépend pas de l'orientation de la cible
local hudArrow: GuiObject
local hudArrowScale: UIScale
local hudArrowBase = UDim2.new() -- position de repos de la flèche d'interface, sans le balancement
local hudArrowBob = Vector2.yAxis -- sens du balancement (vers le bouton)
local chevrons: { { BasePart } } = {}
local arrowOnEdge = false -- flèche d'interface sur un bouton du HUD (au bord de l'écran : placée sur le côté)
local arrowOnOffer = false -- flèche d'interface sur le popup « NEW GEAR! » (qui remplace alors le texte)
local current: Objectives.Objective? = nil
local targetPart: BasePart? = nil
local lastTargetPick = 0

-- Cette méthode permet de lire un attribut numérique du joueur (valeur par défaut si absent) lorsque l'état de
-- l'objectif est recalculé.
local function stat(name: string, default: number): number
	return (player:GetAttribute(name) :: number?) or default
end

-- Cette méthode permet de construire l'état du joueur (action, étape du tutoriel, achats possibles) lorsque
-- l'objectif est recalculé.
local function state(): Objectives.State
	local money = stat("Money", 0)
	local gearCost = Training.nextGearCost(stat("GearTier", 1))
	-- Rien avant le chargement : un ancien joueur ne doit pas voir passer la première étape
	local step = if player:GetAttribute("DataReady") == true then Tutorial.current(stat("Tutorial", 0)) else nil
	return {
		action = player:GetAttribute("Action") :: string?,
		laneState = player:GetAttribute("LaneState") :: string?,
		step = step,
		canBuyGear = gearCost ~= nil and money >= gearCost,
		hasPrize = player:GetAttribute("PendingDummy") ~= nil,
	}
end

-- Cette méthode permet de choisir la pièce du décor que suit le joueur pour l'objectif `kind` lorsque la cible est
-- recalculée ; nil si aucune ne lui est ouverte.
local function findTarget(kind: string, from: Vector3): BasePart?
	local candidates: { Objectives.Candidate } = {}
	local partOf: { [Objectives.Candidate]: BasePart } = {}
	for _, instance in CollectionService:GetTagged(Objectives.TAG) do
		if instance:IsA("BasePart") and instance:GetAttribute("Objective") == kind then
			local candidate = {
				position = instance.Position,
				slot = instance:GetAttribute("Slot") :: number?,
				owner = instance:GetAttribute("OwnerUserId") :: number?,
			}
			table.insert(candidates, candidate)
			partOf[candidate] = instance
		end
	end
	local chosen = Objectives.chooseTarget(candidates, player:GetAttribute("Slot") :: number?, player.UserId, from)
	return if chosen then partOf[chosen] else nil
end

-- Cette méthode permet de créer un chevron au sol (deux branches jaunes en « > ») lorsque le tracé est construit.
local function makeChevron(folder: Folder): { BasePart }
	local arms = {}
	for _ = 1, 2 do
		table.insert(
			arms,
			UIKit.create("Part", {
				Name = "Chevron",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = UIKit.COLORS.yellow,
				Size = Vector3.new(CHEVRON_WIDTH, 0.08, CHEVRON_ARM),
				Parent = folder,
			})
		)
	end
	return arms
end

-- Cette méthode permet de placer ou de ranger les chevrons entre les pieds du joueur et la cible lorsque l'image se
-- prépare.
local function updateChevrons(from: Vector3?, to: Vector3?)
	local points = {}
	if from and to then
		local phase = (os.clock() * CHEVRON_SPEED / CHEVRON_SPACING) % 1
		points = Objectives.chevrons(from, to, CHEVRON_SPACING, CHEVRON_GAP, phase, CHEVRON_COUNT)
	end
	local parts, frames = {}, {}
	local hidden = CFrame.new(0, -1000, 0)
	for i, arms in chevrons do
		local point = points[i]
		for side, arm in arms do
			local cf = hidden
			if point and from and to then
				local direction = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
				local tip = CFrame.lookAt(point, point + direction)
				local angle = if side == 1 then CHEVRON_ANGLE else -CHEVRON_ANGLE
				cf = tip
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(0, 0, CHEVRON_ARM / 2 - (arm.Size.X / 2) * math.tan(CHEVRON_ANGLE))
			end
			table.insert(parts, arm)
			table.insert(frames, cf)
		end
	end
	Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Cette méthode permet de placer la flèche d'interface à côté du bouton désigné, pointe vers lui : sur le côté pour
-- les boutons du HUD au bord de l'écran (elle masquerait le bouton voisin), au-dessus sinon (popup, carte d'une
-- fenêtre), lorsque l'objectif change.
local function placeHudArrow(anchor: GuiObject?)
	if not anchor then
		return
	end
	local screen = Workspace.CurrentCamera.ViewportSize.X
	local x = anchor.AbsolutePosition.X + anchor.AbsoluteSize.X / 2
	if arrowOnEdge and x < screen / 3 then
		hudArrow.AnchorPoint = Vector2.new(0, 0.5)
		hudArrow.Rotation = 90 -- pointe à gauche
		hudArrowBase = UDim2.new(1, 6, 0.5, 0)
		hudArrowBob = Vector2.xAxis
	elseif arrowOnEdge and x > screen * 2 / 3 then
		hudArrow.AnchorPoint = Vector2.new(1, 0.5)
		hudArrow.Rotation = -90 -- pointe à droite
		hudArrowBase = UDim2.new(0, -6, 0.5, 0)
		hudArrowBob = -Vector2.xAxis
	else
		hudArrow.AnchorPoint = Vector2.new(0.5, 1)
		hudArrow.Rotation = 0
		hudArrowBase = UDim2.new(0.5, 0, 0, -6)
		hudArrowBob = Vector2.yAxis
	end
end

-- Cette méthode permet de recalculer l'objectif (texte, cible) et de l'afficher lorsque l'état du joueur change.
local function refresh()
	local picked = Objectives.pick(state())
	if picked ~= current then
		current = picked
		targetPart = nil
		lastTargetPick = 0
		if picked then
			label.Text = picked.text
			UIKit.pop(label, 1.3)
		end
	end
end

-- Cette méthode permet de poser la flèche d'interface sur le bouton à cliquer (UPGRADE du popup « NEW GEAR! », sinon
-- bouton d'achat de la carte quand sa fenêtre est ouverte, sinon bouton du HUD qui l'ouvre) lorsque l'objectif, le
-- popup ou les fenêtres changent.
local function updateHudAnchor()
	local anchor: GuiObject? = nil
	local edge, onOffer = false, false
	if current and current.button then
		local buy = current.buy
		local offerButton = if buy == "Gear" then Hud.offerButton() else nil
		local cardButton = if buy then Hud.buyButton(buy) else nil
		if offerButton then
			anchor, onOffer = offerButton, true
		elseif cardButton then
			anchor = cardButton
		else
			anchor, edge = Hud.anchor(current.button), true
		end
	end
	arrowOnOffer = onOffer
	if anchor == hudArrow.Parent then
		return
	end
	arrowOnEdge = edge
	hudArrow.Parent = anchor
	hudArrow.Visible = anchor ~= nil
	placeHudArrow(anchor)
	hudArrow.Position = hudArrowBase -- pas d'image à l'ancienne place en changeant de bouton
end

-- Cette méthode permet d'animer le texte, la flèche et les chevrons à chaque image lorsque l'objectif est affiché.
local function step()
	updateHudAnchor()
	-- Texte en haut au centre : il se tait sous une fenêtre, un bandeau ou un popup, passe sous le popup d'offre, puis
	-- revient sans rejouer son apparition (Shared.Overlay) ; l'offre « NEW GEAR! » que la flèche désigne dit déjà quoi
	-- faire : le texte se tait
	local place = Overlay.objective({
		windowOpen = Hud.isWindowOpen(),
		bannerShown = Hud.isBannerShown(),
		popupShown = Hud.isPopupShown(),
		offerShown = Hud.isOfferShown(),
	})
	label.Visible = current ~= nil and not arrowOnOffer and place ~= "Hidden"
	label.Position = UDim2.new(0.5, 0, 0, if place == "BelowOffer" then Hud.OFFER_BOTTOM + 6 else LABEL_TOP)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local kind = current and current.target
	if kind and root and os.clock() - lastTargetPick > TARGET_REFRESH then
		lastTargetPick = os.clock()
		targetPart = findTarget(kind, root.Position)
	end
	local target = if kind then targetPart else nil
	-- Point visé : le centre de la cible, ou pour la bande de lancer son point le plus proche du joueur
	local aim = if target
		then Objectives.aimPoint(
			target.Position,
			target:GetAttribute("Span") :: number?,
			if root then root.Position else target.Position
		)
		else nil
	-- Flottement et pulsation calculés seulement pour une flèche affichée, coupés en mouvement réduit
	local now = os.clock()
	local reduced = UIKit.reducedMotion()
	worldArrow.Enabled = target ~= nil
	if aim then
		local pulse = UIMotion.pulse(now, reduced)
		worldArrow.Size = UDim2.fromScale(ARROW_SIZE * pulse, ARROW_SIZE * pulse)
		arrowAnchor.CFrame =
			CFrame.new(aim + Vector3.new(0, ARROW_HEIGHT + UIMotion.float(now, reduced) * ARROW_FLOAT, 0))
	end
	if hudArrow.Parent and hudArrow.Visible then
		placeHudArrow(hudArrow.Parent :: GuiObject) -- suit les changements de taille d'écran (rotation du mobile)
		-- Sur l'offre, réduite par son UIScale : la flèche garde la taille et le flottement qu'elle a ailleurs
		local compensate = if arrowOnOffer then 1 / Hud.OFFER_SCALE else 1
		local bob = UIMotion.float(now, reduced) * HUD_ARROW_FLOAT * compensate
		hudArrow.Position = hudArrowBase + UDim2.fromOffset(hudArrowBob.X * bob, hudArrowBob.Y * bob)
		hudArrowScale.Scale = UIMotion.pulse(now, reduced) * compensate
	end
	if aim and root and humanoid then
		local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - 0.12, 0)
		updateChevrons(feet, Vector3.new(aim.X, feet.Y, aim.Z))
	else
		updateChevrons(nil, nil)
	end
end

-- Cette méthode permet de construire le texte, les flèches et les chevrons de l'objectif et de les brancher sur les
-- attributs du joueur lorsque le client démarre.
function Objective.init(localPlayer: Player, gui: ScreenGui)
	player = localPlayer
	label = UIKit.text({
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, LABEL_TOP),
		Size = UDim2.fromOffset(640, 40),
		TextSize = 34,
		Visible = false,
		Parent = gui,
	})
	local folder = UIKit.create("Folder", { Name = "ObjectiveMarkers", Parent = Workspace })
	arrowAnchor = UIKit.create("Part", {
		Name = "ArrowAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		Parent = folder,
	})
	worldArrow = UIKit.create("BillboardGui", {
		Name = "ObjectiveArrow",
		Adornee = arrowAnchor,
		ResetOnSpawn = false, -- sinon détruite à la réapparition de l'avatar
		LightInfluence = 0,
		Size = UDim2.fromScale(ARROW_SIZE, ARROW_SIZE),
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.icon("arrow", { Size = UDim2.fromScale(1, 1), Parent = worldArrow })
	hudArrow = UIKit.icon("arrow", {
		Name = "ObjectiveArrow",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 6,
		Visible = false,
	})
	hudArrowScale = UIKit.scaleOf(hudArrow)
	for i = 1, CHEVRON_COUNT do
		chevrons[i] = makeChevron(folder)
	end

	for _, attribute in { "Action", "LaneState", "Money", "GearTier", "PendingDummy", "Tutorial", "DataReady" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	RunService.RenderStepped:Connect(step)
	refresh()
end

return Objective
