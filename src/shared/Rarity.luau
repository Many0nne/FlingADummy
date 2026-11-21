-- Raretés affichées sur les cartes d'objets (nom coloré sous le nom de l'objet, comme « Commun » dans les jeux de
-- référence). Partagé avec la collection (#13) : l'indice 1 est le plus courant.
local Rarity = {}

-- `income` : revenu ($/s, taille normale) du plus courant et du plus rare de ses mannequins (Shared.DummyFamilies) ;
-- × 2 dans une rareté, × 3 de la plus rentable à la moins rentable de la suivante (#15 : un nouveau mannequin rare se
-- sent sur le compteur de revenu), soit × 6 d'une rareté à l'autre
export type Tier = { name: string, color: Color3, income: { number } }

Rarity.LIST = {
	{ name = "Common", color = Color3.fromRGB(235, 235, 235), income = { 4, 8 } },
	{ name = "Uncommon", color = Color3.fromRGB(90, 220, 90), income = { 25, 50 } },
	{ name = "Rare", color = Color3.fromRGB(70, 160, 255), income = { 150, 300 } },
	{ name = "Epic", color = Color3.fromRGB(190, 90, 255), income = { 900, 1800 } },
	{ name = "Legendary", color = Color3.fromRGB(255, 190, 40), income = { 5500, 11000 } },
	{ name = "Mythic", color = Color3.fromRGB(255, 70, 110), income = { 33000, 66000 } },
	{ name = "Secret", color = Color3.fromRGB(110, 255, 225), income = { 200000, 400000 } },
	-- Au-delà de Secret (#94), comme les paliers Divin, Céleste, Cosmique de Throw a Seed : cotes de 5 × 10^6 à 10^14
	-- (10^16-10^17 en taille Giant)
	{ name = "Divine", color = Color3.fromRGB(255, 240, 140), income = { 1.2e6, 2.4e6 } },
	{ name = "Celestial", color = Color3.fromRGB(255, 140, 235), income = { 7.5e6, 15e6 } },
	{ name = "Ethereal", color = Color3.fromRGB(170, 140, 255), income = { 45e6, 90e6 } },
	{ name = "Infinity", color = Color3.fromRGB(255, 110, 30), income = { 270e6, 540e6 } },
} :: { Tier }

Rarity.SECRET = 7 -- premier palier joué avec la séquence complète du secret (Shared.RevealPlan)

-- Cette méthode permet de donner la rareté d'indice `index` (bornée) lorsqu'une carte affiche un objet.
function Rarity.get(index: number): Tier
	return Rarity.LIST[math.clamp(index, 1, #Rarity.LIST)]
end

return Rarity
