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

return SkyClock
