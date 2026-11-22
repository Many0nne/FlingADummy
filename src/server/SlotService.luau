-- Places du lobby (SLOT_COUNT joueurs sur une piste partagée) : chaque joueur reçoit une place (sa base et son appareil
-- d'entraînement) et réapparaît dans le hub, juste derrière la bande de lancer commune. Un joueur prêt qui pose le
-- pied sur la bande y est figé par le serveur, face à la piste (à l'endroit où il est entré, écarté de ses voisins), et
-- passe à l'état « Holding » (mannequin dans les bras, jauge ouverte) jusqu'à son lancer ; après le vol, il revient
-- dans le hub, derrière la bande.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local SlotQueue = require(ReplicatedStorage.Shared.SlotQueue)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local CollisionGroups = require(script.Parent.CollisionGroups)
local CourseBuilder = require(script.Parent.CourseBuilder)

type Slot = CourseBuilder.Slot

-- Joueur figé sur la bande : son abscisse, l'instant où sa jauge s'est ouverte et les réglages rendus à la fin
type Frozen = {
	x: number,
	since: number,
	root: BasePart,
	humanoid: Humanoid,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
}

local SlotService = {}

local slots: { Slot } = {}
local queue = SlotQueue.new(0) :: SlotQueue.Queue<Player> -- places et file d'attente, remplacé dans init
local slotOf: { [Player]: Slot } = {}
local frozen: { [Player]: Frozen } = {}

-- Cette méthode permet de rendre au joueur ses déplacements (et de le ramener dans le hub derrière la bande si
-- `toHub`) lorsque son lancer est fini ; sans effet s'il n'est pas figé.
local function unfreeze(player: Player, toHub: boolean)
	local state = frozen[player]
	if not state then
		return
	end
	frozen[player] = nil
	local humanoid = state.humanoid
	humanoid.WalkSpeed = state.walkSpeed
	humanoid.JumpPower = state.jumpPower
	humanoid.JumpHeight = state.jumpHeight
	state.root.Anchored = false
	-- L'ancrage avait repris le personnage au joueur : on le lui rend pour qu'il marche sans à-coups
	if state.root.Parent then
		pcall(state.root.SetNetworkOwner, state.root, player)
	end
	local slot = slotOf[player]
	if toHub and slot and state.root.Parent and player.Character then
		player.Character:PivotTo(slot.spawn)
	end
	if player:GetAttribute("Action") == "Holding" then
		player:SetAttribute("Action", nil)
	end
end

-- Cette méthode permet de figer le joueur sur la bande (face à la piste, là où il est entré, écarté d'un voisin,
-- debout sur la bande) et d'ouvrir sa jauge lorsqu'il y pose le pied, prêt à lancer.
local function freeze(player: Player, character: Model, root: BasePart, humanoid: Humanoid): boolean
	local taken = {}
	for _, other in frozen do
		table.insert(taken, other.x)
	end
	local x = CourseLayout.bandSpot(root.Position.X, taken)
	if not x then
		return false -- bande pleine : il attend sans être figé
	end
	-- Debout sur la bande même s'il y arrive en sautant : HumanoidRootPart à hauteur des jambes + sa demi-hauteur
	-- (R6 : HipHeight vaut 0, jambes de 2 studs)
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	local z = CourseLayout.bandDepth(root.Position.Z)
	local position = Vector3.new(x, CourseLayout.BAND_TOP + legs + root.Size.Y / 2, z)
	frozen[player] = {
		x = x,
		since = os.clock(),
		root = root,
		humanoid = humanoid,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(position, position + Vector3.zAxis))
	-- Ancré par le serveur : le client ne peut plus le déplacer
	root.Anchored = true
	player:SetAttribute("Action", "Holding")
	return true
end

-- Cette méthode permet de mettre toutes les pièces du personnage dans le groupe Characters lorsqu'il apparaît
-- (accessoires chargés après coup compris) : il ne gêne ni le mannequin ni les éclats ni les obstacles.
local function setupCharacter(player: Player, character: Model)
	CollisionGroups.assign(character, CollisionGroups.CHARACTERS)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionGroups.CHARACTERS
		end
	end)
	-- Nouveau personnage : l'ancien, figé, a disparu avec ses réglages
	frozen[player] = nil
	player:SetAttribute("Action", nil)
	local slot = slotOf[player]
	if slot and character:WaitForChild("HumanoidRootPart", 5) then
		character:PivotTo(slot.spawn)
	end
end

-- Cette méthode permet de poser la place `index` sur le joueur (attributs lus par la base, l'appareil et le HUD) et de
-- lui retirer le message d'attente lorsqu'une place lui est donnée, à son arrivée ou quand un autre joueur part.
local function grant(player: Player, index: number)
	slotOf[player] = slots[index]
	player:SetAttribute("SlotWait", nil)
	player:SetAttribute("Slot", index)
	player:SetAttribute("LaneState", "Ready")
end

-- Cette méthode permet de donner au joueur la première place libre lorsqu'il arrive, ou de le mettre en attente
-- (attribut SlotWait, message du client) quand le lobby est plein.
local function assign(player: Player)
	local index = queue:join(player)
	if index then
		grant(player, index)
	else
		player:SetAttribute("SlotWait", true)
		warn("[SlotService] lobby plein : " .. player.Name .. " attend une place")
	end
	-- Retour au hub quand le lancer est fini (LaunchService repasse le joueur à « Ready » après le résultat), sauf s'il
	-- vient d'être remis en prise sur la bande (THROW AGAIN, SlotService.holdAgain)
	player:GetAttributeChangedSignal("LaneState"):Connect(function()
		if player:GetAttribute("LaneState") == "Ready" and player:GetAttribute("Action") ~= "Holding" then
			unfreeze(player, true)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

-- Cette méthode permet de figer sur la bande le joueur prêt qui y pose le pied lorsque Heartbeat tourne.
local function watchBand(player: Player)
	if frozen[player] or player:GetAttribute("Action") ~= nil then
		return -- déjà figé, ou à l'entraînement
	end
	if player:GetAttribute("LaneState") ~= "Ready" or not player:GetAttribute("DataReady") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and root and humanoid and humanoid.Health > 0 and CourseLayout.isOnBand(root.Position) then
		freeze(player, character, root, humanoid)
	end
end

-- Cette méthode permet de donner la place d'un joueur lorsque le serveur traite son lancer ou son entraînement ; nil
-- s'il n'en a pas.
function SlotService.getSlot(player: Player): Slot?
	return slotOf[player]
end

-- Cette méthode permet de donner l'instant (os.clock du serveur) où la jauge du joueur s'est ouverte lorsque le
-- serveur vérifie la valeur de son lancer ; nil s'il n'est pas figé sur la bande.
function SlotService.gaugeOpenedAt(player: Player): number?
	local state = frozen[player]
	return state and state.since
end

-- Cette méthode permet de remettre le joueur en prise sur la bande (Action « Holding ») lorsqu'il clique THROW AGAIN
-- (#76), avant son retour à « Ready » ; false (retour au hub, comme GO BACK) si refusé ou bande pleine.
function SlotService.holdAgain(player: Player): boolean
	-- Mêmes contrôles qu'une arrivée à pied, et pas avant la première pose du tutoriel
	if
		player:GetAttribute("LaneState") ~= "Result"
		or player:GetAttribute("Action") ~= nil
		or not player:GetAttribute("DataReady")
		or not slotOf[player]
		or not Tutorial.canThrowAgain((player:GetAttribute("Tutorial") :: number?) or 0)
	then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local state = frozen[player]
	if state and state.root == root and root.Anchored then
		-- Toujours figé à sa place depuis le lancer : seule la jauge se rouvre (nouvelle heure d'ouverture)
		state.since = os.clock()
		player:SetAttribute("Action", "Holding")
		return true
	end
	-- Plus figé (réapparu) : depuis le hub, une place libre près de lui, comme une arrivée à pied ; bande pleine : il y
	-- reste, comme après GO BACK
	unfreeze(player, true)
	return freeze(player, character, root, humanoid)
end

-- Cette méthode permet de donner les places sans joueur lorsque l'on lance des mannequins de test (Studio).
function SlotService.freeSlots(): { Slot }
	local free = {}
	for index, slot in slots do
		if queue:isFree(index) then
			table.insert(free, slot)
		end
	end
	return free
end

-- Cette méthode permet de brancher l'attribution, la libération des places et le figeage sur la bande lorsque le
-- serveur démarre.
function SlotService.init(builtSlots: { Slot })
	slots = builtSlots
	queue = SlotQueue.new(#builtSlots)
	Players.PlayerAdded:Connect(assign)
	for _, player in Players:GetPlayers() do
		assign(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		frozen[player] = nil
		slotOf[player] = nil
		-- La place libérée passe au plus ancien joueur en attente (#142), reposé dans le hub devant sa base
		local next, index = queue:leave(player)
		if next and index then
			grant(next, index)
			if next.Character and next.Character:FindFirstChild("HumanoidRootPart") then
				next.Character:PivotTo(slots[index].spawn)
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		for player in slotOf do
			watchBand(player)
		end
	end)
end

return SlotService
