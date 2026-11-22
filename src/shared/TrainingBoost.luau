-- Bonus « 2x TRAINING! » de l'entraînement (#119, retour de la sprint review 2) : toutes les BOOST_INTERVAL_MIN à
-- BOOST_INTERVAL_MAX s d'entraînement (temps cumulé sur les séances du joueur, au hasard), un bouton apparaît
-- BOOST_OFFER_TIME s ; cliqué à temps, l'EXP par répétition (donc la Throw Power) est × BOOST_MULTIPLIER pendant
-- BOOST_TIME s. Raté : rien. Pas d'apparition pendant un bonus, pas de cumul ; arrêter la séance annule le bouton et le
-- bonus. Le serveur tient l'état : il annonce chaque apparition (numéro) et n'accepte que le clic du numéro annoncé,
-- une fois, jusqu'à BOOST_CLICK_SLACK s après la fin de l'affichage (latence). Logique pure : horloge fournie par
-- l'appelant (temps d'entraînement cumulé), hasard par une fonction `rng` (nombre dans [0, 1)).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local TrainingBoost = {}

export type Offer = { id: number, shownAt: number }

export type State = {
	clock: number, -- temps d'entraînement cumulé (s), avancé seulement pendant les séances
	nextAt: number, -- instant (horloge `clock`) de la prochaine apparition
	lastId: number, -- numéro de la dernière apparition annoncée (0 : aucune)
	claimedId: number, -- numéro de la dernière apparition cliquée à temps (0 : aucune)
	cancelledId: number, -- numéro de la dernière apparition annulée par l'arrêt de la séance (0 : aucune)
	offer: Offer?, -- apparition en cours (clic encore accepté)
	boostEndsAt: number?, -- fin du bonus actif (horloge `clock`)
}

-- Résultat d'un pas de l'horloge : « Offer » (bouton à montrer), « Missed » (bouton raté, fenêtre close), « Ended »
-- (bonus terminé), nil sinon
export type Event = "Offer" | "Missed" | "Ended"

-- Refus d'un clic : « Late » (fenêtre close), « Duplicate » (déjà cliqué), « Cancelled » (séance arrêtée pendant
-- l'affichage), « Unknown » (numéro jamais annoncé ou remplacé)
export type Refusal = "Late" | "Duplicate" | "Cancelled" | "Unknown"

-- Cette méthode permet de tirer le temps d'entraînement avant la prochaine apparition lorsque le calendrier repart
-- (début, bouton raté, bonus fini, séance arrêtée).
function TrainingBoost.nextDelay(rng: () -> number): number
	local low, high = GameConfig.BOOST_INTERVAL_MIN, GameConfig.BOOST_INTERVAL_MAX
	return low + (high - low) * math.clamp(rng(), 0, 1)
end

-- Cette méthode permet de créer le calendrier d'un joueur (première apparition après un premier intervalle
-- d'entraînement) lorsqu'il arrive sur le serveur.
function TrainingBoost.new(rng: () -> number): State
	return {
		clock = 0,
		nextAt = TrainingBoost.nextDelay(rng),
		lastId = 0,
		claimedId = 0,
		cancelledId = 0,
		offer = nil,
		boostEndsAt = nil,
	}
end

-- Cette méthode permet de faire avancer l'horloge d'entraînement de `dt` s lorsque le joueur s'entraîne ; renvoie
-- l'événement du pas (fin de bonus, bouton raté, nouvelle apparition) ou nil.
function TrainingBoost.advance(state: State, dt: number, rng: () -> number): Event?
	state.clock += math.max(dt, 0)
	local boostEnds = state.boostEndsAt
	if boostEnds then
		if state.clock < boostEnds then
			return nil
		end
		state.boostEndsAt = nil
		state.nextAt = state.clock + TrainingBoost.nextDelay(rng)
		return "Ended"
	end
	local offer = state.offer
	if offer then
		if state.clock <= offer.shownAt + GameConfig.BOOST_OFFER_TIME + GameConfig.BOOST_CLICK_SLACK then
			return nil
		end
		state.offer = nil
		state.nextAt = state.clock + TrainingBoost.nextDelay(rng)
		return "Missed"
	end
	if state.clock < state.nextAt then
		return nil
	end
	state.lastId += 1
	state.offer = { id = state.lastId, shownAt = state.clock }
	return "Offer"
