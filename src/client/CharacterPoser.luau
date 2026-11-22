-- Animations des avatars (R15) et mannequins décoratifs : le joueur local joue les clips de Shared.AnimationData
-- (tenu, entraînement, lancer) sur son Animator, qui les réplique et pilote aussi bien les Motor6D que les
-- AnimationConstraint des avatars récents. Chaque client pose, pour tous les joueurs, le mannequin tenu sur la main
-- droite, le mannequin d'entraînement (celui du palier d'équipement) couché sur les deux mains, ou le mannequin de
-- collection porté devant la poitrine (outil du Backpack équipé, #54), d'après les attributs, l'outil et les mains.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationData = require(Shared:WaitForChild("AnimationData"))
local Assets = require(Shared:WaitForChild("Assets"))
local BackpackPlan = require(Shared:WaitForChild("BackpackPlan"))
local Collection = require(Shared:WaitForChild("Collection"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))
local Training = require(Shared:WaitForChild("Training"))
local TrainingLook = require(Shared:WaitForChild("TrainingLook"))

local LaunchGhost = require(script.Parent.LaunchGhost)
local UIKit = require(script.Parent.UIKit)

local HELD_SCALE = 0.6
local PALM_GAP = AnimationData.PALM_GAP
local LIFT_OFFSET = AnimationData.LIFT_OFFSET
local FADE = 0.2 -- fondu d'entrée et de sortie des clips (s)
local THROW_FADE = 0.08
local THROW_TIMEOUT = 3 -- fin forcée d'un lancer local (s)
local HANDOFF_TIME = 2 -- attente maximale du mannequin du serveur, décoratif figé au point de lâcher (s)
local RETRY_TIME = 1 -- nouvel essai après un LoadAnimation raté (s)
local ANSWER_TIME = 0.6 -- délai minimal entre le lâcher et la fin du geste, le temps que le serveur réponde (s)

type State = { visual: Model?, key: string? }
type Throw = {
	start: number,
	released: boolean,
	releasedAt: number,
	release: () -> (),
	finished: () -> (),
	track: AnimationTrack?,
	marker: RBXScriptConnection?,
}
type Released = { model: Model, born: number }

local CharacterPoser = {}

local localPlayer = Players.LocalPlayer
local states: { [Player]: State } = {}
-- false = chargement raté, pas retenté à chaque frame
local animations: { [string]: Animation | false } = {}
local tracks: {
	character: Model?,
	byName: { [string]: AnimationTrack | false },
	retryAt: { [string]: number },
} =
	{ character = nil, byName = {}, retryAt = {} }
local throw: Throw? = nil
local released: Released? = nil

local CLIPS: { [string]: AnimationData.Clip } = {}
for _, clip in AnimationData.CLIPS do
	CLIPS[clip.name] = clip
end

-- Cette méthode permet de donner l'Animation d'un clip lorsque l'on le charge : asset publié, ou dans Studio le
-- clip construit à la volée (KeyframeSequenceProvider) tant qu'il n'est pas publié ; nil sinon.
local function animationFor(clip: AnimationData.Clip): Animation?
	local cached = animations[clip.name]
	if cached ~= nil then
		return cached or nil
	end
	local uri = Assets.uri(Assets.ANIMATIONS[clip.name])
	if not uri and RunService:IsStudio() then
		local ok, result = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(AnimationData.buildSequence(clip))
		end)
		uri = if ok then result else nil
	end
	if not uri then
		animations[clip.name] = false
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = clip.name
	animation.AnimationId = uri
	animations[clip.name] = animation
	return animation
end

-- Cette méthode permet de donner la piste d'un clip sur le personnage du joueur local (chargée une fois par
-- personnage) lorsque l'on la joue ou l'arrête ; nil sans Animator ou sans animation.
local function trackFor(name: string): AnimationTrack?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	if tracks.character ~= character then
		tracks = { character = character, byName = {}, retryAt = {} }
	end
	local existing = tracks.byName[name]
	if existing ~= nil then
		return existing or nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil -- Animator pas encore créé : on retente à la frame suivante
	end
	local animation = animationFor(CLIPS[name])
	if not animation then
		tracks.byName[name] = false
		return nil
	end
	if os.clock() < (tracks.retryAt[name] or 0) then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		tracks.retryAt[name] = os.clock() + RETRY_TIME -- Animator en cours d'initialisation : on retentera
		return nil
	end
	tracks.byName[name] = track
	return track
