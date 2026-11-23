# Icone et vignettes de la page du jeu (#178) : composees a partir des captures du jeu reel (assets/store/captures/,
# prises en Studio par assets/store/studio/, procedure dans assets/store/README.md), au style des jeux de reference
# (01 / 02 / 09) : couleurs poussees, arc jaune du lancer, silhouette noire « ? » et « !! » rouges, gros texte a
# contour noir en degrade (police LuckiestGuy, celle du jeu, lue dans l'installation de Roblox).
# Usage : python -I assets/store/compose.py [--refs <dossier>]
#   --refs : dossier des icones et vignettes des references (<placeId>_icon.png, <placeId>_thumb<n>.png), pour la
#            planche de comparaison docs/captures/sortie-178/comparaison.jpg
# Sortie : assets/store/export/icon.png (512 x 512), thumb-<n>.png (1920 x 1080), planche.jpg (controle).
import argparse
import glob
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CAPTURES = os.path.join(HERE, "captures")
EXPORT = os.path.join(HERE, "export")
RENDERS = os.path.join(ROOT, "assets", "dummy", "export", "collection")
COMPARE = os.path.join(ROOT, "docs", "captures", "sortie-178", "comparaison.jpg")
THUMB = (1920, 1080)
ICON = 512
REF_PLACES = ["120219252362013", "114326934417838", "129081220403721"]  # 01, 02, 09

YELLOW = (255, 214, 30)
ORANGE = (255, 140, 0)
RED = (255, 40, 40)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)


def font_path():
    """Cette methode permet de trouver la police LuckiestGuy de l'installation de Roblox (celle des titres du jeu)
    lorsque l'on ecrit un texte ; la variable FAD_FONT la remplace."""
    if os.environ.get("FAD_FONT"):
        return os.environ["FAD_FONT"]
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Roblox", "Versions")
    found = sorted(glob.glob(os.path.join(base, "*", "content", "fonts", "LuckiestGuy-Regular.ttf")))
    if not found:
        raise SystemExit("LuckiestGuy-Regular.ttf introuvable : installer Roblox Studio ou definir FAD_FONT")
    return found[-1]


FONT = None


def font(size):
    """Cette methode permet de charger la police des titres a la taille voulue lorsque l'on ecrit un texte."""
    global FONT
    FONT = FONT or font_path()
    return ImageFont.truetype(FONT, size)


def vivid(img, color=1.3, contrast=1.08, bright=1.04):
    """Cette methode permet de pousser couleurs et contraste d'une capture (rendu sature des references) lorsque l'on
    prepare le fond d'une image."""
    img = ImageEnhance.Color(img).enhance(color)
    img = ImageEnhance.Contrast(img).enhance(contrast)
    return ImageEnhance.Brightness(img).enhance(bright)


def cover(img, size, box=None):
    """Cette methode permet de recadrer une capture (rectangle `box` en fractions x0, y0, x1, y1, sinon au centre)
    puis de la mettre a la taille `size` lorsque l'on prepare le fond d'une image."""
    w, h = img.size
    if box:
        img = img.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))
        w, h = img.size
    target = size[0] / size[1]
    if w / h > target:
        nw = int(h * target)
        img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = int(w / target)
        img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    return img.resize(size, Image.LANCZOS)


def gradient(size, top, bottom):
    """Cette methode permet de creer un degrade vertical de `top` a `bottom` lorsque l'on remplit un texte."""
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((w, h))


def rainbow(size):
    """Cette methode permet de creer un degrade arc-en-ciel horizontal lorsque l'on ecrit une cote « 1 IN N »."""
    w, h = size
    stops = [(255, 60, 60), (255, 170, 30), (255, 240, 40), (70, 230, 90), (60, 170, 255), (190, 90, 255)]
    row = Image.new("RGB", (w, 1))
    for x in range(w):
        t = x / max(w - 1, 1) * (len(stops) - 1)
        i = min(int(t), len(stops) - 2)
        f = t - i
        row.putpixel((x, 0), tuple(int(stops[i][k] + (stops[i + 1][k] - stops[i][k]) * f) for k in range(3)))
    return row.resize((w, h))


