-- Tableaux de scores du hub (#120, Shared.Leaderboard) : top 10 global par OrderedDataStore (un par tableau). Toutes
-- les REFRESH s, le serveur écrit le score de chaque joueur dont la sauvegarde est chargée s'il a changé (et à son
-- départ ou à l'arrêt du serveur), lit le top de chaque tableau puis l'affiche, complété par les valeurs des joueurs du
-- serveur (plus fraîches). Sans accès DataStore (Studio sans accès API) ou en cas d'erreur : repli sur les joueurs du
-- serveur, signalé dans le journal.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Leaderboard = require(ReplicatedStorage.Shared.Leaderboard)
local PlayerData = require(script.Parent.PlayerData)
local Props = require(script.Parent.Props)

type Entry = Leaderboard.Entry

local LeaderboardService = {}

local READ_MARGIN = 8 -- lignes lues en plus du top : remplacent un joueur présent dont la valeur a baissé
local UNKNOWN = "Player" -- nom d'un joueur introuvable (compte supprimé, service indisponible)

local boards: { Props.Scoreboard } = {}
local stores: { [string]: OrderedDataStore } = {}
local tops: { [string]: { Entry } } = {} -- dernier top global lu, par tableau
local global = false -- vrai si la dernière lecture du classement global a réussi pour tous les tableaux
local written: { [Player]: { [string]: number } } = {} -- dernier score écrit, par joueur et par tableau
local names: { [number]: string } = {} -- noms affichés des joueurs absents du serveur (cache, introuvables compris)
local fallbackReason: string? = nil -- raison du repli, signalée une fois par changement d'état
local namesWarned = false -- échec de la recherche des noms déjà signalé
-- Joueurs en train de partir (encore dans Players pendant PlayerRemoving) : plus comptés ni écrits par le
-- rafraîchissement
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
-- mise en cache, introuvables compris) lorsque le top global vient d'être lu.
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
	if not (ok and type(infos) == "table") then
		if not namesWarned then
			namesWarned = true
			warn("[Leaderboard] noms des joueurs introuvables : " .. tostring(infos))
		end
		return -- service indisponible : nouvel essai à la lecture suivante
	end
	for _, info in infos do
		names[info.Id] = info.DisplayName
	end
	-- Comptes absents de la réponse (supprimés) : plus redemandés
	for _, userId in missing do
		names[userId] = names[userId] or UNKNOWN
	end
end

-- Cette méthode permet d'afficher le classement `entries` sur le tableau `scoreboard` (lignes vides au-delà) et sa
-- portée (tous les serveurs ou ce serveur) lorsque le classement est recalculé.
local function render(scoreboard: Props.Scoreboard, entries: { Entry })
	scoreboard.scope.Text = if global then "TOP 10 · ALL SERVERS" else "TOP 10 · THIS SERVER"
	for index, row in scoreboard.rows do
		local entry = entries[index]
		row.name.Text = if entry then entry.name or names[entry.userId] or UNKNOWN else "-"
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
-- écrit, lorsque le classement est rafraîchi ou (`final`) que le joueur part ; seulement si sa sauvegarde a été lue
-- (sinon ses valeurs par défaut écraseraient son vrai score), jamais pour les joueurs de test de Studio. Renvoie la
-- raison d'un échec d'écriture, nil sinon.
local function writeScores(player: Player, final: boolean?): string?
	if player.UserId <= 0 or not PlayerData.isLoaded(player) or (leaving[player] and not final) then
		return nil
	end
	local last = written[player] or {}
	if not final then
		written[player] = last
	end
	local failure: string? = nil
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
				failure = "écriture impossible (" .. board.store .. ") : " .. tostring(err)
			end
		end
	end
	return failure
end

-- Cette méthode permet de lire le top global de chaque tableau (avec une marge de lignes, pour remplacer un joueur
-- présent dont la valeur a baissé) lorsque le classement est rafraîchi ; renvoie la raison d'un échec, nil sinon :
-- les tableaux passent alors sur les joueurs du serveur jusqu'à la lecture suivante.
local function readTops(): string?
	if next(stores) == nil then
		global = false
		return "classements globaux indisponibles"
	end
	local failure: string? = nil
	local count = math.min(Leaderboard.SIZE + READ_MARGIN + #Players:GetPlayers(), 100)
	for _, board in Leaderboard.BOARDS do
		local store = stores[board.id]
		local ok, result = pcall(function()
			local page = store:GetSortedAsync(false, count):GetCurrentPage()
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
	return failure
end

-- Cette méthode permet d'écrire les scores des joueurs, de relire le top global et de réafficher les tableaux
-- lorsque l'horloge du classement tourne (toutes les REFRESH s) ; un échec d'écriture ou de lecture est signalé une
-- fois.
local function refresh()
	local failure: string? = nil
	for _, player in Players:GetPlayers() do
		failure = writeScores(player) or failure
	end
	failure = readTops() or failure
	report(failure)
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

-- Cette méthode permet de retirer des tableaux un joueur qui part et d'écrire ses derniers scores lorsqu'il quitte le
-- serveur ou que le serveur s'arrête.
local function depart(player: Player)
	if leaving[player] then
		return
	end
	leaving[player] = true
	renderAll()
	local failure = writeScores(player, true)
	if failure then
		warn("[Leaderboard] " .. failure)
	end
	written[player] = nil
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
	Players.PlayerRemoving:Connect(depart)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			depart(player)
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(Leaderboard.REFRESH)
		end
	end)
end

return LeaderboardService
