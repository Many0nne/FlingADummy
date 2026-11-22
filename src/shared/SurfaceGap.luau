-- Faces confondues du décor (#93) : deux pièces dont des faces de même sens sont dans le même plan (à moins de MIN_GAP)
-- et se recouvrent scintillent quand la caméra bouge (z-fighting). Règle du testeur : un élément posé sur un autre
-- ressort toujours un peu. Logique pure : Server.Build l'applique à la pose (une pièce qui affleure une pièce déjà posée
-- du même élément ressort de STEP), le garde-fou des tests la vérifie sur tout le décor.
local SurfaceGap = {}

SurfaceGap.MIN_GAP = 0.05 -- écart minimal entre deux faces de même sens qui se recouvrent (studs)
SurfaceGap.STEP = 0.1 -- avancée d'une face qui affleure une autre
SurfaceGap.OVERLAP = 0.05 -- recouvrement négligeable en dessous (pièces qui se touchent par un bord)
SurfaceGap.TOLERANCE = 1e-3 -- arrondis des positions (un écart voulu de 0,05 vaut 0,0499…)
local PARALLEL = 0.999 -- produit scalaire minimal entre deux normales de même sens
local MAX_PASSES = 6 -- une avancée peut en créer une autre : quelques passes au plus

export type Box = { cframe: CFrame, size: Vector3 }

-- Face d'une boîte : normale, position du plan, centre, axes du rectangle et demi-côtés
export type Face = {
	axis: number, -- 1, 2, 3 : axe X, Y, Z de la boîte
	sign: number, -- +1 ou -1
	normal: Vector3,
	d: number,
	center: Vector3,
	u: Vector3,
	v: Vector3,
	hu: number,
	hv: number,
}

-- Cette méthode permet de lister les 6 faces d'une boîte lorsque l'on compare deux pièces.
function SurfaceGap.faces(box: Box): { Face }
	local cf, half = box.cframe, box.size / 2
	local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local halves = { half.X, half.Y, half.Z }
	local out = {}
	for i = 1, 3 do
		local j, k = i % 3 + 1, (i + 1) % 3 + 1
		for _, sign in { 1, -1 } do
			local normal = axes[i] * sign
			local center = cf.Position + normal * halves[i]
			table.insert(out, {
				axis = i,
				sign = sign,
				normal = normal,
				d = normal:Dot(center),
				center = center,
				u = axes[j],
				v = axes[k],
				hu = halves[j],
				hv = halves[k],
			})
		end
	end
	return out
end

-- Cette méthode permet de mesurer le recouvrement de deux rectangles d'un même plan (axes séparateurs) lorsque deux
-- faces sont dans le même plan ; négatif ou nul s'ils ne font que se toucher.
function SurfaceGap.overlap(a: Face, b: Face): number
	local depth = math.huge
	for _, w in { a.u, a.v, b.u, b.v } do
		local ra = math.abs(a.u:Dot(w)) * a.hu + math.abs(a.v:Dot(w)) * a.hv
		local rb = math.abs(b.u:Dot(w)) * b.hu + math.abs(b.v:Dot(w)) * b.hv
		depth = math.min(depth, ra + rb - math.abs((a.center - b.center):Dot(w)))
	end
	return depth
end

-- Cette méthode permet de savoir si deux faces scintillent (même sens, écart sous MIN_GAP, rectangles qui se
-- recouvrent) lorsque l'on compare deux pièces ; renvoie aussi l'écart.
function SurfaceGap.clash(a: Face, b: Face): (boolean, number)
	if a.normal:Dot(b.normal) < PARALLEL then
		return false, math.huge
	end
	local gap = math.abs(a.d - a.normal:Dot(b.center))
	if gap >= SurfaceGap.MIN_GAP - SurfaceGap.TOLERANCE then
		return false, gap
	end
	return SurfaceGap.overlap(a, b) > SurfaceGap.OVERLAP, gap
end

