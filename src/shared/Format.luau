-- Mise en forme des nombres affichés (argent, distances).
local Format = {}

-- Cette méthode permet d'écrire un entier avec séparateurs de milliers lorsque l'interface affiche un montant.
function Format.thousands(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return (if n < 0 then "-" else "") .. grouped
end

-- Cette méthode permet d'écrire une somme d'argent (`$12,345`) lorsque l'interface l'affiche.
function Format.money(n: number): string
	if n < 0 then
		return "-$" .. Format.thousands(-n)
	end
	return "$" .. Format.thousands(n)
end

-- Cette méthode permet d'écrire une distance arrondie au mètre (`123 m`) lorsque l'interface l'affiche.
function Format.meters(n: number): string
	return Format.thousands(math.max(0, n)) .. " m"
end

return Format
