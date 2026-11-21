-- Effets de la révélation du tirage par palier de rareté (#67, paliers : Shared.RevealPlan ; orchestration :
-- Client.Prize) : confettis de la couleur de la rareté, ciel qui s'assombrit, explosion de particules, et la séquence
-- du secret calée sur la référence 09 (écran noir et phrase lettre à lettre, décor dédié avec tapis rouge, colonnes et
-- lumière dorée, portail qui s'ouvre, pluie de pièces, « SECRET!! » géant et cote complète). Tout est local au joueur ;
-- le décor du secret se construit au-dessus de la piste (rien ne le gêne), le passage se fait sous l'écran noir.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Format = require(Shared:WaitForChild("Format"))
local RevealPlan = require(Shared:WaitForChild("RevealPlan"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local WHITE = Color3.new(1, 1, 1)
local STAGE_HEIGHT = 350 -- le décor du secret flotte à cette hauteur au-dessus du point d'atterrissage (studs)
local CARPET_LENGTH = 80
local COLUMN_GAP = 12 -- studs entre deux paires de colonnes le long du tapis
local COLUMN_X = 14
local GOLD = Color3.fromRGB(205, 115, 35) -- orangé : la lumière dorée des lampes et le Bloom l'éclaircissent
local CARPET = Color3.fromRGB(150, 12, 24)
local PORTAL_RIM = Color3.fromRGB(255, 215, 200)
local PORTAL_CORE = Color3.fromRGB(120, 0, 14)

local RevealFx = {}

RevealFx.CARPET_LENGTH = CARPET_LENGTH -- longueur du tapis rouge (la caméra part de son bout)

local layer: ScreenGui -- confettis, pièces, bandeau « SECRET!! »
local cover: ScreenGui -- écran noir, devant tout le reste
local generation = 0 -- invalide les effets en cours (clear)
local stage: Folder? = nil
-- Lumière d'origine, gardée au premier assombrissement et rendue par restoreSky
type SavedSky = {
	clock: number,
	brightness: number,
	outdoor: Color3,
	atmosphere: Atmosphere?,
	atmosphereColor: Color3?,
	atmosphereDecay: Color3?,
}
local saved: SavedSky? = nil
local grading: ColorCorrectionEffect? = nil
local skyTweens: { Tween } = {} -- assombrissement en cours (annulé par restoreSky, sinon il réécrirait la lumière)
local loose: { Instance } = {} -- effets posés hors du décor (attachements du terrain), retirés avec lui

-- Cette méthode permet de créer une couche d'interface plein écran (sans marge du haut, ordre `order`) lorsque le
-- module démarre ; son échelle suit la taille de l'écran comme le HUD.
local function makeLayer(name: string, order: number): ScreenGui
	local screen = UIKit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = order,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	return screen
end

-- Cette méthode permet de donner l'échelle des textes (1 à 720 px de haut, bornée) lorsque le bandeau ou la phrase se
-- construisent.
local function textScale(): number
	local size = Workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(size.X / 1280, size.Y / 720), 0.5, 1.3)
end

-- Cette méthode permet de créer une pièce de décor locale (ancrée, sans collision ni requête) lorsque l'on construit
-- le décor du secret ou un effet.
local function part(props: { [string]: any }): Part
	local base = {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
	for key, value in props do
		base[key] = value
	end
	return UIKit.create("Part", base)
end

-- Cette méthode permet de savoir si un effet lancé à la génération `mine` doit continuer lorsqu'il reprend après une
-- attente (clear l'a peut-être annulé).
local function alive(mine: number): boolean
	return mine == generation
end

-- Cette méthode permet d'assombrir le ciel en `time` s (soir, ou nuit si `night`, teinte `color`) lorsque la
-- silhouette d'un Legendary ou plus apparaît, ou que le décor du secret s'affiche.
function RevealFx.darkenSky(color: Color3, night: boolean, time: number)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not saved then
		saved = {
			clock = Lighting.ClockTime,
			brightness = Lighting.Brightness,
			outdoor = Lighting.OutdoorAmbient,
			atmosphere = atmosphere,
			atmosphereColor = atmosphere and atmosphere.Color,
			atmosphereDecay = atmosphere and atmosphere.Decay,
		}
	end
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if not grading then
		grading = UIKit.create("ColorCorrectionEffect", { Name = "RevealDark", Parent = Lighting })
	end
	local goals: { { any } } = {
		{
			Lighting,
			{
				ClockTime = if night then 23.9 else 19.6,
				Brightness = if night then 0.6 else 1.4,
				OutdoorAmbient = Color3.fromRGB(70, 60, 95),
			},
		},
		{ grading, { TintColor = color:Lerp(WHITE, 0.7), Contrast = 0.15, Brightness = -0.04 } },
	}
	if atmosphere then
		table.insert(goals, { atmosphere, { Color = Color3.fromRGB(40, 30, 60), Decay = Color3.fromRGB(30, 20, 50) } })
	end
	for _, goal in goals do
		local tween = TweenService:Create(goal[1], info, goal[2])
		table.insert(skyTweens, tween)
		tween:Play()
	end
end

-- Cette méthode permet de rendre la lumière d'origine lorsque le tirage se termine (GO BACK, fin forcée).
function RevealFx.restoreSky()
	for _, tween in skyTweens do
		tween:Cancel()
	end
	skyTweens = {}
	local sky = saved
	saved = nil
	if grading then
		grading:Destroy()
		grading = nil
	end
	if not sky then
		return
	end
	-- Pose directe (le joueur repart au hub), les tweens d'assombrissement annulés ci-dessus
	Lighting.ClockTime = sky.clock
	Lighting.Brightness = sky.brightness
	Lighting.OutdoorAmbient = sky.outdoor
	if sky.atmosphere and sky.atmosphere.Parent then
		sky.atmosphere.Color = sky.atmosphereColor :: Color3
		sky.atmosphere.Decay = sky.atmosphereDecay :: Color3
	end
end

-- Cette méthode permet de faire pleuvoir `count` confettis (rectangles qui tournoient, couleur de la rareté, blanc et
-- or) du haut de l'écran lorsque le mannequin d'un Rare ou plus se révèle.
function RevealFx.confetti(color: Color3, count: number)
	if count <= 0 then
		return
	end
	local palette = { color, color:Lerp(WHITE, 0.45), WHITE, C.gold, color:Lerp(Color3.new(0, 0, 0), 0.2) }
	local s = textScale()
	for i = 1, count do
		local x = math.random()
		local piece = UIKit.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, -0.05 - math.random() * 0.1),
			Size = UDim2.fromOffset(math.random(8, 14) * s, math.random(14, 24) * s),
			Rotation = math.random(0, 360),
			BackgroundColor3 = palette[(i % #palette) + 1],
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = layer,
		})
		local fall = 1.6 + math.random() * 1.4
		task.delay(math.random() * 0.6, function()
			if not piece.Parent then
				return
			end
			TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.25, 1.08),
				Rotation = piece.Rotation + math.random(-720, 720),
			}):Play()
			task.delay(fall, function()
				piece:Destroy()
			end)
		end)
	end
