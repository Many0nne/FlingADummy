-- Amorçage du serveur : groupes de collision, gabarits maillés du mannequin, décor (et cibles des objectifs), remotes,
-- données joueur, places du lobby, bases (collection et revenu), entraînement et lancers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BaseService = require(script.BaseService)
local CollisionGroups = require(script.CollisionGroups)
local CourseBuilder = require(script.CourseBuilder)
local DummyAssets = require(script.DummyAssets)
local LaunchService = require(script.LaunchService)
local PlayerData = require(script.PlayerData)
local SlotService = require(script.SlotService)
local TrainingService = require(script.TrainingService)

Workspace.Gravity = GameConfig.GRAVITY
CollisionGroups.setup()
task.spawn(DummyAssets.init)
local course = CourseBuilder.build()
local remotes = Remotes.create()
PlayerData.init()
SlotService.init(course.slots)
TrainingService.init(course.slots, remotes.StopTraining)
BaseService.init(course.slots, remotes.PlaceDummy, remotes.Inventory)
LaunchService.init(remotes, course.dummies)

remotes.BuyUpgrade.OnServerEvent:Connect(function(player, kind)
	PlayerData.buyUpgrade(player, kind)
end)
remotes.SetMusic.OnServerEvent:Connect(function(player, off)
	PlayerData.setMusicOff(player, off)
end)
remotes.ThrowDummy.OnServerEvent:Connect(function(player, action, index)
	PlayerData.throwDummy(player, action, index)
end)

-- Studio : DebugThrowDummy (indice du catalogue, contexte Server) donne et équipe ce mannequin à lancer (mesures)
if RunService:IsStudio() then
	-- Cette méthode permet de suivre l'attribut DebugThrowDummy d'un joueur lorsqu'il arrive (ou est déjà là).
	local function watchDebugThrowDummy(player: Player)
		player:GetAttributeChangedSignal("DebugThrowDummy"):Connect(function()
			local value = player:GetAttribute("DebugThrowDummy")
			if value ~= nil then
				player:SetAttribute("DebugThrowDummy", nil)
				PlayerData.debugThrowDummy(player, value)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchDebugThrowDummy)
	for _, player in Players:GetPlayers() do
		watchDebugThrowDummy(player)
	end
end
