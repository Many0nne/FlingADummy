-- Catalogue des looks des mannequins générés (#96), au format de assets/dummy/build_collection.py : construit par
-- tools/export-generated-looks.luau (export pour Blender) et par tests/specs/DummyFamilies.spec.luau (garde-fou : le
-- generated.json versionné, donc les icônes publiées, suit les palettes).
local GeneratedLooks = {}

GeneratedLooks.PATH = "assets/dummy/export/generated.json"

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

-- Cette méthode permet de construire le catalogue (id → look) des mannequins générés avec les modules chargés par
-- `loader` (tests/lib/Loader) lorsque l'on exporte les looks ou que le garde-fou les compare ; renvoie aussi leur nombre.
function GeneratedLooks.build(loader: any): ({ [string]: any }, number)
	local Collection = loader:require("src/shared/Collection")
	local DummyModels = loader:require("src/shared/DummyModels")
	local DummyShape = loader:require("src/shared/DummyShape")
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
	return catalog, count
end

return GeneratedLooks
