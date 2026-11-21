-- Exporte le look des mannequins générés (#96 : famille × palette, Shared.DummyFamilies) au format du catalogue de
-- assets/dummy/build_collection.py, pour que Blender rende leurs aperçus (puis leurs icônes, assets/icons/dummy_icons.py)
-- avec les mêmes pièces ajoutées, couleurs et matériaux qu'en jeu (Shared.DummyShape.addonFinish).
-- Usage depuis la racine du dépôt : lune run tools/export-generated-looks.luau
-- Sortie : assets/dummy/export/generated.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Loader = require("../tests/lib/Loader")

local GeneratedLooks = require("./GeneratedLooks")

local catalog, count = GeneratedLooks.build(Loader.new())
fs.writeFile(GeneratedLooks.PATH, serde.encode("json", catalog, true))
print(string.format("[generated] %d looks -> %s", count, GeneratedLooks.PATH))
