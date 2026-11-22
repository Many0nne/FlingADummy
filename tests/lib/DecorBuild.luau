-- Construit tout le décor généré (Server.CourseBuilder : hub, bases, zone de lancer, piste, obstacles des thèmes,
-- pièges) sous Lune, avec de vraies Instances (@lune/roblox) et des services Roblox simulés, pour que les tests
-- contrôlent la géométrie du décor sans Studio (#93 : faces coplanaires). Seuls les tirages diffèrent du jeu (Random
-- simulé) : les règles de pose sont les mêmes, les positions des accessoires semés au hasard non.
local roblox = require("@lune/roblox")

local Instance = roblox.Instance

local DecorBuild = {}

-- Cette méthode permet de simuler Random (tirages déterministes, pas ceux de Roblox) lorsque le décor sème ses
-- accessoires.
local function newRandom(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	-- Cette méthode permet de tirer un réel dans [0, 1[ lorsque l'on avance le générateur (Park-Miller).
	local function next01(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	return {
		NextNumber = function(_, low: number?, high: number?)
			local a, b = low or 0, high or 1
			return a + (b - a) * next01()
		end,
		NextInteger = function(_, low: number, high: number)
			return math.min(high, low + math.floor(next01() * (high - low + 1)))
		end,
	}
end

-- Enveloppes des Instances Lune : `Position` et `Orientation` d'une pièce (non sérialisées, ignorées par Lune) y
-- passent par son CFrame, comme dans Roblox. Une enveloppe par Instance (comparaisons et clés de table justes) : Lune
-- rend une nouvelle valeur à chaque lecture d'une même Instance, retrouvée par un attribut numéroté.
local ID = "_DecorBuildId"
local wrappers: { [number]: any } = {}
local reals = setmetatable({}, { __mode = "k" })
local wrap

-- Cette méthode permet de retrouver l'Instance Lune d'une valeur (enveloppe ou non) lorsqu'on la passe à Lune.
local function unwrap(value: any): any
	return if type(value) == "table" and reals[value] then reals[value] else value
end

-- Cette méthode permet d'envelopper une valeur rendue par Lune (Instance, liste d'Instances) lorsque le décor la lit.
local function wrapValue(value: any): any
	if typeof(value) == "Instance" then
		return wrap(value)
	end
	if type(value) == "table" then
		local out = {}
		for key, item in value do
			out[key] = wrapValue(item)
		end
		return out
	end
	return value
end

-- Cette méthode permet de donner l'enveloppe d'une Instance Lune lorsque le décor la crée ou la retrouve.
function wrap(real: any): any
	local id = real:GetAttribute(ID)
	if id then
		return wrappers[id]
	end
	id = #wrappers + 1
	real:SetAttribute(ID, id)
	local isPart = real:IsA("BasePart")
	local proxy = setmetatable({}, {
		__index = function(_, key)
			if isPart and key == "Position" then
				return real.CFrame.Position
			end
			if isPart and key == "Orientation" then
				local rx, ry, rz = real.CFrame:ToOrientation()
				return roblox.Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
			end
			-- Physique absente sous Lune
			if isPart and key == "SetNetworkOwner" then
				return function() end
			end
			local value = real[key]
			if type(value) == "function" then
				return function(_, ...)
					local args = table.pack(...)
					for i = 1, args.n do
						args[i] = unwrap(args[i])
					end
					return wrapValue(value(real, table.unpack(args, 1, args.n)))
				end
			end
			return wrapValue(value)
		end,
		__newindex = function(_, key, value)
			if isPart and key == "Position" then
				real.CFrame = real.CFrame.Rotation + value
			elseif isPart and key == "Orientation" then
				local r = roblox.CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
				real.CFrame = r + real.CFrame.Position
			else
				real[key] = unwrap(value)
			end
		end,
		__tostring = function()
			return real:GetFullName()
		end,
	})
	wrappers[id] = proxy
	reals[proxy] = real
	return proxy
end

-- Cette méthode permet de donner un signal simulé (Connect sans effet) lorsqu'un module s'abonne à un événement.
local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end

-- Cette méthode permet de donner un service simulé qui accepte tous les appels sans effet lorsque le décor n'en attend
-- rien (physique, joueurs, animations).
local function inert()
	local service = {}
	return setmetatable(service, {
		__index = function(_, key)
			if key == "Heartbeat" or key == "Stepped" or key == "PlayerAdded" or key == "PlayerRemoving" then
				return signal()
			end
			return function()
				return setmetatable({}, {
					__index = function()
						return function() end
					end,
				})
			end
		end,
	})
end

DecorBuild.SOURCE = "_DecorSource" -- attribut des pièces : générateur qui les a posées (« Props.build Pine »…)

-- Cette méthode permet de construire le décor lorsqu'un test en contrôle la géométrie ; renvoie le dossier `Course`, le
-- résultat de CourseBuilder.build (places), le module et son chargeur.
function DecorBuild.build(Loader): any
	local workspace = wrap(Instance.new("Workspace")) -- avec son Terrain
	local source = "CourseBuilder"
	local calls = 0
	local tags: { [any]: { [string]: boolean } } = {}
	local collection = {
		AddTag = function(_, instance, tag)
			tags[instance] = tags[instance] or {}
			tags[instance][tag] = true
		end,
		RemoveTag = function(_, instance, tag)
			if tags[instance] then
				tags[instance][tag] = nil
			end
		end,
		HasTag = function(_, instance, tag)
			return tags[instance] ~= nil and tags[instance][tag] == true
		end,
		GetTagged = function()
			return {}
		end,
		GetInstanceAddedSignal = signal,
	}
	local loader = Loader.new({
		Workspace = workspace,
		Lighting = wrap(Instance.new("Lighting")),
		CollectionService = collection,
		RunService = inert(),
		TweenService = inert(),
		Players = inert(),
		PhysicsService = inert(),
	}, {
		Random = { new = newRandom },
		Instance = {
			new = function(className: string, parent: any?)
				local real = Instance.new(className)
				real:SetAttribute(DecorBuild.SOURCE, source)
				local instance = wrap(real)
				if parent then
					instance.Parent = parent
				end
				return instance
			end,
		},
		PhysicalProperties = roblox.PhysicalProperties,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		BrickColor = roblox.BrickColor,
		Font = roblox.Font,
		Rect = roblox.Rect,
		OverlapParams = {
			new = function()
				return {}
			end,
		},
		TweenInfo = {
			new = function()
				return {}
			end,
		},
		task = { delay = function() end, spawn = function() end, defer = function() end, wait = function() end },
		print = function() end,
	})
	-- Dossier des gabarits de mannequins absent (chargé par le jeu) : le râtelier attend son arrivée
	local replicated = loader.game:GetService("ReplicatedStorage")
	replicated.FindFirstChild = function()
		return nil
	end
	replicated.ChildAdded = signal()
	loader.services.ReplicatedStorage = replicated

	local ThemeObstacles = loader:require("src/server/ThemeObstacles")
	local TrapProps = loader:require("src/server/TrapProps")
	-- Générateur de chaque pièce : appel le plus extérieur d'une fonction de Props, ThemeObstacles ou TrapProps
	for name, module in
		{ Props = loader:require("src/server/Props"), ThemeObstacles = ThemeObstacles, TrapProps = TrapProps }
	do
		for key, fn in module do
			if type(fn) == "function" then
				module[key] = function(first, ...)
					if source ~= "CourseBuilder" then
						return fn(first, ...)
					end
					local detail = if type(first) == "string"
						then " " .. first
						elseif type(first) == "table" and type(rawget(first, "kind")) == "string" then " " .. rawget(
							first,
							"kind"
						)
						else ""
					calls += 1
					source = name .. "." .. key .. detail .. " #" .. calls
					local results = table.pack(pcall(fn, first, ...))
					source = "CourseBuilder"
					if not results[1] then
						error(results[2], 0)
					end
					return table.unpack(results, 2, results.n)
				end
			end
		end
	end
	local CourseBuilder = loader:require("src/server/CourseBuilder")
	local built = CourseBuilder.build()
	return { course = workspace:FindFirstChild("Course"), built = built, CourseBuilder = CourseBuilder, loader = loader }
end

-- Cette méthode permet de lister les blocs visibles (pièces pleines, pas entièrement transparentes) sous `root` lorsque
-- le garde-fou des faces confondues contrôle le décor ; chaque boîte est étiquetée par son générateur et son chemin.
function DecorBuild.boxes(root: any): { any }
	local boxes = {}
	for _, part in root:GetDescendants() do
		if part.ClassName == "Part" and part.Shape.Name == "Block" and part.Transparency < 1 then
			local label = string.format("%s %s", tostring(part:GetAttribute(DecorBuild.SOURCE)), part:GetFullName())
			table.insert(
				boxes,
				{ cframe = part.CFrame, size = part.Size, label = label, opaque = part.Transparency == 0 }
			)
		end
	end
	return boxes
end

return DecorBuild
