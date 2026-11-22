-- Kit d'interface calé sur les jeux de référence (01 Throw Food For Animals, 02 Break and Steal an Egg, 09 Throw a
-- Seed) : police ronde grasse blanche à contour noir fin, boutons carrés à icône dessinée et libellé dessous, fenêtres
-- sombres à bandeau dégradé et croix rouge, cartes d'objets grises avec rendu 3D, popups jaunes, sons d'interface.
-- Animations (#34) : rebond des boutons au survol et au clic, reflet diagonal sur les boutons importants, pastille
-- rouge, fenêtres qui s'ouvrent en pop sur fond flou, popups à rayons et étincelles, « +N » qui volent vers un
-- compteur. Aucune boucle par image : des tweens qui se terminent, et un seul minuteur partagé pour les reflets.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Assets"))
local DummyShape = require(Shared:WaitForChild("DummyShape"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local UIMotion = require(Shared:WaitForChild("UIMotion"))

local UIKit = {}

UIKit.FONT = Enum.Font.FredokaOne

UIKit.COLORS = {
	white = Color3.new(1, 1, 1),
	ink = Color3.fromRGB(20, 20, 26),
	yellow = Color3.fromRGB(255, 210, 60),
	gold = Color3.fromRGB(255, 210, 60),
	orange = Color3.fromRGB(255, 140, 30),
	cyan = Color3.fromRGB(90, 205, 255),
	green = Color3.fromRGB(80, 215, 70),
	red = Color3.fromRGB(235, 55, 60),
	blue = Color3.fromRGB(45, 140, 255),
	panel = Color3.fromRGB(43, 47, 58),
	slate = Color3.fromRGB(36, 48, 72),
	equipped = Color3.fromRGB(70, 74, 86),
	locked = Color3.fromRGB(110, 114, 126),
	bone = Color3.fromRGB(255, 120, 90),
	smash = Color3.fromRGB(255, 170, 60),
}

-- Repli des icônes tant qu'elles ne sont pas publiées (Shared.Assets.ICONS à 0)
local EMOJI = {
	shop = "🎁",
	index = "📘",
	dummies = "🤖",
	power = "💪",
	cash = "💵",
	arrow = "🔻",
	music = "🎵",
	rebirth = "🌟",
}

local SHINE_PERIOD = 3.5 -- s entre deux passages du reflet sur les boutons importants
local SHINE_STAGGER = 0.3 -- s de décalage entre deux boutons (le reflet descend la colonne)
local SHINE_TIME = 0.6 -- s pour traverser un bouton
local BLUR_SIZE = 10 -- flou de fond léger derrière une fenêtre ouverte
local FLY_HOVER = 0.3 -- s pendant lesquelles un « +N » reste sur place avant de voler
local FLY_TIME = 0.45 -- s de vol jusqu'au compteur
UIKit.FLY_DURATION = FLY_HOVER + FLY_TIME

export type Card = {
	frame: Frame,
	title: TextLabel,
	rarity: TextLabel,
	viewport: ViewportFrame,
	stat: TextLabel,
	action: TextButton,
}

export type Window = { frame: Frame, body: Frame, title: TextLabel }

export type PopupOptions = {
	title: string, -- gros titre en dégradé (« LEVEL UP! », « NEW GEAR! »)
	subtitle: string?, -- ligne blanche dessous
	subtitleColor: Color3?,
	tag: string?, -- petit texte rouge au-dessus du titre (« NEW! », comme « NOUVEAU ! » de la référence 09)
	colors: { Color3 }?, -- dégradé du titre, haut puis bas (jaune → orange par défaut)
	position: UDim2?, -- centre du popup (haut de l'écran par défaut)
	duration: number?, -- s d'affichage, fondu compris
	rays: boolean?, -- rayons tournants derrière le titre (oui par défaut)
	sparkles: boolean?, -- étincelles autour du titre (oui par défaut)
}

export type FlyOptions = {
	from: Vector2, -- point de départ, en pixels d'écran
	target: GuiObject, -- texte du compteur visé
	iconTarget: GuiObject?, -- icône du compteur (cible des icônes qui accompagnent le « +N »)
	text: string,
	color: Color3,
	icon: string, -- nom d'icône (UIKit.icon)
	icons: number, -- nombre d'icônes qui accompagnent le « +N »
	scale: number?, -- échelle du HUD (les effets vivent dans une couche sans UIScale)
	onIcon: (() -> ())?, -- appelé à l'arrivée de chaque icône
	onArrive: (() -> ())?, -- appelé à l'arrivée du « +N »
}

local sequences: { [UIScale]: number } = setmetatable({}, { __mode = "k" }) :: any
local shines: { [GuiObject]: UIGradient } = {}
local shineRunning = false
local openWindows: { [GuiObject]: boolean } = {} -- fenêtre ouverte → floute le fond
local blur: BlurEffect? = nil
local fxLayer: ScreenGui? = nil

-- Cette méthode permet de créer une instance avec ses propriétés (Parent en dernier) lorsque l'on construit une
-- interface.
function UIKit.create(className: string, props: { [string]: any }?): any
	local instance = Instance.new(className)
	if props then
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
		instance.Parent = props.Parent
	end
	return instance
end

-- Cette méthode permet d'arrondir les coins d'un cadre lorsque l'on construit un panneau ou un bouton.
function UIKit.corner(parent: Instance, radius: number?)
	UIKit.create("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

-- Cette méthode permet d'entourer un cadre d'un trait noir lorsque l'on construit un panneau ou un bouton.
function UIKit.outline(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or UIKit.COLORS.ink,
		Thickness = thickness or 3,
		Parent = parent,
	})
end

-- Cette méthode permet de poser un dégradé vertical clair → sombre sur un cadre (relief des boutons et cartes)
-- lorsque l'on construit un élément ; `top` et `bottom` sont des teintes multipliées par la couleur du fond.
function UIKit.shade(parent: Instance, top: Color3?, bottom: Color3?, rotation: number?): UIGradient
	return UIKit.create("UIGradient", {
		Color = ColorSequence.new(top or Color3.new(1, 1, 1), bottom or Color3.fromRGB(185, 185, 185)),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

-- Cette méthode permet de créer un texte au style du jeu (police ronde, blanc, contour noir fin) lorsque l'on affiche
-- un chiffre ou un titre ; `props` complète ou remplace le style par défaut.
function UIKit.text(props: { [string]: any }): TextLabel
	local label = UIKit.create("TextLabel", {
		BackgroundTransparency = 1,
		Font = UIKit.FONT,
		TextColor3 = UIKit.COLORS.white,
		TextSize = 28,
		RichText = true,
	})
	UIKit.create("UIStroke", { Color = UIKit.COLORS.ink, Thickness = props.StrokeThickness or 2, Parent = label })
	props.StrokeThickness = nil
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	label.Parent = props.Parent
	return label
end

-- Cette méthode permet de colorer un texte en dégradé vertical (haut → bas, comme les titres des références) lorsque
-- l'on construit un titre de popup ou de résultat ; le contour reste uni.
function UIKit.gradientText(label: TextLabel, top: Color3, bottom: Color3): UIGradient
	label.TextColor3 = Color3.new(1, 1, 1)
	local gradient = label:FindFirstChildOfClass("UIGradient") or UIKit.create("UIGradient", { Parent = label })
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	return gradient
end

-- Cette méthode permet d'afficher une icône dessinée (image publiée, sinon emoji de repli) lorsque l'on construit un
-- bouton ou un compteur ; `props` place l'icône.
function UIKit.icon(name: string, props: { [string]: any }): GuiObject
	local uri = Assets.uri(Assets.ICONS[name])
	local icon: GuiObject
	if uri then
		icon = UIKit.create("ImageLabel", {
			BackgroundTransparency = 1,
			Image = uri,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		icon = UIKit.create("TextLabel", {
			BackgroundTransparency = 1,
			Font = UIKit.FONT,
			Text = EMOJI[name] or "?",
			TextScaled = true,
		})
	end
	for key, value in props do
		if key ~= "Parent" then
			(icon :: any)[key] = value
		end
	end
	icon.Parent = props.Parent
	return icon
end

-- Cette méthode permet de jouer un son d'interface (non positionné) lorsque l'interface réagit.
function UIKit.playSound(name: string, pitch: number?)
	local definition = Sounds[name]
	if not definition then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = definition.id
	sound.Volume = definition.volume
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Cette méthode permet de savoir si le joueur a demandé le mouvement réduit (réglage Roblox) lorsque l'interface
-- choisit de jouer un effet en boucle ; faux si le réglage n'existe pas. Studio : DebugReducedMotion (attribut de
-- Workspace, true) le simule, le réglage étant en lecture seule pour les scripts.
function UIKit.reducedMotion(): boolean
	if RunService:IsStudio() and Workspace:GetAttribute("DebugReducedMotion") == true then
		return true
	end
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

-- Cette méthode permet de savoir si un élément est réellement affiché (lui, ses parents et son ScreenGui) lorsqu'un
-- effet en boucle décide de jouer ou de se taire.
function UIKit.isShown(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled and node:IsDescendantOf(game)
		end
		node = node.Parent
	end
	return false
end

-- Cette méthode permet de donner (ou créer) le UIScale d'un élément lorsque l'on anime sa taille.
function UIKit.scaleOf(target: GuiObject): UIScale
	return target:FindFirstChildOfClass("UIScale") or UIKit.create("UIScale", { Parent = target })
end

-- Cette méthode permet d'interrompre l'animation d'échelle en cours d'un élément et de réserver la suivante lorsque
-- l'on lance un nouveau tween d'échelle ; renvoie le jeton de la nouvelle animation.
local function claim(scale: UIScale): number
	local token = (sequences[scale] or 0) + 1
	sequences[scale] = token
	return token
end

-- Cette méthode permet de mener l'échelle d'un élément vers `value` en `time` s lorsque le joueur survole ou
-- enfonce un bouton ; interrompt l'animation d'échelle en cours.
function UIKit.scaleTo(target: GuiObject, value: number, time: number, style: Enum.EasingStyle?)
	local scale = UIKit.scaleOf(target)
	claim(scale)
	TweenService:Create(scale, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = value,
	}):Play()
end

-- Cette méthode permet de jouer une suite d'étapes d'échelle (Shared.UIMotion) sur un élément lorsqu'il s'ouvre,
-- apparaît ou réagit ; `onDone` est appelé à la fin, sauf si une autre animation d'échelle l'a interrompue.
function UIKit.playKeys(target: GuiObject, keys: { UIMotion.Key }, onDone: (() -> ())?)
	local scale = UIKit.scaleOf(target)
	local token = claim(scale)
	scale.Scale = keys[1].scale
	-- Cette méthode permet d'enchaîner l'étape `i` lorsque la précédente s'est terminée sans interruption.
	local function step(i: number)
		if sequences[scale] ~= token then
			return
		end
		if i > #keys then
			if onDone then
				onDone()
			end
			return
		end
		local tween = TweenService:Create(
			scale,
			TweenInfo.new(keys[i].time - keys[i - 1].time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = keys[i].scale }
		)
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				step(i + 1)
			end
		end)
		tween:Play()
	end
	step(2)
end

-- Cette méthode permet de faire rebondir un élément (grossit puis revient) lorsque sa valeur change ou qu'il apparaît.
function UIKit.pop(target: GuiObject, from: number?)
	local scale = UIKit.scaleOf(target)
	claim(scale)
	scale.Scale = from or 1.25
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Cette méthode permet de faire gonfler et clignoter un compteur lorsqu'un gain y arrive ; `flash` est la couleur
-- du clignotement, le texte revient ensuite à sa couleur.
function UIKit.bump(label: TextLabel, flash: Color3?)
	UIKit.playKeys(label, UIMotion.COUNTER_BUMP)
	if flash then
		local color = (label:GetAttribute("BaseColor") :: Color3?) or label.TextColor3
		label:SetAttribute("BaseColor", color)
		label.TextColor3 = flash
		TweenService:Create(label, TweenInfo.new(0.3), { TextColor3 = color }):Play()
	end
end

-- Cette méthode permet de recentrer le point d'ancrage d'un élément sans le déplacer (le UIScale grossit alors depuis
-- son centre) lorsqu'un bouton est construit ; sans effet dans une grille ou une liste, qui le placent elles-mêmes.
function UIKit.centerPivot(gui: GuiObject)
	local parent = gui.Parent
	if parent and parent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return
	end
	local shift = Vector2.new(0.5, 0.5) - gui.AnchorPoint
	local size = gui.Size
	gui.Position += UDim2.new(
		size.X.Scale * shift.X,
		size.X.Offset * shift.X,
		size.Y.Scale * shift.Y,
		size.Y.Offset * shift.Y
	)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
end

-- Cette méthode permet de brancher un bouton (rebond au survol 1,06, enfoncement 0,92 puis retour, son, action)
-- lorsque l'on construit un bouton ; un bouton marqué Disabled reste inerte.
local function bindPress(button: GuiButton, onClick: () -> ())
	UIKit.centerPivot(button)
	local hovered = false
	local pressed = false
	-- Cette méthode permet de savoir si le bouton refuse les clics (possédé, verrouillé) lorsque le joueur le touche.
	local function disabled(): boolean
		return button:GetAttribute("Disabled") == true
	end
	button.MouseEnter:Connect(function()
		-- Au doigt, MouseEnter arrive sans MouseLeave : pas de survol sur écran tactile
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch or disabled() then
			return
		end
		hovered = true
		if not pressed then
			UIKit.scaleTo(button, UIMotion.HOVER_SCALE, 0.12)
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		UIKit.scaleTo(button, 1, 0.12)
	end)
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) or disabled() then
			return
		end
		pressed = true
		UIKit.scaleTo(button, UIMotion.PRESS_SCALE, UIMotion.PRESS_TIME)
		-- Relâché écouté partout : un doigt glissé hors du bouton avant d'être levé le fait aussi revenir
		local connection
		connection = UserInputService.InputEnded:Connect(function(ended)
			-- Au doigt, seul ce doigt-là relâche (un autre doigt levé ne compte pas)
			if ended.UserInputType ~= kind or (kind == Enum.UserInputType.Touch and ended ~= input) then
				return
			end
			connection:Disconnect()
			if pressed then
				pressed = false
				local rest = if hovered and not disabled() then UIMotion.HOVER_SCALE else 1
				UIKit.scaleTo(button, rest, UIMotion.RELEASE_TIME, Enum.EasingStyle.Back)
			end
		end)
	end)
	button.Activated:Connect(function()
		if disabled() then
			return
		end
		UIKit.playSound("Click")
		onClick()
	end)
	-- Bouton masqué (lui ou un parent : croix, STOP, HUD en vol) : MouseLeave n'arrivera pas, il reprendrait à 1,06
	local node: Instance? = button
	while node and node:IsA("GuiObject") do
		(node :: GuiObject):GetPropertyChangedSignal("Visible"):Connect(function()
			if (hovered or pressed) and not UIKit.isShown(button) then
				hovered = false
				pressed = false
				local scale = UIKit.scaleOf(button)
				claim(scale)
				scale.Scale = 1
			end
		end)
		node = node.Parent
	end
end

-- Cette méthode permet de faire traverser le reflet d'un bouton (bande claire en diagonale) lorsque le minuteur des
-- reflets arrive à ce bouton.
local function playShine(gradient: UIGradient)
	if not gradient.Parent then
		return
	end
	gradient.Offset = Vector2.new(-1, 0)
	TweenService:Create(gradient, TweenInfo.new(SHINE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		Offset = Vector2.new(1, 0),
	}):Play()
end

-- Cette méthode permet de faire passer le reflet sur tous les boutons importants affichés, toutes les SHINE_PERIOD s,
-- tant qu'il en reste ; un seul minuteur pour tous, muet pour les boutons cachés et en mouvement réduit.
local function runShines()
	while next(shines) do
		task.wait(SHINE_PERIOD)
		if not UIKit.reducedMotion() then
			local order = 0
			for button, gradient in shines do
				if not button:IsDescendantOf(game) then
					shines[button] = nil
				elseif UIKit.isShown(button) then
					task.delay(order * SHINE_STAGGER, playShine, gradient)
					order += 1
				end
			end
		end
	end
	shineRunning = false
end

-- Cette méthode permet de poser un reflet diagonal qui passe de temps en temps sur un bouton important (Shop,
-- Dummies) lorsque le bouton est construit ; `radius` reprend l'arrondi du bouton.
function UIKit.addShine(button: GuiObject, radius: number?)
	local overlay = UIKit.create("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = button.ZIndex + 3,
		Parent = button,
	})
	UIKit.corner(overlay, radius or 8)
	shines[button] = UIKit.create("UIGradient", {
		Rotation = 30,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = overlay,
	})
	if not shineRunning then
		shineRunning = true
		task.spawn(runShines)
	end
end

-- Cette méthode permet de créer un bouton plein (vert par défaut, relief dégradé, contour noir, texte blanc à
-- contour) lorsque l'on construit une interface ; `onClick` est appelé à l'activation.
function UIKit.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local button = UIKit.create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = UIKit.COLORS.green,
		Font = UIKit.FONT,
		TextColor3 = UIKit.COLORS.white,
		TextSize = 24,
		RichText = true,
	})
	local radius = props.Radius or 8
	local shine = props.Shine
	UIKit.corner(button, radius)
	UIKit.outline(button, 3)
	UIKit.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = UIKit.COLORS.ink,
		Thickness = 2,
		Parent = button,
	})
	UIKit.shade(button, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	props.Radius = nil
	props.Shine = nil
	for key, value in props do
		if key ~= "Parent" then
			(button :: any)[key] = value
		end
	end
	button.Parent = props.Parent
	bindPress(button, onClick)
	if shine then
		UIKit.addShine(button, radius)
	end
	return button
end

-- Cette méthode permet d'afficher, mettre à jour ou masquer la pastille rouge au coin haut droit d'un bouton
-- lorsqu'une action y est possible ; `value` : nombre (« 3 », « 99+ »), texte (« ! ») ou nil pour la masquer.
function UIKit.setBadge(button: GuiObject, value: (number | string)?)
	local text = UIMotion.badgeText(value)
	local badge = button:FindFirstChild("Badge") :: Frame?
	if not text then
		if badge then
			badge.Visible = false
		end
		return
	end
	if not badge then
		badge = UIKit.create("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = UIKit.COLORS.red,
			Visible = false,
			ZIndex = button.ZIndex + 6,
			Parent = button,
		})
		UIKit.corner(badge :: Frame, 15)
		UIKit.outline(badge :: Frame, 2.5)
		UIKit.text({
			Name = "Count",
			Size = UDim2.fromScale(1, 1),
			TextSize = 22,
			ZIndex = button.ZIndex + 7,
			Parent = badge,
		})
	end
	local frame = badge :: Frame
	local label = frame:FindFirstChild("Count") :: TextLabel
	local changed = not frame.Visible or label.Text ~= text
	label.Text = text
	frame.Size = UDim2.fromOffset(math.max(30, 14 + 12 * #text), 30)
	frame.Visible = true
	if changed then
		UIKit.playKeys(frame, UIMotion.POPUP_IN)
	end
end

-- Cette méthode permet de créer un bouton carré à icône dessinée et libellé dessous (Shop, Index, Dummies) lorsque
-- le HUD est construit ; `size` est le côté du carré, `props.Shine` ajoute le reflet des boutons importants.
function UIKit.iconButton(
	icon: string,
	label: string,
	size: number,
	props: { [string]: any },
	onClick: () -> ()
): TextButton
	local button = UIKit.create("TextButton", {
		Name = label,
		AutoButtonColor = false,
		BackgroundColor3 = UIKit.COLORS.slate,
		Size = UDim2.fromOffset(size, size),
		Text = "",
	})
	local radius = math.floor(size * 0.16)
	local shine = props.Shine
	props.Shine = nil
	UIKit.corner(button, radius)
	UIKit.outline(button, 3)
	UIKit.shade(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150))
	-- Liseré clair intérieur (relief des boutons de référence)
	local rim = UIKit.create("Frame", {
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		BackgroundTransparency = 1,
		Parent = button,
	})
	UIKit.corner(rim, math.floor(size * 0.13))
	UIKit.outline(rim, 2, Color3.fromRGB(95, 120, 165))
	UIKit.icon(icon, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 2,
		Parent = button,
	})
	UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, 20, 0, 26),
		Text = label,
		TextSize = 22,
		ZIndex = 5,
		Parent = button,
	})
	for key, value in props do
		if key ~= "Parent" then
			(button :: any)[key] = value
		end
	end
	button.Parent = props.Parent
	bindPress(button, onClick)
	if shine then
		UIKit.addShine(button, radius)
	end
	return button
