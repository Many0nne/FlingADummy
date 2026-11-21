-- Musique de fond du joueur local (logique de choix : Shared.Music). Pistes jouées dans un SoundGroup « Music »
-- distinct des effets (volume modéré) ; le moment suit les attributs du joueur (`LaneState` répliqué par le serveur,
-- `PrizePhase` posé localement par Client.Prize). Fondus : chaque piste rejoint son volume cible à vitesse constante,
-- une piste remplacée s'efface puis est détruite. Muet : attribut `MusicOff` sauvegardé côté serveur (remote
-- SetMusic), appliqué tout de suite en local.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MusicRules = require(Shared:WaitForChild("Music"))
local Remotes = require(Shared:WaitForChild("Remotes"))

type Playing = { sound: Sound, track: MusicRules.Track, level: number, speed: number } -- speed : vitesse du fondu

local Music = {}

-- Appelée quand le muet change (le HUD met son bouton à jour)
Music.onChanged = nil :: ((muted: boolean) -> ())?

local player: Player
local remotes: Remotes.Remotes
local group: SoundGroup
local started = false -- musique lancée (données du joueur chargées : le muet sauvegardé est connu)
local muted = false
local mood: MusicRules.Mood = "Hub"
local bed: MusicRules.Bed? = nil
local hubIndex: number? = nil -- piste du hub en cours ou dernière jouée (rotation)
local current: Playing? = nil
local fading: { Playing } = {}
local fanfare: Playing? = nil
local fanfareEndsAt = 0

