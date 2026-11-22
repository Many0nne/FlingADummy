-- Plan des planches de référence (#121, docs/planches/) : quelles prises de vue faire en Studio et ce que chacune
-- montre. Les mannequins (collection, à lancer) sont posés par rangées de ROW cases égales devant un fond neutre ; la
-- base et l'appareil d'entraînement sont photographiés en place, un palier par prise, avec le même cadrage.
-- Logique pure (testée) : lue par Server.PhotoStudio (scène), Client.PhotoCamera (cadrage) et tools/Planches.luau
-- (manifeste docs/planches/manifest.json, lu par tools/planches.py qui découpe et assemble les captures).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BaseLook = require(Shared:WaitForChild("BaseLook"))
local Collection = require(Shared:WaitForChild("Collection"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local ThrowDummies = require(Shared:WaitForChild("ThrowDummies"))
local Training = require(Shared:WaitForChild("Training"))

local PlanchePlan = {}

PlanchePlan.ROW = 6 -- cases par prise de vue d'une rangée de mannequins
PlanchePlan.CELL_WIDTH = 7 -- largeur d'une case (studs) : un mannequin d'échelle 1, bras compris, et son aura
PlanchePlan.CELL_HEIGHT = 11 -- hauteur d'une case (studs) : des pieds (anneau au sol) au-dessus de la tête
PlanchePlan.FOV = 30 -- champ vertical de la caméra (degrés) : presque sans déformation, peu de brume
PlanchePlan.SHOT = "PhotoShot" -- attribut de Workspace : nom de la prise en cours (posé en Studio, contexte Server)
PlanchePlan.FRAME = "PhotoFrame" -- pièce invisible du cadrage de la prise en cours (Workspace), lue par le client

-- Ordre des planches (nom du fichier docs/planches/<nom>.jpg)
PlanchePlan.SHEETS = { "collection", "a-lancer", "base", "entrainement" }

-- Contenu d'une case : mannequin de collection (`key` = id), mannequin à lancer (indice), palier de base ou de
-- l'appareil d'entraînement (palier)
export type Item = { kind: string, key: string | number }

-- Prise de vue : `framing` « row » (rangée de cases, de gauche à droite), « base » ou « station » (une prise par
-- palier) ; `group` : rareté de la rangée (planche de la collection)
export type Shot = { name: string, sheet: string, framing: string, group: number?, items: { Item } }

-- Cette méthode permet de découper une liste en prises de vue d'au plus ROW cases lorsque l'on range des mannequins.
local function rows(sheet: string, items: { Item }, group: number?, into: { Shot })
	for first = 1, #items, PlanchePlan.ROW do
		local chunk = table.move(items, first, math.min(first + PlanchePlan.ROW - 1, #items), 1, {})
		table.insert(into, { name = "", sheet = sheet, framing = "row", group = group, items = chunk })
	end
end

-- Cette méthode permet de donner les prises de vue de la planche `sheet` (dans l'ordre, nommées « <planche>-<n> »)
-- lorsque l'on pose la scène ou que l'on écrit le manifeste.
function PlanchePlan.shots(sheet: string): { Shot }
	local list: { Shot } = {}
	if sheet == "collection" then
		-- Une rangée par rareté (plusieurs si elle compte plus de ROW mannequins), dans l'ordre du catalogue
		for rarity = 1, #Rarity.LIST do
			local items = {}
			for _, dummy in Collection.DUMMIES do
				if dummy.rarity == rarity then
					table.insert(items, { kind = "collection", key = dummy.id })
				end
			end
			rows(sheet, items, rarity, list)
		end
	elseif sheet == "a-lancer" then
		local items = {}
		-- Catalogue, puis le Rainbow Dummy du passe de la boutique Robux (#160, ThrowDummies.RAINBOW)
		for index = 1, ThrowDummies.RAINBOW do
			table.insert(items, { kind = "throw", key = index })
		end
		rows(sheet, items, nil, list)
	elseif sheet == "base" then
		for tier = 1, #BaseLook.BASE_TIERS do
			table.insert(
				list,
				{ name = "", sheet = sheet, framing = "base", items = { { kind = "base", key = tier } } }
			)
		end
	elseif sheet == "entrainement" then
		for tier = 1, #Training.GEARS do
			table.insert(
				list,
				{ name = "", sheet = sheet, framing = "station", items = { { kind = "station", key = tier } } }
			)
		end
	else
		error("planche inconnue : " .. tostring(sheet))
	end
	for index, shot in list do
		shot.name = sheet .. "-" .. index
	end
	return list
end

-- Cette méthode permet de retrouver une prise de vue par son nom (« collection-3 ») lorsque Studio la demande ; nil
-- si elle n'existe pas.
function PlanchePlan.find(name: string): Shot?
	local sheet = string.match(name, "^(.-)%-%d+$")
	if not sheet or not table.find(PlanchePlan.SHEETS, sheet) then
		return nil
	end
	for _, shot in PlanchePlan.shots(sheet) do
		if shot.name == name then
			return shot
		end
	end
	return nil
end

-- Cette méthode permet de donner la distance de la caméra au plan cadré pour que `width` studs remplissent toute la
-- largeur de l'image (champ vertical FOV, image `aspect` = largeur / hauteur) lorsque le client cadre une prise.
function PlanchePlan.distance(width: number, aspect: number): number
	local halfV = math.rad(PlanchePlan.FOV / 2)
	return (width / 2) / (math.tan(halfV) * aspect)
end

return PlanchePlan
