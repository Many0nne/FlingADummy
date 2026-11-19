-- Caméra du lancer et du vol : gros plan sur l'avatar pendant le geste (côté du bras qui lance, léger
-- rapprochement), puis suit le torse du mannequin lancé (arrière, côté, haut), secousses proportionnelles aux chocs,
-- coup de champ de vision au départ ; rend la caméra normale quand le couloir redevient prêt.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local OFFSET = Vector3.new(16, 10, -26) -- côté (+X), haut, derrière (le vol part vers +Z)
local POSITION_SHARPNESS = 6 -- vitesse de rattrapage de la position (1/s)
local FOCUS_SHARPNESS = 12 -- vitesse de rattrapage du point visé (1/s)
local SHAKE_DECAY = 6 -- extinction des secousses (1/s)
local MAX_SHAKE = 2.5 -- amplitude maximale (studs)
local BASE_FOV = 70
local BIND_NAME = "FlightCamera"

-- Gros plan du lancer, dans le repère du personnage (X à droite, -Z devant) : départ, arrivée, point visé
local CLOSE_FROM = Vector3.new(5.6, 2.9, -3.2)
local CLOSE_TO = Vector3.new(4.5, 2.6, -2.5)
local CLOSE_FOCUS = Vector3.new(0.5, 2.6, 0)
local CLOSE_FOV = 50
local CLOSE_ROLL = math.rad(-5)

local FlightCamera = {}

local player: Player
local following = false
local shake = 0

-- Cette méthode permet de rendre la caméra normale (suivie du personnage) lorsque le vol et son résultat sont finis,
-- ou que le lancer n'a pas eu lieu.
function FlightCamera.stop()
	if not following then
		return
	end
	following = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = BASE_FOV
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Cette méthode permet de secouer la caméra (amplitude cumulée, plafonnée) lorsqu'un choc du vol du joueur arrive.
function FlightCamera.shake(amount: number)
	shake = math.min(shake + amount, MAX_SHAKE)
end

-- Cette méthode permet de donner un coup de champ de vision (élargi puis rendu) lorsque le mannequin part.
function FlightCamera.punch()
	local camera = Workspace.CurrentCamera
	camera.FieldOfView = BASE_FOV + 18
	TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = BASE_FOV,
	}):Play()
end

-- Cette méthode permet de cadrer l'avatar en gros plan pendant son geste de lancer (repère figé au départ, caméra
-- qui se rapproche en `duration` secondes, légère inclinaison) lorsque le joueur clique ; follow prend le relais.
function FlightCamera.closeUp(root: BasePart, duration: number)
	FlightCamera.stop()
	following = true
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CLOSE_FOV
	local base = root.CFrame
	local start = os.clock()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local k = math.clamp((os.clock() - start) / duration, 0, 1)
		local eased = 1 - (1 - k) ^ 3
		local position = base:PointToWorldSpace(CLOSE_FROM:Lerp(CLOSE_TO, eased))
		local focus = base:PointToWorldSpace(CLOSE_FOCUS)
		camera.CFrame = CFrame.lookAt(position, focus) * CFrame.Angles(0, 0, CLOSE_ROLL * eased)
	end)
end

-- Cette méthode permet de suivre un mannequin lancé lorsque le serveur annonce le lancer ; la caméra avance avec la
-- vitesse du torse et le lissage ne corrige que l'écart, d'où aucun retard même à grande vitesse.
function FlightCamera.follow(model: Model)
	local torso = model:WaitForChild("Torso", 2) :: BasePart?
	if not torso then
		return
	end
	FlightCamera.stop()
	following = true
	shake = 0
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local position = camera.CFrame.Position
	local focus = torso.Position
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not torso.Parent then
			FlightCamera.stop()
			return
		end
		local target = torso.Position
		position += torso.AssemblyLinearVelocity * dt
		position = position:Lerp(target + OFFSET, 1 - math.exp(-POSITION_SHARPNESS * dt))
		focus = focus:Lerp(target, 1 - math.exp(-FOCUS_SHARPNESS * dt))
		shake *= math.exp(-SHAKE_DECAY * dt)
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * shake
		camera.CFrame = CFrame.lookAt(position + jitter, focus + jitter * 0.5)
	end)
end

-- Cette méthode permet de brancher la caméra de vol sur l'état du couloir lorsque le client démarre.
function FlightCamera.init(localPlayer: Player)
	player = localPlayer
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Ready" then
			FlightCamera.stop()
		end
	end)
end

return FlightCamera
