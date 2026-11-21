-- Exporte le look des mannequins générés (#96 : famille × palette, Shared.DummyFamilies) au format du catalogue de
-- assets/dummy/build_collection.py, pour que Blender rende leurs aperçus (puis leurs icônes, assets/icons/dummy_icons.py)
-- avec les mêmes pièces ajoutées, couleurs et matériaux qu'en jeu (Shared.DummyShape.addonFinish).
-- Usage depuis la racine du dépôt : lune run tools/export-generated-looks.luau
-- Sortie : assets/dummy/export/generated.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Loader = require("../tests/lib/Loader")

local OUT = "assets/dummy/export/generated.json"

local loader = Loader.new()
local Collection = loader:require("src/shared/Collection")
local DummyModels = loader:require("src/shared/DummyModels")
local DummyShape = loader:require("src/shared/DummyShape")

-- Cette méthode permet de convertir une couleur Roblox en triplet sRGB 0-255 lorsque l'on écrit le catalogue.
local function rgb(color: Color3): { number }
	return {
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
	}
end

-- Cette méthode permet de convertir un Vector3 en liste lorsque l'on écrit le catalogue.
local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local drawn = {}
for _, dummy in Collection.DRAWN do
	drawn[dummy.id] = true
end

local catalog = {}
local count = 0
for _, dummy in Collection.DUMMIES do
	if drawn[dummy.id] then
		continue
	end
	local look = Collection.look(dummy.id)
	local parts = {}
	for _, name in look.accessories do
		local def = DummyModels.ADDONS[name]
		local material, transparency = DummyShape.addonFinish(def, look)
		table.insert(parts, {
			mesh = name,
			piece = def.piece,
			color = rgb((look.accessoryColors or {})[name] or def.color),
			material = material.Name,
			transparency = transparency,
		})
	end
	local pieces = nil
	if look.pieceColors then
		pieces = {}
		for piece, color in look.pieceColors do
			pieces[piece] = rgb(color)
		end
	end
	local effects = {}
	for _, effect in look.effects or {} do
		table.insert(effects, {
			kind = effect.kind,
			preset = effect.preset,
			piece = effect.piece,
			offset = vec(effect.offset),
			color = rgb(effect.color),
			color2 = rgb(effect.color2 or effect.color),
			brightness = effect.brightness or 2,
		})
	end
	catalog[dummy.id] = {
		color = rgb(look.color),
		material = if look.material then look.material.Name else nil,
		pieces = pieces,
		hidden = look.hidden,
		parts = parts,
		effects = effects,
	}
	count += 1
end

fs.writeFile(OUT, serde.encode("json", catalog, true))
print(string.format("[generated] %d looks -> %s", count, OUT))
