-- Manifeste des planches de référence (#121) : prises de vue de Shared.PlanchePlan, avec pour chaque case ce que la
-- planche écrit (nom, cote, revenu, prix, chance, palier) et l'empreinte de son apparence (déclinaison du mannequin,
-- palier de base ou d'appareil). Écrit par tools/planches-manifest.luau (docs/planches/manifest.json, lu par
-- tools/planches.py) ; comparé par tests/specs/Planches.spec.luau : un mannequin, un palier ajouté ou un look modifié
-- sans planches régénérées fait échouer check.sh.
local serde = require("@lune/serde")

local Planches = {}

Planches.PATH = "docs/planches/manifest.json"

Planches.TITLES = {
	collection = "Mannequins de collection",
	["a-lancer"] = "Mannequins à lancer",
	base = "Paliers de la base",
	entrainement = "Paliers de l'appareil d'entraînement",
}

-- Cette méthode permet d'écrire une valeur sous une forme stable (clés triées, types Roblox en texte) lorsque l'on
-- calcule l'empreinte d'une apparence.
local function canonical(value: any): string
	local kind = typeof(value)
	if kind == "table" then
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, key in keys do
			table.insert(parts, tostring(key) .. "=" .. canonical(value[key]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif kind == "number" then
		return string.format("%.4f", value)
	end
	return kind .. ":" .. tostring(value)
end

-- Cette méthode permet de donner l'empreinte courte (10 caractères) d'une apparence lorsque l'on écrit une case.
local function fingerprint(value: any): string
	return string.sub(serde.hash("sha256", canonical(value)), 1, 10)
end

-- Cette méthode permet de convertir une couleur Roblox en « #rrggbb » lorsque l'on écrit le manifeste.
local function hex(color: Color3): string
	return "#" .. string.lower(color:ToHex())
end

-- Cette méthode permet de construire le manifeste avec les modules chargés par `loader` (tests/lib/Loader) lorsque
-- l'on régénère les planches ou que le garde-fou les compare ; renvoie aussi le nombre de cases par planche.
function Planches.build(loader: any): ({ [string]: any }, { [string]: number })
	local BaseLook = loader:require("src/shared/BaseLook")
	local Collection = loader:require("src/shared/Collection")
	local DummyModels = loader:require("src/shared/DummyModels")
	local Format = loader:require("src/shared/Format")
	local PlanchePlan = loader:require("src/shared/PlanchePlan")
	local Rarity = loader:require("src/shared/Rarity")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")
	local Training = loader:require("src/shared/Training")
	local TrainingLook = loader:require("src/shared/TrainingLook")

	-- Cette méthode permet de décrire une case (texte de la planche et empreinte de l'apparence) lorsque l'on parcourt
	-- une prise de vue.
	local function describe(item: any): { [string]: any }
		if item.kind == "collection" then
			local entry = { id = item.key, size = 1 }
			local dummy = Collection.get(item.key)
			local variant = Collection.variant(entry)
			local addons = {}
			for _, name in variant.accessories or {} do
				addons[name] = DummyModels.ADDONS[name]
			end
			return {
				key = item.key,
				title = dummy.name,
				lines = {
					"1 IN " .. Format.short(Collection.odds(entry)),
					Format.money(Collection.income(entry)) .. "/s",
				},
				look = fingerprint({ variant = variant, addons = addons }),
			}
		elseif item.kind == "throw" then
			local dummy = ThrowDummies.get(item.key)
			return {
				key = dummy.id,
				title = dummy.name,
				lines = {
					if dummy.cost == 0 then "FREE" else Format.money(dummy.cost),
					string.format("LUCK x%g", dummy.luck),
				},
				look = fingerprint(ThrowDummies.variant(item.key)),
			}
		elseif item.kind == "base" then
			local tier, fence = BaseLook.base(item.key)
			return {
				key = item.key,
				title = string.format("%d. %s", item.key, tier.name),
				lines = { string.format("%d présentoirs", tier.displays) },
				look = fingerprint({ tier = tier, fence = fence }),
			}
		end
		local gear = Training.GEARS[item.key]
		-- Mannequins du râtelier : look du palier (Shared.TrainingLook, #118) et définitions de leurs pièces ajoutées
		local rack = {}
		for _, tier in BaseLook.rackTiers(item.key) do
			local variant = TrainingLook.variant(tier, "rack")
			local addons = {}
			for _, name in variant.accessories or {} do
				addons[name] = DummyModels.ADDONS[name]
			end
			table.insert(rack, { variant = variant, addons = addons })
		end
		return {
			key = item.key,
			title = string.format("%d. %s", item.key, gear.name),
			lines = {
				if gear.cost == 0 then "FREE" else Format.money(gear.cost),
				string.format("+%s EXP / rep", Format.short(gear.gain)),
			},
			look = fingerprint({ station = BaseLook.station(item.key), rack = rack }),
		}
	end

	local sheets = {}
	local counts = {}
	for _, name in PlanchePlan.SHEETS do
		local shots = {}
		local count = 0
		for _, shot in PlanchePlan.shots(name) do
			local items = {}
			for _, item in shot.items do
				table.insert(items, describe(item))
			end
			count += #items
			local group = nil
			if shot.group then
				local rarity = Rarity.get(shot.group)
				group = { name = rarity.name, color = hex(rarity.color) }
			end
			table.insert(shots, { name = shot.name, framing = shot.framing, group = group, items = items })
		end
		counts[name] = count
		table.insert(sheets, { name = name, title = Planches.TITLES[name], shots = shots })
	end
	return { row = PlanchePlan.ROW, cell = { PlanchePlan.CELL_WIDTH, PlanchePlan.CELL_HEIGHT }, sheets = sheets }, counts
end

return Planches
