-- Pont provisoire entre le décor actuel et les objectifs du HUD : marque la zone de lancer (« Throw ») et le poste
-- d'entraînement (« Train ») de chaque couloir comme cibles (tag Shared.Objectives.TAG, attributs Objective et Lane).
-- Quand le décor les marque lui-même (carte #10 : CollectionService:AddTag + SetAttribute("Objective", ...) à la
-- construction), ce module devient inutile : le retirer avec son appel dans init.server.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Objectives = require(ReplicatedStorage.Shared.Objectives)

local ObjectiveTargets = {}

-- Pièce du décor de chaque couloir → objectif qu'elle désigne
local PARTS = { Pad = "Throw", TrainSpot = "Train" }

-- Cette méthode permet de marquer une pièce comme cible d'objectif réservée au joueur d'un couloir lorsque le décor
-- est construit.
function ObjectiveTargets.mark(part: BasePart, objective: string, lane: number?)
	part:SetAttribute("Objective", objective)
	part:SetAttribute("Lane", lane)
	CollectionService:AddTag(part, Objectives.TAG)
end

-- Cette méthode permet de marquer la zone de lancer et le poste d'entraînement de chaque couloir lorsque le serveur
-- a construit les couloirs ; une pièce déjà marquée (par le décor) est laissée telle quelle.
function ObjectiveTargets.init(lanes: { { index: number, folder: Folder } })
	for _, lane in lanes do
		for name, objective in PARTS do
			local part = lane.folder:FindFirstChild(name)
			if part and part:IsA("BasePart") and not CollectionService:HasTag(part, Objectives.TAG) then
				ObjectiveTargets.mark(part, objective, lane.index)
			end
		end
	end
end

return ObjectiveTargets
