-- Effets des comportements en vol (#138), vus par tous les joueurs : flamme, fumée et son de réacteur du Rocket pendant
-- sa poussée, traînées d'air au bout des bras du Glider pendant sa descente planée (souffle au début), « boing »,
-- anneau de poussière et étoiles à chaque rebond réglé du Rubber. Quand les allumer : Shared.FlightFx, d'après le plan
-- du vol (attributs `LaunchOrigin`, `LaunchVelocity`, `ThrownIndex` posés par Server.LaunchService) et le compteur
-- `Bounces` du serveur, sur la position affichée du torse.
--
-- Les effets sont portés par des pièces du client (hors du mannequin) qui suivent à chaque image les pièces affichées :
-- la copie locale du lanceur (Client.LaunchGhost, décalage sur la copie répliquée) puis la copie répliquée, sans
-- double effet ni reprise au retour de la main. Chez le lanceur, le vol commence dès le lâcher sur le décoratif qui part
-- (plan prévu par le client, #144) et passe, sans se rallumer, au mannequin du serveur quand sa copie locale prend le
-- relais (repères du plan recalculés sur son départ). Mouvement réduit : moins de particules, pas d'anneau qui s'étend.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local FlightFxRules = require(Shared:WaitForChild("FlightFx"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))

local LaunchGhost = require(script.Parent.LaunchGhost)
local UIKit = require(script.Parent.UIKit)

local BIND_NAME = "FlightFx"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FLAME_BACK = 1.6 -- la flamme part de ce recul derrière le torse (studs)
local FADE = 0.2 -- extinction de la flamme et du son du réacteur (s)
local LINGER = 1 -- pièces d'effets gardées après la fin du suivi : particules et traînées finissent leur vie (s)
local DUST_RAYS = 12 -- particules de l'anneau de poussière d'un rebond (mouvement normal)
local STARS = 8 -- étoiles d'un rebond (mouvement normal)
local ARMS = { "LeftLowerArm", "RightLowerArm" }

type Arm = { source: BasePart, rig: BasePart, trail: Trail }
type Flight = {
	model: Model,
	torso: BasePart,
	tracker: FlightFxRules.Tracker,
	profile: FlightFxRules.Profile,
	root: Folder, -- pièces d'effets du vol
	jet: BasePart?, -- porte la flamme et la fumée, derrière le torse
	flame: ParticleEmitter?,
	smoke: ParticleEmitter?,
	light: PointLight?,
	roar: Sound?,
	arms: { Arm },
	previous: Vector3?, -- position affichée du torse à l'image précédente
	heading: Vector3, -- direction affichée du mouvement (lissée)
	boosting: boolean,
	gliding: boolean,
}

local FlightFx = {}

local folder: Folder
local burstPart: BasePart
local burstAnchor: Attachment
local rings: { [number]: ParticleEmitter } = {} -- anneau de poussière par rang de rebond (taille propre à chacun)
local dust: ParticleEmitter
local stars: ParticleEmitter
local rayParams = RaycastParams.new()
local flights: { [Model]: Flight } = {}

-- Cette méthode permet de créer une pièce d'effet du client (ancrée, invisible, sans collision) lorsque un vol démarre.
local function rigPart(name: string, parent: Instance): BasePart
	return UIKit.create("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one * 0.4,
		Parent = parent,
	})
end

-- Cette méthode permet de jouer un son de la table Shared.Sounds porté par `parent` (volume multiplié par `level`)
-- lorsque un effet de vol démarre ; le son est détruit à sa fin.
local function sound(name: string, parent: Instance, level: number, pitch: number?): Sound?
	local definition = Sounds[name]
	if not definition then
		return nil
	end
	local s = UIKit.create("Sound", {
		SoundId = definition.id,
		Volume = definition.volume * level,
		PlaybackSpeed = pitch or 1,
		RollOffMinDistance = 40,
		RollOffMaxDistance = 600,
		Parent = parent,
	})
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	Debris:AddItem(s, 8)
	return s
end

-- Cette méthode permet de jouer un son ponctuel à une position du monde lorsque la glisse commence ou qu'un rebond
-- tombe.
local function soundAt(name: string, position: Vector3, level: number, pitch: number?)
	local holder = Instance.new("Attachment")
	holder.Parent = Workspace.Terrain
	holder.WorldPosition = position
	sound(name, holder, level, pitch)
	Debris:AddItem(holder, 6)
end

-- Cette méthode permet de poser la flamme, la fumée, la lueur et le son du réacteur lorsque un Rocket part.
local function addJet(flight: Flight)
	local jet = rigPart("Jet", flight.root)
	local rate = flight.profile.rate
	-- Flamme collée au mannequin (LockedToPart) : un jet court qui le suit, pas une traînée sur la piste
	flight.flame = UIKit.create("ParticleEmitter", {
		Texture = FIRE,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 150)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 170, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 20)),
		}),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.2), NumberSequenceKeypoint.new(1, 0.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) }),
		Lifetime = NumberRange.new(0.14, 0.2),
		Speed = NumberRange.new(22, 30),
		SpreadAngle = Vector2.new(12, 12),
		Rate = 110 * rate,
		LockedToPart = true,
		EmissionDirection = Enum.NormalId.Front,
		ZOffset = 1,
		Parent = jet,
	})
	-- Fumée grise courte derrière la flamme, elle aussi collée : quelques studs, pas de nuage sur les obstacles
	flight.smoke = UIKit.create("ParticleEmitter", {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(150, 150, 158)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(26, 38),
		SpreadAngle = Vector2.new(18, 18),
		Rate = 40 * rate,
		LockedToPart = true,
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Front,
		Parent = jet,
	})
	flight.light = UIKit.create("PointLight", {
		Color = Color3.fromRGB(255, 160, 60),
		Brightness = 3,
		Range = 16,
		Parent = jet,
	})
	local roar = sound("Rocket", jet, 0.9)
	if roar then
		roar.Looped = true -- toute la poussée, quelle que soit la longueur du clip ; stopJet l'éteint
	end
	flight.roar = roar
	flight.jet = jet