end

-- Cette méthode permet de faire pleuvoir des pièces d'argent sur tout l'écran (icône « cash », comme la pluie de pièces
-- de la référence) lorsque le secret sort du portail.
function RevealFx.coinRain(count: number)
	local s = textScale()
	for i = 1, count do
		local x = math.random()
		local size = math.random(46, 86) * s
		local coin = UIKit.icon("cash", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, -0.1),
			Size = UDim2.fromOffset(size, size),
			Rotation = math.random(-30, 30),
			ZIndex = 3,
			Parent = layer,
		})
		local fall = 0.9 + math.random() * 0.8
		task.delay((i - 1) / count * 1.1, function()
			if not coin.Parent then
				return
			end
			TweenService:Create(coin, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.1, 1.15),
				Rotation = coin.Rotation + math.random(-180, 180),
			}):Play()
			task.delay(fall, function()
				coin:Destroy()
			end)
		end)
	end
	for k = 0, 3 do
		task.delay(k * 0.3, UIKit.playSound, "Cash", 1 + k * 0.08)
	end
end

-- Cette méthode permet de faire exploser des particules (gerbe d'étincelles à la couleur de la rareté, boule de
-- lumière et onde de choc au sol) autour de `center` lorsque le mannequin d'un Legendary ou plus se révèle.
function RevealFx.explosion(center: Vector3, ground: Vector3, scale: number, color: Color3)
	local ball = part({
		Name = "RevealBlast",
		Shape = Enum.PartType.Ball,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = color:Lerp(WHITE, 0.5),
		Transparency = 0.05,
		Size = Vector3.one * 3,
		Position = center,
		Parent = Workspace,
	})
	TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * (14 * scale + 6),
		Transparency = 1,
	}):Play()
	local wave = part({
		Name = "RevealWave",
		Shape = Enum.PartType.Cylinder,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.15,
		Size = Vector3.new(0.3, 3, 3),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = Workspace,
	})
	local reach = 30 * scale + 20
	TweenService:Create(wave, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, reach, reach),
		Transparency = 1,
	}):Play()
	local holder = UIKit.create("Attachment", { WorldPosition = center, Parent = Workspace.Terrain })
	for _, spec in { { color, 70, 0.9 }, { WHITE, 40, 0.6 }, { C.gold, 30, 0.7 } } do
		local sparks = UIKit.create("ParticleEmitter", {
			Texture = DummyShape.fxTexture("star"),
			Color = ColorSequence.new(WHITE, spec[1]),
			LightEmission = 1,
			LightInfluence = 0,
			Size = NumberSequence.new(spec[3] * scale + 0.4, 0),
			Lifetime = NumberRange.new(0.8, 1.6),
			Speed = NumberRange.new(25 * scale, 55 * scale),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -20, 0),
			Drag = 2.5,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-200, 200),
			Enabled = false,
			Parent = holder,
		})
		sparks:Emit(spec[2])
	end
	UIKit.playSound("Crash", 0.7)
	task.delay(2, function()
		ball:Destroy()
		wave:Destroy()
		holder:Destroy()
	end)
