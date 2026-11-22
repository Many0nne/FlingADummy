-- Caméra du lancer et du vol : resserrée derrière l'épaule tant que le joueur tient le mannequin sur la bande (#158),
-- gros plan sur l'avatar pendant le geste (côté du bras qui lance, léger rapprochement ; cadrages et fondus :
-- Shared.ThrowFraming), puis suit le torse du mannequin lancé (arrière, côté, haut ; plongée qui suit l'altitude :
-- Shared.FlightFraming), secousses proportionnelles aux chocs,
-- coup de champ de vision au départ ; rend la caméra normale quand le couloir redevient prêt.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FlightFraming = require(Shared:WaitForChild("FlightFraming"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ThrowFraming = require(Shared:WaitForChild("ThrowFraming"))

local UIKit = require(script.Parent.UIKit)

local POSITION_SHARPNESS = 6 -- vitesse de rattrapage de la position (1/s)
local FOCUS_SHARPNESS = 12 -- vitesse de rattrapage du point visé (1/s)
local SHAKE_DECAY = 6 -- extinction des secousses (1/s)
local MAX_SHAKE = 2.5 -- amplitude maximale (studs)
local BASE_FOV = 70
local BIND_NAME = "FlightCamera"
local SHOWCASE_PUSH = 6 -- durée du lent rapprochement sur le mannequin gagné (s)

local FlightCamera = {}

local player: Player
local following = false
local banded = false -- cadrage de la bande en cours (FlightCamera.band), jusqu'au geste ou à la sortie de bande
local shake = 0
local punchTween: Tween? = nil -- coup de champ de vision en cours (coupé par un retour sur la bande)
local flightFocus: Vector3? = nil -- point visé par la caméra de vol à la dernière image (repris par un nouveau suivi)

-- Cette méthode permet de donner la durée d'un fondu de la caméra (nulle en mouvement réduit : coupe directe) lorsqu'un
-- cadrage de la bande ou du geste commence.
local function fadeTime(duration: number): number
	return if UIKit.reducedMotion() then 0 else duration
end

-- Cette méthode permet de rendre la caméra normale (suivie du personnage) lorsque le vol et son résultat sont finis,
-- ou que le lancer n'a pas eu lieu.
function FlightCamera.stop()
	if not following then
		return
	end
	following = false
	banded = false
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
	local tween = TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = BASE_FOV,
	})
	tween:Play()
	punchTween = tween
end

-- Cette méthode permet de savoir si `root` appartient encore au personnage affiché lorsqu'un cadrage de l'avatar
-- se met à jour (faux après sa mort, sa réapparition ou sa destruction).
local function standing(root: BasePart, humanoid: Humanoid?): boolean
	return root:IsDescendantOf(Workspace) and (humanoid == nil or humanoid.Health > 0)
end

-- Cette méthode permet de donner l'inclinaison (radians, autour du regard) d'un cadrage lorsqu'un fondu en part et
-- doit la rendre peu à peu (gros plan du geste incliné, lancer refusé).
local function rollOf(view: CFrame): number
	local level = CFrame.lookAt(view.Position, view.Position + view.LookVector)
	local _, _, roll = level:ToObjectSpace(view):ToEulerAnglesXYZ()
	return roll
end

