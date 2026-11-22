-- Départ du vol du joueur local (#117, #144) : le mannequin lancé est simulé par le serveur, et sa copie répliquée reste
-- figée à son apparition le temps que le tampon d'interpolation du moteur se remplisse (200 à 290 ms), puis s'affiche
-- en retard. Le lanceur voit à sa place une copie locale de ce mannequin (mêmes pièces, même pose, chaque image),
-- décalée sur la trajectoire du plan (Shared.FlightGhost) : elle quitte la main sans s'arrêter, puis son avance se
-- résorbe et la copie répliquée, masquée pour lui seul pendant ce temps, reprend la main (0,9 à 1,2 s mesurées). Au
-- retour, la copie locale est masquée et ses effets coupés, puis retirée après la vie de ses particules. Les autres
-- joueurs et le résultat du serveur ne changent pas.
--
-- Lâcher anticipé (#144) : sans attendre la réponse du serveur (un aller-retour), le décoratif lâché part dès le
-- marqueur Release sur le plan calculé par le client (Shared.ThrowStart : main, puissance, jauge, mannequin équipé),
-- en passant en TRANSITION de sa pose et de son échelle en main (0,6) à celles du vol. Le mannequin du serveur, reconnu
-- dès son arrivée (attribut `Owner`), est masqué ; son départ recale le plan affiché (Shared.FlightGhost.rebase), puis la
-- copie locale de ses pièces prend le relais du décoratif. Sans départ du serveur dans la latence plus REFUSE_MARGIN
-- (couloir pas en vol : lancer refusé), le décoratif s'efface en VANISH.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FlightGhost = require(Shared:WaitForChild("FlightGhost"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))
local ThrowStart = require(Shared:WaitForChild("ThrowStart"))

local BIND_NAME = "LaunchGhost"
local FADE_OUT = 2 -- copie locale gardée, masquée, après le retour (s) : ses particules et sa traînée s'éteignent
local REFUSE_MARGIN = 0.3 -- sans départ du serveur passé la latence + cette marge (s), couloir pas en vol : refusé
local HANDOFF_TIME = 2 -- sans départ du serveur passé ce temps (s), le décoratif s'efface quoi qu'il arrive
local VANISH = 0.15 -- effacement du décoratif d'un lancer refusé (s)
-- Effets de la copie répliquée coupés pendant l'affichage anticipé (la copie locale porte les siens) ; les surfaces
-- et panneaux (cibles du torse en blocs, DummyShape.addTarget) restent visibles sur une pièce masquée
local EFFECTS = {
	SurfaceGui = true,
	BillboardGui = true,
	Highlight = true,
	ParticleEmitter = true,
	Trail = true,
	Beam = true,
	Fire = true,
	Smoke = true,
	Sparkles = true,
	PointLight = true,
	SpotLight = true,
	SurfaceLight = true,
}

-- Départ d'un vol (calculé par le client au lâcher, ou envoyé par le serveur)
type Launch = { origin: Vector3, velocity: Vector3, thrown: number }
type Pair = { source: BasePart, copy: BasePart }
type Active = {
	model: Model?, -- copie répliquée affichée à travers la copie locale (nil avant l'arrivée du départ du serveur)
	torso: BasePart?,
	visual: Model?, -- décoratif lâché (#144), affiché jusqu'au relais par la copie locale
	from: CFrame, -- repère du décoratif au lâcher
	grow: number, -- échelle à atteindre par le décoratif (vol / main)
	scaled: number, -- échelle courante du décoratif
	flight: CFrame, -- orientation du mannequin du serveur au départ (tête la première, sans position)
	releasedAt: number, -- os.clock() du lâcher
	deadline: number?, -- os.clock() au-delà duquel, sans départ du serveur, le lancer est tenu pour refusé
	refused: boolean,
	copy: Model?,
	pairs: { Pair },
	hidden: { [Instance]: number }, -- LocalTransparencyModifier d'origine des pièces et décalcomanies masquées
	effects: { [Instance]: boolean }, -- Enabled d'origine des effets coupés
	path: FlightGhost.Path,
	state: FlightGhost.State,
	shown: Vector3?, -- position affichée du torse (copie locale ou décoratif) à l'image en cours
	offset: Vector3, -- décalage de la copie locale sur la copie répliquée à l'image en cours
	velocity: Vector3?, -- vitesse affichée du torse à l'image en cours
	speed: number?, -- vitesse réelle du vol (cadrage de la caméra) tant que la copie répliquée n'est pas suivie
	previous: Vector3?, -- position de la copie répliquée à l'image précédente
	added: RBXScriptConnection?, -- pièces et effets arrivés après le départ
}

local LaunchGhost = {}

-- Écoutes posées par Client.FlightFx : effets du vol portés par le décoratif dès le lâcher, puis repris par le
-- mannequin du serveur au relais (sans les rallumer)
LaunchGhost.onAnticipate = nil :: ((visual: Model, origin: Vector3, velocity: Vector3, thrown: number) -> ())?
LaunchGhost.onSwap = nil :: ((visual: Model, model: Model) -> ())?

local player = Players.LocalPlayer
local active: Active? = nil
local session = 0 -- incrémenté à chaque départ ou arrêt : un départ qui attendait son torse s'efface

-- Cette méthode permet de masquer tout de suite un modèle du client (pièces, effets coupés) et de le retirer après la
-- vie de ses particules lorsque le vol ne l'affiche plus.
local function retire(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = 1
		elseif EFFECTS[descendant.ClassName] then
			(descendant :: any).Enabled = false
		end
	end
	Debris:AddItem(model, FADE_OUT)
end

-- Cette méthode permet d'effacer en VANISH s le décoratif d'un lancer refusé (pièces de plus en plus transparentes,
-- effets coupés), puis de le retirer.
local function vanish(model: Model)
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			parts[descendant] = (descendant :: any).Transparency
		elseif EFFECTS[descendant.ClassName] then
			(descendant :: any).Enabled = false
		end
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - start) / VANISH, 0, 1)
		for instance, transparency in parts do
			(instance :: any).Transparency = transparency + (1 - transparency) * k
		end
		if k >= 1 or not model.Parent then
			connection:Disconnect()
			Debris:AddItem(model, FADE_OUT)
		end
	end)
end

-- Cette méthode permet de rendre la main à la copie répliquée (copie locale retirée, pièces et effets rendus) lorsque
-- l'avance est résorbée, que le vol disparaît, que le lancer est refusé ou qu'un autre lancer part.
function LaunchGhost.stop()
	session += 1
	local current = active
	if not current then
		return
	end
	active = nil
	RunService:UnbindFromRenderStep(BIND_NAME)
	if current.added then
		current.added:Disconnect()
	end
	-- Copie masquée tout de suite, retirée plus tard : les particules déjà émises et la traînée finissent leur vie
	if current.copy then
		retire(current.copy)
	end
	local visual = current.visual
	if visual then
		if current.refused then
			vanish(visual)
		else
			retire(visual)
		end
	end
	-- Seules les valeurs encore à celles posées ici sont rendues (un autre système a pu en changer entre-temps)
	for instance, value in current.hidden do
		if instance.Parent and (instance :: any).LocalTransparencyModifier == 1 then
			(instance :: any).LocalTransparencyModifier = value
		end
	end
	for instance, enabled in current.effects do
		if instance.Parent and (instance :: any).Enabled == false then
			(instance :: any).Enabled = enabled
		end
	end
end

-- Cette méthode permet d'effacer le décoratif d'un lancer anticipé lorsque le serveur ne l'a pas lancé (geste fini, le
-- couloir n'est pas en vol) ; sans effet une fois le départ du serveur arrivé.
function LaunchGhost.cancel()
	local current = active
	if current and current.visual and not current.model then
		current.refused = true
		LaunchGhost.stop()
	end
end

-- Cette méthode permet de faire une copie locale d'une pièce du mannequin répliqué (ancrée, sans soudure ni
-- contrainte, sans collision ni étiquette) lorsque l'affichage anticipé démarre.
local function copyPart(source: BasePart): BasePart
	local copy = source:Clone()
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("Constraint") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end
	-- Les pièces animées par Client.DummyFx bougent déjà sur l'original : la copie suit, sans animation propre
	for _, tag in copy:GetTags() do
		copy:RemoveTag(tag)
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.LocalTransparencyModifier = 0
	return copy
end

-- Cette méthode permet de masquer pour le joueur local un élément de la copie répliquée (pièce copiée, décalcomanie,
-- effet) lorsque la copie locale ou le décoratif la remplace à l'écran.
local function hide(model: Model, current: Active, instance: Instance)
	-- Pièces : les enfants directs, celles que la copie locale reprend (Shared.DummyShape n'en imbrique pas)
	local copied = instance:IsA("BasePart") and instance.Parent == model
	if copied or instance:IsA("Decal") then
		current.hidden[instance] = (instance :: any).LocalTransparencyModifier;
		(instance :: any).LocalTransparencyModifier = 1
	elseif EFFECTS[instance.ClassName] then
		current.effects[instance] = (instance :: any).Enabled;
		(instance :: any).Enabled = false
	end
end

-- Cette méthode permet d'ajouter à la copie locale une pièce du mannequin répliqué (enfant direct) lorsque la copie
-- locale prend le relais ou qu'elle arrive après.
local function mirror(current: Active, source: Instance)
	local copy = current.copy
	if copy and source:IsA("BasePart") then
		local part = copyPart(source)
		part.Parent = copy
		table.insert(current.pairs, { source = source, copy = part })
	end
end

-- Cette méthode permet de lire un départ de vol (point, vitesse, mannequin lancé) lorsque le serveur l'annonce ; nil
-- s'il est illisible.
local function readLaunch(launch: any): Launch?
	if typeof(launch) ~= "table" or typeof(launch.origin) ~= "Vector3" or typeof(launch.velocity) ~= "Vector3" then
		return nil
	end
	return {
		origin = launch.origin,
		velocity = launch.velocity,
		thrown = if ThrowDummies.isIndex(launch.thrown) then launch.thrown else 1,
	}
end

-- Cette méthode permet de donner la trajectoire prévue d'un départ lorsque l'affichage anticipé démarre ou se recale.
local function pathOf(launch: Launch): FlightGhost.Path
	return FlightGhost.path(launch.origin, launch.velocity, Workspace.Gravity, ThrowDummies.get(launch.thrown))
end

-- Cette méthode permet de masquer le mannequin du serveur derrière ce que voit le lanceur (pièces arrivées après
-- comprises, copiées si la copie locale existe) et de retenir son torse lorsque son départ arrive.
local function attach(current: Active, model: Model)
	current.model = model
	for _, descendant in model:GetDescendants() do
		hide(model, current, descendant)
	end
	-- Arrivé après le départ (réplication en plusieurs paquets) : copié s'il s'agit d'une pièce, masqué dans tous les cas
	current.added = model.DescendantAdded:Connect(function(descendant)
		if descendant.Parent == model then
			mirror(current, descendant)
		end
		hide(model, current, descendant)
	end)
	local torso = model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		current.torso = torso
		return
	end
	task.spawn(function()
		local found = model:WaitForChild("Torso", 2) -- même attente que Client.FlightCamera
		if active == current and found and found:IsA("BasePart") then
			current.torso = found
		end
	end)
end

-- Cette méthode permet de construire la copie locale des pièces du mannequin du serveur lorsque elle prend la place
-- du décoratif lâché, ou dès le départ d'un lancer sans lâcher anticipé.
local function buildCopy(current: Active, model: Model)
	local copy = Instance.new("Model")
	copy.Name = "LaunchGhost"
	current.copy = copy
	for _, child in model:GetChildren() do
		mirror(current, child)
	end
	copy.Parent = Workspace
end

-- Cette méthode permet de placer la copie locale d'une image de `dt` s (décalée sur la copie répliquée) lorsque elle
-- porte l'affichage anticipé, et de rendre la main une fois l'avance résorbée.
local function follow(current: Active, torso: BasePart, dt: number)
	local state, path = current.state, current.path
	local offset = FlightGhost.advance(path, state, torso.Position, dt)
	if state.done then
		if RunService:IsStudio() then
			-- Trace de vérification : instant du retour à la copie répliquée, et s'il a été forcé (choc, fin du plan)
			print(
				string.format(
					"[LaunchGhost] main rendue à %.2f s (%s)",
					state.elapsed,
					if state.fadeFrom == Vector3.zero then "avance résorbée" else "résorption forcée"
				)
			)
		end
		LaunchGhost.stop()
		return
	end
	for _, pair in current.pairs do
		local source, part = pair.source, pair.copy
		if not source.Parent then
			part.LocalTransparencyModifier = 1 -- pièce retirée par le serveur
			continue
		end
		part.CFrame = source.CFrame + offset
		-- Os cassés teintés, pièces rendues transparentes par le serveur pendant l'affichage anticipé
		part.Color = source.Color
		part.Transparency = source.Transparency
	end
	-- Vitesse de la copie répliquée telle qu'affichée (en retard), pas sa vitesse répliquée du moment
	local position = torso.Position
	local replicated = if current.previous and dt > 0
		then (position - current.previous) / dt
		else torso.AssemblyLinearVelocity
	current.previous = position
	current.offset = offset
	current.shown = position + offset
	current.velocity = FlightGhost.velocity(path, state, replicated)
	current.speed = nil
end

-- Cette méthode permet de passer l'affichage du décoratif lâché à la copie locale du mannequin du serveur lorsque son
-- torse est arrivé et que le décoratif a fini de passer de la main au vol.
local function swap(current: Active, model: Model, torso: BasePart)
	local visual = current.visual :: Model
	buildCopy(current, model)
	current.visual = nil
	retire(visual)
	if LaunchGhost.onSwap then
		LaunchGhost.onSwap(visual, model)
	end
	follow(current, torso, 0) -- copie placée dès cette image
end

-- Cette méthode permet d'avancer d'une image de `dt` s le décoratif lâché (plan prévu, puis celui du serveur : point,
-- orientation et échelle passent de la main au vol en TRANSITION) lorsque le lanceur vient de lâcher.
local function anticipate(current: Active, visual: Model, dt: number)
	local state, path = current.state, current.path
	local position = FlightGhost.ahead(path, state, dt)
	local flying = FlightGhost.flying(state)
	local k = math.clamp(flying / FlightGhost.TRANSITION, 0, 1)
	local eased = k * k * (3 - 2 * k)
	local scale = 1 + (current.grow - 1) * eased
	if math.abs(scale - current.scaled) > 1e-4 then
		visual:ScaleTo(scale)
		current.scaled = scale
	end
	visual:PivotTo(CFrame.new(position) * current.from.Rotation:Lerp(current.flight, eased))
	current.shown = position
	current.velocity = if flying > 0 then FlightGhost.velocity(path, state, Vector3.zero) else Vector3.zero
	local _, planned = FlightGhost.sample(path, flying)
	current.speed = planned.Magnitude
	local model, torso = current.model, current.torso
	if model and torso and torso.Parent and k >= 1 then
		swap(current, model, torso)
		return
	end
	-- Pas de départ du serveur : lancer refusé (couloir pas en vol), ou réponse perdue
	local now = os.clock()
	local deadline = current.deadline
	if not model and deadline and now > deadline then
		if player:GetAttribute("LaneState") ~= "Flying" or now - current.releasedAt > HANDOFF_TIME then
			if RunService:IsStudio() then
				print(
					string.format("[LaunchGhost] lâcher anticipé sans départ du serveur à %.2f s : effacé", flying)
				)
			end
			current.refused = true
			LaunchGhost.stop()
		end
	end
end

-- Cette méthode permet de brancher l'avance d'image de l'affichage du vol (décoratif, puis copie locale) lorsque il
-- démarre ; avant la caméra (Client.FlightCamera, Camera + 1), qui cadre la position affichée de cette image.
local function bind(current: Active)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 1, function(dt)
		if active ~= current then
			return
		end
		local visual = current.visual
		if visual then
			if not visual.Parent then
				LaunchGhost.stop()
				return
			end
			anticipate(current, visual, dt)
			return
		end
		local torso = current.torso
		if not torso or not torso.Parent then
			LaunchGhost.stop()
			return
		end
		follow(current, torso, dt)
	end)
end

-- Cette méthode permet de lire la latence aller-retour du joueur local (s) lorsque l'on dose l'avance du départ
-- anticipé ; 0 si elle n'est pas mesurable.
local function ping(): number
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and typeof(value) == "number" then math.max(value, 0) else 0
end

-- Cette méthode permet de faire partir le décoratif lâché (`visual`, construit à l'échelle `scale`) sur le plan prévu
-- par le client lorsque le geste atteint le marqueur Release (jauge arrêtée à `gauge`) ; faux si le départ ne peut pas
-- être calculé (le décoratif reste alors figé à la main jusqu'au départ du serveur).
function LaunchGhost.anticipate(visual: Model, scale: number, gauge: number): boolean
	LaunchGhost.stop()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not visual.PrimaryPart or scale <= 0 then
		return false
	end
	local power = player:GetAttribute("ThrowPower")
	local _, thrown = ThrowDummies.sanitize(player:GetAttribute("ThrowTier"), player:GetAttribute("ThrowEquipped"))
	local launch: Launch = {
		origin = ThrowStart.origin(root.Position, root.CFrame.LookVector),
		velocity = ThrowStart.DIRECTION
			* ThrowStart.speed(if typeof(power) == "number" then power else GameConfig.START_POWER, gauge),
		thrown = thrown,
	}
	local from = visual:GetPivot()
	local latency = ping()
	local hold = FlightGhost.hold(latency)
	local current: Active = {
		model = nil,
		torso = nil,
		visual = visual,
		from = from,
		grow = 1 / scale,
		scaled = visual:GetScale(),
		flight = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, launch.velocity.Unit),
		releasedAt = os.clock(),
		deadline = os.clock() + latency + REFUSE_MARGIN,
		refused = false,
		copy = nil,
		pairs = {},
		hidden = {},
		effects = {},
		path = pathOf(launch),
		state = FlightGhost.new(hold, from.Position - launch.origin),
		shown = from.Position,
		offset = Vector3.zero,
		velocity = Vector3.zero,
		speed = nil,
		previous = nil,
		added = nil,
	}
	active = current
	bind(current)
	if LaunchGhost.onAnticipate then
		LaunchGhost.onAnticipate(visual, launch.origin, launch.velocity, thrown)
	end
	if RunService:IsStudio() then
		print(
			string.format(
				"[LaunchGhost] lâcher anticipé : latence %.3f s, maintien %.2f s, départ à %.2f studs de la main",
				latency,
				hold,
				(from.Position - launch.origin).Magnitude
			)
		)
	end
	return true
end

-- Cette méthode permet de suivre le vol du joueur local lorsque le serveur annonce son lancer (`launch` : point de
-- départ, vitesse, mannequin lancé) : recalage du décoratif parti au lâcher, ou départ anticipé sur le plan du serveur
-- (lancer de test, DebugLaunch) ; sans effet si le départ est illisible.
function LaunchGhost.start(model: Model, launch: any)
	local current = active
	if current and current.model == model then
		return -- déjà reconnu à son arrivée
	end
	local read = readLaunch(launch)
	if current and current.visual and not current.model then
		if not read then
			return
		end
		-- Départ du serveur : le plan affiché passe sur le sien sans saut, son mannequin est masqué
		local path = pathOf(read)
		FlightGhost.rebase(current.state, current.path, path)
		current.path = path
		current.deadline = nil
		attach(current, model)
		if RunService:IsStudio() then
			print(
				string.format(
					"[LaunchGhost] départ du serveur %.3f s après le lâcher, écart au départ prévu %.2f studs",
					os.clock() - current.releasedAt,
					current.state.correction.Magnitude
				)
			)
		end
		return
	end
	LaunchGhost.stop()
	if not read then
		return
	end
	local id = session
	local torso = model:WaitForChild("Torso", 2) -- même attente que Client.FlightCamera
	if id ~= session or not torso or not torso:IsA("BasePart") then
		return
	end
	local fresh: Active = {
		model = nil,
		torso = nil,
		visual = nil,
		from = CFrame.identity,
		grow = 1,
		scaled = 1,
		flight = CFrame.identity,
		releasedAt = os.clock(),
		deadline = nil,
		refused = false,
		copy = nil,
		pairs = {},
		hidden = {},
		effects = {},
		path = pathOf(read),
		state = FlightGhost.new(),
		shown = nil,
		offset = Vector3.zero,
		velocity = nil,
		speed = nil,
		previous = nil,
		added = nil,
	}
	attach(fresh, model)
	buildCopy(fresh, model)
	active = fresh
	bind(fresh)
	if RunService:IsStudio() then
		print(
			string.format(
				"[LaunchGhost] départ anticipé : %d pièces, trajectoire prévue %.2f s",
				#fresh.pairs,
				FlightGhost.duration(fresh.path)
			)
		)
	end
end

-- Cette méthode permet de savoir si le décoratif lâché porte encore l'affichage du vol lorsque les effets du vol
-- (Client.FlightFx) voient arriver le mannequin du joueur local (ils attendent alors le relais).
function LaunchGhost.anticipating(): boolean
	local current = active
	return current ~= nil and current.visual ~= nil
end

-- Cette méthode permet de donner la position, la vitesse et la vitesse réelle du torse affiché (décoratif ou copie
-- locale) lorsque la caméra de vol le cadre ; nil quand la copie répliquée est montrée telle quelle.
function LaunchGhost.torso(): (Vector3?, Vector3?, number?)
	local current = active
	if not current then
		return nil, nil, nil
	end
	return current.shown, current.velocity, current.speed
end

-- Cette méthode permet de donner le décalage de la copie locale sur le mannequin répliqué `model` à l'image en cours
-- lorsque les effets du vol (Client.FlightFx) se placent sur ce qui est affiché ; zéro si `model` est montré tel quel.
function LaunchGhost.offset(model: Model): Vector3
	local current = active
	if not current or current.model ~= model or not current.copy then
		return Vector3.zero
	end
	return current.offset
end

-- Cette méthode permet de retirer la copie locale sans attendre lorsque le joueur quitte le vol (retour au hub), et de
-- reconnaître le mannequin du joueur local dès son arrivée (masqué derrière le décoratif lâché).
function LaunchGhost.init(localPlayer: Player)
	player = localPlayer
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Ready" then
			LaunchGhost.stop()
		end
	end)
	task.spawn(function()
		local dummies = Workspace:WaitForChild("Course"):WaitForChild("Dummies")
		dummies.ChildAdded:Connect(function(child)
			if
				not child:IsA("Model")
				or child:GetAttribute("Owner") ~= player.UserId
				or not LaunchGhost.anticipating()
			then
				return
			end
			LaunchGhost.start(child, {
				origin = child:GetAttribute("LaunchOrigin"),
				velocity = child:GetAttribute("LaunchVelocity"),
				thrown = child:GetAttribute("ThrownIndex"),
			})
		end)
	end)
end

return LaunchGhost
