-- Contrôles tactiles (#19) : sur écran tactile, le joystick et le bouton de saut se cachent quand le joueur ne peut pas
-- bouger (figé sur la bande, vol, résultat, tirage : Shared.TouchLayout.movementLocked). Un toucher n'importe où sur
-- l'écran lance alors le mannequin ou passe le tirage, sans être pris par le joystick. Ils restent à l'entraînement : le
-- bouton de saut y arrête la séance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TouchLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TouchLayout"))

local TouchControls = {}

-- Cette méthode permet de brancher l'affichage des contrôles tactiles sur l'état du joueur lorsque le client démarre ;
-- sans effet sans écran tactile.
function TouchControls.init(player: Player)
	if not UserInputService.TouchEnabled then
		return
	end
	local found = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
	if not found then
		warn("[TouchControls] PlayerModule introuvable : joystick toujours affiché")
		return
	end
	local ok, controls = pcall(function()
		return (require(found :: any) :: any):GetControls()
	end)
	if not ok or not controls then
		warn("[TouchControls] contrôles indisponibles : " .. tostring(controls))
		return
	end
	local locked: boolean? = nil
	-- Cette méthode permet de cacher ou rendre les contrôles lorsque l'action, l'état du couloir ou le tirage changent.
	local function update()
		local now = TouchLayout.movementLocked(
			player:GetAttribute("Action") :: string?,
			player:GetAttribute("LaneState") :: string?,
			player:GetAttribute("PrizePhase") :: string?
		)
		if now == locked then
			return
		end
		locked = now
		if now then
			controls:Disable()
		else
			controls:Enable()
		end
	end
	for _, name in { "Action", "LaneState", "PrizePhase" } do
		player:GetAttributeChangedSignal(name):Connect(update)
	end
	update()
end

return TouchControls
