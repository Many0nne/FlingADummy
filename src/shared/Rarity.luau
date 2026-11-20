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
	{ name = "Secret", color = Color3.fromRGB(40, 40, 48) },
} :: { Tier }

-- Cette méthode permet de donner la rareté d'indice `index` (bornée) lorsqu'une carte affiche un objet.
function Rarity.get(index: number): Tier
	return Rarity.LIST[math.clamp(index, 1, #Rarity.LIST)]
end

return Rarity
