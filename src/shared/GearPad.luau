-- Pad d'amélioration de l'équipement (#159, référence 09 : pad « barre de bronze $100K » à côté de la barre de traction) :
-- panneau « NEXT: Iron Dummy », « +45 EXP / rep », prix sur une plaque verte si abordable, rouge sinon, « MAX » au
-- dernier palier. Logique pure (testée) ; Server.CourseBuilder construit le pad, Client.Hud branche ses invites.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Training = require(Shared:WaitForChild("Training"))

local GearPad = {}

GearPad.BUY_TAG = "GearPadBuy" -- invites « Upgrade » (attributs Slot, Price, Maxed), activées par le client du propriétaire
GearPad.VIEW_TAG = "GearPadView" -- invites « View all » (attribut Slot) : ouvrent la fenêtre Training Gear

-- Afford : abordable (plaque verte) ; Short : argent insuffisant (rouge) ; Idle : place libre (neutre) ; Max : dernier palier
export type Tone = "Afford" | "Short" | "Idle" | "Max"
export type Panel = { title: string, gain: string, price: string, tone: Tone, cost: number? }

-- Cette méthode permet de donner le contenu du panneau du pad lorsque son propriétaire possède le palier `tier` et
-- `money` (nil : place libre) ; au dernier palier, « MAX » et l'équipement possédé, sans prix.
function GearPad.panel(tier: number, money: number?): Panel
	local cost = Training.nextGearCost(tier)
	if cost == nil then
		local gear = Training.gear(tier)
		return { title = "MAX GEAR", gain = gear.name, price = "MAX", tone = "Max", cost = nil }
	end
	local nextGear = Training.gear(tier + 1)
	local tone: Tone = if money == nil then "Idle" elseif money >= cost then "Afford" else "Short"
	return {
		title = "NEXT: " .. nextGear.name,
		gain = "+" .. Format.short(nextGear.gain) .. " EXP / rep",
		price = Format.money(cost),
		tone = tone,
		cost = cost,
	}
end

return GearPad
