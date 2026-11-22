-- Entraînement : l'invite « Lift » de l'appareil (devant la base du joueur) place l'avatar sur le podium ; il soulève
-- un mannequin en boucle, chaque répétition donne l'EXP de l'équipement (attributs TrainLevel / TrainExp) et chaque
-- niveau franchi donne sa Throw Power (Shared.Training). L'invite est masquée pendant la séance. L'appareil s'habille
-- aux couleurs du Training Gear de son propriétaire (Shared.BaseLook, #92). Bouton « 2x TRAINING! » (#119) : le serveur
-- tient le calendrier de chaque joueur (Shared.TrainingBoost), annonce les apparitions (remote TrainingBoost), valide le
-- clic et double l'EXP des répétitions pendant le bonus (attribut TrainBoostEnds, en temps serveur, pour le HUD).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Training = require(ReplicatedStorage.Shared.Training)
local TrainingBoost = require(ReplicatedStorage.Shared.TrainingBoost)
local CourseBuilder = require(script.Parent.CourseBuilder)
local PlayerData = require(script.Parent.PlayerData)
local SlotService = require(script.Parent.SlotService)

local TrainingService = {}

type Session = { elapsed: number, prompt: ProximityPrompt }

local sessions: { [Player]: Session } = {}
-- Calendrier du bouton « 2x TRAINING! » de chaque joueur, gardé d'une séance à l'autre (temps d'entraînement cumulé)
local boosts: { [Player]: TrainingBoost.State } = {}
local boostRemote: RemoteEvent? = nil
local random = Random.new()

-- Cette méthode permet de tirer un nombre dans [0, 1) lorsque le calendrier du bonus tire son prochain intervalle.
local function rng(): number
	return random:NextNumber()
end

-- Cette méthode permet d'écrire une ligne de suivi du bonus dans la sortie lorsque l'on teste dans Studio.
local function trace(player: Player, message: string)
	if RunService:IsStudio() then
		print(string.format("[Boost] %s %s (horloge %.2f s)", player.Name, message, boosts[player].clock))
	end
end

-- Cette méthode permet de donner (ou créer) le calendrier du bonus d'un joueur lorsque sa séance avance ou qu'il clique.
local function boostOf(player: Player): TrainingBoost.State
	local state = boosts[player]
	if not state then
		state = TrainingBoost.new(rng)
		boosts[player] = state
	end
	return state
end

-- Cette méthode permet de clore la séance d'un joueur (invite de son appareil réaffichée) lorsque l'entraînement
-- s'arrête, que l'avatar disparaît ou que le joueur part.
local function endSession(player: Player)
	local session = sessions[player]
	if session then
		sessions[player] = nil
		session.prompt.Enabled = true
	end
	-- Bouton et bonus annulés avec la séance (pas de report) ; le calendrier repart d'un intervalle complet
	local boost = boosts[player]
	if boost and TrainingBoost.stop(boost, rng) then
		trace(player, "annulé : séance arrêtée")
		if boostRemote and player.Parent then
			boostRemote:FireClient(player, "Cancel")
		end
	end
	player:SetAttribute("TrainBoostEnds", nil)
end

-- Cette méthode permet de valider le clic sur l'apparition `id` du bouton « 2x TRAINING! » lorsque le client l'envoie
-- (ou que l'attribut DebugBoostClaim le simule dans Studio) ; accepté, le bonus démarre et le HUD reçoit sa fin.
local function claimBoost(player: Player, id: unknown)
	local boost = boosts[player]
	if not sessions[player] or not boost then
		return -- pas de séance : aucun bouton à l'écran
	end
	local ok, refusal = TrainingBoost.claim(boost, id)
	if ok then
		player:SetAttribute("TrainBoostEnds", Workspace:GetServerTimeNow() + GameConfig.BOOST_TIME)
		trace(player, "clic accepté #" .. tostring(id))
	else
		trace(player, string.format("clic refusé #%s (%s)", tostring(id), tostring(refusal)))
	end
end

-- Cette méthode permet de rendre la main à l'avatar (désancré, état libre) lorsque l'entraînement s'arrête.
function TrainingService.stop(player: Player)
	if player:GetAttribute("Action") ~= "Training" then
		return
	end
	endSession(player)
	player:SetAttribute("Action", nil)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
	end
end

-- Cette méthode permet de démarrer l'entraînement lorsque le joueur active l'invite de SON appareil et que son lancer
-- précédent est fini.
function TrainingService.start(player: Player)
	local slot = SlotService.getSlot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- Ni pendant une séance, ni figé sur la bande de lancer (il doit d'abord lancer)
	if not slot or not root or player:GetAttribute("Action") ~= nil then
		return
	end
	-- Pas avant le chargement des données : il écraserait les répétitions faites entre-temps
	if player:GetAttribute("LaneState") ~= "Ready" or player:GetAttribute("DataReady") ~= true then
		return
	end
	-- Debout sur le podium, dos au râtelier ; ancré pour que la boucle d'animation ne le fasse pas dériver
	character:PivotTo(slot.station)
	root.Anchored = true
	sessions[player] = { elapsed = 0, prompt = slot.prompt }
	slot.prompt.Enabled = false
	player:SetAttribute("Action", "Training")
end

-- Cette méthode permet de compter une répétition (EXP × `multiplier` du bonus, niveau, Throw Power au passage de
-- niveau) lorsque REP_TIME s'est écoulé.
local function completeRep(player: Player, multiplier: number)
	local progress, power = Training.completeRep({
		level = (player:GetAttribute("TrainLevel") :: number?) or 1,
		exp = (player:GetAttribute("TrainExp") :: number?) or 0,
	}, (player:GetAttribute("GearTier") :: number?) or 1, multiplier)
	-- Puissance d'abord : le client la lit déjà à jour quand il annonce le niveau
	if power > 0 then
		PlayerData.addPower(player, power)
	end
	player:SetAttribute("TrainExp", progress.exp)
	player:SetAttribute("TrainLevel", progress.level)
	if power > 0 then
		PlayerData.tutorialStep(player, "Train")
	end
end

-- Cette méthode permet d'annoncer une apparition, un bouton raté ou la fin du bonus lorsque l'horloge
-- d'entraînement du joueur avance de `dt` s pendant sa séance.
local function stepBoost(player: Player, dt: number)
	local boost = boostOf(player)
	local event = TrainingBoost.advance(boost, dt, rng)
	if event == "Offer" then
		trace(player, "apparition #" .. boost.lastId)
		if boostRemote then
			-- Fin de l'affichage en temps serveur : le client cache le bouton quand la fenêtre de clic se ferme
			local deadline = Workspace:GetServerTimeNow() + GameConfig.BOOST_OFFER_TIME
			boostRemote:FireClient(player, "Offer", boost.lastId, deadline)
		end
	elseif event == "Missed" then
		trace(player, "raté #" .. boost.lastId)
	elseif event == "Ended" then
		trace(player, "bonus fini")
		player:SetAttribute("TrainBoostEnds", nil)
	end
end

-- Cette méthode permet de démarrer ou d'arrêter l'entraînement par attribut lorsque l'on teste dans Studio sans
-- input : DebugTrain = true démarre la séance sur l'appareil du joueur, false l'arrête ; DebugBoost = true fait
-- apparaître le bouton « 2x TRAINING! » à la prochaine image de la séance ; DebugBoostClaim = numéro simule le clic
-- envoyé par le client (même validation que le remote : clic tardif ou en double refusé).
local function watchDebugTrain(player: Player)
	player:GetAttributeChangedSignal("DebugBoost"):Connect(function()
		if player:GetAttribute("DebugBoost") ~= true then
			return
		end
		player:SetAttribute("DebugBoost", nil)
		local boost = boostOf(player)
		if not boost.offer and not boost.boostEndsAt then
			boost.nextAt = boost.clock
		end
	end)
	player:GetAttributeChangedSignal("DebugBoostClaim"):Connect(function()
		local id = player:GetAttribute("DebugBoostClaim")
		if id == nil then
			return
		end
		player:SetAttribute("DebugBoostClaim", nil)
		claimBoost(player, id)
	end)
	player:GetAttributeChangedSignal("DebugTrain"):Connect(function()
		local value = player:GetAttribute("DebugTrain")
		if typeof(value) ~= "boolean" then
			return
		end
		player:SetAttribute("DebugTrain", nil)
		if value then
			TrainingService.start(player)
		else
			TrainingService.stop(player)
		end
	end)
end

-- Cette méthode permet d'habiller l'appareil de la place du joueur à son Training Gear (confettis à chaque achat, pas
-- au chargement) dès que sa place est connue ; son départ rend à l'appareil le premier palier.
local function dressStation(player: Player, slots: { CourseBuilder.Slot })
	local connections: { RBXScriptConnection } = {}
	local slot: CourseBuilder.Slot? = nil
	-- Cette méthode permet de suivre le Training Gear du joueur lorsque SlotService lui a donné une place.
	local function follow()
		local index = player:GetAttribute("Slot")
		if slot or typeof(index) ~= "number" or not slots[index] then
			return
		end
		local owned = slots[index]
		slot = owned
		local shown = (player:GetAttribute("GearTier") :: number?) or 1
		CourseBuilder.styleStation(owned, shown)
		table.insert(
			connections,
			player:GetAttributeChangedSignal("GearTier"):Connect(function()
				local tier = (player:GetAttribute("GearTier") :: number?) or 1
				if tier > shown and player:GetAttribute("DataReady") == true then
					CourseBuilder.celebrate(owned.trainer.burst)
				end
				shown = tier
				CourseBuilder.styleStation(owned, tier)
			end)
		)
	end
	-- SlotService pose l'attribut Slot dans son propre PlayerAdded : suivi sans attente bloquante (lobby plein : jamais)
	table.insert(connections, player:GetAttributeChangedSignal("Slot"):Connect(follow))
	follow()
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(gone)
			if gone ~= player then
				return
			end
			for _, connection in connections do
				connection:Disconnect()
			end
			if slot then
				CourseBuilder.styleStation(slot, 1)
			end
		end)
	)
end

-- Cette méthode permet de brancher les invites des appareils (un par place), leur habillage au Training Gear du
-- joueur, l'arrêt demandé par le client et la boucle des répétitions lorsque le serveur démarre.
function TrainingService.init(slots: { CourseBuilder.Slot }, stopRemote: RemoteEvent, boost: RemoteEvent)
	boostRemote = boost
	boost.OnServerEvent:Connect(claimBoost)
	Players.PlayerAdded:Connect(function(player)
		dressStation(player, slots)
	end)
	for _, player in Players:GetPlayers() do
		dressStation(player, slots)
	end
	for _, slot in slots do
		slot.prompt.Triggered:Connect(function(player)
			if SlotService.getSlot(player) == slot then
				TrainingService.start(player)
			end
		end)
	end
	stopRemote.OnServerEvent:Connect(TrainingService.stop)
	Players.PlayerRemoving:Connect(function(player)
		endSession(player)
		boosts[player] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		for player, session in sessions do
			if not player.Character or player:GetAttribute("Action") ~= "Training" then
				endSession(player) -- avatar réapparu (Action remise à zéro) ou disparu
				continue
			end
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				TrainingService.stop(player) -- avatar mort : pas de répétitions pendant la réapparition
				continue
			end
			stepBoost(player, dt)
			session.elapsed += dt
			if session.elapsed >= GameConfig.REP_TIME then
				session.elapsed -= GameConfig.REP_TIME
				completeRep(player, TrainingBoost.multiplier(boostOf(player)))
			end
		end
	end)
	if RunService:IsStudio() then
		Players.PlayerAdded:Connect(watchDebugTrain)
		for _, player in Players:GetPlayers() do
			watchDebugTrain(player)
		end
	end
end

return TrainingService
