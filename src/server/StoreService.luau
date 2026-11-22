-- Boutique Robux côté serveur (#160) : attribution des achats (une seule fonction par article, appelée par le vrai reçu
-- et par la simulation de Studio), reçus idempotents (ProcessReceipt : reçu noté dans la sauvegarde, écrite avant
-- PurchaseGranted), passes vérifiés à l'arrivée (UserOwnsGamePassAsync) et mémorisés, boosts minutés décomptés en jeu
-- seulement, chance du serveur (tous les joueurs, non sauvegardée), lancers chanceux, pack de démarrage. Les effets
-- sont lus par les autres services : BaseService (revenu, présentoirs), LaunchService (CHANCE), TrainingService (EXP).
-- Attributs publiés : Passes (« BigBase,VIP »), Boost<type> (fin en temps serveur), LuckyThrows, StarterEnds (fin de
-- l'offre du pack de démarrage en temps serveur) ; ServerLuckEnds sur Workspace.
-- Studio : un article dont l'identifiant Roblox vaut 0 s'achète en simulation (bouton de la fenêtre, ou attribut
-- DebugBuy = « id » ou « id#reçu » sur le joueur, contexte Server).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Store = require(ReplicatedStorage.Shared.Store)
local ThrowDummies = require(ReplicatedStorage.Shared.ThrowDummies)
local PlayerData = require(script.Parent.PlayerData)

local TICK = 1 -- s entre deux avancées des minuteurs

local StoreService = {}

local remote: RemoteEvent? = nil
local serverLuckEnds = 0 -- fin de la chance du serveur (temps serveur)
local simulated = 0 -- compteur des reçus simulés de Studio
local pendingPasses: { [Player]: { Store.Item } } = {} -- passes achetés avant le chargement des données

-- Cette méthode permet de publier l'état d'achat d'un joueur dans ses attributs (passes, fins des boosts, lancers
-- chanceux, fin de l'offre du pack de démarrage) lorsque il est chargé, qu'un achat est attribué ou remis à zéro.
local function publish(player: Player)
	local state = PlayerData.store(player)
	if not state then
		return
	end
	local now = Workspace:GetServerTimeNow()
	player:SetAttribute("Passes", Store.encodePasses(state.passes))
	for kind in Store.BOOSTS do
		local left = state.boosts[kind]
		player:SetAttribute("Boost" .. kind, if left then now + left else nil)
	end
	player:SetAttribute("LuckyThrows", state.lucky)
	local starter = Store.starterLeft(state)
	player:SetAttribute("StarterEnds", if starter then now + starter else nil)
end

-- Cette méthode permet de prévenir le client de l'acheteur (popup) lorsque un achat lui est attribué ; `amount` :
-- argent reçu (argent rapide, pack de démarrage).
local function announce(player: Player, item: Store.Item, amount: number?)
	if remote then
		remote:FireClient(player, "Granted", item.id, amount)
	end
end

-- Cette méthode permet de donner l'argent rapide de `minutes` de revenu (revenu affiché du joueur, boosts compris)
-- lorsque un achat d'argent ou le pack de démarrage est attribué ; renvoie le montant.
local function giveCash(player: Player, minutes: number): number
	local amount = Store.cash(minutes, (player:GetAttribute("Income") :: number?) or 0)
	PlayerData.addMoney(player, amount)
	return amount
end

-- Cette méthode permet d'appliquer un passe possédé (mémorisé, Rainbow Dummy équipé à l'achat) lorsque un achat ou la
-- vérification d'arrivée le donne ; `silent` : sans popup (passe déjà acheté, retrouvé à l'arrivée).
local function grantPass(player: Player, item: Store.Item, silent: boolean?): boolean
	local state = PlayerData.store(player)
	if not state or player:GetAttribute("DataReady") ~= true then
		-- Données pas encore prêtes : appliqué au chargement (ready), le joueur a payé
		local pending = pendingPasses[player] or {}
		table.insert(pending, item)
		pendingPasses[player] = pending
		return false
	end
	if state.passes[item.id] then
		return true
	end
	state.passes[item.id] = true
	if item.id == "Rainbow" and not silent then
		player:SetAttribute("ThrowEquipped", ThrowDummies.RAINBOW)
	end
	publish(player)
	if not silent then
		announce(player, item)
		-- Big Base : présentoirs 31 à 40 utilisables tout de suite, passe sauvegardé avec eux
		task.spawn(PlayerData.saveNow, player)
	end
	return true
end

