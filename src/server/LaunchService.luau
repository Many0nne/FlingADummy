-- Lancers : l'avatar projette le mannequin depuis ses mains, le serveur suit le vol (distance, zone, os cassés par
-- membre, vitres et objets détruits), annonce chaque choc aux clients (effets), calcule les gains puis remet le
-- couloir à neuf. Toute la physique est simulée par le serveur (propriétaire réseau nil).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Damage = require(Shared.Damage)
local Economy = require(Shared.Economy)
local GameConfig = require(Shared.GameConfig)
local Gauge = require(Shared.Gauge)
local Remotes = require(Shared.Remotes)
local Zones = require(Shared.Zones)

local CourseBuilder = require(script.Parent.CourseBuilder)
local DummyFactory = require(script.Parent.DummyFactory)
local LaneService = require(script.Parent.LaneService)
local PlayerData = require(script.Parent.PlayerData)

type Lane = CourseBuilder.Lane

local GLASS_SLOWDOWN = 0.97 -- vitesse conservée en traversant une vitre (il y en a jusqu'à 9 par vol)
local SPIN = Vector3.new(5, 2, 2) -- rotation aléatoire maximale au départ (rad/s par axe)
local THUD_DV = 40 -- choc du torse sans os cassé qui mérite un « boum »
local THUD_COOLDOWN = 0.25
local GLASS_CAUSE_WINDOW = 0.15 -- un os cassé juste après une vitre est attribué à la vitre (s)
local CAUSE_RADIUS = 7 -- un os cassé près d'une caisse ou d'une brique leur est attribué (studs)

export type Impact = {
	kind: string, -- "Throw" | "Glass" | "Bone" | "Smash" | "Thud"
	position: Vector3,
	value: number?, -- os ajoutés, objets détruits, ou force du choc
	material: string?, -- "Crate" | "Brick" pour Smash
	userId: number,
}

type Flight = {
	player: Player,
	lane: Lane,
	dummy: Model,
	torso: BasePart,
	parts: { BasePart },
	startTime: number,
	gauge: number,
	perfect: boolean,
	prevVelocity: { [BasePart]: Vector3 },
	bones: { [string]: number },
	totalBones: number,
	smashed: number,
	counted: { [BasePart]: boolean },
	distance: number,
	prevPosition: Vector3,
	restTime: number,
	lastGlass: number,
	lastThud: number,
	worstImpact: { kind: string, dv: number, speed: number }?,
	impacts: { Impact },
}

local LaunchService = {}

local remotes: Remotes.Remotes
local flights: { [Player]: Flight } = {}
local rng = Random.new()

-- Cette méthode permet de donner le point de départ du mannequin (main de l'avatar au lâcher de l'animation de
-- lancer, au-dessus de la tête côté bras droit ; zone de lancer si le personnage manque) lorsqu'un lancer part.
local function throwOrigin(player: Player, lane: Lane): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- Repère horizontal de l'avatar (là où sa main lâche le décoratif), sinon celui de la piste (la direction du
	-- lancer est inclinée de LAUNCH_PITCH_DEG)
	local look = if root then root.CFrame.LookVector else lane.direction
	local flat = Vector3.new(look.X, 0, look.Z)
	local forward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local right = forward:Cross(Vector3.yAxis)
	local offset = Vector3.new(0, GameConfig.THROW_HEIGHT, 0)
		+ forward * GameConfig.THROW_FORWARD
		+ right * GameConfig.THROW_SIDE
	if root then
		return root.Position + offset
	end
	return lane.pad + Vector3.new(0, 3, 0) + offset
end

