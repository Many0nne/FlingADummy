-- Marques et blocs superposés (#161) : aucune face d'un bloc des mannequins à lancer (étiquette, plaques, ailes,
-- réacteur, signes de rang) ne doit être coplanaire (écart sous DummyShape.MIN_FACE_GAP) à une face de même sens de sa
-- pièce porteuse, de la coque des marques ou d'un autre bloc de la même pièce, sinon elles scintillent (z-fighting).
-- Les blocs sont de vraies boîtes : le contrôle est exact. Les pièces ajoutées des mannequins de collection sont des
-- maillages dont la boîte ne dit rien de la surface : leur coque de marques est contrôlée sur le modèle construit
-- (DummyShape.spec). Toutes les cotes se multiplient par la même échelle du modèle : l'échelle 1 vaut à toute échelle.
return function(T, Loader)
	local roblox = require("@lune/roblox")
	local loader = Loader.new()
	local DummyShape = loader:require("src/shared/DummyShape")
	local ThrowDummies = loader:require("src/shared/ThrowDummies")

	local AXES = { "X", "Y", "Z" }

	-- Cette méthode permet de lister les faces coplanaires (écart sous `minGap`) de deux boîtes lorsqu'un test cherche un
	-- z-fighting : mêmes sens de face, et rectangles qui se recouvrent sur les deux autres axes.
	local function coplanar(a, b, minGap: number): { string }
		local found = {}
		for _, axis in AXES do
			local overlap = true
			for _, other in AXES do
				if other ~= axis then
					local lo = math.max(a.center[other] - a.half[other], b.center[other] - b.half[other])
					local hi = math.min(a.center[other] + a.half[other], b.center[other] + b.half[other])
					if hi - lo < 0.05 then -- recouvrement négligeable : pas de scintillement visible
						overlap = false
					end
				end
			end
			if overlap then
				for _, sign in { -1, 1 } do
					local gap =
						math.abs((a.center[axis] + sign * a.half[axis]) - (b.center[axis] + sign * b.half[axis]))
					if gap < minGap - 1e-6 then
						table.insert(
							found,
							string.format(
								"%s/%s face %s%s (écart %.3f)",
								a.label,
								b.label,
								sign > 0 and "+" or "-",
								axis,
								gap
							)
						)
					end
				end
			end
		end
		return found
	end

	-- Cette méthode permet de lister, par pièce porteuse, les boîtes à comparer (corps, coque des marques si le matériau
	-- retire l'atlas, blocs) lorsqu'un test contrôle une déclinaison de mannequin à lancer.
	local function boxesByPiece(variant)
		local byPiece = {}
		for _, piece in DummyShape.PIECES do
			byPiece[piece.name] = { { center = Vector3.zero, half = piece.size / 2, label = piece.name, body = true } }
			if
				DummyShape.MARKED[piece.name]
				and variant.material
				and variant.material ~= roblox.Enum.Material.SmoothPlastic
			then
				local half = piece.size / 2 + Vector3.one * DummyShape.MARKS_GAP
				table.insert(byPiece[piece.name], { center = Vector3.zero, half = half, label = piece.name .. "Marks" })
			end
		end
		for index, block in variant.blocks or {} do
			table.insert(
				byPiece[block.piece],
				{ center = block.offset, half = block.size / 2, label = "Block" .. index }
			)
		end
		return byPiece
	end

	T.describe("FaceClearance (#161)", function()
		T.it("l'écart de la coque des marques dépasse le minimum", function()
			T.expect(DummyShape.MARKS_GAP >= DummyShape.MIN_FACE_GAP, "écart des marques sous le minimum")
		end)

		T.it("aucune face coplanaire sur les blocs des mannequins à lancer", function()
			local all = {}
			local count = 0
			for index = 1, #ThrowDummies.LIST do
				count += 1
				for piece, boxes in boxesByPiece(ThrowDummies.variant(index)) do
					for i = 1, #boxes do
						for j = i + 1, #boxes do
							if not (boxes[i].body and boxes[j].label:match("Marks$")) then
								for _, issue in coplanar(boxes[i], boxes[j], DummyShape.MIN_FACE_GAP) do
									table.insert(all, ThrowDummies.get(index).id .. " " .. piece .. " : " .. issue)
								end
							end
						end
					end
				end
			end
			T.expectEqual(#all, 0, table.concat(all, " | "))
			T.expect(count >= 20, "catalogue complet : " .. count)
		end)
	end)
end
