-- Scène de prise de vue des planches de référence (#121, Studio seulement) : l'attribut PhotoShot de Workspace (nom
-- d'une prise de Shared.PlanchePlan, posé par le MCP en contexte Server) pose la prise ; Client.PhotoCamera y cadre la
-- caméra, puis le MCP capture l'écran. Mannequins : construits comme en jeu (Shared.DummyShape, déclinaisons de
-- Shared.Collection avec leur aura et de Shared.ThrowDummies), en rangée devant un fond neutre au-dessus du hub, face au
-- soleil. Base et appareil : une place libre habillée au palier voulu (Server.BaseService, Server.CourseBuilder),
-- photographiée en place. Attribut retiré : scène détruite, place rendue à son état vide.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Collection = require(Shared.Collection)
local CourseLayout = require(Shared.CourseLayout)
local DummyShape = require(Shared.DummyShape)
local GameConfig = require(Shared.GameConfig)
local PlanchePlan = require(Shared.PlanchePlan)
local ThrowDummies = require(Shared.ThrowDummies)

local BaseService = require(script.Parent.BaseService)
local CourseBuilder = require(script.Parent.CourseBuilder)

type Slot = CourseBuilder.Slot

local PhotoStudio = {}

local ORIGIN = Vector3.new(0, 300, -260) -- sol de la scène : au-dessus du hub (ciel de jour, chargé avec le hub)
local BACKDROP = Color3.fromRGB(70, 75, 90) -- fond neutre sombre : les auras et néons ne le délavent pas
local BACK_GAP = 16 -- du plan des mannequins au fond (studs) : hors de portée des lumières des auras
local FEET = 3.82 -- du centre du torse au bas des pieds, échelle 1 (Shared.DummyShape)
-- Cadrage de la base : vue plongeante face à l'entrée, appareil et pad de part et d'autre (ils ne la masquent pas)
local BASE_VIEW = { aim = Vector3.new(4, 0, 0), from = Vector3.new(1, 1.2, 0), width = 92 }
-- Cadrage de l'appareil d'entraînement : de face, un peu au-dessus (podium, râtelier et ses trois mannequins) ;
-- tools/planches.py en garde le centre en 4:3
local STATION_VIEW = { aim = Vector3.new(0, 4.5, 0), from = Vector3.new(1, 0.5, 0.35), width = 44 }

local slots: { Slot } = {}
local scene: Folder? = nil
local staged: Slot? = nil -- place libre habillée par la prise en cours

-- Cette méthode permet de donner les places occupées par un joueur lorsque l'on choisit ou rend la place photographiée.
local function takenSlots(): { [number]: boolean }
	local taken = {}
	for _, player in Players:GetPlayers() do
		local index = player:GetAttribute("Slot")
		if typeof(index) == "number" then
			taken[index] = true
		end
	end
	return taken
end

-- Cette méthode permet de choisir la place sans joueur à photographier (la dernière libre) lorsqu'une prise de base
-- ou d'appareil commence ; nil si le lobby est plein.
local function freeSlot(): Slot?
	local taken = takenSlots()
	for index = #slots, 1, -1 do
		if not taken[index] then
			return slots[index]
		end
	end
	return nil
end

-- Cette méthode permet de rendre la place habillée à son état vide (palier 1, présentoirs de départ) lorsque la
-- prise change ou que la séance se termine.
local function restoreSlot()
	if not staged then
		return
	end
	if takenSlots()[staged.index] then
		-- Un joueur a pris la place pendant la séance : sa base n'est pas vidée (playtest à relancer pour la revoir)
		warn("[planches] place " .. staged.index .. " prise pendant la séance : relancer le playtest")
	else
		BaseService.showcase(staged, nil)
		CourseBuilder.styleStation(staged, 1)
	end
	staged = nil
end

-- Cette méthode permet de poser la pièce invisible de cadrage (position = point visé, LookVector = sens de la vue,
-- largeur à remplir) que lit Client.PhotoCamera lorsque la prise est prête.
local function frame(parent: Instance, shot: string, aim: Vector3, look: Vector3, width: number)
	local part = Instance.new("Part")
	part.Name = PlanchePlan.FRAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.lookAt(aim, aim + look)
	part:SetAttribute("Shot", shot)
	part:SetAttribute("Width", width)
	part.Parent = parent
end

-- Cette méthode permet de poser un bloc neutre ancré (sol ou fond) lorsque l'on monte le décor d'une rangée.
local function slab(parent: Instance, size: Vector3, cframe: CFrame)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = BACKDROP
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
end

