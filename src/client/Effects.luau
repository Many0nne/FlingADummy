-- Effets des crashs, joués par chaque client à partir des chocs annoncés par le serveur : son positionné, gerbe de
-- particules, popup dans la scène (« +1 BONE », « SMASH x6 », « BOING! » des pièges des thèmes), combos, foule sur les gros crashs ; secousses de
-- caméra et souffle du vent pour le vol du joueur local.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Sounds"))
local Traps = require(Shared:WaitForChild("Traps"))

local FlightCamera = require(script.Parent.FlightCamera)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local COMBO_WINDOW = 1.2 -- chocs enchaînés dans cet intervalle = combo (s)
local CROWD_COOLDOWN = 2.5
local WIND_MAX_VOLUME = 0.6

local Effects = {}

local player: Player
local folder: Folder
local emitters: { [string]: ParticleEmitter } = {}
local emitterAnchor: Attachment
local combo = 0
local lastComboTime = 0
local lastCrowd = 0
local wind: Sound
local flyingTorso: BasePart? = nil

-- Cette méthode permet de jouer un son à une position du monde lorsque survient un choc.
local function playAt(name: string, position: Vector3, pitch: number?)
	local definition = Sounds[name]
	if not definition then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Parent = Workspace.Terrain
	holder.WorldPosition = position
	local sound = Instance.new("Sound")
	sound.SoundId = definition.id
	sound.Volume = definition.volume
	sound.PlaybackSpeed = pitch or (0.9 + math.random() * 0.2)
	sound.RollOffMinDistance = 40
	sound.RollOffMaxDistance = 600
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 6)
end

-- Cette méthode permet de créer un émetteur de particules réutilisable (déclenché par Emit) lorsque le client
-- démarre.
local function emitter(name: string, props: { [string]: any })
	local particles = UIKit.create("ParticleEmitter", props)
	particles.Name = name
	particles.Enabled = false
	particles.Parent = emitterAnchor
	emitters[name] = particles
end

-- Cette méthode permet d'émettre une gerbe de particules à une position lorsque survient un choc.
local function burst(name: string, position: Vector3, count: number)
	local particles = emitters[name]
	if particles then
		emitterAnchor.WorldPosition = position
		particles:Emit(count)
	end
end

