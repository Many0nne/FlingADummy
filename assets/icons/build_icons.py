# Icones d'interface dessinees en couleur (style des jeux de reference : objet 3D sature, contour noir epais) :
# boutique (cadeau), index (livre), mannequins (buste du mannequin de crash-test), puissance (biceps), argent (liasse),
# fleche d'objectif (triangle jaune).
# Rend chaque icone sur fond transparent puis ajoute le contour noir par dilatation de l'alpha.
# Usage : blender -b --factory-startup --python assets/icons/build_icons.py [-- nom1 nom2]
# Sortie : assets/icons/export/<nom>.png (256 x 256) et assets/icons/export/sheet.png (planche de controle).
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = os.path.join(HERE, "export")
DUMMY_BLEND = os.path.join(HERE, "..", "dummy", "dummy.blend")
SIZE = 256
OUTLINE = 9  # epaisseur du contour noir (px a 256)
MARGIN = 0.06  # marge autour de l'objet, en fraction de l'image


def srgb(hex_color):
    """Cette methode permet de convertir une couleur sRGB hexadecimale en couleur lineaire Blender lorsque l'on cree un
    materiau."""
    h = hex_color.lstrip("#")
    out = []
    for i in range(3):
        c = int(h[i * 2 : i * 2 + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def reset():
    """Cette methode permet de repartir d'une scene vide (reglages d'usine) lorsque l'on commence une icone."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, roughness=0.35, emission=0.0):
    """Cette methode permet de creer un materiau uni brillant lorsque l'on modelise une piece d'icone."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = srgb(color)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = srgb(color)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def box(size, location, mat, bevel=0.08, rotation=(0, 0, 0)):
    """Cette methode permet de creer un pave aux aretes adoucies lorsque l'on modelise une icone."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = "NONE"
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def parent_all(objs, rotation):
    """Cette methode permet de tourner un groupe d'objets d'un bloc (pivot a l'origine) lorsque l'icone est assemblee."""
    bpy.ops.object.empty_add(location=(0, 0, 0))
    root = bpy.context.active_object
    for o in objs:
        o.parent = root
    root.rotation_euler = rotation
    return root


def build_book():
    """Cette methode permet de modeliser le livre bleu de l'index (couverture, tranche blanche, etiquette) lorsque
    l'icone index est rendue."""
    blue = material("Cover", "#2F7BFF")
    dark = material("Spine", "#1C4FC4")
    pages = material("Pages", "#F4F1E6", roughness=0.6)
    gold = material("Label", "#FFD23C")
    objs = [
        box((1.5, 0.12, 2.0), (0.05, -0.36, 0), blue, 0.05),
        box((1.5, 0.12, 2.0), (0.05, 0.36, 0), blue, 0.05),
        box((0.16, 0.84, 2.0), (-0.68, 0, 0), dark, 0.07),
        box((1.4, 0.62, 1.86), (0.08, 0, 0), pages, 0.03),
        box((0.9, 0.04, 0.32), (0.12, -0.43, 0.45), gold, 0.03),
        box((0.9, 0.04, 0.1), (0.12, -0.43, -0.05), gold, 0.02),
    ]
    parent_all(objs, (math.radians(8), math.radians(-14), math.radians(-28)))


def build_gift():
    """Cette methode permet de modeliser le cadeau rose de la boutique (boite, couvercle, ruban, noeud) lorsque l'icone
    boutique est rendue."""
    pink = material("Box", "#FF3C8C")
    lid = material("Lid", "#FF5AA0")
    ribbon = material("Ribbon", "#FFD23C", roughness=0.25)
    objs = [
        box((1.6, 1.6, 1.25), (0, 0, -0.35), pink, 0.06),
        box((1.8, 1.8, 0.42), (0, 0, 0.45), lid, 0.06),
        box((0.36, 1.66, 1.3), (0, 0, -0.35), ribbon, 0.03),
        box((1.66, 0.36, 1.3), (0, 0, -0.35), ribbon, 0.03),
        box((0.38, 1.86, 0.48), (0, 0, 0.45), ribbon, 0.03),
        box((1.86, 0.38, 0.48), (0, 0, 0.45), ribbon, 0.03),
    ]
    for side in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.42,
            minor_radius=0.14,
            location=(side * 0.4, 0, 0.98),
            rotation=(math.radians(90), math.radians(side * 28), 0),
        )
        loop = bpy.context.active_object
        loop.scale = (1, 0.7, 1)
        loop.data.materials.append(ribbon)
        for poly in loop.data.polygons:
            poly.use_smooth = True
        objs.append(loop)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, 0.8))
    knot = bpy.context.active_object
    knot.data.materials.append(ribbon)
    for poly in knot.data.polygons:
        poly.use_smooth = True
    objs.append(knot)
    parent_all(objs, (math.radians(18), 0, math.radians(32)))