-- Cette méthode permet de donner la boîte englobante (coins bas et haut, axes du monde) d'une boîte orientée lorsque
-- l'on écarte d'emblée deux pièces trop loin pour se toucher.
function SurfaceGap.bounds(cframe: CFrame, size: Vector3): (Vector3, Vector3)
	local half = size / 2
	local x, y, z = cframe.XVector, cframe.YVector, cframe.ZVector
	local extent = Vector3.new(
		math.abs(x.X) * half.X + math.abs(y.X) * half.Y + math.abs(z.X) * half.Z,
		math.abs(x.Y) * half.X + math.abs(y.Y) * half.Y + math.abs(z.Y) * half.Z,
		math.abs(x.Z) * half.X + math.abs(y.Z) * half.Y + math.abs(z.Z) * half.Z
	)
	return cframe.Position - extent, cframe.Position + extent
end

-- Pièce déjà posée, avec ses faces et sa boîte englobante (en nombres : comparaisons rapides) calculées une fois ;
-- `part` : l'Instance, que l'appelant peut écarter si elle a changé de forme depuis (SurfaceGap.settle, `keep`)
export type Placed = {
	box: Box,
	part: any?,
	faces: { Face }?, -- calculées à la première comparaison
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
}

-- Cette méthode permet de préparer une pièce posée (faces, boîte englobante) lorsqu'on l'ajoute à la liste que
-- SurfaceGap.settle compare aux pièces suivantes.
function SurfaceGap.place(size: Vector3, cframe: CFrame): Placed
	local box = { size = size, cframe = cframe }
	local low, high = SurfaceGap.bounds(cframe, size)
	return {
		box = box,
		faces = nil,
		x0 = low.X,
		y0 = low.Y,
		z0 = low.Z,
		x1 = high.X,
		y1 = high.Y,
		z1 = high.Z,
	}
end

-- Cette méthode permet de faire ressortir une nouvelle pièce (taille `size`, repère `cframe`) de STEP sur chaque face
-- qui affleure une face d'une pièce déjà posée (`placed`), lorsque l'on pose un élément de décor ; renvoie la taille et
-- le repère corrigés (inchangés sans faces confondues). `keep(other)` (facultatif) écarte une pièce posée qui n'est
-- plus un bloc visible.
function SurfaceGap.settle(
	placed: { Placed },
	size: Vector3,
	cframe: CFrame,
	keep: ((Placed) -> boolean)?
): (Vector3, CFrame)
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	local margin = SurfaceGap.MIN_GAP
	for _ = 1, MAX_PASSES do
		local low, high = SurfaceGap.bounds(cframe, size)
		local x0, y0, z0 = low.X - margin, low.Y - margin, low.Z - margin
		local x1, y1, z1 = high.X + margin, high.Y + margin, high.Z + margin
		local mine = nil
		-- Faces à faire avancer (une fois par passe, même contre plusieurs pièces) : [axe][sens]
		local push = { { [1] = false, [-1] = false }, { [1] = false, [-1] = false }, { [1] = false, [-1] = false } }
		local moved = false
		for _, other in placed do
			-- Boîtes englobantes séparées : pas de faces communes
			if
				other.x0 <= x1
				and x0 <= other.x1
				and other.y0 <= y1
				and y0 <= other.y1
				and other.z0 <= z1
				and z0 <= other.z1
				and (keep == nil or keep(other))
			then
				mine = mine or SurfaceGap.faces({ size = size, cframe = cframe })
				other.faces = other.faces or SurfaceGap.faces(other.box)
				for _, face in other.faces :: { Face } do
					for _, own in mine do
						if not push[own.axis][own.sign] and SurfaceGap.clash(face, own) then
							push[own.axis][own.sign] = true
							moved = true
						end
					end
				end
			end
		end
		if not moved then
			return size, cframe
		end
		local offset = Vector3.zero
		for i = 1, 3 do
			local plus = if push[i][1] then 1 else 0
			local minus = if push[i][-1] then 1 else 0
			size += axes[i] * SurfaceGap.STEP * (plus + minus)
			offset += axes[i] * SurfaceGap.STEP / 2 * (plus - minus)
		end
		cframe = cframe * CFrame.new(offset)
	end
	return size, cframe
end

return SurfaceGap