-- Cette méthode permet de tirer le mannequin d'un joueur lorsqu'il le tient sur la zone de lancer (ou que `force`
-- vient de DebugLaunch) ; `gauge` vient du client et est borné ici.
function LaunchService.launch(player: Player, gauge: any, force: boolean?)
	if typeof(gauge) ~= "number" or gauge ~= gauge then
		return
	end
	gauge = math.clamp(gauge, 0, 1)
	if player:GetAttribute("LaneState") ~= "Ready" or not player:GetAttribute("DataReady") then
		return
	end
	if not force and player:GetAttribute("Action") ~= "Holding" then
		return
	end
	local lane = LaneService.getLane(player)
	if not lane then
		return
	end
	player:SetAttribute("LaneState", "Flying")
	player:SetAttribute("Action", nil)

	local power = (player:GetAttribute("ThrowPower") :: number?) or GameConfig.START_POWER
	local speed = Economy.launchSpeed(power) * Gauge.launchFactor(gauge)
	local dir = lane.direction
	local origin = throwOrigin(player, lane)
	local dummy = DummyFactory.build()
	-- Tête la première : l'axe vertical du mannequin suit la direction du lancer
	dummy:PivotTo(CFrame.fromMatrix(origin, Vector3.xAxis, dir))
	dummy.Parent = lane.folder

	local spin =
		Vector3.new(rng:NextNumber(-SPIN.X, SPIN.X), rng:NextNumber(-SPIN.Y, SPIN.Y), rng:NextNumber(-SPIN.Z, SPIN.Z))
	local parts = {}
	for _, child in dummy:GetChildren() do
		if child:IsA("BasePart") and not child:GetAttribute("Accessory") then
			child:SetNetworkOwner(nil)
			child.AssemblyLinearVelocity = dir * speed
			child.AssemblyAngularVelocity = spin
			table.insert(parts, child)
		end
	end
	dummy:SetAttribute("Distance", 0)
	dummy:SetAttribute("Bones", 0)
	dummy:SetAttribute("Smashed", 0)
	dummy:SetAttribute("Zone", 1)
	dummy:SetAttribute("Speed", math.floor(speed))

	local torso = dummy.PrimaryPart :: BasePart
	local flight: Flight = {
		player = player,
		lane = lane,
		dummy = dummy,
		torso = torso,
		parts = parts,
		startTime = os.clock(),
		gauge = gauge,
		perfect = Gauge.isPerfect(gauge),
		prevVelocity = {},
		bones = {},
		totalBones = 0,
		smashed = 0,
		counted = {},
		distance = 0,
		prevPosition = torso.Position,
		restTime = 0,
		lastGlass = -math.huge,
		lastThud = -math.huge,
		worstImpact = nil,
		impacts = {},
	}
	flights[player] = flight
	remotes.LaunchStarted:FireClient(player, dummy)
	remotes.Impact:FireAllClients({
		{ kind = "Throw", position = origin, value = speed, userId = player.UserId },
	})
end

-- Cette méthode permet de noter un choc à annoncer aux clients en fin de frame lorsque le vol en produit un.
local function addImpact(flight: Flight, kind: string, position: Vector3, value: number?, material: string?)
	table.insert(flight.impacts, {
		kind = kind,
		position = position,
		value = value,
		material = material,
		userId = flight.player.UserId,
	})
end

-- Cette méthode permet de briser une vitre et de ralentir un peu le mannequin lorsqu'il la traverse au point
-- `crossing` ; les vitesses de référence sont recalées pour que le ralentissement ne compte pas comme un choc.
local function shatterGlass(flight: Flight, glass: CourseBuilder.Glass, crossing: Vector3)
	CourseBuilder.shatter(flight.lane, glass, crossing, flight.torso.AssemblyLinearVelocity)
	for _, p in flight.parts do
		local v = p.AssemblyLinearVelocity * GLASS_SLOWDOWN
		p.AssemblyLinearVelocity = v
		flight.prevVelocity[p] = v
	end
	flight.smashed += 1
	flight.lastGlass = os.clock()
	addImpact(flight, "Glass", crossing)
end

-- Cette méthode permet de détecter les vitres franchies par le torse entre deux frames lorsqu'il avance ; le
-- franchissement remplace la collision, qui raterait une vitre fine à grande vitesse.
local function checkGlass(flight: Flight, position: Vector3)
	local previous = flight.prevPosition
	flight.prevPosition = position
	if position.Z <= previous.Z then
		return
	end
	for _, glass in flight.lane.glass do
		if not glass.broken and previous.Z < glass.z and position.Z >= glass.z then
			local crossing = previous:Lerp(position, (glass.z - previous.Z) / (position.Z - previous.Z))
			if crossing.Y <= glass.top then
				shatterGlass(flight, glass, crossing)
			end
		end
	end