-- Cette méthode permet d'afficher un texte qui monte et s'efface au point d'un choc lorsque le joueur doit lire ce
-- qu'il vient de gagner.
local function popup(position: Vector3, text: string, color: Color3, size: number?)
	local anchor = Instance.new("Attachment")
	anchor.Parent = Workspace.Terrain
	anchor.WorldPosition = position
	local gui = UIKit.create("BillboardGui", {
		Size = UDim2.fromOffset(320, 70),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 400,
		Adornee = anchor,
		Parent = anchor,
	})
	local label = UIKit.text({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextSize = size or 40,
		TextColor3 = color,
		StrokeThickness = 4,
		Rotation = math.random(-8, 8),
		Parent = gui,
	})
	UIKit.pop(label, 1.8)
	TweenService:Create(gui, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
	}):Play()
	task.delay(0.7, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(anchor, 1.3)
end

-- Cette méthode permet de compter les chocs enchaînés du joueur local et d'afficher le combo lorsqu'il atteint 3.
local function bumpCombo(position: Vector3)
	local now = os.clock()
	combo = if now - lastComboTime <= COMBO_WINDOW then combo + 1 else 1
	lastComboTime = now
	if combo >= 3 then
		popup(position + Vector3.new(0, 5, 0), "x" .. combo .. " COMBO!", C.gold, 36 + math.min(combo, 10) * 2)
	end
	if combo >= 5 and now - lastCrowd > CROWD_COOLDOWN then
		lastCrowd = now
		UIKit.playSound("Crowd")
	end
end

-- Cette méthode permet de jouer les effets d'un choc annoncé par le serveur lorsque l'événement Impact arrive.
local function onImpact(impact: any)
	local position: Vector3 = impact.position
	local mine = impact.userId == player.UserId
	if impact.kind == "Throw" then
		playAt("Whoosh", position, 0.8)
		if mine then
			FlightCamera.punch()
			combo = 0
		end
	elseif impact.kind == "Glass" then
		playAt("Glass", position)
		burst("Glass", position, 40)
		popup(position, "GLASS!", C.glass)
		if mine then
			FlightCamera.shake(0.6)
			bumpCombo(position)
		end
	elseif impact.kind == "Bone" then
		local bones = impact.value or 1
		playAt("Bone", position, 0.85 + math.random() * 0.3)
		burst("Bone", position, 12 * bones)
		popup(position, "+" .. bones .. (if bones > 1 then " BONES" else " BONE"), C.bone)
		if mine then
			FlightCamera.shake(0.5 * bones)
			bumpCombo(position)
			if bones >= 2 and os.clock() - lastCrowd > CROWD_COOLDOWN then
				lastCrowd = os.clock()
				UIKit.playSound("Crowd")
			end
		end
	elseif impact.kind == "Smash" then
		local count = impact.value or 1
		playAt(if impact.material == "Brick" then "Brick" else "Crate", position)
		burst("Dust", position, 10 + count * 3)
		burst("Chips", position, 6 + count * 2)
		popup(position, "SMASH" .. (if count > 1 then " x" .. count else "!"), C.smash)
		if mine then
			FlightCamera.shake(0.3 + count * 0.05)
			bumpCombo(position)
		end
	elseif impact.kind == "Trap" then
		local def = Traps.KINDS[impact.material or ""]
		if def then
			playAt(def.sound, position, 1)
			burst(def.burst, position, 40)
			burst("Dust", position, 10)
			popup(position + Vector3.new(0, 3, 0), def.label, C.gold, 52)
			if mine then
				FlightCamera.shake(0.9)
				bumpCombo(position)
			end
		end
	elseif impact.kind == "Thud" then
		playAt("Thud", position)
		burst("Dust", position, 14)
		if mine then
			FlightCamera.shake(math.min((impact.value or 40) / 80, 1.2))
		end
	end
end

-- Cette méthode permet de faire suivre le souffle du vent au mannequin du joueur local (volume selon la vitesse)
-- lorsque son lancer part ; nil l'arrête.
function Effects.setFlying(model: Model?)
	flyingTorso = if model then model:FindFirstChild("Torso") :: BasePart? else nil
end

-- Cette méthode permet de créer les émetteurs, le son du vent et de brancher l'événement Impact lorsque le client
-- démarre.
function Effects.init(localPlayer: Player, impactRemote: RemoteEvent)
	player = localPlayer
	folder = UIKit.create("Folder", { Name = "Effects", Parent = Workspace })
	local holder = UIKit.create("Part", {
		Name = "EmitterHolder",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one,
		Parent = folder,
	})
	emitterAnchor = UIKit.create("Attachment", { Parent = holder })
	emitter("Glass", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(200, 240, 255)),
		LightEmission = 1,
		Size = NumberSequence.new(1.2, 0),
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(20, 45),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
	})
	emitter("Bone", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 80, 60), Color3.fromRGB(255, 255, 255)),
		LightEmission = 0.6,
		Size = NumberSequence.new(1.5, 0),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(15, 30),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	})
	emitter("Dust", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(200, 190, 175)),
		Transparency = NumberSequence.new(0.3, 1),
		Size = NumberSequence.new(3, 9),
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(180, 60),
		Drag = 2,
		Rotation = NumberRange.new(0, 360),
	})
	emitter("Chips", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90)),
		Size = NumberSequence.new(0.8, 0.2),
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(120, 120),
		Acceleration = Vector3.new(0, -80, 0),
	})
	-- Gerbes des pièges des thèmes (Shared.Traps : `burst`)
	local sparkle = "rbxasset://textures/particles/sparkles_main.dds"
	emitter("Stars", {
		Texture = sparkle,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 80)),
		LightEmission = 1,
		Size = NumberSequence.new(1.6, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(20, 35),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
	})
	emitter("Wind", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
		Transparency = NumberSequence.new(0.4, 1),
		Size = NumberSequence.new(2, 6),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(30, 50),
		SpreadAngle = Vector2.new(180, 40),
		Drag = 2,
	})
	emitter("Splash", {
		Texture = sparkle,
		Color = ColorSequence.new(Color3.fromRGB(120, 210, 255), Color3.fromRGB(255, 255, 255)),
		Size = NumberSequence.new(1.4, 0.4),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -90, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	emitter("Sparks", {
		Texture = sparkle,
		Color = ColorSequence.new(Color3.fromRGB(140, 230, 255), Color3.fromRGB(255, 255, 255)),
		LightEmission = 1,
		Size = NumberSequence.new(1, 0),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(30, 55),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	})
	emitter("Snow", {
		Texture = sparkle,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Size = NumberSequence.new(1.2, 0.6),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(10, 25),
		SpreadAngle = Vector2.new(180, 90),
		Acceleration = Vector3.new(0, -30, 0),
	})
	emitter("Fire", {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 60, 20)),
		LightEmission = 1,
		Size = NumberSequence.new(3, 0),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(12, 25),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
	})
	emitter("Confetti", {
		Texture = sparkle,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 160)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(90, 200, 255)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 230, 110)),
		}),
		Size = NumberSequence.new(1, 0.5),
		Lifetime = NumberRange.new(0.9, 1.6),
		Speed = NumberRange.new(25, 45),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -40, 0),
		Drag = 2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
	})
	wind = UIKit.create("Sound", {
		SoundId = Sounds.Wind.id,
		Looped = true,
		Volume = 0,
		Parent = folder,
	})
	wind:Play()
	RunService.RenderStepped:Connect(function(dt)
		local torso = flyingTorso
		local target = 0
		if torso and torso.Parent then
			target = math.clamp(torso.AssemblyLinearVelocity.Magnitude / 300, 0, 1) * WIND_MAX_VOLUME
		end
		wind.Volume += (target - wind.Volume) * math.min(dt * 6, 1)
		wind.PlaybackSpeed = 0.8 + wind.Volume
	end)
	impactRemote.OnClientEvent:Connect(function(list)
		if type(list) ~= "table" then
			return
		end
		for _, impact in list do
			if type(impact) == "table" and typeof(impact.position) == "Vector3" then
				onImpact(impact)
			end
		end
	end)
	-- Un joueur qui quitte ne laisse pas de son de vent
	Players.LocalPlayer:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Ready" then
			flyingTorso = nil
		end
	end)
end

return Effects