def text_layer(text, size, fill, outline=None, rainbow_fill=False, shadow=True):
    """Cette methode permet de rendre un texte (degrade `fill` = (haut, bas), contour noir, ombre portee) sur un
    calque transparent lorsque l'on ajoute un titre a une image."""
    f = font(size)
    outline = outline if outline is not None else max(4, size // 9)
    left, top, right, bottom = f.getbbox(text, stroke_width=outline)
    pad = outline + size // 8
    w, h = right - left + 2 * pad, bottom - top + 2 * pad
    origin = (pad - left, pad - top)
    stroke = Image.new("L", (w, h), 0)
    ImageDraw.Draw(stroke).text(origin, text, font=f, fill=255, stroke_width=outline, stroke_fill=255)
    inner = Image.new("L", (w, h), 0)
    ImageDraw.Draw(inner).text(origin, text, font=f, fill=255)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    if shadow:
        off = max(3, size // 14)
        shade = Image.new("RGBA", (w, h), (0, 0, 0, 150))
        layer.paste(shade, (off, off), stroke)
    layer.paste(Image.new("RGBA", (w, h), BLACK + (255,)), (0, 0), stroke)
    paint = rainbow((w, h)) if rainbow_fill else gradient((w, h), fill[0], fill[1])
    layer.paste(paint.convert("RGBA"), (0, 0), inner)
    # Reflet clair en haut des lettres
    shine = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shine).rectangle((0, 0, w, origin[1] + int(size * 0.32)), fill=70)
    layer.paste(Image.new("RGBA", (w, h), WHITE + (255,)), (0, 0), ImageChops.multiply(inner, shine))
    return layer


def put(img, layer, center, angle=0):
    """Cette methode permet de coller un calque centre sur `center`, tourne de `angle` degres, lorsque l'on compose."""
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x, y = int(center[0] - layer.width / 2), int(center[1] - layer.height / 2)
    img.alpha_composite(layer, (max(x, 0), max(y, 0)), (max(-x, 0), max(-y, 0)))


def bezier(p0, p1, p2, n=80):
    """Cette methode permet d'echantillonner une courbe de Bezier quadratique lorsque l'on trace l'arc du lancer."""
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))
    return pts


def arc(img, p0, p1, p2, width, gap=None):
    """Cette methode permet de tracer l'arc jaune du lancer (bord orange, epaisseur qui grandit vers l'arrivee comme
    dans les references) de `p0` a `p2`, controle `p1`, interrompu sur `gap` (t debut, t fin : l'objet en vol passe
    devant), lorsque l'on compose une vignette."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    n = 400
    pts = [(i / n, p) for i, p in enumerate(bezier(p0, p1, p2, n=n))]
    if gap:
        pts = [(t, p) for t, p in pts if not gap[0] < t < gap[1]]
    for color, extra in ((ORANGE + (255,), 0.45), (YELLOW + (255,), 0.0)):
        for t, (x, y) in pts:
            r = width * (0.55 + 0.45 * t) * (1 + extra) / 2
            d.ellipse((x - r, y - r, x + r, y + r), fill=color)
    img.alpha_composite(layer)


def streaks(img, tip, direction, length, spread, count=7, width=10, seed=3):
    """Cette methode permet de dessiner des traits de vitesse blancs derriere un objet en vol (pointe `tip`, sens de
    deplacement `direction`) lorsque l'on compose une image."""
    import random

    rnd = random.Random(seed)
    dx, dy = direction
    n = math.hypot(dx, dy)
    dx, dy = dx / n, dy / n
    px, py = -dy, dx
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(count):
        off = (i - (count - 1) / 2) / max(count - 1, 1) * spread + rnd.uniform(-spread * 0.08, spread * 0.08)
        start = rnd.uniform(0.15, 0.45) * length
        span = rnd.uniform(0.45, 1.0) * length
        x0, y0 = tip[0] - dx * start + px * off, tip[1] - dy * start + py * off
        x1, y1 = x0 - dx * span, y0 - dy * span
        d.line((x0, y0, x1, y1), fill=(255, 255, 255, 215), width=width)
        r = width / 2
        d.ellipse((x0 - r, y0 - r, x0 + r, y0 + r), fill=(255, 255, 255, 215))
    img.alpha_composite(layer)


