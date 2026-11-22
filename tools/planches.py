# Planches de reference (#121) : range les captures Studio des prises de vue (Shared.PlanchePlan) puis assemble les
# planches docs/planches/<planche>.jpg a partir du manifeste docs/planches/manifest.json (tools/planches-manifest.luau).
# Procedure complete (reservation Studio, prises, captures) : docs/planches/README.md.
#
# Usage, depuis la racine du worktree :
#   python -I tools/planches.py shots [planche...]        liste des prises, dans l'ordre ou les capturer
#   python -I tools/planches.py grab <prise>              derniere capture MCP -> <prise>.png (reprise d'une prise)
#   python -I tools/planches.py collect [planche...]      les N dernieres captures MCP -> prises des planches, dans l'ordre
#                                                         (exactement les planches photographiees pendant la seance)
#   python -I tools/planches.py build [planche...]        assemble les planches (toutes par defaut)
# Options : --captures <dossier> (captures MCP, defaut %LOCALAPPDATA%\Roblox\tmp-capture-storage),
#           --work <dossier> (prises rangees, defaut %TEMP%\fad-planches)
import datetime
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "planches")
MANIFEST = os.path.join(OUT, "manifest.json")
CAPTURES = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Roblox", "tmp-capture-storage")
WORK = os.path.join(os.environ.get("TEMP", "/tmp"), "fad-planches")

WIDTH = 1600  # largeur des planches
PAD = 12
BG = (28, 30, 40)
CARD = (44, 47, 60)
MUTED = (190, 200, 210)
MAX_BYTES = 1_000_000  # une planche reste sous 1 Mo (qualite JPEG baissee au besoin)
STATION_ASPECT = 4 / 3  # recadrage des prises de l'appareil (centre de l'image)
MAX_SESSION = 2 * 3600  # s entre la premiere et la derniere capture d'une seance, au-dela : signale
TOP_CROP = 0.07  # bandeau du haut retire des prises de base (boutons de Roblox en haut a gauche)


def font(size, bold=True):
    """Cette methode permet de charger une police lorsque l'on ecrit sur une planche."""
    names = ["arialbd.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf"] if bold else ["arial.ttf", "segoeui.ttf",
                                                                                "DejaVuSans.ttf"]
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def load_manifest():
    """Cette methode permet de lire le manifeste lorsque l'on range ou assemble ; renvoie les planches par nom (ordre
    garde)."""
    with open(MANIFEST, encoding="utf-8") as f:
        data = json.load(f)
    return data, {sheet["name"]: sheet for sheet in data["sheets"]}


def selected(args, sheets):
    """Cette methode permet de donner les planches demandees (toutes si aucune) lorsqu'une commande les parcourt."""
    names = [a for a in args if not a.startswith("--")] or list(sheets)
    for name in names:
        if name not in sheets:
            sys.exit(f"planche inconnue : {name} (connues : {', '.join(sheets)})")
    return names


def option(args, flag, default):
    """Cette methode permet de lire une option « --flag valeur » lorsque la ligne de commande la donne."""
    if flag in args:
        i = args.index(flag)
        if i + 1 >= len(args):
            sys.exit(f"{flag} attend une valeur")
        value = args[i + 1]
        del args[i:i + 2]
        return value
    return default


def captures(folder):
    """Cette methode permet de lister les captures MCP (PNG, du plus ancien au plus recent) lorsque l'on les range."""
    files = []
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                if f.read(8) == b"\x89PNG\r\n\x1a\n":
                    files.append(path)
    return sorted(files, key=os.path.getmtime)


def cmd_shots(args):
    """Cette methode permet d'afficher les prises a capturer, dans l'ordre, lorsque l'on prepare la seance Studio."""
    _, sheets = load_manifest()
    for name in selected(args, sheets):
        for shot in sheets[name]["shots"]:
            print(shot["name"])


def cmd_grab(args, folder, work):
    """Cette methode permet de ranger la derniere capture MCP sous le nom d'une prise lorsque l'on refait une prise."""
    _, sheets = load_manifest()
    names = {shot["name"] for sheet in sheets.values() for shot in sheet["shots"]}
    if not args or args[0] not in names:
        sys.exit("usage : grab <prise> (prises : python -I tools/planches.py shots)")
    shot = args[0]
    files = captures(folder)
    if not files:
        sys.exit(f"aucune capture dans {folder}")
    os.makedirs(work, exist_ok=True)
    sheet = next(s for s in sheets.values() if any(x["name"] == shot for x in s["shots"]))
    others = [os.path.join(work, x["name"] + ".png") for x in sheet["shots"] if x["name"] != shot]
    sizes = {Image.open(p).size for p in others if os.path.isfile(p)}
    if sizes and Image.open(files[-1]).size not in sizes:
        sys.exit(f"capture de taille {Image.open(files[-1]).size}, les autres prises de la planche : {sizes} "
                 "(fenetre de Studio redimensionnee ?)")
    shutil.copy2(files[-1], os.path.join(work, shot + ".png"))
    print(f"{shot} <- {os.path.basename(files[-1])}")


