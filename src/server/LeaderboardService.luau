-- Tableaux de scores du hub (#120, Shared.Leaderboard) : top 10 global par OrderedDataStore (un par tableau). Toutes
-- les REFRESH s, le serveur écrit le score de chaque joueur chargé qui a changé (et au départ du joueur), lit le top de
-- chaque tableau puis l'affiche, complété par les valeurs des joueurs du serveur (plus fraîches). Sans accès DataStore
-- (Studio sans accès API) ou en cas d'erreur : repli sur les joueurs du serveur, signalé dans le journal.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Leaderboard = require(ReplicatedStorage.Shared.Leaderboard)
local Props = require(script.Parent.Props)

type Entry = Leaderboard.Entry

local LeaderboardService = {}

local boards: { Props.Scoreboard } = {}
local stores: { [string]: OrderedDataStore } = {}
local tops: { [string]: { Entry } } = {} -- dernier top global lu, par tableau
local global = false -- vrai si la dernière lecture du classement global a réussi pour tous les tableaux
local written: { [Player]: { [string]: number } } = {} -- dernier score écrit, par joueur et par tableau
local names: { [number]: string } = {} -- noms affichés des joueurs absents du serveur (cache)
local fallbackReason: string? = nil -- raison du repli, signalée une fois par changement d'état
-- Joueurs en train de partir (encore dans Players pendant PlayerRemoving) : plus comptés dans les valeurs du serveur
local leaving: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Cette méthode permet de signaler dans le journal le passage au repli sur les joueurs du serveur (ou le retour au
-- classement global) lorsque l'état change, sans répéter le même message à chaque rafraîchissement.
local function report(reason: string?)
	if reason == fallbackReason then
		return
	end
	fallbackReason = reason
	if reason then
		warn("[Leaderboard] repli sur les joueurs du serveur : " .. reason)
	else
		print("[Leaderboard] classement global (OrderedDataStore)")
	end
end

-- Cette méthode permet de donner les valeurs des joueurs chargés du serveur pour le tableau `board` lorsque l'on
-- complète le top global ou qu'on s'en passe.
local function liveEntries(board: Leaderboard.Board): { Entry }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("DataReady") == true and not leaving[player] then
			local value = player:GetAttribute(board.attribute)
			if type(value) == "number" then
				table.insert(list, { userId = player.UserId, value = value, name = player.DisplayName })
			end
		end
	end
	return list
end

-- Cette méthode permet de retrouver les noms affichés des joueurs du top absents du serveur (une requête groupée,
-- mise en cache) lorsque le top global vient d'être lu.
local function resolveNames(entries: { Entry })
	local missing = {}
	for _, entry in entries do
		if not names[entry.userId] and entry.userId > 0 then
			table.insert(missing, entry.userId)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	else
		warn("[Leaderboard] noms des joueurs introuvables : " .. tostring(infos))
	end
end

-- Cette méthode permet d'afficher le classement `entries` sur le tableau `scoreboard` (lignes vides au-delà) et sa
-- portée (tous les serveurs ou ce serveur) lorsque le classement est recalculé.
local function render(scoreboard: Props.Scoreboard, entries: { Entry })
	scoreboard.scope.Text = if global then "TOP 10 · ALL SERVERS" else "TOP 10 · THIS SERVER"
	for index, row in scoreboard.rows do
		local entry = entries[index]
		row.name.Text = if entry then entry.name or names[entry.userId] or "Player" else "-"
		row.value.Text = if entry then Leaderboard.format(scoreboard.board.id, entry.value) else ""
	end
end

-- Cette méthode permet de recalculer et d'afficher tous les tableaux (dernier top global lu, complété par les joueurs
-- du serveur) lorsque le classement est relu, qu'un joueur arrive chargé ou qu'il part ; aucun appel DataStore.
local function renderAll()
	for _, scoreboard in boards do
		local board = scoreboard.board
		local stored = if global then tops[board.id] or {} else {}
		render(scoreboard, Leaderboard.merge(stored, liveEntries(board)))
	end
end

-- Cette méthode permet d'écrire dans chaque classement global le score du joueur qui a changé depuis le dernier
-- écrit lorsque le classement est rafraîchi ou que le joueur part ; rien pour les joueurs de test de Studio.
local function writeScores(player: Player)
	if player.UserId <= 0 or player:GetAttribute("DataReady") ~= true then
		return
	end
	local last = written[player] or {}
	written[player] = last
	for _, board in Leaderboard.BOARDS do
		local store = stores[board.id]
		local score = Leaderboard.score(player:GetAttribute(board.attribute))
		if store and Leaderboard.shouldWrite(last[board.id], score) then
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), score)
			end)
			if ok then
				last[board.id] = score
			else
				report("écriture impossible (" .. board.store .. ") : " .. tostring(err))
			end
		end
	end
end

-- Cette méthode permet de lire le top global de chaque tableau lorsque le classement est rafraîchi ; en cas d'erreur
-- (Studio sans accès API, quota), les tableaux passent sur les joueurs du serveur jusqu'à la lecture suivante.
local function readTops()
	if next(stores) == nil then
		global = false
		return
	end
	local failure: string? = nil
	for _, board in Leaderboard.BOARDS do
		local store = stores[board.id]
		local ok, result = pcall(function()
			local page = store:GetSortedAsync(false, Leaderboard.SIZE):GetCurrentPage()
			local entries: { Entry } = {}
			for _, item in page do
				local userId = tonumber(item.key)
				if userId and type(item.value) == "number" then
					table.insert(entries, { userId = userId, value = item.value })
				end
			end
			return entries
		end)
		if ok then
			tops[board.id] = result
			resolveNames(result)
		else
			failure = "lecture impossible (" .. board.store .. ") : " .. tostring(result)
		end
	end
	global = failure == nil
	report(failure)
end

-- Cette méthode permet d'écrire les scores des joueurs, de relire le top global et de réafficher les tableaux
-- lorsque l'horloge du classement tourne (toutes les REFRESH s).
local function refresh()
	for _, player in Players:GetPlayers() do
		writeScores(player)
	end
	readTops()
	renderAll()
end

-- Cette méthode permet de suivre l'arrivée d'un joueur : ses valeurs entrent dans les tableaux dès ses données
-- chargées.
local function track(player: Player)
	player:GetAttributeChangedSignal("DataReady"):Connect(function()
		if player:GetAttribute("DataReady") == true then
			renderAll()
		end
	end)
end

-- Cette méthode permet d'ouvrir les classements globaux, de brancher arrivées et départs et de lancer le
-- rafraîchissement périodique des tableaux `built` lorsque le serveur démarre.
function LeaderboardService.init(built: { Props.Scoreboard })
	boards = built
	for _, board in Leaderboard.BOARDS do
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.store)
		end)
		if ok then
			stores[board.id] = result
		else
			report("classement indisponible (" .. board.store .. ") : " .. tostring(result))
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Dernier score écrit au départ, puis le joueur n'est plus compté dans les valeurs du serveur
		leaving[player] = true
		renderAll()
		writeScores(player)
		written[player] = nil
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(Leaderboard.REFRESH)
		end
	end)
end

return LeaderboardService
