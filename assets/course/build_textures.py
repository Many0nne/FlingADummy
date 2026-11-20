"""Textures « briques à tenons » du décor (jeux de référence 01 / 09 : carrés en creux sur couleurs saturées).

Produit dans assets/course/export/ :
- checker_color.png / checker_normal.png : tuile de 16 × 16 studs, damier 2 × 2 de carreaux de 8 studs (un carreau
  sur deux assombri) couverts de briques de 2 studs à carré en creux. Sol et parois (MaterialVariant « FadChecker »).
- brick_color.png / brick_normal.png : une brique de 2 × 2 studs, mêmes motifs, sans damier. Accessoires
  (MaterialVariant « FadBrick »).

Les cartes de couleur sont en gris clair : la couleur de la pièce les teinte (MaterialVariant). Normales au format
OpenGL (Y vers le haut), comme Roblox les attend.

Usage : python -I assets/course/build_textures.py
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "export")

BRICK_PX = 128  # pixels par brique (2 studs)
BASE = 236  # gris de la face d'une brique
CHECKER_DARK = 0.80  # carreaux sombres du damier
SEAM = 0.03  # joint entre briques (fraction de la brique)
INSET_MIN, INSET_MAX = 0.2, 0.8  # carré en creux
BEVEL = 0.07  # largeur de la paroi du creux
NORMAL_TILT = 0.55  # pente des parois (composante latérale de la normale)


def brick_cell(u, v):
    """Renvoie (luminosité relative, normale x, normale y) au point (u, v) d'une brique, u et v dans [0, 1[."""
    # Joint : petit sillon le long des bords de la brique
    if u < SEAM or v < SEAM or u > 1 - SEAM or v > 1 - SEAM:
        return 0.84, 0.0, 0.0
    lo, hi = INSET_MIN, INSET_MAX
    if lo <= u <= hi and lo <= v <= hi:
        # Parois du creux : haut et gauche à l'ombre (la lumière vient d'en haut à gauche), bas et droite éclairés
        dl, dr, dt, db = u - lo, hi - u, v - lo, hi - v
        edge = min(dl, dr, dt, db)
        if edge < BEVEL:
            if edge == dt:
                return 0.72, 0.0, -NORMAL_TILT
            if edge == dl:
                return 0.80, NORMAL_TILT, 0.0
            if edge == db:
                return 1.07, 0.0, NORMAL_TILT
            return 1.03, -NORMAL_TILT, 0.0
        return 0.94, 0.0, 0.0  # fond du creux
    return 1.0, 0.0, 0.0


def build(bricks, checker):
    """Construit (couleur, normales) d'une tuile de `bricks` × `bricks` briques, damier 2 × 2 si `checker`."""
    size = bricks * BRICK_PX
    color = Image.new("RGB", (size, size))
    normal = Image.new("RGB", (size, size))
    cpx, npx = color.load(), normal.load()
    # Motif d'une brique calculé une fois, puis répété
    cell = [[brick_cell((x + 0.5) / BRICK_PX, (y + 0.5) / BRICK_PX) for x in range(BRICK_PX)] for y in range(BRICK_PX)]
    half = size // 2
    for y in range(size):
        for x in range(size):
            light, nx, ny = cell[y % BRICK_PX][x % BRICK_PX]
            if checker and ((x < half) != (y < half)):
                light *= CHECKER_DARK
            g = max(0, min(255, round(BASE * light)))
            cpx[x, y] = (g, g, g)
            nz = (1 - nx * nx - ny * ny) ** 0.5
            npx[x, y] = (round((nx + 1) * 127.5), round((ny + 1) * 127.5), round((nz + 1) * 127.5))
    return color, normal


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, bricks, checker in (("checker", 8, True), ("brick", 1, False)):
        color, normal = build(bricks, checker)
        color.save(os.path.join(OUT, f"{name}_color.png"))
        normal.save(os.path.join(OUT, f"{name}_normal.png"))
        print(f"{name}: {color.size[0]} px")


if __name__ == "__main__":
    main()
