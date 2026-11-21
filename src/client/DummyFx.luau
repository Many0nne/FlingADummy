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

-- Données d'animation d'une pièce, lues une fois (soudure, repos, rotation, flottement) ; true : pas encore lues
type Record = { weld: Weld, carrier: BasePart, base: CFrame, spin: Vector3?, bob: Vector2? }
local animated: { [BasePart]: Record | true } = {}

-- Cette méthode permet de lire une fois les données d'animation d'une pièce étiquetée lorsque la boucle la rencontre ;
-- true (réessayer plus tard) tant que sa soudure, sa pièce porteuse ou son repos ne sont pas arrivés (réplication).
local function record(part: BasePart): Record | true
	local weld = part:FindFirstChild(DummyShape.FX_WELD)
	local base = part:GetAttribute("FxBase")
	if not weld or not weld:IsA("Weld") or typeof(base) ~= "CFrame" or not weld.Part0 then
		return true
	end
	local spin = part:GetAttribute("FxSpin")
	local bob = part:GetAttribute("FxBob")
	return {
		weld = weld,
		carrier = weld.Part0 :: BasePart,
		base = base,
		spin = if typeof(spin) == "Vector3" then spin else nil,
		bob = if typeof(bob) == "Vector2" then bob else nil,
	}
end

-- Cette méthode permet de placer une pièce animée à l'instant `t` lorsque la boucle d'animation passe sur elle (une
-- pièce du monde trop loin de la caméra reste figée).
local function step(part: BasePart, t: number, eye: Vector3)
	local data = animated[part]
	if data == true then
		data = record(part)
		animated[part] = data
	end
	if data == true or not data then
		return
	end
	local weld, carrier = data.weld, data.carrier
	if (carrier.Position - eye).Magnitude > MAX_DISTANCE and part:IsDescendantOf(Workspace) then
		return
	end
	local inWorld = part:IsDescendantOf(Workspace)
	local model = part.Parent
	local scale = if model and model:IsA("Model") then model:GetScale() else 1
	local offset = DummyShape.fxOffset(data.base, scale, t, data.spin, data.bob)
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
