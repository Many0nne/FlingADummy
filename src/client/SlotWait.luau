-- Message du joueur sans place (#142) : quand le lobby est plein, il attend qu'une base se libère (attribut SlotWait posé
-- par Server.SlotService, retiré dès qu'une place lui est donnée).
local UIKit = require(script.Parent.UIKit)

local SlotWait = {}

-- Cette méthode permet d'afficher le message d'attente en haut de l'écran lorsque le joueur n'a pas de place, et de
-- le retirer quand une place lui est donnée.
function SlotWait.init(player: Player, gui: ScreenGui)
	local label = UIKit.text({
		Name = "SlotWait",
		Text = "Server full, waiting for a free base…",
		TextSize = 30,
		TextColor3 = UIKit.COLORS.yellow,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(640, 44),
		Visible = false,
		Parent = gui,
	})
	local function update()
		label.Visible = player:GetAttribute("SlotWait") == true
	end
	player:GetAttributeChangedSignal("SlotWait"):Connect(update)
	update()
end

return SlotWait
