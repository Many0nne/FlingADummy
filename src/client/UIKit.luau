-- Kit d'interface calé sur les jeux de référence (01 Throw Food For Animals, 09 Throw a Seed) : police ronde grasse
-- blanche à contour noir fin, boutons carrés à icône dessinée et libellé dessous, fenêtres sombres à bandeau dégradé
-- et croix rouge, cartes d'objets grises avec rendu 3D, popups jaunes, sons d'interface.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Assets"))
local Sounds = require(Shared:WaitForChild("Sounds"))

local UIKit = {}

UIKit.FONT = Enum.Font.FredokaOne

UIKit.COLORS = {
	white = Color3.new(1, 1, 1),
	ink = Color3.fromRGB(20, 20, 26),
	yellow = Color3.fromRGB(255, 210, 60),
	gold = Color3.fromRGB(255, 210, 60),
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
	glass = Color3.fromRGB(150, 225, 255),
}

-- Repli des icônes tant qu'elles ne sont pas publiées (Shared.Assets.ICONS à 0)
local EMOJI = {
	shop = "🎁",
	index = "📘",
	dummies = "🤖",
	power = "💪",
	cash = "💵",
	arrow = "🔻",
}

export type Card = {
	frame: Frame,
	title: TextLabel,
	rarity: TextLabel,
	viewport: ViewportFrame,
	stat: TextLabel,
	action: TextButton,
}

export type Window = { frame: Frame, body: Frame, title: TextLabel }

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

-- Cette méthode permet de faire rebondir un élément (grossit puis revient) lorsque sa valeur change ou qu'il apparaît.
function UIKit.pop(target: GuiObject, from: number?)
	local scale = target:FindFirstChildOfClass("UIScale") or UIKit.create("UIScale", { Parent = target })
	scale.Scale = from or 1.25
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Cette méthode permet de brancher le clic d'un bouton (son, enfoncement, action) lorsque l'on construit un bouton.
local function onActivated(button: GuiButton, onClick: () -> ())
	button.Activated:Connect(function()
		UIKit.playSound("Click")
		UIKit.pop(button, 0.88)
		onClick()
	end)
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
	UIKit.corner(button, props.Radius or 8)
	UIKit.outline(button, 3)
	UIKit.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = UIKit.COLORS.ink,
		Thickness = 2,
		Parent = button,
	})
	UIKit.shade(button, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	props.Radius = nil
	for key, value in props do
		if key ~= "Parent" then
			(button :: any)[key] = value
		end
	end
	button.Parent = props.Parent
	onActivated(button, onClick)
	return button
end

-- Cette méthode permet de poser la pastille rouge « ! » au coin haut droit d'un bouton lorsqu'une action y est
-- possible ; renvoyée masquée.
function UIKit.badge(parent: GuiObject): Frame
	local badge = UIKit.create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = UIKit.COLORS.red,
		Visible = false,
		ZIndex = 4,
		Parent = parent,
	})
	UIKit.corner(badge, 15)
	UIKit.outline(badge, 2.5)
	UIKit.text({ Size = UDim2.fromScale(1, 1), Text = "!", TextSize = 24, ZIndex = 5, Parent = badge })
	return badge
end

-- Cette méthode permet de créer un bouton carré à icône dessinée et libellé dessous (Shop, Index, Dummies) lorsque
-- le HUD est construit ; `size` est le côté du carré.
function UIKit.iconButton(
	icon: string,
	label: string,
	size: number,
	props: { [string]: any },
	onClick: () -> ()
): TextButton
	local button = UIKit.create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = UIKit.COLORS.slate,
		Size = UDim2.fromOffset(size, size),
		Text = "",
	})
	UIKit.corner(button, math.floor(size * 0.16))
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
		ZIndex = 3,
		Parent = button,
	})
	for key, value in props do
		if key ~= "Parent" then
			(button :: any)[key] = value
		end
	end
	button.Parent = props.Parent
	onActivated(button, onClick)
	return button
end

-- Cette méthode permet de créer une fenêtre (cadre sombre, bandeau dégradé avec icône et titre, croix rouge) lorsque
-- le HUD construit une boutique ou un index ; `onClose` est appelé par la croix.
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
	local distance = size.Magnitude * 0.5 / math.tan(math.rad(15)) * 1.05
	local center = cf.Position
	local eye = center + Vector3.new(0.45, 0.3, -1).Unit * distance
	camera.CFrame = CFrame.lookAt(eye, center)
	viewport.CurrentCamera = camera
	model.Parent = viewport
end

-- Cette méthode permet de créer une carte d'objet (nom, rareté, rendu 3D, statistique, bouton d'action) dans une
-- boutique lorsque la fenêtre est construite ; `onAction` est appelé par le bouton.
function UIKit.card(parent: Instance, order: number, onAction: () -> ()): Card
	local frame = UIKit.create("Frame", {
		Name = "Card" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(176, 262),
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
		TextScaled = false,
		TextWrapped = false,
		ZIndex = 12,
		Parent = frame,
	})
	local rarity = UIKit.text({
		Position = UDim2.fromOffset(4, 32),
		Size = UDim2.new(1, -8, 0, 18),
		TextSize = 16,
		ZIndex = 12,
		Parent = frame,
	})
	local viewport = UIKit.create("ViewportFrame", {
		Position = UDim2.fromOffset(8, 52),
		Size = UDim2.new(1, -16, 0, 116),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1.5, 1),
		ZIndex = 12,
		Parent = frame,
	})
	local statPill = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 174),
		Size = UDim2.new(1, -16, 0, 30),
		BackgroundColor3 = Color3.fromRGB(88, 94, 106),
		ZIndex = 12,
		Parent = frame,
	})
	UIKit.corner(statPill, 6)
	UIKit.outline(statPill, 2)
	local stat = UIKit.text({ Size = UDim2.fromScale(1, 1), TextSize = 20, ZIndex = 13, Parent = statPill })
	local action = UIKit.button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 212),
		Size = UDim2.new(1, -16, 0, 40),
		ZIndex = 12,
		Parent = frame,
	}, onAction)
	return { frame = frame, title = title, rarity = rarity, viewport = viewport, stat = stat, action = action }
end

-- Cette méthode permet d'afficher un popup de palier (titre jaune à contour, sous-titre blanc) en haut au centre qui
-- rebondit puis s'efface lorsque le joueur gagne un niveau ou un équipement ; renvoie sa durée d'affichage.
function UIKit.popup(parent: Instance, title: string, subtitle: string?, subtitleColor: Color3?): number
	local holder = UIKit.create("Frame", {
		Name = "Popup",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(640, 96),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = parent,
	})
	UIKit.text({
		Size = UDim2.new(1, 0, 0, 52),
		Text = title,
		TextSize = 48,
		TextColor3 = UIKit.COLORS.gold,
		StrokeThickness = 3,
		ZIndex = 20,
		Parent = holder,
	})
	if subtitle then
		UIKit.text({
			Position = UDim2.fromOffset(0, 54),
			Size = UDim2.new(1, 0, 0, 30),
			Text = subtitle,
			TextSize = 28,
			TextColor3 = subtitleColor or UIKit.COLORS.white,
			ZIndex = 20,
			Parent = holder,
		})
	end
	UIKit.pop(holder, 0.4)
	local duration = 1.8
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

return UIKit
