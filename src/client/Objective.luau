-- Objectif du moment au style des jeux de référence : texte blanc à contour en haut au centre, triangle jaune qui
-- flotte au-dessus de la cible (pièce du décor marquée, cf. Shared.Objectives) ou du bouton du HUD désigné, et file
-- de chevrons jaunes au sol qui défilent du joueur vers la cible.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Objectives = require(Shared:WaitForChild("Objectives"))
local Training = require(Shared:WaitForChild("Training"))

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
local TARGET_REFRESH = 0.2 -- s entre deux choix de cible

local Objective = {}

local player: Player
local label: TextLabel
local worldArrow: BillboardGui
local arrowAnchor: BasePart -- point invisible au-dessus de la cible : la flèche ne dépend pas de l'orientation de la cible
local hudArrow: GuiObject
local hudArrowBase = UDim2.new() -- position de repos de la flèche d'interface, sans le balancement
local hudArrowBob = Vector2.yAxis -- sens du balancement (vers le bouton)
local chevrons: { { BasePart } } = {}
local current: Objectives.Objective? = nil
local targetPart: BasePart? = nil
local thrown = false
local levelsThisSession = 0
local lastPower = 0
local lastTargetPick = 0

-- Cette méthode permet de lire un attribut numérique du joueur (valeur par défaut si absent) lorsque l'état de
-- l'objectif est recalculé.
local function stat(name: string, default: number): number
	return (player:GetAttribute(name) :: number?) or default
end

-- Cette méthode permet de construire l'état du joueur (action, achats possibles, alternance lancer / entraînement)
-- lorsque l'objectif est recalculé.
local function state(): Objectives.State
	local money = stat("Money", 0)
	local gearCost = Training.nextGearCost(stat("GearTier", 1))
	local valueCost = Economy.valueCost(stat("ValueLevel", 1))
	return {
		action = player:GetAttribute("Action") :: string?,
		laneState = player:GetAttribute("LaneState") :: string?,
		thrown = thrown,
		levelsThisSession = levelsThisSession,
		canBuyGear = gearCost ~= nil and money >= gearCost,
		canBuyDummy = valueCost ~= nil and money >= valueCost,
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
				lane = instance:GetAttribute("Lane") :: number?,
				owner = instance:GetAttribute("OwnerUserId") :: number?,
			}
			table.insert(candidates, candidate)
			partOf[candidate] = instance
		end
	end
	local chosen = Objectives.chooseTarget(candidates, player:GetAttribute("Lane") :: number?, player.UserId, from)
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
-- les boutons des bords (elle masquerait le bouton voisin), au-dessus sinon (STOP), lorsque l'objectif change.
local function placeHudArrow(anchor: GuiObject?)
	if not anchor then
		return
	end
	local screen = Workspace.CurrentCamera.ViewportSize.X
	local x = anchor.AbsolutePosition.X + anchor.AbsoluteSize.X / 2
	if x < screen / 3 then
		hudArrow.AnchorPoint = Vector2.new(0, 0.5)
		hudArrow.Rotation = 90 -- pointe à gauche
		hudArrowBase = UDim2.new(1, 6, 0.5, 0)
		hudArrowBob = Vector2.xAxis
	elseif x > screen * 2 / 3 then
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
	local anchor = if current and current.button then Hud.anchor(current.button) else nil
	hudArrow.Parent = anchor
	hudArrow.Visible = anchor ~= nil
	placeHudArrow(anchor)
end

-- Cette méthode permet d'animer le texte, la flèche et les chevrons à chaque image lorsque l'objectif est affiché.
local function step()
	label.Visible = current ~= nil and not Hud.isPopupShown()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local kind = current and current.target
	if kind and root and os.clock() - lastTargetPick > TARGET_REFRESH then
		lastTargetPick = os.clock()
		targetPart = findTarget(kind, root.Position)
	end
	local target = if kind then targetPart else nil
	local bob = math.sin(os.clock() * 4) * 0.5
	worldArrow.Enabled = target ~= nil
	if target then
		arrowAnchor.CFrame = CFrame.new(target.Position + Vector3.new(0, ARROW_HEIGHT + bob, 0))
	end
	if hudArrow.Parent then
		placeHudArrow(hudArrow.Parent :: GuiObject) -- suit les changements de taille d'écran (rotation du mobile)
	end
	hudArrow.Position = hudArrowBase + UDim2.fromOffset(hudArrowBob.X * bob * 8, hudArrowBob.Y * bob * 8)
	if target and root and humanoid then
		local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - 0.12, 0)
		updateChevrons(feet, Vector3.new(target.Position.X, feet.Y, target.Position.Z))
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
		Position = UDim2.new(0.5, 0, 0, 36),
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
		Size = UDim2.fromScale(3, 3),
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
	for i = 1, CHEVRON_COUNT do
		chevrons[i] = makeChevron(folder)
	end

	lastPower = stat("ThrowPower", GameConfig.START_POWER)
	player:GetAttributeChangedSignal("ThrowPower"):Connect(function()
		local power = stat("ThrowPower", GameConfig.START_POWER)
		if power > lastPower then
			thrown = false
		end
		lastPower = power
		refresh()
	end)
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Flying" then
			thrown = true
		end
		refresh()
	end)
	player:GetAttributeChangedSignal("Action"):Connect(function()
		if player:GetAttribute("Action") == "Training" then
			levelsThisSession = 0
		end
		refresh()
	end)
	player:GetAttributeChangedSignal("TrainLevel"):Connect(function()
		levelsThisSession += 1
		refresh()
	end)
	for _, attribute in { "Money", "GearTier", "ValueLevel" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	RunService.RenderStepped:Connect(step)
	refresh()
end

return Objective