-- Cette méthode permet de resserrer la caméra derrière l'épaule, regard vers le bout de la piste, en BAND_CAM_IN
-- secondes depuis le cadrage courant lorsque le joueur se fige sur la bande ; à rappeler pour remettre en prise.
function FlightCamera.band(root: BasePart)
	local camera = Workspace.CurrentCamera
	local fromView, fromFov = camera.CFrame, camera.FieldOfView
	local fromFocus = ThrowFraming.focusOf(fromView, root.Position)
	local fromRoll = rollOf(fromView)
	if punchTween then
		punchTween:Cancel() -- lâcher anticipé puis refusé : le fondu reprend le champ de vision où il en est
		punchTween = nil
	end
	FlightCamera.stop()
	following = true
	banded = true
	camera.CameraType = Enum.CameraType.Scriptable
	local duration = fadeTime(GameConfig.BAND_CAM_IN)
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	local start = os.clock()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		if not standing(root, humanoid) then
			FlightCamera.leaveBand() -- personnage mort (la caméra libre suit sa chute) ou réapparu
			return
		end
		local k = ThrowFraming.progress(os.clock() - start, duration)
		local toPosition, toFocus = ThrowFraming.band(root.CFrame)
		local position, focus = ThrowFraming.blend(fromView.Position, fromFocus, toPosition, toFocus, root.Position, k)
		camera.CFrame = CFrame.lookAt(position, focus) * CFrame.Angles(0, 0, fromRoll * (1 - k))
		camera.FieldOfView = fromFov + (GameConfig.BAND_CAM_FOV - fromFov) * k
	end)
end

-- Cette méthode permet de rendre la caméra libre en BAND_CAM_OUT secondes (fondu vers ce qu'elle calcule à chaque
-- image) lorsque le joueur quitte la bande sans lancer ; sans effet hors du cadrage de la bande.
function FlightCamera.leaveBand()
	if not banded then
		return
	end
	local camera = Workspace.CurrentCamera
	local fromView, fromFov = camera.CFrame, camera.FieldOfView
	FlightCamera.stop()
	local duration = fadeTime(GameConfig.BAND_CAM_OUT)
	if duration <= 0 then
		return
	end
	-- Après la caméra libre (Camera), qui part du regard de la bande : le fondu mêle son calcul de l'image au cadrage
	-- quitté ; stop l'interrompt
	following = true
	camera.FieldOfView = fromFov
	local start = os.clock()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local k = ThrowFraming.progress(os.clock() - start, duration)
		camera.CFrame = fromView:Lerp(camera.CFrame, k)
		camera.FieldOfView = fromFov + (BASE_FOV - fromFov) * k
		if k >= 1 then
			FlightCamera.stop()
		end
	end)
end

-- Cette méthode permet de cadrer l'avatar en gros plan pendant son geste de lancer (repère figé au départ, caméra
-- qui se rapproche en `duration` secondes, légère inclinaison) lorsque le joueur clique ; part du cadrage courant (la
-- bande) en THROW_CAM_BLEND secondes, sans saut ; follow prend le relais.
function FlightCamera.closeUp(root: BasePart, duration: number)
	local camera = Workspace.CurrentCamera
	local fromView, fromFov = camera.CFrame, camera.FieldOfView
	local fromFocus = ThrowFraming.focusOf(fromView, root.Position)
	FlightCamera.stop()
	following = true
	camera.CameraType = Enum.CameraType.Scriptable
	local blend = fadeTime(GameConfig.THROW_CAM_BLEND)
	local base = root.CFrame
	local start = os.clock()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		if not root:IsDescendantOf(Workspace) then
			FlightCamera.stop() -- personnage réapparu pendant le geste
			return
		end
		local elapsed = os.clock() - start
		local k = math.clamp(elapsed / duration, 0, 1)
		local toPosition, toFocus, roll = ThrowFraming.closeUp(base, 1 - (1 - k) ^ 3)
		local w = ThrowFraming.progress(elapsed, blend)
		local position, focus = ThrowFraming.blend(fromView.Position, fromFocus, toPosition, toFocus, base.Position, w)
		camera.CFrame = CFrame.lookAt(position, focus) * CFrame.Angles(0, 0, roll * w)
		camera.FieldOfView = fromFov + (ThrowFraming.CLOSE_FOV - fromFov) * w
	end)
end

-- Cette méthode permet de suivre un mannequin lancé (Shared.FlightFraming, `shown` : torse affiché par Client.LaunchGhost)
-- lorsque le lancer part ; un suivi qui en remplace un autre garde son point visé (passage du décoratif au serveur, #144).
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
