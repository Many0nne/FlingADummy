-- Règle de pose d'un mannequin hors tutoriel (#70), partagée par le client (bouton AUTO, retour au joueur) et le
-- serveur (BaseService, qui valide) : tutoriel (première pose à la main), rien à poser, trop loin de la base, base
-- pleine, ou pose possible. Les messages courts expliquent pourquoi rien n'est posé.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Tutorial = require(Shared:WaitForChild("Tutorial"))

export type Status = "ok" | "tutorial" | "none" | "far" | "full"

export type Input = {
	tutorialStep: number?, -- attribut « Tutorial » du joueur
	hasEntry: boolean, -- un mannequin à poser (tenu ou dernier gagné)
	near: boolean, -- le joueur est dans sa base ou tout près
	hasTarget: boolean, -- Inventory.autoTarget a trouvé un présentoir
}

local PlaceRule = {}

PlaceRule.MESSAGES = {
	far = "Too far! Walk back to your base to place it.",
	full = "Base full! Buy a display or sell at the SELL stand.",
	waiting = "Walk back to your base to place your new dummy!",
} :: { [string]: string }

-- Cette méthode permet de savoir si la première pose du tutoriel (à la main, sur un présentoir) reste à faire
-- lorsque le client ou le serveur décident de poser avec AUTO ou un présentoir.
function PlaceRule.firstPending(tutorialStep: number?): boolean
	return Tutorial.current(tutorialStep or 0) == "Place"
end

-- Cette méthode permet de donner l'état de la pose AUTO lorsque le joueur la demande ou que le bouton se met à jour ;
-- l'ordre des tests est celui du retour au joueur (la cause la plus simple à corriger d'abord).
function PlaceRule.status(input: Input): Status
	if PlaceRule.firstPending(input.tutorialStep) then
		return "tutorial"
	elseif not input.hasEntry then
		return "none"
	elseif not input.near then
		return "far"
	elseif not input.hasTarget then
		return "full"
	end
	return "ok"
end

-- Cette méthode permet de donner le message à afficher lorsque la pose n'a pas eu lieu ; nil si rien à dire (pose
-- possible, tutoriel qui a son propre panneau, ou rien à poser).
function PlaceRule.message(status: Status): string?
	return PlaceRule.MESSAGES[status]
end

return PlaceRule
