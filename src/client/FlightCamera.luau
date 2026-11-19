-- Caméra de vol : suit le torse du mannequin lancé (arrière, côté, haut), puis rend la caméra normale quand le
-- couloir redevient prêt ou que le mannequin disparaît.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OFFSET = Vector3.new(16, 10, -26) -- côté (+X), haut, derrière (le vol part vers +Z)
local POSITION_SHARPNESS = 6 -- vitesse de rattrapage de la position (1/s)
local FOCUS_SHARPNESS = 12 -- vitesse de rattrapage du point visé (1/s)
local BIND_NAME = "FlightCamera"

local FlightCamera = {}

local player: Player
local following = false

-- Cette méthode permet de rendre la caméra normale (suivie du personnage) lorsque le vol et son résultat sont finis.
local function stop()
	if not following then
		return
	end
	following = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Cette méthode permet de suivre un mannequin lancé lorsque le serveur annonce le lancer ; la caméra avance avec la
-- vitesse du torse et le lissage ne corrige que l'écart, d'où aucun retard même à grande vitesse.
function FlightCamera.follow(model: Model)
	local torso = model:WaitForChild("Torso", 2) :: BasePart?
	if not torso then
		return
	end
	stop()
	following = true
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local position = camera.CFrame.Position
	local focus = torso.Position
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not torso.Parent then
			stop()
			return
		end
		local target = torso.Position
		position += torso.AssemblyLinearVelocity * dt
		position = position:Lerp(target + OFFSET, 1 - math.exp(-POSITION_SHARPNESS * dt))
		focus = focus:Lerp(target, 1 - math.exp(-FOCUS_SHARPNESS * dt))
		camera.CFrame = CFrame.lookAt(position, focus)
	end)
end

-- Cette méthode permet de brancher la caméra de vol sur l'état du couloir lorsque le client démarre.
function FlightCamera.init(localPlayer: Player)
	player = localPlayer
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Ready" then
			stop()
		end
	end)
end

return FlightCamera
