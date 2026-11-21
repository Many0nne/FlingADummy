-- Ciel des zones (#97) : quand la caméra du joueur arrive dans une zone de nuit (Shared.Zones, la Galaxy), son client fait
-- tomber la nuit (ciel étoilé par défaut de Roblox à minuit), puis rend le plein jour en revenant (sens du fondu :
-- Shared.SkyClock). Réglage local : la lumière du serveur ne change pas, chaque joueur voit le ciel de sa caméra. Pendant
-- un tirage (Client.Prize, ciel assombri par Client.RevealFx), le module ne touche à rien et reprend à la fin.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkyClock = require(Shared:WaitForChild("SkyClock"))
local Zones = require(Shared:WaitForChild("Zones"))

local ZoneSky = {}

local CHECK_PERIOD = 0.25 -- s entre deux lectures de la position de la caméra
local REVEAL_EFFECT = "RevealDark" -- assombrissement d'un tirage rare (Client.RevealFx) : le ciel lui appartient
local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

-- Ciel voulu au dernier fondu ; nil = inconnu (fondu interrompu par un tirage) : le prochain passage le refait
local night: boolean? = false
local dayClock: number? = nil -- heure du serveur, rendue au retour du jour
local tween: Tween? = nil

-- Cette méthode permet de faire tomber la nuit ou de rendre le jour (fondu de l'heure) lorsque la caméra entre dans
-- une zone de nuit ou en sort, ou qu'un fondu interrompu doit être refait.
local function setNight(value: boolean)
	if value == night then
		return
	end
	night = value
	-- Heure du jour gardée à la première nuit seulement (jamais une heure intermédiaire d'un fondu)
	if dayClock == nil then
		dayClock = Lighting.ClockTime
	end
	if tween then
		tween:Cancel()
	end
	local target = SkyClock.target(Lighting.ClockTime, value, dayClock :: number)
	local fade = TweenService:Create(Lighting, FADE, { ClockTime = target })
	tween = fade
	fade:Play()
end

-- Cette méthode permet de savoir si un tirage tient le ciel (phase de tirage en cours ou ciel assombri) lorsque l'on
-- veut changer l'heure : on attend alors sa fin.
local function revealOwnsSky(): boolean
	local player = Players.LocalPlayer
	return (player and player:GetAttribute("PrizePhase") ~= nil) or Lighting:FindFirstChild(REVEAL_EFFECT) ~= nil
end

-- Cette méthode permet de suivre la caméra et de régler le ciel de sa zone lorsque le client démarre.
function ZoneSky.init()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_PERIOD then
			return
		end
		elapsed = 0
		local camera = Workspace.CurrentCamera
		if revealOwnsSky() then
			-- Le tirage assombrit le ciel : notre fondu s'arrête et sera refait à la fin du tirage
			if tween then
				tween:Cancel()
				tween = nil
				night = nil
			end
		elseif camera then
			setNight(Zones.isNight(camera.CFrame.Position.Z))
		end
	end)
end

return ZoneSky
