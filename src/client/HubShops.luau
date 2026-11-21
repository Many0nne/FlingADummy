-- Stands du hub côté client (#68, décor construit par Server.Props) : invite du stand SHOP (ouvre la boutique des
-- mannequins à lancer), mannequins à lancer exposés sur les plateaux qui tournent, marchands qui se balancent et
-- saluent, pièce géante et tête d'enseigne qui tournent, éclat de pièces au-dessus du comptoir SELL à chaque vente,
-- confettis d'une base ou d'un appareil d'entraînement à chaque présentoir ou Training Gear acheté.
-- Tout est local à chaque client (rien n'est répliqué).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseLayout = require(Shared:WaitForChild("CourseLayout"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))

local UIKit = require(script.Parent.UIKit)

local DISPLAY_SPIN = 0.9 -- rad/s des mannequins exposés
local MODEL_SPIN = 1.2 -- rad/s de la pièce géante et de la tête de l'enseigne
local FEET = 3.82 -- du centre du torse au bas des pieds, à l'échelle 1 (Shared.DummyShape.PIECES)
local WAVE_PERIOD = 5 -- s entre deux saluts du marchand
local WAVE_TIME = 1.6 -- s de salut
local BURST_COINS = 30

type Display = { socket: BasePart, model: Model?, stage: number, phase: number }
type Spinner = { model: Model, base: CFrame }
type Merchant = { model: Model, base: CFrame, arm: BasePart?, shoulder: CFrame?, armHalf: number, phase: number }

local HubShops = {}

-- Appelée quand le joueur déclenche l'invite du stand SHOP (branchée par le HUD : ouvre la boutique)
HubShops.onShop = nil :: (() -> ())?

local displays: { [BasePart]: Display } = {}
local spinners: { [Model]: Spinner } = {}
local merchants: { [Model]: Merchant } = {}

-- Cette méthode permet de suivre un plateau de vitrine (mannequin à lancer exposé, construit au premier passage)
-- lorsqu'il apparaît.
local function addDisplay(socket: Instance)
	if socket:IsA("BasePart") and not displays[socket] then
		displays[socket] = { socket = socket, model = nil, stage = -1, phase = math.random() * math.pi * 2 }
	end
end

-- Cette méthode permet de (re)construire le mannequin exposé d'un plateau (à son échelle, pieds sur le plateau)
-- lorsque le plateau apparaît ou que les maillages arrivent.
local function buildDisplay(display: Display, stage: number)
	if display.model then
		display.model:Destroy()
	end
	display.stage = stage
	local index = display.socket:GetAttribute("Index")
	local scale = display.socket:GetAttribute("Scale")
	if typeof(index) ~= "number" or typeof(scale) ~= "number" then
		display.model = nil
		return
	end
	local model = DummyShape.buildVisual(scale, ThrowDummies.variant(index) :: DummyShape.Variant)
	local primary = model.PrimaryPart :: BasePart
	primary.Anchored = true
	model.Name = "ShopDummy" .. index
	model.Parent = display.socket
	display.model = model
end

-- Cette méthode permet de suivre un modèle qui tourne sur lui-même (repère de départ retenu) lorsqu'il apparaît.
local function addSpinner(model: Instance)
	if model:IsA("Model") and model.PrimaryPart and not spinners[model] then
		spinners[model] = { model = model, base = model:GetPivot() }
	end
end

-- Cette méthode permet de suivre un marchand (repère, bras qui salue et son épaule) lorsqu'il apparaît.
local function addMerchant(model: Instance)
	if not model:IsA("Model") or not model.PrimaryPart or merchants[model] then
		return
	end
	local base = model:GetPivot()
	local arm = model:FindFirstChild("WaveArm") :: BasePart?
	local entry: Merchant = { model = model, base = base, armHalf = 0, phase = math.random() * WAVE_PERIOD }
	if arm then
		entry.arm = arm
		entry.armHalf = arm.Size.Y / 2
		-- Épaule : haut du bras, dans le repère du marchand
		entry.shoulder = base:ToObjectSpace(arm.CFrame * CFrame.new(0, entry.armHalf, 0))
	end
	merchants[model] = entry
end

-- Cette méthode permet de faire jaillir des pièces au-dessus du comptoir SELL lorsque le serveur compte une vente.
local function bindBurst(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part:GetAttributeChangedSignal("Sales"):Connect(function()
		local emitter = part:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			emitter:Emit(BURST_COINS)
		end
	end)
end

-- Cette méthode permet de faire jaillir les confettis d'une base ou d'un appareil (quart du nombre en mouvement réduit)
-- lorsque le serveur compte un présentoir ou un Training Gear acheté (attribut Upgrades).
local function bindUpgrade(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part:GetAttributeChangedSignal("Upgrades"):Connect(function()
		local share = if UIKit.reducedMotion() then 0.25 else 1
		for _, emitter in part:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(math.ceil(((emitter:GetAttribute("Count") :: number?) or 30) * share))
			end
		end
	end)
end

-- Cette méthode permet d'ouvrir la boutique lorsque le joueur déclenche l'invite du stand SHOP.
local function bindShopPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function()
			if HubShops.onShop then
				HubShops.onShop()
			end
		end)
	end
end

-- Cette méthode permet d'avancer les animations des stands d'une frame (plateaux, pièce géante, marchands) lorsque
-- RenderStepped tourne ; les éléments retirés du monde sont oubliés.
local function step()
	local now = os.clock()
	local still = UIKit.reducedMotion()
	local stage = DummyShape.meshStage()
	for socket, display in displays do
		if not socket.Parent then
			displays[socket] = nil
			continue
		end
		if display.stage ~= stage then
			buildDisplay(display, stage)
		end
		local model = display.model
		if model then
			local scale = (socket:GetAttribute("Scale") :: number?) or 1
			local angle = if still then 0 else display.phase + now * DISPLAY_SPIN
			model:PivotTo(CFrame.new(socket.Position + Vector3.new(0, FEET * scale, 0)) * CFrame.Angles(0, angle, 0))
		end
	end
	for model, spinner in spinners do
		if not model.Parent then
			spinners[model] = nil
		elseif not still then
			local center = spinner.base.Position
			local turn = CFrame.Angles(0, now * MODEL_SPIN, 0)
			model:PivotTo(CFrame.new(center) * turn * CFrame.new(-center) * spinner.base)
		end
	end
	for model, merchant in merchants do
		if not model.Parent then
			merchants[model] = nil
			continue
		end
		if still then
			-- Mouvement réduit : marchand remis au repos (pas figé bras levé)
			model:PivotTo(merchant.base)
			if merchant.arm and merchant.shoulder then
				merchant.arm.CFrame = merchant.base * merchant.shoulder * CFrame.new(0, -merchant.armHalf, 0)
			end
			continue
		end
		local bob = math.abs(math.sin(now * 2 + merchant.phase)) * 0.15
		local pivot = merchant.base * CFrame.new(0, bob, 0)
		model:PivotTo(pivot)
		if merchant.arm and merchant.shoulder then
			-- Salut : bras levé sur le côté qui s'agite, puis redescend
			local t = (now + merchant.phase) % WAVE_PERIOD
			local raise = if t < WAVE_TIME then math.sin(math.pi * t / WAVE_TIME) else 0
			local angle = raise * (math.rad(150) + math.rad(18) * math.sin(now * 14))
			merchant.arm.CFrame = pivot
				* merchant.shoulder
				* CFrame.Angles(0, 0, angle)
				* CFrame.new(0, -merchant.armHalf, 0)
		end
	end
end

-- Cette méthode permet de brancher les éléments étiquetés des stands (déjà là ou à venir) et la boucle d'animation
-- lorsque le client démarre.
function HubShops.init()
	local bindings = {
		[ThrowDummies.DISPLAY_TAG] = addDisplay,
		[CourseLayout.SPIN_TAG] = addSpinner,
		[CourseLayout.MERCHANT_TAG] = addMerchant,
		[CourseLayout.SELL_BURST_TAG] = bindBurst,
		[CourseLayout.UPGRADE_BURST_TAG] = bindUpgrade,
		[ThrowDummies.SHOP_TAG] = bindShopPrompt,
	}
	for tag, bind in bindings do
		for _, instance in CollectionService:GetTagged(tag) do
			bind(instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	end
	RunService.RenderStepped:Connect(step)
end

return HubShops
