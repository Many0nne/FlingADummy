-- Animation des pièces mobiles des pièges (pales du ventilateur, rondin, presse, diable, vague…) : chaque client fait
-- bouger lui-même les modèles étiquetés Traps.MOTION_TAG par Server.TrapProps (mouvement : Shared.Traps.motion), et
-- seulement ceux proches de sa caméra. Rien ne se réplique à chaque image. Horloge et phase sont celles que le serveur
-- prend pour déclencher le piège (Shared.Traps.active), décalées du retard d'affichage des mannequins (#84,
-- Shared.DisplayLag : mesuré sur le mannequin en vol le plus proche de la caméra, échantillons FlightClock du serveur) :
-- la pièce frappe quand le mannequin affiché la touche. Les pièces nommées
-- Traps.POWER_PART (plaque de l'aimant, bouche du geyser, faisceaux laser) ne s'allument que pendant la phase active ;
-- celles qui portent l'attribut Traps.POWER_FADE disparaissent éteintes.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DisplayLag = require(Shared:WaitForChild("DisplayLag"))
local Traps = require(Shared:WaitForChild("Traps"))

local TrapMotion = {}

type Mover = {
	model: Model,
	home: CFrame,
	motion: string,
	axis: Vector3,
	amplitude: number,
	period: number,
	offset: number, -- décalage de phase : deux pièges voisins ne battent pas en même temps
	kind: string?, -- piège (Shared.Traps.KINDS) de la pièce mobile
	power: { BasePart }, -- pièces allumées pendant la phase active
	lit: boolean?, -- état affiché des pièces `power`
	parked: boolean?, -- remise au repos depuis qu'elle est hors de portée de la caméra
}

local movers: { [Model]: Mover } = {}
-- Trajectoires récentes des torses en vol (heure serveur, position), et os.clock() du dernier échantillon reçu
local tracks: { [BasePart]: { track: DisplayLag.Track, heard: number } } = {}
local clock = DisplayLag.clock()
local studio = RunService:IsStudio()

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
	local power = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == Traps.POWER_PART then
			table.insert(power, part)
		end
	end
	local phase = model:GetAttribute("Phase")
	local kind = model:GetAttribute("Trap")
	movers[model] = {
		model = model,
		home = home,
		motion = tostring(model:GetAttribute("Motion")),
		axis = axis,
		amplitude = tonumber(model:GetAttribute("Amplitude")) or 0,
		period = math.max(tonumber(model:GetAttribute("Period")) or 1, 0.05),
		offset = if type(phase) == "number" then phase else Traps.phaseOffset(home.Position.X, home.Position.Z),
		kind = if type(kind) == "string" then kind else nil,
		power = power,
		lit = nil,
	}
end

-- Cette méthode permet d'allumer ou d'éteindre les pièces `power` d'une pièce mobile (néon et étincelles, ou métal
-- sombre) lorsque son piège entre dans sa phase active ou en sort.
local function setPower(mover: Mover, lit: boolean)
	if mover.lit == lit then
		return
	end
	mover.lit = lit
	for _, part in mover.power do
		part.Material = if lit then Enum.Material.Neon else Enum.Material.Metal -- éteinte : état construit par le serveur
		local on = part:GetAttribute("PowerColor")
		part.Color = if lit and typeof(on) == "Color3" then on else Traps.POWER_OFF
		-- Faisceau, panache : invisibles éteints (Traps.POWER_FADE)
		local fade = part:GetAttribute(Traps.POWER_FADE)
		if type(fade) == "number" then
			part.Transparency = if lit then fade else 1
		end
		for _, emitter in part:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = lit
			end
		end
	end
end

-- Cette méthode permet de retenir un échantillon (heure serveur, position) du torse `torso` lorsqu'il arrive du
-- serveur (remote FlightClock).
local function hear(torso: any, time: any, position: any)
	if typeof(torso) ~= "Instance" or not torso:IsA("BasePart") or type(time) ~= "number" then
		return
	end
	if typeof(position) ~= "Vector3" then
		return
	end
	local entry = tracks[torso]
	if not entry then
		entry = { track = DisplayLag.track(), heard = 0 }
		tracks[torso] = entry
	end
	entry.heard = os.clock()
	DisplayLag.push(entry.track, time, position)
end

-- Cette méthode permet de mesurer le retard d'affichage sur le torse en vol le plus proche de la caméra (`eye`) à
-- l'heure serveur `now` lorsque le rendu tourne ; nil sans torse mesurable. Les vols finis sont oubliés.
local function measure(eye: Vector3, now: number): number?
	local measured, nearest = nil, math.huge
	for torso, entry in tracks do
		if not torso.Parent or os.clock() - entry.heard > DisplayLag.KEEP then
			tracks[torso] = nil
			continue
		end
		local position = torso.Position
		local distance = (position - eye).Magnitude
		if distance < nearest then
			local lag = DisplayLag.measure(entry.track, now, position)
			if lag then
				measured, nearest = lag, distance
			end
		end
	end
	return measured
end

-- Cette méthode permet d'avancer d'une image les pièces mobiles proches de la caméra lorsque le rendu tourne.
local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	-- Horloge partagée, décalée du retard d'affichage : la presse écrase quand le mannequin affiché passe dessous
	local serverNow = Workspace:GetServerTimeNow()
	local lag = DisplayLag.step(clock, measure(eye, serverNow), dt)
	local now = DisplayLag.now(clock, serverNow)
	if studio then
		-- Mesures en Studio (#84) : retard appliqué, lu par une sonde
		local player = Players.LocalPlayer
		local shown = player:GetAttribute("TrapDelay")
		if type(shown) ~= "number" or math.abs(shown - lag) >= 0.001 then
			player:SetAttribute("TrapDelay", lag)
		end
	end
	for model, mover in movers do
		if not model.Parent or not model.PrimaryPart then
			continue
		end
		-- Plaques allumées : suivies même de loin (le néon se voit de loin, et ne change que deux fois par cycle)
		if mover.kind and #mover.power > 0 then
			setPower(mover, Traps.active(mover.kind, now, mover.offset))
		end
		if (mover.home.Position - eye).Magnitude > Traps.MOTION_RANGE then
			-- Hors de portée : pièce remise une fois au repos (fantôme rentré sous terre), pas figée en plein mouvement
			if not mover.parked then
				model:PivotTo(mover.home)
				mover.parked = true
			end
			continue
		end
		mover.parked = false
		local t = now + mover.offset * mover.period
		model:PivotTo(mover.home * Traps.motion(mover.motion, t, mover.axis, mover.amplitude, mover.period))
	end
end

-- Cette méthode permet de brancher l'animation des pièges et la mesure du retard d'affichage (échantillons de
-- `flightClock`) lorsque le client démarre.
function TrapMotion.init(flightClock: UnreliableRemoteEvent)
	flightClock.OnClientEvent:Connect(hear)
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
