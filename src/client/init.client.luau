-- Amorçage du client : HUD, charge du canon, caméra de vol, branchés sur les remotes du serveur.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local FlightCamera = require(script.FlightCamera)
local Hud = require(script.Hud)
local LaunchInput = require(script.LaunchInput)

local player = Players.LocalPlayer
local remotes = Remotes.wait()

Hud.init(player, function(kind)
	remotes.BuyUpgrade:FireServer(kind)
end)
LaunchInput.init(player, remotes)
FlightCamera.init(player)

remotes.LaunchStarted.OnClientEvent:Connect(function(model: Model)
	if typeof(model) ~= "Instance" then
		return
	end
	Hud.setDummy(model)
	FlightCamera.follow(model)
end)
remotes.LaunchResult.OnClientEvent:Connect(Hud.showResult)
