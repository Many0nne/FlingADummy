-- Raretés affichées sur les cartes d'objets (nom coloré sous le nom de l'objet, comme « Commun » dans les jeux de
-- référence). Partagé avec la collection (#13) : l'indice 1 est le plus courant.
local Rarity = {}

export type Tier = { name: string, color: Color3 }

Rarity.LIST = {
	{ name = "Common", color = Color3.fromRGB(235, 235, 235) },
	{ name = "Uncommon", color = Color3.fromRGB(90, 220, 90) },
	{ name = "Rare", color = Color3.fromRGB(70, 160, 255) },
	{ name = "Epic", color = Color3.fromRGB(190, 90, 255) },
	{ name = "Legendary", color = Color3.fromRGB(255, 190, 40) },
	{ name = "Mythic", color = Color3.fromRGB(255, 70, 110) },
	{ name = "Secret", color = Color3.fromRGB(110, 255, 225) },
	-- Au-delà de Secret (#94), comme les paliers Divin, Céleste, Cosmique de Throw a Seed : cotes de 5 × 10^6 à 10^14
	-- (10^16-10^17 en taille Giant)
	{ name = "Divine", color = Color3.fromRGB(255, 240, 140) },
	{ name = "Celestial", color = Color3.fromRGB(255, 140, 235) },
	{ name = "Ethereal", color = Color3.fromRGB(170, 140, 255) },
	{ name = "Infinity", color = Color3.fromRGB(255, 110, 30) },
} :: { Tier }

Rarity.SECRET = 7 -- premier palier joué avec la séquence complète du secret (Shared.RevealPlan)

-- Cette méthode permet de donner la rareté d'indice `index` (bornée) lorsqu'une carte affiche un objet.
function Rarity.get(index: number): Tier
	return Rarity.LIST[math.clamp(index, 1, #Rarity.LIST)]
end

return Rarity