end

-- Cette méthode permet d'accorder le flou de fond au nombre de fenêtres ouvertes lorsque l'une s'ouvre ou se ferme.
local function updateBlur()
	local wanted = false
	for _, blurs in openWindows do
		wanted = wanted or blurs
	end
	local camera = Workspace.CurrentCamera
	if not blur or blur.Parent ~= camera then
		if not wanted then
			return
		end
		if blur then
			blur:Destroy()
		end
		blur = UIKit.create("BlurEffect", { Name = "WindowBlur", Size = 0, Parent = camera })
	end
	local effect = blur :: BlurEffect
	effect.Enabled = true
	local tween = TweenService:Create(effect, TweenInfo.new(if wanted then 0.25 else 0.12), {
		Size = if wanted then BLUR_SIZE else 0,
	})
	if not wanted then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				effect.Enabled = false
			end
		end)
	end
	tween:Play()
end

-- Cette méthode permet d'ouvrir une fenêtre en pop (0,6 → 1,05 → 1 en 0,25 s) sur fond légèrement flou lorsque le
-- joueur l'ouvre ; `blurBackground` à false garde la scène nette (écran de résultat).
function UIKit.openWindow(frame: GuiObject, blurBackground: boolean?)
	openWindows[frame] = blurBackground ~= false
	frame.Visible = true
	UIKit.playKeys(frame, UIMotion.WINDOW_OPEN)
	updateBlur()
