-- Mise en forme des nombres affichés (argent, puissance, distances).
local Format = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx" }

-- Cette méthode permet d'écrire un entier avec séparateurs de milliers lorsque l'interface affiche un montant exact.
function Format.thousands(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return (if n < 0 then "-" else "") .. grouped
end

-- Cette méthode permet d'abréger un grand nombre (`950`, `1.2K`, `34.5M`) lorsque l'interface affiche un compteur ;
-- 3 chiffres significatifs au-delà de 1 000, sans zéros inutiles.
function Format.short(n: number): string
	local value = math.floor(math.abs(n))
	local sign = if n < 0 then "-" else ""
	if value < 1000 then
		return sign .. tostring(value)
	end
	local tier = 0
	local scaled = value
	while scaled >= 1000 and tier < #SUFFIXES do
		scaled /= 1000
		tier += 1
	end
	local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local factor = 10 ^ decimals
	-- Tronqué, pas arrondi : 999 999 s'écrit 999K, jamais 1000K
	local text = string.format("%." .. decimals .. "f", math.floor(scaled * factor) / factor)
	if decimals > 0 then
		text = (string.gsub((string.gsub(text, "0+$", "")), "%.$", ""))
	end
	return sign .. text .. SUFFIXES[tier]
end

-- Cette méthode permet d'écrire une somme d'argent abrégée (`$12.3K`) lorsque l'interface l'affiche.
function Format.money(n: number): string
	if n < 0 then
		return "-$" .. Format.short(-n)
	end
	return "$" .. Format.short(n)
end

-- Cette méthode permet d'écrire une distance arrondie au mètre (`1,234 m`) lorsque l'interface l'affiche.
function Format.meters(n: number): string
	return Format.thousands(math.max(0, n)) .. " m"
end

return Format
