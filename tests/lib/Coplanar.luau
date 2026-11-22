-- Garde-fou des faces confondues du décor (#93) : cherche, parmi des boîtes orientées, les paires de faces qui
-- scintillent (Shared.SurfaceGap.clash : même sens, même plan, rectangles qui se recouvrent), sauf si une troisième pièce
-- opaque recouvre la zone commune (face posée contre un autre bloc) ou si la face regarde le sol sous le niveau du sol.
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3

local Coplanar = {}

export type Box = { cframe: roblox.CFrame, size: roblox.Vector3, label: string, opaque: boolean }
export type Hit = { a: Box, b: Box, gap: number, at: roblox.Vector3, normal: roblox.Vector3 }

local PROBE = 0.02 -- distance de la face où l'on cherche une pièce qui la cache
local CELL = 16 -- côté des cellules de la recherche de pièces qui cachent une face

-- Cette méthode permet de savoir si un point est dans une boîte (bords compris) lorsque l'on cherche ce qui cache une
-- face.
local function inside(box: Box, point): boolean
	local p = box.cframe:PointToObjectSpace(point)
	local half = box.size / 2 + Vector3.one * 1e-4
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

-- Cette méthode permet de donner la boîte englobante (coins bas et haut) d'un rectangle de face lorsque l'on range les
-- faces pour le balayage.
local function bounds(face): (any, any)
	local extent = Vector3.new(
		math.abs(face.u.X) * face.hu + math.abs(face.v.X) * face.hv,
		math.abs(face.u.Y) * face.hu + math.abs(face.v.Y) * face.hv,
		math.abs(face.u.Z) * face.hu + math.abs(face.v.Z) * face.hv
	)
	return face.center - extent, face.center + extent
end

-- Cette méthode permet de chercher les faces confondues visibles de `boxes` lorsqu'un test contrôle le décor
-- (`SurfaceGap` : Shared.SurfaceGap chargé par le test) ; renvoie un relevé par paire de faces.
function Coplanar.find(boxes: { Box }, SurfaceGap): { Hit }
	local minGap = SurfaceGap.MIN_GAP
	-- Faces rangées par sens (normale arrondie) et tranche de plan (largeur minGap) : une face ne se compare qu'à sa
	-- tranche et à la suivante
	local buckets = {}
	for index, box in boxes do
		for _, face in SurfaceGap.faces(box) do
			local n = face.normal
			if not SurfaceGap.unseen(face) then
				face.index = index
				face.min, face.max = bounds(face)
				-- Bornes en nombres : balayage rapide
				face.x0, face.y0, face.z0 = face.min.X, face.min.Y, face.min.Z
				face.x1, face.y1, face.z1 = face.max.X, face.max.Y, face.max.Z
				local key = string.format(
					"%d,%d,%d|%d",
					math.round(n.X * 1000),
					math.round(n.Y * 1000),
					math.round(n.Z * 1000),
					math.floor(face.d / minGap)
				)
				buckets[key] = buckets[key] or {}
				table.insert(buckets[key], face)
			end
		end
	end

	-- Pièces opaques rangées par cellules (pour savoir si une zone de face est cachée)
	local grid: { [string]: { number } } = {}
	for index, box in boxes do
		if box.opaque then
			local cf, half = box.cframe, box.size / 2
			local extent = Vector3.new(
				math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
				math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
				math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
			)
			local lo, hi = (cf.Position - extent) / CELL, (cf.Position + extent) / CELL
			for x = math.floor(lo.X), math.floor(hi.X) do
				for y = math.floor(lo.Y), math.floor(hi.Y) do
					for z = math.floor(lo.Z), math.floor(hi.Z) do
						local key = x .. "," .. y .. "," .. z
						grid[key] = grid[key] or {}
						table.insert(grid[key], index)
					end
				end
			end
		end
	end
	-- Cette méthode permet de savoir si une pièce opaque autre que `a`, `b` contient le point lorsque l'on teste si la
	-- zone commune est cachée.
	local function covered(point, a: number, b: number): boolean
		local key = math.floor(point.X / CELL) .. "," .. math.floor(point.Y / CELL) .. "," .. math.floor(point.Z / CELL)
		for _, index in grid[key] or {} do
			if index ~= a and index ~= b and inside(boxes[index], point) then
				return true
			end
		end
		return false
	end

	local hits: { Hit } = {}
	-- Cette méthode permet de relever deux faces confondues si une partie de leur zone commune reste visible lorsque
	-- leurs boîtes englobantes se touchent.
	local function compare(a, b)
		if a.index == b.index then
			return
		end
		local clash, gap = SurfaceGap.clash(a, b)
		if not clash then
			return
		end
		-- Zone commune approchée par l'intersection des boîtes englobantes des deux faces, sondée juste devant
		local lo = Vector3.new(math.max(a.min.X, b.min.X), math.max(a.min.Y, b.min.Y), math.max(a.min.Z, b.min.Z))
		local hi = Vector3.new(math.min(a.max.X, b.max.X), math.min(a.max.Y, b.max.Y), math.min(a.max.Z, b.max.Z))
		local mid = (lo + hi) / 2
		local n = a.normal
		local front = mid + n * (math.max(a.d, b.d) + PROBE - n:Dot(mid))
		local spread = (hi - lo) / 2 * 0.9
		for _, sx in { 0, 1, -1 } do
			for _, sy in { 0, 1, -1 } do
				for _, sz in { 0, 1, -1 } do
					local offset = Vector3.new(spread.X * sx, spread.Y * sy, spread.Z * sz)
					local point = front + offset - n * n:Dot(offset)
					if not covered(point, a.index, b.index) then
						table.insert(hits, { a = boxes[a.index], b = boxes[b.index], gap = gap, at = mid, normal = n })
						return
					end
				end
			end
		end
	end
	for key, list in buckets do
		-- Tranche et tranche suivante, balayées ensemble le long de X ; les paires de la tranche suivante seule sont
		-- comparées quand c'est son tour
		local base, slice = string.match(key, "^(.*)|(-?%d+)$")
		local mine = {}
		local all = table.clone(list)
		for _, face in list do
			mine[face] = true
		end
		for _, face in buckets[(base :: string) .. "|" .. tostring((tonumber(slice) :: number) + 1)] or {} do
			table.insert(all, face)
		end
		table.sort(all, function(x, y)
			return x.x0 < y.x0
		end)
		local margin = SurfaceGap.OVERLAP
		for i = 1, #all do
			local a = all[i]
			local ax1, ay0, ay1, az0, az1 = a.x1 + margin, a.y0 - margin, a.y1 + margin, a.z0 - margin, a.z1 + margin
			for j = i + 1, #all do
				local b = all[j]
				if b.x0 > ax1 then
					break
				end
				if (mine[a] or mine[b]) and b.y0 <= ay1 and ay0 <= b.y1 and b.z0 <= az1 and az0 <= b.z1 then
					compare(a, b)
				end
			end
		end
	end
	return hits
end

return Coplanar
