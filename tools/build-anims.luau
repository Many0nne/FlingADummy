-- Génère les KeyframeSequence (.rbxm) des animations de l'avatar à partir de Shared.AnimationData, dans
-- assets/anim/export/<Nom>.rbxm, prêtes à publier (Open Cloud, type Animation). Les ids publiés vont dans
-- Shared.Assets. Usage : `lune run tools/build-anims.luau` depuis la racine du dépôt.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Loader = require("../tests/lib/Loader")

local OUT = "assets/anim/export"

local loader = Loader.new()
local AnimationData = loader:require("src/shared/AnimationData")

fs.writeDir(OUT)
for _, clip in AnimationData.CLIPS do
	local path = OUT .. "/" .. clip.name .. ".rbxm"
	fs.writeFile(path, roblox.serializeModel({ AnimationData.buildSequence(clip) }))
	print(string.format("%s : %d keyframes, %.2f s -> %s", clip.name, #clip.keyframes, clip.length, path))
end
