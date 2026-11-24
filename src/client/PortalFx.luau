-- Portails des tours à la demande (#231) : le portail de la ligne d'arrivée et celui de sortie, au début de la piste,
-- ne sont pas dressés en permanence. Chaque client ouvre une copie des modèles de référence du serveur
-- (ReplicatedStorage.PortalTemplates, Server.Portals) quand un mannequin affiché (n'importe quel joueur) va franchir la
-- ligne avec un tour de plus à faire (Shared.Laps.finishNeeded), puis la referme après son passage. Le portail de sortie
-- s'ouvre en même temps et reste ouvert le temps de recracher le mannequin (EXIT_HOLD). Ouverture et fermeture : le
-- portail grandit depuis le cœur de son rideau (Model:ScaleTo) ; mouvement réduit : apparition sans animation.
-- Position affichée : copie locale du lanceur tant qu'elle est montrée (Client.LaunchGhost), comme Client.FlightFx.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Laps = require(Shared:WaitForChild("Laps"))

local LaunchGhost = require(script.Parent.LaunchGhost)
local UIKit = require(script.Parent.UIKit)

local OPEN_TIME = 0.3 -- durée de l'ouverture (s)
local CLOSE_TIME = 0.35 -- durée de la fermeture (s)
local CLOSE_DELAY = 0.25 -- le portail reste ouvert ce temps après le dernier besoin (pas de clignotement)
local EXIT_HOLD = 1.2 -- le portail de sortie reste ouvert ce temps après qu'un mannequin en est ressorti (s)
local MIN_SCALE = 0.02 -- échelle d'un portail fermé (ScaleTo refuse 0)

type Gate = {
	template: Model,
	model: Model?, -- copie ouverte (ou en train de s'ouvrir, de se fermer)
	swirl: Model?,
	period: number,
	scale: number, -- échelle affichée, de MIN_SCALE (fermé) à 1 (ouvert)
	wanted: boolean,
	lastNeed: number, -- os.clock() du dernier besoin
}
type Watched = { z: number?, lap: number }

local PortalFx = {}

local gates: { [string]: Gate } = {}
local watched: { [Model]: Watched } = {}
local exitUntil = 0 -- os.clock() jusqu'auquel le portail de sortie reste ouvert (mannequin qui en ressort)
local studio = RunService:IsStudio()

-- Cette méthode permet de préparer un portail fermé à partir de son modèle de référence lorsque le client démarre.
local function gate(template: Model): Gate
	local swirl = template:FindFirstChild("Swirl")
	local period = if swirl then tonumber(swirl:GetAttribute("Period")) else nil
	return {
		template = template,
		period = math.max(period or 2.4, 0.1),
		scale = MIN_SCALE,
		wanted = false,
		lastNeed = -math.huge,
	}
end

-- Cette méthode permet de donner la position affichée du torse d'un mannequin lancé lorsque l'on guette son passage.
local function shownZ(model: Model): number?
	local torso = model:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	return (torso.Position + LaunchGhost.offset(model)).Z
end

-- Cette méthode permet de dire si un mannequin affiché demande le portail d'arrivée cette image (et de noter sa sortie
-- par le portail de sortie quand son affichage saute au début de la piste) lorsque l'on parcourt les vols.
local function scan(model: Model, dt: number): boolean
	if model:GetAttribute("LaunchVelocity") == nil then
		return false
	end
	local z = shownZ(model)
	if not z then
		return false
	end
	local state = watched[model]
	if not state then
		state = { z = nil, lap = 1 }
		watched[model] = state
	end
	local lap = model:GetAttribute("Lap")
	local previous = state.z
	state.z = z
	-- Tour affiché : le serveur annonce le tour suivant un peu avant que l'affichage ressorte au début de la piste
	if typeof(lap) == "number" and lap > state.lap and z < Laps.LENGTH / 2 then
		state.lap = lap
		exitUntil = os.clock() + EXIT_HOLD
	end
	if not previous or dt <= 0 then
		return false
	end
	local speed = (z - previous) / dt
	return Laps.finishNeeded(z, speed, state.lap)
end

-- Cette méthode permet d'ouvrir la copie d'un portail (fermée, au cœur de son rideau) lorsque son besoin commence.
local function openCopy(g: Gate)
	local model = g.template:Clone()
	model:ScaleTo(MIN_SCALE)
	model.Parent = Workspace
	g.model = model
	g.swirl = model:FindFirstChild("Swirl") :: Model?
	g.scale = MIN_SCALE
	if studio then
		print(string.format("[Portal] %s ouvert", g.template.Name))
	end
end

-- Cette méthode permet d'avancer l'ouverture, la fermeture et le tourbillon d'un portail d'une image lorsque le rendu
-- tourne.
local function animate(g: Gate, need: boolean, now: number, dt: number)
	if need then
		g.lastNeed = now
	end
	local wanted = now - g.lastNeed <= CLOSE_DELAY
	if wanted and not g.model then
		openCopy(g)
	end
	local model = g.model
	if not model then
		return
	end
	local reduced = UIKit.reducedMotion()
	local target = if wanted then 1 else MIN_SCALE
	local speed = (1 - MIN_SCALE) / (if wanted then OPEN_TIME else CLOSE_TIME)
	local scale = if reduced then target else g.scale + math.clamp(target - g.scale, -speed * dt, speed * dt)
	if scale ~= g.scale then
		g.scale = scale
		-- Ouverture : dépassement (pop, courbe « back out ») sur la fin, comme les fenêtres du jeu ; fermeture qui accélère
		local p = (scale - MIN_SCALE) / (1 - MIN_SCALE)
		local eased = if wanted then 1 + 2.70158 * (p - 1) ^ 3 + 1.70158 * (p - 1) ^ 2 else p * p
		model:ScaleTo(math.max(MIN_SCALE + (1 - MIN_SCALE) * eased, MIN_SCALE))
	end
	if not wanted and scale <= MIN_SCALE then
		model:Destroy()
		g.model = nil
		g.swirl = nil
		if studio then
			print(string.format("[Portal] %s fermé", g.template.Name))
		end
		return
	end
	local swirl = g.swirl
	if swirl and swirl.PrimaryPart then
		swirl:PivotTo(swirl:GetPivot() * CFrame.Angles(0, 0, 2 * math.pi * dt / g.period))
	end
end

-- Cette méthode permet de récupérer les modèles de référence des portails et de les ouvrir à la demande des vols affichés
-- (dossier Course/Dummies) lorsque le client démarre.
function PortalFx.init()
	task.spawn(function()
		local templates = ReplicatedStorage:WaitForChild("PortalTemplates")
		local finish = templates:WaitForChild("FinishPortal") :: Model
		local exit = templates:WaitForChild("ExitPortal") :: Model
		gates.finish = gate(finish)
		gates.exit = gate(exit)
		local dummies = Workspace:WaitForChild("Course"):WaitForChild("Dummies")
		RunService.RenderStepped:Connect(function(dt)
			local need = false
			for _, child in dummies:GetChildren() do
				if child:IsA("Model") and scan(child, dt) then
					need = true
				end
			end
			for model in watched do
				if model.Parent ~= dummies then
					watched[model] = nil
				end
			end
			local now = os.clock()
			animate(gates.finish, need, now, dt)
			animate(gates.exit, need or now < exitUntil, now, dt)
		end)
	end)
end

return PortalFx
