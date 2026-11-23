# Textures de lumiere de l'interface (#194) : formes blanches sur fond transparent, teintees en jeu (ImageColor3).
# Style des jeux de reference (02, 09, 01) : pas de bandes regulieres, une lumiere douce.
#   sunburst : soleil de rayons larges, fondus vers l'exterieur, rythme irregulier (derriere un objet mis en avant)
#   halo     : halo rond, coeur plus vif, bord fondu (derriere une icone)
#   sheen    : faisceaux de lumiere en eventail depuis le coin haut gauche, largeurs et forces inegales (vignettes)
#   vignette : bords assombris d'un panneau (teinte noire en jeu), centre transparent
# Usage : python -I assets/ui/build_ui_textures.py
# Sortie : assets/ui/export/<nom>.png et assets/ui/export/sheet.png (planche de controle sur fond colore).
import math
import os

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = os.path.join(HERE, "export")


def smoothstep(a, b, x):
    """Cette methode permet de passer en douceur de 0 a 1 entre a et b lorsque l'on fond un bord."""
    if a == b:
        return 0.0 if x < a else 1.0
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def render(size, alpha_of, blur=0):
    """Cette methode permet de remplir une image blanche dont l'alpha vaut alpha_of(u, v) (coordonnees de 0 a 1)
    lorsque une texture est produite ; `blur` adoucit les bords."""
    mask = Image.new("L", (size, size), 0)
    data = []
    for y in range(size):
        v = (y + 0.5) / size
        for x in range(size):
            u = (x + 0.5) / size
            data.append(int(255 * min(1.0, max(0.0, alpha_of(u, v)))))
    mask.putdata(data)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


# Rayons du soleil : (largeur relative, force), repetes autour du cercle ; le rythme large / fin / moyen evite le peigne
SUN_PATTERN = [(0.70, 1.0), (0.26, 0.55), (0.50, 0.8)]
SUN_RAYS = 15


def sunburst():
    """Cette methode permet de dessiner le soleil de rayons larges (coins effiles au centre, fondus au bord) lorsque
    la texture sunburst est produite."""
    period = 2 * math.pi / SUN_RAYS

    def alpha(u, v):
        dx, dy = u - 0.5, v - 0.5
        r = math.hypot(dx, dy)
        if r > 0.5:
            return 0.0
        theta = math.atan2(dy, dx) % (2 * math.pi)
        index = int(theta // period)
        width, strength = SUN_PATTERN[index % len(SUN_PATTERN)]
        t = (theta % period) / period  # 0..1 dans la periode, rayon centre sur 0.5
        half = width / 2
        edge = 0.1
        ray = 1 - smoothstep(half - edge, half + edge, abs(t - 0.5))
        fade = 1 - smoothstep(0.2, 0.5, r)
        core = smoothstep(0.02, 0.14, r)
        return ray * strength * fade * core

    return render(512, alpha, blur=1.2)


def halo():
    """Cette methode permet de dessiner un halo rond, coeur vif et bord tres fondu, lorsque la texture halo est
    produite."""

    def alpha(u, v):
        r = math.hypot(u - 0.5, v - 0.5) / 0.5
        if r >= 1:
            return 0.0
        body = 0.85 * (1 - smoothstep(0.0, 1.0, r)) ** 2.2
        core = 0.15 * (1 - smoothstep(0.0, 0.3, r))
        return body + core

    return render(256, alpha)


# Faisceaux de la lumiere en coin : (angle en degres depuis l'horizontale, demi-largeur en degres, force)
SHEEN_BEAMS = [(17, 6.5, 0.95), (31, 1.6, 0.75), (47, 9.0, 0.5), (66, 2.4, 0.6), (78, 4.5, 0.3)]


def sheen():
    """Cette methode permet de dessiner l'eventail de faisceaux inegaux qui part du coin haut gauche et s'eteint vers
    le coin oppose lorsque la texture sheen est produite."""
    ox, oy = -0.08, -0.08

    def alpha(u, v):
        dx, dy = u - ox, v - oy
        d = math.hypot(dx, dy)
        angle = math.degrees(math.atan2(dy, dx))
        light = 0.0
        for center, half, strength in SHEEN_BEAMS:
            offset = abs(angle - center)
            if offset < half * 1.6:
                light = max(light, strength * (1 - smoothstep(half * 0.45, half * 1.6, offset)))
        fade = 1 - smoothstep(0.15, 1.25, d)
        return light * fade

    return render(512, alpha, blur=1.5)


def vignette():
    """Cette methode permet de dessiner des bords assombris (distance en super-ellipse, fond transparent au centre)
    lorsque la texture vignette est produite."""

    def alpha(u, v):
        x, y = abs(u - 0.5) / 0.5, abs(v - 0.5) / 0.5
        d = (x**4 + y**4) ** 0.25
        return smoothstep(0.45, 1.05, d) ** 1.4

    return render(256, alpha)


def main():
    """Cette methode permet de produire toutes les textures et la planche de controle lorsque le script est lance."""
    os.makedirs(EXPORT, exist_ok=True)
    tiles = [("sunburst", sunburst()), ("halo", halo()), ("sheen", sheen()), ("vignette", vignette())]
    for name, img in tiles:
        img.save(os.path.join(EXPORT, name + ".png"))
    cell = 256
    sheet = Image.new("RGBA", (cell * len(tiles), cell), (236, 92, 28, 255))
    for i, (_, img) in enumerate(tiles):
        sheet.alpha_composite(img.resize((cell, cell), Image.LANCZOS), (i * cell, 0))
    sheet.save(os.path.join(EXPORT, "sheet.png"))


if __name__ == "__main__":
    main()
