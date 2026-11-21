-- Superposition du haut de l'écran : fenêtres, popups, offre « NEW GEAR! » et texte de l'objectif (#87, #62).
return function(T, Loader)
	local Overlay = Loader.new():require("src/shared/Overlay")

	T.describe("Overlay.offer", function()
		T.it("écran libre : l'offre s'affiche", function()
			T.expectEqual(Overlay.offer({ windowOpen = false, popupShown = false }), true)
		end)
		T.it("une fenêtre ouverte (vente, My Dummies, Index, boutiques) masque l'offre", function()
			T.expectEqual(Overlay.offer({ windowOpen = true, popupShown = false }), false)
		end)
		T.it("un popup de palier ou un bandeau masque l'offre", function()
			T.expectEqual(Overlay.offer({ windowOpen = false, popupShown = true }), false)
		end)
	end)

	T.describe("Overlay.objective", function()
		T.it("écran libre : le texte de l'objectif s'affiche", function()
			T.expectEqual(Overlay.objective({ windowOpen = false, popupShown = false, offerShown = false }), true)
			T.expectEqual(Overlay.objective({ windowOpen = false, popupShown = false }), true)
		end)
		T.it("le popup d'offre masque le texte (il était dessiné sur son bandeau, #62)", function()
			T.expectEqual(Overlay.objective({ windowOpen = false, popupShown = false, offerShown = true }), false)
		end)
		T.it("une fenêtre ou un popup de palier masquent le texte", function()
			T.expectEqual(Overlay.objective({ windowOpen = true, popupShown = false, offerShown = false }), false)
			T.expectEqual(Overlay.objective({ windowOpen = false, popupShown = true, offerShown = false }), false)
		end)
		T.it("tout revient à la fermeture : la règle ne dépend que de l'état courant", function()
			local open = { windowOpen = true, popupShown = false, offerShown = false }
			T.expectEqual(Overlay.offer(open), false)
			open.windowOpen = false
			T.expectEqual(Overlay.offer(open), true)
			-- L'offre revenue reprend la place du texte
			open.offerShown = Overlay.offer(open)
			T.expectEqual(Overlay.objective(open), false)
		end)
	end)
end