end

-- Cette méthode permet de fermer une fenêtre (rétrécit en 0,12 s puis disparaît) lorsque le joueur la ferme ;
-- `instant` la masque sans animation (vol, jauge).
function UIKit.closeWindow(frame: GuiObject, instant: boolean?)
	local wasOpen = openWindows[frame] ~= nil
	openWindows[frame] = nil
	if wasOpen then
		updateBlur()
	end
	local scale = UIKit.scaleOf(frame)
	if instant or not frame.Visible then
		claim(scale)
		scale.Scale = 1
		frame.Visible = false
		return
	end
	-- Part de l'échelle actuelle : une fenêtre fermée en pleine ouverture ne saute pas à 1
	local close = table.clone(UIMotion.WINDOW_CLOSE)
	close[1] = { time = 0, scale = scale.Scale }
	UIKit.playKeys(frame, close, function()
		frame.Visible = false
		scale.Scale = 1
	end)
end

-- Cette méthode permet de savoir si une fenêtre est ouverte (pas en train de se fermer) lorsque le joueur clique
-- sur son bouton.
function UIKit.isWindowOpen(frame: GuiObject): boolean
	return openWindows[frame] ~= nil
end

-- Cette méthode permet de créer une fenêtre (cadre sombre, bandeau dégradé à contour épais avec icône et titre, croix
-- rouge) lorsque le HUD construit une boutique ou un index ; `onClose` est appelé par la croix.
function UIKit.window(
	parent: Instance,
	props: {
		name: string,
		title: string,
		icon: string?,
		colors: { Color3 },
		size: Vector2,
	},
	onClose: () -> ()
): Window
	local frame = UIKit.create("Frame", {
		Name = props.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(props.size.X, props.size.Y),
		BackgroundColor3 = UIKit.COLORS.panel,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	})
	UIKit.corner(frame, 14)
	UIKit.outline(frame, 4)
	local header = UIKit.create("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 10,
		Parent = frame,
	})
	UIKit.corner(header, 14)
	UIKit.create("UIGradient", { Color = ColorSequence.new(props.colors[1], props.colors[2]), Parent = header })
	-- Bas du bandeau droit (seuls les coins du haut sont arrondis)
	local flat = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = header,
	})
	UIKit.create("UIGradient", { Color = ColorSequence.new(props.colors[1], props.colors[2]), Parent = flat })
	-- Trait épais sous le bandeau : avec le contour de la fenêtre, le bandeau est cerné (référence 02)
	UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = UIKit.COLORS.ink,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = header,
	})
	local titleX = 18
	if props.icon then
		UIKit.icon(props.icon, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -14, 0.5, -6),
			Size = UDim2.fromOffset(72, 72),
			ZIndex = 12,
			Parent = header,
		})
		titleX = 64
	end
	local title = UIKit.text({
		Position = UDim2.fromOffset(titleX, 0),
		Size = UDim2.new(1, -titleX - 70, 1, 0),
		Text = props.title,
		TextSize = 34,
		StrokeThickness = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = header,
	})
	UIKit.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = UIKit.COLORS.red,
		Text = "X",
		TextSize = 28,
		ZIndex = 12,
		Parent = header,
	}, onClose)
	local body = UIKit.create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 70),
		Size = UDim2.new(1, -24, 1, -82),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = frame,
	})
	return { frame = frame, body = body, title = title }
