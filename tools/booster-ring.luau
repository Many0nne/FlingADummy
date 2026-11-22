-- Anneau propulseur de la Moon Base (#98) : hauteur du torse aux sites du piège « Booster » et taux de passage dans le
-- cerceau (simulation : tools/BoosterRingSim, plan de vol du serveur sans obstacle ni piège).
-- Usage : lune run tools/booster-ring [raison des puissances, 1.25] [pas de jauge, 0.05] [bas de la boîte, celui de
-- Traps.KINDS.Booster] [haut de la boîte, idem] (les deux derniers : essai d'un autre cerceau)
local process = require("@lune/process")

local Loader = require("../tests/lib/Loader")
local Sim = require("./BoosterRingSim")

local m = Sim.modules(Loader.new())
local def = m.Traps.KINDS.Booster
local step = tonumber(process.args[1])
local gaugeStep = tonumber(process.args[2])
local bottom = tonumber(process.args[3]) or def.bottom or m.Traps.FLOOR
local top = tonumber(process.args[4]) or def.height

local sites = Sim.sites(m)
print(string.format("Anneau : bas %.1f, haut %.1f, sites (m) : %s", bottom, top, table.concat(sites, ", ")))

-- Mannequins à lancer de base : Rubber, Glass et Steel volent comme le Crash Dummy jusqu'au premier contact, les
-- suivants du catalogue ont les mêmes comportements que les six de base
for _, index in { 1, 5, 6 } do
	local thrown = m.ThrowDummies.get(index)
	local flights = Sim.flights(m, thrown, step, gaugeStep)
	print(string.format("== %s (%d vols simulés)", thrown.name, #flights))
	-- Par vol : passe-t-il en l'air au-dessus d'au moins un site, et dans un anneau ?
	local flying, boosted = 0, 0
	for _, flight in flights do
		local over, hit = false, false
		for _, z in sites do
			local height = Sim.heightAt(flight, z)
			if height then
				over = true
				hit = hit or (height >= bottom and height <= top)
			end
		end
		flying += if over then 1 else 0
		boosted += if hit then 1 else 0
	end
	print(
		string.format(
			"  au moins un site : %d vols en l'air au-dessus, %d dans un anneau (%.0f %%)",
			flying,
			boosted,
			if flying > 0 then 100 * boosted / flying else 0
		)
	)
	for _, z in sites do
		local heights = Sim.heights(flights, z)
		local function pct(p: number): number
			return heights[math.max(1, math.floor(#heights * p))] or 0
		end
		print(
			string.format(
				"  site %.0f m : %d en l'air, %.0f %% dans l'anneau ; hauteur du torse p10 %.0f, p50 %.0f, p90 %.0f (min %.0f, max %.0f)",
				z,
				#heights,
				100 * Sim.share(heights, bottom, top),
				pct(0.1),
				pct(0.5),
				pct(0.9),
				heights[1] or 0,
				heights[#heights] or 0
			)
		)
	end
end