end

-- Cette méthode permet de trouver ce qui a cassé un os (vitre, mur, caisses ou sol) lorsqu'un membre subit un choc
-- au point `position`.
local function classifyCause(flight: Flight, position: Vector3): string
	if os.clock() - flight.lastGlass < GLASS_CAUSE_WINDOW then
		return "Glass"
	end
	for _, p in flight.lane.breakables do
		if p.Parent and (p.Position - position).Magnitude < CAUSE_RADIUS then
			return if p.Name == "Brick" then "Wall" else "Crates"
		end
	end
	return "Ground"
end

-- Cette méthode permet de casser des os lorsqu'un membre change brusquement de vitesse entre deux frames ; pas de
-- dégâts pendant IMPACT_GRACE_TIME (le lancer vient d'imposer la vitesse).
local function checkBones(flight: Flight, elapsed: number)
	local armed = elapsed > GameConfig.IMPACT_GRACE_TIME
	local now = os.clock()
	for _, p in flight.parts do
		local v = p.AssemblyLinearVelocity
		local before = flight.prevVelocity[p]
		flight.prevVelocity[p] = v
		if not armed or not before then
			continue
		end
		local dv = (v - before).Magnitude
		local current = flight.bones[p.Name] or 0
		local added = math.min(Damage.bonesForImpact(dv), GameConfig.MAX_BONES_PER_LIMB - current)
		if added > 0 then
			flight.bones[p.Name] = current + added
			flight.totalBones += added
			p.Color = Damage.tint(p:GetAttribute("BaseColor") or p.Color, current + added)
			p:SetAttribute("Bones", current + added)
			addImpact(flight, "Bone", p.Position, added)
			if not flight.worstImpact or dv > flight.worstImpact.dv then
				flight.worstImpact = { kind = classifyCause(flight, p.Position), dv = dv, speed = before.Magnitude }
			end
		elseif p == flight.torso and dv > THUD_DV and now - flight.lastThud > THUD_COOLDOWN then
			flight.lastThud = now
			addImpact(flight, "Thud", p.Position, dv)
		end
	end
end

-- Cette méthode permet de compter une fois chaque caisse ou brique du couloir lorsqu'elle est projetée ; un seul
-- choc « Smash » par type et par frame est annoncé, avec le nombre d'objets.
local function checkSmashed(flight: Flight)
	local byMaterial: { [string]: { count: number, position: Vector3 } } = {}
	for _, p in flight.lane.breakables do
		if not flight.counted[p] and p.AssemblyLinearVelocity.Magnitude > GameConfig.SMASH_SPEED then
			flight.counted[p] = true
			flight.smashed += 1
			local entry = byMaterial[p.Name]
			if entry then
				entry.count += 1
			else
				byMaterial[p.Name] = { count = 1, position = p.Position }
			end
		end
	end
	for material, entry in byMaterial do
		addImpact(flight, "Smash", entry.position, entry.count, material)
	end
end

-- Cette méthode permet de détruire le mannequin et de remettre le couloir à neuf lorsque le lancer est terminé.
local function clearLane(flight: Flight)
	flight.dummy:Destroy()
	CourseBuilder.resetObstacles(flight.lane)
end

-- Cette méthode permet de clore un vol (gains, record, blessures et cause envoyées au client) lorsque le mannequin
-- s'est arrêté, puis de rendre le couloir prêt après RESULT_TIME.
local function finish(flight: Flight, elapsed: number)
	local player = flight.player
	flights[player] = nil
	local zone = Zones.at(flight.distance)
	local result: any = Economy.payout({
		distance = flight.distance,
		bones = flight.totalBones,
		smashed = flight.smashed,
		perfect = flight.perfect,
		zoneMultiplier = zone.multiplier,
	}, (player:GetAttribute("ValueLevel") :: number?) or 1)
	local best = (player:GetAttribute("BestDistance") :: number?) or 0
	result.record = result.distance > best and best > 0
	result.zone = Zones.indexAt(flight.distance)
	result.bonesByLimb = flight.bones
	result.injuries = Damage.describe(flight.bones)
	result.cause = if flight.worstImpact then Damage.cause(flight.worstImpact.kind, flight.worstImpact.speed) else nil
	PlayerData.addMoney(player, result.total)
	PlayerData.recordDistance(player, result.distance)
	player:SetAttribute("LaneState", "Result")
	remotes.LaunchResult:FireClient(player, result)
	if RunService:IsStudio() then
		print(
			string.format(
				"[Launch] distance=%d zone=%d bones=%d smashed=%d payout=%d gauge=%.2f power=%d time=%.1f | %s | %s",
				result.distance,
				result.zone,
				result.bones,
				result.smashed,
				result.total,
				flight.gauge,
				(player:GetAttribute("ThrowPower") :: number?) or 0,
				elapsed,
				result.injuries,
				tostring(result.cause)
			)
		)
	end
	task.delay(GameConfig.RESULT_TIME, function()
		clearLane(flight)
		if player.Parent and LaneService.getLane(player) == flight.lane then
			player:SetAttribute("LaneState", "Ready")
		end
	end)
end

-- Cette méthode permet de mettre à jour les attributs du mannequin lus par le client (compteurs, zone) lorsqu'ils
-- changent.
local function publish(flight: Flight)
	local dummy = flight.dummy
	local values = {
		Distance = math.max(0, math.floor(flight.distance)),
		Bones = flight.totalBones,
		Smashed = flight.smashed,
		Zone = Zones.indexAt(flight.distance),
	}
	for name, value in values do
		if dummy:GetAttribute(name) ~= value then
			dummy:SetAttribute(name, value)
		end
	end
end

-- Cette méthode permet d'avancer le suivi d'un vol d'une frame lorsque Heartbeat tourne.
local function step(flight: Flight, dt: number)
	local elapsed = os.clock() - flight.startTime
	local torso = flight.torso
	if not flight.player.Parent or not torso.Parent then
		flights[flight.player] = nil
		clearLane(flight)
		return
	end
	local position = torso.Position
	checkGlass(flight, position)
	checkBones(flight, elapsed)
	checkSmashed(flight)
	flight.distance = math.max(flight.distance, position.Z)
	publish(flight)
	if #flight.impacts > 0 then
		remotes.Impact:FireAllClients(flight.impacts)
		flight.impacts = {}
	end

	if torso.AssemblyLinearVelocity.Magnitude < GameConfig.REST_SPEED then
		flight.restTime += dt
	else
		flight.restTime = 0
	end
	if
		flight.restTime >= GameConfig.REST_TIME
		or elapsed >= GameConfig.MAX_FLIGHT_TIME
		or position.Y < GameConfig.KILL_Y
	then
		finish(flight, elapsed)
	end
end

-- Cette méthode permet de déclencher un lancer en écrivant l'attribut DebugLaunch (0-1) sur le joueur lorsque l'on
-- teste dans Studio sans simuler d'input (lancer depuis la zone de lancer, même si l'avatar n'y est pas).
local function watchDebugLaunch(player: Player)
	player:GetAttributeChangedSignal("DebugLaunch"):Connect(function()
		local value = player:GetAttribute("DebugLaunch")
		if typeof(value) ~= "number" then
			return
		end
		player:SetAttribute("DebugLaunch", nil)
		if player:GetAttribute("LaneState") ~= "Ready" then
			print("[Launch] DebugLaunch ignoré : LaneState = " .. tostring(player:GetAttribute("LaneState")))
			return
		end
		LaunchService.launch(player, value, true)
	end)
end

-- Cette méthode permet de brancher les remotes, le suivi des vols et le nettoyage au départ lorsque le serveur
-- démarre.
function LaunchService.init(createdRemotes: Remotes.Remotes)
	remotes = createdRemotes
	remotes.Launch.OnServerEvent:Connect(function(player, gauge)
		LaunchService.launch(player, gauge)
	end)
	RunService.Heartbeat:Connect(function(dt)
		for _, flight in flights do
			step(flight, dt)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local flight = flights[player]
		if flight then
			flights[player] = nil
			clearLane(flight)
		end
	end)
	if RunService:IsStudio() then
		Players.PlayerAdded:Connect(watchDebugLaunch)
		for _, player in Players:GetPlayers() do
			watchDebugLaunch(player)
		end
	end
end

return LaunchService
