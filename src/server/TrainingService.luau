-- Entraînement : l'invite « Train » du poste place l'avatar sur le tapis ; il soulève un mannequin en boucle, chaque
-- répétition ajoute la Throw Power de son équipement et remplit les niveaux (attributs TrainLevel / TrainReps).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Training = require(ReplicatedStorage.Shared.Training)
local PlayerData = require(script.Parent.PlayerData)
local SlotService = require(script.Parent.SlotService)

local TrainingService = {}

local timers: { [Player]: number } = {}

-- Cette méthode permet de rendre la main à l'avatar (désancré, état libre) lorsque l'entraînement s'arrête.
function TrainingService.stop(player: Player)
	if player:GetAttribute("Action") ~= "Training" then
		return
	end
	timers[player] = nil
	player:SetAttribute("Action", nil)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
	end
end

-- Cette méthode permet de démarrer l'entraînement lorsque le joueur active l'invite de SON poste et que son lancer
-- précédent est fini.
function TrainingService.start(player: Player)
	local slot = SlotService.getSlot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not slot or not root or player:GetAttribute("Action") == "Training" then
		return
	end
	if player:GetAttribute("LaneState") ~= "Ready" then
		return
	end
	-- Debout sur le tapis, face à la piste ; ancré pour que la boucle d'animation ne le fasse pas dériver
	character:PivotTo(slot.station)
	root.Anchored = true
	timers[player] = 0
	player:SetAttribute("Action", "Training")
end

-- Cette méthode permet de compter une répétition (puissance, niveau) lorsque REP_TIME s'est écoulé.
local function completeRep(player: Player)
	local gear = Training.gear((player:GetAttribute("GearTier") :: number?) or 1)
	PlayerData.addPower(player, gear.gain)
	local progress = Training.addRep({
		level = (player:GetAttribute("TrainLevel") :: number?) or 1,
		reps = (player:GetAttribute("TrainReps") :: number?) or 0,
	})
	player:SetAttribute("TrainReps", progress.reps)
	player:SetAttribute("TrainLevel", progress.level)
end

-- Cette méthode permet de brancher les invites des postes (un par place), l'arrêt demandé par le client et la boucle des
-- répétitions lorsque le serveur démarre.
function TrainingService.init(slots: { any }, stopRemote: RemoteEvent)
	for _, slot in slots do
		slot.prompt.Triggered:Connect(function(player)
			if SlotService.getSlot(player) == slot then
				TrainingService.start(player)
			end
		end)
	end
	stopRemote.OnServerEvent:Connect(TrainingService.stop)
	Players.PlayerRemoving:Connect(function(player)
		timers[player] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		for player, elapsed in timers do
			if not player.Character or player:GetAttribute("Action") ~= "Training" then
				timers[player] = nil
				continue
			end
			elapsed += dt
			if elapsed >= GameConfig.REP_TIME then
				elapsed -= GameConfig.REP_TIME
				completeRep(player)
			end
			timers[player] = elapsed
		end
	end)
end

return TrainingService
