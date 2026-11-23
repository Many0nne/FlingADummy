-- Compte les instances du décor généré (#115) : construit tout le décor sous Lune (tests/lib/DecorBuild, vrai code de
-- Server.CourseBuilder, tirages simulés) et donne le total, par zone de la piste et avant / après 2,4 km.
-- Usage depuis la racine du dépôt : lune run tools/decor-count.luau
local DecorBuild = require("../tests/lib/DecorBuild")
local Loader = require("../tests/lib/Loader")

local scene = DecorBuild.build(Loader)
local course = scene.course
local Zones = scene.loader:require("src/shared/Zones")

local FAR = scene.CourseBuilder.FAR_START
local total = #course:GetDescendants()
local near, far = 0, 0
local lines = {}
for index, zone in Zones.LIST do
	local folder = course:FindFirstChild("Zone" .. index)
	local count = if folder then #folder:GetDescendants() + 1 else 0
	if zone.start >= FAR then
		far += count
	else
		near += count
	end
	table.insert(lines, string.format("  %-15s %5d", zone.name, count))
end
print(string.format("[decor] %d instances sous Course", total))
print(table.concat(lines, "\n"))
print(string.format("[decor] zones avant %d m : %d ; zones depuis %d m : %d ; reste (hub, obstacles, bout) : %d", FAR, near, FAR, far, total - near - far))
