-- RemoteEvents du jeu : créés par le serveur dans ReplicatedStorage.Remotes, attendus par le client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = {
	"Launch",
	"GaugeStop",
	"BuyUpgrade",
	"StopTraining",
	"PlaceDummy",
	"Inventory",
	"ResultDone",
	"ThrowAgain",
	"LaunchStarted",
	"LaunchRefused",
	"LaunchResult",
	"Impact",
	"SetMusic",
	"Announce",
	"ThrowDummy",
	"Rebirth",
	"TrainingBoost",
	"Store",
	"FlightClock",
}

-- Remotes non fiables (UnreliableRemoteEvent) : un message perdu est remplacé par le suivant
local UNRELIABLE = {
	FlightClock = true,
}

export type Remotes = {
	GaugeStop: RemoteEvent, -- client → serveur : sans charge, au clic qui arrête l'aiguille (le serveur note l'arrivée)
	Launch: RemoteEvent, -- client → serveur : valeur de jauge 0-1, à la fin de l'élan
	BuyUpgrade: RemoteEvent, -- client → serveur : "Gear"
	PlaceDummy: RemoteEvent, -- client → serveur : présentoir où poser le dernier mannequin gagné, ou nil (AUTO)
	-- client → serveur : action sur la collection (Server.BaseService.act) : "Place" / "Sell" + clé « id:taille » du
	-- stock, "Remove" + présentoir, "SellRarity" + rareté, "PlaceBest", "BuyDisplay" (pad de sa base)
	Inventory: RemoteEvent,
	ResultDone: RemoteEvent, -- client → serveur : GO BACK, fin du résultat et du tirage
	-- client → serveur : THROW AGAIN (#76), fin du résultat puis remise en prise sur la bande (sinon comme GO BACK)
	ThrowAgain: RemoteEvent,
	StopTraining: RemoteEvent, -- client → serveur : bouton STOP ou saut pendant l'entraînement
	LaunchStarted: RemoteEvent, -- serveur → client : modèle du mannequin lancé, départ du vol (point, vitesse, mannequin)
	LaunchRefused: RemoteEvent, -- serveur → client : sans charge, Launch refusé (le décoratif parti au lâcher s'efface)
	LaunchResult: RemoteEvent, -- serveur → client : gains, blessures, cause
	-- serveur → tous les clients : liste de chocs de la frame (effets, sons, popups) ; `at` (heure serveur) sur les
	-- chocs d'un vol, montrés quand le mannequin affiché y arrive (#84)
	Impact: RemoteEvent,
	SetMusic: RemoteEvent, -- client → serveur : true = musique coupée (bouton du HUD), sauvegardé avec les données
	-- serveur → tous les clients : tirage Legendary ou plus (bandeau), à la fin du résultat du gagnant :
	-- { userId, player, name, rarity, odds } ; renaissance d'un joueur : { kind = "Rebirth", userId, player, rebirths }
	Announce: RemoteEvent,
	-- client → serveur : boutique de mannequins à lancer (Shared.ThrowDummies) : "Buy" / "Equip" + indice du catalogue
	ThrowDummy: RemoteEvent,
	Rebirth: RemoteEvent, -- client → serveur : sans charge, bouton REBIRTH de la fenêtre (Shared.Rebirth)
	-- Bouton « 2x TRAINING! » (Shared.TrainingBoost) : serveur → client "Offer" + numéro + fin de l'affichage en temps
	-- serveur (bouton à montrer) ou "Cancel"
	-- (séance arrêtée) ; client → serveur : numéro de l'apparition cliquée. Bonus accordé : attribut TrainBoostEnds
	TrainingBoost: RemoteEvent,
	-- Boutique Robux (#160, Server.StoreService) : client → serveur "Buy" + identifiant d'un article pas encore créé sur
	-- l'expérience (achat simulé en Studio seulement) ; serveur → client "Granted" + identifiant + argent reçu (popup de
	-- l'acheteur), serveur → tous "ServerLuck" + identifiant + nom de l'acheteur
	Store: RemoteEvent,
	-- serveur → tous les clients, non fiable : torse d'un mannequin en vol, heure serveur et position de ce torse,
	-- DisplayLag.SAMPLE_RATE fois par seconde (#84 : retard d'affichage mesuré par Client.TrapMotion)
	FlightClock: UnreliableRemoteEvent,
}

local Remotes = {}

-- Cette méthode permet de créer le dossier des RemoteEvents lorsque le serveur démarre.
function Remotes.create(): Remotes
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	local remotes = {}
	for _, name in NAMES do
		local remote = Instance.new(if UNRELIABLE[name] then "UnreliableRemoteEvent" else "RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
	return remotes :: any
end

-- Cette méthode permet d'attendre les RemoteEvents créés par le serveur lorsque le client démarre.
function Remotes.wait(): Remotes
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local remotes = {}
	for _, name in NAMES do
		remotes[name] = folder:WaitForChild(name)
	end
	return remotes :: any
end

return Remotes
