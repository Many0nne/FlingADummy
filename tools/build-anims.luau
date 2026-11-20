-- Génère les KeyframeSequence (.rbxm) des animations de l'avatar à partir de Shared.AnimationData, dans
-- assets/anim/export/<Nom>.rbxm, prêtes à publier (Open Cloud, type Animation). Les ids publiés vont dans
-- Shared.Assets. Usage depuis la racine du dépôt (procédure complète : assets/anim/README.md) :
--   lune run tools/build-anims.luau              exporte les .rbxm
--   lune run tools/build-anims.luau --published  après publication : réécrit assets/anim/published.json (id + SHA-256
--                                                des .rbxm exportés), sans réexporter
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Loader = require("../tests/lib/Loader")

local OUT = "assets/anim/export"

local loader = Loader.new()
local AnimationData = loader:require("src/shared/AnimationData")

-- Cette méthode permet d'enregistrer l'id et l'empreinte du .rbxm de chaque clip lorsque l'on vient de les publier.
local function writePublished()
	local Assets = loader:require("src/shared/Assets")
	local published = {}
	for _, clip in AnimationData.CLIPS do
		local id = Assets.ANIMATIONS[clip.name]
		if not id or id == 0 then
			error(clip.name .. " : id absent ou 0 dans Assets.ANIMATIONS (README, étape « Créer une nouvelle animation »)")
		end
		local path = OUT .. "/" .. clip.name .. ".rbxm"
		if not fs.isFile(path) then
			error(clip.name .. " : " .. path .. " absent, exporter d'abord (lune run tools/build-anims.luau)")
		end
		local sha256 = serde.hash("sha256", fs.readFile(path))
		if sha256 ~= serde.hash("sha256", roblox.serializeModel({ AnimationData.buildSequence(clip) })) then
			error(clip.name .. " : export périmé par rapport à AnimationData, exporter puis republier d'abord")
		end
		published[clip.name] = { id = string.format("%d", id), sha256 = sha256 }
	end
	fs.writeFile("assets/anim/published.json", serde.encode("json", published, true) .. "\n")
	print("assets/anim/published.json réécrit")
end

if table.find(process.args, "--published") then
	writePublished()
	return
end

fs.writeDir(OUT)
for _, clip in AnimationData.CLIPS do
	local path = OUT .. "/" .. clip.name .. ".rbxm"
	fs.writeFile(path, roblox.serializeModel({ AnimationData.buildSequence(clip) }))
	print(string.format("%s : %d keyframes, %.2f s -> %s", clip.name, #clip.keyframes, clip.length, path))
end
