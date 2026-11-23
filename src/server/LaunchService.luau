-- Lancers : l'avatar projette le mannequin depuis ses mains, le serveur suit le vol (distance, zone, os cassés par
-- membre, objets détruits sur la piste partagée, pièges des thèmes déclenchés), annonce chaque choc aux clients (effets) et calcule la
-- CHANCE qui pousse le tirage du mannequin de collection (pas d'argent ; × 2 par renaissance du lanceur). Toute la physique est simulée par le
-- serveur (propriétaire réseau nil) ; plusieurs vols coexistent (un par joueur, plus les mannequins de test lancés
-- dans Studio).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Damage = require(Shared.Damage)
local DisplayLag = require(Shared.DisplayLag)
local Economy = require(Shared.Economy)
local FlightArc = require(Shared.FlightArc)
local GameConfig = require(Shared.GameConfig)
local Gauge = require(Shared.Gauge)
local Rebirth = require(Shared.Rebirth)
local Remotes = require(Shared.Remotes)
local RevealPlan = require(Shared.RevealPlan)
local ThrowDummies = require(Shared.ThrowDummies)
local ThrowStart = require(Shared.ThrowStart)
local Traps = require(Shared.Traps)
local Zones = require(Shared.Zones)

local ObstacleRules = require(Shared.ObstacleRules)
local TrackPlan = require(Shared.TrackPlan)

local BaseService = require(script.Parent.BaseService)
local CourseBuilder = require(script.Parent.CourseBuilder)
local DummyFactory = require(script.Parent.DummyFactory)
local Obstacles = require(script.Parent.Obstacles)
local PlayerData = require(script.Parent.PlayerData)
local SlotService = require(script.Parent.SlotService)
local StoreService = require(script.Parent.StoreService)

type Slot = CourseBuilder.Slot

local SPIN = Vector3.new(5, 2, 2) -- rotation aléatoire maximale au départ (rad/s par axe)
local THUD_DV = 40 -- choc du torse sans os cassé qui mérite un « boum »
local THUD_COOLDOWN = 0.25
local CAUSE_RADIUS = 7 -- un os cassé près d'une pièce d'obstacle lui est attribué (studs)
local TRAP_CAUSE_WINDOW = 0.8 -- un os cassé juste après un piège (retombée de la presse, du trampoline) lui est attribué (s)

export type Impact = {
	kind: string, -- "Throw" | "Bone" | "Smash" | "Thud" | "Trap"
	position: Vector3,
	value: number?, -- os ajoutés, objets détruits, ou force du choc
	material: string?, -- "Crate" | "Brick" pour Smash ; piège (Shared.Traps.KINDS) pour Trap
	userId: number,
	at: number?, -- heure serveur du choc (#84 : chaque client le montre quand son mannequin affiché y arrive)
}

type Flight = {
	owner: Player?, -- nil pour un mannequin de test (DebugLaunchBots)
	key: any, -- clé dans `flights` : le joueur, ou un identifiant de mannequin de test
	slot: Slot,
	thrown: ThrowDummies.Dummy, -- mannequin à lancer équipé au départ : chance, os, portance, poussée
	rebirth: number, -- multiplicateur de CHANCE des renaissances du lanceur au départ (Shared.Rebirth.luck)
	boost: number, -- multiplicateur de CHANCE de la boutique Robux au départ (Shared.Store.luck)
	forward: Vector3, -- direction du lancer (poussée du réacteur)
	flat: Vector3, -- direction de la piste à plat (trajectoire, frein au sol)
	origin: Vector3, -- point de départ du mannequin
	arc: FlightArc.Plan, -- plafond, fin de la croisière, distance au premier contact (#113), comportement (#130)
	phase: FlightArc.Phase, -- montée, croisière, vol libre ou au sol
	apex: number, -- plus haut point du torse (trace Studio)
	landedAt: number?, -- distance au premier contact au sol (trace Studio : glissade)
	fall: number, -- chute la plus forte du torse depuis le dernier rebond (studs/s : rebond du caoutchouc)
	bounces: number, -- rebonds du caoutchouc (trace Studio)
	bounceUntil: number, -- temps de vol (s) jusqu'auquel le rebond en cours n'est pas freiné
	trapped: boolean, -- un piège l'a projeté : plus de plafond
	announce: any?, -- annonce du tirage (Legendary et plus), envoyée à tous quand le gagnant a vu sa révélation
	dummy: Model,
	torso: BasePart,
	parts: { BasePart },
	startTime: number,
	gauge: number,
	prevVelocity: { [BasePart]: Vector3 },
	bones: { [string]: number },
	totalBones: number,
	smashed: number,
	distance: number,
	prevPosition: Vector3,
	restTime: number,
	lastThud: number,
	worstImpact: { kind: string, dv: number, speed: number }?,
	impacts: { Impact },
	traps: { [number]: boolean }, -- pièges déjà déclenchés par ce vol (site de TrackPlan.TrapBox, toutes colonnes)
	trapMisses: { [number]: boolean }, -- pièges traversés hors phase (trace Studio, une fois par vol et par piège)
	lastTrap: { kind: string, at: number }?, -- dernier piège déclenché : cause des os cassés juste après
	clockSent: number, -- os.clock() du dernier échantillon FlightClock envoyé (#84)
	stallChecked: boolean, -- sortie de la zone de lancer déjà vérifiée (FlightArc.STALL_TIME, #215)
	reached: number, -- plus grande distance parcourue le long de la piste depuis le départ (studs, #215)
	lucky: boolean?, -- lancer chanceux consommé au départ : rendu avec le lancer (#215)
	tutorialBefore: number?, -- tutoriel du lanceur avant le départ : l'étape « Throw » est reprise si le vol est rendu (#221)
}

local LaunchService = {}

local remotes: Remotes.Remotes
local dummiesFolder: Folder
local flights: { [any]: Flight } = {}
local results: { [Player]: Flight } = {} -- vol dont le résultat et le tirage sont à l'écran
local gaugeStops: { [Player]: number } = {} -- os.clock() d'arrivée du GaugeStop, jusqu'au Launch
local rng = Random.new()
local botCount = 0

-- Cette méthode permet de donner le point de départ du mannequin (main de l'avatar au lâcher de l'animation de
-- lancer, au-dessus de la tête côté bras droit ; point de la place sur la bande si le personnage manque) lorsqu'un
-- lancer part.
local function throwOrigin(player: Player?, slot: Slot): Vector3
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- Repère horizontal de l'avatar (là où sa main lâche le décoratif), sinon celui de la piste (la direction du
	-- lancer est inclinée de LAUNCH_PITCH_DEG)
	-- (Shared.ThrowStart : même calcul chez le lanceur, qui affiche le départ dès le lâcher, #144)
	if root then
		return ThrowStart.origin(root.Position, root.CFrame.LookVector)
	end
	return ThrowStart.origin(slot.launchPoint + Vector3.new(0, 3, 0), slot.direction)
end

-- Cette méthode permet de lancer un mannequin neuf (le mannequin à lancer `thrownIndex` du catalogue, avec son modèle
-- et sa physique) depuis la main du lanceur (ou sa place) et de commencer à suivre son vol lorsqu'un joueur, ou un
-- test, lance ; `rebirth` (renaissances) et `boost` (boutique Robux) multiplient sa CHANCE, `luck` remplace celle du
-- mannequin (Rainbow Dummy : selon le meilleur possédé). Renvoie le mannequin, le point de départ et la vitesse.
local function startFlight(
	owner: Player?,
	key: any,
	slot: Slot,
	power: number,
	gauge: number,
	thrownIndex: number,
	rebirth: number,
	boost: number,
	luck: number?
): (Model, Vector3, number)
	local speed = ThrowStart.speed(power, gauge)
	local dir = slot.direction
	local origin = throwOrigin(owner, slot)
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	local flat = if flatDir.Magnitude > 1e-3 then flatDir.Unit else Vector3.zAxis
	local thrown = ThrowDummies.get(thrownIndex)
	if luck and luck ~= thrown.luck then
		thrown = table.clone(thrown)
		thrown.luck = luck
	end
	local arc = FlightArc.plan(speed * flatDir.Magnitude, speed * dir.Y, origin.Y, Workspace.Gravity, thrown)
	local dummy = DummyFactory.build(ThrowDummies.variant(thrownIndex) :: any, thrown.physics)
	-- Tête la première : l'axe vertical du mannequin suit la direction du lancer
	dummy:PivotTo(CFrame.fromMatrix(origin, Vector3.xAxis, dir))
	-- Départ du vol, lu par chaque client pour recalculer le plan (effets des comportements : Client.FlightFx, #138),
	-- posé avant la réplication ; `LaunchTime` : heure du lâcher (suivi commencé en retard), `Bounces` : rebonds
	-- réglés du caoutchouc
	dummy:SetAttribute("LaunchOrigin", origin)
	dummy:SetAttribute("LaunchTime", Workspace:GetServerTimeNow())
	dummy:SetAttribute("LaunchVelocity", dir * speed)
	dummy:SetAttribute("ThrownIndex", thrownIndex)
	dummy:SetAttribute("Bounces", 0)
	-- Lanceur : son client reconnaît le mannequin dès son arrivée et le masque derrière l'affichage anticipé (#144)
	if owner then
		dummy:SetAttribute("Owner", owner.UserId)
	end
	dummy.Parent = dummiesFolder

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
	dummy:SetAttribute("Luck", thrown.luck) -- bannière CHANCE : multiplicateur du mannequin lancé
	dummy:SetAttribute("Rebirth", rebirth) -- bannière CHANCE : multiplicateur des renaissances
	dummy:SetAttribute("Boost", boost) -- bannière CHANCE : multiplicateur de la boutique Robux
	-- CHANCE de départ déjà multipliée : la bannière ne montre pas « 1X » avant la première frame
	dummy:SetAttribute(
		"Chance",
		Economy.chance({ distance = 0, bones = 0, smashed = 0, luck = thrown.luck, rebirth = rebirth, boost = boost }).total
	)
	dummy:SetAttribute("Thrown", thrown.name)

	local torso = dummy.PrimaryPart :: BasePart
	flights[key] = {
		owner = owner,
		key = key,
		slot = slot,
		thrown = thrown,
		rebirth = rebirth,
		boost = boost,
		forward = dir,
		flat = flat,
		origin = origin,
		arc = arc,
		phase = FlightArc.startPhase(arc),
		apex = origin.Y,
		landedAt = nil,
		fall = 0,
		bounces = 0,
		bounceUntil = 0,
		trapped = false,
		dummy = dummy,
		torso = torso,
		parts = parts,
		startTime = os.clock(),
		gauge = gauge,
		prevVelocity = {},
		bones = {},
		totalBones = 0,
		smashed = 0,
		distance = 0,
		prevPosition = torso.Position,
		restTime = 0,
		lastThud = -math.huge,
		worstImpact = nil,
		impacts = {},
		traps = {},
		trapMisses = {},
		lastTrap = nil,
		clockSent = -math.huge,
		stallChecked = false,
		reached = 0,
	}
	return dummy, origin, speed
end

-- Cette méthode permet de donner la latence aller-retour du joueur (s) lorsque le serveur vérifie la valeur de sa
-- jauge ; 0 si elle n'est pas mesurable.
local function networkLag(player: Player): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and typeof(ping) == "number" then ping else 0
end

-- Cette méthode permet de retenir la valeur de jauge d'un lancer lorsque le serveur le reçoit : celle du client si
-- elle est compatible avec l'instant où la jauge s'est ouverte (Shared.Gauge.verify), sinon celle du serveur.
local function verifiedGauge(player: Player, claimed: number, openedAt: number, stopArrival: number?): number
	local elapsed = os.clock() - openedAt
	local lag = networkLag(player)
	-- Un GaugeStop arrivé avant l'ouverture est ignoré par Gauge.verify (repli)
	local stopAt = if stopArrival then stopArrival - openedAt else nil
	local value, accepted = Gauge.verify(claimed, elapsed, lag, stopAt)
	if RunService:IsStudio() then
		print(
			string.format(
				"[Launch] jauge %s : client=%.2f serveur=%.2f (%.2f s après ouverture, GaugeStop %s, latence %.3f s)",
				if accepted then "acceptée" else "refusée",
				claimed,
				value,
				elapsed,
				if stopAt then string.format("à %.2f s", stopAt) else "absent",
				lag
			)
		)
	end
	return value
end

-- Cette méthode permet de noter l'heure d'arrivée du clic qui arrête la jauge lorsque le joueur est figé sur la bande
-- avec la jauge ouverte ; une seule fois par lancer (les suivants sont ignorés jusqu'au Launch).
function LaunchService.gaugeStop(player: Player)
	local openedAt = SlotService.gaugeOpenedAt(player)
	if player:GetAttribute("LaneState") ~= "Ready" or player:GetAttribute("Action") ~= "Holding" or not openedAt then
		return
	end
	-- Un GaugeStop resté d'une jauge précédente (avant l'ouverture actuelle) est remplacé
	local previous = gaugeStops[player]
	if previous and previous >= openedAt then
		return
	end
	gaugeStops[player] = os.clock()
end

-- Cette méthode permet de tirer le mannequin d'un joueur lorsqu'il est figé sur la bande de lancer (ou que `force`
-- vient de DebugLaunch) ; `gauge` vient du client, bornée puis vérifiée ici (sauf DebugLaunch).
function LaunchService.launch(player: Player, gauge: any, force: boolean?)
	-- Cette méthode permet de prévenir le lanceur d'un refus (son décoratif est parti au lâcher, #144) lorsque le
	-- Launch du client ne lance rien.
	local function refuse()
		if not force then
			remotes.LaunchRefused:FireClient(player)
		end
	end
	if typeof(gauge) ~= "number" or gauge ~= gauge then
		refuse()
		return
	end
	gauge = math.clamp(gauge, 0, 1)
	-- Tout Launch consomme le GaugeStop noté, même refusé plus bas : le clic suivant en notera un nouveau
	local stopArrival = gaugeStops[player]
	gaugeStops[player] = nil
	if player:GetAttribute("LaneState") ~= "Ready" or not player:GetAttribute("DataReady") then
		refuse()
		return
	end
	local slot = SlotService.getSlot(player)
	if not slot then
		refuse()
		return
	end
	if not force then
		local openedAt = SlotService.gaugeOpenedAt(player)
		if player:GetAttribute("Action") ~= "Holding" or not openedAt then
			refuse()
			return
		end
		gauge = verifiedGauge(player, gauge, openedAt, stopArrival)
	end
	player:SetAttribute("LaneState", "Flying")
	player:SetAttribute("Action", nil)
	local tutorialBefore = (player:GetAttribute("Tutorial") :: number?) or 0
	PlayerData.tutorialStep(player, "Throw")

	local power = (player:GetAttribute("ThrowPower") :: number?) or GameConfig.START_POWER
	local owned, equipped =
		ThrowDummies.sanitize(player:GetAttribute("ThrowTier"), player:GetAttribute("ThrowEquipped"))
	local rebirth = Rebirth.luck(Rebirth.read(player:GetAttribute("Rebirths")))
	local boost, lucky = StoreService.launchLuck(player) -- consomme un lancer chanceux s'il en reste
	local luck = ThrowDummies.luckOf(equipped, owned)
	local dummy, origin, speed = startFlight(player, player, slot, power, gauge, equipped, rebirth, boost, luck)
	flights[player].lucky = lucky
	-- Pas de reprise avant le chargement : la sauvegarde lue pose elle-même le masque du tutoriel
	flights[player].tutorialBefore = if player:GetAttribute("DataReady") == true then tutorialBefore else nil
	-- Départ du vol pour le lanceur : il rejoue le plan en avance sur la copie répliquée (Client.LaunchGhost, #117)
	remotes.LaunchStarted:FireClient(player, dummy, {
		origin = origin,
		velocity = slot.direction * speed,
		thrown = equipped,
	})
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
		userId = if flight.owner then flight.owner.UserId else 0,
		at = Workspace:GetServerTimeNow(),
	})
end

-- Cette méthode permet de casser `bones` os sur les membres les plus proches de `contact` (un chacun, au plus
-- MAX_BONES_PER_LIMB par membre) lorsqu'un piège se déclenche ; renvoie les os réellement cassés.
local function breakNearest(flight: Flight, contact: Vector3, bones: number): number
	local limbs = {}
	for _, p in flight.parts do
		if (flight.bones[p.Name] or 0) < GameConfig.MAX_BONES_PER_LIMB then
			limbs[p.Name] = p.Position
		end
	end
	local broken = 0
	for _, name in Traps.nearestLimbs(limbs, contact, bones) do
		local p = flight.dummy:FindFirstChild(name) :: BasePart?
		if p then
			local count = (flight.bones[name] or 0) + 1
			flight.bones[name] = count
			flight.totalBones += 1
			broken += 1
			p.Color = Damage.tint(p:GetAttribute("BaseColor") or p.Color, count)
			p:SetAttribute("Bones", count)
			addImpact(flight, "Bone", p.Position, 1)
		end
	end
	return broken
end

-- Effet d'un piège : nouvelle vitesse (Shared.Traps.react, recalée comme référence pour ne pas compter de choc),
-- rotation du corps, os cassés, cause du crash et annonce aux clients.

-- Cette méthode permet de donner la phase du piège `box` à l'instant `now` pour la trace [Trap] (Studio) lorsqu'il
-- est traversé ; « - » pour un piège sans cycle.
local function phaseLabel(box: TrackPlan.TrapBox, now: number): string
	if not Traps.CYCLES[box.kind] then
		return "-"
	end
	return string.format("%.2f", Traps.phase(box.kind, now, Traps.phaseOffset(box.x, box.z)))
end

-- Cette méthode permet de déclencher le piège `box` (une fois par vol) lorsque le torse traverse sa boîte à l'instant
-- `now` (horloge du serveur, celle qui a décidé que le piège agit).
local function triggerTrap(flight: Flight, box: TrackPlan.TrapBox, position: Vector3, now: number)
	flight.traps[box.site] = true
	flight.lastTrap = { kind = box.kind, at = os.clock() }
	-- Le piège rend le vol libre : son rebond peut passer le plafond (#113)
	flight.trapped = true
	if flight.phase == "Rise" or flight.phase == "Cruise" then
		flight.phase = "Free"
	end
	local def = Traps.KINDS[box.kind]
	local before = flight.torso.AssemblyLinearVelocity
	local after = Traps.react(box.kind, before, Traps.push(box.kind, now, Traps.phaseOffset(box.x, box.z)))
	-- Rotation du corps entier autour du torse (chaque membre suit), pas de chaque membre sur lui-même
	local spin = Vector3.new(0, def.spin, 0)
	local center = flight.torso.Position
	for _, p in flight.parts do
		local v = after + spin:Cross(p.Position - center)
		p.AssemblyLinearVelocity = v
		p.AssemblyAngularVelocity = spin
		flight.prevVelocity[p] = v
	end
	local contact = Traps.contact(box.center, box.size, position)
	breakNearest(flight, contact, def.bones)
	local dv = (after - before).Magnitude
	if not flight.worstImpact or dv > flight.worstImpact.dv then
		-- Vitesse affichée : la plus forte (arrivée lente dans la lave : celle du rebond)
		flight.worstImpact = { kind = box.kind, dv = dv, speed = math.max(before.Magnitude, after.Magnitude) }
	end
	flight.restTime = 0
	addImpact(flight, "Trap", contact, dv, box.kind)
	if RunService:IsStudio() then
		print(
			string.format(
				"[Trap] %s colonne %d à %.0f m, phase %s : %.0f → %.0f studs/s",
				box.kind,
				box.column,
				box.z,
				phaseLabel(box, now),
				before.Magnitude,
				after.Magnitude
			)
		)
	end
end

-- Cette méthode permet de savoir si le piège `box` agit à l'instant `now` sur un torse allé de `previous` à `position`
-- pendant la frame lorsqu'il traverse sa boîte ; le rondin doit toucher le torse en un point du trajet (4 points,
-- ramenés dans la boîte ; rondin pris à `now` pour toute la frame, soit ≈ 0,5 stud d'écart au plus vite).
local function trapActs(box: TrackPlan.TrapBox, now: number, previous: Vector3, position: Vector3): boolean
	local offset = Traps.phaseOffset(box.x, box.z)
	if box.kind ~= "SwingLog" then
		return Traps.active(box.kind, now, offset)
	end
	local foot = Vector3.new(box.x, 0, box.z)
	for step = 0, 3 do
		local point = Traps.contact(box.center, box.size, previous:Lerp(position, step / 3))
		if Traps.active(box.kind, now, offset, point - foot) then
			return true
		end
	end
	return false
end

-- Cette méthode permet de déclencher les pièges dont le torse a traversé la boîte entre deux frames lorsqu'il bouge
-- (passage à grande vitesse compris : le trajet est testé, pas seulement la position) ; un piège hors de sa phase
-- active (presse levée, rondin loin du torse, diable rentré, aimant éteint : Shared.Traps.active) laisse passer.
local function checkTraps(flight: Flight, previous: Vector3, position: Vector3)
	if os.clock() - flight.startTime <= GameConfig.IMPACT_GRACE_TIME then
		return
	end
	local minZ, maxZ = math.min(previous.Z, position.Z), math.max(previous.Z, position.Z)
	for _, box in Obstacles.traps() do
		local half = box.size.Z / 2
		if
			not flight.traps[box.site]
			and box.z + half >= minZ
			and box.z - half <= maxZ
			and Traps.crosses(box.center, box.size, previous, position)
		then
			local now = Workspace:GetServerTimeNow()
			if trapActs(box, now, previous, position) then
				triggerTrap(flight, box, position, now)
			elseif RunService:IsStudio() and not flight.trapMisses[box.site] then
				-- Trace de vérification (Studio) : un passage hors phase, une fois par vol et par piège
				flight.trapMisses[box.site] = true
				print(
					string.format(
						"[Trap] %s colonne %d à %.0f m, phase %s : hors phase, rien",
						box.kind,
						box.column,
						box.z,
						phaseLabel(box, now)
					)
				)
			end
		end
	end
end

-- Cette méthode permet de trouver ce qui a cassé un os (piège, obstacle ou sol) lorsqu'un membre subit un choc
-- au point `position`.
local function classifyCause(flight: Flight, position: Vector3): string
	local trap = flight.lastTrap
	if trap and os.clock() - trap.at < TRAP_CAUSE_WINDOW then
		return trap.kind
	end
	local piece = Obstacles.nearest(position, CAUSE_RADIUS)
	return if piece then piece.kind else "Ground"
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
		local added = math.min(
			Damage.bonesForImpact(ThrowDummies.boneImpact(flight.thrown, dv)),
			GameConfig.MAX_BONES_PER_LIMB - current
		)
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

-- Cette méthode permet de compter une fois chaque pièce projetée pour le vol le plus proche (piste partagée) lorsque
-- Heartbeat tourne ; un choc « Smash » par vol, matériau et frame est annoncé avec le nombre d'objets.
local function checkSmashed(list: { Flight })
	local positions = {}
	for index, flight in list do
		positions[index] = flight.torso.Position
	end
	local byFlight: { [Flight]: { [string]: { count: number, position: Vector3 } } } = {}
	for _, piece in Obstacles.pieces() do
		local p = piece.part
		if
			piece.claimed
			or not p.Parent
			or p.Anchored
			or p.AssemblyLinearVelocity.Magnitude <= GameConfig.SMASH_SPEED
		then
			continue
		end
		local index = ObstacleRules.claimant(p.Position, positions)
		if not index then
			continue
		end
		piece.claimed = true
		local flight = list[index]
		flight.smashed += 1
		local materials = byFlight[flight] or {}
		byFlight[flight] = materials
		local entry = materials[piece.material]
		if entry then
			entry.count += 1
		else
			materials[piece.material] = { count = 1, position = p.Position }
		end
	end
	for flight, materials in byFlight do
		for material, entry in materials do
			addImpact(flight, "Smash", entry.position, entry.count, material)
		end
	end
end

-- Cette méthode permet de rendre la main au joueur (hub, ou bande si `again` : THROW AGAIN #76) et d'annoncer un tirage
-- rare lorsque son résultat est fini (GO BACK, THROW AGAIN, délai dépassé) ; sans effet si déjà clos.
local function closeResult(player: Player, flight: Flight, again: boolean?)
	if results[player] ~= flight then
		return
	end
	results[player] = nil
	if flight.announce and player.Parent then
		remotes.Announce:FireAllClients(flight.announce)
		flight.announce = nil
	end
	if
		player.Parent
		and SlotService.getSlot(player) == flight.slot
		and player:GetAttribute("LaneState") == "Result"
	then
		-- Remise en prise avant « Ready » : Action « Holding » déjà posée, SlotService ne le renvoie pas au hub. Refusée
		-- (tutoriel, mort, bande pleine) : retour au hub, comme GO BACK
		local held = again == true and SlotService.holdAgain(player)
		if again and RunService:IsStudio() then
			print(
				string.format("[Launch] ThrowAgain %s : %s", player.Name, if held then "en prise" else "repli GO BACK")
			)
		end
		player:SetAttribute("LaneState", "Ready")
	end
end

-- Cette méthode permet de clore un vol lorsque le mannequin s'est arrêté : CHANCE du lancer, tirage du mannequin
-- de collection (Server.BaseService), record, blessures et cause envoyés au client, qui joue le résultat puis le
-- tirage. Le lancer ne rapporte pas d'argent. Le mannequin lancé quitte la piste après RESULT_CLEAR_TIME.
local function finish(flight: Flight, elapsed: number)
	flights[flight.key] = nil
	local player = flight.owner
	local result: any = Economy.chance({
		distance = flight.distance,
		bones = flight.totalBones,
		smashed = flight.smashed,
		luck = flight.thrown.luck,
		rebirth = flight.rebirth,
		boost = flight.boost,
	})
	result.bones = flight.totalBones
	result.smashed = flight.smashed
	result.landing = flight.torso.Position
	if player then
		local best = (player:GetAttribute("BestDistance") :: number?) or 0
		result.record = result.distance > best and best > 0
		result.bonesByLimb = flight.bones
		result.injuries = Damage.describe(flight.bones)
		result.cause = if flight.worstImpact
			then Damage.cause(flight.worstImpact.kind, flight.worstImpact.speed)
			else nil
		result.prize = BaseService.award(player, result.total)
		PlayerData.recordDistance(player, result.distance)
		player:SetAttribute("LaneState", "Result")
		results[player] = flight
		remotes.LaunchResult:FireClient(player, result)
		-- Bandeau pour tous à partir de Legendary (#67), envoyé à la fin du résultat (closeResult) : personne ne gâche
		-- le tirage du gagnant dans le chat avant qu'il l'ait vu
		local prize = result.prize
		if prize and RevealPlan.announces(prize.rarity) then
			flight.announce = {
				userId = player.UserId,
				player = player.DisplayName,
				name = prize.name,
				rarity = prize.rarity,
				odds = prize.odds,
			}
		end
		-- Fin forcée sans GO BACK : plus tard pour une mise en scène plus longue (secret ≈ 30 s)
		task.delay(RevealPlan.resultTime(prize and prize.rarity), closeResult, player, flight)
	end
	if RunService:IsStudio() then
		print(
			string.format(
				"[Launch] %s dummy=%s rebirth=x%g distance=%d zone=%d bones=%d smashed=%d chance=%.2f prize=%s gauge=%.2f time=%.1f | %s"
					.. " | apex=%d landed=%s slide=%s planned=%d reach=%d bounces=%d",
				if player then player.Name else tostring(flight.key),
				flight.thrown.id,
				flight.rebirth,
				result.distance,
				result.zone,
				flight.totalBones,
				flight.smashed,
				result.total,
				if result.prize then result.prize.name .. " (1 in " .. result.prize.odds .. ")" else "-",
				flight.gauge,
				elapsed,
				tostring(result.cause),
				math.floor(flight.apex),
				if flight.landedAt then tostring(math.floor(flight.landedAt)) else "-",
				if flight.landedAt then tostring(math.floor(flight.distance - flight.landedAt)) else "-",
				math.floor(flight.origin.Z + flight.arc.range),
				math.floor(flight.origin.Z + flight.arc.reach),
				flight.bounces
			)
		)
	end
	task.delay(GameConfig.RESULT_CLEAR_TIME, function()
		flight.dummy:Destroy()
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
		Chance = Economy.chance({
			distance = flight.distance,
			bones = flight.totalBones,
			smashed = flight.smashed,
			luck = flight.thrown.luck,
			rebirth = flight.rebirth,
			boost = flight.boost,
		}).total,
	}
	for name, value in values do
		if dummy:GetAttribute(name) ~= value then
			dummy:SetAttribute(name, value)
		end
	end
end

-- Cette méthode permet d'appliquer le comportement en vol du mannequin lancé (portance du planeur, poussée du
-- réacteur, rebond du caoutchouc d'après la vitesse du torse `before` de la frame précédente, réglés par le plan du
-- vol : Shared.FlightArc) puis la trajectoire
-- (plafond, croisière, frein au sol : Shared.FlightArc ; `impact` : choc du torse cette frame) à toutes ses pièces
-- lorsque le vol avance d'une frame ; les vitesses de référence suivent (pas de choc).
local function applyBehavior(flight: Flight, elapsed: number, dt: number, before: Vector3?, impact: boolean)
	local velocity = flight.torso.AssemblyLinearVelocity
	-- Un piège vient d'agir : ni portance ni rebond ne remplacent sa poussée, et le frein attend (TRAP_COAST)
	local coasting = flight.lastTrap ~= nil and os.clock() - flight.lastTrap.at < FlightArc.TRAP_COAST
	local change = FlightArc.accel(flight.arc, velocity, flight.forward, elapsed, Workspace.Gravity, coasting, dt) * dt
	local armed = elapsed > GameConfig.IMPACT_GRACE_TIME
	-- Projeté par un piège : le caoutchouc rebondit librement (physique), sa poussée n'est pas reprise par le plan
	if before and armed and not coasting and not flight.trapped then
		local bounced = FlightArc.bounce(
			flight.arc,
			before,
			velocity,
			flight.forward,
			flight.fall,
			flight.bounces,
			flight.torso.Position.Y
		)
		if bounced then
			change += bounced - velocity
			flight.bounces += 1
			flight.dummy:SetAttribute("Bounces", flight.bounces)
			flight.bounceUntil = elapsed + FlightArc.bounceTime(bounced, Workspace.Gravity)
		end
	end
	-- Chute la plus forte depuis le dernier rebond : remise à zéro dès que le torse remonte
	local vy = (velocity + change).Y
	flight.fall = if vy < 0 then math.max(flight.fall, -vy) else 0
	local position = flight.torso.Position
	local phase, control = FlightArc.step(flight.arc, {
		phase = flight.phase,
		along = (position - flight.origin):Dot(flight.flat),
		height = position.Y,
		velocity = velocity + change,
		forward = flight.flat,
		armed = armed,
		impact = armed and impact,
		trapped = flight.trapped,
		coasting = coasting,
		bouncing = elapsed < flight.bounceUntil,
		dt = dt,
		gravity = Workspace.Gravity,
	})
	if phase == "Landed" and flight.phase ~= "Landed" then
		flight.landedAt = position.Z
	end
	flight.phase = phase
	change += control
	if change == Vector3.zero then
		return
	end
	for _, p in flight.parts do
		local v = p.AssemblyLinearVelocity + change
		p.AssemblyLinearVelocity = v
		flight.prevVelocity[p] = v
	end
end

-- Cette méthode permet d'envoyer à tous les clients l'heure serveur et la position du torse (`position`, celle qui
-- décide des pièges cette frame) lorsque le vol avance, DisplayLag.SAMPLE_RATE fois par seconde au plus (#84).
local function sendClock(flight: Flight, position: Vector3)
	local clock = os.clock()
	-- Tolérance de 5 ms : une frame sur trois à 60 Hz, pas une sur quatre au moindre écart
	if clock - flight.clockSent < 1 / DisplayLag.SAMPLE_RATE - 0.005 then
		return
	end
	flight.clockSent = clock
	remotes.FlightClock:FireAllClients(flight.torso, Workspace:GetServerTimeNow(), position)
end

-- Cette méthode permet de décrire les pièces proches du torse (hors mannequin) lorsque le vol est rendu au joueur
-- (trace Studio : ce qui a pu arrêter le mannequin, #215).
local function nearbyParts(flight: Flight): string
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { flight.dummy }
	local names = {}
	for _, part in Workspace:GetPartBoundsInRadius(flight.torso.Position, 6, params) do
		if #names >= 6 then
			break
		end
		table.insert(
			names,
			string.format("%s[%s,%s]", part:GetFullName(), part.CollisionGroup, tostring(part.CanCollide))
		)
	end
	return if #names > 0 then table.concat(names, " ") else "-"
end

-- Cette méthode permet de rendre le lancer au joueur, sans résultat ni tirage (lancer chanceux rendu, remise en prise
-- sur la bande quand c'est possible), lorsque son mannequin n'a pas quitté la zone de lancer (#215).
local function handBack(flight: Flight, along: number)
	flights[flight.key] = nil
	local torso = flight.torso
	if RunService:IsStudio() then
		print(
			string.format(
				"[Launch] vol rendu (calé dans la zone de lancer) : %s dummy=%s gauge=%.2f plus loin=%.1f phase=%s"
					.. " position=%s vitesse=%s ancré=%s près=%s",
				if flight.owner then flight.owner.Name else tostring(flight.key),
				flight.thrown.id,
				flight.gauge,
				along,
				flight.phase,
				tostring(torso.Position),
				tostring(torso.AssemblyLinearVelocity),
				tostring(torso.Anchored),
				nearbyParts(flight)
			)
		)
	end
	flight.dummy:Destroy()
	local player = flight.owner
	if not player or not player.Parent then
		return
	end
	if flight.lucky then
		StoreService.refundLuck(player)
	end
	-- Un lancer rendu n'a rien donné : le tutoriel reste à « Throw » (#221), avant la remise en prise qui le consulte
	if flight.tutorialBefore then
		PlayerData.tutorialRevokeThrow(player, flight.tutorialBefore)
	end
	-- Remise en prise comme THROW AGAIN (refusée : tutoriel, réapparu, bande pleine → hub, comme un vol perdu)
	local held = SlotService.holdAgain(player, "Flying")
	if RunService:IsStudio() then
		print(string.format("[Launch] vol rendu à %s : %s", player.Name, if held then "en prise" else "retour au hub"))
	end
	player:SetAttribute("LaneState", "Ready")
end

-- Cette méthode permet d'avancer le suivi d'un vol d'une frame lorsque Heartbeat tourne.
local function step(flight: Flight, dt: number)
	local elapsed = os.clock() - flight.startTime
	local torso = flight.torso
	if (flight.owner and not flight.owner.Parent) or not torso.Parent then
		flights[flight.key] = nil
		flight.dummy:Destroy()
		-- Mannequin perdu en vol : le joueur encore là reprend la main (et quitte la bande)
		if flight.owner and flight.owner.Parent then
			if flight.tutorialBefore then
				PlayerData.tutorialRevokeThrow(flight.owner, flight.tutorialBefore) -- aucun mannequin gagné (#221)
			end
			flight.owner:SetAttribute("LaneState", "Ready")
		end
		return
	end
	local position = torso.Position
	local previous = flight.prevPosition
	local before = flight.prevVelocity[torso] -- vitesse du torse à la frame précédente (rebond du caoutchouc)
	-- Choc du torse cette frame (avant qu'un piège ne remplace sa vitesse), gravité de la frame déduite (pas de faux
	-- choc sur un à-coup du serveur) : premier contact
	local expected = if before then before - Vector3.new(0, Workspace.Gravity * dt, 0) else nil
	local impact = expected ~= nil and (torso.AssemblyLinearVelocity - expected).Magnitude > FlightArc.IMPACT_DV
	flight.prevPosition = position
	flight.apex = math.max(flight.apex, position.Y)
	checkBones(flight, elapsed)
	checkTraps(flight, previous, position)
	sendClock(flight, position)
	flight.distance = math.max(flight.distance, position.Z)
	flight.reached = math.max(flight.reached, (position - flight.origin):Dot(flight.flat))
	-- Garde-fou (#215) : un mannequin resté dans la zone de lancer (plus loin atteint, pas la position du moment : un
	-- rebond en arrière ne compte pas) est rendu au joueur, pas compté comme un lancer raté
	if not flight.stallChecked and elapsed >= FlightArc.STALL_TIME then
		flight.stallChecked = true
		if FlightArc.stalled(flight.arc, flight.reached) then
			-- Chocs de cette frame (os, objets projetés) annoncés avant le retrait du mannequin
			if #flight.impacts > 0 then
				remotes.Impact:FireAllClients(flight.impacts)
				flight.impacts = {}
			end
			handBack(flight, flight.reached)
			return
		end
	end
	applyBehavior(flight, elapsed, dt, before, impact)
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

-- Cette méthode permet de lancer `count` mannequins de test depuis les places libres (jauge pleine, DebugBotsPower et
-- DebugBotsDummy du joueur s'ils sont posés) lorsque l'on mesure des vols dans Studio sans toucher à sa sauvegarde.
local function launchBots(player: Player, count: number)
	local botPower = player:GetAttribute("DebugBotsPower")
	local power = if typeof(botPower) == "number"
			and botPower > 0
			and botPower < math.huge
		then botPower
		else (player:GetAttribute("ThrowPower") :: number?) or GameConfig.START_POWER
	local botDummy = player:GetAttribute("DebugBotsDummy")
	local thrownIndex = if ThrowDummies.isIndex(botDummy) then botDummy :: number else 1
	for i, slot in SlotService.freeSlots() do
		if i > count then
			break
		end
		botCount += 1
		startFlight(nil, "Bot" .. botCount, slot, power, 1, thrownIndex, 1, 1)
	end
end

-- Cette méthode permet de lancer par attribut lorsque l'on teste dans Studio sans input : DebugLaunch (0-1) lance le
-- mannequin du joueur depuis sa place, DebugLaunchBots (n) lance n mannequins de test depuis les places libres
-- (DebugBotsPower, DebugBotsDummy : puissance et mannequin à lancer des tests).
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
	player:GetAttributeChangedSignal("DebugLaunchBots"):Connect(function()
		local value = player:GetAttribute("DebugLaunchBots")
		if typeof(value) ~= "number" then
			return
		end
		player:SetAttribute("DebugLaunchBots", nil)
		launchBots(player, value)
	end)
end

-- Cette méthode permet de brancher les remotes, le suivi des vols et le nettoyage au départ lorsque le serveur
-- démarre.
function LaunchService.init(createdRemotes: Remotes.Remotes, dummies: Folder)
	remotes = createdRemotes
	dummiesFolder = dummies
	remotes.GaugeStop.OnServerEvent:Connect(LaunchService.gaugeStop)
	remotes.Launch.OnServerEvent:Connect(function(player, gauge)
		LaunchService.launch(player, gauge)
	end)
	remotes.ResultDone.OnServerEvent:Connect(function(player)
		local flight = results[player]
		if flight then
			closeResult(player, flight)
		end
	end)
	-- THROW AGAIN : ignoré hors d'un résultat ouvert (double clic, clic pendant le vol, résultat déjà clos)
	remotes.ThrowAgain.OnServerEvent:Connect(function(player)
		local flight = results[player]
		if flight then
			closeResult(player, flight, true)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local list = {}
		for _, flight in flights do
			table.insert(list, flight)
		end
		if #list == 0 then
			return
		end
		checkSmashed(list)
		for _, flight in list do
			step(flight, dt)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		results[player] = nil
		gaugeStops[player] = nil
		local flight = flights[player]
		if flight then
			flights[player] = nil
			flight.dummy:Destroy()
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
