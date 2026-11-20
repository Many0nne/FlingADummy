-- Amorçage du serveur : groupes de collision, gabarits maillés du mannequin, décor (et cibles des objectifs), remotes, données joueur, places du lobby, entraînement et lancers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
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
LaunchService.init(remotes, course.dummies)

remotes.BuyUpgrade.OnServerEvent:Connect(function(player, kind)
	PlayerData.buyUpgrade(player, kind)
end)