end

-- Cette méthode permet d'éteindre le réacteur en FADE s (plus de particules, lueur et son qui baissent) lorsque la
-- poussée affichée finit.
local function stopJet(flight: Flight)
	if flight.flame then
		flight.flame.Enabled = false
	end
	if flight.smoke then
		flight.smoke.Enabled = false
	end
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if flight.light then
		TweenService:Create(flight.light, info, { Brightness = 0 }):Play()
	end
	local roar = flight.roar
	if roar and roar.Parent then
		TweenService:Create(roar, info, { Volume = 0 }):Play()
		task.delay(FADE, function()
			if roar.Parent then
				roar:Destroy()
			end
		end)
	end
end

-- Cette méthode permet de poser les traînées d'air blanches au bout des bras (éteintes jusqu'à la descente planée)
-- lorsque un Glider part, puis à chaque image tant qu'un bras manque (réplication en plusieurs paquets).
local function addTrails(flight: Flight)
	for _, name in ARMS do
		local source = flight.model:FindFirstChild(name)
		if not source or not source:IsA("BasePart") or flight.root:FindFirstChild("Trail" .. name) then
			continue
		end
		local rig = rigPart("Trail" .. name, flight.root)
		-- Bout de la main (le bras pend selon -Y de sa pièce) et un point un peu plus haut : largeur de la traînée
		local tip = -source.Size.Y / 2
		local a0 = UIKit.create("Attachment", { Position = Vector3.new(0, tip, 0), Parent = rig })
		local a1 = UIKit.create("Attachment", { Position = Vector3.new(0, tip + 0.7, 0), Parent = rig })
		local trail = UIKit.create("Trail", {
			Attachment0 = a0,
			Attachment1 = a1,
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.3) }),
			Lifetime = 0.3, -- courte : la traînée n'atteint pas la caméra de vol
			MinLength = 0.1,
			FaceCamera = true,
			LightEmission = 0.4,
			Enabled = false,
			Parent = rig,
		})
		table.insert(flight.arms, { source = source, rig = rig, trail = trail })
	end
end

-- Cette méthode permet de donner le point du sol sous `position` (piste, obstacle ; y = 0 à défaut) lorsque un rebond
-- pose son anneau de poussière.
local function groundUnder(position: Vector3): Vector3
	local hit = Workspace:Raycast(position, Vector3.new(0, -20, 0), rayParams)
	if hit then
		return hit.Position + Vector3.new(0, 0.2, 0)
	end
	return Vector3.new(position.X, 0.2, position.Z)
