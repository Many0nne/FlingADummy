-- Renaissance (#108), calée sur Net a Fish! (12) et Ant Evolution (05) : fenêtre REBIRTH à bandeau violet (gain
-- « LUCK x2 FOREVER », listes « Resets » / « Keeps », condition et prix, bouton vert grisé tant qu'une condition
-- manque, deux clics pour confirmer), popup « REBIRTH READY! » une fois par renaissance quand la condition est
-- remplie, puis à la renaissance un écran plein violet (« REBIRTH! », rayons, gerbe d'étoiles violettes). Le client
-- n'envoie qu'une intention (remote Rebirth), le serveur valide (Shared.Rebirth).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Rebirth = require(Shared:WaitForChild("Rebirth"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Training = require(Shared:WaitForChild("Training"))
local UIMotion = require(Shared:WaitForChild("UIMotion"))

local UIKit = require(script.Parent.UIKit)

local C = UIKit.COLORS
local VIOLET = Color3.fromRGB(150, 70, 255)
local PINK = Color3.fromRGB(255, 80, 200)
local STAR = Color3.fromHex(Rebirth.COLOR_HEX) -- violet des étoiles (aussi celui du compteur de la base, du bandeau)
local CONFIRM_TIME = 3 -- s pendant lesquelles le second clic confirme
local CELEBRATE_TIME = 3.4 -- s d'écran plein à la renaissance, fondu compris

export type Hooks = {
	popup: (options: UIKit.PopupOptions) -> (), -- popup de palier (« REBIRTH READY! »)
	money: () -> number, -- argent affiché (gains en vol pas encore arrivés exclus)
	screenFree: () -> boolean, -- au hub, écran libre (ni vol, ni tirage, ni jauge, ni fenêtre, ni bandeau)
}

local RebirthWindow = {}

local player: Player
local remotes: Remotes.Remotes
local hooks: Hooks
local gui: ScreenGui
local frame: Frame
local gainLabel: TextLabel
local nowLabel: TextLabel
local gearLabel: TextLabel
local priceLabel: TextLabel
local countLabel: TextLabel
local button: TextButton
local confirmUntil = 0
local knownRebirths = math.huge -- renaissances au chargement : les suivantes se fêtent
local readyShown: number? = nil -- renaissance (compteur) pour laquelle « REBIRTH READY! » a été montré

-- Cette méthode permet de lire l'état du joueur pour la condition de renaissance (argent affiché) lorsque la fenêtre
-- se rafraîchit ou que le bouton est cliqué.
local function state(): Rebirth.State
	return {
		gearTier = (player:GetAttribute("GearTier") :: number?) or 1,
		money = hooks.money(),
		rebirths = Rebirth.read(player:GetAttribute("Rebirths")),
	}
end

-- Cette méthode permet de savoir si la renaissance est possible avec l'argent affiché, comme le bouton de la fenêtre
-- (pastille, popup) lorsque l'argent ou l'équipement changent.
function RebirthWindow.isReady(): boolean
	if not player or not hooks or player:GetAttribute("DataReady") ~= true then
		return false
	end
	return Rebirth.missing(state()) == nil
end

-- Cette méthode permet de rafraîchir la fenêtre (gain, compteur, condition cochée ou non, prix vert ou rouge, bouton
-- vert ou grisé avec la condition manquante) lorsque l'argent, l'équipement ou les renaissances changent.
function RebirthWindow.refresh()
	if not frame or not frame.Visible then
		return
	end
	local current = state()
	local k = current.rebirths
	local price = Rebirth.price(k)
	local missing = Rebirth.missing(current)
	gainLabel.Text = "LUCK " .. Rebirth.luckText(1) .. " FOREVER"
	nowLabel.Text = string.format(
		'Luck <font color="#%s">%s</font>  →  <font color="#%s">%s</font>',
		STAR:ToHex(),
		Rebirth.luckText(k),
		C.green:ToHex(),
		Rebirth.luckText(k + 1)
	)
	countLabel.Text = "Rebirths: " .. k
	local hasGear = current.gearTier >= Rebirth.REQUIRED_GEAR
	gearLabel.Text = (if hasGear then "✔ " else "✖ ") .. Training.gear(Rebirth.REQUIRED_GEAR).name
	gearLabel.TextColor3 = if hasGear then C.green else C.red
	priceLabel.Text = (if current.money >= price then "✔ " else "✖ ") .. Format.money(price)
	priceLabel.TextColor3 = if current.money >= price then C.green else C.red
	if missing == "Max" then
		button.Text = "MAX"
	elseif missing == "Gear" then
		button.Text = "NEED "
			.. string.upper((string.gsub(Training.gear(Rebirth.REQUIRED_GEAR).name, " Dummy$", "")))
			.. " GEAR"
	elseif missing == "Money" then
		button.Text = "NEED " .. Format.money(price)
	elseif os.clock() < confirmUntil then
		button.Text = "SURE?"
	else
		button.Text = "REBIRTH"
	end
	button.BackgroundColor3 = if missing then C.locked elseif os.clock() < confirmUntil then C.orange else C.green
	button:SetAttribute("Disabled", missing ~= nil)
end

-- Cette méthode permet de répondre au bouton REBIRTH lorsque le joueur clique : le premier clic demande confirmation
-- (« SURE? » pendant CONFIRM_TIME s), le second envoie la demande au serveur.
local function onClick()
	if Rebirth.missing(state()) then
		return
	end
	if os.clock() < confirmUntil then
		confirmUntil = 0
		remotes.Rebirth:FireServer()
	else
		confirmUntil = os.clock() + CONFIRM_TIME
		UIKit.playSound("Click", 0.9)
		task.delay(CONFIRM_TIME + 0.05, RebirthWindow.refresh)
	end
	RebirthWindow.refresh()
end

-- Cette méthode permet de construire une colonne « Resets » ou « Keeps » (titre coloré, une ligne par élément, coche
-- ou croix) lorsque la fenêtre est construite.
local function column(parent: Instance, x: number, title: string, color: Color3, mark: string, items: { string })
	local box = UIKit.create("Frame", {
		Position = UDim2.new(x, if x > 0 then 6 else 0, 0, 96),
		Size = UDim2.new(0.5, -6, 0, 168),
		BackgroundColor3 = color:Lerp(C.panel, 0.75),
		ZIndex = 12,
		Parent = parent,
	})
	UIKit.corner(box, 10)
	UIKit.outline(box, 3)
	UIKit.text({
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 32),
		Text = title,
		TextSize = 28,
		TextColor3 = color,
		ZIndex = 13,
		Parent = box,
	})
	for index, item in items do
		UIKit.text({
			Position = UDim2.fromOffset(16, 6 + index * 30),
			Size = UDim2.new(1, -24, 0, 28),
			Text = mark .. "  " .. item,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 13,
			Parent = box,
		})
	end
end

-- Cette méthode permet de construire le contenu de la fenêtre (gain, colonnes, condition, prix, compteur, bouton)
-- dans `body` lorsque le HUD est construit.
local function buildBody(body: Frame)
	gainLabel = UIKit.text({
		Size = UDim2.new(1, 0, 0, 50),
		TextSize = 46,
		StrokeThickness = 4,
		ZIndex = 12,
		Parent = body,
	})
	UIKit.gradientText(gainLabel, Color3.fromRGB(255, 245, 150), C.orange)
	nowLabel = UIKit.text({
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 24,
		ZIndex = 12,
		Parent = body,
	})
	column(body, 0, "RESETS", C.red, "✖", Rebirth.RESETS)
	column(body, 0.5, "KEEPS", C.green, "✔", Rebirth.KEEPS)
	gearLabel = UIKit.text({
		Position = UDim2.fromOffset(4, 274),
		Size = UDim2.new(0.5, -8, 0, 28),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = body,
	})
	priceLabel = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 274),
		Size = UDim2.new(0.5, -8, 0, 28),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 12,
		Parent = body,
	})
	countLabel = UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, -8),
		Size = UDim2.fromOffset(160, 28),
		TextSize = 22,
		TextColor3 = STAR,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
		Parent = body,
	})
	button = UIKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(280, 58),
		Text = "REBIRTH",
		TextSize = 30,
		Radius = 12,
		Shine = true,
		ZIndex = 12,
		Parent = body,
	}, onClick)