end

-- Cette méthode permet de cadrer un modèle de trois quarts dans un ViewportFrame (rendu 3D d'une carte) lorsque la
-- carte change d'objet ; l'ancien modèle est retiré.
function UIKit.showModel(viewport: ViewportFrame, model: Model?)
	viewport:ClearAllChildren()
	if not model then
		return
	end
	local cf, size = model:GetBoundingBox()
	local camera = UIKit.create("Camera", { FieldOfView = 30, Parent = viewport })
	local distance = size.Magnitude * 0.5 / math.tan(math.rad(15))
	local center = cf.Position
	local eye = center + Vector3.new(0.45, 0.3, -1).Unit * distance
	camera.CFrame = CFrame.lookAt(eye, center)
	viewport.CurrentCamera = camera
	DummyShape.viewportSafe(model) -- verre et champ de force ne s'y rendent pas (#89)
	model.Parent = viewport
end

UIKit.CARD_WIDTH = 196 -- largeur d'une carte de boutique (px)
UIKit.CARD_HEIGHT = 300 -- hauteur d'une carte de boutique (px)
UIKit.CARD_GAP = 10 -- écart entre deux cartes d'une grille qui défile
local GRID_PAD = 4 -- marge haute et basse d'une grille de cartes (px)
local GRID_PEEK = 20 -- px de la rangée précédente laissés visibles au-dessus de la carte visée
local scrollTokens: { [ScrollingFrame]: {} } = {} -- placement automatique en cours, par grille

-- Cette méthode permet de créer une grille de cartes à défilement vertical (`columns` cartes par rangée, centrées,
-- comme les boutiques de 02 et 09) dans le corps d'une fenêtre lorsque une boutique est construite (#45).
function UIKit.cardGrid(body: GuiObject, columns: number): ScrollingFrame
	local grid = UIKit.create("ScrollingFrame", {
		Name = "Cards",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.COLORS.white,
		ZIndex = 11,
		Parent = body,
	})
	UIKit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(UIKit.CARD_WIDTH, UIKit.CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(UIKit.CARD_GAP, UIKit.CARD_GAP),
		FillDirectionMaxCells = columns,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	UIKit.create("UIPadding", {
		PaddingTop = UDim.new(0, GRID_PAD),
		PaddingBottom = UDim.new(0, GRID_PAD),
		Parent = grid,
	})
	grid:SetAttribute("Columns", columns)
	return grid
end

-- Cette méthode permet de faire défiler une grille de cartes jusqu'à la rangée de la carte `order` (un bout de la
-- rangée précédente reste visible au-dessus) lorsque une boutique s'ouvre (12 équipements, 20 mannequins depuis #94).
function UIKit.scrollToCard(grid: ScrollingFrame, order: number)
	local columns = (grid:GetAttribute("Columns") :: number?) or 1
	local rank = math.floor((order - 1) / columns)
	local y = if rank == 0 then 0 else GRID_PAD + rank * (UIKit.CARD_HEIGHT + UIKit.CARD_GAP) - GRID_PEEK
	-- CanvasPosition est en pixels d'écran : la position est ramenée à l'échelle du HUD (UIScale du ScreenGui, mobile)
	local gui = grid:FindFirstAncestorOfClass("ScreenGui")
	local hudScale = gui and gui:FindFirstChildOfClass("UIScale")
	local token = {} -- placement en cours : un nouvel appel ou un défilement du joueur l'annulent
	scrollTokens[grid] = token
	-- Cette méthode permet de placer la grille sur la carte visée lorsque la fenêtre s'affiche ou que la grille grandit,
	-- tant que le joueur n'a pas défilé lui-même.
	local function apply()
		if scrollTokens[grid] == token then
			grid.CanvasPosition = Vector2.new(0, y * (if hudScale then hudScale.Scale else 1))
		end
	end
	-- Cette méthode permet d'annuler les recalages lorsque le joueur fait défiler la grille (molette ou doigt sur elle) ;
	-- seule une vraie entrée compte, le moteur bornant lui-même CanvasPosition pendant le pop d'ouverture.
	local function onInput(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseWheel and kind ~= Enum.UserInputType.Touch then
			return
		end
		local at, from, size = input.Position, grid.AbsolutePosition, grid.AbsoluteSize
		local inset = GuiService:GetGuiInset() -- positions d'entrée sous la barre du haut, grille à IgnoreGuiInset
		local x, py = at.X, at.Y + inset.Y
		if x >= from.X and x <= from.X + size.X and py >= from.Y and py <= from.Y + size.Y then
			if scrollTokens[grid] == token then
				scrollTokens[grid] = nil
			end
		end
	end
	local inputs = {
		UserInputService.InputChanged:Connect(onInput),
		UserInputService.InputBegan:Connect(onInput),
	}
	task.delay(1, function()
		for _, connection in inputs do
			connection:Disconnect()
		end
	end)
	-- Différé d'une image (fenêtre tout juste visible), puis repris quand la grille jamais affichée a calculé sa
	-- hauteur (sinon la position serait bornée à 0) et à la fin du pop d'ouverture (grille réduite pendant
	-- UIMotion.WINDOW_OPEN : la position y était bornée plus bas)
	task.defer(apply)
	task.delay(UIMotion.WINDOW_OPEN[#UIMotion.WINDOW_OPEN].time + 0.05, apply)
	if grid.AbsoluteCanvasSize.Y <= grid.AbsoluteWindowSize.Y then
		local connection: RBXScriptConnection
		connection = grid:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
			apply()
			if grid.AbsoluteCanvasSize.Y > grid.AbsoluteWindowSize.Y then
				connection:Disconnect()
			end
		end)
		task.delay(1, function()
			connection:Disconnect()
		end)
	end
end

-- Cette méthode permet de créer une carte d'objet (nom, rareté, rendu 3D, statistique, bouton d'action) dans une
-- boutique lorsque la fenêtre est construite ; `onAction` est appelé par le bouton.
function UIKit.card(parent: Instance, order: number, onAction: () -> ()): Card
	local frame = UIKit.create("Frame", {
		Name = "Card" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(UIKit.CARD_WIDTH, UIKit.CARD_HEIGHT),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 11,
		Parent = parent,
	})
	UIKit.corner(frame, 10)
	UIKit.outline(frame, 3)
	UIKit.shade(frame, Color3.fromRGB(236, 238, 244), Color3.fromRGB(176, 182, 194))
	local title = UIKit.text({
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.new(1, -8, 0, 28),
		TextSize = 24,
		-- Noms longs (« Nebula Rubber Dummy », #94) : réduits pour tenir dans la carte au lieu de déborder sur la voisine
		TextScaled = true,
		TextWrapped = false,
		ZIndex = 12,
		Parent = frame,
	})
	UIKit.create("UITextSizeConstraint", { MaxTextSize = 24, Parent = title })
	local rarity = UIKit.text({
		Position = UDim2.fromOffset(4, 34),
		Size = UDim2.new(1, -8, 0, 18),
		TextSize = 19,
		ZIndex = 12,
		Parent = frame,
	})
	local viewport = UIKit.create("ViewportFrame", {
		Position = UDim2.fromOffset(8, 56),
		Size = UDim2.new(1, -16, 0, 150),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1.5, 1),
		ZIndex = 12,
		Parent = frame,
	})
	local statPill = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 212),
		Size = UDim2.new(1, -16, 0, 30),
		BackgroundColor3 = Color3.fromRGB(88, 94, 106),
		ZIndex = 12,
		Parent = frame,
	})
	UIKit.corner(statPill, 6)
	UIKit.outline(statPill, 2)
	local stat = UIKit.text({ Size = UDim2.fromScale(1, 1), TextSize = 22, ZIndex = 13, Parent = statPill })
	local action = UIKit.button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 250),
		Size = UDim2.new(1, -16, 0, 42),
		ZIndex = 12,
		Parent = frame,
	}, onAction)
	return { frame = frame, title = title, rarity = rarity, viewport = viewport, stat = stat, action = action }
