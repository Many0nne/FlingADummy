-- Gabarits maillés du mannequin : au démarrage, crée une MeshPart par pièce et par accessoire (Shared.Assets,
-- maillages Blender publiés) dans ReplicatedStorage.DummyTemplates, que Shared.DummyShape clone côté serveur et
-- client. Tout ou rien pour les pièces du corps : un seul échec et le jeu garde les blocs du gabarit. Les pièces
-- ajoutées des modèles de collection (#66) se chargent ensuite, par lots parallèles ; une pièce absente est seulement
-- omise.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local DummyShape = require(ReplicatedStorage.Shared.DummyShape)

local DummyAssets = {}

local LOAD_ATTEMPTS = 3
local RETRY_DELAY = 2 -- s
local WORKERS = 8 -- chargements simultanés (environ 170 maillages : une rafale complète se ferait limiter)

-- Cette méthode permet de créer la MeshPart d'un maillage publié (collision en boîte, texture de l'atlas pour une
-- pièce du corps) lorsque les gabarits se construisent ; nil si le maillage n'est pas publié ou ne se charge pas.
local function createPart(name: string, textured: boolean): MeshPart?
	local uri = Assets.uri(Assets.DUMMY_MESHES[name])
	if not uri then
		return nil
	end
	local ok, result
	for attempt = 1, LOAD_ATTEMPTS do
		ok, result = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(uri), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
		if ok or attempt == LOAD_ATTEMPTS then
			break
		end
		-- Service d'assets momentanément indisponible ou limité : attente croissante, décalée au hasard pour que les
		-- chargements en échec ne réessaient pas tous ensemble
		task.wait(RETRY_DELAY * attempt + math.random())
	end
	if not ok then
		warn("[DummyAssets] maillage " .. name .. " : " .. tostring(result))
		return nil
	end
	local part = result :: MeshPart
	part.Name = name
	-- L'atlas passe par une SurfaceAppearance en Overlay (zones transparentes = couleur de la pièce) : TextureID les
	-- rend en noir, et ses propriétés ne s'écrivent pas par script, d'où le modèle Shared.DummySurface cloné.
	local surface = textured and ReplicatedStorage.Shared:FindFirstChild(DummyShape.SURFACE)
	if surface then
		surface:Clone().Parent = part
	end
	part.Anchored = false
	return part
end

-- Cette méthode permet de charger une liste de maillages par WORKERS en parallèle dans `folder` lorsque les gabarits se
-- construisent (appel qui cède jusqu'à la fin) ; renvoie le nombre d'échecs (une erreur imprévue compte comme un échec,
-- sans bloquer l'attente).
local function loadAll(names: { string }, textured: boolean, folder: Folder): number
	local nextIndex, running, failures = 1, 0, 0
	-- Cette méthode permet à un chargeur de prendre les maillages de la liste un par un jusqu'à ce qu'elle soit vide.
	local function worker()
		while nextIndex <= #names do
			local name = names[nextIndex]
			nextIndex += 1
			local ok, part = pcall(createPart, name, textured)
			if ok and part then
				part.Parent = folder
			else
				failures += 1
			end
		end
		running -= 1
	end
	for _ = 1, math.min(WORKERS, #names) do
		running += 1
		task.spawn(worker)
	end
	while running > 0 do
		task.wait(0.1)
	end
	return failures
end

-- Cette méthode permet de construire les gabarits lorsque le serveur démarre (appel qui cède : à lancer dans un
-- task.spawn) : les pièces du corps d'abord (dossier publié et marqué Ready), puis les pièces ajoutées des modèles de
-- collection (attribut Complete à la fin, qui fait reconstruire les mannequins posés sans elles).
function DummyAssets.init()
	local folder = Instance.new("Folder")
	folder.Name = DummyShape.TEMPLATES
	local body = {}
	for _, piece in DummyShape.PIECES do
		table.insert(body, piece.name)
	end
	if loadAll(body, true, folder) > 0 then
		folder:Destroy() -- tout ou rien pour le corps : le jeu garde les blocs du gabarit
		return
	end
	folder:SetAttribute("Ready", true)
	folder.Parent = ReplicatedStorage
	local addons = {}
	for name in DummyShape.ACCESSORIES do
		if Assets.DUMMY_MESHES[name] then
			table.insert(addons, name)
		end
	end
	loadAll(addons, false, folder)
	folder:SetAttribute(DummyShape.COMPLETE, true)
end

return DummyAssets
