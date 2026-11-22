-- Départ du vol du joueur local (#117) : le mannequin lancé est simulé par le serveur, et sa copie répliquée reste
-- figée à son apparition le temps que le tampon d'interpolation du moteur se remplisse (200 à 290 ms), puis s'affiche
-- en retard. Le lanceur voit à sa place une copie locale de ce mannequin (mêmes pièces, même pose, chaque image),
-- décalée sur la trajectoire du plan (Shared.FlightGhost) : elle quitte la main sans s'arrêter, puis son avance se
-- résorbe et la copie répliquée, masquée pour lui seul pendant ce temps, reprend la main (0,9 à 1,2 s mesurées). Au
-- retour, la copie locale est masquée et ses effets coupés, puis retirée après la vie de ses particules. Les autres
-- joueurs et le résultat du serveur ne changent pas.
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FlightGhost = require(Shared:WaitForChild("FlightGhost"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))

local BIND_NAME = "LaunchGhost"
local FADE_OUT = 2 -- copie locale gardée, masquée, après le retour (s) : ses particules et sa traînée s'éteignent
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

type Pair = { source: BasePart, copy: BasePart }
type Active = {
	model: Model, -- copie répliquée affichée à travers la copie locale
	torso: BasePart,
	copy: Model,
	pairs: { Pair },
	hidden: { [Instance]: number }, -- LocalTransparencyModifier d'origine des pièces et décalcomanies masquées
	effects: { [Instance]: boolean }, -- Enabled d'origine des effets coupés
	path: FlightGhost.Path,
	state: FlightGhost.State,
	shown: Vector3?, -- position affichée du torse (copie locale) à l'image en cours
	offset: Vector3, -- décalage de la copie locale sur la copie répliquée à l'image en cours
	velocity: Vector3?, -- vitesse affichée du torse à l'image en cours
	previous: Vector3?, -- position de la copie répliquée à l'image précédente
	added: RBXScriptConnection?, -- pièces et effets arrivés après le départ
}

local LaunchGhost = {}

local active: Active? = nil
local session = 0 -- incrémenté à chaque départ ou arrêt : un départ qui attendait son torse s'efface

-- Cette méthode permet de rendre la main à la copie répliquée (copie locale retirée, pièces et effets rendus) lorsque
-- l'avance est résorbée, que le vol disparaît ou qu'un autre lancer part.
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
	for _, descendant in current.copy:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = 1
		elseif EFFECTS[descendant.ClassName] then
			(descendant :: any).Enabled = false
		end
	end
	Debris:AddItem(current.copy, FADE_OUT)
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
-- effet) lorsque la copie locale la remplace à l'écran.
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

-- Cette méthode permet d'ajouter à la copie locale une pièce du mannequin répliqué (enfant direct) lorsque
-- l'affichage anticipé démarre ou qu'elle arrive après.
local function mirror(current: Active, source: Instance)
	if source:IsA("BasePart") then
		local part = copyPart(source)
		part.Parent = current.copy
		table.insert(current.pairs, { source = source, copy = part })
	end
end

-- Cette méthode permet de démarrer l'affichage anticipé du mannequin du joueur local lorsque le serveur annonce son
-- lancer (`launch` : point de départ, vitesse, mannequin lancé) ; sans effet si le départ est illisible.
function LaunchGhost.start(model: Model, launch: any)
	LaunchGhost.stop()
	if typeof(launch) ~= "table" or typeof(launch.origin) ~= "Vector3" or typeof(launch.velocity) ~= "Vector3" then
		return
	end
	local id = session
	local torso = model:WaitForChild("Torso", 2) -- même attente que Client.FlightCamera
	if id ~= session or not torso or not torso:IsA("BasePart") then
		return
	end
	local thrown = if ThrowDummies.isIndex(launch.thrown) then ThrowDummies.get(launch.thrown) else nil
	local path = FlightGhost.path(launch.origin, launch.velocity, Workspace.Gravity, thrown)
	local copy = Instance.new("Model")
	copy.Name = "LaunchGhost"
	local current: Active = {
		model = model,
		torso = torso,
		copy = copy,
		pairs = {},
		hidden = {},
		effects = {},
		path = path,
		state = FlightGhost.new(),
		shown = nil,
		offset = Vector3.zero,
		velocity = nil,
		previous = nil,
		added = nil,
	}
	for _, child in model:GetChildren() do
		mirror(current, child)
	end
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
	copy.Parent = Workspace
	active = current
	-- Avant la caméra (Client.FlightCamera, Camera + 1) : elle cadre la position affichée de cette image
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 1, function(dt)
		if active ~= current then
			return
		end
		if not torso.Parent then
			LaunchGhost.stop()
			return
		end
		local state = current.state
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
	end)
	if RunService:IsStudio() then
		print(
			string.format(
				"[LaunchGhost] départ anticipé : %d pièces, trajectoire prévue %.2f s",
				#current.pairs,
				FlightGhost.duration(path)
			)
		)
	end
end

-- Cette méthode permet de donner la position et la vitesse du torse affiché (copie locale) lorsque la caméra de vol le
-- cadre ; nil quand la copie répliquée est montrée telle quelle.
function LaunchGhost.torso(): (Vector3?, Vector3?)
	local current = active
	if not current then
		return nil, nil
	end
	return current.shown, current.velocity
end

-- Cette méthode permet de donner le décalage de la copie locale sur le mannequin répliqué `model` à l'image en cours
-- lorsque les effets du vol (Client.FlightFx) se placent sur ce qui est affiché ; zéro si `model` est montré tel quel.
function LaunchGhost.offset(model: Model): Vector3
	local current = active
	if not current or current.model ~= model then
		return Vector3.zero
	end
	return current.offset
end

-- Cette méthode permet de retirer la copie locale sans attendre lorsque le joueur quitte le vol (retour au hub).
function LaunchGhost.init(player: Player)
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Ready" then
			LaunchGhost.stop()
		end
	end)
end

return LaunchGhost
