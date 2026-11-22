-- Caméra du lancer et du vol : gros plan sur l'avatar pendant le geste (côté du bras qui lance, léger
-- rapprochement), puis suit le torse du mannequin lancé (arrière, côté, haut ; plongée qui suit l'altitude :
-- Shared.FlightFraming), secousses proportionnelles aux chocs,
-- coup de champ de vision au départ ; rend la caméra normale quand le couloir redevient prêt.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FlightFraming = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FlightFraming"))

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
local SHOWCASE_PUSH = 6 -- durée du lent rapprochement sur le mannequin gagné (s)

local FlightCamera = {}

local player: Player
local following = false
local shake = 0
local flightFocus: Vector3? = nil -- point visé par la caméra de vol à la dernière image (repris par un nouveau suivi)

-- Cette méthode permet de rendre la caméra normale (suivie du personnage) lorsque le vol et son résultat sont finis,
-- ou que le lancer n'a pas eu lieu.
function FlightCamera.stop()
	if not following then
		return
	end
	following = false
	flightFocus = nil
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
		if not root.Parent then
			FlightCamera.stop() -- personnage mort ou réapparu pendant le geste
			return
		end
		local k = math.clamp((os.clock() - start) / duration, 0, 1)
		local eased = 1 - (1 - k) ^ 3
		local position = base:PointToWorldSpace(CLOSE_FROM:Lerp(CLOSE_TO, eased))
		local focus = base:PointToWorldSpace(CLOSE_FOCUS)
		camera.CFrame = CFrame.lookAt(position, focus) * CFrame.Angles(0, 0, CLOSE_ROLL * eased)
	end)
end

-- Cette méthode permet de suivre un mannequin lancé (Shared.FlightFraming, lissage de l'écart seul) lorsque le serveur
-- annonce le lancer, ou dès le lâcher (décoratif qui part, #144) ; `shown` : torse à l'écran s'il n'est pas la copie
-- répliquée (Client.LaunchGhost : position, vitesse affichée, vitesse réelle). Un suivi qui en remplace un autre garde
-- son point visé : pas de saut au passage du décoratif au mannequin du serveur.
function FlightCamera.follow(model: Model, shown: (() -> (Vector3?, Vector3?, number?))?)
	local torso = model:WaitForChild("Torso", 2) :: BasePart?
	if not torso then
		return
	end
	local kept = flightFocus
	FlightCamera.stop()
	following = true
	shake = 0
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	-- La vitesse prolongée doit être celle de ce qui est affiché : la copie répliquée, figée au départ à vitesse pleine,
	-- se faisait dépasser par la caméra (#117)
	-- Cette méthode permet de donner la position, la vitesse et la vitesse réelle du torse à l'écran lorsque la caméra
	-- se place.
	local function displayed(): (Vector3, Vector3, number)
		local position, velocity, speed
		if shown then
			position, velocity, speed = shown()
		end
		local part = torso :: BasePart
		return position or part.Position,
			velocity or part.AssemblyLinearVelocity,
			speed or part.AssemblyLinearVelocity.Magnitude
	end
	local position = camera.CFrame.Position
	local focus = kept or displayed()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not torso.Parent then
			FlightCamera.stop()
			return
		end
		local target, velocity, speed = displayed()
		position += velocity * dt
		-- Distance du cadrage selon la vitesse réelle (répliquée, ou du plan avant elle) : pas de va-et-vient quand
		-- l'affichage ralentit au départ
		local offset = FlightFraming.offset(target.Y, speed) -- piste à y = 0
		position = position:Lerp(target + offset, 1 - math.exp(-POSITION_SHARPNESS * dt))
		-- Le point visé avance lui aussi avec le torse : sinon, en montée rapide, il traîne en dessous et le mannequin
		-- sort par le haut de l'image (#88)
		focus += velocity * dt
		focus = focus:Lerp(target, 1 - math.exp(-FOCUS_SHARPNESS * dt))
		shake *= math.exp(-SHAKE_DECAY * dt)
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * shake
		camera.CFrame = CFrame.lookAt(position + jitter, focus + jitter * 0.5)
		flightFocus = focus
	end)
end

-- Cette méthode permet de cadrer le mannequin gagné (debout au point d'atterrissage, `height` studs de haut) depuis
-- l'arrière de la piste, en se rapprochant doucement, lorsque le tirage se joue ; les secousses (shake) marquent
-- chaque palier du suspense ; stop rend la caméra.
function FlightCamera.showcase(focus: Vector3, height: number)
	FlightCamera.stop()
	following = true
	shake = 0
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = BASE_FOV
	local distance = math.max(height, 5) * 2.2 + 4
	local from = camera.CFrame.Position
	local start = os.clock()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local t = os.clock() - start
		local blend = 1 - math.exp(-6 * t) -- arrive vite depuis la caméra de vol
		local push = distance * (1 - 0.12 * math.min(t / SHOWCASE_PUSH, 1)) -- puis se rapproche lentement
		local target = focus + Vector3.new(push * 0.25, height * 0.35 + 1.5, -push)
		shake *= math.exp(-SHAKE_DECAY * dt)
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * shake
		camera.CFrame = CFrame.lookAt(from:Lerp(target, blend) + jitter, focus + jitter * 0.3)
	end)
end

-- Cette méthode permet de faire glisser la caméra de `from` à `to` en `duration` s (départ et arrivée en douceur,
-- secousses comprises) lorsque la séquence du secret longe le tapis rouge de son décor ; stop ou showcase reprennent.
function FlightCamera.dolly(from: CFrame, to: CFrame, duration: number)
	FlightCamera.stop()
	following = true
	shake = 0
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = BASE_FOV
	local start = os.clock()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local k = math.clamp((os.clock() - start) / math.max(duration, 0.01), 0, 1)
		local eased = k * k * (3 - 2 * k)
		shake *= math.exp(-SHAKE_DECAY * dt)
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * shake
		camera.CFrame = from:Lerp(to, eased) + jitter
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
