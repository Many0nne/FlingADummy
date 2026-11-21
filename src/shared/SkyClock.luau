-- Heure du ciel des zones de nuit (#97, logique pure, testée) : vers quelle heure fondre Lighting.ClockTime quand la nuit
-- tombe sur la Galaxy ou que le jour revient (Client.ZoneSky), sans repasser par le plein jour ni lever le soleil à
-- l'envers. Roblox garde l'heure entre 0 et 24 (24 est ramené à 0).
local SkyClock = {}

-- Cette méthode permet de donner l'heure cible d'un fondu lorsque la nuit tombe (`night`) ou que le jour `day` revient,
-- l'heure étant `current` : la nuit en avançant par le coucher (24) depuis l'après-midi, en reculant (0) depuis le matin.
function SkyClock.target(current: number, night: boolean, day: number): number
	if not night then
		return day
	end
	return if current % 24 >= day then 24 else 0
end

SkyClock.DAWN = 5 -- entre minuit et l'aube, le ciel est déjà de nuit

-- Cette méthode permet de savoir si l'heure `clock` est après minuit (ciel de nuit) lorsqu'un tirage rare veut
-- assombrir le ciel vers le soir (Client.RevealFx) : fondre de là vers 19-24 h repasserait par tout le jour.
function SkyClock.isAfterMidnight(clock: number): boolean
	return clock % 24 < SkyClock.DAWN
end

return SkyClock