end

-- Cette méthode permet de donner l'origine du décor du secret (sol, là où le mannequin se dressera) au-dessus du point
-- d'atterrissage `ground` lorsque la séquence du secret commence.
function RevealFx.stageOrigin(ground: Vector3): Vector3
	return ground + Vector3.new(0, STAGE_HEIGHT, 0)
end

-- Cette méthode permet de construire le décor du secret autour de `origin` (sol sombre, tapis rouge vers -Z, colonnes
-- dorées éclairées, portique) lorsque l'écran noir le cache.
function RevealFx.buildStage(origin: Vector3)
	RevealFx.clearStage()
	local folder = UIKit.create("Folder", { Name = "RevealStage" })
	local mid = origin + Vector3.new(0, 0, -CARPET_LENGTH / 2 + 6)
	part({
		Name = "Floor",
		Color = Color3.fromRGB(28, 14, 34),
		Size = Vector3.new(120, 1, CARPET_LENGTH + 40),
		Position = mid - Vector3.new(0, 0.5, 0),
		Parent = folder,
	})
	part({
		Name = "Carpet",
		Color = CARPET,
		Material = Enum.Material.Fabric,
		Size = Vector3.new(10, 0.2, CARPET_LENGTH),
		Position = mid + Vector3.new(0, 0.1, 0),
		Parent = folder,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Strip",
			Color = C.gold,
			Material = Enum.Material.Neon,
			Size = Vector3.new(0.6, 0.15, CARPET_LENGTH),
			Position = mid + Vector3.new(side * 6.5, 0.12, 0),
			Parent = folder,
		})
		for z = -6, -CARPET_LENGTH + 6, -COLUMN_GAP do
			local foot = origin + Vector3.new(side * COLUMN_X, 0, z)
			part({
				Name = "Base",
				Color = GOLD,
				Size = Vector3.new(6, 2, 6),
				Position = foot + Vector3.new(0, 1, 0),
				Parent = folder,
			})
			part({
				Name = "Column",
				Color = GOLD,
				Size = Vector3.new(4, 20, 4),
				Position = foot + Vector3.new(0, 12, 0),
				Parent = folder,
			})
			part({
				Name = "Cap",
				Color = GOLD,
				Size = Vector3.new(6, 2, 6),
				Position = foot + Vector3.new(0, 23, 0),
				Parent = folder,
			})
			local lamp = part({
				Name = "Lamp",
				Color = C.yellow,
				Material = Enum.Material.Neon,
				Size = Vector3.new(1, 3, 1.4),
				Position = foot + Vector3.new(-side * 2.3, 13, 0),
				Parent = folder,
			})
			UIKit.create("PointLight", { Color = C.gold, Range = 14, Brightness = 0.8, Shadows = false, Parent = lamp })
		end
		-- Piliers du portail
		part({
			Name = "GatePillar",
			Color = GOLD,
			Size = Vector3.new(4, 30, 4),
			Position = origin + Vector3.new(side * 10, 15, 4),
			Parent = folder,
		})
	end
	part({
		Name = "Lintel",
		Color = GOLD,
		Size = Vector3.new(26, 4, 5),
		Position = origin + Vector3.new(0, 31, 4),
		Parent = folder,
	})
	folder.Parent = Workspace
	stage = folder
