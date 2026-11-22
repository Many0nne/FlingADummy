-- Départ du vol du joueur local (#117) : le mannequin lancé est simulé par le serveur, et sa copie répliquée reste
-- figée à son apparition le temps que le tampon d'interpolation du moteur se remplisse (≈ 200 ms), puis s'affiche en
-- retard. Le lanceur voit à sa place une copie locale de ce mannequin (mêmes pièces, même pose, chaque image),
-- décalée sur la trajectoire du plan (Shared.FlightGhost) : elle quitte la main sans s'arrêter, puis son avance se
-- résorbe et la copie répliquée, masquée pour lui seul pendant ce temps, reprend la main (≈ 1,7 s au plus). Les
-- autres joueurs et le résultat du serveur ne changent pas.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FlightGhost = require(Shared:WaitForChild("FlightGhost"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))

local BIND_NAME = "LaunchGhost"
-- Effets de la copie répliquée coupés pendant l'affichage anticipé (la copie locale porte les siens)
local EFFECTS = {
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
	torso: BasePart,
	copy: Model,
	pairs: { Pair },
	hidden: { [Instance]: number }, -- LocalTransparencyModifier d'origine des pièces et décalcomanies masquées
	effects: { [Instance]: boolean }, -- Enabled d'origine des effets coupés
	path: FlightGhost.Path,
	state: FlightGhost.State,
	shown: Vector3?, -- position affichée du torse (copie locale) à l'image en cours
}

local LaunchGhost = {}

local active: Active? = nil

-- Cette méthode permet de rendre la main à la copie répliquée (copie locale retirée, pièces et effets rendus) lorsque
-- l'avance est résorbée, que le vol disparaît ou qu'un autre lancer part.
function LaunchGhost.stop()
	local current = active
	if not current then
		return
	end
	active = nil
	RunService:UnbindFromRenderStep(BIND_NAME)
	current.copy:Destroy()
	for instance, value in current.hidden do
		if instance.Parent then
			(instance :: any).LocalTransparencyModifier = value
		end
	end
	for instance, enabled in current.effects do
		if instance.Parent then
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

-- Cette méthode permet de masquer pour le joueur local la copie répliquée (pièces, décalcomanies, effets) lorsque la
-- copie locale la remplace à l'écran.
local function hideSource(model: Model, current: Active)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			current.hidden[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = 1
		elseif EFFECTS[descendant.ClassName] then
			current.effects[descendant] = (descendant :: any).Enabled;
			(descendant :: any).Enabled = false
		end
	end
end

-- Cette méthode permet de démarrer l'affichage anticipé du mannequin du joueur local lorsque le serveur annonce son
-- lancer (`launch` : point de départ, vitesse, mannequin lancé) ; sans effet si le départ est illisible.
function LaunchGhost.start(model: Model, launch: any)
	LaunchGhost.stop()
	if typeof(launch) ~= "table" or typeof(launch.origin) ~= "Vector3" or typeof(launch.velocity) ~= "Vector3" then
		return
	end
	local torso = model:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local thrown = if ThrowDummies.isIndex(launch.thrown) then ThrowDummies.get(launch.thrown) else nil
	local path = FlightGhost.path(launch.origin, launch.velocity, Workspace.Gravity, thrown)
	local copy = Instance.new("Model")
	copy.Name = "LaunchGhost"
	local current: Active = {
		torso = torso,
		copy = copy,
		pairs = {},
		hidden = {},
		effects = {},
		path = path,
		state = FlightGhost.new(),
		shown = nil,
	}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local part = copyPart(child)
			part.Parent = copy
			table.insert(current.pairs, { source = child, copy = part })
		end
	end
	hideSource(model, current)
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
			pair.copy.CFrame = pair.source.CFrame + offset
		end
		current.shown = torso.Position + offset
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

-- Cette méthode permet de donner la position et la vitesse affichées du torse du mannequin du joueur local (copie
-- locale) lorsque la caméra de vol le cadre ; nil quand la copie répliquée est montrée telle quelle (vitesse : nil
-- aussi pendant la résorption forcée).
function LaunchGhost.torso(): (Vector3?, Vector3?)
	local current = active
	if not current or not current.shown then
		return nil, nil
	end
	return current.shown, FlightGhost.velocity(current.path, current.state)
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
