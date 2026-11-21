-- Superposition du haut de l'écran (#87, #62) : une seule règle pour savoir qui se tait quand plusieurs éléments
-- veulent la même place. Une fenêtre ouverte (boutique, collection, Index) masque l'offre « NEW GEAR! » /
-- « NEW DUMMY! » et le texte de l'objectif ; le bandeau d'annonce (même place que l'offre) les masque aussi ; un popup de
-- palier (« LEVEL UP! », plusieurs fois par séance d'entraînement) ne masque que le texte, l'offre restant cliquable ;
-- l'offre affichée fait passer le texte sous elle. Tout revient à la fermeture : les appelants ne rejouent pas le son.
local Overlay = {}

export type State = {
	windowOpen: boolean, -- une fenêtre du HUD est ouverte
	bannerShown: boolean?, -- un bandeau d'annonce occupe le haut de l'écran
	popupShown: boolean?, -- un popup de palier est à l'écran
	offerShown: boolean?, -- le popup d'offre est affiché (sans effet sur l'offre elle-même)
}

-- Place du texte de l'objectif : masqué, en haut au centre, ou sous le popup d'offre
export type ObjectivePlace = "Hidden" | "Top" | "BelowOffer"

-- Cette méthode permet de savoir si le popup d'offre a le droit de s'afficher lorsque l'offre est recalculée.
function Overlay.offer(state: State): boolean
	return not state.windowOpen and not state.bannerShown
end

-- Cette méthode permet de placer le texte de l'objectif lorsque l'objectif est dessiné ; la flèche du tutoriel, elle,
-- reste (elle désigne le bouton à cliquer dans la fenêtre ou le popup).
function Overlay.objective(state: State): ObjectivePlace
	if state.windowOpen or state.bannerShown or state.popupShown then
		return "Hidden"
	end
	return if state.offerShown then "BelowOffer" else "Top"
end

return Overlay
