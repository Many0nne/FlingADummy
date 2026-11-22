-- Tableaux de scores du hub (#120) : LONGEST THROW (record), INCOME ($/s courant), REBIRTHS. Top 10 global tenu par un
-- OrderedDataStore par tableau (Server.LeaderboardService), complété et rafraîchi par les valeurs des joueurs du
-- serveur. Logique pure : scores écrits, fusion du top global et des joueurs présents, textes affichés.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local Leaderboard = {}

Leaderboard.SIZE = 10 -- lignes par tableau
Leaderboard.REFRESH = 60 -- s entre deux écritures et lectures du classement global
-- Plus grand entier exact d'un nombre Luau : un OrderedDataStore ne garde que des entiers (revenus bien en dessous)
Leaderboard.MAX_SCORE = 2 ^ 53

export type Board = {
	id: string,
	title: string, -- bandeau du tableau
	icon: string,
	attribute: string, -- attribut du joueur lu (répliqué)
	store: string, -- nom de l'OrderedDataStore
	color: Color3, -- bandeau
}

local rgb = Color3.fromRGB
Leaderboard.BOARDS = {
	{
		id = "Distance",
		title = "LONGEST THROW",
		icon = "🏆",
		attribute = "BestDistance",
		store = "TopDistance_v1",
		color = rgb(255, 150, 30),
	},
	{
		id = "Income",
		title = "INCOME",
		icon = "💰",
		attribute = "BaseIncome", -- revenu des présentoirs, sans les multiplicateurs de la boutique Robux (#160)
		store = "TopIncome_v1",
		color = rgb(70, 190, 70),
	},
	{
		id = "Rebirths",
		title = "REBIRTHS",
		icon = "🌟",
		attribute = "Rebirths",
		store = "TopRebirths_v1",
		color = rgb(170, 90, 255),
	},
} :: { Board }

-- Ligne d'un classement : joueur (UserId, nom affiché si connu) et sa valeur
export type Entry = { userId: number, value: number, name: string? }

-- Cette méthode permet de donner le score entier à écrire dans le classement pour la valeur `value` d'un joueur
-- (arrondi à l'unité inférieure, borné à MAX_SCORE) ; 0 si elle n'est pas un nombre ou vaut moins de 1 : écrit quand
-- même, il efface un ancien score (revenu retombé à zéro, sauvegarde remise à zéro) et n'est jamais affiché.
function Leaderboard.score(value: any): number
	if type(value) ~= "number" or value ~= value or value < 1 then
		return 0
	end
	return math.min(math.floor(value), Leaderboard.MAX_SCORE)
end

-- Cette méthode permet de savoir s'il faut écrire le score `score` d'un joueur quand le classement en connaît `known`
-- (dernier écrit pendant sa session, sinon valeur lue dans le top ; nil : inconnu) : seulement s'il a changé (un
-- écrit par tableau et par joueur au plus toutes les REFRESH s), et pas un 0 qui n'effacerait rien de connu.
function Leaderboard.shouldWrite(known: number?, score: number): boolean
	if known == nil then
		return score > 0
	end
	return score ~= known
end

-- Cette méthode permet d'écrire la valeur d'un tableau (« 3.6 km », « $12.3K/s », « 4 ») lorsque le tableau affiche
-- une ligne.
function Leaderboard.format(id: string, value: number): string
	if id == "Distance" then
		return Format.distance(value)
	elseif id == "Income" then
		return Format.money(value) .. "/s"
	end
	return Format.short(value)
end

-- Cette méthode permet de fusionner le top global lu (`stored`) et les valeurs des joueurs du serveur (`live`, plus
-- fraîches : elles remplacent celles lues pour le même joueur) en un classement décroissant de `size` lignes au plus
-- (égalité : UserId croissant) ; les valeurs sous 1 sont écartées.
function Leaderboard.merge(stored: { Entry }, live: { Entry }, size: number?): { Entry }
	local byUser: { [number]: Entry } = {}
	for _, entry in stored do
		byUser[entry.userId] = entry
	end
	for _, entry in live do
		byUser[entry.userId] = entry
	end
	local list: { Entry } = {}
	for _, entry in byUser do
		if Leaderboard.score(entry.value) >= 1 then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	local limit = size or Leaderboard.SIZE
	while #list > limit do
		table.remove(list)
	end
	return list
end

return Leaderboard
