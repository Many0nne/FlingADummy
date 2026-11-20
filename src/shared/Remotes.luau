-- RemoteEvents du jeu : créés par le serveur dans ReplicatedStorage.Remotes, attendus par le client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES =
	{ "Launch", "BuyUpgrade", "StopTraining", "PlaceDummy", "ResultDone", "LaunchStarted", "LaunchResult", "Impact" }

export type Remotes = {
	Launch: RemoteEvent, -- client → serveur : valeur de jauge 0-1, à la fin de l'élan
	BuyUpgrade: RemoteEvent, -- client → serveur : "Gear"
	PlaceDummy: RemoteEvent, -- client → serveur : présentoir (1-6) où poser le mannequin gagné, ou nil (AUTO)
	ResultDone: RemoteEvent, -- client → serveur : GO BACK, fin du résultat et du tirage
	StopTraining: RemoteEvent, -- client → serveur : bouton STOP ou saut pendant l'entraînement
	LaunchStarted: RemoteEvent, -- serveur → client : modèle du mannequin lancé
	LaunchResult: RemoteEvent, -- serveur → client : gains, blessures, cause
	Impact: RemoteEvent, -- serveur → tous les clients : liste de chocs de la frame (effets, sons, popups)
}

local Remotes = {}

-- Cette méthode permet de créer le dossier des RemoteEvents lorsque le serveur démarre.
function Remotes.create(): Remotes
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	local remotes = {}
	for _, name in NAMES do
		local remote = Instance.new("RemoteEvent")
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