end

-- Cette méthode permet de jouer ou d'arrêter un clip en boucle du joueur local lorsque son action change ;
-- l'entraînement est calé sur REP_TIME et démarre au sommet, là où le serveur compte la répétition.
local function setLooping(name: string, on: boolean)
	local track = if on then trackFor(name) else tracks.byName[name] or nil
	if not track then
		return
	end
	if on and not track.IsPlaying then
		track:Play(FADE)
		if name == "Train" then
			local clip = CLIPS.Train
			track:AdjustSpeed(clip.length / GameConfig.REP_TIME)
			track.TimePosition = clip.markers.Top
		end
	elseif not on and track.IsPlaying then
		track:Stop(FADE)
	end
end

-- Cette méthode permet de calculer où poser le mannequin tenu (couché sur la paume droite, dos contre la main, tête
-- vers l'avant du personnage) lorsque le personnage le porte ou le lance ; suit le bras pendant tout le geste.
local function palmFrame(character: Model, root: BasePart, scale: number): CFrame
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	local arm = character:FindFirstChild("RightUpperArm") :: BasePart?
	local fallback = root.CFrame * CFrame.new(0, GameConfig.THROW_HEIGHT, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	if not hand or not arm then
		return fallback
	end
	local reach = hand.Position - arm.Position
	if reach.Magnitude < 0.1 then
		return fallback
	end
	local up = reach.Unit
	local forward = root.CFrame.LookVector
	local head = forward - up * forward:Dot(up)
	if head.Magnitude < 0.05 then
		head = -root.CFrame.UpVector
	end
	head = head.Unit
	local back = -up
	local center = hand.Position + up * (PALM_GAP + LIFT_OFFSET * scale) + head * (0.5 * scale)
	return CFrame.fromMatrix(center, head:Cross(back), head, back)
end

-- Cette méthode permet de calculer où poser le mannequin d'entraînement (couché sur le dos en travers des deux mains,
-- au-dessus de la tête) lorsque le personnage s'entraîne.
local function liftFrame(character: Model, root: BasePart, scale: number): CFrame
	local left = character:FindFirstChild("LeftHand") :: BasePart?
	local right = character:FindFirstChild("RightHand") :: BasePart?
	local up = root.CFrame.UpVector
	if not left or not right then
		return root.CFrame * CFrame.new(0, GameConfig.THROW_HEIGHT, 0) * CFrame.Angles(-math.pi / 2, 0, -math.pi / 2)
	end
	local across = right.Position - left.Position
	across -= up * across:Dot(up)
	across = if across.Magnitude > 0.05 then across.Unit else root.CFrame.RightVector
	local center = (left.Position + right.Position) / 2 + up * (PALM_GAP + LIFT_OFFSET * scale)
	local back = -up
	return CFrame.fromMatrix(center, across:Cross(back), across, back)
end

-- Cette méthode permet de remplacer le mannequin décoratif d'un personnage lorsque ce qu'il tient change (`key`) ;
-- nil le retire.
local function setVisual(state: State, key: string?, build: (() -> Model)?)
	if state.key == key then
		return
	end
	if state.visual then
		state.visual:Destroy()
		state.visual = nil
	end
	state.key = key
	if build then
		local model = build()
		local primary = model.PrimaryPart :: BasePart
		primary.Anchored = true
		model.Parent = Workspace
		state.visual = model
	end
end

-- Cette méthode permet de lâcher le mannequin du joueur local lorsque l'animation de lancer atteint son marqueur
-- Release (ou le délai de secours) : le lancer part au serveur et le décoratif n'est plus posé sur la main ; le geste
-- le confie à Client.LaunchGhost, qui le fait partir tout de suite (#144), sinon il reste figé au point de lâcher.
local function release()
	local current = throw
	if not current or current.released then
		return
	end
	current.released = true
	current.releasedAt = os.clock()
	local state = states[localPlayer]
	if state and state.visual then
		if released then
			released.model:Destroy()
		end
		released = { model = state.visual, born = os.clock() }
		state.visual = nil
		state.key = nil
	end
	current.release()
end

-- Cette méthode permet de retirer le décoratif lâché lorsque le mannequin du serveur n'arrive pas (HANDOFF_TIME,
-- filet de sécurité : le refus et l'arrivée du vrai passent par handOff).
local function updateReleased(now: number)
	local current = released
	if current and (now - current.born > HANDOFF_TIME or not current.model.Parent) then
		current.model:Destroy()
		released = nil
	end
end

-- Cette méthode permet de donner la clé « id:taille » du mannequin de collection que tient un personnage (outil du
-- Backpack équipé) lorsque l'on pose le mannequin porté ; nil s'il n'en tient pas.
local function carriedKey(character: Model?): string?
	local _, key = BackpackPlan.held(character)
	return key
end

-- Cette méthode permet de jouer les clips en boucle du joueur local selon son action et de clore son lancer
-- lorsque Heartbeat tourne.
local function updateLocal(action: any, now: number)
	local current = throw
	if current then
		local playing = current.track ~= nil and current.track.IsPlaying
		local answered = current.released and now - current.releasedAt > ANSWER_TIME
		if now - current.start > THROW_TIMEOUT or (answered and not playing) then
			throw = nil
			if current.marker then
				current.marker:Disconnect()
			end
			current.finished()
			current = nil
		end
	end
	setLooping("Hold", action == "Holding" and current == nil)
	setLooping("Train", action == "Training")
	setLooping("Carry", action == nil and current == nil and carriedKey(localPlayer.Character) ~= nil)
end

-- Cette méthode permet de calculer où poser le mannequin porté (debout devant la poitrine, entre les deux mains, pieds
-- au-dessus du sol) lorsque le personnage tient un mannequin de collection.
local function carryFrame(character: Model, root: BasePart, scale: number): CFrame
	local left = character:FindFirstChild("LeftHand") :: BasePart?
	local right = character:FindFirstChild("RightHand") :: BasePart?
	local hands = if left and right
		then (left.Position + right.Position) / 2
		else (root.CFrame * CFrame.new(0, 0.4, -1)).Position
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local ground = if humanoid then root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 else nil
	return AnimationData.carryFrame(hands, root.CFrame.LookVector, scale, ground)
end

-- Cette méthode permet de mettre à jour le mannequin décoratif d'un joueur lorsque Heartbeat tourne.
local function update(player: Player, state: State)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		setVisual(state, nil)
		return
	end
	local action = player:GetAttribute("Action")
	-- Pas de nouveau mannequin en main tant que le décoratif lâché vole sans réponse du serveur (#144)
	local releasedHere = player == localPlayer and (throw ~= nil and throw.released or LaunchGhost.anticipating())
	-- Le suffixe reconstruit le décoratif en maillé quand les gabarits arrivent après lui (blocs en attendant)
	local shape = ":mesh" .. DummyShape.meshStage()
	local carried = if action == nil then carriedKey(character) else nil
	if action == "Holding" and not releasedHere then
		-- Mannequin à lancer équipé (boutique, Shared.ThrowDummies) : celui qui part au lancer
		local _, thrown = ThrowDummies.sanitize(player:GetAttribute("ThrowTier"), player:GetAttribute("ThrowEquipped"))
		setVisual(state, "Holding" .. thrown .. shape, function()
			return DummyShape.buildVisual(HELD_SCALE, ThrowDummies.variant(thrown) :: DummyShape.Variant)
		end)
		if state.visual then
			state.visual:PivotTo(palmFrame(character, root, HELD_SCALE))
		end
	elseif action == "Training" then
		local tier = (player:GetAttribute("GearTier") :: number?) or 1
		local gear = Training.gear(tier)
		-- Look du palier (#118) ; sans particules en mouvement réduit (la clé reconstruit au changement de réglage), les
		-- pièces ajoutées (anneaux, lunes) restant à leur repos par Client.DummyFx (#146)
		local still = UIKit.reducedMotion()
		setVisual(state, "Training" .. tier .. (if still then ":still" else "") .. shape, function()
			return DummyShape.buildVisual(gear.scale, TrainingLook.variant(tier, "lifted", still) :: DummyShape.Variant)
		end)
		if state.visual then
			state.visual:PivotTo(liftFrame(character, root, gear.scale))
		end
	elseif carried then
		-- Mannequin de collection porté (outil équipé), à l'échelle de sa taille
		local key = carried
		local entry = Inventory.parseKey(key) :: Collection.Entry
		local scale = AnimationData.CARRY_SCALE * Collection.scale(entry)
		setVisual(state, "Carry" .. key .. shape, function()
			return DummyShape.buildVisual(scale, Collection.variant(entry, true) :: DummyShape.Variant)
		end)
		if state.visual then
			state.visual:PivotTo(carryFrame(character, root, scale))
		end
	else
		setVisual(state, nil)
	end
end

-- Cette méthode permet de lancer le geste du joueur local lorsque la jauge est arrêtée : clip de lancer, puis
-- `onRelease` au marqueur Release et `onFinished` quand le geste est fini (lancer parti ou refusé).
function CharacterPoser.playThrow(onRelease: () -> (), onFinished: () -> ())
	local current: Throw =
		{ start = os.clock(), released = false, releasedAt = 0, release = onRelease, finished = onFinished }
	throw = current
	setLooping("Hold", false)
	local track = trackFor("Throw")
	if track then
		current.track = track
		current.marker = track:GetMarkerReachedSignal("Release"):Once(release)
		track:Play(THROW_FADE)
		-- Fondu de sortie avant la fin du clip : un clip qui s'arrête seul passe d'un coup à l'animation par défaut
		task.delay(CLIPS.Throw.length - FADE, function()
			if throw == current and track.IsPlaying then
				track:Stop(FADE)
			end
		end)
	end
	task.delay(GameConfig.THROW_RELEASE_TIME + GameConfig.GAUGE_RELEASE_SLACK, function()
		if throw == current then
			release()
		end
	end)
end

-- Cette méthode permet de savoir si le geste du joueur local est en cours lorsque l'interface doit ignorer un clic.
function CharacterPoser.isThrowing(): boolean
	return throw ~= nil
end

-- Cette méthode permet de donner le décoratif lâché par le joueur local et son échelle de construction lorsque le
-- geste le fait partir sans attendre le serveur (Client.LaunchGhost, #144) ; nil s'il n'y en a pas.
function CharacterPoser.released(): (Model?, number)
	local current = released
	return if current then current.model else nil, HELD_SCALE
end

-- Cette méthode permet d'oublier le décoratif lâché (sans le retirer) lorsque Client.LaunchGhost l'a pris en charge.
function CharacterPoser.forgetReleased()
	released = nil
end

-- Cette méthode permet de retirer le mannequin décoratif lâché lorsque le mannequin du serveur prend le relais.
function CharacterPoser.handOff()
	if released then
		released.model:Destroy()
		released = nil
	end
end

-- Cette méthode permet de brancher le suivi des joueurs et la boucle des animations lorsque le client démarre.
function CharacterPoser.init()
	-- Cette méthode permet de suivre un joueur lorsqu'il rejoint la partie (ou y est déjà).
	local function track(player: Player)
		states[player] = { visual = nil, key = nil }
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			setVisual(state, nil)
			states[player] = nil
		end
	end)
	-- Heartbeat : après la simulation, les mains sont à leur place animée de la frame
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		updateLocal(localPlayer:GetAttribute("Action"), now)
		for player, state in states do
			update(player, state)
		end
		updateReleased(now)
	end)
	-- Le serveur compte la répétition au sommet : on y recale le clip à chaque répétition (le premier lancement
	-- d'un clip publié encore en chargement ignore TimePosition)
	-- Cette méthode permet de recaler le clip au sommet lorsqu'une répétition change l'EXP ou le niveau.
	local function resyncTrain()
		local train = tracks.byName.Train
		if train and train.IsPlaying and localPlayer:GetAttribute("Action") == "Training" then
			train.TimePosition = CLIPS.Train.markers.Top
		end
	end
	localPlayer:GetAttributeChangedSignal("TrainExp"):Connect(resyncTrain)
	localPlayer:GetAttributeChangedSignal("TrainLevel"):Connect(resyncTrain)
end

return CharacterPoser
