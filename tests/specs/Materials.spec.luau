-- Matériaux « briques à tenons » : MaterialVariant synchronisés par Rojo (src/materials), cartes publiées, échelle
-- conforme à assets/course/build_textures.py (brique de 2 studs, damier de 16 studs), noms connus de Server.Build.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function(T)
	local build = fs.readFile("src/server/Build.luau")
	local project = fs.readFile("default.project.json")
	local expected = { FadChecker = 16, FadWall = 16, FadBrick = 2, FadBrickFine = 1 }

	T.describe("MaterialVariant du décor", function()
		for name, studs in expected do
			T.it(name .. " : cartes publiées, échelle, référencé par Build et le projet", function()
				local model = serde.decode("json", fs.readFile("src/materials/" .. name .. ".model.json"))
				T.expectEqual(model.className, "MaterialVariant")
				T.expectEqual(model.properties.BaseMaterial, "Plastic")
				T.expectEqual(model.properties.StudsPerTile, studs)
				for _, map in { "ColorMap", "NormalMap" } do
					T.expect(
						string.match(model.properties[map] or "", "^rbxassetid://%d+$") ~= nil,
						name .. " : " .. map .. " publiée"
					)
				end
				T.expect(string.find(build, '"' .. name .. '"', 1, true) ~= nil, "nom utilisé par Server.Build")
				T.expect(
					string.find(project, "src/materials/" .. name .. ".model.json", 1, true) ~= nil,
					"synchronisé dans MaterialService"
				)
			end)
		end
	end)
end