def build_cash():
    """Cette methode permet de modeliser la liasse de billets verts (billets empiles, bande de papier) lorsque l'icone
    argent est rendue."""
    green = material("Bill", "#3FC24A")
    light = material("Face", "#8CE87A")
    band = material("Band", "#F4F1E6", roughness=0.6)
    objs = []
    for i in range(3):
        z = -0.5 + i * 0.42
        rot = (0, 0, math.radians((i - 1) * 6))
        objs.append(box((2.2, 1.15, 0.36), (0, 0, z), green, 0.05, rot))
        objs.append(box((1.6, 0.72, 0.02), (0, 0, z + 0.185), light, 0.0, rot))
    objs.append(box((0.42, 1.22, 1.3), (0, 0, -0.08), band, 0.03))
    parent_all(objs, (math.radians(30), 0, math.radians(-22)))


def build_biceps():
    """Cette methode permet de modeliser un bras plie qui montre son biceps (metaballes jaunes) lorsque l'icone de
    puissance est rendue."""
    yellow = material("Skin", "#FFC83C", roughness=0.3)
    mb = bpy.data.metaballs.new("Arm")
    mb.resolution = 0.04
    mb.render_resolution = 0.03
    mb.threshold = 0.45
    obj = bpy.data.objects.new("Arm", mb)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(yellow)

    def ball(co, radius, kind="BALL", size=None, rotation=None):
        """Cette methode permet d'ajouter une metaballe au bras lorsque l'on assemble le biceps."""
        el = mb.elements.new(type=kind)
        el.co = co
        el.radius = radius
        el.stiffness = 1.6
        if size:
            el.size_x, el.size_y, el.size_z = size
        if rotation:
            el.rotation = rotation

    from mathutils import Euler

    # Bras horizontal (epaule a gauche), avant-bras dresse, poing en haut, biceps bombe
    ball((-0.75, 0, -0.7), 0.5, "CAPSULE", (0.6, 0, 0))
    ball((-0.4, 0, -0.25), 0.75)
    ball((0.45, 0, -0.6), 0.55)
    ball((0.5, 0, 0.2), 0.52, "CAPSULE", (0.45, 0, 0), Euler((0, math.radians(-100), 0)).to_quaternion())
    ball((0.4, 0, 1.05), 0.85)
    ball((0.0, 0, 1.0), 0.45)
    obj.location = (0, 0, 0)


def build_dummy():
    """Cette methode permet de reprendre le mannequin de dummy.blend en buste de trois quarts lorsque l'icone mannequins
    est rendue."""
    with bpy.data.libraries.load(DUMMY_BLEND, link=False) as (src, dst):
        dst.objects = [name for name in src.objects]
    keep = {"Head", "Torso", "LeftUpperArm", "RightUpperArm", "Helmet"}
    objs = []
    for obj in dst.objects:
        if obj is None or obj.type != "MESH":
            continue
        if obj.name.split(".")[0] in keep:
            bpy.context.collection.objects.link(obj)
            obj.parent = None
            objs.append(obj)
    # Le gabarit garde ses positions : centrer sur le haut du corps
    parent_all(objs, (0, 0, math.radians(180 - 28)))


def build_arrow():
    """Cette methode permet de modeliser le triangle jaune pointe en bas qui designe la cible de l'objectif (prisme
    aux aretes adoucies) lorsque l'icone fleche est rendue."""
    yellow = material("Arrow", "#FFD23C", roughness=0.3)
    bpy.ops.mesh.primitive_cylinder_add(vertices=3, radius=1.0, depth=0.45, rotation=(math.radians(90), 0, 0))
    obj = bpy.context.active_object
    # Le premier sommet est sur +Y (haut apres le quart de tour en X) : un demi-tour en Y le met en bas
    obj.rotation_euler = (math.radians(90), math.radians(180), 0)
    bpy.ops.object.transform_apply(rotation=True)
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.14
    mod.segments = 5
    mod.limit_method = "NONE"
    obj.data.materials.append(yellow)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.rotation_euler = (math.radians(-12), 0, 0)


