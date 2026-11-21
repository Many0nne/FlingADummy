# Textures des effets des mannequins de collection (#66) : formes blanches sur fond transparent, teintees en jeu par
# la couleur de l'emetteur (ParticleEmitter.Color, Beam.Color). Style des jeux de reference : formes franches, coeur
# plein, halo doux. star (eclat a 4 branches), glow (halo rond), ring (anneau au sol), bubble (bulle), flake (flocon),
# note (croche), rays (soleil de rayons, derriere le mannequin), beam (faisceau de la colonne de lumiere, defile en
# longueur : axe X de l'image = longueur du faisceau).
# Usage : python -I assets/fx/build_fx_textures.py
# Sortie : assets/fx/export/<nom>.png et assets/fx/export/sheet.png (planche de controle sur fond sombre).
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = os.path.join(HERE, "export")
N = 256  # cote des textures carrees
SS = 2  # sur-echantillonnage du dessin (lissage)


def canvas(w=N, h=N):
    """Cette methode permet de creer un masque noir sur-echantillonne lorsque l'on dessine une forme."""
    return Image.new("L", (w * SS, h * SS), 0)


def finish(mask, blur=0, glow=0, glow_strength=0.6):
    """Cette methode permet de reduire un masque, d'y ajouter un halo flou et d'en faire une image blanche dont
    l'alpha est le masque lorsque la forme est dessinee."""
    w, h = mask.size[0] // SS, mask.size[1] // SS
    mask = mask.resize((w, h), Image.LANCZOS)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur))
    if glow:
        halo = mask.filter(ImageFilter.GaussianBlur(glow)).point(lambda v: int(v * glow_strength))
        mask = ImageChops.lighter(mask, halo)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def star():
    """Cette methode permet de dessiner l'eclat a 4 branches effilees (scintillement) lorsque la texture star est
    produite."""
    m = canvas()
    d = ImageDraw.Draw(m)
    c = N * SS / 2
    long_, thin = c * 0.92, c * 0.11
    for angle in (0, 90):
        a = math.radians(angle)
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        pts = [(c + ux * long_, c + uy * long_), (c + px * thin, c + py * thin), (c - ux * long_, c - uy * long_),
               (c - px * thin, c - py * thin)]
        d.polygon(pts, fill=255)
    r = c * 0.16
    d.ellipse((c - r, c - r, c + r, c + r), fill=255)
    return finish(m, blur=1, glow=18, glow_strength=0.7)


def glow():
    """Cette methode permet de dessiner un halo rond, plein au centre et fondu au bord, lorsque la texture glow est
    produite."""
    img = Image.new("L", (N, N), 0)
    px = img.load()
    c = (N - 1) / 2
    for y in range(N):
        for x in range(N):
            r = math.hypot(x - c, y - c) / c
            px[x, y] = int(255 * max(0.0, 1 - r) ** 2.2)
    out = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    out.putalpha(img)
    return out


def ring():
    """Cette methode permet de dessiner un anneau epais au bord doux (onde au sol) lorsque la texture ring est
    produite."""
    m = canvas()
    d = ImageDraw.Draw(m)
    c = N * SS / 2
    outer, inner = c * 0.86, c * 0.66
    d.ellipse((c - outer, c - outer, c + outer, c + outer), fill=255)
    d.ellipse((c - inner, c - inner, c + inner, c + inner), fill=0)
    return finish(m, blur=3, glow=14, glow_strength=0.8)


def bubble():
    """Cette methode permet de dessiner une bulle (contour, reflet) lorsque la texture bubble est produite."""
    m = canvas()
    d = ImageDraw.Draw(m)
    c = N * SS / 2
    r = c * 0.8
    d.ellipse((c - r, c - r, c + r, c + r), fill=70)
    d.ellipse((c - r, c - r, c + r, c + r), outline=255, width=int(c * 0.13))
    hx, hy, hr = c - r * 0.38, c - r * 0.38, r * 0.2
    d.ellipse((hx - hr, hy - hr, hx + hr, hy + hr), fill=255)
    return finish(m, blur=1)