end

-- Cette méthode permet de créer une gerbe de rayons qui tourne derrière un titre puis s'efface (référence 09, tirage
-- « 1 en N ») lorsqu'un popup ou un résultat apparaît ; se détruit après `duration` s, immobile en mouvement réduit.
function UIKit.rays(
	parent: Instance,
	props: {
		position: UDim2,
		size: number,
		duration: number,
		color: Color3?,
		count: number?,
		zIndex: number?,
	}
): Frame
	local count = props.count or 10
	local holder = UIKit.create("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundTransparency = 1,
		ZIndex = props.zIndex or 1,
		Parent = parent,
	})
	local still = UIKit.reducedMotion()
	local fadeOut = math.min(0.35, props.duration / 3)
	for i = 1, count do
		local angle = i * 180 / count
		local bar = UIKit.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, math.max(6, props.size * 0.07), 1, 0),
			Rotation = angle,
			BackgroundColor3 = props.color or UIKit.COLORS.yellow,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = props.zIndex or 1,
			Parent = holder,
		})
		UIKit.create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, 0.45),
				NumberSequenceKeypoint.new(0.5, 0.85),
				NumberSequenceKeypoint.new(0.75, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = bar,
		})
		TweenService:Create(bar, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
		if not still then
			TweenService:Create(bar, TweenInfo.new(props.duration, Enum.EasingStyle.Linear), {
				Rotation = angle + 70,
			}):Play()
		end
		task.delay(props.duration - fadeOut, function()
			if bar.Parent then
				TweenService:Create(bar, TweenInfo.new(fadeOut), { BackgroundTransparency = 1 }):Play()
			end
		end)
	end
	task.delay(props.duration, function()
		holder:Destroy()
	end)
	return holder
end

-- Cette méthode permet de créer une étincelle à quatre branches (deux traits blancs effilés en croix) lorsque l'on
-- décore un popup.
local function sparkle(parent: Instance, position: UDim2, size: number, zIndex: number): Frame
	local holder = UIKit.create("Frame", {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		Parent = parent,
	})
	for i = 0, 1 do
		local bar = UIKit.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = if i == 0 then UDim2.fromScale(1, 0.16) else UDim2.fromScale(0.16, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = holder,
		})
		UIKit.create("UIGradient", {
			Rotation = i * 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = bar,
		})
	end
	return holder
