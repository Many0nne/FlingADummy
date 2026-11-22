-- Écrit le manifeste des planches de référence (#121) : prises de vue, texte et empreinte de chaque case
-- (tools/Planches.luau). À relancer avant de régénérer les planches (procédure : docs/planches/README.md).
-- Usage depuis la racine du dépôt : lune run tools/planches-manifest.luau
-- Sortie : docs/planches/manifest.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Loader = require("../tests/lib/Loader")

local Planches = require("./Planches")

local manifest, counts = Planches.build(Loader.new())
fs.writeFile(Planches.PATH, serde.encode("json", manifest, true) .. "\n")
for _, sheet in manifest.sheets do
	print(string.format("[planches] %s : %d case(s), %d prise(s)", sheet.name, counts[sheet.name], #sheet.shots))
end
print("[planches] -> " .. Planches.PATH)
