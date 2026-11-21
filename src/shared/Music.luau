-- Musique de fond (Client.Music) : pistes et logique pure du choix. Comme les références 01 et 09, la musique suit le
-- moment de jeu : hub (base, entraînement, boutiques) = pistes joyeuses en rotation enchaînées en fondu ; vol du
-- mannequin = piste rythmée ; tirage = musique baissée pendant la silhouette, fanfare à la révélation, puis reprise
-- (au hub). Pistes de la bibliothèque audio Roblox sous licence (« APMOfficial », Courtesy of APM Music), gratuites et
-- utilisables dans les jeux.
local Music = {}

export type Track = { id: string, name: string, volume: number }
export type Mood = "Hub" | "Flight" | "Tease" | "Reveal"
export type Bed = "Hub" | "Flight"

Music.TRACKS = {
	-- Hub : pop légère et joyeuse, en rotation
	Hub = {
		{ id = "rbxassetid://1842243521", name = "Scooter Girl", volume = 1 }, -- « Bouncy happy activity », 156 s
		{ id = "rbxassetid://1839930506", name = "Nickels and Dimes", volume = 0.9 }, -- synth pop, flûte de pan, 199 s
		{ id = "rbxassetid://1842246698", name = "Funky Thing", volume = 1 }, -- « Bright pop novelty », 170 s
	},
	-- Vol : punk rapide (202 bpm), en boucle le temps du lancer
	Flight = {
		{ id = "rbxassetid://9043932327", name = "Skate Or Die D", volume = 0.8 },
	},
	-- Révélation du tirage : fanfare courte
	Fanfare = { id = "rbxassetid://1845411858", name = "Top Prize", volume = 1 } :: Track,
}

-- Pistes de rechange proposées au test (même source) : hub « Happy Time » 1839401036, « Fun Kidz » 1839153331 ;
-- vol « Stronger Than You A » 9040412177 ; fanfare « Glamour Fanfare 7 » 1844584907, « Winner » 1844584698.

Music.GROUP_VOLUME = 0.3 -- SoundGroup musique : sous les chocs, le clic de jauge et les sons d'interface
Music.FADE = 1.5 -- s d'un fondu entre deux pistes du hub, et du muet
Music.SWITCH_FADE = 0.5 -- s d'une bascule de moment (le vol ne dure que quelques secondes)
Music.DUCK = 0.25 -- part du volume gardée pendant la silhouette du tirage et la fanfare
Music.FANFARE_MAX = 4.5 -- s : la fanfare s'efface au-delà, même si la piste dure plus

-- Cette méthode permet de déduire le moment musical lorsque `LaneState` ou la phase du tirage (`PrizePhase` local)
-- change ; `previous` = moment précédent (un résultat ne garde la piste du vol que s'il suit le vol).
function Music.mood(laneState: string?, prizePhase: string?, previous: Mood?): Mood
	if prizePhase == "Reveal" then
		return "Reveal"
	elseif prizePhase == "Tease" then
		return "Tease"
	elseif laneState == "Flying" then
		return "Flight"
	elseif laneState == "Result" then
		return if previous == "Flight" then "Flight" else "Hub"
	end
	return "Hub"
end

-- Cette méthode permet de choisir la liste de fond d'un moment lorsque celui-ci change ; la silhouette garde la piste
-- du vol (baissée), la révélation passe déjà au hub sous la fanfare pour une reprise sans coupure.
function Music.bed(mood: Mood): Bed
	if mood == "Flight" or mood == "Tease" then
		return "Flight"
	end
	return "Hub"
end

-- Cette méthode permet de donner la part de volume de la piste de fond lorsque le moment, la fanfare ou le muet
-- changent : 0 en muet, baissée pendant la silhouette et tant que la fanfare joue, pleine sinon.
function Music.bedLevel(mood: Mood, fanfarePlaying: boolean, muted: boolean): number
	if muted then
		return 0
	elseif mood == "Tease" or fanfarePlaying then
		return Music.DUCK
	end
	return 1
end

-- Cette méthode permet de donner l'indice de la piste suivante d'une liste (rotation dans l'ordre, retour au début)
-- lorsque la piste en cours se termine ou que l'on revient à cette liste.
function Music.nextIndex(bed: Bed, current: number?): number
	local count = #Music.TRACKS[bed]
	if not current then
		return 1
	end
	return current % count + 1
end

-- Cette méthode permet de choisir la première piste du hub au hasard (`roll` dans [0, 1[) lorsque le joueur arrive,
-- pour que deux sessions ne commencent pas toujours par la même.
function Music.firstIndex(bed: Bed, roll: number): number
	local count = #Music.TRACKS[bed]
	return math.clamp(math.floor(roll * count) + 1, 1, count)
end

-- Cette méthode permet de savoir s'il faut enchaîner la piste suivante lorsque la piste du hub approche de sa fin
-- (fondu lancé FADE s avant la fin) ; faux tant que la durée n'est pas connue (piste en chargement).
function Music.shouldAdvance(position: number, length: number): boolean
	return length > Music.FADE * 2 and position >= length - Music.FADE
end

-- Cette méthode permet de rapprocher un volume de sa cible à vitesse constante (un fondu complet en FADE s) lorsque
-- la musique avance d'une image de `dt` s.
function Music.approach(volume: number, target: number, scale: number, dt: number): number
	local step = scale * dt / Music.FADE
	if volume < target then
		return math.min(volume + step, target)
	end
	return math.max(volume - step, target)
end

return Music