def cmd_collect(args, folder, work):
    """Cette methode permet de ranger les N dernieres captures MCP sous les noms des N prises des planches demandees,
    dans l'ordre, lorsque la seance Studio est finie : les planches demandees sont celles photographiees pendant la
    seance, sans reprise (une prise ratee se refait apres, avec grab)."""
    _, sheets = load_manifest()
    shots = [shot["name"] for name in selected(args, sheets) for shot in sheets[name]["shots"]]
    files = captures(folder)
    if len(files) < len(shots):
        sys.exit(f"{len(shots)} prises attendues, {len(files)} captures dans {folder}")
    files = files[-len(shots):]
    span = os.path.getmtime(files[-1]) - os.path.getmtime(files[0])
    if span > MAX_SESSION:
        print(f"ATTENTION : {span / 3600:.1f} h entre la premiere et la derniere capture : une capture manque-t-elle ? "
              "(des captures d'une seance precedente seraient prises a sa place)")
    sizes = {Image.open(f).size for f in files}
    if len(sizes) > 1:
        sys.exit(f"captures de tailles differentes {sizes} : une capture en trop ou fenetre redimensionnee ? "
                 "Refaire les prises en cause avec « grab ».")
    os.makedirs(work, exist_ok=True)
    for shot, path in zip(shots, files):
        shutil.copy2(path, os.path.join(work, shot + ".png"))
        print(f"{shot} <- {os.path.basename(path)}")


def shot_image(work, name):
    """Cette methode permet d'ouvrir la capture rangee d'une prise lorsque l'on assemble une planche."""
    path = os.path.join(work, name + ".png")
    if not os.path.isfile(path):
        sys.exit(f"capture manquante : {path} (collect ou grab)")
    return Image.open(path).convert("RGB")


def cells(image, count, row, cell):
    """Cette methode permet de decouper une prise « row » en ses cases (ROW cases egales sur toute la largeur, centrees
    en hauteur) lorsque l'on assemble une planche de mannequins ; renvoie les `count` premieres."""
    w, h = image.size
    cw = w / row
    ch = min(h, cw * cell[1] / cell[0])
    top = (h - ch) / 2
    return [image.crop((round(i * cw), round(top), round((i + 1) * cw), round(top + ch))) for i in range(count)]


def centered(draw, x, width, y, text, fnt, fill):
    """Cette methode permet d'ecrire un texte centre (raccourci s'il deborde) lorsque l'on legende une case."""
    while draw.textlength(text, font=fnt) > width - 8 and len(text) > 3:
        text = text[:-2] + "…"
    tw = draw.textlength(text, font=fnt)
    draw.text((x + (width - tw) / 2, y), text, font=fnt, fill=fill)


def captured_on(sheet, work):
    """Cette methode permet de donner la date de la capture la plus recente d'une planche lorsque l'on l'assemble."""
    for shot in sheet["shots"]:
        shot_image(work, shot["name"])  # capture manquante : message clair avant la lecture des dates
    newest = max(os.path.getmtime(os.path.join(work, shot["name"] + ".png")) for shot in sheet["shots"])
    return datetime.date.fromtimestamp(newest).isoformat()


def header(draw, title, count, date):
    """Cette methode permet d'ecrire le titre d'une planche (nombre d'elements, date des captures) lorsque l'on
    l'assemble."""
    draw.text((PAD + 4, 14), f"Fling a Dummy : {title} ({count})", font=font(32), fill="white")
    stamp = f"captures Studio du {date} - docs/planches/README.md"
    fs = font(15, bold=False)
    draw.text((WIDTH - PAD - 4 - draw.textlength(stamp, font=fs), 26), stamp, font=fs, fill=MUTED)
    return 64