-- Cette méthode permet de créer une piste (volume nul, dans le groupe musique) lorsque l'on enchaîne une piste de
-- fond ou la fanfare.
local function newSound(track: MusicRules.Track, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = track.name
	sound.SoundId = track.id
	sound.Volume = 0
	sound.Looped = looped
	sound.SoundGroup = group
	sound.Parent = group
	sound:Play()
	return sound
end

-- Cette méthode permet de démarrer la piste `i` d'une liste de fond en fondu de `fade` s, la précédente s'effaçant
-- au même rythme, lorsque le moment change de liste ou que la piste du hub se termine.
local function play(list: MusicRules.Bed, i: number, fade: number)
	local speed = MusicRules.FADE / fade
	if current then
		local previous = current :: Playing
		previous.speed = speed
		table.insert(fading, previous)
	end
	local track = MusicRules.TRACKS[list][i]
	bed = list
	if list == "Hub" then
		hubIndex = i
	end
	-- La piste du vol tourne en boucle le temps du lancer ; celles du hub s'enchaînent
	local sound = newSound(track, list == "Flight")
	local playing = { sound = sound, track = track, level = 0, speed = speed }
	current = playing
	sound.Ended:Connect(function()
		if current == playing and bed == "Hub" then
			play("Hub", MusicRules.nextIndex("Hub", hubIndex), MusicRules.FADE)
		end
	end)
end

-- Cette méthode permet de jouer la fanfare de la révélation (courte, la piste de fond baissée dessous) lorsque le
-- tirage révèle le mannequin gagné.
local function playFanfare()
	if fanfare then
		table.insert(fading, fanfare)
	end
	local track = MusicRules.TRACKS.Fanfare
	local sound = newSound(track, false)
	fanfare = { sound = sound, track = track, level = 0, speed = 4 }
	fanfareEndsAt = os.clock() + MusicRules.FANFARE_MAX
end

-- Cette méthode permet de recalculer le moment musical lorsque `LaneState` ou `PrizePhase` change : bascule de liste
-- de fond en fondu, fanfare à l'entrée dans la révélation.
local function refresh()
	if not started then
		return
	end
	local previous = mood
	mood = MusicRules.mood(
		player:GetAttribute("LaneState") :: string?,
		player:GetAttribute("PrizePhase") :: string?,
		previous
	)
	local wanted = MusicRules.bed(mood)
	if wanted ~= bed then
		-- Le vol repart du début ; le hub reprend à la piste suivante de la rotation (au hasard à l'arrivée)
		local i = if wanted == "Flight"
			then 1
			elseif hubIndex then MusicRules.nextIndex("Hub", hubIndex)
			else MusicRules.firstIndex("Hub", math.random())
		play(wanted, i, MusicRules.SWITCH_FADE)
	end
	if mood == "Reveal" and previous ~= "Reveal" then
		playFanfare()
	end
end

-- Cette méthode permet d'avancer les fondus d'une image (volumes vers leur cible, pistes effacées détruites, fin de
-- la fanfare, enchaînement du hub avant la fin de piste) lorsque le client rend une image.
local function step(dt: number)
	local fanfareOn = false
	if fanfare then
		local f = fanfare :: Playing
		local over = os.clock() >= fanfareEndsAt or (f.sound.TimeLength > 0 and not f.sound.IsPlaying)
		if over then
			table.insert(fading, f)
			fanfare = nil
		else
			fanfareOn = true
			f.level = MusicRules.approach(f.level, if muted then 0 else 1, f.speed, dt)
			f.sound.Volume = f.level * f.track.volume
		end
	end
	if current then
		local c = current :: Playing
		c.level = MusicRules.approach(c.level, MusicRules.bedLevel(mood, fanfareOn, muted), c.speed, dt)
		c.sound.Volume = c.level * c.track.volume
		if bed == "Hub" and MusicRules.shouldAdvance(c.sound.TimePosition, c.sound.TimeLength) then
			play("Hub", MusicRules.nextIndex("Hub", hubIndex), MusicRules.FADE)
		end
	end
	for i = #fading, 1, -1 do
		local f = fading[i]
		f.level = MusicRules.approach(f.level, 0, f.speed, dt)
		f.sound.Volume = f.level * f.track.volume
		if f.level <= 0 then
			f.sound:Destroy()
			table.remove(fading, i)
		end
	end
end

-- Cette méthode permet d'appliquer un état de muet (fondu vers le silence ou retour) et de prévenir le HUD lorsque
-- le joueur clique le bouton ou que l'attribut sauvegardé arrive.
local function setMuted(value: boolean)
	if value == muted then
		return
	end
	muted = value
	if Music.onChanged then
		Music.onChanged(muted)
	end
end

-- Cette méthode permet de couper ou remettre la musique (effet immédiat, choix envoyé au serveur qui le sauvegarde)
-- lorsque le joueur clique le bouton musique du HUD.
function Music.toggle()
	setMuted(not muted)
	remotes.SetMusic:FireServer(muted)
end

-- Cette méthode permet de savoir si la musique est coupée lorsque le HUD construit son bouton.
function Music.isMuted(): boolean
	return muted
end

-- Cette méthode permet de lancer la musique (muet sauvegardé appliqué) lorsque les
-- données du joueur sont chargées.
local function start()
	if started or player:GetAttribute("DataReady") ~= true then
		return
	end
	started = true
	setMuted(player:GetAttribute("MusicOff") == true)
	refresh()
end

-- Cette méthode permet de créer le groupe musique et de brancher la musique sur les attributs du joueur lorsque le
-- client démarre.
function Music.init(localPlayer: Player, allRemotes: Remotes.Remotes)
	player = localPlayer or Players.LocalPlayer
	remotes = allRemotes
	group = Instance.new("SoundGroup")
	group.Name = "Music"
	group.Volume = MusicRules.GROUP_VOLUME
	group.Parent = SoundService
	for _, attribute in { "LaneState", "PrizePhase" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	player:GetAttributeChangedSignal("MusicOff"):Connect(function()
		if started then
			setMuted(player:GetAttribute("MusicOff") == true)
		end
	end)
	player:GetAttributeChangedSignal("DataReady"):Connect(start)
	RunService.RenderStepped:Connect(step)
	start()
end

return Music
