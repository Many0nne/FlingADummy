-- Gabarits maillés du mannequin : au démarrage, crée une MeshPart par pièce et par accessoire (Shared.Assets,
-- maillages Blender publiés) dans ReplicatedStorage.DummyTemplates, que Shared.DummyShape clone côté serveur et
-- client. Tout ou rien : un seul échec et le jeu garde les blocs du gabarit.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local DummyShape = require(ReplicatedStorage.Shared.DummyShape)

local DummyAssets = {}

local LOAD_ATTEMPTS = 3
local RETRY_DELAY = 2 -- s

-- Cette méthode permet de créer la MeshPart d'un maillage publié (collision en boîte, texture de l'atlas) lorsque
-- les gabarits se construisent ; nil si le maillage n'est pas publié ou ne se charge pas.
local function createPart(name: string): MeshPart?
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
		task.wait(RETRY_DELAY) -- service d'assets momentanément indisponible ou limité
	end
	if not ok then
		warn("[DummyAssets] maillage " .. name .. " : " .. tostring(result))
		return nil
	end
	local part = result :: MeshPart
	part.Name = name
	-- L'atlas passe par une SurfaceAppearance en Overlay (zones transparentes = couleur de la pièce) : TextureID les
	-- rend en noir, et ses propriétés ne s'écrivent pas par script, d'où le modèle Shared.DummySurface cloné.
	local surface = ReplicatedStorage.Shared:FindFirstChild(DummyShape.SURFACE)
	if surface then
		surface:Clone().Parent = part
	end
	part.Anchored = false
	return part
end

-- Cette méthode permet de construire les gabarits lorsque le serveur démarre (appel qui cède : à lancer dans un
-- task.spawn) ; les mannequins construits avant la fin restent en blocs.
function DummyAssets.init()
	local names = {}
	for _, piece in DummyShape.PIECES do
		table.insert(names, piece.name)
	end
	for name in DummyShape.ACCESSORIES do
		table.insert(names, name)
	end
	local folder = Instance.new("Folder")
	folder.Name = DummyShape.TEMPLATES
	for _, name in names do
		local part = createPart(name)
		if not part then
			folder:Destroy()
			return
		end
		part.Parent = folder
	end
	folder:SetAttribute("Ready", true)
	folder.Parent = ReplicatedStorage
end

return DummyAssets
