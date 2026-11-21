-- Animation des pièces ajoutées des mannequins de collection (#66) : anneaux, halos, orbites et flammes étiquetés
-- Shared.DummyShape.FX_TAG tournent ou flottent en boucle, partout où le mannequin est montré (présentoirs des
-- bases, tirage, en main, fenêtres Index / Inventaire). Seul le client anime : rien n'est répliqué.
--
-- Dans le monde, une pièce soudée à un mannequin non ancré bouge par le C0 de sa soudure ; sur un présentoir ancré
-- ou dans un ViewportFrame (pas de physique), la soudure est coupée et la pièce placée directement.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DummyShape = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DummyShape"))

local DummyFx = {}

local MAX_DISTANCE = 220 -- au-delà, une pièce du monde reste figée (studs)

local animated: { [BasePart]: true } = {}

-- Cette méthode permet de placer une pièce animée à l'instant `t` lorsque la boucle d'animation passe sur elle.
local function step(part: BasePart, t: number, eye: Vector3)
	local weld = part:FindFirstChild(DummyShape.FX_WELD)
	local base = part:GetAttribute("FxBase")
	if not weld or not weld:IsA("Weld") or typeof(base) ~= "CFrame" then
		return
	end
	local carrier = weld.Part0
	if not carrier then
		return
	end
	local inWorld = part:IsDescendantOf(Workspace)
	if inWorld and (carrier.Position - eye).Magnitude > MAX_DISTANCE then
		return
	end
	local model = part.Parent
	local scale = if model and model:IsA("Model") then model:GetScale() else 1
	local spin = part:GetAttribute("FxSpin")
	local bob = part:GetAttribute("FxBob")
	local offset = DummyShape.fxOffset(
		base,
		scale,
		t,
		if typeof(spin) == "Vector3" then spin else nil,
		if typeof(bob) == "Vector2" then bob else nil
	)
	if inWorld and not part.Anchored then
		weld.Enabled = true
		weld.C0 = offset
	else
		weld.Enabled = false -- sinon déplacer la pièce entraînerait tout le mannequin
		part.CFrame = carrier.CFrame * offset
	end
end

-- Cette méthode permet de démarrer l'animation des pièces étiquetées lorsque le client s'amorce.
function DummyFx.init()
	for _, instance in CollectionService:GetTagged(DummyShape.FX_TAG) do
		if instance:IsA("BasePart") then
			animated[instance] = true
		end
	end
	CollectionService:GetInstanceAddedSignal(DummyShape.FX_TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			animated[instance] = true
		end
	end)
	CollectionService:GetInstanceRemovedSignal(DummyShape.FX_TAG):Connect(function(instance)
		animated[instance :: BasePart] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		for part in animated do
			step(part, t, eye)
		end
	end)
end

return DummyFx
