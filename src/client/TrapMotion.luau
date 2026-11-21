-- Animation des pièces mobiles des pièges (pales du ventilateur, rondin, presse, diable, vague…) : chaque client fait
-- bouger lui-même les modèles étiquetés Traps.MOTION_TAG par Server.TrapProps (mouvement : Shared.Traps.motion), et
-- seulement ceux proches de sa caméra. Rien ne se réplique à chaque image.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Traps = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Traps"))

local TrapMotion = {}

type Mover = {
	model: Model,
	home: CFrame,
	motion: string,
	axis: Vector3,
	amplitude: number,
	period: number,
	offset: number, -- décalage de phase : deux pièges voisins ne battent pas en même temps
}

local movers: { [Model]: Mover } = {}

-- Cette méthode permet de retenir un modèle mobile (repos, mouvement lu dans ses attributs) lorsqu'il arrive chez le
-- client.
local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local home = model:GetAttribute("Home")
	local axis = model:GetAttribute("Axis")
	if typeof(home) ~= "CFrame" or typeof(axis) ~= "Vector3" or axis.Magnitude < 1e-6 then
		return
	end
	movers[model] = {
		model = model,
		home = home,
		motion = tostring(model:GetAttribute("Motion")),
		axis = axis,
		amplitude = tonumber(model:GetAttribute("Amplitude")) or 0,
		period = math.max(tonumber(model:GetAttribute("Period")) or 1, 0.05),
		offset = Traps.phaseOffset(home.Position.X, home.Position.Z),
	}
end

-- Cette méthode permet d'avancer d'une image les pièces mobiles proches de la caméra lorsque le rendu tourne.
local function step()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = Workspace:GetServerTimeNow() -- horloge partagée : la presse écrase quand le serveur la fait écraser
	for model, mover in movers do
		if not model.Parent or not model.PrimaryPart then
			continue
		end
		if (mover.home.Position - eye).Magnitude > Traps.MOTION_RANGE then
			continue
		end
		local t = now + mover.offset * mover.period
		model:PivotTo(mover.home * Traps.motion(mover.motion, t, mover.axis, mover.amplitude, mover.period))
	end
end

-- Cette méthode permet de brancher l'animation des pièges lorsque le client démarre.
function TrapMotion.init()
	CollectionService:GetInstanceAddedSignal(Traps.MOTION_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Traps.MOTION_TAG):Connect(function(model)
		movers[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(Traps.MOTION_TAG) do
		track(model)
	end
	RunService.RenderStepped:Connect(step)
end

return TrapMotion