end

-- Cette méthode permet de retirer le décor du secret lorsque le tirage se termine ou est passé.
function RevealFx.clearStage()
	if stage then
		stage:Destroy()
		stage = nil
	end
	for _, instance in loose do
		instance:Destroy()
	end
	loose = {}
end

-- Cette méthode permet d'ouvrir le portail du secret (anneau, cœur rouge, braises) de diamètre `size` en `center`
-- lorsque la caméra arrive au bout du tapis ; renvoie la fonction qui le fait éclater.
function RevealFx.portal(center: Vector3, size: number): () -> ()
	local parent = stage or Workspace
	local facing = CFrame.new(center) * CFrame.Angles(0, math.pi / 2, 0)
	local rim = part({
		Name = "PortalRim",
		Shape = Enum.PartType.Cylinder,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = PORTAL_RIM,
		Size = Vector3.new(0.3, 0.2, 0.2),
		CFrame = facing,
		Parent = parent,
	})
	local core = part({
		Name = "PortalCore",
		Shape = Enum.PartType.Cylinder,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = PORTAL_CORE,
		Size = Vector3.new(0.4, 0.2, 0.2),
		CFrame = facing * CFrame.new(0, 0, 0),
		Parent = parent,
	})
	local open = TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(rim, open, { Size = Vector3.new(0.3, size, size) }):Play()
	TweenService:Create(core, open, { Size = Vector3.new(0.4, size * 0.86, size * 0.86) }):Play()
	local holder = UIKit.create("Attachment", {
		WorldPosition = center - Vector3.new(0, size * 0.4, 0.5),
		Parent = Workspace.Terrain,
	})
	table.insert(loose, holder)
	UIKit.create("ParticleEmitter", {
		Texture = DummyShape.fxTexture("star"),
		Color = ColorSequence.new(C.orange, C.gold),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new(0.5, 0),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 40,
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 4, 0),
		Parent = holder,
	})
	UIKit.playSound("Whoosh", 0.55)
	return function()
		core.Color = WHITE
		local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(core, fade, { Size = Vector3.new(0.4, size * 1.6, size * 1.6), Transparency = 1 }):Play()
		TweenService:Create(rim, fade, { Size = Vector3.new(0.3, size * 1.3, size * 1.3), Transparency = 1 }):Play()
		task.delay(0.7, function()
			rim:Destroy()
			core:Destroy()
			holder:Destroy()
		end)
	end
