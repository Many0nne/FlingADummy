-- Animation des pièces ajoutées des mannequins de collection (#66) : anneaux, halos, orbites et flammes étiquetés
-- Shared.DummyShape.FX_TAG tournent ou flottent en boucle, partout où le mannequin est montré (présentoirs des
-- bases, tirage, en main, fenêtres Index / Inventaire). Seul le client anime : rien n'est répliqué.
-- Mouvement réduit (#146, réglage Roblox) : chaque pièce est posée une fois à son repos, sans animation ; elle reprend
-- quand le réglage est retiré.
--
-- Dans le monde, une pièce soudée à un mannequin non ancré bouge par le C0 de sa soudure ; sur un présentoir ancré
-- ou dans un ViewportFrame (pas de physique), la soudure est coupée et la pièce placée directement.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DummyShape = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DummyShape"))

local UIKit = require(script.Parent.UIKit)

local DummyFx = {}

local MAX_DISTANCE = 220 -- au-delà, une pièce du monde reste figée (studs)

-- Données d'animation d'une pièce, lues une fois (soudure, repos, rotation, flottement) ; true : pas encore lues
type Record = { weld: Weld, carrier: BasePart, base: CFrame, spin: Vector3?, bob: Vector2? }
local animated: { [BasePart]: Record | true } = {}
local resting: { [BasePart]: true } = {} -- pièces encore à poser à leur repos (mouvement réduit)
local still = false -- mouvement réduit en cours

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

-- Cette méthode permet de donner les données d'animation d'une pièce (lues à la première demande) lorsque la boucle
-- l'anime ou la pose au repos ; nil tant qu'elles ne sont pas arrivées.
local function dataOf(part: BasePart): Record?
	local data = animated[part]
	if data == true then
		data = record(part)
		animated[part] = data
	end
	if data == true or not data then
		return nil
	end
	return data
end

-- Cette méthode permet de placer une pièce animée à l'instant `t` (au repos si `rest` : ni rotation ni flottement)
-- lorsque la boucle passe sur elle.
local function place(part: BasePart, data: Record, t: number, rest: boolean)
	local weld, carrier = data.weld, data.carrier
	local inWorld = part:IsDescendantOf(Workspace)
	local model = part.Parent
	local scale = if model and model:IsA("Model") then model:GetScale() else 1
	local offset = if rest
		then DummyShape.fxOffset(data.base, scale, 0)
		else DummyShape.fxOffset(data.base, scale, t, data.spin, data.bob)
	if inWorld and not part.Anchored then
		weld.Enabled = true
		weld.C0 = offset
	else
		weld.Enabled = false -- sinon déplacer la pièce entraînerait tout le mannequin
		part.CFrame = carrier.CFrame * offset
		if rest then
			-- Au repos, soudure rendue comme à la construction (pièce déjà à sa place) : la pièce suit son porteur
			-- s'il est déplacé ou désancré plus tard, sans autre passage
			weld.C0 = offset
			weld.Enabled = true
		end
	end
end

-- Cette méthode permet d'animer une pièce à l'instant `t` lorsque la boucle d'animation passe sur elle (une pièce du
-- monde trop loin de la caméra reste figée).
local function step(part: BasePart, t: number, eye: Vector3)
	local data = dataOf(part)
	if not data then
		return
	end
	if (data.carrier.Position - eye).Magnitude > MAX_DISTANCE and part:IsDescendantOf(Workspace) then
		return
	end
	place(part, data, t, false)
end

-- Cette méthode permet de noter une pièce étiquetée lorsque elle apparaît (à poser au repos en mouvement réduit).
local function track(part: BasePart)
	animated[part] = true
	if still then
		resting[part] = true
	end
end

-- Cette méthode permet de démarrer l'animation des pièces étiquetées lorsque le client s'amorce.
function DummyFx.init()
	for _, instance in CollectionService:GetTagged(DummyShape.FX_TAG) do
		if instance:IsA("BasePart") then
			track(instance)
		end
	end
	CollectionService:GetInstanceAddedSignal(DummyShape.FX_TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			track(instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(DummyShape.FX_TAG):Connect(function(instance)
		animated[instance :: BasePart] = nil
		resting[instance :: BasePart] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local reduced = UIKit.reducedMotion()
		if reduced ~= still then
			still = reduced
			table.clear(resting)
			if still then
				-- Réglage activé en cours de partie : toutes les pièces reviennent à leur repos, une fois
				for part in animated do
					resting[part] = true
				end
			end
		end
		if still then
			-- Un seul passage par pièce : posée dès que ses données sont là, puis plus touchée
			for part in resting do
				local data = dataOf(part)
				if data then
					place(part, data, 0, true)
					resting[part] = nil
				end
			end
			return
		end
		local t = os.clock()
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		for part in animated do
			step(part, t, eye)
		end
	end)
end

return DummyFx
