-- Tutoriel court, toute la boucle une fois, dans l'ordre des références : Lancer → Poser le mannequin gagné (bouton
-- AUTO) → S'entraîner (un niveau) → Acheter le premier équipement, puis plus aucun objectif affiché. L'état est un
-- masque de drapeaux (attribut `Tutorial` du joueur, sauvegardé) : une étape faite dans le désordre compte quand même,
-- et l'étape affichée est la première qui reste à faire. Aussi : choix du palier proposé par le popup « NEW GEAR! ».
local Tutorial = {}

Tutorial.STEPS = { "Throw", "Place", "Train", "BuyGear" }

-- Le bit 8 servait à l'ancienne étape « améliorer le mannequin » (retirée) : un joueur qui l'avait faite a forcément
-- fini les autres, son tutoriel reste fini.
local FLAG = { Throw = 1, Train = 2, BuyGear = 4, Place = 8 }
Tutorial.DONE = 15 -- tous les drapeaux

-- Cette méthode permet d'enregistrer une étape faite (`event` : « Throw », « Place », « Train », « BuyGear »)
-- lorsque le serveur la constate ; un achat d'équipement vaut aussi les étapes d'avant (la boucle est comprise).
function Tutorial.complete(flags: number, event: string): number
	local flag = FLAG[event]
	if not flag then
		return flags
	end
	if event == "BuyGear" then
		flag = bit32.bor(flag, FLAG.Throw, FLAG.Place, FLAG.Train)
	elseif event == "Place" then
		flag = bit32.bor(flag, FLAG.Throw) -- on ne pose qu'un mannequin gagné en lançant
	end
	return bit32.bor(flags, flag)
end

-- Cette méthode permet de donner l'étape à afficher (la première qui reste à faire) lorsque l'objectif est recalculé ;
-- nil une fois le tutoriel fini.
function Tutorial.current(flags: number): string?
	for _, step in Tutorial.STEPS do
		if bit32.band(flags, FLAG[step]) == 0 then
			return step
		end
	end
	return nil
end

-- Cette méthode permet de déduire le tutoriel déjà fait d'une sauvegarde antérieure au tutoriel lorsqu'un ancien
-- joueur arrive : un ancien joueur ne revoit pas les étapes qu'il a déjà faites (« poser » reste à faire : les
-- anciennes sauvegardes n'ont pas de base).
function Tutorial.infer(data: { [string]: any }): number
	local flags = 0
	if type(data.BestDistance) == "number" and data.BestDistance > 0 then
		flags = Tutorial.complete(flags, "Throw")
	end
	if type(data.TrainLevel) == "number" and data.TrainLevel > 1 then
		flags = Tutorial.complete(flags, "Train")
	end
	if type(data.GearTier) == "number" and data.GearTier > 1 then
		flags = bit32.bor(flags, FLAG.BuyGear, FLAG.Throw, FLAG.Train)
	end
	return flags
end

-- Cette méthode permet de choisir le palier d'équipement que propose le popup « NEW GEAR! » lorsque l'argent ou
-- l'équipement changent : le palier suivant s'il est abordable et que le joueur n'a pas fermé son popup, sinon nil.
function Tutorial.gearOffer(owned: number, cost: number?, money: number, dismissed: { [number]: boolean }): number?
	local tier = owned + 1
	if cost == nil or money < cost or dismissed[tier] then
		return nil
	end
	return tier
end

return Tutorial
