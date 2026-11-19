-- Données du joueur : argent, Throw Power, équipement, niveaux et record, portés par des attributs du Player (répliqués au
-- client), recopiés dans les leaderstats et sauvegardés en DataStore.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Training = require(ReplicatedStorage.Shared.Training)

local STORE_NAME = "PlayerData_v2"

local DEFAULTS = {
	Money = 0,
	ThrowPower = GameConfig.START_POWER,
	GearTier = 1,
	ValueLevel = 1,
	TrainLevel = 1,
	TrainReps = 0,
	BestDistance = 0,
}

local PlayerData = {}

local store: DataStore? = nil
local loaded: { [Player]: boolean } = {}

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
	setupLeaderstats(player)
	if store then
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(keyOf(player))
		end)
		if not ok then
			warn("[PlayerData] lecture impossible pour " .. player.Name .. " : " .. tostring(data))
		else
			if type(data) == "table" then
				for key in DEFAULTS do
					if type(data[key]) == "number" then
						player:SetAttribute(key, data[key])
					end
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
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(keyOf(player), data)
	end)
	if not ok then
		warn("[PlayerData] sauvegarde impossible pour " .. player.Name .. " : " .. tostring(err))
	end
end

-- Cette méthode permet de créditer (ou débiter) de l'argent lorsqu'un lancer se termine ou qu'un achat est validé.
function PlayerData.addMoney(player: Player, amount: number)
	player:SetAttribute("Money", ((player:GetAttribute("Money") :: number?) or 0) + amount)
end

-- Cette méthode permet de mettre à jour le record du joueur lorsque la distance d'un lancer le dépasse.
function PlayerData.recordDistance(player: Player, distance: number)
	if distance > ((player:GetAttribute("BestDistance") :: number?) or 0) then
		player:SetAttribute("BestDistance", distance)
	end
end

-- Cette méthode permet d'acheter le niveau suivant d'une amélioration lorsque le client le demande ; le serveur
-- valide le type, le niveau maximal et le solde. Renvoie true si l'achat a eu lieu.
function PlayerData.buyUpgrade(player: Player, kind: any): boolean
	local attribute, cost
	if kind == "Gear" then
		attribute = "GearTier"
		cost = Training.nextGearCost((player:GetAttribute(attribute) :: number?) or 1)
	elseif kind == "Value" then
		attribute = "ValueLevel"
		cost = Economy.valueCost((player:GetAttribute(attribute) :: number?) or 1)
	else
		return false
	end
	local money = (player:GetAttribute("Money") :: number?) or 0
	if cost == nil or money < cost then
		return false
	end
	player:SetAttribute("Money", money - cost)
	player:SetAttribute(attribute, ((player:GetAttribute(attribute) :: number?) or 1) + 1)
	return true
end

-- Cette méthode permet d'ajouter de la Throw Power lorsque l'avatar termine une répétition d'entraînement.
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
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			save(player)
		end
	end)
end

return PlayerData
