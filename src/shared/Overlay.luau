-- Superposition des éléments du haut de l'écran (#87, #62) : une seule règle pour savoir qui se tait quand plusieurs
-- veulent s'afficher. Une fenêtre ouverte (boutique, collection, Index) masque l'offre « NEW GEAR! » / « NEW DUMMY! »
-- et le texte de l'objectif ; un popup (palier, bandeau d'annonce) les masque aussi ; l'offre affichée masque le texte
-- de l'objectif (même place, en haut au centre). Tout revient à la fermeture : les appelants ne rejouent pas le son.
local Overlay = {}

export type State = {
	windowOpen: boolean, -- une fenêtre du HUD est ouverte
	popupShown: boolean, -- un popup de palier ou un bandeau d'annonce occupe le haut de l'écran
	offerShown: boolean?, -- le popup d'offre est affiché (sans effet sur l'offre elle-même)
}

-- Cette méthode permet de savoir si le popup d'offre a le droit de s'afficher lorsque l'offre est recalculée.
function Overlay.offer(state: State): boolean
	return not state.windowOpen and not state.popupShown
end

-- Cette méthode permet de savoir si le texte de l'objectif a le droit de s'afficher lorsque l'objectif est dessiné ;
-- la flèche du tutoriel, elle, reste (elle désigne le bouton à cliquer dans la fenêtre ou le popup).
function Overlay.objective(state: State): boolean
	return not state.windowOpen and not state.popupShown and not state.offerShown
end

return Overlay
