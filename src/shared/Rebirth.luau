-- Renaissance (#108) : avec le dernier équipement d'entraînement (Infinite) et $50B × 4^k (k = renaissances déjà
-- faites), le joueur remet sa progression à zéro (argent, Throw Power, entraînement, équipement, mannequins à lancer)
-- contre une CHANCE × 2 définitive par renaissance (× 2^k au total, comptée dans la CHANCE du lancer comme le
-- multiplicateur du mannequin lancé). Gardés : collection (base, présentoirs achetés, stock, Index), tutoriel, records.
-- Logique pure, partagée par le serveur (validation), le client (fenêtre REBIRTH) et le joueur simulé.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Training = require(Shared:WaitForChild("Training"))

local Rebirth = {}

Rebirth.BASE_PRICE = 50e9 -- prix de la première renaissance
Rebirth.PRICE_GROWTH = 4 -- prix × 4 à chaque renaissance
Rebirth.LUCK_STEP = 2 -- CHANCE × 2 par renaissance, pour toujours
Rebirth.REQUIRED_GEAR = #Training.GEARS -- dernier équipement d'entraînement (Infinite)
Rebirth.MAX = 60 -- borne de lecture d'une sauvegarde (2^60 : bien au-delà de toute partie)
Rebirth.COLOR_HEX = "D28CFF" -- violet des renaissances (étoiles violettes de la référence 05) : base, bandeau, fenêtre

-- Attributs du joueur remis à leur valeur de départ (ceux d'un nouveau joueur) par une renaissance
Rebirth.RESET = {
	Money = 0,
	ThrowPower = GameConfig.START_POWER,
	GearTier = 1,
	TrainLevel = 1,
	TrainExp = 0,
	ThrowTier = 1,
	ThrowEquipped = 1,
}

-- Lignes de la fenêtre REBIRTH (« Resets » / « Keeps »)
Rebirth.RESETS = { "Money", "Throw Power", "Training gear", "Thrown dummies" }
Rebirth.KEEPS = { "Your dummies", "Base & displays", "Index", "Best distance" }

export type State = { gearTier: number, money: number, rebirths: number }

-- Cette méthode permet de lire le nombre de renaissances d'une sauvegarde ou d'un attribut lorsque le serveur charge
-- le joueur ou que l'interface l'affiche : entier de 0 à MAX, 0 si absent ou illisible (ancienne sauvegarde).
function Rebirth.read(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, Rebirth.MAX)
end

-- Cette méthode permet de donner le prix de la renaissance suivante lorsque le joueur en a déjà fait `rebirths`.
function Rebirth.price(rebirths: number): number
	return Rebirth.BASE_PRICE * Rebirth.PRICE_GROWTH ^ Rebirth.read(rebirths)
end

-- Cette méthode permet de donner le multiplicateur de CHANCE d'un joueur qui a fait `rebirths` renaissances lorsque
-- son lancer part ou que l'interface l'affiche (1 sans renaissance).
function Rebirth.luck(rebirths: number): number
	return Rebirth.LUCK_STEP ^ Rebirth.read(rebirths)
end

-- Cette méthode permet de savoir si le joueur peut renaître lorsque le serveur valide la demande ou que la fenêtre
-- s'affiche ; renvoie la condition manquante (« Max » au plafond, puis « Gear », puis « Money »), nil si tout est
-- rempli.
function Rebirth.missing(state: State): string?
	if Rebirth.read(state.rebirths) >= Rebirth.MAX then
		return "Max"
	end
	if state.gearTier < Rebirth.REQUIRED_GEAR then
		return "Gear"
	end
	if state.money < Rebirth.price(state.rebirths) then
		return "Money"
	end
	return nil
end

-- Cette méthode permet de donner les attributs du joueur après une renaissance (remis à zéro, compteur + 1) lorsque
-- le serveur l'accepte ; nil si la condition n'est pas remplie. Tout ce qui n'y figure pas est gardé.
function Rebirth.apply(state: State): { [string]: any }?
	if Rebirth.missing(state) then
		return nil
	end
	local result = table.clone(Rebirth.RESET)
	result.Rebirths = Rebirth.read(state.rebirths) + 1
	return result
end

-- Cette méthode permet d'écrire le multiplicateur de CHANCE de `rebirths` renaissances (« x8 », « x1.02K ») lorsque
-- la fenêtre, le badge de la bannière CHANCE ou une annonce l'affichent.
function Rebirth.luckText(rebirths: number): string
	return "x" .. Format.short(Rebirth.luck(rebirths))
end

-- Cette méthode permet d'écrire l'annonce d'une renaissance (« Ana rebirthed! Rebirth 3: x8 luck ») lorsque le
-- bandeau ou le chat des joueurs du serveur l'affiche.
function Rebirth.announceText(player: string, rebirths: number): string
	return string.format("%s rebirthed! Rebirth %d: %s luck", player, rebirths, Rebirth.luckText(rebirths))
end

-- Cette méthode permet de lire une annonce de renaissance reçue du serveur (nil si elle est mal formée) lorsque le
-- client la reçoit.
function Rebirth.parseAnnouncement(data: any): { userId: number?, player: string, rebirths: number }?
	if type(data) ~= "table" or data.kind ~= "Rebirth" or type(data.player) ~= "string" then
		return nil
	end
	local rebirths = Rebirth.read(data.rebirths)
	if rebirths < 1 then
		return nil
	end
	return {
		userId = if type(data.userId) == "number" then data.userId else nil,
		player = data.player,
		rebirths = rebirths,
	}
end

return Rebirth
