-- Amorçage du client : HUD, objectif, poses des avatars, lancer, caméra et écran de vol (CHANCE finale à l'arrêt),
-- effets des crashs, tirage du mannequin de collection et pose dans la base, branchés sur les remotes du serveur.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local CharacterPoser = require(script.CharacterPoser)
local Effects = require(script.Effects)
local FlightCamera = require(script.FlightCamera)
local FlightView = require(script.FlightView)
local Hud = require(script.Hud)
local Objective = require(script.Objective)
local Prize = require(script.Prize)
local ThrowCinematic = require(script.ThrowCinematic)
local ThrowController = require(script.ThrowController)

local player = Players.LocalPlayer
local remotes = Remotes.wait()

-- Cette méthode permet d'arrêter l'entraînement lorsque le joueur clique sur STOP ou demande un saut.
local function stopTraining()
	if player:GetAttribute("Action") == "Training" then
		remotes.StopTraining:FireServer()
	end
end

Hud.onBuy = function(kind: string)
	remotes.BuyUpgrade:FireServer(kind)
end
Hud.init(player, stopTraining)
local gui = Hud.screen()
Objective.init(player, gui)
FlightView.init(gui)
Prize.init(player, remotes, gui)
CharacterPoser.init()
ThrowController.init(player, remotes, gui)
FlightCamera.init(player)
Effects.init(player, remotes.Impact)
UserInputService.JumpRequest:Connect(stopTraining)

local prizeToken = 0 -- invalide un tirage programmé si le couloir redevient prêt ou qu'un autre vol part

remotes.LaunchStarted.OnClientEvent:Connect(function(model: Model)
	if typeof(model) ~= "Instance" then
		return
	end
	prizeToken += 1
	ThrowCinematic.finish()
	CharacterPoser.handOff()
	FlightView.show(model)
	FlightCamera.follow(model)
	Effects.setFlying(model)
end)

-- Cette méthode permet de lancer le tirage du mannequin gagné lorsque la CHANCE finale a été assez vue ; en Studio,
-- écrit le délai mesuré entre l'arrêt du mannequin et l'apparition de la silhouette.
local function playPrize(result: any)
	local stoppedAt = FlightView.stoppedAt()
	FlightView.hideTag()
	Prize.play(result)
	if RunService:IsStudio() and stoppedAt then
		local now = os.clock()
		print(string.format("[Landing] silhouette t=%.3f, arrêt → silhouette %.2f s", now, now - stoppedAt))
	end
end

remotes.LaunchResult.OnClientEvent:Connect(function(result)
	Effects.setFlying(nil)
	prizeToken += 1
	local current = prizeToken
	local delay = FlightView.settle(result)
	task.delay(delay, function()
		if current == prizeToken then
			playPrize(result)
		end
	end)
end)
player:GetAttributeChangedSignal("LaneState"):Connect(function()
	if player:GetAttribute("LaneState") == "Ready" then
		prizeToken += 1
		FlightView.hide()
	end
end)