end

-- Cette méthode permet de faire scintiller `count` étincelles au hasard dans une zone `area` (px, centrée dans
-- `parent`) lorsqu'un popup ou un record apparaît ; chacune grandit, tourne et disparaît (tweens qui se terminent).
function UIKit.sparkles(parent: Instance, count: number, area: Vector2, zIndex: number?, delay: number?)
	for i = 1, count do
		local position =
			UDim2.new(0.5, math.random(-area.X // 2, area.X // 2), 0.5, math.random(-area.Y // 2, area.Y // 2))
		local star = sparkle(parent, position, math.random(22, 40), zIndex or 1)
		local scale = UIKit.create("UIScale", { Scale = 0, Parent = star })
		task.delay((delay or 0) + (i - 1) * 0.12, function()
			if not star.Parent then
				return
			end
			local grow = TweenService:Create(
				scale,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
				{ Scale = 1 }
			)
			grow.Completed:Once(function()
				star:Destroy()
			end)
			grow:Play()
			TweenService:Create(star, TweenInfo.new(0.44), { Rotation = 45 }):Play()
		end)
	end
end

-- Cette méthode permet d'afficher un popup (titre en dégradé, tag rouge, sous-titre) qui rebondit devant rayons et
-- étincelles puis s'efface lorsque le joueur gagne un palier ou un objet ; renvoie sa durée (réutilisé par #31).
function UIKit.popup(parent: Instance, options: PopupOptions): number
	local duration = options.duration or 1.8
	local colors = options.colors or { Color3.fromRGB(255, 240, 110), UIKit.COLORS.orange }
	local holder = UIKit.create("Frame", {
		Name = "Popup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = options.position or UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(640, 110),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = parent,
	})
	if options.rays ~= false then
		UIKit.rays(holder, {
			position = UDim2.new(0.5, 0, 0, 44),
			size = 300,
			duration = duration,
			color = colors[1],
			zIndex = 19,
		})
	end
	if options.tag then
		UIKit.text({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 20),
			Size = UDim2.new(1, 0, 0, 26),
			Text = options.tag,
			TextSize = 26,
			TextColor3 = UIKit.COLORS.red,
			StrokeThickness = 2.5,
			Rotation = -4,
			ZIndex = 21,
			Parent = holder,
		})
	end
	local title = UIKit.text({
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 52),
		Text = options.title,
		TextSize = 52,
		StrokeThickness = 4,
		ZIndex = 21,
		Parent = holder,
	})
	UIKit.gradientText(title, colors[1], colors[2])
	if options.subtitle then
		UIKit.text({
			Position = UDim2.fromOffset(0, 74),
			Size = UDim2.new(1, 0, 0, 30),
			Text = options.subtitle,
			TextSize = 28,
			TextColor3 = options.subtitleColor or UIKit.COLORS.white,
			ZIndex = 21,
			Parent = holder,
		})
	end
	if options.sparkles ~= false then
		UIKit.sparkles(holder, 6, Vector2.new(460, 90), 22, 0.1)
	end
	UIKit.playKeys(holder, UIMotion.POPUP_IN)
	task.delay(duration - 0.4, function()
		for _, child in holder:GetChildren() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				local stroke = child:FindFirstChildOfClass("UIStroke")
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				end
			end
		end
		task.wait(0.45)
		holder:Destroy()
	end)
	return duration
