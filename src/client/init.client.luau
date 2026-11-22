-- Amorçage du client : HUD, objectif, poses des avatars, lancer, caméra et écran de vol (CHANCE finale à l'arrêt),
-- effets des crashs et des comportements en vol, pièces mobiles des pièges, tirage du mannequin de collection (et
-- annonces des tirages rares) et pose dans la base, animation des mannequins de collection, stands du hub (boutique des
-- mannequins à lancer), construction des bases qui montent de palier et taille de leur texte, musique de fond, ciel de
-- nuit de la Galaxy, contrôles tactiles cachés quand le joueur ne peut pas bouger, branchés sur les remotes du serveur.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Announce = require(script.Announce)
local BaseFx = require(script.BaseFx)
local BoostButton = require(script.BoostButton)
local CharacterPoser = require(script.CharacterPoser)
local DummyFx = require(script.DummyFx)
local Effects = require(script.Effects)
local FlightCamera = require(script.FlightCamera)
local FlightFx = require(script.FlightFx)
local FlightView = require(script.FlightView)
local Hud = require(script.Hud)
local HubShops = require(script.HubShops)
local LaunchGhost = require(script.LaunchGhost)
local Music = require(script.Music)
local Objective = require(script.Objective)
local PhotoCamera = require(script.PhotoCamera)
local Prize = require(script.Prize)
local SlotWait = require(script.SlotWait)
local ThrowCinematic = require(script.ThrowCinematic)
local ThrowController = require(script.ThrowController)
local TouchControls = require(script.TouchControls)
local TrapMotion = require(script.TrapMotion)
local ZoneSky = require(script.ZoneSky)

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
Hud.onMusicToggle = Music.toggle
Music.onChanged = Hud.setMusicOff
Hud.init(player, stopTraining, remotes)
local gui = Hud.screen()
BoostButton.init(player, remotes.TrainingBoost, gui, { trainBar = Hud.trainBar(), popup = Hud.popup })
Objective.init(player, gui)
SlotWait.init(player, gui)
FlightView.init(gui)
Prize.init(player, remotes, gui)
-- Annonces des tirages rares : en attente pendant le vol et le tirage du joueur local (pas de résultat gâché)
Announce.init(remotes.Announce, gui, function()
	local state = player:GetAttribute("LaneState")
	return Prize.isShowing() or state == "Flying" or state == "Result"
end, Hud.reserveTop, Hud.isLevelPopupShown)
CharacterPoser.init()
DummyFx.init()
HubShops.onShop = Hud.openDummyShop
HubShops.init()
BaseFx.init()
ThrowController.init(player, remotes, gui)
FlightCamera.init(player)
LaunchGhost.init(player)
-- Lâcher anticipé (#144) : le décoratif part dès le marqueur Release, sans attendre l'aller-retour du serveur ; la
-- caméra de vol, le coup de champ de vision et le souffle partent avec lui
ThrowController.onReleased = function(gauge: number)
	-- Studio : DebugNoAnticipate (attribut de Workspace) garde l'ancien départ, pour comparer
	if RunService:IsStudio() and Workspace:GetAttribute("DebugNoAnticipate") == true then
		return
	end
	local visual, scale = CharacterPoser.released()
	if visual and LaunchGhost.anticipate(visual, scale, gauge) then
		CharacterPoser.forgetReleased()
		ThrowCinematic.finish()
		FlightCamera.follow(visual, LaunchGhost.torso)
		Effects.thrown(visual:GetPivot().Position)
	end
end
FlightFx.init()
Effects.init(player, remotes.Impact)
TrapMotion.init()
ZoneSky.init()
-- Studio : cadrage des prises de vue des planches de référence (#121, attribut PhotoShot de Workspace)
if RunService:IsStudio() then
	PhotoCamera.init()
end
Music.init(player, remotes)
UserInputService.JumpRequest:Connect(stopTraining)
-- Joystick et bouton de saut cachés quand le joueur ne peut pas bouger : un toucher n'importe où lance (#19)
task.spawn(TouchControls.init, player)

local prizeToken = 0 -- invalide un tirage programmé si le couloir redevient prêt ou qu'un autre vol part

remotes.LaunchStarted.OnClientEvent:Connect(function(model: Model, launch: any)
	if typeof(model) ~= "Instance" then
		return
	end
	prizeToken += 1
	ThrowCinematic.finish()
	CharacterPoser.handOff()
	-- Départ anticipé sur le plan du vol : pas de mannequin figé à l'apparition (#117), recalage du décoratif parti au
	-- lâcher (#144) ; sans retarder l'écran de vol si le torse se fait attendre
	task.spawn(LaunchGhost.start, model, launch)
	FlightView.show(model)
	FlightCamera.follow(model, LaunchGhost.torso)
	Effects.setFlying(model)
end)

-- Cette méthode permet de lancer le tirage du mannequin gagné lorsque la CHANCE finale a été assez vue ; en Studio,
-- écrit le délai mesuré entre l'arrêt du mannequin et l'apparition de la silhouette.
local function playPrize(result: any)
	local stoppedAt, estimated = FlightView.stoppedAt()
	FlightView.hideTag()
	Prize.play(result)
	if RunService:IsStudio() and stoppedAt then
		local now = os.clock()
		print(
			string.format(
				"[Landing] silhouette t=%.3f, arrêt → silhouette %.2f s%s",
				now,
				now - stoppedAt,
				if estimated then " (arrêt estimé)" else ""
			)
		)
	end
end

-- Lancer refusé par le serveur : le décoratif parti au lâcher s'efface (#144)
remotes.LaunchRefused.OnClientEvent:Connect(LaunchGhost.refuse)

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
