# Icones d'interface dessinees en couleur (style des jeux de reference : objet 3D sature, contour noir epais) :
# boutique (cadeau), index (livre), mannequins (buste du mannequin de crash-test), puissance (biceps), argent (liasse),
# fleche d'objectif (triangle jaune), musique (double croche violette), raretes (rarity1 a rarity11 : buste du
# mannequin a la couleur de la rarete, icones des mannequins dans la barre d'outils).
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


def build_music():
    """Cette methode permet de modeliser la double croche violette du bouton musique (deux tetes ovales penchees,
    hampes et barre) lorsque l'icone musique est rendue."""
    purple = material("Note", "#A24BFF", roughness=0.3)
    objs = []
    for x in (-0.55, 0.65):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.4, location=(x, 0, -0.85), segments=32, ring_count=16)
        head = bpy.context.active_object
        head.scale = (1.25, 0.6, 0.9)
        head.rotation_euler = (0, math.radians(25), 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        head.data.materials.append(purple)
        for poly in head.data.polygons:
            poly.use_smooth = True
        objs.append(head)
    objs.append(box((0.18, 0.3, 1.75), (-0.17, 0, 0.0), purple, 0.06))
    objs.append(box((0.18, 0.3, 1.75), (1.03, 0, 0.18), purple, 0.06))
    objs.append(box((1.38, 0.3, 0.36), (0.43, 0, 0.92), purple, 0.08, rotation=(0, math.radians(-8.5), 0)))
    parent_all(objs, (0, 0, math.radians(-10)))


def sphere(location, radius, mat, scale=(1, 1, 1), rotation=(0, 0, 0)):
    """Cette methode permet de creer une sphere lisse (eventuellement aplatie) lorsque l'on modelise une icone."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=32, ring_count=16)
    obj = bpy.context.active_object
    obj.scale = scale
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def cylinder(location, radius, depth, mat, rotation=(0, 0, 0), vertices=32, bevel=0.0, radius2=None):
    """Cette methode permet de creer un cylindre ou un cone (si radius2 est donne) lorsque l'on modelise une icone."""
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    else:
        bpy.ops.mesh.primitive_cone_add(
            vertices=vertices, radius1=radius, radius2=radius2, depth=depth, location=location
        )
    obj = bpy.context.active_object
    obj.location = location  # le cone ignore parfois le parametre de l'operateur
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(rotation=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = "NONE"
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def star(location, outer, thickness, mat, points=5):
    """Cette methode permet de creer une etoile epaisse face a la camera lorsque l'on modelise une icone."""
    verts = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else outer * 0.45
        a = math.pi / 2 + i * math.pi / points
        verts.append((r * math.cos(a), 0, r * math.sin(a)))
    mesh = bpy.data.meshes.new("Star")
    mesh.from_pydata(verts, [], [list(range(len(verts)))])
    obj = bpy.data.objects.new("Star", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    solid = obj.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 0
    bevel = obj.modifiers.new("Bevel", "BEVEL")
    bevel.width = thickness * 0.3
    bevel.segments = 3
    bevel.limit_method = "NONE"
    obj.data.materials.append(mat)
    return obj


def arc_beads(center, radius, start, end, mat, bead, count=22):
    """Cette methode permet de tracer un arc epais dans le plan XZ (chapelet de spheres) lorsque l'on modelise un
    arc-en-ciel ou des fleches circulaires ; renvoie les spheres."""
    out = []
    for i in range(count + 1):
        a = math.radians(start + (end - start) * i / count)
        out.append(sphere((center[0] + radius * math.cos(a), center[1], center[2] + radius * math.sin(a)), bead, mat))
    return out


def build_clover():
    """Cette methode permet de modeliser le trefle a quatre feuilles (feuilles en coeur arrondi, tige) lorsque l'icone
    chance est rendue."""
    green = material("Leaf", "#3FD64A")
    light = material("Vein", "#8DF27A")
    dark = material("Stem", "#1E9A38")
    objs = []
    for sx, sz in ((-1, 1), (1, 1), (-1, -1), (1, -1)):
        objs.append(sphere((sx * 0.52, 0, sz * 0.52), 0.62, green, (1, 0.4, 1)))
        objs.append(sphere((sx * 0.68, -0.12, sz * 0.7), 0.28, light, (1, 0.3, 1)))
    objs.append(sphere((0, 0, 0), 0.34, dark, (1, 0.5, 1)))
    objs.append(box((0.2, 0.2, 1.3), (0.55, 0, -1.45), dark, 0.06, (0, math.radians(35), 0)))
    parent_all(objs, (0, 0, math.radians(-8)))


def build_moneybag():
    """Cette methode permet de modeliser le sac d'argent (sac dore, col noue, signe dollar) lorsque l'icone argent
    des passes est rendue."""
    sack = material("Sack", "#E9A12E")
    tie = material("Tie", "#B8651B")
    mark = material("Dollar", "#2FB84A", emission=0.2)
    objs = [
        sphere((0, 0, -0.35), 1.15, sack, (1.0, 0.8, 0.95)),
        cylinder((0, 0, 0.78), 0.4, 0.55, sack, radius2=0.28),
        box((0.9, 0.5, 0.2), (0, 0, 0.55), tie, 0.07),
        sphere((-0.5, 0, 1.15), 0.34, sack, (1, 0.7, 1.15), (0, math.radians(-25), 0)),
        sphere((0.5, 0, 1.15), 0.34, sack, (1, 0.7, 1.15), (0, math.radians(25), 0)),
    ]
    bpy.ops.object.text_add(location=(0, -0.95, -0.35), rotation=(math.radians(90), 0, 0))
    text = bpy.context.active_object
    text.data.body = "$"
    text.data.size = 1.35
    text.data.extrude = 0.05
    text.data.align_x = "CENTER"
    text.data.align_y = "CENTER"
    text.data.materials.append(mark)
    objs.append(text)
    parent_all(objs, (math.radians(-6), 0, math.radians(8)))


def build_crown():
    """Cette methode permet de modeliser la couronne doree a trois pointes (bandeau, pointes, gemmes) lorsque l'icone
    VIP est rendue."""
    gold = material("Gold", "#FFC21E", roughness=0.25)
    red = material("Ruby", "#FF2E5B", roughness=0.15, emission=0.3)
    blue = material("Sapphire", "#2F8BFF", roughness=0.15, emission=0.3)
    objs = [box((2.3, 0.7, 0.6), (0, 0, -0.55), gold, 0.1)]
    for x, h in ((-0.95, 1.1), (0, 1.5), (0.95, 1.1)):
        objs.append(cylinder((x, 0, -0.25 + h / 2), 0.42, h, gold, vertices=4, radius2=0.05, bevel=0.04))
        objs.append(sphere((x, 0, -0.25 + h + 0.12), 0.2, red))
    objs.append(sphere((-0.5, -0.38, -0.55), 0.17, blue))
    objs.append(sphere((0.5, -0.38, -0.55), 0.17, blue))
    objs.append(sphere((0, -0.38, -0.55), 0.2, red))
    parent_all(objs, (math.radians(-6), 0, math.radians(-8)))


def build_house():
    """Cette methode permet de modeliser la maison (murs, toit rouge, porte, fenetre, cheminee) lorsque l'icone de la
    base agrandie est rendue."""
    wall = material("Wall", "#FFE2A0")
    roof = material("Roof", "#E8453C")
    door = material("Door", "#8A4B1F")
    glass = material("Window", "#6FD2FF", emission=0.3)
    objs = [
        box((1.9, 1.5, 1.4), (0, 0, -0.5), wall, 0.07),
        box((0.34, 0.34, 0.7), (0.65, 0, 0.95), roof, 0.05),
        box((0.5, 0.06, 0.85), (-0.4, -0.76, -0.78), door, 0.03),
        box((0.5, 0.06, 0.45), (0.45, -0.76, -0.4), glass, 0.03),
    ]
    bpy.ops.mesh.primitive_cylinder_add(vertices=3, radius=1.55, depth=1.7, rotation=(math.radians(90), 0, 0))
    top = bpy.context.active_object
    # Le premier sommet doit etre en haut (+Z) : le prisme est tourne autour de l'axe de l'extrusion (Y)
    top.rotation_euler = (math.radians(90), 0, math.radians(0))
    top.location = (0, 0, 0.45)
    top.scale = (1.0, 1.0, 0.62)
    bpy.ops.object.transform_apply(scale=True)
    mod = top.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.1
    mod.segments = 3
    mod.limit_method = "NONE"
    top.data.materials.append(roof)
    objs.append(top)
    parent_all(objs, (math.radians(8), 0, math.radians(-12)))


def build_rainbow():
    """Cette methode permet de modeliser l'arc-en-ciel (quatre bandes, deux nuages) lorsque l'icone du passe arc-en-ciel
    est rendue."""
    bands = ["#FF3B4F", "#FFC21E", "#3FD64A", "#2F8BFF"]
    white = material("Cloud", "#FFFFFF", roughness=0.7)
    for i, color in enumerate(bands):
        arc_beads((0, 0, -0.55), 1.55 - i * 0.33, 0, 180, material("Band%d" % i, color), 0.17, count=60)
    for x in (-1.3, 1.3):
        for dx, dz, r in ((-0.25, 0.0, 0.35), (0.0, 0.18, 0.42), (0.28, 0.0, 0.34)):
            sphere((x + dx * (1 if x > 0 else -1), -0.3, -0.62 + dz), r, white, (1, 0.7, 0.9))


def build_potion():
    """Cette methode permet de modeliser la potion (flacon rond, col, bouchon, bulles) lorsque l'icone des boosts est
    rendue."""
    liquid = material("Liquid", "#C04BFF", roughness=0.15, emission=0.25)
    glass = material("Glass", "#E8F4FF", roughness=0.1)
    cork = material("Cork", "#B8651B", roughness=0.7)
    foam = material("Foam", "#F0B8FF", roughness=0.2)
    objs = [
        sphere((0, 0, -0.45), 1.05, liquid),
        cylinder((0, 0, 0.55), 0.32, 0.8, glass, bevel=0.03),
        cylinder((0, 0, 1.08), 0.42, 0.18, glass, bevel=0.04),
        cylinder((0, 0, 1.38), 0.3, 0.5, cork, radius2=0.36, bevel=0.04),
        sphere((-0.35, -0.85, -0.2), 0.2, foam, (1, 0.5, 1)),
        sphere((0.3, -0.9, -0.7), 0.13, foam, (1, 0.5, 1)),
    ]
    parent_all(objs, (0, 0, math.radians(-12)))


def build_globe():
    """Cette methode permet de modeliser le globe (ocean bleu, continents verts, anneau) lorsque l'icone de la chance du
    serveur est rendue."""
    ocean = material("Ocean", "#2F8BFF", roughness=0.25)
    land = material("Land", "#3FD64A")
    ring = material("Ring", "#FFC21E", roughness=0.25)
    objs = [sphere((0, 0, 0), 1.25, ocean)]
    for x, z, sx, sz in ((-0.45, 0.35, 0.62, 0.5), (0.5, -0.2, 0.5, 0.7), (-0.2, -0.85, 0.4, 0.28), (0.55, 0.78, 0.3, 0.25)):
        # Taches aplaties qui affleurent la surface (profondeur du point sur la sphere)
        y = -math.sqrt(max(0.0, 1.25 ** 2 - x * x - z * z)) + 0.04
        objs.append(sphere((x, y, z), 1, land, (sx, 0.12, sz)))
    bpy.ops.mesh.primitive_torus_add(
        major_radius=1.5, minor_radius=0.06, rotation=(math.radians(70), 0, math.radians(-20))
    )
    band = bpy.context.active_object
    band.data.materials.append(ring)
    for poly in band.data.polygons:
        poly.use_smooth = True
    objs.append(band)
    parent_all(objs, (math.radians(-10), 0, math.radians(8)))


def build_dice():
    """Cette methode permet de modeliser le de (cube blanc arrondi, points violets sur trois faces) lorsque l'icone des
    lancers chanceux est rendue."""
    white = material("Die", "#F8F6FF", roughness=0.3)
    pip = material("Pip", "#6A2BD0", roughness=0.3)
    objs = [box((1.7, 1.7, 1.7), (0, 0, 0), white, 0.22)]
    h = 0.85
    spots = {
        # face avant (-Y) : 3 points ; dessus (+Z) : 5 points ; droite (+X) : 2 points
        "front": ((0, -h, 0), [(-0.45, 0.45), (0, 0), (0.45, -0.45)]),
        "top": ((0, 0, h), [(-0.45, -0.45), (0.45, -0.45), (0, 0), (-0.45, 0.45), (0.45, 0.45)]),
        "right": ((h, 0, 0), [(-0.4, 0.4), (0.4, -0.4)]),
    }
    for name, (origin, offsets) in spots.items():
        for u, v in offsets:
            if name == "front":
                loc, scale = (origin[0] + u, origin[1] + 0.02, origin[2] + v), (1, 0.28, 1)
            elif name == "top":
                loc, scale = (origin[0] + u, origin[1] + v, origin[2] - 0.02), (1, 1, 0.28)
            else:
                loc, scale = (origin[0] - 0.02, origin[1] + u, origin[2] + v), (0.28, 1, 1)
            objs.append(sphere(loc, 0.17, pip, scale))
    parent_all(objs, (math.radians(32), math.radians(6), math.radians(-30)))


def build_ticket():
    """Cette methode permet de modeliser le ticket dore (encoches, etoile) lorsque l'icone des passes de jeu est
    rendue."""
    gold = material("Ticket", "#FFC21E", roughness=0.3)
    red = material("Star", "#FF3C8C", roughness=0.3)
    body = box((2.4, 0.3, 1.8), (0, 0, 0), gold, 0.12)
    for x in (-1.25, 1.25):
        cut = cylinder((x, 0, 0), 0.32, 1.0, gold, rotation=(math.radians(90), 0, 0), vertices=24)
        cut.hide_render = True
        mod = body.modifiers.new("Notch", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cut
    objs = [body, star((0, -0.18, 0), 0.6, 0.12, red)]
    parent_all(objs, (math.radians(-8), 0, math.radians(-28)))


def build_rebirth():
    """Cette methode permet de modeliser les deux fleches circulaires violettes (renaissance) lorsque l'icone Rebirth
    est rendue."""
    purple = material("Arrow", "#B04BFF", roughness=0.25, emission=0.15)
    radius = 1.15
    for base in (20, 200):
        arc_beads((0, 0, 0), radius, base, base + 130, purple, 0.17, count=50)
        # Pointe : cone dont l'axe suit la tangente (sens trigonometrique) au bout de l'arc
        a = math.radians(base + 130)
        pos = Vector((radius * math.cos(a), 0, radius * math.sin(a)))
        tangent = Vector((-math.sin(a), 0, math.cos(a)))
        # Cree a l'origine (transform_apply cuit la position dans le maillage), tourne, puis deplace
        head = cylinder((0, 0, 0), 0.55, 0.8, purple, vertices=16, radius2=0.0, bevel=0.05)
        head.rotation_euler = tangent.to_track_quat("Z", "Y").to_euler()
        head.location = pos + tangent * 0.3


# Couleurs des raretes (Shared.Rarity, dans l'ordre) : icones des mannequins dans la barre d'outils (#54), puis les
# raretes au-dela de Secret (#94 : Divine, Celestial, Ethereal, Infinity)
RARITY_COLORS = ["#EBEBEB", "#5ADC5A", "#46A0FF", "#BE5AFF", "#FFBE28", "#FF466E", "#6EFFE1",
                 "#FFF08C", "#FF8CEB", "#AA8CFF", "#FF6E1E"]


def rarity_builder(color):
    """Cette methode permet de fabriquer la construction de l'icone d'une rarete (buste du mannequin, zones claires a
    la couleur de la rarete) lorsque la table des icones est remplie."""

    def build():
        """Cette methode permet de construire le buste teinte lorsque l'icone de la rarete est rendue."""
        build_dummy()
        tint = material("Rarity", color, roughness=0.35)
        for obj in bpy.context.scene.objects:
            if obj.type != "MESH":
                continue
            for index, slot in enumerate(obj.material_slots):
                if slot.material and slot.material.name.split(".")[0] == "Body":
                    obj.material_slots[index].material = tint

    return build


ICONS = {
    "shop": build_gift,
    "index": build_book,
    "dummies": build_dummy,
    "power": build_biceps,
    "cash": build_cash,
    "arrow": build_arrow,
    "music": build_music,
    # Boutique Robux (#173) et bouton Rebirth (#111)
    "clover": build_clover,
    "moneybag": build_moneybag,
    "crown": build_crown,
    "house": build_house,
    "rainbow": build_rainbow,
    "potion": build_potion,
    "globe": build_globe,
    "dice": build_dice,
    "ticket": build_ticket,
    "rebirth": build_rebirth,
}
for _rank, _color in enumerate(RARITY_COLORS, start=1):
    ICONS["rarity%d" % _rank] = rarity_builder(_color)


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


def write_sheet(tiles, name="sheet.png"):
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
    img.filepath_raw = os.path.join(EXPORT, name)
    img.file_format = "PNG"
    img.save()


def main():
    """Cette methode permet de rendre les icones demandees (toutes par defaut) lorsque le script est lance."""
    os.makedirs(EXPORT, exist_ok=True)
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    names = args or list(ICONS)
    tiles = [render_icon(name) for name in names]
    # Rendu partiel : planche separee (sheet_partial.png), la planche complete reste celle de tous les rendus
    write_sheet(tiles, "sheet_partial.png" if args else "sheet.png")


# Importable (assets/icons/dummy_icons.py reprend outline et write_sheet) : rendu seulement si lance directement
if __name__ == "__main__":
    main()
