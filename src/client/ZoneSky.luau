-- Ciel des zones (#97) : quand la caméra du joueur arrive dans une zone de nuit (Shared.Zones, la Galaxy), son client fait
-- tomber la nuit (ciel étoilé par défaut de Roblox à minuit), puis rend le plein jour en revenant. Réglage local : la
-- lumière du serveur (Server.CourseBuilder) ne change pas, chaque joueur voit le ciel de sa propre caméra.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Zones = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Zones"))

local ZoneSky = {}

local CHECK_PERIOD = 0.25 -- s entre deux lectures de la position de la caméra
local NIGHT_CLOCK = 0 -- minuit : étoiles du ciel par défaut
local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local night = false
local dayClock: number? = nil -- heure du serveur, rendue au retour du jour
local tween: Tween? = nil

-- Cette méthode permet de faire tomber la nuit ou de rendre le jour (fondu de l'heure) lorsque la caméra entre dans
-- une zone de nuit ou en sort.
local function setNight(value: boolean)
	if value == night then
		return
	end
	night = value
	if value then
		dayClock = Lighting.ClockTime
	end
	if tween then
		tween:Cancel()
	end
	local target = if value then NIGHT_CLOCK else (dayClock or Lighting.ClockTime)
	local fade = TweenService:Create(Lighting, FADE, { ClockTime = target })
	tween = fade
	fade:Play()
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
		if camera then
			setNight(Zones.isNight(camera.CFrame.Position.Z))
		end
	end)
end

return ZoneSky
