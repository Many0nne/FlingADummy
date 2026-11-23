-- Contrôles tactiles (#19) : sur écran tactile, le joystick et le bouton de saut se cachent quand le joueur ne peut pas
-- bouger (figé sur la bande, vol, résultat, tirage : Shared.TouchLayout.movementLocked). Un toucher n'importe où sur
-- l'écran lance alors le mannequin ou passe le tirage, sans être pris par le joystick, et le bouton de saut ne recouvre
-- plus l'écran de vol (en bas à droite). Ils restent à l'entraînement : le bouton de saut y arrête la séance.
local GuiService = game:GetService("GuiService")
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
	-- Cette méthode permet de cacher ou rendre les contrôles lorsque l'action, l'état du couloir ou le tirage changent.
	local function update()
		GuiService.TouchControlsEnabled = not TouchLayout.movementLocked(
			player:GetAttribute("Action") :: string?,
			player:GetAttribute("LaneState") :: string?,
			player:GetAttribute("PrizePhase") :: string?
		)
	end
	for _, name in { "Action", "LaneState", "PrizePhase" } do
		player:GetAttributeChangedSignal(name):Connect(update)
	end
	update()
end

return TouchControls
