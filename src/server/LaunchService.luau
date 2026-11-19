-- Lancers : tir du mannequin, suivi du vol (distance, os cassés, vitres et objets détruits), résultat et remise à
-- neuf du couloir. Toute la physique est simulée par le serveur (propriétaire réseau nil).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Damage = require(Shared.Damage)
local Economy = require(Shared.Economy)
local GameConfig = require(Shared.GameConfig)
local Gauge = require(Shared.Gauge)
local Remotes = require(Shared.Remotes)

local CourseBuilder = require(script.Parent.CourseBuilder)
local DummyFactory = require(script.Parent.DummyFactory)
local LaneService = require(script.Parent.LaneService)
local PlayerData = require(script.Parent.PlayerData)

type Lane = CourseBuilder.Lane

local GLASS_SLOWDOWN = 0.9 -- vitesse conservée en traversant une vitre
local SPIN = Vector3.new(4, 1.5, 1.5) -- rotation aléatoire maximale au départ (rad/s par axe)
local START_BACK = 1.5 -- centre du torse en retrait de la bouche (studs) : la tête dépasse du canon

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
	bones: { [BasePart]: number },
	totalBones: number,
	smashed: number,
	counted: { [BasePart]: boolean },
	distance: number,
	prevPosition: Vector3,
	restTime: number,
}

local LaunchService = {}

local remotes: Remotes.Remotes
local flights: { [Player]: Flight } = {}
local rng = Random.new()

-- Cette méthode permet de tirer le mannequin d'un joueur lorsque son couloir est prêt ; `gauge` vient du client et
-- est borné ici.
function LaunchService.launch(player: Player, gauge: any)
	if typeof(gauge) ~= "number" or gauge ~= gauge then
		return
	end
	gauge = math.clamp(gauge, 0, 1)
	if player:GetAttribute("LaneState") ~= "Ready" or not player:GetAttribute("DataReady") then
		return
	end
	local lane = LaneService.getLane(player)
	if not lane then
		return
	end
	player:SetAttribute("LaneState", "Flying")

	local speed = Economy.launchSpeed((player:GetAttribute("PowerLevel") :: number?) or 1) * Gauge.launchFactor(gauge)
	local dir = lane.direction
	local dummy = DummyFactory.build()
	-- Tête la première : l'axe vertical du mannequin suit la direction de tir
	dummy:PivotTo(CFrame.fromMatrix(lane.muzzle - dir * START_BACK, Vector3.xAxis, dir))
	dummy.Parent = lane.folder

	local spin =
		Vector3.new(rng:NextNumber(-SPIN.X, SPIN.X), rng:NextNumber(-SPIN.Y, SPIN.Y), rng:NextNumber(-SPIN.Z, SPIN.Z))
	local parts = {}
	for _, child in dummy:GetChildren() do
		if child:IsA("BasePart") then
			child:SetNetworkOwner(nil)
			child.AssemblyLinearVelocity = dir * speed
			child.AssemblyAngularVelocity = spin
			table.insert(parts, child)
		end
	end
	dummy:SetAttribute("Distance", 0)
	dummy:SetAttribute("Bones", 0)
	dummy:SetAttribute("Smashed", 0)

	local torso = dummy.PrimaryPart :: BasePart
	flights[player] = {
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
	}
	remotes.LaunchStarted:FireClient(player, dummy)
end

-- Cette méthode permet de briser une vitre et de ralentir le mannequin lorsqu'il la traverse au point `crossing` ;
-- les vitesses de référence sont recalées pour que le ralentissement ne compte pas comme un choc.
local function shatterGlass(flight: Flight, glass: CourseBuilder.Glass, crossing: Vector3)
	CourseBuilder.shatter(flight.lane, glass, crossing, flight.torso.AssemblyLinearVelocity)
	for _, p in flight.parts do
		local v = p.AssemblyLinearVelocity * GLASS_SLOWDOWN
		p.AssemblyLinearVelocity = v
		flight.prevVelocity[p] = v
	end
	flight.smashed += 1
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

-- Cette méthode permet de casser des os lorsqu'un membre change brusquement de vitesse entre deux frames ; pas de
-- dégâts pendant IMPACT_GRACE_TIME (le canon vient d'imposer la vitesse).
local function checkBones(flight: Flight, elapsed: number)
	local armed = elapsed > GameConfig.IMPACT_GRACE_TIME
	for _, p in flight.parts do
		local v = p.AssemblyLinearVelocity
		local before = flight.prevVelocity[p]
		if armed and before then
			local current = flight.bones[p] or 0
			local added =
				math.min(Damage.bonesForImpact((v - before).Magnitude), GameConfig.MAX_BONES_PER_LIMB - current)
			if added > 0 then
				flight.bones[p] = current + added
				flight.totalBones += added
				p.Color = Damage.tint(p:GetAttribute("BaseColor") or p.Color, current + added)
			end
		end
		flight.prevVelocity[p] = v
	end
end

-- Cette méthode permet de compter une fois chaque caisse ou brique du couloir lorsqu'elle est projetée.
local function checkSmashed(flight: Flight)
	for _, p in flight.lane.breakables do
		if not flight.counted[p] and p.AssemblyLinearVelocity.Magnitude > GameConfig.SMASH_SPEED then
			flight.counted[p] = true
			flight.smashed += 1
		end
	end
end

-- Cette méthode permet de détruire le mannequin et de remettre le couloir à neuf lorsque le lancer est terminé.
local function clearLane(flight: Flight)
	flight.dummy:Destroy()
	CourseBuilder.resetObstacles(flight.lane)
end

-- Cette méthode permet de clore un vol (gains, record, résultat au client) lorsque le mannequin s'est arrêté, puis de
-- rendre le couloir prêt après RESULT_TIME.
local function finish(flight: Flight, elapsed: number)
	local player = flight.player
	flights[player] = nil
	local result = Economy.payout({
		distance = flight.distance,
		bones = flight.totalBones,
		smashed = flight.smashed,
		perfect = flight.perfect,
	}, (player:GetAttribute("ValueLevel") :: number?) or 1)
	PlayerData.addMoney(player, result.total)
	PlayerData.recordDistance(player, result.distance)
	player:SetAttribute("LaneState", "Result")
	remotes.LaunchResult:FireClient(player, result)
	if RunService:IsStudio() then
		print(
			string.format(
				"[Launch] distance=%d bones=%d smashed=%d payout=%d gauge=%.2f power=%d time=%.1f",
				result.distance,
				result.bones,
				result.smashed,
				result.total,
				flight.gauge,
				(player:GetAttribute("PowerLevel") :: number?) or 1,
				elapsed
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
	flight.distance = math.max(flight.distance, position.Z - flight.lane.muzzle.Z)

	local dummy = flight.dummy
	local distance = math.max(0, math.floor(flight.distance))
	if dummy:GetAttribute("Distance") ~= distance then
		dummy:SetAttribute("Distance", distance)
	end
	if dummy:GetAttribute("Bones") ~= flight.totalBones then
		dummy:SetAttribute("Bones", flight.totalBones)
	end
	if dummy:GetAttribute("Smashed") ~= flight.smashed then
		dummy:SetAttribute("Smashed", flight.smashed)
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
-- teste dans Studio sans simuler d'input.
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
		LaunchService.launch(player, value)
	end)
end

-- Cette méthode permet de brancher les remotes, le suivi des vols et le nettoyage au départ lorsque le serveur
-- démarre.
function LaunchService.init(createdRemotes: Remotes.Remotes)
	remotes = createdRemotes
	remotes.Launch.OnServerEvent:Connect(LaunchService.launch)
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