def flake():
    """Cette methode permet de dessiner un flocon a 6 branches et petites barbes lorsque la texture flake est
    produite."""
    m = canvas()
    d = ImageDraw.Draw(m)
    c = N * SS / 2
    width = int(c * 0.1)
    for k in range(6):
        a = math.radians(90 + k * 60)
        ux, uy = math.cos(a), math.sin(a)
        end = (c + ux * c * 0.86, c - uy * c * 0.86)
        d.line([(c, c), end], fill=255, width=width)
        for t, length in ((0.5, 0.26), (0.72, 0.18)):
            bx, by = c + ux * c * t, c - uy * c * t
            for side in (-1, 1):
                b = a + side * math.radians(45)
                d.line([(bx, by), (bx + math.cos(b) * c * length, by - math.sin(b) * c * length)], fill=255,
                       width=int(width * 0.8))
    r = c * 0.14
    d.ellipse((c - r, c - r, c + r, c + r), fill=255)
    return finish(m, blur=1, glow=10, glow_strength=0.5)


def note():
    """Cette methode permet de dessiner une croche (tete penchee, hampe, crochet) lorsque la texture note est
    produite."""
    m = canvas()
    d = ImageDraw.Draw(m)
    s = N * SS
    # Tete ovale penchee : ellipse dessinee a part puis tournee
    head = Image.new("L", (int(s * 0.42), int(s * 0.3)), 0)
    ImageDraw.Draw(head).ellipse((0, 0, head.size[0] - 1, head.size[1] - 1), fill=255)
    head = head.rotate(25, expand=True)
    m.paste(255, (int(s * 0.14), int(s * 0.6)), head)
    x = int(s * 0.5)
    d.rectangle((x, int(s * 0.12), x + int(s * 0.08), int(s * 0.74)), fill=255)
    d.polygon([(x, int(s * 0.12)), (x + int(s * 0.36), int(s * 0.32)), (x + int(s * 0.3), int(s * 0.46)),
               (x + int(s * 0.04), int(s * 0.3))], fill=255)
    return finish(m, blur=1, glow=10, glow_strength=0.5)


def rays():
    """Cette methode permet de dessiner un soleil de 12 rayons fondus vers l'exterieur (gloire derriere un mannequin
    rare) lorsque la texture rays est produite."""
    m = canvas()
    d = ImageDraw.Draw(m)
    c = N * SS / 2
    for k in range(12):
        a0 = math.radians(k * 30 - 6)
        a1 = math.radians(k * 30 + 6)
        d.polygon([(c, c), (c + math.cos(a0) * c, c + math.sin(a0) * c), (c + math.cos(a1) * c,
                                                                           c + math.sin(a1) * c)], fill=255)
    rays_img = finish(m, blur=2)
    # Fondu radial : rayons pleins au centre, transparents au bord
    alpha = rays_img.getchannel("A")
    fade = glow().getchannel("A").point(lambda v: min(255, int(v * 1.6)))
    rays_img.putalpha(ImageChops.multiply(alpha, fade))
    return rays_img


def beam():
    """Cette methode permet de dessiner le faisceau de la colonne de lumiere (plein au centre, fondu sur les bords,
    trainees qui se repetent en longueur pour defiler sans couture) lorsque la texture beam est produite."""
    w, h = 256, 64
    img = Image.new("L", (w, h), 0)
    px = img.load()
    for y in range(h):
        across = 1 - abs((y - (h - 1) / 2) / ((h - 1) / 2))
        across = across ** 1.6
        for x in range(w):
            streak = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * (x / w * 3 + y / h * 0.6)))
            px[x, y] = int(255 * across * streak)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(img)
    return out


TEXTURES = {
    "star": star,
    "glow": glow,
    "ring": ring,
    "bubble": bubble,
    "flake": flake,
    "note": note,
    "rays": rays,
    "beam": beam,
}


def main():
    """Cette methode permet d'ecrire toutes les textures et leur planche de controle lorsque le script est lance."""
    os.makedirs(EXPORT, exist_ok=True)
    tiles = []
    for name, make in TEXTURES.items():
        img = make()
        img.save(os.path.join(EXPORT, name + ".png"))
        tiles.append(img)
    cell = 140
    sheet = Image.new("RGBA", (cell * len(tiles), cell), (30, 32, 44, 255))
    for i, img in enumerate(tiles):
        t = img.copy()
        t.thumbnail((cell - 12, cell - 12))
        tint = Image.new("RGBA", t.size, (120, 255, 225, 255))
        tint.putalpha(t.getchannel("A"))
        sheet.alpha_composite(tint, (i * cell + (cell - t.width) // 2, (cell - t.height) // 2))
    sheet.save(os.path.join(EXPORT, "sheet.png"))
    print("[fx] textures", EXPORT)


main()