end

-- Cette méthode permet de donner l'émetteur de l'anneau de poussière du k-ième rebond (créé à la première demande,
-- taille fixée par son rang : changer la taille d'un émetteur partagé redimensionnerait les anneaux encore à l'écran)
-- lorsque un rebond tombe.
local function ringFor(k: number): ParticleEmitter
	local rank = math.clamp(k, 1, 6)
	local existing = rings[rank]
	if existing then
		return existing
	end
	local scale = FlightFxRules.bounceScale(rank)
	-- Anneau à plat sur le sol (particule tournée vers sa vitesse, verticale et presque nulle) qui s'étend
	local ring = UIKit.create("ParticleEmitter", {
		Texture = DummyShape.fxTexture("ring"),
		Color = ColorSequence.new(Color3.fromRGB(245, 235, 215)),
		LightEmission = 0.2,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2 * scale),
			NumberSequenceKeypoint.new(1, 14 * scale),
		}),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.35),
		Speed = NumberRange.new(0.01),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.zero,
		Enabled = false,
		Parent = burstPart,
	})
	rings[rank] = ring
	return ring
end

-- Cette méthode permet de jouer le k-ième rebond du Rubber (« boing » de plus en plus aigu, anneau de poussière au
-- sol, étoiles) au torse affiché `position` lorsque le suivi l'annonce.
local function playBounce(flight: Flight, k: number, position: Vector3)
	local scale = FlightFxRules.bounceScale(k)
	local profile = flight.profile
	local ground = groundUnder(position)
	soundAt("Boing", position, 0.8, FlightFxRules.boingPitch(k))
	burstPart.CFrame = CFrame.new(ground)
	if profile.ring then
		ringFor(k):Emit(1)
	end
	-- Poussière en étoile, à plat sur le sol : une particule par direction
	local rays = math.max(math.floor(DUST_RAYS * profile.burst * scale + 0.5), 3)
	for i = 1, rays do
		burstAnchor.CFrame = CFrame.Angles(0, 2 * math.pi * i / rays, 0)
		dust:Emit(1)
	end
	burstAnchor.CFrame = CFrame.new()
	stars:Emit(math.max(math.floor(STARS * profile.burst * scale + 0.5), 2))
end

-- Cette méthode permet d'arrêter les effets d'un vol (émetteurs et traînées coupés, pièces retirées après LINGER s)
-- lorsque le mannequin disparaît ou que son suivi n'a plus rien à jouer.
local function finish(flight: Flight)
	flights[flight.model] = nil
	if flight.boosting then
		stopJet(flight)
	end
	for _, arm in flight.arms do
		arm.trail.Enabled = false
	end
	Debris:AddItem(flight.root, LINGER)
end

local begin: (Model, BasePart, FlightFxRules.Cues, Vector3, Vector3, number, number) -> ()

-- Cette méthode permet de commencer le suivi des effets d'un mannequin lancé lorsque il apparaît (rien pour un
-- mannequin sans comportement visible : Crash, Glass, Steel).
local function start(model: Model)
	if flights[model] then
		return
	end
	local origin = model:GetAttribute("LaunchOrigin")
	local velocity = model:GetAttribute("LaunchVelocity")
	local index = model:GetAttribute("ThrownIndex")
	if typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" or not ThrowDummies.isIndex(index) then
		return
	end
	-- Mannequin du joueur local parti au lâcher : ses effets portés par le décoratif passent sur lui au relais (adopt)
	if model:GetAttribute("Owner") == Players.LocalPlayer.UserId and LaunchGhost.anticipating() then
		return
	end
	local cues = FlightFxRules.cues(origin, velocity, Workspace.Gravity, ThrowDummies.get(index))
	if cues.boostAlong <= 0 and not cues.glide and cues.bounces == 0 then
		return
	end
	local torso = model:FindFirstChild("Torso")
	if not torso then
		-- Réplication en plusieurs paquets (connexion lente) : le suivi démarre à l'arrivée du torse
		local added, gone
		added = model.ChildAdded:Connect(function(child)
			if child.Name == "Torso" then
				added:Disconnect()
				gone:Disconnect()
				task.spawn(start, model)
			end
		end)
		-- Mannequin retiré avant l'arrivée du torse : plus rien à attendre
		gone = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				added:Disconnect()
				gone:Disconnect()
			end
		end)
		return
	end
	if flights[model] or not torso:IsA("BasePart") or not model.Parent then
		return
	end
	-- Suivi commencé en retard (arrivée en cours de vol, torse tardif) : temps du vol et rebonds déjà passés
	local launchedAt = model:GetAttribute("LaunchTime")
	local age = if typeof(launchedAt) == "number" then Workspace:GetServerTimeNow() - launchedAt else 0
	local counted = model:GetAttribute("Bounces")
	begin(model, torso, cues, origin, velocity, age, if typeof(counted) == "number" then counted else 0)
