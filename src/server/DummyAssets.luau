-- Gabarits maillés du mannequin : au démarrage, crée une MeshPart par pièce et par accessoire (Shared.Assets,
-- maillages Blender publiés) dans ReplicatedStorage.DummyTemplates, que Shared.DummyShape clone côté serveur et
-- client. Tout ou rien : un seul échec et le jeu garde les blocs du gabarit.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local DummyShape = require(ReplicatedStorage.Shared.DummyShape)

local DummyAssets = {}

-- Cette méthode permet de créer la MeshPart d'un maillage publié (collision en boîte, texture de l'atlas) lorsque
-- les gabarits se construisent ; nil si le maillage n'est pas publié ou ne se charge pas.
local function createPart(name: string): MeshPart?
	local uri = Assets.uri(Assets.DUMMY_MESHES[name])
	if not uri then
		return nil
	end
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(uri), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if not ok then
		warn("[DummyAssets] maillage " .. name .. " : " .. tostring(result))
		return nil
	end
	local part = result :: MeshPart
	part.Name = name
	part.TextureID = Assets.uri(Assets.DUMMY_TEXTURE) or ""
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
