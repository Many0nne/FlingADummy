-- Plan des obstacles de la piste (logique pure, testée) : dans chaque zone, une rangée de vitres (repère de distance,
-- cadre aux couleurs du thème), ses obstacles cassables à tour de rôle et son piège signature, répartis à intervalles
-- réguliers ; puis les boîtes de déclenchement des pièges (une par colonne d'obstacles). Construit par
-- Server.Obstacles, lu par Server.LaunchService.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CourseLayout = require(Shared:WaitForChild("CourseLayout"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Traps = require(Shared:WaitForChild("Traps"))
local Zones = require(Shared:WaitForChild("Zones"))

local TrackPlan = {}

export type Site = {
	zone: number, -- indice de la zone (Shared.Zones)
	kind: string, -- "Glass" | "Obstacle" | "Trap"
	name: string, -- obstacle (Server.ThemeObstacles) ou piège (Shared.Traps) ; "Glass" pour les vitres
	z: number, -- distance du site sur la piste (m)
}

export type TrapBox = {
	id: number,
	site: number, -- piège (site) auquel appartient la boîte : un vol ne le déclenche qu'une fois, toutes colonnes confondues
	kind: string, -- Shared.Traps.KINDS
	zone: number,
	column: number, -- colonne d'obstacles (1 à SLOT_COUNT)
	x: number,
	z: number,
	center: Vector3,
	size: Vector3,
}

TrackPlan.FIRST_SITE = 22 -- rien avant : le mannequin vient de quitter la main (m)
TrackPlan.START_GAP = 8 -- dégagement après l'entrée d'une zone (ligne, panneaux) (m)
TrackPlan.END_GAP = 6 -- dégagement avant la zone suivante (m)
TrackPlan.SPACING = 35 -- écart visé entre deux sites (m)
TrackPlan.MIN_SITES = 3 -- obstacles et pièges d'une zone, au moins…
TrackPlan.MAX_SITES = 8 -- … et au plus (zones longues : sites plus espacés)
TrackPlan.TRAP_EVERY = 150 -- un piège de plus par tranche de 150 m (zones longues), au plus un site sur trois
TrackPlan.GLASS_SITE = 2 -- les vitres prennent le 2e site de chaque zone

-- Cette méthode permet de donner la hauteur d'une rangée de vitres (ou d'un piège en colonne) à `z` lorsque l'on la
-- construit : plus elle est loin, plus elle est haute, pour rester sur la trajectoire des lancers puissants.
function TrackPlan.glassHeight(z: number): number
	return math.clamp(30 + z * 0.15, 30, 320)
end

-- Cette méthode permet de répartir les sites d'une zone (vitres, obstacles à tour de rôle, pièges espacés) lorsque
-- l'on construit la piste ; `courseLength` borne la dernière zone.
function TrackPlan.zoneSites(index: number, courseLength: number): { Site }
	local zone = Zones.LIST[index]
	local start, finish = zone.start, Zones.finish(index, courseLength)
	local length = finish - start
	local low = math.max(start + TrackPlan.START_GAP, TrackPlan.FIRST_SITE)
	local high = finish - TrackPlan.END_GAP
	local base = math.clamp(math.floor(length / TrackPlan.SPACING + 0.5), TrackPlan.MIN_SITES, TrackPlan.MAX_SITES)
	local trapCount = math.max(1, math.min(math.floor(length / TrackPlan.TRAP_EVERY), math.floor(base / 3)))
	-- Assez de sites pour poser chaque obstacle du thème au moins une fois
	local count = math.max(base, #zone.obstacles + trapCount) + 1 -- + la rangée de vitres
	local glassAt = math.min(TrackPlan.GLASS_SITE, count)
	local trapAt: { [number]: boolean } = {}
	for j = 1, trapCount do
		-- Place visée, sinon la plus proche libre (ni vitres, ni autre piège), d'un côté ou de l'autre
		local wanted = math.clamp(math.floor(j * (count + 1) / (trapCount + 1) + 0.5), 1, count)
		for shift = 0, count do
			local candidates = { wanted + shift, wanted - shift }
			local placed = false
			for _, at in candidates do
				if at >= 1 and at <= count and at ~= glassAt and not trapAt[at] then
					trapAt[at] = true
					placed = true
					break
				end
			end
			if placed then
				break
			end
		end
	end
	local sites = {}
	local nextObstacle = 1
	for k = 1, count do
		local z = low + (high - low) * (k - 1) / math.max(count - 1, 1)
		z = math.floor(z * 2 + 0.5) / 2 -- au demi-mètre : positions lisibles et reproductibles
		if k == glassAt then
			table.insert(sites, { zone = index, kind = "Glass", name = "Glass", z = z })
		elseif trapAt[k] then
			table.insert(sites, { zone = index, kind = "Trap", name = zone.trap, z = z })
		else
			local name = zone.obstacles[(nextObstacle - 1) % #zone.obstacles + 1]
			nextObstacle += 1
			table.insert(sites, { zone = index, kind = "Obstacle", name = name, z = z })
		end
	end
	return sites
end

-- Cette méthode permet de donner tous les sites de la piste, zone après zone, lorsque le serveur la construit.
function TrackPlan.sites(courseLength: number): { Site }
	local all = {}
	for index in Zones.LIST do
		for _, site in TrackPlan.zoneSites(index, courseLength) do
			table.insert(all, site)
		end
	end
	return all
end

-- Cette méthode permet de donner la boîte de déclenchement du piège `kind` de la colonne centrée sur `x` à `z`
-- lorsque l'on pose le piège ou que l'on suit un vol : largeur de colonne, du sol à sa hauteur (ou à celle des vitres).
function TrackPlan.trapBox(kind: string, x: number, z: number): (Vector3, Vector3)
	local def = Traps.KINDS[kind]
	local height = def.height or TrackPlan.glassHeight(z)
	local size = Vector3.new(Traps.WIDTH, height - Traps.FLOOR, def.depth)
	return Vector3.new(x, Traps.FLOOR + size.Y / 2, z), size
end

-- Cette méthode permet de donner les boîtes de tous les pièges de la piste (une par colonne d'obstacles), numérotées,
-- lorsque le serveur construit la piste.
function TrackPlan.trapBoxes(sites: { Site }): { TrapBox }
	local boxes = {}
	local trapSite = 0
	for _, site in sites do
		if site.kind == "Trap" then
			trapSite += 1
			for column = 1, GameConfig.SLOT_COUNT do
				local x = CourseLayout.slotX(column)
				local center, size = TrackPlan.trapBox(site.name, x, site.z)
				table.insert(boxes, {
					id = #boxes + 1,
					site = trapSite,
					kind = site.name,
					zone = site.zone,
					column = column,
					x = x,
					z = site.z,
					center = center,
					size = size,
				})
			end
		end
	end
	return boxes
end

return TrackPlan