def silhouette(img, render_id, center, height, rim=12):
    """Cette methode permet de poser la silhouette noire d'un mannequin de collection (apercu Blender, bord blanc)
    centree sur `center`, haute de `height` px, lorsque l'on compose la vignette mystere."""
    src = Image.open(os.path.join(RENDERS, render_id + ".png")).convert("RGBA")
    alpha = src.getchannel("A").point(lambda a: 255 if a > 12 else 0)
    # Trous des effets transparents bouches (fermeture : dilatation puis erosion)
    alpha = alpha.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    bbox = alpha.getbbox()
    alpha = alpha.crop(bbox)
    scale = height / alpha.height
    alpha = alpha.resize((int(alpha.width * scale), int(alpha.height * scale)), Image.LANCZOS)
    alpha = alpha.point(lambda a: 255 if a > 110 else 0).filter(ImageFilter.GaussianBlur(1.2))
    pad = rim * 2
    w, h = alpha.width + 2 * pad, alpha.height + 2 * pad
    big = Image.new("L", (w, h), 0)
    big.paste(alpha, (pad, pad))
    ring = big.filter(ImageFilter.MaxFilter(rim * 2 + 1)).filter(ImageFilter.GaussianBlur(1.5))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    layer.paste(Image.new("RGBA", (w, h), WHITE + (255,)), (0, 0), ring)
    layer.paste(Image.new("RGBA", (w, h), (12, 12, 16, 255)), (0, 0), big)
    put(img, layer, center)


def load(name):
    """Cette methode permet de lire une capture du jeu (assets/store/captures/<name>.jpg) lorsque l'on compose."""
    return Image.open(os.path.join(CAPTURES, name + ".jpg")).convert("RGB")


# --- Images ---------------------------------------------------------------------------------------------------------
# Positions en pixels de l'image finale ; reglees d'apres les captures (voir assets/store/README.md).


def icon():
    """Cette methode permet de composer l'icone (512 x 512) : avatar bacon hair qui lance, mannequin en vol, Crash King
    dans le canyon, sans texte ni retouche comme les icones des references (la scene est entierement dans la capture)."""
    return vivid(cover(load("icon"), (ICON, ICON), ICON_BOX)).convert("RGBA")


def thumb_arc():
    """Cette methode permet de composer la vignette du lancer : arc jaune jusqu'au mannequin geant, cote « 1 IN 100T »."""
    img = vivid(cover(load("arc"), THUMB, ARC["box"])).convert("RGBA")
    arc(img, *ARC["arc"], width=40, gap=ARC["gap"])
    put(img, text_layer("1 IN 100T", 170, None, rainbow_fill=True), ARC["odds"], angle=-3)
    return img


def thumb_mystery():
    """Cette methode permet de composer la vignette mystere : silhouette noire « ? », « !! » rouges, mannequin en vol."""
    img = vivid(cover(load("mystery"), THUMB, MYSTERY["box"])).convert("RGBA")
    streaks(img, MYSTERY["tip"], MYSTERY["dir"], 300, 170, count=6, width=13)
    silhouette(img, MYSTERY["render"], MYSTERY["sil"], MYSTERY["sil_h"])
    put(img, text_layer("?", 330, (WHITE, (225, 225, 235)), outline=26), MYSTERY["q"], angle=-8)
    put(img, text_layer("!!", 230, ((255, 90, 70), (210, 0, 0)), outline=20), MYSTERY["bang"], angle=12)
    return img


def thumb_smash():
    """Cette methode permet de composer la vignette du vol : le mannequin traverse les obstacles, « SMASH! »."""
    img = vivid(cover(load("smash"), THUMB, SMASH["box"])).convert("RGBA")
    put(img, text_layer(SMASH["text"], 190, (YELLOW, ORANGE)), SMASH["at"], angle=-6)
    if SMASH.get("sub"):
        put(img, text_layer(SMASH["sub"], 95, (WHITE, (200, 235, 255))), SMASH["sub_at"], angle=-6)
    return img


def thumb_collection():
    """Cette methode permet de composer la vignette de la collection : avatar bras leves devant trois mannequins rares
    geants, revenu par seconde de l'Infinite Crash King (valeur affichee en jeu)."""
    img = vivid(cover(load("collection"), THUMB, COLLECTION["box"])).convert("RGBA")
    put(img, text_layer(COLLECTION["income"], 180, ((150, 255, 90), (30, 190, 40))), COLLECTION["at"], angle=-4)
    return img


