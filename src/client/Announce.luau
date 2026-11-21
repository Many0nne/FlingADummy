-- Annonce serveur d'un tirage Legendary ou plus (#67) : bandeau en haut au centre, vu par tous les joueurs du serveur
-- (« Ana pulled a LEGENDARY Gold Dummy! 1 IN 4K », couleur de la rareté), et ligne dans le chat. Une annonce attend
-- que le joueur local ne soit ni en vol ni en tirage (le gagnant, en vol puis en tirage quand elle arrive, ne voit pas
-- son résultat gâché, et le haut de l'écran reste à la cote du suspense) ; un bandeau affiché s'efface dès qu'un
-- tirage local commence. Les annonces passent une par une.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local RevealPlan = require(Shared:WaitForChild("RevealPlan"))

local UIKit = require(script.Parent.UIKit)

local SHOW_TIME = 4.5 -- s d'affichage d'un bandeau, entrée et sortie comprises
local SLIDE = 0.35 -- s de l'entrée et de la sortie du bandeau
local WAIT_STEP = 0.25 -- s entre deux vérifications pendant que le tirage local occupe l'écran
local QUEUE_MAX = 5 -- annonces en attente au plus (les plus anciennes sautent)

local Announce = {}

local gui: ScreenGui
local queue: { RevealPlan.Announcement } = {}
local running = false
local isBusy: () -> boolean = function()
	return false
end
local onShown: (number) -> () = function(_duration: number) end
local topTaken: () -> boolean = function()
	return false
end

-- Cette méthode permet d'écrire l'annonce dans le chat (message système à la couleur de la rareté) lorsque son bandeau
-- s'affiche ; sans effet si le chat n'est pas disponible.
local function toChat(text: string)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
		if general then
			general:DisplaySystemMessage(text)
		end
	end)
end

-- Cette méthode permet d'afficher le bandeau d'une annonce (glisse depuis le haut, reste, repart) lorsque son tour
-- vient ; cède jusqu'à sa sortie.
local function show(data: RevealPlan.Announcement)
	local tier = Rarity.get(data.rarity)
	local hex = tier.color:ToHex()
	local who = if data.userId == Players.LocalPlayer.UserId then "You" else data.player
	local text = RevealPlan.announceText(who, data.name, data.rarity, Format.short(data.odds), hex)
	toChat(text)
	onShown(SHOW_TIME + SLIDE)
	local strip = UIKit.create("Frame", {
		Name = "Announce",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -70),
		Size = UDim2.fromOffset(720, 54),
		BackgroundColor3 = Color3.new(1, 1, 1), -- teinté par le dégradé
		BackgroundTransparency = 0.1,
		ZIndex = 30,
		Parent = gui,
	})
	UIKit.corner(strip, 12)
	UIKit.outline(strip, 3, tier.color)
	UIKit.shade(strip, tier.color:Lerp(Color3.new(0, 0, 0), 0.45), Color3.fromRGB(20, 18, 30))
	UIKit.text({
		Size = UDim2.fromScale(1, 1),
		Text = "★ " .. text .. " ★",
		TextSize = 26,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 31,
		Parent = strip,
	})
	UIKit.playSound("LevelUp", 1.25)
	TweenService:Create(strip, TweenInfo.new(SLIDE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 10),
	}):Play()
	UIKit.sparkles(strip, 5, Vector2.new(680, 40), 32, 0.2)
	-- Reste affiché, sauf si un vol ou un tirage du joueur local commence entre-temps
	local stay = os.clock() + SHOW_TIME - SLIDE
	while os.clock() < stay and not isBusy() do
		task.wait(WAIT_STEP)
	end
	local leave = TweenService:Create(strip, TweenInfo.new(SLIDE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, -70),
	})
	leave:Play()
	task.wait(SLIDE)
	strip:Destroy()
end

-- Cette méthode permet de passer les annonces en attente une par une (hors vol et tirage local, haut de l'écran libre)
-- lorsque une annonce arrive et que rien ne tourne ; une annonce en erreur ne bloque pas les suivantes.
local function drain()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			while isBusy() or topTaken() do
				task.wait(WAIT_STEP)
			end
			local ok, err = pcall(show, table.remove(queue, 1) :: RevealPlan.Announcement)
			if not ok then
				warn("[Announce] " .. tostring(err))
			end
		end
		running = false
	end)
end

-- Cette méthode permet de mettre en file une annonce reçue du serveur (ignorée si elle est mal formée) lorsque un
-- joueur du serveur tire un Legendary ou plus.
function Announce.receive(data: any)
	local announcement = RevealPlan.parseAnnouncement(data)
	if not announcement then
		return
	end
	table.insert(queue, announcement)
	while #queue > QUEUE_MAX do
		table.remove(queue, 1)
	end
	drain()
end

-- Cette méthode permet de brancher les annonces sur le remote lorsque le client démarre ; `busy` : vol ou tirage local,
-- `shown(durée)` : un bandeau prend le haut de l'écran, `taken` : un popup l'occupe déjà.
function Announce.init(
	remote: RemoteEvent,
	screen: ScreenGui,
	busy: () -> boolean,
	shown: (number) -> (),
	taken: () -> boolean
)
	gui = screen
	isBusy = busy
	onShown = shown
	topTaken = taken
	remote.OnClientEvent:Connect(Announce.receive)
end

return Announce
