-- Coulées d'herbe (neige, sable…) qui débordent des marches des parois, comme dans 01 / 09 : blocs qui descendent en
-- escalier (un bloc large, parfois un plus étroit dessous), calés sur les demi-carreaux du damier des parois (FadWall,
-- carreaux de 8 studs : Roblox ancre la texture au coin de chaque pièce) ; les blocs portent FadBrick, dont les tenons
-- (un tous les 2 studs) tombent alors sur ceux de la paroi. Logique pure : Server.CourseBuilder pose les
-- blocs.
local Drips = {}

Drips.GRID = 4 -- largeur des blocs et des écarts : par demi-carreau du damier
Drips.MAX_DROP = 10 -- descente maximale sous la couverture (bloc de 6 studs + marche de 4)
-- Épaisseur de la couverture d'herbe des marches (posée 0,4 sous le dessus du bloc) : c'est aussi la place à laisser sous
-- une coulée, qui part 0,4 sous le dessus d'une marche quand la couverture du dessous dépasse de 0,8 son bloc
Drips.CAP_THICKNESS = 1.2

export type Block = {
	t: number, -- début du bloc le long du bord (studs depuis son origine)
	width: number,
	top: number, -- distance sous la couverture du haut du bloc
	height: number,
}

-- Cette méthode permet de tracer les blocs d'une coulée le long d'un bord de `length` studs qui commence à `origin`
-- (distance au coin de la paroi le long du bord) lorsque l'on habille une paroi ; `int(a, b)`, `real()` : tirages.
function Drips.layout(origin: number, length: number, int: (number, number) -> number, real: () -> number): { Block }
	local grid = Drips.GRID
	local blocks = {}
	-- Départ calé sur la grille du damier de la paroi, puis largeurs et écarts multiples de la grille
	local t = -origin % grid + grid * int(0, 1)
	while t <= length - grid do
		local room = math.floor((length - t) / grid) * grid
		local width = math.min(grid * int(1, 3), room)
		local height = 2 * int(1, 3)
		table.insert(blocks, { t = t, width = width, top = 0, height = height })
		-- Marche du dessous, plus étroite d'un demi-carreau, calée sur un bord du bloc
		if width >= 2 * grid and real() < 0.6 then
			local offset = if real() < 0.5 then 0 else grid
			table.insert(blocks, { t = t + offset, width = width - grid, top = height, height = 2 * int(1, 2) })
		end
		t += width + grid * int(0, 2)
	end
	return blocks
end

return Drips