-- Cette méthode permet d'appliquer un produit acheté (boost, chance du serveur, lancers chanceux, argent rapide, pack
-- de démarrage) lorsque son reçu est attribué pour la première fois ; renvoie true si c'est fait.
local function grantProduct(player: Player, item: Store.Item): boolean
	local state = PlayerData.store(player)
	if not state then
		return false
	end
	local amount: number? = nil
	if item.id == "StarterPack" then
		state.starter = true
		state.lucky = math.min(state.lucky + Store.STARTER.throws, Store.LUCKY_MAX)
		for kind, seconds in Store.STARTER.boosts do
			Store.addBoost(state, kind, seconds)
		end
		amount = giveCash(player, Store.STARTER.minutes)
	elseif item.id == "ServerLuck" then
		local now = Workspace:GetServerTimeNow()
		serverLuckEnds = math.max(serverLuckEnds, now) + (item.seconds or 0)
		Workspace:SetAttribute("ServerLuckEnds", serverLuckEnds)
		if remote then
			remote:FireAllClients("ServerLuck", item.id, player.DisplayName)
		end
	elseif item.boost then
		Store.addBoost(state, item.boost, item.seconds or 0)
	elseif item.throws then
		state.lucky = math.min(state.lucky + item.throws, Store.LUCKY_MAX)
	elseif item.minutes then
		amount = giveCash(player, item.minutes)
	else
		return false
	end
	publish(player)
	announce(player, item, amount)
	return true
end

-- Cette méthode permet d'attribuer un achat de produit une seule fois par reçu (noté puis sauvegardé avant de répondre
-- PurchaseGranted) lorsque ProcessReceipt arrive ou que Studio le simule ; NotProcessedYet si le joueur n'est pas
-- prêt ou que la sauvegarde échoue (Roblox représentera le reçu).
local function purchase(player: Player, item: Store.Item, purchaseId: string): Enum.ProductPurchaseDecision
	local state = PlayerData.store(player)
	if not state or player:GetAttribute("DataReady") ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Sauvegarde pas lue (DataStore en panne) : l'achat serait écrasé au départ ; Studio : joueur neuf de test accepté
	local loaded = PlayerData.isLoaded(player)
	if not loaded and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local granted = Store.applyReceipt(state, purchaseId, function()
		return grantProduct(player, item)
	end)
	if not granted or (loaded and not PlayerData.saveNow(player)) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Cette méthode permet de traiter un reçu Roblox (produit du catalogue, acheteur présent) lorsque MarketplaceService
-- le présente, au premier achat ou à chaque rejeu.
local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local item = Store.byAsset("Product", info.ProductId)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not item or not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return purchase(player, item, tostring(info.PurchaseId))
end

-- Cette méthode permet de simuler l'achat d'un article (même chemin que le vrai reçu ou la vraie fin d'achat de passe)
-- lorsque l'on teste dans Studio ; `purchaseId` rejoue un reçu donné. Renvoie true si l'article existe.
function StoreService.simulate(player: Player, id: any, purchaseId: string?): boolean
	local item = Store.get(id)
	if not item or not RunService:IsStudio() then
		return false
	end
	PlayerData.markSimulated(player) -- rien de ce que donne la simulation n'arrive dans la vraie sauvegarde
	if item.kind == "Pass" then
		local ok = grantPass(player, item)
		print(string.format("[Store] simulation : passe %s pour %s (%s)", item.id, player.Name, tostring(ok)))
	else
		simulated += 1
		local receipt = purchaseId or ("studio-" .. simulated)
		local decision = purchase(player, item, receipt)
		print(
			string.format(
				"[Store] simulation : %s pour %s, reçu %s → %s",
				item.id,
				player.Name,
				receipt,
				decision.Name
			)
		)
	end
	return true
end

-- Cette méthode permet de retrouver à l'arrivée les passes achetés hors de cette session (vérifiés auprès de Roblox,
-- identifiants créés seulement) lorsque les données du joueur sont prêtes.
local function verifyPasses(player: Player)
	for _, item in Store.ITEMS do
		local state = PlayerData.store(player)
		if not state or not player.Parent then
			return
		end
		if item.kind == "Pass" and item.assetId ~= 0 and not state.passes[item.id] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, item.assetId)
			end)
			if ok and owns then
				grantPass(player, item, true)
			end
		end
	end
end

-- Cette méthode permet de donner ce qui agit sur un joueur (passes, boosts en cours, chance du serveur) lorsque un
-- service calcule un multiplicateur ; `lucky` : lancer chanceux utilisé.
local function activeOf(player: Player, lucky: boolean?): Store.Active
	local state = PlayerData.store(player)
	return {
		passes = if state then state.passes else {},
		boosts = if state then state.boosts else {},
		serverLuck = Workspace:GetServerTimeNow() < serverLuckEnds,
		lucky = lucky,
	}