end

-- Cette méthode permet de commencer le suivi des effets d'un mannequin affiché lorsque son vol démarre (repères
-- `cues`, départ `origin` à `velocity`, `age` s déjà écoulées, `counted` rebonds déjà comptés).
function begin(
	model: Model,
	torso: BasePart,
	cues: FlightFxRules.Cues,
	origin: Vector3,
	velocity: Vector3,
	age: number,
	counted: number
)
	local root = UIKit.create("Folder", { Name = model.Name, Parent = folder })
	local flight: Flight = {
		model = model,
		torso = torso,
		tracker = FlightFxRules.tracker(cues, origin, velocity, age, counted),
		profile = FlightFxRules.profile(UIKit.reducedMotion()),
		root = root,
		jet = nil,
		flame = nil,
		smoke = nil,
		light = nil,
		roar = nil,
		arms = {},
		previous = nil,
		heading = if velocity.Magnitude > 1e-3 then velocity.Unit else Vector3.zAxis,
		boosting = cues.boostAlong > 0,
		gliding = false,
	}
	if flight.boosting then
		addJet(flight)
	end
	if cues.glide then
		addTrails(flight)
	end
	flights[model] = flight
end

-- Cette méthode permet d'avancer les effets d'un vol d'une image de `dt` s (pièces d'effets placées sur ce qui est
-- affiché, effets allumés ou joués selon Shared.FlightFx) lorsque le client dessine.
local function step(flight: Flight, dt: number)
	local model, torso = flight.model, flight.torso
	if not torso.Parent or not model.Parent or flight.tracker.time > GameConfig.MAX_FLIGHT_TIME + 2 then
		finish(flight)
		return
	end
	local offset = LaunchGhost.offset(model)
	local position = torso.Position + offset
	local counted = model:GetAttribute("Bounces")
	local frame = FlightFxRules.step(flight.tracker, position, dt, if typeof(counted) == "number" then counted else 0)

	-- Direction affichée du mouvement : la flamme part à l'opposé
	local previous = flight.previous
	flight.previous = position
	if previous and dt > 0 then
		local moved = position - previous
		if moved.Magnitude > 1e-3 then
			local heading = flight.heading:Lerp(moved.Unit, math.min(dt * 20, 1))
			-- Demi-tour en une image (piège) : le mélange s'annule, on prend la nouvelle direction
			flight.heading = if heading.Magnitude > 1e-3 then heading.Unit else moved.Unit
		end
	end

	local jet = flight.jet
	if jet then
		if flight.boosting and not frame.boosting then
			stopJet(flight)
		end
		local behind = position - flight.heading * FLAME_BACK
		jet.CFrame = CFrame.lookAt(behind, behind - flight.heading)
	end
	flight.boosting = frame.boosting

	if flight.tracker.cues.glide and #flight.arms < #ARMS then
		addTrails(flight)
	end
	for _, arm in flight.arms do
		arm.rig.CFrame = arm.source.CFrame + offset
		if arm.trail.Enabled ~= frame.gliding then
			arm.trail.Enabled = frame.gliding
		end
	end
	if frame.glideStart then
		soundAt("Gust", position, 0.5, 1.15)
	end
	flight.gliding = frame.gliding

	if frame.bounce then
		playBounce(flight, frame.bounce, position)
	end
end