-- Cette méthode permet de construire le mannequin d'une case (échelle 1, comme sur un présentoir ou une vitrine) lorsque
-- l'on monte une rangée.
local function buildDummy(item: PlanchePlan.Item): Model
	local variant = if item.kind == "collection"
		then Collection.variant({ id = item.key :: string, size = 1 })
		else ThrowDummies.variant(item.key :: number)
	local model = DummyShape.buildVisual(1, variant :: DummyShape.Variant)
	model.Name = "Photo_" .. tostring(item.key);
	(model.PrimaryPart :: BasePart).Anchored = true
	return model
end

-- Cette méthode permet de monter une rangée de mannequins (une case par mannequin, de gauche à droite à l'image) face
-- au soleil, devant un fond neutre, lorsqu'une prise « row » commence.
local function stageRow(parent: Instance, shot: PlanchePlan.Shot)
	local sun = Lighting:GetSunDirection()
	local flat = Vector3.new(sun.X, 0, sun.Z)
	-- Caméra du côté du soleil : mannequins éclairés de face, leurs ombres tombent derrière eux
	local look = if flat.Magnitude > 0.05 then -flat.Unit else Vector3.new(0, 0, 1)
	local right = look:Cross(Vector3.yAxis).Unit
	local width = PlanchePlan.ROW * PlanchePlan.CELL_WIDTH
	local aim = ORIGIN + Vector3.new(0, PlanchePlan.CELL_HEIGHT / 2 - 1, 0)
	local basis = CFrame.lookAt(ORIGIN, ORIGIN + look)
	slab(parent, Vector3.new(width + 60, 1, 50), basis * CFrame.new(0, -0.5, -BACK_GAP + 25))
	slab(parent, Vector3.new(width + 60, 50, 1), basis * CFrame.new(0, 20, -BACK_GAP - 0.5))
	for index, item in shot.items do
		local x = (index - (PlanchePlan.ROW + 1) / 2) * PlanchePlan.CELL_WIDTH
		local position = ORIGIN + right * x + Vector3.new(0, FEET, 0)
		local model = buildDummy(item)
		model:PivotTo(CFrame.lookAt(position, position - look))
		model.Parent = parent
	end
	frame(parent, shot.name, aim, look, width)
end

-- Cette méthode permet d'habiller la place libre au palier de la prise (base ou appareil) et d'en poser le cadrage
-- lorsqu'une prise « base » ou « station » commence ; false si aucune place n'est libre.
local function stageSlot(parent: Instance, shot: PlanchePlan.Shot): boolean
	local slot = freeSlot()
	if not slot then
		return false
	end
	staged = slot
	local tier = shot.items[1].key :: number
	local side = CourseLayout.entranceSide(slot.index)
	local mirror = Vector3.new(side, 1, 1) -- vues décrites pour une entrée vers +X
	local center, view
	if shot.framing == "base" then
		BaseService.showcase(slot, GameConfig.DISPLAY_START + tier - 1)
		center, view = CourseLayout.basePosition(slot.index), BASE_VIEW
	else
		CourseBuilder.styleStation(slot, tier)
		center, view = CourseLayout.stationPosition(slot.index), STATION_VIEW
	end
	frame(parent, shot.name, center + view.aim * mirror, -(view.from * mirror).Unit, view.width)
	return true
end

-- Cette méthode permet de poser la prise `name` (ou de tout retirer si nil) lorsque l'attribut PhotoShot change.
local function stage(name: string?)
	if scene then
		scene:Destroy()
		scene = nil
	end
	restoreSlot()
	if name == nil or name == "" then
		print("[planches] scène retirée")
		return
	end
	local shot = PlanchePlan.find(name)
	if not shot then
		warn("[planches] prise inconnue : " .. name)
		return
	end
	if DummyShape.meshStage() < 2 then
		warn("[planches] maillages des mannequins pas tous chargés : attendre, retirer PhotoShot (nil) puis reposer la prise")
	end
	local folder = Instance.new("Folder")
	folder.Name = "PhotoStudio"
	if shot.framing == "row" then
		stageRow(folder, shot)
	elseif not stageSlot(folder, shot) then
		warn("[planches] aucune place libre pour " .. name)
		return
	end
	folder.Parent = Workspace
	scene = folder
	print(string.format("[planches] %s prête (%d case(s))", name, #shot.items))
end

-- Cette méthode permet de brancher l'attribut PhotoShot de Workspace sur la scène lorsque le serveur démarre en
-- Studio (après Server.BaseService).
function PhotoStudio.init(builtSlots: { Slot })
	slots = builtSlots
	Workspace:GetAttributeChangedSignal(PlanchePlan.SHOT):Connect(function()
		local value = Workspace:GetAttribute(PlanchePlan.SHOT)
		stage(if type(value) == "string" then value else nil)
	end)
end

return PhotoStudio