end

-- Cette méthode permet de lancer une étoile violette du centre de `parent` vers une direction au hasard (grandit,
-- tourne, s'efface) lorsque la renaissance est fêtée.
local function shootStar(parent: Instance, delay: number)
	local angle = math.random() * math.pi * 2
	local distance = math.random(180, 420)
	local star = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(60, 60),
		Text = if math.random() < 0.5 then "★" else "✦",
		TextSize = math.random(30, 64),
		TextColor3 = STAR:Lerp(Color3.new(1, 1, 1), math.random() * 0.4),
		TextTransparency = 1,
		ZIndex = 43,
		Parent = parent,
	})
	task.delay(delay, function()
		if not star.Parent then
			return
		end
		star.TextTransparency = 0
		local target = UDim2.new(0.5, math.cos(angle) * distance, 0.45, math.sin(angle) * distance * 0.7)
		local fly = TweenService:Create(
			star,
			TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = target, Rotation = math.random(-180, 180) }
		)
		fly:Play()
		TweenService
			:Create(star, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.7), {
				TextTransparency = 1,
			})
			:Play()
	end)
end

-- Cette méthode permet de fêter une renaissance (écran plein violet, « REBIRTH! », rayons, gerbe d'étoiles, gain et
-- numéro de la renaissance, puis fondu) lorsque le compteur du joueur local augmente.
local function celebrate(rebirths: number)
	local cover = UIKit.create("Frame", {
		Name = "RebirthCelebration",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 10, 80),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = gui,
	})
	UIKit.create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 50, 220), Color3.fromRGB(25, 5, 55)),
		Rotation = 90,
		Parent = cover,
	})
	TweenService:Create(cover, TweenInfo.new(0.25), { BackgroundTransparency = 0.25 }):Play()
	UIKit.rays(cover, {
		position = UDim2.fromScale(0.5, 0.45),
		size = 760,
		duration = CELEBRATE_TIME,
		color = STAR,
		count = 14,
		zIndex = 41,
	})
	local title = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(700, 110),
		Text = "REBIRTH!",
		TextSize = 104,
		StrokeThickness = 6,
		ZIndex = 44,
		Parent = cover,
	})
	UIKit.gradientText(title, Color3.fromRGB(255, 255, 255), STAR)
	local subtitle = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, 62),
		Size = UDim2.fromOffset(700, 46),
		Text = "LUCK " .. Rebirth.luckText(1) .. " FOREVER!",
		TextSize = 44,
		StrokeThickness = 4,
		ZIndex = 44,
		Parent = cover,
	})
	UIKit.gradientText(subtitle, Color3.fromRGB(255, 245, 150), C.orange)
	UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, 114),
		Size = UDim2.fromOffset(700, 34),
		Text = string.format("Rebirth %d  •  total luck %s", rebirths, Rebirth.luckText(rebirths)),
		TextSize = 30,
		TextColor3 = STAR,
		ZIndex = 44,
		Parent = cover,
	})
	UIKit.playKeys(title, UIMotion.POPUP_IN)
	for i = 1, 26 do
		shootStar(cover, 0.05 + (i % 13) * 0.08 + (if i > 13 then 0.9 else 0))
	end
	UIKit.sparkles(cover, 10, Vector2.new(700, 260), 45, 0.2)
	UIKit.playSound("LevelUp", 0.8)
	task.delay(0.9, UIKit.playSound, "LevelUp", 1.1)
	task.delay(CELEBRATE_TIME - 0.45, function()
		for _, child in cover:GetDescendants() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			elseif child:IsA("UIStroke") then
				TweenService:Create(child, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(cover, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.45)
		cover:Destroy()
	end)
end

-- Cette méthode permet d'annoncer « REBIRTH READY! » une fois par renaissance (comme « Renaissance prête ! » de 12)
-- lorsque la condition est remplie après le chargement, écran libre (au hub, hors vol, tirage, jauge et bandeau) ;
-- fenêtre REBIRTH déjà ouverte : le joueur le voit, pas de popup.
function RebirthWindow.checkReady()
	if knownRebirths == math.huge or not RebirthWindow.isReady() then
		return
	end
	local k = Rebirth.read(player:GetAttribute("Rebirths"))
	if readyShown == k then
		return
	end
	if frame.Visible then
		readyShown = k
		return
	end
	if not hooks.screenFree() then
		return -- réessayé au prochain rafraîchissement du HUD (le revenu change l'argent chaque seconde)
	end
	readyShown = k
	hooks.popup({
		title = "REBIRTH READY!",
		subtitle = "Open Rebirth: luck " .. Rebirth.luckText(k + 1) .. " forever",
		subtitleColor = STAR,
		colors = { Color3.fromRGB(240, 200, 255), VIOLET },
		duration = 2.6,
	})
	UIKit.playSound("LevelUp", 1.3)
end

-- Cette méthode permet de construire la fenêtre REBIRTH (fermée) et de la brancher sur les attributs du joueur lorsque
-- le HUD est construit ; renvoie son cadre (ouvert et fermé par le HUD), `onClose` ferme la fenêtre.
function RebirthWindow.init(
	localPlayer: Player,
	createdRemotes: Remotes.Remotes,
	screen: ScreenGui,
	createdHooks: Hooks,
	onClose: () -> ()
): Frame
	player = localPlayer
	remotes = createdRemotes
	hooks = createdHooks
	gui = screen
	local window = UIKit.window(gui, {
		name = "Rebirth",
		title = "Rebirth",
		icon = "rebirth",
		colors = { VIOLET, PINK },
		size = Vector2.new(620, 470),
	}, onClose)
	frame = window.frame
	buildBody(window.body)
	for _, attribute in { "GearTier", "Money", "Rebirths" } do
		player:GetAttributeChangedSignal(attribute):Connect(RebirthWindow.refresh)
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then
			confirmUntil = 0 -- fenêtre rouverte : nouvelle confirmation demandée
		end
		RebirthWindow.refresh()
	end)
	-- Compte remis à zéro (DebugWipe) : « REBIRTH READY! » s'annoncera de nouveau
	player:GetAttributeChangedSignal("Draws"):Connect(function()
		if player:GetAttribute("Draws") == 0 then
			readyShown = nil
		end
	end)
	-- Cette méthode permet de retenir les renaissances au chargement lorsque les données du joueur sont prêtes (la
	-- valeur sauvegardée ne se fête pas) ; une condition déjà remplie au chargement s'annonce.
	local function seed()
		knownRebirths = Rebirth.read(player:GetAttribute("Rebirths"))
		RebirthWindow.checkReady()
	end
	if player:GetAttribute("DataReady") == true then
		seed()
	end
	player:GetAttributeChangedSignal("DataReady"):Connect(seed)
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		local k = Rebirth.read(player:GetAttribute("Rebirths"))
		if player:GetAttribute("DataReady") == true and k > knownRebirths then
			onClose()
			celebrate(k)
		end
		if knownRebirths ~= math.huge then
			if k < knownRebirths then
				readyShown = nil -- compteur redescendu (DebugWipe)
			end
			knownRebirths = k
		end
	end)
	return frame
end

return RebirthWindow