ICONS = {
    "shop": build_gift,
    "index": build_book,
    "dummies": build_dummy,
    "power": build_biceps,
    "cash": build_cash,
    "arrow": build_arrow,
}


def setup_render():
    """Cette methode permet de regler le rendu (Eevee, fond transparent, couleurs non filmiques, soleil et ciel clairs)
    lorsque l'icone est prete a rendre."""
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = SIZE * 2
    scene.render.resolution_y = SIZE * 2
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.75, 0.8, 0.9, 1)
    bg.inputs["Strength"].default_value = 0.9
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(40), math.radians(-25), math.radians(-30)))
    bpy.context.active_object.data.energy = 3.2


def frame_camera():
    """Cette methode permet de placer une camera orthographique de face qui cadre tous les objets visibles avec une
    marge lorsque l'icone est assemblee."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in bpy.context.scene.objects:
        if obj.type not in {"MESH", "META"}:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        points += [evaluated.matrix_world @ v.co for v in mesh.vertices]
        evaluated.to_mesh_clear()
    xs = [p.x for p in points]
    zs = [p.z for p in points]
    cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
    extent = max(max(xs) - min(xs), max(zs) - min(zs))
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = extent / (1 - 2 * MARGIN - 2 * OUTLINE / SIZE)
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (cx, -20, cz)
    cam.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.scene.camera = cam


def outline(path):
    """Cette methode permet d'ajouter le contour noir (dilatation de l'alpha) et de reduire a 256 px lorsque le rendu
    brut est ecrit."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    # Reduction 2x (moyenne 2 x 2, couleurs premultipliees)
    rgb = px[:, :, :3] * px[:, :, 3:4]
    rgb = rgb.reshape(h // 2, 2, w // 2, 2, 3).mean(axis=(1, 3))
    alpha = px[:, :, 3].reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3))
    n = h // 2
    grown = alpha.copy()
    r = OUTLINE
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d = math.hypot(dx, dy)
            if d > r + 0.5:
                continue
            weight = min(1.0, r + 0.5 - d)
            shifted = np.zeros_like(alpha)
            ys = slice(max(0, dy), n + min(0, dy))
            yd = slice(max(0, -dy), n + min(0, -dy))
            xs = slice(max(0, dx), n + min(0, dx))
            xd = slice(max(0, -dx), n + min(0, -dx))
            shifted[ys, xs] = alpha[yd, xd] * weight
            grown = np.maximum(grown, shifted)
    ink = np.array([0.08, 0.08, 0.1], dtype=np.float32)  # pixels PNG 8 bits : valeurs sRGB
    out_rgb = rgb + ink * (grown - alpha)[:, :, None]
    out_alpha = grown
    safe = np.where(out_alpha > 1e-4, out_alpha, 1)[:, :, None]
    out = np.concatenate([out_rgb / safe, out_alpha[:, :, None]], axis=2)
    result = bpy.data.images.new(os.path.basename(path), n, n, alpha=True)
    result.pixels = out.ravel()
    result.filepath_raw = path
    result.file_format = "PNG"
    result.save()
    return out


def render_icon(name):
    """Cette methode permet de construire, rendre et contourer une icone lorsque le script la traite."""
    reset()
    ICONS[name]()
    setup_render()
    frame_camera()
    path = os.path.join(EXPORT, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return outline(path)


def write_sheet(tiles):
    """Cette methode permet d'assembler les icones sur fond vert (controle visuel) lorsque toutes sont rendues."""
    n = SIZE
    sheet = np.zeros((n, n * len(tiles), 4), dtype=np.float32)
    sheet[:, :] = (0.45, 0.85, 0.3, 1)  # vert des decors de reference
    for i, tile in enumerate(tiles):
        a = tile[:, :, 3:4]
        region = sheet[:, i * n : (i + 1) * n, :3]
        sheet[:, i * n : (i + 1) * n, :3] = region * (1 - a) + tile[:, :, :3] * a
    img = bpy.data.images.new("sheet", n * len(tiles), n, alpha=True)
    img.pixels = sheet.ravel()
    img.filepath_raw = os.path.join(EXPORT, "sheet.png")
    img.file_format = "PNG"
    img.save()


def main():
    """Cette methode permet de rendre les icones demandees (toutes par defaut) lorsque le script est lance."""
    os.makedirs(EXPORT, exist_ok=True)
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    names = args or list(ICONS)
    tiles = [render_icon(name) for name in names]
    if not args:
        write_sheet(tiles)


main()
