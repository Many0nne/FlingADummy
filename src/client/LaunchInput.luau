-- Charge et tir : maintenir clic gauche, toucher ou Espace fait courir l'aiguille ; relâcher envoie la valeur au
-- serveur. Actif seulement quand le couloir est prêt.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gauge = require(Shared:WaitForChild("Gauge"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Hud = require(script.Parent.Hud)

local LaunchInput = {}

local player: Player
local remotes: Remotes.Remotes
local chargingWith: Enum.UserInputType? = nil
local chargeStart = 0
local current = 0

-- Cette méthode permet de démarrer la charge lorsque le joueur appuie et que son couloir est prêt ; renvoie true si
-- la charge a démarré.
local function begin(inputType: Enum.UserInputType): boolean
	if chargingWith or player:GetAttribute("LaneState") ~= "Ready" then
		return false
	end
	chargingWith = inputType
	chargeStart = os.clock()
	current = 0
	return true
end

-- Cette méthode permet de tirer avec la valeur courante de la jauge lorsque le joueur relâche l'entrée qui charge.
local function release(inputType: Enum.UserInputType)
	if chargingWith ~= inputType then
		return
	end
	chargingWith = nil
	remotes.Launch:FireServer(current)
end

-- Cette méthode permet de brancher souris, toucher et Espace sur la charge lorsque le client démarre.
function LaunchInput.init(localPlayer: Player, createdRemotes: Remotes.Remotes)
	player = localPlayer
	remotes = createdRemotes

	UserInputService.InputBegan:Connect(function(input, processed)
		local kind = input.UserInputType
		if not processed and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			begin(kind)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		-- Le clavier est relâché par l'action Espace : une autre touche relâchée ne doit pas tirer
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			release(kind)
		end
	end)

	-- Espace passe par une action prioritaire : pendant la charge, elle ne fait pas sauter le personnage
	ContextActionService:BindActionAtPriority("ChargeCannon", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			return if begin(input.UserInputType) then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
		elseif state == Enum.UserInputState.End and chargingWith == input.UserInputType then
			release(input.UserInputType)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)

	RunService.RenderStepped:Connect(function()
		if chargingWith then
			current = Gauge.value(os.clock() - chargeStart)
			Hud.setGauge(current)
		end
	end)
end

return LaunchInput
