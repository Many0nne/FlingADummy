-- Amorçage du client : HUD, poses des avatars, lancer, caméra et écran de vol, effets des crashs, résultat,
-- branchés sur les remotes du serveur.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local CharacterPoser = require(script.CharacterPoser)
local Effects = require(script.Effects)
local FlightCamera = require(script.FlightCamera)
local FlightView = require(script.FlightView)
local Hud = require(script.Hud)
local ResultScreen = require(script.ResultScreen)
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
FlightView.init(gui)
ResultScreen.init(gui)
CharacterPoser.init()
ThrowController.init(player, remotes, gui)
FlightCamera.init(player)
Effects.init(player, remotes.Impact)
UserInputService.JumpRequest:Connect(stopTraining)

remotes.LaunchStarted.OnClientEvent:Connect(function(model: Model)
	if typeof(model) ~= "Instance" then
		return
	end
	ThrowCinematic.finish()
	CharacterPoser.handOff()
	FlightView.show(model)
	FlightCamera.follow(model)
	Effects.setFlying(model)
end)
remotes.LaunchResult.OnClientEvent:Connect(function(result)
	FlightView.settle()
	Effects.setFlying(nil)
	ResultScreen.show(result)
end)
player:GetAttributeChangedSignal("LaneState"):Connect(function()
	if player:GetAttribute("LaneState") == "Ready" then
		FlightView.hide()
		ResultScreen.hide()
	end
end)
