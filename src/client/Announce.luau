-- Annonce serveur d'un tirage Legendary ou plus (#67) : bandeau en haut au centre, vu par tous les joueurs du serveur
-- (« Ana pulled a LEGENDARY Gold Dummy! 1 IN 4K », couleur de la rareté), et ligne dans le chat. Les annonces arrivées
-- pendant le tirage du joueur local attendent la fin de son tirage (le gagnant ne voit pas son résultat gâché, et le
-- haut de l'écran reste à la cote du suspense) ; elles passent ensuite une par une.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local RevealPlan = require(Shared:WaitForChild("RevealPlan"))

local UIKit = require(script.Parent.UIKit)

local SHOW_TIME = 4.5 -- s d'affichage d'un bandeau, entrée et sortie comprises
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

-- Cette méthode permet d'écrire l'annonce dans le chat (message système à la couleur de la rareté) lorsque son bandeau
-- s'affiche ; sans effet si le chat n'est pas disponible.
local function toChat(data: RevealPlan.Announcement, text: string)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
		if general then
			local hex = Rarity.get(data.rarity).color:ToHex()
			general:DisplaySystemMessage(string.format('<font color="#%s">%s</font>', hex, text))
		end
	end)
end

-- Cette méthode permet d'afficher le bandeau d'une annonce (glisse depuis le haut, reste, repart) lorsque son tour
-- vient ; cède jusqu'à sa sortie.
local function show(data: RevealPlan.Announcement)
	local tier = Rarity.get(data.rarity)
	local text = RevealPlan.announceText(data.player, data.name, data.rarity, Format.short(data.odds))
	toChat(data, text)
	onShown(SHOW_TIME)
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
		Text = string.format(
			'★ %s pulled a <font color="#%s">%s %s</font>! 1 IN %s ★',
			data.player,
			tier.color:ToHex(),
			string.upper(tier.name),
			data.name,
			Format.short(data.odds)
		),
		TextSize = 26,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 31,
		Parent = strip,
	})
	UIKit.playSound("LevelUp", 1.25)
	TweenService:Create(strip, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 10),
	}):Play()
	UIKit.sparkles(strip, 5, Vector2.new(680, 40), 32, 0.2)
	task.wait(SHOW_TIME - 0.35)
	local leave = TweenService:Create(strip, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, -70),
	})
	leave:Play()
	leave.Completed:Wait()
	strip:Destroy()
end

-- Cette méthode permet de passer les annonces en attente une par une, chacune après la fin du tirage local, lorsque
-- une annonce arrive et que rien ne tourne.
local function drain()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			while isBusy() do
				task.wait(WAIT_STEP)
			end
			show(table.remove(queue, 1) :: RevealPlan.Announcement)
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

-- Cette méthode permet de brancher les annonces sur le remote du serveur lorsque le client démarre ; `busy` dit si le
-- tirage local occupe l'écran, `shown` est appelé (durée en s) quand un bandeau occupe le haut de l'écran.
function Announce.init(remote: RemoteEvent, screen: ScreenGui, busy: () -> boolean, shown: (number) -> ())
	gui = screen
	isBusy = busy
	onShown = shown
	remote.OnClientEvent:Connect(Announce.receive)
end

return Announce