end

-- Cette méthode permet de donner la couche d'effets (ScreenGui sans UIScale, au-dessus du HUD, en pixels d'écran)
-- lorsque des « +N » doivent voler d'un point de l'écran à un compteur.
local function effectsLayer(): ScreenGui
	if fxLayer and fxLayer.Parent then
		return fxLayer
	end
	fxLayer = UIKit.create("ScreenGui", {
		Name = "HudEffects",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	return fxLayer :: ScreenGui
end

-- Cette méthode permet de donner le centre d'un élément en pixels d'écran lorsqu'un effet vole vers lui.
local function centerOf(gui: GuiObject): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize / 2
end

-- Cette méthode permet de faire jaillir puis voler un « +N » et quelques icônes vers un compteur lorsque le joueur
-- gagne de l'argent ou de la puissance ; renvoie l'étiquette (texte modifiable en vol pour un gain regroupé).
function UIKit.flyGain(options: FlyOptions): TextLabel
	local layer = effectsLayer()
	local s = options.scale or 1
	local label = UIKit.text({
		Name = "FlyGain",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(options.from.X, options.from.Y),
		Size = UDim2.fromOffset(260 * s, 44 * s),
		Text = options.text,
		TextSize = math.floor(38 * s),
		TextColor3 = options.color,
		StrokeThickness = 3,
		ZIndex = 3,
		Parent = layer,
	})
	UIKit.playKeys(label, UIMotion.POPUP_IN)
	local iconGoal = options.iconTarget or options.target
	for i = 1, options.icons do
		local angle = (i / options.icons) * 2 * math.pi + math.random() * 0.6
		local radius = (50 + math.random() * 40) * s
		local icon = UIKit.icon(options.icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(options.from.X, options.from.Y),
			Size = UDim2.fromOffset(38 * s, 38 * s),
			ZIndex = 2,
			Parent = layer,
		})
		TweenService:Create(icon, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(
				options.from.X + math.cos(angle) * radius,
				options.from.Y + math.sin(angle) * radius
			),
		}):Play()
		task.delay(FLY_HOVER + (i - 1) * 0.05, function()
			local goal = centerOf(iconGoal)
			local fly =
				TweenService:Create(icon, TweenInfo.new(FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(goal.X, goal.Y),
					Size = UDim2.fromOffset(24 * s, 24 * s),
				})
			fly.Completed:Once(function()
				icon:Destroy()
				if options.onIcon then
					options.onIcon()
				end
			end)
			fly:Play()
		end)
	end
	task.delay(FLY_HOVER, function()
		local goal = centerOf(options.target)
		local fly =
			TweenService:Create(label, TweenInfo.new(FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(goal.X, goal.Y),
				TextTransparency = 0.4,
			})
		UIKit.scaleTo(label, 0.5, FLY_TIME, Enum.EasingStyle.Quad)
		fly.Completed:Once(function()
			label:Destroy()
			if options.onArrive then
				options.onArrive()
			end
		end)
		fly:Play()
	end)
	return label
end

return UIKit
