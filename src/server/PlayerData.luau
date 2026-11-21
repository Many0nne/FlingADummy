-- Données du joueur : argent, Throw Power, équipement, niveaux, record, muet musique et renaissances, portés par des
-- attributs du Player (répliqués au client), recopiés dans les leaderstats ; collection (stock, présentoirs de la base
-- et présentoirs achetés, Index : Shared.Inventory) gardée côté serveur. Le tout est sauvegardé en DataStore (migration
-- des sauvegardes de #13 par Inventory.read). Renaissance (Shared.Rebirth) et remise à zéro de Studio (DebugWipe).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Rebirth = require(ReplicatedStorage.Shared.Rebirth)
local ThrowDummies = require(ReplicatedStorage.Shared.ThrowDummies)
local Training = require(ReplicatedStorage.Shared.Training)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local STORE_NAME = "PlayerData_v2"

local DEFAULTS = {
	Money = 0,
	ThrowPower = GameConfig.START_POWER,
	GearTier = 1,
	TrainLevel = 1,
	TrainExp = 0, -- EXP du niveau d'entraînement en cours (Shared.Training)
	BestDistance = 0,
	Tutorial = 0, -- étapes du tutoriel faites (drapeaux, Shared.Tutorial)
	Draws = 0, -- mannequins de collection gagnés (le premier est garanti : Collection.STARTER)
	MusicOff = false, -- musique de fond coupée (bouton du HUD, Client.Music)
	ThrowTier = 1, -- mannequins à lancer possédés : les ThrowTier premiers du catalogue (Shared.ThrowDummies)
	ThrowEquipped = 1, -- mannequin à lancer équipé (tenu et lancé)
	Rebirths = 0, -- renaissances faites (Shared.Rebirth : CHANCE × 2 chacune)
}

-- Collection d'un joueur : stock, présentoirs, Index (Shared.Inventory)
export type CollectionData = Inventory.Data

local PlayerData = {}

local store: DataStore? = nil
local loaded: { [Player]: boolean } = {}
local collections: { [Player]: CollectionData } = {}
local musicChangedAt: { [Player]: number } = {}
local musicWanted: { [Player]: boolean } = {} -- dernier choix reçu, appliqué à la fin du délai
local musicScheduled: { [Player]: boolean } = {}
local resetListeners: { (Player) -> () } = {} -- prévenus quand la collection d'un joueur est remplacée (DebugWipe)
local MUSIC_COOLDOWN = 0.25 -- s entre deux changements du muet musique (attribut répliqué à tout le serveur)

-- Cette méthode permet de construire la clé DataStore d'un joueur lorsque l'on lit ou écrit ses données.
local function keyOf(player: Player): string
	return "player_" .. player.UserId
end

-- Cette méthode permet de créer les leaderstats Cash et Best, recopiées des attributs, lorsqu'un joueur arrive.
local function setupLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, entry in { { "Cash", "Money" }, { "Best", "BestDistance" } } do
		local value = Instance.new("IntValue")
		value.Name = entry[1]
		value.Value = player:GetAttribute(entry[2]) or 0
		value.Parent = folder
		player:GetAttributeChangedSignal(entry[2]):Connect(function()
			value.Value = player:GetAttribute(entry[2]) or 0
		end)
	end
	folder.Parent = player
end

-- Cette méthode permet de charger les données sauvegardées d'un joueur lorsqu'il arrive ; sans DataStore (Studio
-- sans accès API), le joueur démarre avec les valeurs par défaut et ne sera pas sauvegardé.
local function load(player: Player)
	for key, value in DEFAULTS do
		player:SetAttribute(key, value)
	end
	collections[player] = Inventory.new()
	setupLeaderstats(player)
	-- Studio : attribut FreshPlayer sur Workspace = nouveau joueur (données vierges, rien lu ni sauvegardé)
	local fresh = RunService:IsStudio() and Workspace:GetAttribute("FreshPlayer") == true
	if fresh then
		print("[PlayerData] FreshPlayer : " .. player.Name .. " démarre à zéro, sans sauvegarde")
	end
	if store and not fresh then
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(keyOf(player))
		end)
		if not ok then
			warn("[PlayerData] lecture impossible pour " .. player.Name .. " : " .. tostring(data))
		else
			if type(data) == "table" then
				for key, default in DEFAULTS do
					if type(data[key]) == type(default) then
						player:SetAttribute(key, data[key])
					end
				end
				-- Mannequins à lancer : niveaux bornés au catalogue (sauvegarde ancienne ou catalogue raccourci)
				local owned, equipped = ThrowDummies.sanitize(data.ThrowTier, data.ThrowEquipped)
				player:SetAttribute("ThrowTier", owned)
				player:SetAttribute("ThrowEquipped", equipped)
				-- Renaissances : entier borné (sauvegarde antérieure à #108 : 0)
				player:SetAttribute("Rebirths", Rebirth.read(data.Rebirths))
				-- Sauvegarde antérieure au tutoriel : étapes déduites de la progression
				if type(data.Tutorial) ~= "number" then
					player:SetAttribute("Tutorial", Tutorial.infer(data))
				end
				local collection, sold = Inventory.read(data.Collection)
				collections[player] = collection
				if sold > 0 then
					PlayerData.addMoney(player, sold) -- stock au-delà du plafond : vendu, pas perdu
				end
			end
			loaded[player] = true
		end
	end
	-- Lancer autorisé seulement après le chargement : un gain crédité avant serait écrasé par la sauvegarde lue
	player:SetAttribute("DataReady", true)
end

-- Cette méthode permet de sauvegarder les données d'un joueur lorsqu'il part ou que le serveur s'arrête ; ne fait rien
-- si le chargement avait échoué (on n'écrase pas une sauvegarde par des valeurs par défaut).
local function save(player: Player)
	if not store or not loaded[player] then
		return
	end
	local data = {}
	for key in DEFAULTS do
		data[key] = player:GetAttribute(key)
	end
	local collection = collections[player]
	if collection then
		data.Collection = Inventory.write(collection)
	end
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(keyOf(player), data)
	end)
	if not ok then
		warn("[PlayerData] sauvegarde impossible pour " .. player.Name .. " : " .. tostring(err))
	end
end

-- Cette méthode permet de créditer (ou débiter) de l'argent lorsque la base verse son revenu, qu'un mannequin est
-- revendu ou qu'un achat est validé.
function PlayerData.addMoney(player: Player, amount: number)
	player:SetAttribute("Money", ((player:GetAttribute("Money") :: number?) or 0) + amount)
end

-- Cette méthode permet de donner la collection d'un joueur (modifiable en place, sauvegardée avec ses données)
-- lorsque le serveur tire, pose, retire ou vend un mannequin ; nil avant son arrivée ou après son départ.
function PlayerData.collection(player: Player): CollectionData?
	return collections[player]
end

-- Cette méthode permet de mettre à jour le record du joueur lorsque la distance d'un lancer le dépasse.
function PlayerData.recordDistance(player: Player, distance: number)
	if distance > ((player:GetAttribute("BestDistance") :: number?) or 0) then
		player:SetAttribute("BestDistance", distance)
	end
end

-- Cette méthode permet d'acheter l'équipement d'entraînement suivant lorsque le client le demande (`kind` = "Gear") ;
-- le serveur valide le type, le palier maximal et le solde. Renvoie true si l'achat a eu lieu.
function PlayerData.buyUpgrade(player: Player, kind: any): boolean
	if kind ~= "Gear" then
		return false
	end
	local tier = (player:GetAttribute("GearTier") :: number?) or 1
	local cost = Training.nextGearCost(tier)
	local money = (player:GetAttribute("Money") :: number?) or 0
	if cost == nil or money < cost then
		return false
	end
	player:SetAttribute("Money", money - cost)
	player:SetAttribute("GearTier", tier + 1)
	PlayerData.tutorialStep(player, "BuyGear")
	return true
end

-- Cette méthode permet d'acheter ou d'équiper un mannequin à lancer lorsque le client le demande depuis la boutique
-- (`action` = "Buy" : le suivant seulement, avec l'argent, puis équipé ; "Equip" : un mannequin possédé). Le serveur
-- valide l'action, l'indice, l'ordre, la possession et le solde ; renvoie true si quelque chose a changé.
function PlayerData.throwDummy(player: Player, action: any, index: any): boolean
	if player:GetAttribute("DataReady") ~= true then
		return false
	end
	local owned, equipped =
		ThrowDummies.sanitize(player:GetAttribute("ThrowTier"), player:GetAttribute("ThrowEquipped"))
	local money = (player:GetAttribute("Money") :: number?) or 0
	local result = ThrowDummies.act(owned, equipped, money, action, index)
	if not result then
		return false
	end
	if result.cost > 0 then
		player:SetAttribute("Money", money - result.cost)
	end
	player:SetAttribute("ThrowTier", result.owned)
	player:SetAttribute("ThrowEquipped", result.equipped)
	return true
end

-- Cette méthode permet de donner au joueur les `index` premiers mannequins à lancer et d'équiper le dernier lorsque
-- l'on mesure dans Studio (attribut DebugThrowDummy, contexte Server) : rien n'est payé.
function PlayerData.debugThrowDummy(player: Player, index: any)
	-- Pas avant le chargement : la sauvegarde lue écraserait le don
	if not ThrowDummies.isIndex(index) or player:GetAttribute("DataReady") ~= true then
		return
	end
	local owned = ThrowDummies.sanitize(player:GetAttribute("ThrowTier"), nil)
	player:SetAttribute("ThrowTier", math.max(owned, index))
	player:SetAttribute("ThrowEquipped", index)
end

-- Cette méthode permet de noter une étape du tutoriel faite (« Throw », « Place », « Train », « BuyGear ») lorsque
-- le serveur la constate ; sans effet une fois le tutoriel fini.
function PlayerData.tutorialStep(player: Player, event: string)
	local flags = (player:GetAttribute("Tutorial") :: number?) or 0
	local updated = Tutorial.complete(flags, event)
	if updated ~= flags then
		player:SetAttribute("Tutorial", updated)
	end
end

-- Cette méthode permet de noter le choix du bouton musique (true = coupée) lorsque le client l'envoie ; au plus un
-- changement par MUSIC_COOLDOWN s (attribut répliqué à tout le serveur), le dernier choix reçu appliqué en différé.
function PlayerData.setMusicOff(player: Player, off: any)
	if type(off) ~= "boolean" or player:GetAttribute("DataReady") ~= true then
		return
	end
	musicWanted[player] = off
	if musicScheduled[player] then
		return
	end
	local function apply()
		musicScheduled[player] = nil
		local wanted = musicWanted[player]
		if wanted ~= nil and player.Parent and player:GetAttribute("MusicOff") ~= wanted then
			musicChangedAt[player] = os.clock()
			player:SetAttribute("MusicOff", wanted)
		end
	end
	local delay = MUSIC_COOLDOWN - (os.clock() - (musicChangedAt[player] or -math.huge))
	if delay <= 0 then
		apply()
	else
		musicScheduled[player] = true
		task.delay(delay, apply)
	end
end

-- Cette méthode permet de faire renaître le joueur lorsque le client le demande (fenêtre REBIRTH) : le serveur
-- valide le chargement, l'état (au hub, ni en vol ni jauge ouverte) et la condition (Shared.Rebirth.missing), puis
-- remet la progression à zéro et compte la renaissance ; `onAccepted` est appelé juste avant (arrêt de l'entraînement).
-- Renvoie le nouveau nombre de renaissances, nil si refusée.
function PlayerData.rebirth(player: Player, onAccepted: (() -> ())?): number?
	if player:GetAttribute("DataReady") ~= true then
		return nil
	end
	local state = player:GetAttribute("LaneState")
	if (state ~= nil and state ~= "Ready") or player:GetAttribute("Action") == "Holding" then
		return nil
	end
	local result = Rebirth.apply({
		gearTier = (player:GetAttribute("GearTier") :: number?) or 1,
		money = (player:GetAttribute("Money") :: number?) or 0,
		rebirths = Rebirth.read(player:GetAttribute("Rebirths")),
	})
	if not result then
		return nil
	end
	if onAccepted then
		onAccepted()
	end
	-- Compteur en dernier : l'interface qui le suit lit des valeurs déjà remises à zéro
	for key, value in result do
		if key ~= "Rebirths" then
			player:SetAttribute(key, value)
		end
	end
	player:SetAttribute("Rebirths", result.Rebirths)
	return result.Rebirths
end

-- Cette méthode permet d'être prévenu quand la collection d'un joueur est remplacée (DebugWipe) lorsque un service
-- (la base) doit se reconstruire.
function PlayerData.onReset(listener: (Player) -> ())
	table.insert(resetListeners, listener)
end

-- Cette méthode permet de remettre toute la sauvegarde d'un joueur à l'état d'un nouveau joueur (renaissances,
-- collection, tutoriel et records compris) lorsque l'on teste dans Studio (attribut DebugWipe, #95) ; la sauvegarde
-- vide est écrite à son départ comme d'habitude.
function PlayerData.wipe(player: Player)
	local state = player:GetAttribute("LaneState")
	if
		player:GetAttribute("DataReady") ~= true
		or (state ~= nil and state ~= "Ready")
		or player:GetAttribute("Action") == "Holding"
	then
		-- En vol, en tirage ou jauge ouverte, le lancer en cours créditerait la sauvegarde vide
		print("[PlayerData] DebugWipe refusé : revenir au hub d'abord (LaneState = " .. tostring(state) .. ")")
		return
	end
	for key, value in DEFAULTS do
		player:SetAttribute(key, value)
	end
	collections[player] = Inventory.new()
	for _, listener in resetListeners do
		listener(player)
	end
	print("[PlayerData] DebugWipe : " .. player.Name .. " repart comme un nouveau joueur")
end

-- Cette méthode permet d'ajouter de la Throw Power lorsque l'avatar franchit un niveau d'entraînement.
function PlayerData.addPower(player: Player, amount: number)
	player:SetAttribute("ThrowPower", ((player:GetAttribute("ThrowPower") :: number?) or 0) + amount)
end

-- Cette méthode permet de brancher chargement et sauvegarde sur l'arrivée, le départ et l'arrêt du serveur lorsque
-- le serveur démarre.
function PlayerData.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore indisponible, progression non sauvegardée : " .. tostring(result))
	end
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		loaded[player] = nil
		collections[player] = nil
		musicChangedAt[player] = nil
		musicWanted[player] = nil
		musicScheduled[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			save(player)
		end
	end)
end

return PlayerData
