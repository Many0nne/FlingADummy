"""Textures « briques à tenons » du décor (jeux de référence 01 / 09 : tenons en relief sur couleurs saturées).

Produit dans assets/course/export/ :
- checker_color.png / checker_normal.png : tuile de 16 × 16 studs, damier 2 × 2 de carreaux de 8 studs (un carreau
  sur deux assombri de CHECKER_DARK) portant chacun 4 × 4 tenons (un tous les 2 studs). Sol (MaterialVariant
  « FadChecker »).
- wall_color.png : même tuile au damier plus doux (WALL_DARK), avec checker_normal.png. Parois en gradins, couverture
  d'herbe (MaterialVariant « FadWall »).
- brick_color.png / brick_normal.png : un tenon sur une cellule de 2 × 2 studs, sans damier. Accessoires, barrières,
  poteaux, stands, obstacles (MaterialVariant « FadBrick »).

Le tenon est un carré aux coins arrondis, en relief : biseau clair en haut à gauche (côté lumière), sombre en bas à
droite, petite ombre portée en bas à droite, comme sur les captures de 01 (sol, poteaux). Pas de joint entre les
cellules : la plaque est unie entre les tenons.

Les cartes de couleur sont en gris : la couleur de la pièce les teinte (MaterialVariant). Normales au format OpenGL
(vert = haut de l'image), comme Roblox les attend.

Usage : python -I assets/course/build_textures.py
"""

import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "export")

BASE = 214  # gris de la plaque (marge sous 255 pour le biseau éclairé)
# Carreaux sombres du damier, mesurés en jeu contre 01 (rapport clair / sombre rendu ≈ facteur ** 1,5) : sol très
# marqué (rendu ≈ 0,64), parois et herbe plus douces (rendu ≈ 0,8)
CHECKER_DARK = 0.74
WALL_DARK = 0.86
STUD_HALF = 0.20  # demi-côté du tenon (fraction de la cellule de 2 studs) : tenon de 40 %
STUD_RADIUS = 0.06  # arrondi des coins du tenon
BEVEL = 0.055  # largeur du biseau du tenon
STUD_TOP = 1.03  # dessus du tenon, à peine plus clair que la plaque
BEVEL_LIGHT = 0.19  # écart de luminosité des biseaux (+ côté lumière, − à l'opposé)
SHADOW_OFFSET = 0.04  # décalage de l'ombre portée vers le bas à droite
SHADOW = 0.86  # luminosité de l'ombre portée
NORMAL_TILT = 0.6  # pente du biseau (composante latérale de la normale)
SUPERSAMPLE = 3  # échantillons par axe et par pixel (bords lissés)
LIGHT = (-1 / math.sqrt(2), -1 / math.sqrt(2))  # lumière venant d'en haut à gauche (repère image : y vers le bas)


def stud_sdf(x, y):
    """Cette méthode permet de donner la distance signée au bord du tenon (négative dedans) et la direction sortante
    lorsque l'on ombre un point (x, y) centré sur la cellule."""
    half = STUD_HALF - STUD_RADIUS
    qx, qy = abs(x) - half, abs(y) - half
    ox, oy = max(qx, 0.0), max(qy, 0.0)
    outside = math.hypot(ox, oy)
    dist = outside + min(max(qx, qy), 0.0) - STUD_RADIUS
    # Direction sortante : radiale dans les coins arrondis, sinon perpendiculaire au côté le plus proche
    if outside > 0:
        gx, gy = ox / outside, oy / outside
    elif qx > qy:
        gx, gy = 1.0, 0.0
    else:
        gx, gy = 0.0, 1.0
    return dist, math.copysign(gx, x), math.copysign(gy, y)


def sample(u, v):
    """Cette méthode permet de donner (luminosité relative, normale x, normale y en repère image) lorsque l'on échantillonne
    le point (u, v) d'une cellule, u et v dans [0, 1[."""
    x, y = u - 0.5, v - 0.5
    dist, gx, gy = stud_sdf(x, y)
    if dist <= -BEVEL:
        return STUD_TOP, 0.0, 0.0
    if dist <= 0:
        # Biseau : éclairé s'il fait face à la lumière, avec une pente qui suit la direction sortante
        facing = gx * LIGHT[0] + gy * LIGHT[1]
        return 1.0 + BEVEL_LIGHT * facing, gx * NORMAL_TILT, gy * NORMAL_TILT
    shadow, _, _ = stud_sdf(x - SHADOW_OFFSET, y - SHADOW_OFFSET)
    if shadow < 0:
        return SHADOW, 0.0, 0.0
    return 1.0, 0.0, 0.0


def cell(px):
    """Cette méthode permet de calculer le motif lissé d'une cellule de `px` pixels (lignes de (luminosité, normale RGB))
    lorsque l'on construit une tuile."""
    rows = []
    n = SUPERSAMPLE
    for py in range(px):
        row = []
        for pxx in range(px):
            light = nx = ny = 0.0
            for sy in range(n):
                for sx in range(n):
                    l, a, b = sample((pxx + (sx + 0.5) / n) / px, (py + (sy + 0.5) / n) / px)
                    light, nx, ny = light + l, nx + a, ny + b
            light, nx, ny = light / (n * n), nx / (n * n), ny / (n * n)
            # Repère image (y vers le bas) vers OpenGL (vert vers le haut)
            gy = -ny
            nz = math.sqrt(max(0.0, 1 - nx * nx - gy * gy))
            normal = (round((nx + 1) * 127.5), round((gy + 1) * 127.5), round((nz + 1) * 127.5))
            row.append((light, normal))
        rows.append(row)
    return rows


def build(cells, cell_px, checker):
    """Cette méthode permet de construire (couleur, normales) d'une tuile de `cells` × `cells` cellules lorsque l'on
    exporte une carte ; damier 2 × 2 assombri de `checker` (None : sans damier)."""
    size = cells * cell_px
    color = Image.new("RGB", (size, size))
    normal = Image.new("RGB", (size, size))
    cpx, npx = color.load(), normal.load()
    motif = cell(cell_px)
    half = size // 2
    for y in range(size):
        for x in range(size):
            light, n = motif[y % cell_px][x % cell_px]
            if checker and ((x < half) != (y < half)):
                light *= checker
            g = max(0, min(255, round(BASE * light)))
            cpx[x, y] = (g, g, g)
            npx[x, y] = n
    return color, normal


def main():
    os.makedirs(OUT, exist_ok=True)
    # Damier : 8 × 8 cellules de 128 px (1 024 px, plafond des textures Roblox) ; brique seule : 256 px (gros plan).
    # La paroi ne diffère du sol que par le damier : elle reprend checker_normal.png.
    tiles = (("checker", 8, 128, CHECKER_DARK), ("wall", 8, 128, WALL_DARK), ("brick", 1, 256, None))
    for name, cells, cell_px, checker in tiles:
        color, normal = build(cells, cell_px, checker)
        color.save(os.path.join(OUT, f"{name}_color.png"))
        if name != "wall":
            normal.save(os.path.join(OUT, f"{name}_normal.png"))
        print(f"{name}: {color.size[0]} px")


if __name__ == "__main__":
    main()