# Captures de 1614 x 759 (fenetre de Studio) : cadre carre de l'icone, cadre 16:9 de chaque vignette
ICON_BOX = (370 / 1614, 0, 1129 / 1614, 1)
# Arc : trainee du lancer, de la main de l'avatar (940, 560 dans la capture) jusqu'au mannequin en vol (605, 230) ;
# vue de dos, la main et les pieds du roi se superposent presque a l'image, un arc jusqu'au roi repartirait sur ses
# pas. Capture recadree de x = 132 a 1481 puis agrandie de 1,4233.
ARC = {
    "box": (132 / 1614, 0, 1481 / 1614, 1),
    "arc": ((1150, 790), (1090, 210), (735, 345)),
    "gap": None,
    "odds": (960, 120),
}
MYSTERY = {
    "box": (180 / 1614, 0, 1529 / 1614, 1),
    "tip": (730, 330),
    "dir": (1, -0.15),
    "render": "diamond",
    "sil": (1530, 570),
    "sil_h": 700,
    "q": (1530, 550),
    "bang": (1820, 210),
}
SMASH = {"box": (132 / 1614, 0, 1481 / 1614, 1), "text": "SMASH!", "at": (430, 150), "sub": None, "sub_at": (0, 0)}
COLLECTION = {"box": (132 / 1614, 0, 1481 / 1614, 1), "income": "$540M/s", "at": (1130, 120)}

OUTPUTS = [
    ("icon", icon),
    ("thumb-1", thumb_arc),
    ("thumb-2", thumb_mystery),
    ("thumb-3", thumb_smash),
    ("thumb-4", thumb_collection),
]


def sheet(images, refs_dir):
    """Cette methode permet d'assembler la planche de controle (nos images) et, si `refs_dir` est donne, la comparaison
    cote a cote avec les icones et vignettes des references 01 / 02 / 09 lorsque la composition est finie."""
    row_h = 216

    def row(icon_img, thumbs, label):
        """Cette methode permet d'aligner une icone et ses vignettes sur une rangee etiquetee lorsque l'on monte une
        planche."""
        cells = [icon_img.convert("RGB").resize((row_h, row_h), Image.LANCZOS)]
        cells += [t.convert("RGB").resize((384, row_h), Image.LANCZOS) for t in thumbs[:4]]
        w = 150 + sum(c.width for c in cells) + 10 * len(cells)
        out = Image.new("RGB", (w, row_h), (24, 26, 32))
        d = ImageDraw.Draw(out)
        d.text((10, row_h // 2 - 20), label, font=font(30), fill=WHITE)
        x = 150
        for c in cells:
            out.paste(c, (x, 0))
            x += c.width + 10
        return out

    ours = row(images["icon"], [images[k] for k in ("thumb-1", "thumb-2", "thumb-3", "thumb-4")], "FAD")
    os.makedirs(EXPORT, exist_ok=True)
    ours.save(os.path.join(EXPORT, "planche.jpg"), quality=88)
    if not refs_dir:
        return
    rows = []
    for label, place in zip(("01", "02", "09"), REF_PLACES):
        ic = Image.open(os.path.join(refs_dir, f"{place}_icon.png"))
        th = [Image.open(p) for p in sorted(glob.glob(os.path.join(refs_dir, f"{place}_thumb*.png")))]
        rows.append(row(ic, th, label))
    rows.append(ours)
    w = max(r.width for r in rows)
    out = Image.new("RGB", (w, sum(r.height + 10 for r in rows)), (24, 26, 32))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + 10
    os.makedirs(os.path.dirname(COMPARE), exist_ok=True)
    out.save(COMPARE, quality=85)
    print("comparaison :", COMPARE)


def main():
    """Cette methode permet de composer toutes les images (et la planche) lorsque le script est lance."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--refs", help="dossier des icones et vignettes des references")
    parser.add_argument("only", nargs="*", help="images a composer (toutes par defaut)")
    args = parser.parse_args()
    unknown = [name for name in args.only if name not in dict(OUTPUTS)]
    if unknown:
        parser.error("image inconnue : " + ", ".join(unknown) + " (connues : " + ", ".join(dict(OUTPUTS)) + ")")
    os.makedirs(EXPORT, exist_ok=True)
    images = {}
    for name, build in OUTPUTS:
        path = os.path.join(EXPORT, name + ".png")
        if args.only and name not in args.only:
            if os.path.exists(path):
                images[name] = Image.open(path)
            continue
        img = build().convert("RGB")
        img.save(path, optimize=True)
        images[name] = img
        print(name, img.size, path)
    if len(images) == len(OUTPUTS):
        sheet(images, args.refs)
    else:
        missing = [name for name, _ in OUTPUTS if name not in images]
        print("planche et comparaison non refaites : images manquantes (" + ", ".join(missing) + ")")


if __name__ == "__main__":
    main()
