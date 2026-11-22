-- Tableaux de scores du hub (#120, Shared.Leaderboard) : top 10 global par OrderedDataStore (un par tableau). Toutes
-- les REFRESH s, le serveur relit le top de chaque tableau, écrit le score de chaque joueur dont la sauvegarde a été
-- lue s'il a changé (et à son départ ou à l'arrêt du serveur), puis affiche le top complété par les valeurs des
-- joueurs du serveur (plus fraîches). Sans accès DataStore (Studio sans accès API) ou en cas d'erreur : repli du
-- tableau concerné sur les joueurs du serveur, signalé dans le journal.
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
local CLOSE_WAIT = 20 -- s au plus d'attente des dernières écritures à l'arrêt du serveur

local boards: { Props.Scoreboard } = {}
local stores: { [string]: OrderedDataStore } = {}
local tops: { [string]: { Entry } } = {} -- dernier top global lu, par tableau
local globals: { [string]: boolean } = {} -- tableaux dont la dernière lecture du classement global a réussi
local written: { [Player]: { [string]: number } } = {} -- dernier score écrit, par joueur et par tableau
-- Joueurs dont la sauvegarde a été lue, relevé à leur chargement (PlayerData l'oublie à leur départ)
local eligible: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local names: { [number]: string } = {} -- noms affichés des joueurs absents du serveur (cache, introuvables compris)
local fallbackReason: string? = nil -- raison du repli, signalée une fois par changement d'état
local namesWarned = false -- échec de la recherche des noms déjà signalé
-- Joueurs en train de partir (encore dans Players pendant PlayerRemoving) : plus comptés ni écrits par le
-- rafraîchissement
local leaving: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local pending = 0 -- départs dont les écritures sont en cours (attendus à l'arrêt du serveur)
local busy: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- écriture en cours, par joueur
local writeWarning: string? = nil -- dernier échec d'écriture signalé (une fois par changement)

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
	local global = globals[scoreboard.board.id] == true
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
		local stored = if globals[board.id] then tops[board.id] or {} else {}
		render(scoreboard, Leaderboard.merge(stored, liveEntries(board)))
	end
end

-- Cette méthode permet de donner le score que le classement `board` connaît pour le joueur `userId` (lu dans le
-- dernier top) lorsque l'on décide s'il faut l'écrire ; nil s'il n'y figure pas.
local function storedScore(board: Leaderboard.Board, userId: number): number?
	local top = tops[board.id]
	if top then
		for _, entry in top do
			if entry.userId == userId then
				return entry.value
			end
		end
	end
	return nil
end

-- Cette méthode permet d'écrire dans chaque classement global le score du joueur qui a changé, lorsque le classement
-- est rafraîchi ou (`final`) que le joueur part ; seulement si sa sauvegarde a été lue (sinon ses valeurs par défaut
-- écraseraient son vrai score), jamais pour les joueurs de test de Studio. Renvoie la raison d'un échec, nil sinon.
local function writeScores(player: Player, final: boolean?): string?
	if player.UserId <= 0 or not eligible[player] or (leaving[player] and not final) then
		return nil
	end
	-- Une écriture à la fois par joueur : celle du départ passe après celle du rafraîchissement en cours
	while busy[player] do
		task.wait(0.1)
	end
	busy[player] = true
	local last = written[player] or {}
	if not final then
		written[player] = last
	end
	local failure: string? = nil
	for _, board in Leaderboard.BOARDS do
		-- Le rafraîchissement laisse au départ les écritures d'un joueur qui part pendant qu'il écrit
		if leaving[player] and not final then
			break
		end
		local store = stores[board.id]
		local score = Leaderboard.score(player:GetAttribute(board.attribute))
		local known = last[board.id] or storedScore(board, player.UserId)
		if store and Leaderboard.shouldWrite(known, score) then
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
	busy[player] = nil
	return failure
end

-- Cette méthode permet de lire le top global de chaque tableau (avec une marge de lignes, pour remplacer un joueur
-- présent dont la valeur a baissé) lorsque le classement est rafraîchi ; un tableau dont la lecture échoue passe sur
-- les joueurs du serveur jusqu'à la lecture suivante. Renvoie la raison d'un échec, nil sinon.
local function readTops(): string?
	local failure: string? = nil
	local count = math.min(Leaderboard.SIZE + READ_MARGIN + #Players:GetPlayers(), 100)
	for _, board in Leaderboard.BOARDS do
		local store = stores[board.id]
		if not store then
			globals[board.id] = false
			failure = "classement indisponible (" .. board.store .. ")"
			continue
		end
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
		globals[board.id] = ok
		if ok then
			tops[board.id] = result
			resolveNames(result)
		else
			failure = "lecture impossible (" .. board.store .. ") : " .. tostring(result)
		end
	end
	return failure
end

-- Cette méthode permet de relire le top global, d'écrire les scores des joueurs et de réafficher les tableaux
-- lorsque l'horloge du classement tourne (toutes les REFRESH s) ; un échec est signalé une fois.
local function refresh()
	report(readTops())
	local failure: string? = nil
	for _, player in Players:GetPlayers() do
		failure = writeScores(player) or failure
	end
	-- Écriture refusée (quota) : les tableaux gardent le classement global, seul l'écrit attend le tour suivant
	if failure ~= writeWarning then
		writeWarning = failure
		if failure then
			warn("[Leaderboard] " .. failure .. " (nouvel essai au prochain rafraîchissement)")
		end
	end
	renderAll()
end

-- Cette méthode permet de suivre l'arrivée d'un joueur : ses valeurs entrent dans les tableaux dès ses données
-- chargées, et ses scores pourront être écrits si sa sauvegarde a été lue.
local function track(player: Player)
	-- Cette méthode permet de relever le chargement du joueur lorsque DataReady passe à vrai (ou l'est déjà).
	local function ready()
		if player:GetAttribute("DataReady") == true then
			eligible[player] = PlayerData.isLoaded(player)
			renderAll()
		end
	end
	player:GetAttributeChangedSignal("DataReady"):Connect(ready)
	ready()
end

-- Cette méthode permet de retirer des tableaux un joueur qui part et d'écrire ses derniers scores lorsqu'il quitte le
-- serveur ou que le serveur s'arrête.
local function depart(player: Player)
	if leaving[player] then
		return
	end
	leaving[player] = true
	pending += 1
	renderAll()
	local failure = writeScores(player, true)
	if failure then
		warn("[Leaderboard] " .. failure)
	end
	written[player] = nil
	pending -= 1
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
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(depart)
	-- Arrêt : derniers scores de chaque joueur écrits en parallèle, puis attente des départs encore en cours
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(depart, player)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < CLOSE_WAIT do
			task.wait(0.1)
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