-- Cette méthode permet de commencer les effets du vol sur le décoratif lâché par le joueur local (`visual`, départ prévu
-- par le client) lorsque il part sans attendre le serveur (#144).
local function preview(visual: Model, origin: Vector3, velocity: Vector3, index: number)
	local torso = visual.PrimaryPart
	if not torso or flights[visual] then
		return
	end
	local cues = FlightFxRules.cues(origin, velocity, Workspace.Gravity, ThrowDummies.get(index))
	if cues.boostAlong <= 0 and not cues.glide and cues.bounces == 0 then
		return
	end
	begin(visual, torso, cues, origin, velocity, 0, 0)
end

-- Cette méthode permet de faire passer les effets du décoratif lâché (`visual`) au mannequin du serveur (`model`), sans
-- les rallumer, lorsque sa copie locale prend le relais ; suivi ordinaire si le décoratif n'en portait pas.
local function adopt(visual: Model, model: Model)
	local flight = flights[visual]
	local torso = model:FindFirstChild("Torso")
	if not flight or flights[model] or not torso or not torso:IsA("BasePart") then
		if flight then
			finish(flight)
		end
		task.spawn(start, model)
		return
	end
	flights[visual] = nil
	flight.model = model
	flight.torso = torso
	local origin = model:GetAttribute("LaunchOrigin")
	local velocity = model:GetAttribute("LaunchVelocity")
	local index = model:GetAttribute("ThrownIndex")
	if typeof(origin) == "Vector3" and typeof(velocity) == "Vector3" and ThrowDummies.isIndex(index) then
		local tracker = flight.tracker
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		tracker.cues = FlightFxRules.cues(origin, velocity, Workspace.Gravity, ThrowDummies.get(index))
		tracker.origin = origin
		tracker.flat = if horizontal.Magnitude > 1e-3 then horizontal.Unit else Vector3.zAxis
	end
	-- Repères du plan recalculés sur le départ du serveur ; traînées posées sur les bras du décoratif (échelle de la
	-- main) reposées sur ceux du mannequin du serveur
	for _, arm in flight.arms do
		arm.rig:Destroy()
	end
	flight.arms = {}
	if flight.tracker.cues.glide then
		addTrails(flight)
	end
	flights[model] = flight
end

-- Cette méthode permet de créer les émetteurs des rebonds et de suivre les mannequins lancés (dossier Course/Dummies)
-- lorsque le client démarre.
function FlightFx.init()
	folder = UIKit.create("Folder", { Name = "FlightFx", Parent = Workspace })
	burstPart = rigPart("Bounce", folder)
	burstAnchor = UIKit.create("Attachment", { Parent = burstPart })
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { folder }
	dust = UIKit.create("ParticleEmitter", {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(215, 200, 175)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3.5) }),
		Lifetime = NumberRange.new(0.4, 0.6),
		Speed = NumberRange.new(18, 24),
		Drag = 5,
		SpreadAngle = Vector2.new(4, 4),
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Front,
		Enabled = false,
		Parent = burstAnchor,
	})
	stars = UIKit.create("ParticleEmitter", {
		Texture = DummyShape.fxTexture("star"),
		Color = ColorSequence.new(Color3.fromRGB(255, 225, 60)),
		LightEmission = 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(14, 22),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = Vector3.new(0, -40, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
		EmissionDirection = Enum.NormalId.Top,
		Enabled = false,
		Parent = burstPart,
	})
	LaunchGhost.onAnticipate = preview
	LaunchGhost.onSwap = adopt
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, function(dt)
		for _, flight in flights do
			step(flight, dt)
		end
	end)
	task.spawn(function()
		local dummies = Workspace:WaitForChild("Course"):WaitForChild("Dummies")
		rayParams.FilterDescendantsInstances = { dummies, folder }
		-- Cette méthode permet de suivre un mannequin lorsque il apparaît dans le dossier ou que son départ arrive.
		local function watch(child: Instance)
			if not child:IsA("Model") then
				return
			end
			if child:GetAttribute("LaunchVelocity") ~= nil then
				task.spawn(start, child)
			else
				child:GetAttributeChangedSignal("LaunchVelocity"):Once(function()
					task.spawn(start, child)
				end)
			end
		end
		for _, child in dummies:GetChildren() do
			watch(child)
		end
		dummies.ChildAdded:Connect(watch)
	end)
end

return FlightFx