end

-- Cette méthode permet d'accepter ou de refuser le clic sur l'apparition `id` lorsque le client l'envoie ; accepté,
-- le bonus démarre (BOOST_TIME s) et l'apparition est consommée.
function TrainingBoost.claim(state: State, id: unknown): (boolean, Refusal?)
	if typeof(id) ~= "number" then
		return false, "Unknown"
	end
	local offer = state.offer
	if offer and offer.id == id then
		if state.clock > offer.shownAt + GameConfig.BOOST_OFFER_TIME + GameConfig.BOOST_CLICK_SLACK then
			return false, "Late" -- horloge pas encore avancée jusqu'à l'expiration : refus quand même
		end
		state.offer = nil
		state.claimedId = id
		state.boostEndsAt = state.clock + GameConfig.BOOST_TIME
		return true, nil
	end
	if id == state.claimedId and id > 0 then
		return false, "Duplicate"
	end
	if id == state.cancelledId and id > 0 then
		return false, "Cancelled"
	end
	if id == state.lastId and id > 0 then
		return false, "Late"
	end
	return false, "Unknown"
end

-- Cette méthode permet d'annuler l'apparition et le bonus en cours (le calendrier repart d'un intervalle complet)
-- lorsque la séance s'arrête ; renvoie vrai si quelque chose était en cours.
function TrainingBoost.stop(state: State, rng: () -> number): boolean
	local active = state.offer ~= nil or state.boostEndsAt ~= nil
	if active then
		if state.offer then
			state.cancelledId = state.offer.id
		end
		state.offer = nil
		state.boostEndsAt = nil
		state.nextAt = state.clock + TrainingBoost.nextDelay(rng)
	end
	return active
end

-- Cette méthode permet de donner le multiplicateur d'EXP du moment (BOOST_MULTIPLIER pendant le bonus, 1 sinon)
-- lorsqu'une répétition se termine.
function TrainingBoost.multiplier(state: State): number
	local ends = state.boostEndsAt
	return if ends and state.clock < ends then GameConfig.BOOST_MULTIPLIER else 1
end

-- Cette méthode permet de donner le multiplicateur affiché par le client (fin du bonus `endsAt` en temps serveur, nil
-- sans bonus) lorsque le HUD annonce une répétition ou dessine la barre de durée.
function TrainingBoost.displayMultiplier(endsAt: unknown, now: number): number
	return if typeof(endsAt) == "number" and now < endsAt then GameConfig.BOOST_MULTIPLIER else 1
end

-- Cette méthode permet de donner le multiplicateur de la répétition qui vient d'arriver (BOOST_MULTIPLIER tant que le
-- serveur garde l'attribut TrainBoostEnds, qu'il retire dans l'image où le bonus finit) lorsque le HUD fait s'envoler
-- son « +N EXP » ; pas de comparaison d'horloges, qui se tromperait sur les dernières répétitions du bonus.
function TrainingBoost.grantedMultiplier(endsAt: unknown): number
	return if typeof(endsAt) == "number" then GameConfig.BOOST_MULTIPLIER else 1
end

-- Cette méthode permet de donner combien de temps le client montre encore le bouton (s) lorsque l'annonce arrive
-- avec la fin de l'affichage `deadline` en temps serveur : le bouton disparaît quand le serveur cesse d'attendre le
-- clic (à la marge de latence près), même si l'annonce a mis du temps à arriver.
function TrainingBoost.offerTimeLeft(deadline: unknown, now: number): number
	if typeof(deadline) ~= "number" then
		return GameConfig.BOOST_OFFER_TIME
	end
	return math.clamp(deadline - now, 0, GameConfig.BOOST_OFFER_TIME)
end

-- Cette méthode permet d'écrire le temps restant du bonus (« 0:24 ») lorsque la barre de durée se rafraîchit.
function TrainingBoost.remainingText(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return TrainingBoost
