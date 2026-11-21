-- Mise en forme des nombres affichés (argent, puissance, distances, CHANCE, cotes « 1 IN N »). Les grands nombres
-- s'abrègent comme dans les jeux de référence (K, M, B, T, Qa, Qi, Sx… : « 1 IN 300Qa » de Throw a Seed).
local Format = {}

-- Suffixes par puissance de 1 000 (1e3 … 1e33) ; au-delà, notation scientifique (« 1.2e36 »)
Format.SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local SUFFIXES = Format.SUFFIXES

-- Marge relative contre les erreurs de virgule flottante (4.1 × 100 = 409.99999999999994) : bien plus petite que
-- l'écart entre deux valeurs affichables (999 999 999 999 s'écrit toujours 999B)
local EPSILON = 1e-13

-- Cette méthode permet d'écrire un entier avec séparateurs de milliers lorsque l'interface affiche un montant exact ;
-- sans notation scientifique, même au-delà de 2^53 (chiffres de poids faible alors approximatifs).
function Format.thousands(n: number): string
	if n ~= n then
		return "0"
	end
	local digits = string.format("%.0f", math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return (if n < 0 then "-" else "") .. grouped
end

-- Cette méthode permet d'abréger un grand nombre (`950`, `1.2K`, `34.5M`, `300Qa`) lorsque l'interface affiche un
-- compteur ; 3 chiffres significatifs au-delà de 1 000, tronqués (999 999 s'écrit 999K, jamais 1000K), sans zéros
-- inutiles.
function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local value = math.floor(math.abs(n))
	local sign = if n < 0 then "-" else ""
	if value < 1000 then
		return sign .. tostring(value)
	end
	if value == math.huge or value >= 1000 ^ (#SUFFIXES + 1) then
		return sign .. (if value == math.huge then "inf" else (string.gsub(string.format("%.2g", value), "e%+", "e")))
	end
	-- Rang par le logarithme, corrigé d'un cran si l'arrondi du logarithme tombe à côté (999.999… ou 1000.000…)
	local tier = math.clamp(math.floor(math.log10(value) / 3), 1, #SUFFIXES)
	local scaled = value / 1000 ^ tier
	if scaled >= 1000 and tier < #SUFFIXES then
		tier += 1
		scaled = value / 1000 ^ tier
	elseif scaled < 1 then
		tier -= 1
		scaled = value / 1000 ^ tier
	end
	local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local factor = 10 ^ decimals
	local kept = math.floor(scaled * factor + EPSILON * scaled * factor) / factor
	local text = string.format("%." .. decimals .. "f", kept)
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

-- Cette méthode permet d'écrire un revenu par seconde (`+$1.2K/s`) lorsque le compteur d'argent affiche le revenu.
function Format.perSecond(n: number): string
	return "+" .. Format.money(math.max(0, n)) .. "/s"
end

-- Cette méthode permet d'écrire une distance arrondie au mètre (`1,234 m`) lorsque l'interface l'affiche.
function Format.meters(n: number): string
	return Format.thousands(math.max(0, n)) .. " m"
end

-- Cette méthode permet d'écrire une cote « 1 IN N » abrégée (`1 IN 2.27K`, `1 IN 300Qa`) lorsque le tirage, l'Index
-- ou une annonce l'affichent ; au moins « 1 IN 1 ».
function Format.odds(n: number): string
	return "1 IN " .. Format.short(math.max(1, n))
end

-- Cette méthode permet d'écrire une cote complète avec séparateurs (`2,000,000`) tant qu'elle reste lisible (moins de
-- 10 chiffres), abrégée au-delà (`300Qa`), lorsque la bannière du secret l'affiche en grand.
function Format.fullOdds(n: number): string
	local value = math.max(1, n)
	return if value < 1e9 then Format.thousands(value) else Format.short(value)
end

-- Cette méthode permet d'écrire la CHANCE finale d'un lancer (`X1.36`, deux décimales jusqu'à 100, une jusqu'à 1 000,
-- abrégée au-delà : `X12.3K` ; au moins X1.00) lorsque le mannequin arrêté l'affiche au-dessus de lui ; le format se
-- choisit sur la valeur arrondie (99.996 s'écrit X100.0, 999.96 s'écrit X1K).
function Format.multiplier(chance: number): string
	local value = math.max(1, chance)
	local hundredths = math.floor(value * 100 + 0.5) / 100
	if hundredths < 100 then
		return string.format("X%.2f", hundredths)
	end
	local tenths = math.floor(value * 10 + 0.5) / 10
	if tenths < 1000 then
		return string.format("X%.1f", tenths)
	end
	return "X" .. Format.short(tenths)
end

-- Cette méthode permet d'écrire le multiplicateur de chance d'un mannequin à lancer comme les graines de 09 (`1.0x`,
-- `1.25x`, `2.0x` : au moins une décimale, au plus deux ; entier dès 10 : `13x`, `135x` ; abrégé dès 1 000 : `1.5Kx`)
-- lorsque la boutique ou la bannière CHANCE l'affichent ; le format se choisit sur la valeur arrondie.
function Format.luck(multiplier: number): string
	local hundredths = math.floor(multiplier * 100 + 0.5) / 100
	if hundredths >= 10 then
		local whole = math.floor(multiplier + 0.5)
		return (if whole >= 1000 then Format.short(whole) else tostring(whole)) .. "x"
	end
	local text = string.format("%.2f", hundredths)
	if string.sub(text, -1) == "0" then
		text = string.sub(text, 1, -2)
	end
	return text .. "x"
end

return Format