def hex_rgb(value):
    """Cette methode permet de convertir « #rrggbb » en triplet lorsque l'on colore une rangee."""
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def build_rows(sheet, data, work):
    """Cette methode permet d'assembler une planche de mannequins (une rangee par prise, bandeau de rarete a gauche
    pour la collection) lorsque l'on construit la collection ou les mannequins a lancer ; renvoie l'image."""
    row, cell = data["row"], data["cell"]
    grouped = any(shot.get("group") for shot in sheet["shots"])
    label_w = 150 if grouped else 0
    left = PAD + (label_w + PAD if grouped else 0)
    card_w = (WIDTH - left - PAD - (row - 1) * PAD) // row
    img_h = round(card_w * cell[1] / cell[0])
    text_h = 62
    row_h = img_h + text_h
    top = 64
    height = top + len(sheet["shots"]) * (row_h + PAD) + PAD
    out = Image.new("RGB", (WIDTH, height), BG)
    draw = ImageDraw.Draw(out)
    count = sum(len(shot["items"]) for shot in sheet["shots"])
    header(draw, sheet["title"], count, captured_on(sheet, work))
    for r, shot in enumerate(sheet["shots"]):
        y = top + PAD + r * (row_h + PAD)
        color = hex_rgb(shot["group"]["color"]) if shot.get("group") else (120, 130, 150)
        if grouped:
            draw.rounded_rectangle((PAD, y, PAD + label_w, y + row_h), 12, fill=tuple(c // 3 for c in color),
                                   outline=color, width=3)
            name = shot["group"]["name"]
            fnt = font(24)
            centered(draw, PAD, label_w, y + row_h // 2 - 26, name, fnt, color)
            centered(draw, PAD, label_w, y + row_h // 2 + 6, f"{len(shot['items'])} mannequins", font(15, False),
                     MUTED)
        image = shot_image(work, shot["name"])
        for i, (item, crop) in enumerate(zip(shot["items"], cells(image, len(shot["items"]), row, cell))):
            x = left + i * (card_w + PAD)
            draw.rounded_rectangle((x - 3, y - 3, x + card_w + 3, y + row_h + 3), 12, fill=CARD, outline=color,
                                   width=3)
            out.paste(crop.resize((card_w, img_h), Image.LANCZOS), (x, y))
            centered(draw, x, card_w, y + img_h + 8, item["title"], font(17), "white")
            centered(draw, x, card_w, y + img_h + 35, "   ".join(item["lines"]), font(16, False), MUTED)
    return out


def build_frames(sheet, work):
    """Cette methode permet d'assembler une planche de paliers (une vignette par prise, meme cadrage, legende dessous)
    lorsque l'on construit la base ou l'appareil d'entrainement ; renvoie l'image."""
    station = sheet["shots"][0]["framing"] == "station"
    cols = 3 if station else 2
    images = []
    for shot in sheet["shots"]:
        image = shot_image(work, shot["name"])
        w, h = image.size
        if station:
            cw = min(w, round(h * STATION_ASPECT))
            image = image.crop(((w - cw) // 2, 0, (w - cw) // 2 + cw, h))
        else:
            image = image.crop((0, round(h * TOP_CROP), w, h))
        images.append(image)
    tile_w = (WIDTH - PAD * (cols + 1)) // cols
    tile_h = round(tile_w * images[0].height / images[0].width)
    text_h = 64
    top = 64
    rows = (len(images) + cols - 1) // cols
    out = Image.new("RGB", (WIDTH, top + rows * (tile_h + text_h + PAD) + PAD), BG)
    draw = ImageDraw.Draw(out)
    header(draw, sheet["title"], len(images), captured_on(sheet, work))
    for i, (shot, image) in enumerate(zip(sheet["shots"], images)):
        item = shot["items"][0]
        x = PAD + (i % cols) * (tile_w + PAD)
        y = top + PAD + (i // cols) * (tile_h + text_h + PAD)
        draw.rounded_rectangle((x - 3, y - 3, x + tile_w + 3, y + tile_h + text_h + 3), 12, fill=CARD)
        out.paste(image.resize((tile_w, tile_h), Image.LANCZOS), (x, y))
        centered(draw, x, tile_w, y + tile_h + 8, item["title"], font(21), "white")
        centered(draw, x, tile_w, y + tile_h + 37, "   ".join(item["lines"]), font(16, False), MUTED)
    return out


def save(image, path):
    """Cette methode permet d'ecrire une planche en JPEG sous MAX_BYTES (qualite baissee au besoin) lorsqu'elle est
    assemblee ; renvoie la qualite retenue."""
    for quality in range(90, 49, -5):
        image.save(path, "JPEG", quality=quality, optimize=True, progressive=True)
        if os.path.getsize(path) <= MAX_BYTES:
            return quality
    print(f"ATTENTION : {path} depasse {MAX_BYTES // 1000} Ko meme en qualite {quality} (reduire la planche)")
    return quality


def cmd_build(args, work):
    """Cette methode permet d'assembler les planches demandees dans docs/planches/ lorsque les prises sont rangees."""
    data, sheets = load_manifest()
    for name in selected(args, sheets):
        sheet = sheets[name]
        image = build_rows(sheet, data, work) if sheet["shots"][0]["framing"] == "row" else build_frames(sheet, work)
        path = os.path.join(OUT, name + ".jpg")
        quality = save(image, path)
        print(f"{path} {image.size[0]}x{image.size[1]} q{quality} {os.path.getsize(path) // 1024} Ko")


def main():
    """Cette methode permet d'aiguiller la commande (shots, grab, collect, build) lorsque le script est lance."""
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__ or "usage : python -I tools/planches.py shots|grab|collect|build [planche...]")
    command = args.pop(0)
    folder = option(args, "--captures", CAPTURES)
    work = option(args, "--work", WORK)
    if command == "shots":
        cmd_shots(args)
    elif command == "grab":
        cmd_grab(args, folder, work)
    elif command == "collect":
        cmd_collect(args, folder, work)
    elif command == "build":
        cmd_build(args, work)
    else:
        sys.exit(f"commande inconnue : {command}")


main()
