-- Bases du hub côté client : animation de construction quand une base monte de palier visuel (#122, déroulé dans
-- Shared.BaseUpgrade) et texte flottant lisible (#150) : taille bornée pour que les textes des bases voisines ne se
-- chevauchent pas (Shared.BaseLook.labelPixels), étiquette d'un mannequin posé masquée tant qu'elle passerait devant.
-- Le serveur pose l'habillage final tout de suite (Server.CourseBuilder.styleBase) et garde l'ancien quelques secondes
-- dans ReplicatedStorage : chaque client en anime un double local qui s'enfonce, cache les nouvelles pièces puis les
-- fait tomber une à une (sans collision jusqu'à leur arrivée), poussière et chocs de briques à l'impact, sol en fondu,
-- confettis à la fin. Une rangée qui s'ouvre (#212) : même animation, le terrain s'allonge vers le fond pendant le
-- fondu du sol ; chaque présentoir acheté tombe à sa place (attribut DropAt de son dessus). Un client arrivé après (ou
-- en retard) voit l'état final directement. Rien n'est répliqué.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLook = require(Shared:WaitForChild("BaseLook"))
local BaseUpgrade = require(Shared:WaitForChild("BaseUpgrade"))
local CourseLayout = require(Shared:WaitForChild("CourseLayout"))
local Sounds = require(Shared:WaitForChild("Sounds"))

local HubShops = require(script.Parent.HubShops)
local UIKit = require(script.Parent.UIKit)

local DUST_COUNT = 5 -- particules de poussière par pièce posée
local SOUND_GAP = 0.07 -- s au moins entre deux chocs de briques
local SOUND_LEVEL = 0.45 -- volume des chocs (part du volume de Shared.Sounds.Brick)
local DUST_COLOR = Color3.fromRGB(225, 205, 170)

-- Pièce d'un habillage, retenue telle que le serveur l'a posée (repère, collision) pour la rendre intacte à la fin
type PartState = { part: BasePart, cframe: CFrame, collide: boolean, query: boolean }
-- `visible` : au moins un bloc qui se voit (la zone invisible des paillettes ne fait ni poussière ni bruit)
type Piece = {
	parts: { PartState },
	emitters: { ParticleEmitter },
	bottom: Vector3,
	visible: boolean,
	alpha: number,
	done: boolean,
}

-- Animation en cours sur une base
type Run = {
	base: Model,
	look: Instance, -- nouvel habillage (répliqué)
	plan: BaseUpgrade.Plan,
	started: number, -- os.clock() du début (calé sur l'heure serveur du changement)
	speed: number, -- 1 ; Studio : attribut DebugUpgradeSpeed de Workspace (0,2 : cinq fois plus lent, pour les captures)
	clock: number, -- os.clock() de la réception (durée mesurée en Studio)
	pieces: { Piece },
	old: Folder?, -- double local de l'ancien habillage
	oldParts: { PartState },
	plot: BasePart?,
	fromPlot: Color3,
	toPlot: Color3,
	fromDepth: number, -- profondeur du terrain avant l'agrandissement (celle d'arrivée sinon)
	toSize: Vector3, -- terrain tel que le serveur l'a posé
	toCFrame: CFrame,
	dust: Part,
	emitter: ParticleEmitter,
}

-- Chute d'un présentoir acheté (#212) : socle, dessus et bandeau du palier, cachés jusqu'au départ
type Drop = {
	base: Model,
	display: number,
	parts: { PartState },
	bottom: Vector3,
	started: number, -- os.clock() du départ de la chute (peut être à venir)
	fall: number,
	reduced: boolean,
	speed: number,
	alpha: number,
	dust: Part,
	emitter: ParticleEmitter,
}

local BaseFx = {}

local DISPLAYED = "Displayed_" -- préfixe des mannequins posés (Server.BaseService), étiquette nom et $/s au-dessus

local DISPLAY_NAME = "^Display%d+$" -- dessus d'un présentoir (Server.CourseBuilder)
local DISPLAY_ATTRIBUTE = "Display" -- numéro du présentoir, sur son dessus, son socle et son bandeau

local runs: { [Model]: Run } = {}
local drops: { [BasePart]: Drop } = {} -- chutes en cours, par dessus de présentoir
local dropping: { [BasePart]: boolean } = {} -- pièces d'une chute en cours : l'animation de construction n'y touche pas
local lastSound = -math.huge -- dernier choc de briques joué (os.clock)
local labels: { [Model]: BillboardGui } = {} -- texte flottant de chaque base
local tags: { [BillboardGui]: boolean } = {} -- étiquettes des mannequins posés

-- Cette méthode permet de relever les pièces d'une base (pièce = enfant de l'habillage : modèle ou bloc seul) avec
-- leur étage, leur centre et leur bas, lorsque l'animation démarre.
local function collect(look: Instance): ({ Piece }, { BaseUpgrade.Piece })
	local pieces: { Piece } = {}
	local plans: { BaseUpgrade.Piece } = {}
	for _, child in look:GetChildren() do
		local parts: { PartState } = {}
		local emitters: { ParticleEmitter } = {}
		local candidates = child:GetDescendants()
		table.insert(candidates, child)
		local sum, low = Vector3.zero, math.huge
		local visible = false
		for _, item in candidates do
			if item:IsA("BasePart") then
				visible = visible or item.Transparency < 1
				table.insert(
					parts,
					{ part = item, cframe = item.CFrame, collide = item.CanCollide, query = item.CanQuery }
				)
				sum += item.Position
				low = math.min(low, item.Position.Y - item.Size.Y / 2)
			elseif item:IsA("ParticleEmitter") and item.Enabled then
				table.insert(emitters, item)
			end
		end
		if #parts > 0 then
			local center = sum / #parts
			table.insert(pieces, {
				parts = parts,
				emitters = emitters,
				bottom = Vector3.new(center.X, low, center.Z),
				visible = visible,
				alpha = -1,
				done = false,
			})
			local stage = child:GetAttribute(BaseUpgrade.STAGE_ATTRIBUTE)
			table.insert(plans, { position = center, stage = if typeof(stage) == "number" then stage else 0 })
		end
	end
	return pieces, plans
end

-- Cette méthode permet de rendre une pièce telle que le serveur l'a posée (place, collision, étincelles) lorsque sa
-- chute est finie ou que l'animation s'arrête.
local function settle(piece: Piece)
	if piece.done then
		return
	end
	piece.done = true
	for _, state in piece.parts do
		state.part.CFrame = state.cframe
		state.part.CanCollide = state.collide
		state.part.CanQuery = state.query
		state.part.LocalTransparencyModifier = 0
	end
	for _, emitter in piece.emitters do
		emitter.Enabled = true
	end
end

-- Cette méthode permet de placer une pièce à `lift` studs au-dessus de sa place avec la transparence locale `fade`
-- lorsque l'animation avance.
local function pose(piece: Piece, lift: number, fade: number)
	for _, state in piece.parts do
		state.part.CFrame = state.cframe + Vector3.new(0, lift, 0)
		state.part.LocalTransparencyModifier = fade
	end
end

-- Cette méthode permet de donner le terrain d'une base tel que le serveur l'a posé (couleur, taille, repère ; entrée
-- fixe) lorsque l'animation démarre ou s'arrête, même si une animation précédente l'a modifié localement.
local function serverPlot(base: Model, plot: BasePart): (Color3, Vector3, CFrame)
	local color = base:GetAttribute(BaseUpgrade.PLOT_COLOR_ATTRIBUTE)
	local depth = base:GetAttribute(BaseUpgrade.PLOT_DEPTH_ATTRIBUTE)
	if typeof(depth) ~= "number" then
		depth = plot.Size.Z
	end
	local position = plot.Position
	return if typeof(color) == "Color3" then color else plot.Color,
		Vector3.new(plot.Size.X, plot.Size.Y, depth),
		CFrame.new(position.X, position.Y, CourseLayout.BASE_FRONT - depth / 2)
end

-- Cette méthode permet de rendre les pièces et le sol tels que le serveur les a posés lorsque l'animation d'une base
-- se termine, qu'une autre la remplace ou que le serveur change l'habillage.
local function stop(run: Run)
	runs[run.base] = nil
	-- Pièces rendues même si le serveur a rangé l'habillage pour une animation suivante ; sol remis à l'état publié
	if run.look.Parent then
		for _, piece in run.pieces do
			settle(piece)
		end
	end
	if run.plot then
		run.plot.Color, run.plot.Size, run.plot.CFrame = serverPlot(run.base, run.plot)
	end
	if run.old then
		run.old:Destroy()
	end
	Debris:AddItem(run.dust, 2) -- la dernière poussière retombe
end

-- Cette méthode permet de faire un nuage de poussière (émetteur `emitter`) et un choc de briques (espacés) au point
-- `bottom` lorsqu'une pièce ou un présentoir touche le sol.
local function impact(emitter: ParticleEmitter, bottom: Vector3, now: number)
	local attachment = emitter.Parent :: Attachment
	attachment.WorldPosition = bottom
	emitter:Emit(DUST_COUNT)
	if now - lastSound < SOUND_GAP then
		return
	end
	lastSound = now
	-- Son porté par son propre point (pas celui de la poussière, qui se déplace), sous le terrain : il survit à l'animation
	local source = Instance.new("Attachment")
	source.WorldPosition = bottom
	source.Parent = Workspace.Terrain
	Debris:AddItem(source, 3)
	local definition = Sounds.Brick
	local sound = Instance.new("Sound")
	sound.SoundId = definition.id
	sound.Volume = definition.volume * SOUND_LEVEL
	sound.PlaybackSpeed = 0.95 + math.random() * 0.3
	sound.RollOffMinDistance = 30
	sound.RollOffMaxDistance = 300
	sound.Parent = source
	sound:Play()
end

-- Cette méthode permet de poser l'émetteur de poussière d'une animation (pièce invisible au centre de la base) lorsque
-- l'animation démarre.
local function dustEmitter(base: Model, at: Vector3): (Part, ParticleEmitter)
	local dust = Instance.new("Part")
	dust.Name = "UpgradeDust"
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.CanTouch = false
	dust.Transparency = 1
	dust.Size = Vector3.one
	dust.Position = at
	local attachment = Instance.new("Attachment")
	attachment.Parent = dust
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(DUST_COLOR)
	emitter.Size = NumberSequence.new(1.2, 3)
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(80, 80)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Drag = 5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = attachment
	dust.Parent = base
	return dust, emitter
end

-- Cette méthode permet de faire un double local, sans collision ni étincelles, de l'ancien habillage gardé par le
-- serveur lorsque l'animation démarre (nil s'il n'est plus là).
local function cloneOld(base: Model): (Folder?, { PartState })
	local store = ReplicatedStorage:FindFirstChild(BaseUpgrade.STORE)
	local previous = store and store:FindFirstChild(base.Name)
	if not previous then
		return nil, {}
	end
	local old = previous:Clone() :: Folder
	old.Name = "UpgradeOld"
	local parts: { PartState } = {}
	for _, item in old:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			table.insert(parts, { part = item, cframe = item.CFrame, collide = false, query = false })
		elseif item:IsA("ParticleEmitter") then
			item.Enabled = false
		end
	end
	old.Parent = base
	return old, parts
end

-- Cette méthode permet de faire jaillir les confettis d'une base lorsque son animation de construction finit ou n'est
-- pas jouée (changement reçu en retard, habillage absent).
local function celebrateNow(base: Model)
	local burst = base:FindFirstChild("UpgradeBurst")
	if burst and burst:IsA("BasePart") then
		HubShops.celebrate(burst)
	end
end

-- Cette méthode permet de confier à la chute en cours de son présentoir le bandeau `part` d'un habillage refait (true)
-- lorsque l'animation de construction démarre pendant cette chute : il tombe avec son socle.
local function adoptCollar(base: Model, part: BasePart): boolean
	local display = part:GetAttribute(DISPLAY_ATTRIBUTE)
	if typeof(display) ~= "number" then
		return false
	end
	for _, drop in drops do
		if drop.base == base and drop.display == display then
			table.insert(drop.parts, { part = part, cframe = part.CFrame, collide = false, query = false })
			dropping[part] = true
			part.LocalTransparencyModifier = 1 -- la chute le replace dès l'image suivante
			return true
		end
	end
	return false
end

-- Cette méthode permet de donner au terrain la profondeur de l'agrandissement en cours (`share` : 0 avant, 1 après),
-- entrée fixe, lorsque l'animation d'une rangée qui s'ouvre avance (#212) ; rien si la profondeur ne change pas.
local function stretch(run: Run, share: number)
	local plot = run.plot
	local to = run.toSize.Z
	if not plot or math.abs(run.fromDepth - to) < 1e-3 then
		return
	end
	local depth = BaseUpgrade.plotDepth(run.fromDepth, to, share)
	plot.Size = Vector3.new(run.toSize.X, run.toSize.Y, depth)
	-- Bord côté entrée inchangé : le terrain grandit vers le fond (-ENTRANCE)
	plot.CFrame = run.toCFrame + CourseLayout.ENTRANCE * (to - depth) / 2
end

-- Cette méthode permet de démarrer l'animation de construction d'une base lorsque le serveur signale un changement de
-- palier récent (attribut UpgradeAt) ; reçu trop tard : confettis seuls, l'état final est déjà là.
local function start(base: Model)
	local at = base:GetAttribute(BaseUpgrade.AT_ATTRIBUTE)
	local now = Workspace:GetServerTimeNow()
	if not BaseUpgrade.isFresh(at, now) then
		if not runs[base] then -- une animation en cours fera ses confettis
			celebrateNow(base)
		end
		return
	end
	local previous = runs[base]
	if previous then
		stop(previous)
	end
	local look = base:FindFirstChild("Look")
	if not look then
		celebrateNow(base)
		return
	end
	local plot = base:FindFirstChild("Plot") :: BasePart?
	local toPlot, toSize, toCFrame = Color3.new(), Vector3.zero, base:GetPivot()
	if plot then
		toPlot, toSize, toCFrame = serverPlot(base, plot)
	end
	local center = toCFrame.Position
	local depth = if plot then toSize.Z else CourseLayout.BASE_SIZE.Z
	local gate = center + CourseLayout.ENTRANCE * depth / 2
	local pieces, plans = collect(look)
	-- Bandeau d'un présentoir qui tombe (ancien ou refait) : sa chute le pose, l'animation de construction le laisse
	for _, piece in pieces do
		for _, state in piece.parts do
			if dropping[state.part] or adoptCollar(base, state.part) then
				piece.done = true
			end
		end
	end
	local reduced = UIKit.reducedMotion()
	local old, oldParts = cloneOld(base)
	local dust, emitter = dustEmitter(base, center)
	local fromPlot = base:GetAttribute(BaseUpgrade.FROM_PLOT_ATTRIBUTE)
	local fromDepth = base:GetAttribute(BaseUpgrade.FROM_DEPTH_ATTRIBUTE)
	local debugSpeed = if RunService:IsStudio() then Workspace:GetAttribute("DebugUpgradeSpeed") else nil
	local run: Run = {
		base = base,
		look = look,
		plan = BaseUpgrade.plan(plans, gate, reduced),
		started = os.clock() - math.clamp(now - (at :: number), 0, BaseUpgrade.MAX_AGE),
		speed = if typeof(debugSpeed) == "number" and debugSpeed > 0 then debugSpeed else 1,
		clock = os.clock(),
		pieces = pieces,
		old = old,
		oldParts = oldParts,
		plot = plot,
		fromPlot = if typeof(fromPlot) == "Color3" then fromPlot else toPlot,
		toPlot = toPlot,
		fromDepth = if typeof(fromDepth) == "number" then fromDepth else depth,
		toSize = toSize,
		toCFrame = toCFrame,
		dust = dust,
		emitter = emitter,
	}
	-- Nouvelles pièces cachées, sans collision ni rayons (caméra) jusqu'à leur arrivée, sol remis à l'ancienne couleur
	for _, piece in pieces do
		if piece.done then
			continue
		end
		for _, state in piece.parts do
			state.part.LocalTransparencyModifier = 1
			state.part.CanCollide = false
			state.part.CanQuery = false
		end
		for _, sparkle in piece.emitters do
			sparkle.Enabled = false
		end
	end
	if plot then
		plot.Color = run.fromPlot
	end
	runs[base] = run
	stretch(run, 0)
end

-- Cette méthode permet d'avancer l'animation d'une base d'une image (anciennes pièces, chutes, sol, confettis à la fin)
-- lorsque RenderStepped tourne ; s'arrête d'elle-même si le serveur a changé l'habillage entre-temps.
local function step(run: Run, now: number)
	if run.look.Parent ~= run.base then
		stop(run)
		return
	end
	local plan = run.plan
	local t = (now - run.started) * run.speed
	-- Anciennes pièces : s'enfoncent en s'effaçant (fondu seul en mouvement réduit)
	if run.old then
		local alpha = t / plan.out
		if alpha >= 1 then
			run.old:Destroy()
			run.old = nil
		else
			local sink, fade = BaseUpgrade.sink(alpha)
			for _, state in run.oldParts do
				state.part.CFrame = state.cframe + Vector3.new(0, if plan.reduced then 0 else sink, 0)
				state.part.LocalTransparencyModifier = fade
			end
		end
	end
	for index, piece in run.pieces do
		if piece.done then
			continue
		end
		local alpha = (t - plan.starts[index]) / plan.fall
		if alpha >= 1 then
			settle(piece)
		elseif alpha >= 0 then
			if plan.reduced then
				pose(piece, 0, 1 - alpha)
			else
				pose(piece, BaseUpgrade.dropOffset(alpha), 0)
				if piece.visible and BaseUpgrade.landed(piece.alpha, alpha) then
					impact(run.emitter, piece.bottom, now)
				end
			end
			piece.alpha = alpha
		end
	end
	if run.plot then
		local share = math.clamp((t - plan.floorStart) / math.max(plan.floorEnd - plan.floorStart, 1e-3), 0, 1)
		run.plot.Color = run.fromPlot:Lerp(run.toPlot, share)
		stretch(run, share)
	end
	if t >= plan.finish then
		stop(run)
		celebrateNow(run.base)
		if RunService:IsStudio() then
			print(
				string.format(
					"[BaseFx] %s : %d pièces, %.2f s prévues, %.2f s mesurées%s",
					run.base.Name,
					#run.pieces,
					plan.finish,
					now - run.clock,
					if run.speed ~= 1 then string.format(" (vitesse %.2f)", run.speed) else ""
				)
			)
		end
	end
end

-- Cette méthode permet de rendre un présentoir tel que le serveur l'a posé lorsque sa chute finit ou qu'une autre la
-- remplace.
local function land(drop: Drop)
	for _, state in drop.parts do
		local part = state.part
		part.CFrame = state.cframe
		part.LocalTransparencyModifier = 0
		dropping[part] = nil
		if state.collide then
			-- Socle et dessus : solides s'ils sont affichés (le serveur a pu les cacher entre-temps)
			part.CanCollide = part.Transparency < 1
			part.CanQuery = part.Transparency < 1
		end
	end
	Debris:AddItem(drop.dust, 2) -- la dernière poussière retombe
end

-- Cette méthode permet de lancer la chute du présentoir `top` (socle, dessus, bandeau) lorsque le serveur l'annonce
-- (attribut DropAt, il vient d'être acheté) ; annonce trop vieille (client arrivé après) : rien, il est déjà posé.
local function startDrop(base: Model, top: BasePart)
	local at = top:GetAttribute(BaseUpgrade.DROP_ATTRIBUTE)
	local now = Workspace:GetServerTimeNow()
	local display = top:GetAttribute(DISPLAY_ATTRIBUTE)
	if typeof(display) ~= "number" or not BaseUpgrade.dropFresh(at, now) then
		return
	end
	local previous = drops[top]
	if previous then
		drops[top] = nil
		land(previous)
	end
	-- Socle et dessus : sans collision ni rayons pendant la chute (`collide` : à rendre selon l'état publié)
	local members: { BasePart } = { top }
	local solid: { [BasePart]: boolean } = { [top] = true }
	local pedestal = base:FindFirstChild("Pedestal" .. display)
	if pedestal and pedestal:IsA("BasePart") then
		table.insert(members, pedestal)
		solid[pedestal] = true
	end
	local look = base:FindFirstChild("Look")
	local collar: BasePart? = nil
	if look then
		for _, child in look:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute(DISPLAY_ATTRIBUTE) == display then
				collar = child
				table.insert(members, child)
				break
			end
		end
	end
	-- Bandeau pris par une animation de construction en cours : rendu à sa place, la chute s'en charge
	local run = runs[base]
	if run and collar then
		for _, piece in run.pieces do
			for _, state in piece.parts do
				if state.part == collar then
					settle(piece)
				end
			end
		end
	end
	local parts: { PartState } = {}
	local low = math.huge
	for _, part in members do
		local own = solid[part] == true
		table.insert(parts, { part = part, cframe = part.CFrame, collide = own, query = own })
		if own then
			part.CanCollide = false
			part.CanQuery = false
		end
		part.LocalTransparencyModifier = 1
		dropping[part] = true
		low = math.min(low, part.Position.Y - part.Size.Y / 2)
	end
	local reduced = UIKit.reducedMotion()
	local debugSpeed = if RunService:IsStudio() then Workspace:GetAttribute("DebugUpgradeSpeed") else nil
	local speed = if typeof(debugSpeed) == "number" and debugSpeed > 0 then debugSpeed else 1
	local bottom = Vector3.new(top.Position.X, low, top.Position.Z)
	local dust, emitter = dustEmitter(base, bottom)
	drops[top] = {
		base = base,
		display = display,
		parts = parts,
		bottom = bottom,
		started = os.clock() + ((at :: number) - now) / speed,
		fall = if reduced then BaseUpgrade.FADE_TIME else BaseUpgrade.FALL_TIME,
		reduced = reduced,
		speed = speed,
		alpha = -1,
		dust = dust,
		emitter = emitter,
	}
end

-- Cette méthode permet d'avancer la chute d'un présentoir d'une image (caché avant son départ, chute et rebond, ou
-- fondu en mouvement réduit ; poussière et choc de briques à l'impact) lorsque RenderStepped tourne.
local function stepDrop(top: BasePart, drop: Drop, now: number)
	local alpha = (now - drop.started) * drop.speed / drop.fall
	if alpha >= 1 or not top.Parent then
		drops[top] = nil
		land(drop)
		if RunService:IsStudio() then
			print(string.format("[BaseFx] %s : présentoir %d posé", drop.base.Name, drop.display))
		end
		return
	end
	for _, state in drop.parts do
		if alpha < 0 then
			state.part.LocalTransparencyModifier = 1
		elseif drop.reduced then
			state.part.CFrame = state.cframe
			state.part.LocalTransparencyModifier = 1 - alpha
		else
			state.part.CFrame = state.cframe + Vector3.new(0, BaseUpgrade.dropOffset(alpha), 0)
			state.part.LocalTransparencyModifier = 0
		end
	end
	if not drop.reduced and BaseUpgrade.landed(drop.alpha, alpha) then
		impact(drop.emitter, drop.bottom, now)
	end
	drop.alpha = alpha
end

-- Cette méthode permet de suivre le dessus d'un présentoir (chute annoncée par le serveur) lorsqu'il apparaît dans une
-- base.
local function trackDisplay(base: Model, child: Instance)
	if child:IsA("BasePart") and string.match(child.Name, DISPLAY_NAME) then
		child:GetAttributeChangedSignal(BaseUpgrade.DROP_ATTRIBUTE):Connect(function()
			startDrop(base, child)
		end)
	end
end

-- Cette méthode permet de donner le centre (pixels) d'un point du monde à l'écran et sa profondeur devant la caméra
-- lorsque l'on place une étiquette (nil derrière la caméra).
local function project(camera: Camera, position: Vector3): (Vector2?, number)
	local point = camera:WorldToViewportPoint(position)
	if point.Z <= 0 then
		return nil, point.Z
	end
	return Vector2.new(point.X, point.Y), point.Z
end

-- Cette méthode permet de borner la largeur du texte de chaque base et de masquer l'étiquette d'un mannequin posé qui
-- passerait devant l'un de ces textes (#150) lorsque RenderStepped tourne.
local function arrangeLabels()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local unit = camera.ViewportSize.Y / (2 * math.tan(math.rad(camera.FieldOfView) / 2))
	-- Textes des bases affichés : centre et taille à l'écran
	local shown: { { center: Vector2, size: Vector2 } } = {}
	for base, gui in labels do
		local anchor = gui.Parent
		if not base.Parent or not anchor or not anchor:IsA("BasePart") then
			labels[base] = nil
			continue
		end
		local center, depth = project(camera, anchor.Position)
		if not center then
			continue -- derrière la caméra : pas affiché
		end
		local size = BaseLook.labelPixels(depth, unit)
		local current = gui.Size
		if math.abs(current.X.Offset - size.X) > 0.5 or current.X.Scale ~= 0 then
			gui.Size = UDim2.fromOffset(size.X, size.Y)
		end
		if (anchor.Position - eye).Magnitude <= gui.MaxDistance then
			-- Décalage du texte (SizeOffset, en tailles ; vers le haut quand Y > 0, l'écran compte Y vers le bas)
			local shift = gui.SizeOffset * size
			table.insert(shown, { center = center + Vector2.new(shift.X, -shift.Y), size = size })
		end
	end
	for gui in tags do
		local adornee = gui.Adornee
		if not gui:IsDescendantOf(Workspace) or not adornee or not adornee:IsA("BasePart") then
			tags[gui] = nil
			continue
		end
		local position = adornee.Position + gui.StudsOffsetWorldSpace
		local center, depth = project(camera, position)
		local hidden = false
		if center and (position - eye).Magnitude <= gui.MaxDistance then
			local perStud = unit / math.max(depth, 1)
			local size = Vector2.new(
				gui.Size.X.Scale * perStud + gui.Size.X.Offset,
				gui.Size.Y.Scale * perStud + gui.Size.Y.Offset
			)
			for _, label in shown do
				if BaseLook.overlaps(center, size, label.center, label.size) then
					hidden = true
					break
				end
			end
		end
		if gui.Enabled == hidden then
			gui.Enabled = not hidden
		end
	end
end

-- Cette méthode permet de suivre l'étiquette d'un mannequin posé (nom, $/s) lorsque le serveur le construit dans une
-- base.
local function trackTag(model: Instance)
	if model:IsA("Model") and string.sub(model.Name, 1, #DISPLAYED) == DISPLAYED then
		local gui = model:FindFirstChildOfClass("BillboardGui")
		if gui then
			tags[gui] = true
		end
	end
end

-- Cette méthode permet de suivre une base (changements de palier, texte flottant, étiquettes des mannequins posés)
-- lorsqu'elle apparaît.
local function track(base: Instance)
	if not base:IsA("Model") then
		return
	end
	base:GetAttributeChangedSignal(BaseUpgrade.AT_ATTRIBUTE):Connect(function()
		start(base)
	end)
	for _, child in base:GetChildren() do
		trackTag(child)
		trackDisplay(base, child)
	end
	base.ChildAdded:Connect(function(child)
		trackTag(child)
		trackDisplay(base, child)
	end)
	task.spawn(function()
		local anchor = base:WaitForChild("BaseLabel", 10)
		local gui = anchor and anchor:FindFirstChildOfClass("BillboardGui")
		if gui then
			labels[base] = gui
		end
	end)
end

-- Cette méthode permet de brancher les bases (déjà là ou à venir) et la boucle d'animation lorsque le client démarre.
function BaseFx.init()
	for _, base in CollectionService:GetTagged(BaseUpgrade.BASE_TAG) do
		track(base)
	end
	CollectionService:GetInstanceAddedSignal(BaseUpgrade.BASE_TAG):Connect(track)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, run in runs do
			step(run, now)
		end
		-- Après les animations de construction : la chute garde la main sur ses pièces
		for top, drop in drops do
			stepDrop(top, drop, now)
		end
		arrangeLabels()
	end)
end

return BaseFx