end

-- Cette méthode permet de donner le multiplicateur de revenu de la boutique d'un joueur (2x Money, VIP, boost
-- d'argent) lorsque BaseService recalcule le revenu de sa base.
function StoreService.incomeMultiplier(player: Player): number
	return Store.income(activeOf(player))
end

-- Cette méthode permet de donner le multiplicateur d'EXP de la boutique d'un joueur (Strong Arms, boost
-- d'entraînement) lorsque TrainingService compte une répétition.
function StoreService.trainingMultiplier(player: Player): number
	return Store.training(activeOf(player))
end

-- Cette méthode permet de donner les présentoirs ajoutés par la boutique (Big Base) lorsque BaseService calcule la
-- capacité de la base d'un joueur.
function StoreService.displayBonus(player: Player): number
	local state = PlayerData.store(player)
	return if state then Store.displayBonus(state.passes) else 0
end

-- Cette méthode permet de donner le multiplicateur de CHANCE de la boutique pour un lancer qui part (2x Luck,
-- potions, chance du serveur, lancer chanceux consommé s'il en reste) lorsque LaunchService lance pour un joueur.
function StoreService.launchLuck(player: Player): number
	local state = PlayerData.store(player)
	local lucky = state ~= nil and state.lucky > 0
	if state and lucky then
		state.lucky -= 1
		player:SetAttribute("LuckyThrows", state.lucky)
	end
	return Store.luck(activeOf(player, lucky))
end

-- Cette méthode permet de faire avancer les minuteurs (boosts, temps de jeu du pack de démarrage) des joueurs
-- présents et chargés lorsque l'horloge du serveur tourne ; un boost fini ou une offre passée retire son attribut.
local function tick(dt: number)
	for _, player in Players:GetPlayers() do
		local state = PlayerData.store(player)
		if state and player:GetAttribute("DataReady") == true then
			local offered = Store.starterLeft(state) ~= nil
			for _, kind in Store.tick(state, dt) do
				player:SetAttribute("Boost" .. kind, nil)
			end
			if offered and not Store.starterLeft(state) then
				player:SetAttribute("StarterEnds", nil)
			end
		end
	end
	if serverLuckEnds > 0 and Workspace:GetServerTimeNow() >= serverLuckEnds then
		serverLuckEnds = 0
		Workspace:SetAttribute("ServerLuckEnds", nil)
	end
end

-- Cette méthode permet de suivre un joueur (publication à son chargement, vérification des passes, simulation de
-- Studio par attribut DebugBuy) lorsqu'il arrive.
local function track(player: Player)
	-- Cette méthode permet de publier l'état d'achat et de vérifier les passes lorsque les données du joueur sont prêtes.
	local function ready()
		if player:GetAttribute("DataReady") == true then
			publish(player)
			local pending = pendingPasses[player]
			pendingPasses[player] = nil
			for _, item in pending or {} do
				grantPass(player, item)
			end
			task.spawn(verifyPasses, player)
		end
	end
	player:GetAttributeChangedSignal("DataReady"):Connect(ready)
	ready()
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("DebugBuy"):Connect(function()
			local value = player:GetAttribute("DebugBuy")
			if type(value) ~= "string" then
				return
			end
			player:SetAttribute("DebugBuy", nil)
			local id, receipt = string.match(value, "^([%w_]+)#(.+)$")
			if not StoreService.simulate(player, id or value, receipt) then
				warn("[Store] DebugBuy illisible : " .. value)
			end
		end)
	end
end

-- Cette méthode permet de brancher reçus, fins d'achat de passe, demandes de la fenêtre (simulation de Studio),
-- minuteurs et remise à zéro de Studio lorsque le serveur démarre.
function StoreService.init(storeRemote: RemoteEvent)
	remote = storeRemote
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local item = Store.byAsset("Pass", passId)
		if purchased and item then
			grantPass(player, item)
		end
	end)
	-- Client : « Buy » + identifiant d'un article pas encore créé sur l'expérience, simulé en Studio seulement
	storeRemote.OnServerEvent:Connect(function(player, action, id)
		local item = Store.get(id)
		if action == "Buy" and item and item.assetId == 0 then
			StoreService.simulate(player, id)
		end
	end)
	PlayerData.onReset(publish)
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		pendingPasses[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= TICK then
			tick(elapsed)
			elapsed = 0
		end
	end)
end

return StoreService
