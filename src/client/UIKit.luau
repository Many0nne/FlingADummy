-- Kit d'interface commun : police ronde à contour noir épais, boutons carrés colorés, panneaux arrondis, popups qui
-- rebondissent et sons d'interface (codes visuels du genre « simulateur »).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))

local UIKit = {}

UIKit.TITLE_FONT = Enum.Font.LuckiestGuy
UIKit.BODY_FONT = Enum.Font.FredokaOne

UIKit.COLORS = {
	white = Color3.new(1, 1, 1),
	ink = Color3.fromRGB(20, 20, 26),
	yellow = Color3.fromRGB(255, 205, 40),
	gold = Color3.fromRGB(255, 215, 60),
	green = Color3.fromRGB(70, 210, 90),
	red = Color3.fromRGB(240, 70, 60),
	blue = Color3.fromRGB(60, 160, 255),
	panel = Color3.fromRGB(35, 38, 50),
	locked = Color3.fromRGB(110, 114, 126),
	bone = Color3.fromRGB(255, 120, 90),
	smash = Color3.fromRGB(255, 170, 60),
	glass = Color3.fromRGB(150, 225, 255),
}

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

-- Cette méthode permet d'entourer un cadre d'un trait noir épais lorsque l'on construit un panneau ou un bouton.
function UIKit.outline(parent: Instance, thickness: number?, color: Color3?)
	UIKit.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or UIKit.COLORS.ink,
		Thickness = thickness or 3,
		Parent = parent,
	})
end

-- Cette méthode permet de créer un texte au style du jeu (police ronde, contour noir) lorsque l'on affiche un chiffre
-- ou un titre ; `props` complète ou remplace le style par défaut.
function UIKit.text(props: { [string]: any }): TextLabel
	local label = UIKit.create("TextLabel", {
		BackgroundTransparency = 1,
		Font = UIKit.TITLE_FONT,
		TextColor3 = UIKit.COLORS.white,
		TextSize = 28,
		RichText = true,
	})
	UIKit.create("UIStroke", { Color = UIKit.COLORS.ink, Thickness = props.StrokeThickness or 3, Parent = label })
	props.StrokeThickness = nil
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	label.Parent = props.Parent
	return label
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

-- Cette méthode permet de créer un bouton coloré à contour noir (enfoncement au clic, son) lorsque l'on construit une
-- interface ; `onClick` est appelé à l'activation.
function UIKit.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local button = UIKit.create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = UIKit.COLORS.green,
		Font = UIKit.TITLE_FONT,
		TextColor3 = UIKit.COLORS.white,
		TextSize = 26,
		RichText = true,
	})
	UIKit.corner(button, props.Radius or 12)
	UIKit.outline(button, 3)
	UIKit.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = UIKit.COLORS.ink,
		Thickness = 2.5,
		Parent = button,
	})
	UIKit.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
		Rotation = 90,
		Parent = button,
	})
	props.Radius = nil
	for key, value in props do
		if key ~= "Parent" then
			(button :: any)[key] = value
		end
	end
	button.Parent = props.Parent
	button.Activated:Connect(function()
		UIKit.playSound("Click")
		UIKit.pop(button, 0.88)
		onClick()
	end)
	return button
end

-- Cette méthode permet d'afficher un gros message en haut de l'écran (« LEVEL UP! ») qui rebondit puis s'efface
-- lorsque le joueur franchit un palier.
function UIKit.banner(parent: Instance, title: string, subtitle: string?, color: Color3?, offsetY: number?)
	local holder = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, offsetY or 150),
		Size = UDim2.fromOffset(600, 90),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local main = UIKit.text({
		Size = UDim2.new(1, 0, 0, 56),
		Text = title,
		TextSize = 54,
		TextColor3 = color or UIKit.COLORS.gold,
		StrokeThickness = 4,
		Parent = holder,
	})
	if subtitle then
		UIKit.text({
			Position = UDim2.fromOffset(0, 56),
			Size = UDim2.new(1, 0, 0, 30),
			Text = subtitle,
			TextSize = 28,
			Parent = holder,
		})
	end
	UIKit.pop(holder, 0.4)
	task.delay(1.6, function()
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
	return main
end

return UIKit
