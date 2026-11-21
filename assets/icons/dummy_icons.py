# Icones des mannequins de collection dans la barre d'outils (#66) : une icone carree par mannequin, tiree de son
# apercu trois-quarts (assets/dummy/export/collection/<id>.png, rendu par build_collection.py, effets compris),
# recadree au plus pres, centree, puis contouree de noir comme les autres icones (build_icons.outline).
# Usage : blender -b --factory-startup --python assets/icons/dummy_icons.py
# Sortie : assets/icons/export/dummy_<id>.png (256 x 256) et assets/icons/export/dummy_sheet.png (planche de controle).
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_icons as bi  # noqa: E402

RENDERS = os.path.join(HERE, "..", "dummy", "export", "collection")
BUST = 0.62  # part de la hauteur gardee depuis le haut (tete aux hanches), sauf modele plus large que haut


def pixels(image):
    """Cette methode permet de lire les pixels d'une image Blender en tableau (lignes, colonnes, RGBA) lorsque l'on
    la retravaille."""
    w, h = image.size
    return np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)


def square_crop(px):
    """Cette methode permet de recadrer un rendu sur le haut de ses pixels visibles (buste large : tete, tenue, effets)
    puis de le centrer dans un carre transparent lorsque l'on prepare une icone lisible a 60 px."""
    ys, xs = np.nonzero(px[:, :, 3] > 0.02)
    top, bottom = ys.max(), ys.min()  # pixels Blender : ligne 0 en bas
    height = top - bottom + 1
    keep = int(max(xs.max() - xs.min() + 1, height * BUST))
    crop = px[max(bottom, top + 1 - keep) : top + 1, xs.min() : xs.max() + 1]
    h, w = crop.shape[:2]
    side = max(h, w)
    out = np.zeros((side, side, 4), dtype=np.float32)
    y0, x0 = (side - h) // 2, (side - w) // 2
    out[y0 : y0 + h, x0 : x0 + w] = crop
    return out


def resized(px, size):
    """Cette methode permet de redimensionner un carre de pixels (couleurs premultipliees pour eviter les franges
    sombres) lorsque l'on le pose dans le canevas de l'icone."""
    side = px.shape[0]
    pre = px.copy()
    pre[:, :, :3] *= pre[:, :, 3:4]
    img = bpy.data.images.new("tmp", side, side, alpha=True, float_buffer=True)
    img.pixels = pre.ravel()
    img.scale(size, size)
    out = pixels(img)
    bpy.data.images.remove(img)
    safe = np.where(out[:, :, 3:4] > 1e-4, out[:, :, 3:4], 1)
    out[:, :, :3] /= safe
    return out


def make_icon(dummy_id):
    """Cette methode permet d'ecrire l'icone d'un mannequin (apercu recadre, marge, contour noir) lorsque le script
    la traite ; renvoie ses pixels 256 x 256."""
    src = bpy.data.images.load(os.path.join(RENDERS, dummy_id + ".png"))
    square = square_crop(pixels(src))
    bpy.data.images.remove(src)
    full = bi.SIZE * 2
    inner = int(full * (1 - 2 * bi.MARGIN - 2 * bi.OUTLINE / bi.SIZE))
    canvas = np.zeros((full, full, 4), dtype=np.float32)
    off = (full - inner) // 2
    canvas[off : off + inner, off : off + inner] = resized(square, inner)
    path = os.path.join(bi.EXPORT, "dummy_" + dummy_id + ".png")
    img = bpy.data.images.new("raw", full, full, alpha=True)
    img.pixels = canvas.ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return bi.outline(path)


def main():
    """Cette methode permet de produire les icones de tous les mannequins qui ont un apercu, puis leur planche, lorsque
    le script est lance."""
    os.makedirs(bi.EXPORT, exist_ok=True)
    ids = sorted(f[:-4] for f in os.listdir(RENDERS) if f.endswith(".png"))
    tiles = [make_icon(i) for i in ids]
    bi.write_sheet(tiles, "dummy_sheet.png")
    print("[dummy_icons]", len(ids), "icones", bi.EXPORT)


main()
