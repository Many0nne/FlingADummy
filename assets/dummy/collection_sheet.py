# Planche des mannequins de collection (#66) : une ligne par rarete, carte par mannequin (« 1 IN N », rendu, nom,
# revenu, id), a partir de src/shared/Collection.luau et des apercus de build_collection.py. Avec --ref, colle a
# droite une planche de reference (jeu 09) a la meme hauteur, pour la comparaison cote a cote de la PR.
# Usage : python -I assets/dummy/collection_sheet.py <planche.png> [--ref <image>]
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "src", "shared", "Collection.luau")
RENDERS = os.path.join(HERE, "export", "collection")
RARITIES = [
    ("Common", (235, 235, 235)),
    ("Uncommon", (90, 220, 90)),
    ("Rare", (70, 160, 255)),
    ("Epic", (190, 90, 255)),
    ("Legendary", (255, 190, 40)),
    ("Mythic", (255, 70, 110)),
    ("Secret", (110, 255, 225)),
]


def parse(path):
    """Cette methode permet de lire id, nom, rarete, revenu et « 1 en n » du catalogue lorsque la planche se prepare."""
    block = open(path, encoding="utf-8").read().split("Collection.DUMMIES = {")[1].split("} :: { Dummy }")[0]
    pat = r'id = "(\w+)",\s*name = "([^"]+)",\s*rarity = (\d+),\s*income = (\d+),\s*n = (\d+)'
    return [(i, nm, int(r), int(inc), int(n)) for i, nm, r, inc, n in re.findall(pat, block)]


def short(v):
    """Cette methode permet d'abreger un nombre (12K, 2M) lorsque l'on l'affiche sur une carte."""
    for div, suf in ((1_000_000, "M"), (1_000, "K")):
        if v >= div:
            return f"{v / div:g}{suf}"
    return str(v)


def font(size, bold=True):
    """Cette methode permet de charger une police Windows lorsque l'on ecrit sur la planche."""
    for name in (("arialbd.ttf" if bold else "arial.ttf"), "segoeuib.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def build():
    """Cette methode permet de dessiner la planche (titre, lignes de rarete, cartes) lorsque le script est lance ;
    renvoie l'image."""
    dummies = parse(SRC)
    cw, ch, img_h, pad, label_w = 230, 330, 260, 14, 170
    cols = 3
    w = label_w + cols * (cw + pad) + pad
    h = len(RARITIES) * (ch + pad) + pad + 60
    sheet = Image.new("RGB", (w, h), (28, 30, 40))
    dr = ImageDraw.Draw(sheet)
    dr.text((pad, 16), f"Fling a Dummy : les {len(dummies)} mannequins de collection", font=font(30), fill="white")
    for row, (rname, rcol) in enumerate(RARITIES):
        y = 60 + pad + row * (ch + pad)
        dr.rounded_rectangle((pad, y, label_w - 4, y + ch), 14, fill=tuple(c // 3 for c in rcol), outline=rcol,
                             width=3)
        dr.text((pad + 14, y + ch // 2 - 14), rname, font=font(24), fill=rcol)
        for col, (did, name, _, inc, n) in enumerate(d for d in dummies if d[2] == row + 1):
            x = label_w + pad + col * (cw + pad)
            dr.rounded_rectangle((x, y, x + cw, y + ch), 14, fill=(44, 47, 60), outline=rcol, width=3)
            im = Image.open(os.path.join(RENDERS, f"{did}.png")).convert("RGBA")
            im.thumbnail((cw - 10, img_h))
            sheet.paste(im, (x + (cw - im.width) // 2, y + 6), im)
            dr.text((x + 10, y + 8), f"1 IN {short(n)}", font=font(16), fill="white")
            f = font(19)
            tw = dr.textlength(name, font=f)
            dr.text((x + (cw - tw) / 2, y + img_h + 12), name, font=f, fill="white")
            sub = f"${short(inc)}/s   id: {did}"
            fs = font(15, bold=False)
            tw = dr.textlength(sub, font=fs)
            dr.text((x + (cw - tw) / 2, y + img_h + 40), sub, font=fs, fill=(190, 200, 210))
    return sheet


def main():
    """Cette methode permet d'ecrire la planche (et la comparaison avec la reference si --ref) lorsque le script est
    lance."""
    out = sys.argv[1]
    sheet = build()
    if "--ref" in sys.argv:
        ref = Image.open(sys.argv[sys.argv.index("--ref") + 1]).convert("RGB")
        ref = ref.resize((int(ref.width * sheet.height / ref.height), sheet.height))
        both = Image.new("RGB", (sheet.width + ref.width + 20, sheet.height), (28, 30, 40))
        both.paste(sheet, (0, 0))
        both.paste(ref, (sheet.width + 20, 0))
        sheet = both
    sheet.save(out)
    print("planche", out, sheet.size)


main()
