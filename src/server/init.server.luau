-- Amorçage du serveur : groupes de collision, décor, remotes, données joueur, couloirs et lancers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CollisionGroups = require(script.CollisionGroups)
local CourseBuilder = require(script.CourseBuilder)
local LaneService = require(script.LaneService)
local LaunchService = require(script.LaunchService)
local PlayerData = require(script.PlayerData)

Workspace.Gravity = GameConfig.GRAVITY
CollisionGroups.setup()
local lanes = CourseBuilder.build()
local remotes = Remotes.create()
PlayerData.init()
LaneService.init(lanes)
LaunchService.init(remotes)

remotes.BuyUpgrade.OnServerEvent:Connect(function(player, kind)
	PlayerData.buyUpgrade(player, kind)
end)