end

-- Cette méthode permet de couvrir l'écran de noir et d'y écrire `text` lettre à lettre pendant `duration` s lorsque
-- la séquence du secret commence ; `onDark` prépare le décor sous le noir.
function RevealFx.blackout(text: string, duration: number, onDark: () -> ())
	local mine = generation
	local s = textScale()
	local screen = UIKit.create("Frame", {
		Name = "Blackout",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = cover,
	})
	local label = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 60 * s),
		TextSize = 40 * s,
		TextColor3 = C.gold,
		Text = "",
		ZIndex = 2,
		Parent = screen,
	})
	TweenService:Create(screen, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	task.spawn(function()
		task.wait(0.35)
		if not alive(mine) then
			return
		end
		onDark()
		local start = os.clock()
		local shown = ""
		local typing = duration - 1
		while os.clock() - start < typing do
			if not alive(mine) then
				return
			end
			local now = RevealPlan.typed(text, os.clock() - start)
			if now ~= shown then
				shown = now
				label.Text = now
				UIKit.playSound("Click", 0.8)
			end
			task.wait()
		end
		label.Text = text
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		TweenService:Create(screen, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		screen:Destroy()
	end)
end

-- Cette méthode permet d'afficher « SECRET!! » géant au centre (dégradé de la couleur de la rareté, rebond, étincelles)
-- et la cote complète dessous (« 1 IN 2,000,000 ») pendant `duration` s lorsque le secret vient de sortir du portail.
function RevealFx.banner(title: string, odds: number, color: Color3, duration: number)
	local s = textScale()
	local holder = UIKit.create("Frame", {
		Name = "SecretBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(900 * s, 200 * s),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = layer,
	})
	local big = UIKit.text({
		Size = UDim2.new(1, 0, 0, 120 * s),
		Text = title,
		TextSize = 112 * s,
		StrokeThickness = 6,
		ZIndex = 5,
		Parent = holder,
	})
	UIKit.gradientText(big, color:Lerp(WHITE, 0.35), Color3.fromRGB(255, 110, 220))
	local line = UIKit.text({
		Position = UDim2.fromOffset(0, 124 * s),
		Size = UDim2.new(1, 0, 0, 56 * s),
		Text = string.format('1 IN <font color="#%s">%s</font>', color:ToHex(), Format.thousands(odds)),
		TextSize = 50 * s,
		StrokeThickness = 4,
		ZIndex = 5,
		Parent = holder,
	})
	UIKit.pop(big, 2.2)
	UIKit.pop(line, 1.5)
	UIKit.sparkles(big, 10, Vector2.new(700 * s, 120 * s), 6, 0.1)
	UIKit.playSound("LevelUp", 0.8)
	task.delay(duration - 0.4, function()
		for _, label in { big, line } do
			if label.Parent then
				TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				end
			end
		end
	end)
	task.delay(duration, function()
		holder:Destroy()
	end)
end

-- Cette méthode permet d'arrêter les effets d'interface en cours (écran noir, bandeau, confettis, pièces) lorsque le
-- tirage est passé au clic alors que le mannequin est déjà sorti du portail.
function RevealFx.clearOverlays()
	generation += 1
	for _, screen in { layer, cover } do
		for _, child in screen:GetChildren() do
			child:Destroy()
		end
	end
end

-- Cette méthode permet d'arrêter les effets en cours (interface, décor, ciel) lorsque le tirage est passé au clic ou
-- se termine ; `keepSky` garde le ciel assombri (révélation qui suit un passage).
function RevealFx.clear(keepSky: boolean?)
	RevealFx.clearOverlays()
	RevealFx.clearStage()
	if not keepSky then
		RevealFx.restoreSky()
	end
end

-- Cette méthode permet de créer les couches d'interface des effets lorsque le client démarre.
function RevealFx.init()
	layer = makeLayer("RevealFx", 4)
	cover = makeLayer("RevealCover", 30)
end

return RevealFx
