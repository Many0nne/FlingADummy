# Mannequins de collection (#66) : un modele propre par mannequin, construit sur le corps du mannequin de crash-test
# (assets/dummy/build_dummy.py) avec des pieces ajoutees (maillages separes, une couleur et un materiau Roblox chacune),
# de plus en plus spectaculaire avec la rarete. Exporte export/collection.fbx (pieces ajoutees seules), ecrit
# export/collection.json et genere src/shared/DummyModels.luau (looks, gabarit des pieces, effets), puis rend un apercu
# par mannequin dans export/collection/<id>.png (planche : collection_sheet.py).
# Usage : blender -b --factory-startup --python assets/dummy/build_collection.py [-- --no-render] [--only id,id]
# Unite : 1 unite Blender = 1 stud. Coordonnees des formes en repere Roblox (X droite, Y haut, -Z avant).
import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_dummy as bd  # noqa: E402

EXPORT = os.path.join(HERE, "export")
RENDERS = os.path.join(EXPORT, "collection")
ROOT = os.path.dirname(os.path.dirname(HERE))
LUAU_OUT = os.path.join(ROOT, "src", "shared", "DummyModels.luau")

PIECES = bd.PIECES
HX, HY, HZ = PIECES["Head"][1]
HEAD_TOP = 2.85  # haut du crane (boite de tete 1.28 de haut centree en 2.21)


# --------------------------------------------------------------------------------------------------------------------
# Couleurs et materiaux
# --------------------------------------------------------------------------------------------------------------------


def lin(c):
    """Cette methode permet de convertir une composante sRGB 0-255 en lineaire 0-1 lorsque Blender prend une couleur."""
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


_MATS = {}


def roblox_material(rgb, material="SmoothPlastic", transparency=0.0):
    """Cette methode permet de donner un materiau Blender qui imite un materiau Roblox (plastique, neon, verre, metal,
    glace, champ de force, tissu, roche) d'une couleur lorsque l'on habille une forme ou un apercu."""
    key = (tuple(rgb), material, transparency)
    if key in _MATS:
        return _MATS[key]
    mat = bpy.data.materials.new(f"{material}_{rgb[0]}_{rgb[1]}_{rgb[2]}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.45
    alpha = 1.0 - transparency
    if material == "Neon":
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 1.3
    elif material == "Glass":
        bsdf.inputs["Roughness"].default_value = 0.05
        bsdf.inputs["Transmission Weight"].default_value = 0.7
        alpha = min(alpha, 0.72)
    elif material in ("Foil", "Metal", "DiamondPlate"):
        bsdf.inputs["Metallic"].default_value = 1.0
        bsdf.inputs["Roughness"].default_value = 0.22 if material == "Foil" else 0.38
    elif material == "Ice":
        bsdf.inputs["Roughness"].default_value = 0.15
        bsdf.inputs["Transmission Weight"].default_value = 0.35
        alpha = min(alpha, 0.85)
    elif material == "ForceField":
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 0.8
        alpha = min(alpha, 0.45)
    elif material == "Fabric":
        bsdf.inputs["Roughness"].default_value = 0.9
    elif material in ("Basalt", "CrackedLava"):
        bsdf.inputs["Roughness"].default_value = 0.85
        if material == "CrackedLava":
            # Fissures orange lumineuses sur roche sombre
            noise = nodes.new("ShaderNodeTexVoronoi")
            noise.feature = "DISTANCE_TO_EDGE"
            noise.inputs["Scale"].default_value = 3.0
            ramp = nodes.new("ShaderNodeValToRGB")
            ramp.color_ramp.elements[0].position = 0.0
            ramp.color_ramp.elements[1].position = 0.06
            links = mat.node_tree.links
            links.new(noise.outputs["Distance"], ramp.inputs["Fac"])
            dark = (0.03, 0.02, 0.018, 1)
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.inputs[6].default_value = col
            mix.inputs[7].default_value = dark
            links.new(ramp.outputs["Color"], mix.inputs[0])
            links.new(mix.outputs[2], bsdf.inputs["Base Color"])
            inv = nodes.new("ShaderNodeInvert")
            links.new(ramp.outputs["Color"], inv.inputs["Color"])
            links.new(mix.outputs[2], bsdf.inputs["Emission Color"])
            links.new(inv.outputs["Color"], bsdf.inputs["Emission Strength"])
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            mat.surface_render_method = "BLENDED"
        except (AttributeError, TypeError):
            pass
    _MATS[key] = mat
    return mat


# Plain material for FBX export (no texture: the importer must not create one)
_EXPORT_MAT = None


def export_material():
    """Cette methode permet de donner le materiau neutre des pieces exportees (sans texture, la couleur et le
    materiau Roblox sont poses par le jeu) lorsque l'on modelise une piece."""
    global _EXPORT_MAT
    if _EXPORT_MAT is None:
        _EXPORT_MAT = bpy.data.materials.new("AddonExport")
    return _EXPORT_MAT


# --------------------------------------------------------------------------------------------------------------------
# Formes (repere Roblox)
# --------------------------------------------------------------------------------------------------------------------


def rb(v):
    """Cette methode permet de convertir un point Roblox (x, y, z) en Blender (x, -z, y) lorsque l'on place une
    forme."""
    return Vector((v[0], -v[2], v[1]))


def br(v):
    """Cette methode permet de convertir un point Blender en Roblox lorsque l'on mesure une forme."""
    return Vector((v[0], v[2], -v[1]))


def rot_matrix(rot):
    """Cette methode permet de donner la matrice de rotation Roblox (degres, ordre X puis Y puis Z) lorsque l'on
    oriente une forme."""
    rx, ry, rz = (math.radians(a) for a in rot)
    return Matrix.Rotation(rz, 3, "Z") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rx, 3, "X")


def _finish(obj, scale, center, rot, bevel, segments=3, angle_limit=False):
    """Cette methode permet de mettre une primitive a l'echelle, d'arrondir ses aretes, puis de la tourner et la placer
    (repere Roblox) lorsque l'on cree une forme."""
    me = obj.data
    s = Vector(scale)
    for v in me.vertices:
        p = br(v.co)
        v.co = rb(Vector((p.x * s.x, p.y * s.y, p.z * s.z)))
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE" if angle_limit else "NONE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    m = rot_matrix(rot)
    c = Vector(center)
    for v in me.vertices:
        v.co = rb(m @ br(v.co) + c)
    me.update()
    obj.data.materials.append(export_material())
    return obj


def box(size, center, bevel=0.08, rot=(0, 0, 0), segments=3):
    """Cette methode permet de creer un pave aux aretes adoucies (taille, centre et rotation Roblox) lorsque l'on
    modelise une piece."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    bevel = min(bevel, min(size) * 0.45)
    return _finish(obj, size, center, rot, bevel, segments)


def cyl(radius, height, center, rot=(0, 0, 0), verts=18, bevel=0.03, r2=None):
    """Cette methode permet de creer un cylindre (ou un tronc de cone si `r2`) d'axe Y Roblox avant rotation lorsque
    l'on modelise une piece."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=1, depth=1, location=(0, 0, 0))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=1, radius2=r2 / radius, depth=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    return _finish(obj, (radius, height, radius), center, rot, min(bevel, radius * 0.3), 2, angle_limit=True)


def cone(radius, height, center, rot=(0, 0, 0), verts=12):
    """Cette methode permet de creer un cone pointe vers +Y Roblox avant rotation lorsque l'on modelise une piece."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=1, radius2=0, depth=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    return _finish(obj, (radius, height, radius), center, rot, 0)


def ball(radius, center, scale=(1, 1, 1), rot=(0, 0, 0), seg=14):
    """Cette methode permet de creer une boule (eventuellement ecrasee par `scale`) lorsque l'on modelise une piece."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(6, seg // 2), radius=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    return _finish(obj, (radius * scale[0], radius * scale[1], radius * scale[2]), center, rot, 0)


def gem(radius, height, center, rot=(0, 0, 0), verts=6):
    """Cette methode permet de creer un cristal a facettes (deux pyramides opposees) lorsque l'on modelise un diamant
    ou un eclat."""
    a = cone(radius, height * 0.35, (0, height * 0.175, 0), verts=verts)
    b = cone(radius, height * 0.65, (0, -height * 0.325, 0), rot=(180, 0, 0), verts=verts)
    obj = merge([a, b])
    m = rot_matrix(rot)
    c = Vector(center)
    for v in obj.data.vertices:
        v.co = rb(m @ br(v.co) + c)
    return obj


def shard(radius, height, center, rot=(0, 0, 0), verts=6):
    """Cette methode permet de creer un eclat de cristal (prisme hexagonal a pointe) dresse vers +Y avant rotation
    lorsque l'on modelise de la glace ou du diamant."""
    body = cyl(radius, height * 0.7, (0, height * 0.35, 0), verts=verts, bevel=0)
    tip = cone(radius, height * 0.3, (0, height * 0.85, 0), verts=verts)
    obj = merge([body, tip])
    m = rot_matrix(rot)
    c = Vector(center)
    for v in obj.data.vertices:
        v.co = rb(m @ br(v.co) + c)
    return obj


def torus(major, minor, center, rot=(0, 0, 0), seg=28, minor_seg=8):
    """Cette methode permet de creer un anneau d'axe Y Roblox avant rotation lorsque l'on modelise une bouee, un halo
    ou un anneau en orbite."""
    bpy.ops.mesh.primitive_torus_add(
        major_segments=seg, minor_segments=minor_seg, major_radius=major, minor_radius=minor, location=(0, 0, 0)
    )
    obj = bpy.context.active_object
    return _finish(obj, (1, 1, 1), center, rot, 0)


def prism(points, thickness, center, rot=(0, 0, 0), bevel=0.03):
    """Cette methode permet d'extruder un polygone du plan XY Roblox (points 2D) sur `thickness` en Z lorsque l'on
    modelise une forme plate (cape, aile, eclair, bouclier)."""
    me = bpy.data.meshes.new("prism")
    n = len(points)
    verts = [(x, y, -thickness / 2) for x, y in points] + [(x, y, thickness / 2) for x, y in points]
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    me.from_pydata([tuple(rb(v)) for v in verts], [], faces)
    me.update()
    obj = bpy.data.objects.new("prism", me)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return _finish(obj, (1, 1, 1), center, rot, bevel, 2)


def studs(center, nx, nz, pitch=0.42, radius=0.13, height=0.1, rot=(0, 0, 0)):
    """Cette methode permet de poser une grille de tenons de brique (dessus d'une surface) lorsque l'on donne le style
    briques des jeux de reference a une piece."""
    out = []
    m = rot_matrix(rot)
    c = Vector(center)
    for i in range(nx):
        for k in range(nz):
            local = Vector(((i - (nx - 1) / 2) * pitch, height / 2, (k - (nz - 1) / 2) * pitch))
            out.append(cyl(radius, height, tuple(m @ local + c), rot=rot, verts=12, bevel=0.02))
    return out


def merge(objs):
    """Cette methode permet de fusionner des formes en un seul objet lorsque l'on assemble une piece."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    return bpy.context.active_object


def place(obj, rot=(0, 0, 0), center=(0, 0, 0)):
    """Cette methode permet de tourner puis deplacer une forme deja construite autour de l'origine (repere Roblox)
    lorsque l'on assemble un groupe de formes d'un bloc (anneau incline, aile)."""
    m = rot_matrix(rot)
    c = Vector(center)
    for v in obj.data.vertices:
        v.co = rb(m @ br(v.co) + c)
    obj.data.update()
    return obj


def group(objs, rot=(0, 0, 0), center=(0, 0, 0)):
    """Cette methode permet de fusionner des formes construites autour de l'origine puis de les tourner et placer
    ensemble lorsque l'on modelise un ensemble incline (anneau a graduations, faisceau d'ailes)."""
    return place(merge(objs), rot, center)


def annulus(r_in, r_out, thickness, center, rot=(0, 0, 0), segs=48):
    """Cette methode permet de creer un anneau plat (disque perce) du plan XY Roblox, epais de `thickness` en Z, lorsque
    l'on modelise un disque d'accretion ou un anneau de planete."""
    me = bpy.data.meshes.new("annulus")
    verts, faces = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ca, sa = math.cos(a), math.sin(a)
        for r in (r_in, r_out):
            for z in (-thickness / 2, thickness / 2):
                verts.append(tuple(rb((r * ca, r * sa, z))))
    for i in range(segs):
        j = (i + 1) % segs
        a0, a1 = 4 * i, 4 * j  # indices : (in, bas) (in, haut) (out, bas) (out, haut)
        faces += [
            [a0 + 1, a1 + 1, a1 + 3, a0 + 3],  # dessus
            [a0 + 0, a0 + 2, a1 + 2, a1 + 0],  # dessous
            [a0 + 2, a0 + 3, a1 + 3, a1 + 2],  # bord exterieur
            [a0 + 0, a1 + 0, a1 + 1, a0 + 1],  # bord interieur
        ]
    me.from_pydata(verts, [], faces)
    me.update()
    obj = bpy.data.objects.new("annulus", me)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.materials.append(export_material())
    return place(obj, rot, center)


def star(r_out, r_in, thickness, center, rot=(0, 0, 0), points=5):
    """Cette methode permet de creer une etoile plate a `points` branches (plan XY Roblox) lorsque l'on modelise une
    couronne d'etoiles, un embleme ou des etoiles semees."""
    pts = []
    for k in range(points * 2):
        a = math.pi / 2 + math.pi * k / points
        r = r_out if k % 2 == 0 else r_in
        pts.append((r * math.cos(a), r * math.sin(a)))
    return prism(pts, thickness, center, rot=rot, bevel=0)


def spiral_arm(center, phase, r0, r1, sweep, count, w0, w1, thickness=0.08, z=0.0):
    """Cette methode permet de poser un bras spiral (blocs alignes sur la tangente, du coeur vers l'exterieur, de plus
    en plus fins) dans le plan XY autour de `center` lorsque l'on modelise une galaxie ou un tourbillon."""
    out = []
    drda = (r1 - r0) / sweep
    for i in range(count):
        t = i / (count - 1)
        a = phase + t * sweep
        r = r0 + (r1 - r0) * t
        w = w0 + (w1 - w0) * t
        tangent = a + math.atan2(r, drda)
        step = math.hypot(r, drda) * sweep / (count - 1)
        out.append(box((max(0.2, step * 1.5), w, thickness),
                       (center[0] + r * math.cos(a), center[1] + r * math.sin(a), center[2] + z),
                       bevel=min(0.03, w * 0.3), rot=(0, 0, math.degrees(tangent)), segments=1))
    return out


def ring_of(count, radius, make, y=0.0, phase=0.0):
    """Cette methode permet de repartir `count` formes sur un cercle horizontal (make(x, z, angle_deg) cree chacune)
    lorsque l'on modelise des objets en orbite ou une couronne."""
    out = []
    for i in range(count):
        a = phase + 2 * math.pi * i / count
        out.append(make(radius * math.cos(a), radius * math.sin(a), math.degrees(a)))
    return out


# --------------------------------------------------------------------------------------------------------------------
# Catalogue des modeles (#66) : couleurs sRGB 0-255, materiaux Roblox, pieces ajoutees, effets
# --------------------------------------------------------------------------------------------------------------------

WHITE = (245, 245, 245)
BLACK = (32, 32, 38)
GOLD = (255, 196, 40)
SILVER = (205, 210, 220)


class Part:
    """Piece ajoutee : nom, piece porteuse, couleur, materiau Roblox, formes, animation (spin : axe + degres/s, bob :
    amplitude + periode)."""

    def __init__(self, name, piece, color, shapes, material="SmoothPlastic", transparency=0.0, spin=None, bob=None):
        """Cette methode permet de decrire une piece ajoutee lorsque l'on compose un modele de collection."""
        self.name = name
        self.piece = piece
        self.color = color
        self.material = material
        self.transparency = transparency
        self.shapes = shapes
        self.spin = spin
        self.bob = bob


def fx_particles(preset, piece, offset, color, color2=None):
    """Cette methode permet de decrire un emetteur de particules (preset de Shared.DummyShape) lorsque l'on donne ses
    effets a un mannequin Legendary ou plus."""
    return {"kind": "particles", "preset": preset, "piece": piece, "offset": offset, "color": color,
            "color2": color2 or color}


def fx_light(piece, offset, color, light_range=12, brightness=2):
    """Cette methode permet de decrire une lumiere ponctuelle lorsque l'on donne ses effets a un mannequin."""
    return {"kind": "light", "piece": piece, "offset": offset, "color": color, "range": light_range,
            "brightness": brightness}


def look_rookie():
    """Cette methode permet de modeliser le Rookie (casque de mousse a tenons, brassards gonflables) lorsque le
    catalogue se construit."""
    blue, orange = (40, 120, 255), (255, 140, 30)
    helmet = [
        box((1.72, 0.62, 1.66), (0, HEAD_TOP - 0.12, 0), bevel=0.28, segments=4),
        box((0.22, 0.7, 0.9), (-0.82, 2.3, 0.05), bevel=0.1),
        box((0.22, 0.7, 0.9), (0.82, 2.3, 0.05), bevel=0.1),
        *studs((0, HEAD_TOP + 0.18, 0), 2, 2, pitch=0.6, radius=0.16, height=0.12),
    ]
    parts = [Part("Helmet", "Head", blue, helmet)]
    for side, sx in (("L", -1), ("R", 1)):
        parts.append(Part("Floaty" + side, side == "L" and "LeftUpperArm" or "RightUpperArm", orange,
                          [torus(0.52, 0.24, (1.45 * sx, 0.55, 0), seg=20)]))
    return dict(color=(240, 240, 240), parts=parts)


def look_traffic():
    """Cette methode permet de modeliser le Traffic (plot de chantier sur la tete, gilet fluo a bandes) lorsque le
    catalogue se construit."""
    orange, lime, white = (255, 110, 20), (205, 255, 40), WHITE
    base_y = HEAD_TOP
    cone_parts = [
        box((1.25, 0.14, 1.25), (0, base_y + 0.07, 0), bevel=0.05),
        cyl(0.55, 1.5, (0, base_y + 0.85, 0), r2=0.1, verts=20),
    ]
    stripes = [
        cyl(0.43, 0.2, (0, base_y + 0.62, 0), r2=0.39, verts=20, bevel=0),
        cyl(0.27, 0.2, (0, base_y + 1.1, 0), r2=0.23, verts=20, bevel=0),
    ]
    vest = [
        box((0.62, 1.7, 0.08), (-0.66, 0.15, -0.58), bevel=0.03),
        box((0.62, 1.7, 0.08), (0.66, 0.15, -0.58), bevel=0.03),
        box((2.08, 1.7, 0.08), (0, 0.15, 0.58), bevel=0.03),
        box((0.08, 1.7, 1.12), (-1.03, 0.15, 0), bevel=0.03),
        box((0.08, 1.7, 1.12), (1.03, 0.15, 0), bevel=0.03),
    ]
    vest_stripes = []
    for y in (-0.15, 0.35):
        vest_stripes += [
            box((0.64, 0.16, 0.1), (-0.66, y, -0.6), bevel=0.02),
            box((0.64, 0.16, 0.1), (0.66, y, -0.6), bevel=0.02),
            box((2.1, 0.16, 0.1), (0, y, 0.6), bevel=0.02),
            box((0.1, 0.16, 1.14), (-1.05, y, 0), bevel=0.02),
            box((0.1, 0.16, 1.14), (1.05, y, 0), bevel=0.02),
        ]
    return dict(color=(255, 130, 30), pieces={"LeftUpperLeg": (40, 70, 150), "RightUpperLeg": (40, 70, 150)},
                parts=[
                    Part("Cone", "Head", orange, cone_parts),
                    Part("ConeStripes", "Head", white, stripes),
                    Part("Vest", "Torso", lime, vest),
                    Part("VestStripes", "Torso", (225, 230, 235), vest_stripes, material="Foil"),
                ])


def look_mint():
    """Cette methode permet de modeliser le Mint (casque audio rose, skate dans le dos) lorsque le catalogue se
    construit."""
    pink, purple, yellow = (255, 90, 170), (150, 70, 230), (255, 220, 40)
    phones = [
        box((1.75, 0.16, 0.3), (0, HEAD_TOP + 0.12, 0), bevel=0.06),
        box((0.14, 0.7, 0.3), (-0.86, 2.62, 0), bevel=0.05),
        box((0.14, 0.7, 0.3), (0.86, 2.62, 0), bevel=0.05),
        cyl(0.4, 0.32, (-0.92, 2.2, 0), rot=(0, 0, 90)),
        cyl(0.4, 0.32, (0.92, 2.2, 0), rot=(0, 0, 90)),
    ]
    deck = [
        box((1.0, 2.9, 0.14), (0, 0.0, 0.78), bevel=0.06, rot=(0, 0, 10)),
        box((0.55, 0.12, 0.14), (0.2, 1.0, 0.92), bevel=0.03, rot=(0, 0, 10)),
        box((0.55, 0.12, 0.14), (-0.2, -1.0, 0.92), bevel=0.03, rot=(0, 0, 10)),
    ]
    wheels = []
    for cx, cy in ((0.2, 1.0), (-0.2, -1.0)):
        for dx in (-0.36, 0.36):
            c = Vector((cx + dx * math.cos(math.radians(10)), cy + dx * math.sin(math.radians(10)), 1.04))
            wheels.append(cyl(0.15, 0.16, tuple(c), rot=(0, 0, 100), verts=14))
    return dict(color=(110, 235, 170), parts=[
        Part("Headphones", "Head", pink, phones),
        Part("Deck", "Torso", purple, deck),
        Part("Wheels", "Torso", yellow, wheels),
    ])


def look_biker():
    """Cette methode permet de modeliser le Biker (casque integral a visiere, blouson ouvert cloute, jean) lorsque le
    catalogue se construit."""
    black = (35, 35, 42)
    helmet = [
        box((1.74, 1.56, 1.72), (0, 2.2, 0.02), bevel=0.42, segments=5),
        box((0.3, 0.2, 1.7), (0, HEAD_TOP + 0.02, 0.05), bevel=0.08),
        box((1.4, 0.36, 0.3), (0, 1.55, -0.68), bevel=0.1),
    ]
    stripe = [box((0.34, 0.14, 1.78), (0, HEAD_TOP - 0.02, 0.04), bevel=0.05)]
    visor = [box((1.36, 0.5, 0.12), (0, 2.25, -0.86), bevel=0.06)]
    jacket = [
        box((0.66, 2.0, 0.1), (-0.68, 0.18, -0.6), bevel=0.04),
        box((0.66, 2.0, 0.1), (0.68, 0.18, -0.6), bevel=0.04),
        box((2.12, 2.0, 0.1), (0, 0.18, 0.6), bevel=0.04),
        box((0.1, 2.0, 1.2), (-1.06, 0.18, 0), bevel=0.04),
        box((0.1, 2.0, 1.2), (1.06, 0.18, 0), bevel=0.04),
        box((1.9, 0.26, 0.5), (0, 1.16, 0.36), bevel=0.08),
        box((0.36, 0.5, 0.12), (-0.5, 0.98, -0.64), bevel=0.04, rot=(0, 0, -20)),
        box((0.36, 0.5, 0.12), (0.5, 0.98, -0.64), bevel=0.04, rot=(0, 0, 20)),
    ]
    rivets = [ball(0.07, (x, 1.08, z), seg=8) for x in (-0.9, -0.7, 0.7, 0.9) for z in (-0.3, 0.3)]
    rivets += [ball(0.07, (x, y, -0.66), seg=8) for x in (-0.42, 0.42) for y in (0.5, 0.1, -0.3)]
    return dict(color=(225, 50, 50),
                pieces={k: (50, 80, 160) for k in ("LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg")},
                parts=[
                    Part("Helmet", "Head", black, helmet),
                    Part("HelmetStripe", "Head", (225, 50, 50), stripe),
                    Part("Visor", "Head", (255, 150, 30), visor, material="Glass", transparency=0.15),
                    Part("Jacket", "Torso", black, jacket),
                    Part("Rivets", "Torso", SILVER, rivets, material="Foil"),
                ])


def look_nerd():
    """Cette methode permet de modeliser le Nerd (grosses lunettes, noeud papillon, cartable) lorsque le catalogue se
    construit."""
    red, orange = (230, 40, 50), (255, 150, 40)
    frames = []
    for sx in (-1, 1):
        x = 0.36 * sx
        frames += [
            box((0.62, 0.1, 0.1), (x, 2.53, -0.8), bevel=0.03),
            box((0.62, 0.1, 0.1), (x, 2.03, -0.8), bevel=0.03),
            box((0.1, 0.58, 0.1), (x - 0.27, 2.28, -0.8), bevel=0.03),
            box((0.1, 0.58, 0.1), (x + 0.27, 2.28, -0.8), bevel=0.03),
            box((0.08, 0.1, 0.62), (0.78 * sx, 2.45, -0.5), bevel=0.02),
        ]
    frames.append(box((0.2, 0.1, 0.1), (0, 2.42, -0.8), bevel=0.02))
    lenses = [box((0.46, 0.42, 0.04), (0.36 * sx, 2.28, -0.8), bevel=0.01) for sx in (-1, 1)]
    bow = [
        prism([(0, 0), (0.42, 0.22), (0.42, -0.22)], 0.14, (0.04, 0.98, -0.62)),
        prism([(0, 0), (-0.42, 0.22), (-0.42, -0.22)], 0.14, (-0.04, 0.98, -0.62)),
        box((0.18, 0.18, 0.18), (0, 0.98, -0.64), bevel=0.05),
    ]
    pack = [
        box((1.5, 1.75, 0.62), (0, 0.15, 0.88), bevel=0.2, segments=4),
        box((1.1, 0.7, 0.24), (0, -0.25, 1.24), bevel=0.1),
        box((0.18, 0.12, 1.2), (-0.55, 1.16, 0.2), bevel=0.04),
        box((0.18, 0.12, 1.2), (0.55, 1.16, 0.2), bevel=0.04),
        box((0.18, 1.3, 0.1), (-0.55, 0.5, -0.58), bevel=0.04),
        box((0.18, 1.3, 0.1), (0.55, 0.5, -0.58), bevel=0.04),
        *studs((0, 1.02, 0.88), 3, 1, pitch=0.42),
    ]
    return dict(color=(140, 200, 255), parts=[
        Part("Glasses", "Head", BLACK, frames),
        Part("Lenses", "Head", (220, 245, 255), lenses, material="Glass", transparency=0.3),
        Part("BowTie", "Torso", red, bow),
        Part("Backpack", "Torso", orange, pack),
    ])


def look_ocean():
    """Cette methode permet de modeliser l'Ocean (scaphandre en cuivre a hublots, bouteilles, palmes) lorsque le
    catalogue se construit."""
    copper, glass, yellow, fin = (215, 135, 60), (150, 230, 255), (255, 210, 40), (255, 90, 40)
    helmet = [
        box((2.0, 1.9, 2.0), (0, 2.2, 0), bevel=0.62, segments=6),
        cyl(0.62, 0.16, (0, 2.2, -1.0), rot=(90, 0, 0), verts=24),
        cyl(0.4, 0.14, (-1.0, 2.25, 0), rot=(0, 0, 90), verts=20),
        cyl(0.4, 0.14, (1.0, 2.25, 0), rot=(0, 0, 90), verts=20),
        cyl(0.9, 0.3, (0, 1.3, 0), verts=24),
        cyl(0.16, 0.3, (0, 3.25, 0)),
        *[ball(0.08, (0.62 * math.cos(a), 2.2 + 0.62 * math.sin(a), -1.08), seg=8)
          for a in np.linspace(0, 2 * math.pi, 9)[:-1]],
    ]
    portholes = [
        cyl(0.48, 0.1, (0, 2.2, -1.06), rot=(90, 0, 0), verts=24, bevel=0.01),
        cyl(0.3, 0.1, (-1.05, 2.25, 0), rot=(0, 0, 90), verts=20, bevel=0.01),
        cyl(0.3, 0.1, (1.05, 2.25, 0), rot=(0, 0, 90), verts=20, bevel=0.01),
    ]
    tanks = [
        cyl(0.34, 2.0, (-0.38, 0.1, 0.95), verts=20),
        cyl(0.34, 2.0, (0.38, 0.1, 0.95), verts=20),
        ball(0.34, (-0.38, 1.1, 0.95), scale=(1, 0.6, 1)),
        ball(0.34, (0.38, 1.1, 0.95), scale=(1, 0.6, 1)),
    ]
    valves = [
        cyl(0.1, 0.3, (-0.38, 1.4, 0.95)),
        cyl(0.1, 0.3, (0.38, 1.4, 0.95)),
        box((0.9, 0.12, 0.12), (0, 1.5, 0.95), bevel=0.04),
        box((1.8, 0.14, 0.1), (0, 0.6, 0.6), bevel=0.04),
    ]
    parts = [
        Part("DiveHelmet", "Head", copper, helmet, material="Metal"),
        Part("Portholes", "Head", glass, portholes, material="Glass", transparency=0.2),
        Part("Tanks", "Torso", yellow, tanks),
        Part("Valves", "Torso", SILVER, valves, material="Metal"),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        flipper = [
            prism([(-0.5, 0.0), (0.5, 0.0), (0.7, -1.9), (-0.7, -1.9)], 0.12,
                  (0.5 * sx, -3.76, -0.25), rot=(90, 0, 0), bevel=0.04),
            box((1.0, 0.36, 1.0), (0.5 * sx, -3.62, 0.05), bevel=0.12),
        ]
        parts.append(Part("Flipper" + side, side == "L" and "LeftLowerLeg" or "RightLowerLeg", fin, flipper))
    return dict(color=(40, 120, 255), parts=parts)


def look_hero():
    """Cette methode permet de modeliser le Hero (grande cape rouge evasee, eclair sur la poitrine, masque, bottes)
    lorsque le catalogue se construit."""
    red, yellow = (230, 40, 40), (255, 215, 40)
    cape = [
        prism([(-1.05, 1.15), (1.05, 1.15), (1.75, -3.3), (0.6, -3.05), (0, -3.4), (-0.6, -3.05), (-1.75, -3.3)],
              0.12, (0, 0, 0.72), rot=(-10, 0, 0), bevel=0.04),
        box((2.0, 0.24, 0.5), (0, 1.12, 0.42), bevel=0.08),
        box((0.5, 0.3, 0.3), (-1.0, 1.1, -0.45), bevel=0.08),
        box((0.5, 0.3, 0.3), (1.0, 1.1, -0.45), bevel=0.08),
    ]
    bolt = [prism([(0.15, 0.62), (-0.32, -0.02), (0.0, -0.02), (-0.2, -0.65), (0.34, 0.12), (0.04, 0.12),
                   (0.28, 0.62)], 0.1, (0, 0.32, -0.6), bevel=0.02)]
    shield_bg = [cyl(0.55, 0.06, (0, 0.32, -0.56), rot=(90, 0, 0), verts=24, bevel=0.02)]
    mask = [
        box((1.56, 0.36, 1.48), (0, 2.32, 0), bevel=0.12),
        box((0.3, 0.2, 0.08), (-0.75, 2.32, 0.5), bevel=0.04, rot=(0, -60, 0)),
    ]
    eyes = [box((0.3, 0.16, 0.05), (sx * 0.32, 2.34, -0.76), bevel=0.03) for sx in (-1, 1)]
    blue = (50, 100, 255)
    return dict(color=blue, pieces={"LeftLowerLeg": red, "RightLowerLeg": red, "LeftLowerArm": red,
                                    "RightLowerArm": red},
                parts=[
                    Part("Cape", "Torso", red, cape, material="Fabric"),
                    Part("EmblemDisc", "Torso", red, shield_bg),
                    Part("Emblem", "Torso", yellow, bolt),
                    Part("Mask", "Head", (25, 25, 32), mask),
                    Part("MaskEyes", "Head", WHITE, eyes),
                ])


def look_pilot():
    """Cette methode permet de modeliser le Pilot (bonnet d'aviateur, lunettes, echarpe, jetpack a ailerons) lorsque
    le catalogue se construit."""
    brown, red = (130, 80, 40), (230, 40, 40)
    cap = [
        box((1.62, 0.72, 1.6), (0, HEAD_TOP - 0.18, 0.02), bevel=0.3, segments=4),
        box((0.14, 0.8, 0.6), (-0.8, 2.15, 0.0), bevel=0.06),
        box((0.14, 0.8, 0.6), (0.8, 2.15, 0.0), bevel=0.06),
        box((1.5, 0.5, 0.14), (0, 2.45, 0.74), bevel=0.06),
        box((1.7, 0.12, 0.12), (0, 2.66, -0.6), bevel=0.04),
    ]
    goggles = [cyl(0.3, 0.16, (sx * 0.36, 2.66, -0.82), rot=(90, 0, 0), verts=20) for sx in (-1, 1)]
    goggles.append(box((0.24, 0.1, 0.1), (0, 2.66, -0.84), bevel=0.03))
    lens = [cyl(0.22, 0.06, (sx * 0.36, 2.66, -0.91), rot=(90, 0, 0), verts=20, bevel=0.01) for sx in (-1, 1)]
    pack = [
        cyl(0.36, 1.8, (-0.42, 0.1, 0.98), verts=20),
        cyl(0.36, 1.8, (0.42, 0.1, 0.98), verts=20),
        ball(0.36, (-0.42, 1.0, 0.98), scale=(1, 0.8, 1)),
        ball(0.36, (0.42, 1.0, 0.98), scale=(1, 0.8, 1)),
        cyl(0.28, 0.4, (-0.42, -0.95, 0.98), r2=0.36, verts=16),
        cyl(0.28, 0.4, (0.42, -0.95, 0.98), r2=0.36, verts=16),
        box((1.5, 0.3, 0.3), (0, 0.4, 0.66), bevel=0.08),
    ]
    wings = [
        prism([(0.0, 0.3), (2.2, 0.75), (2.4, 0.45), (0.0, -0.3)], 0.12, (0.25, 0.3, 1.0), rot=(0, 0, 0)),
        prism([(0.0, 0.3), (-2.2, 0.75), (-2.4, 0.45), (0.0, -0.3)], 0.12, (-0.25, 0.3, 1.0), rot=(0, 0, 0)),
        prism([(-0.3, 0), (0.3, 0), (0.0, 0.9)], 0.1, (0, 1.4, 1.0), rot=(0, 90, 0)),
    ]
    scarf = [
        box((1.0, 0.3, 0.9), (0, 1.12, 0), bevel=0.12),
        prism([(0, 0), (0.42, 0), (0.6, -1.4), (0.2, -1.5)], 0.08, (0.2, 1.0, 0.6), rot=(-25, 0, -20)),
    ]
    return dict(color=(70, 165, 60), pieces={"LeftLowerLeg": brown, "RightLowerLeg": brown},
                parts=[
                    Part("AviatorCap", "Head", brown, cap),
                    Part("Goggles", "Head", (60, 40, 25), goggles),
                    Part("GoggleLens", "Head", (255, 200, 60), lens, material="Glass", transparency=0.1),
                    Part("Jetpack", "Torso", SILVER, pack, material="Metal"),
                    Part("Wings", "Torso", red, wings),
                    Part("Scarf", "Torso", WHITE, scarf, material="Fabric"),
                ])


def look_ice():
    """Cette methode permet de modeliser l'Ice (couronne et epaulettes d'eclats de glace, bottes gelees) lorsque le
    catalogue se construit."""
    ice = (170, 240, 255)
    crown = [
        shard(0.2, 1.2, (0, HEAD_TOP - 0.15, 0.1), rot=(8, 0, 0)),
        shard(0.16, 0.95, (-0.42, HEAD_TOP - 0.15, 0.0), rot=(0, 0, 22)),
        shard(0.16, 0.95, (0.42, HEAD_TOP - 0.15, 0.0), rot=(0, 0, -22)),
        shard(0.13, 0.7, (-0.62, HEAD_TOP - 0.25, 0.3), rot=(15, 0, 40)),
        shard(0.13, 0.7, (0.62, HEAD_TOP - 0.25, 0.3), rot=(15, 0, -40)),
        shard(0.14, 0.8, (0, HEAD_TOP - 0.2, 0.45), rot=(35, 0, 0)),
    ]
    back = [
        shard(0.3, 2.0, (-0.45, 0.4, 0.55), rot=(30, 0, 25)),
        shard(0.3, 2.0, (0.45, 0.4, 0.55), rot=(30, 0, -25)),
        shard(0.22, 1.4, (0, 0.0, 0.6), rot=(45, 0, 0)),
        shard(0.2, 1.2, (-0.7, -0.4, 0.5), rot=(40, 0, 55)),
        shard(0.2, 1.2, (0.7, -0.4, 0.5), rot=(40, 0, -55)),
    ]
    parts = [
        Part("IceCrown", "Head", ice, crown, material="Glass", transparency=0.1),
        Part("IceWings", "Torso", ice, back, material="Glass", transparency=0.1),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        x = 1.45 * sx
        parts.append(Part("IceShoulder" + side, side == "L" and "LeftUpperArm" or "RightUpperArm", ice, [
            box((1.0, 0.5, 1.0), (x, 1.05, 0), bevel=0.12, rot=(0, 20, 0)),
            shard(0.18, 1.0, (x + 0.1 * sx, 1.15, 0), rot=(0, 0, -35 * sx)),
            shard(0.14, 0.75, (x + 0.2 * sx, 1.05, -0.25), rot=(-25, 0, -55 * sx)),
            shard(0.14, 0.75, (x + 0.2 * sx, 1.05, 0.25), rot=(25, 0, -55 * sx)),
        ], material="Ice"))
        parts.append(Part("IceBoot" + side, side == "L" and "LeftLowerLeg" or "RightLowerLeg", ice, [
            box((1.25, 0.8, 1.25), (0.5 * sx, -3.45, 0), bevel=0.14, rot=(0, 12 * sx, 0)),
            shard(0.14, 0.6, (0.5 * sx + 0.4 * sx, -3.2, -0.3), rot=(-20, 0, -50 * sx)),
        ], material="Ice"))
    return dict(color=(160, 225, 255), material="Ice", parts=parts)


def look_toxic():
    """Cette methode permet de modeliser le Toxic (masque a gaz, slime fluo qui coule de la tete, baril dans le dos)
    lorsque le catalogue se construit."""
    grey, slime, yellow = (70, 74, 82), (120, 255, 60), (255, 210, 30)
    mask = [
        box((1.1, 0.8, 0.4), (0, 1.95, -0.82), bevel=0.16),
        cyl(0.24, 0.4, (-0.5, 1.75, -0.95), rot=(70, 0, 40)),
        cyl(0.24, 0.4, (0.5, 1.75, -0.95), rot=(70, 0, -40)),
        box((1.6, 0.14, 1.5), (0, 2.42, 0.02), bevel=0.05),
    ]
    lenses = [cyl(0.24, 0.1, (sx * 0.35, 2.42, -0.78), rot=(90, 0, 0), verts=18) for sx in (-1, 1)]
    goo = [
        ball(0.82, (0, HEAD_TOP - 0.05, 0), scale=(1.05, 0.45, 1.0)),
        ball(0.35, (0.35, HEAD_TOP + 0.2, -0.1)),
        ball(0.25, (-0.3, HEAD_TOP + 0.25, 0.2)),
        cyl(0.13, 0.7, (-0.62, 2.45, -0.45), bevel=0),
        ball(0.15, (-0.62, 2.1, -0.45)),
        cyl(0.11, 0.5, (0.66, 2.5, 0.3), bevel=0),
        ball(0.13, (0.66, 2.24, 0.3)),
        cyl(0.12, 0.9, (0.2, 2.3, 0.72), bevel=0),
        ball(0.14, (0.2, 1.86, 0.72)),
    ]
    barrel = [
        cyl(0.62, 1.5, (0, 0.05, 1.22), verts=24),
        cyl(0.66, 0.12, (0, 0.5, 1.22), verts=24),
        cyl(0.66, 0.12, (0, -0.4, 1.22), verts=24),
        box((1.6, 0.16, 0.5), (0, 0.9, 0.8), bevel=0.05),
    ]
    barrel_goo = [
        ball(0.6, (0, 0.82, 1.22), scale=(1, 0.4, 1)),
        ball(0.22, (0.1, 1.0, 1.15)),
        cyl(0.12, 0.6, (0.5, 0.45, 1.6), bevel=0),
        ball(0.14, (0.5, 0.15, 1.6)),
        cyl(0.1, 0.45, (-0.45, 0.55, 1.62), bevel=0),
        ball(0.12, (-0.45, 0.32, 1.62)),
        ball(0.5, (-1.45, 1.2, 0), scale=(1, 0.5, 1)),
        ball(0.5, (1.45, 1.2, 0), scale=(1, 0.5, 1)),
    ]
    return dict(color=(150, 220, 50), parts=[
        Part("GasMask", "Head", grey, mask),
        Part("MaskLenses", "Head", slime, lenses, material="Neon"),
        Part("Slime", "Head", slime, goo, material="Neon"),
        Part("Barrel", "Torso", yellow, barrel),
        Part("BarrelGoo", "Torso", slime, barrel_goo, material="Neon"),
    ])


def look_royal():
    """Cette methode permet de modeliser le Royal (chevalier : heaume a plumet, epaulieres, bouclier, epee, cape doree)
    lorsque le catalogue se construit."""
    purple, red = (150, 70, 230), (230, 40, 50)
    helm = [
        box((1.68, 1.6, 1.66), (0, 2.18, 0.0), bevel=0.22, segments=3),
        box((0.14, 1.3, 0.12), (0, 2.1, -0.84), bevel=0.04),
    ]
    slit = [box((1.3, 0.12, 0.06), (0, 2.32, -0.84), bevel=0.02)]
    plume = [box((0.24, 0.3, 0.3), (0, HEAD_TOP + 0.1 + 0.18 * math.sin(i * 0.5), -0.4 + i * 0.28), bevel=0.1,
                 rot=(i * 12, 0, 0)) for i in range(6)]
    cape = [
        prism([(-1.0, 1.15), (1.0, 1.15), (1.35, -3.2), (-1.35, -3.2)], 0.1, (0, 0, 0.7), rot=(-6, 0, 0)),
        box((1.9, 0.22, 0.4), (0, 1.12, 0.45), bevel=0.08),
    ]
    sword = [
        box((0.14, 2.4, 0.06), (1.45, -2.4, -0.25), bevel=0.03),
        cone(0.1, 0.3, (1.45, -3.75, -0.25), rot=(180, 0, 0), verts=4),
        box((0.8, 0.14, 0.18), (1.45, -1.18, -0.25), bevel=0.05),
        cyl(0.08, 0.5, (1.45, -0.86, -0.25)),
    ]
    parts = [
        Part("KnightHelm", "Head", SILVER, helm, material="Metal"),
        Part("HelmSlit", "Head", (20, 20, 25), slit),
        Part("Plume", "Head", red, plume, material="Fabric"),
        Part("RoyalCape", "Torso", GOLD, cape, material="Fabric"),
        Part("Sword", "RightLowerArm", SILVER, sword, material="Metal"),
        Part("ShieldRim", "LeftLowerArm", GOLD, [
            prism([(-0.75, 0.8), (0.75, 0.8), (0.75, -0.1), (0, -1.0), (-0.75, -0.1)], 0.12,
                  (-2.0, -0.6, 0), rot=(0, 90, 0), bevel=0.04),
        ], material="Foil"),
        Part("ShieldFace", "LeftLowerArm", purple, [
            prism([(-0.6, 0.66), (0.6, 0.66), (0.6, -0.12), (0, -0.84), (-0.6, -0.12)], 0.06,
                  (-2.08, -0.6, 0), rot=(0, 90, 0), bevel=0.02),
        ]),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        parts.append(Part("Pauldron" + side, side == "L" and "LeftUpperArm" or "RightUpperArm", SILVER, [
            box((1.15, 0.36, 1.1), (1.5 * sx, 1.08, 0), bevel=0.14, rot=(0, 0, -14 * sx)),
            box((1.05, 0.3, 1.0), (1.6 * sx, 0.82, 0), bevel=0.12, rot=(0, 0, -22 * sx)),
        ], material="Metal"))
    return dict(color=purple, parts=parts)


def look_gold():
    """Cette methode permet de modeliser le Gold (haut-de-forme, monocle, chaine a medaillon, sac d'argent, anneau de
    pieces en orbite, scintillements) lorsque le catalogue se construit."""
    green = (60, 175, 75)
    hat = [
        cyl(0.62, 1.2, (0, HEAD_TOP + 0.62, 0), verts=24),
        cyl(1.0, 0.1, (0, HEAD_TOP + 0.06, 0), verts=28),
    ]
    trim = [
        cyl(0.64, 0.2, (0, HEAD_TOP + 0.25, 0), verts=24, bevel=0.01),
        torus(0.22, 0.05, (0.33, 2.3, -0.78), rot=(90, 0, 0), seg=18, minor_seg=6),
        box((0.04, 0.6, 0.04), (0.55, 2.0, -0.76), bevel=0.01),
    ]
    chain = [ball(0.09, (0.62 * math.cos(a), 1.08 - 0.25 * max(0, math.sin(a)), -0.62 * math.sin(a) * 0.95), seg=8)
             for a in np.linspace(0, 2 * math.pi, 23)[:-1]]
    chain += [
        cyl(0.36, 0.1, (0, 0.35, -0.66), rot=(90, 0, 0), verts=24),
        torus(0.36, 0.05, (0, 0.35, -0.7), rot=(90, 0, 0), seg=24, minor_seg=6),
        box((0.22, 0.4, 0.06), (0, 0.35, -0.73), bevel=0.02),
    ]
    coins = ring_of(8, 2.0, lambda x, z, a: cyl(0.3, 0.08, (x, 0, z), rot=(90, -a + 90, 0), verts=18, bevel=0.02))
    bag = [
        ball(0.52, (1.45, -1.55, -0.1), scale=(1, 1.05, 1)),
        cyl(0.18, 0.25, (1.45, -0.98, -0.1), r2=0.26),
    ]
    dollar = [box((0.08, 0.4, 0.04), (1.45, -1.55, -0.62), bevel=0.01),
              torus(0.1, 0.04, (1.45, -1.47, -0.62), rot=(90, 0, 0), seg=12, minor_seg=4),
              torus(0.1, 0.04, (1.45, -1.63, -0.62), rot=(90, 0, 0), seg=12, minor_seg=4)]
    return dict(color=GOLD, material="Foil", parts=[
        Part("TopHat", "Head", (28, 28, 32), hat),
        Part("HatTrim", "Head", GOLD, trim, material="Foil"),
        Part("GoldChain", "Torso", (255, 215, 60), chain, material="Foil"),
        Part("CoinRing", "Torso", (255, 205, 50), coins, material="Foil", spin=((0, 1, 0), 60)),
        Part("MoneyBag", "RightLowerArm", green, bag),
        Part("MoneyMark", "RightLowerArm", GOLD, dollar, material="Foil"),
    ], effects=[
        fx_particles("sparkle", "Torso", (0, 0.5, 0), (255, 230, 120), (255, 255, 255)),
        fx_light("Torso", (0, 1, -1), (255, 210, 90), 12, 2),
    ])


def look_lava():
    """Cette methode permet de modeliser le Lava (cornes de basalte a pointes ardentes, rochers sur les epaules,
    flammes, rochers en fusion en orbite, feu) lorsque le catalogue se construit."""
    rock, glow, flame = (60, 45, 40), (255, 100, 20), (255, 150, 30)
    horns = []
    for sx in (-1, 1):
        for i in range(4):
            t = i / 3
            horns.append(box((0.34 - 0.06 * i, 0.4, 0.34 - 0.06 * i),
                             (sx * (0.55 + 0.32 * t), HEAD_TOP + 0.05 + 0.42 * i - 0.06 * i * i, 0.1 + 0.1 * i),
                             bevel=0.08, rot=(10 * i, 0, -sx * (25 + 12 * i))))
    tips = [cone(0.14, 0.45, (sx * 1.2, HEAD_TOP + 1.35, 0.5), rot=(30, 0, -sx * 50), verts=8) for sx in (-1, 1)]
    flames = [cone(0.22, 0.9, (0, HEAD_TOP + 0.4, -0.1), verts=8),
              cone(0.16, 0.65, (-0.3, HEAD_TOP + 0.28, 0.15), rot=(0, 0, 15), verts=8),
              cone(0.16, 0.65, (0.3, HEAD_TOP + 0.28, 0.15), rot=(0, 0, -15), verts=8),
              cone(0.12, 0.5, (0, HEAD_TOP + 0.22, 0.42), rot=(20, 0, 0), verts=8)]
    orbs = ring_of(3, 1.9, lambda x, z, a: box((0.42, 0.38, 0.4), (x, 0, z), bevel=0.1, rot=(a, a * 2, 15)))
    parts = [
        Part("Horns", "Head", rock, horns, material="Basalt"),
        Part("HornTips", "Head", glow, tips, material="Neon"),
        Part("Flames", "Head", flame, flames, material="Neon", bob=(0.12, 0.6)),
        Part("MagmaOrbit", "Torso", glow, orbs, material="Neon", spin=((0, 1, 0), 45)),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        x = 1.45 * sx
        parts.append(Part("Boulders" + side, side == "L" and "LeftUpperArm" or "RightUpperArm", rock, [
            box((0.9, 0.7, 0.9), (x, 1.1, 0), bevel=0.15, rot=(12, 20, -10 * sx)),
            box((0.55, 0.5, 0.55), (x + 0.4 * sx, 1.45, 0.15), bevel=0.12, rot=(30, 10, 25)),
            box((0.45, 0.4, 0.45), (x + 0.1 * sx, 1.5, -0.3), bevel=0.1, rot=(-20, 35, 10)),
        ], material="Basalt"))
    return dict(color=(255, 90, 30), material="CrackedLava", parts=parts, effects=[
        fx_particles("fire", "Head", (0, 1.1, 0), (255, 170, 40), (255, 60, 20)),
        fx_particles("embers", "Torso", (0, 0, 0), (255, 140, 40), (255, 60, 20)),
        fx_light("Torso", (0, 1.5, -1), (255, 120, 40), 14, 3),
    ])


def look_diamond():
    """Cette methode permet de modeliser le Diamond (corps de verre, cristaux geants dans le dos, gemmes aux epaules,
    diamant flottant qui tourne, scintillements) lorsque le catalogue se construit."""
    crystal = (150, 240, 255)
    back = [
        shard(0.4, 3.2, (-0.4, 0.3, 0.6), rot=(20, 0, 42), verts=6),
        shard(0.4, 3.2, (0.4, 0.3, 0.6), rot=(20, 0, -42), verts=6),
        shard(0.32, 2.4, (-0.6, -0.3, 0.6), rot=(25, 0, 78), verts=6),
        shard(0.32, 2.4, (0.6, -0.3, 0.6), rot=(25, 0, -78), verts=6),
        shard(0.26, 1.6, (0, 0.5, 0.6), rot=(20, 0, 0), verts=6),
    ]
    parts = [
        Part("Crystals", "Torso", crystal, back, material="Glass", transparency=0.05),
        Part("FloatGem", "Head", (130, 245, 255), [gem(0.5, 1.1, (0, HEAD_TOP + 1.25, 0), verts=8)], material="Neon",
             spin=((0, 1, 0), 90), bob=(0.18, 2.4)),
        Part("Tiara", "Head", (235, 250, 255), [
            box((1.6, 0.14, 1.56), (0, 2.62, 0.0), bevel=0.05),
            gem(0.2, 0.5, (0, 2.78, -0.8), rot=(90, 0, 0), verts=6),
            gem(0.13, 0.34, (-0.42, 2.72, -0.8), rot=(90, 0, 0), verts=6),
            gem(0.13, 0.34, (0.42, 2.72, -0.8), rot=(90, 0, 0), verts=6),
        ], material="Foil"),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        parts.append(Part("ShoulderGem" + side, side == "L" and "LeftUpperArm" or "RightUpperArm", crystal, [
            gem(0.48, 1.0, (1.5 * sx, 1.2, 0), rot=(0, 0, -25 * sx), verts=6),
            gem(0.28, 0.6, (1.6 * sx, 1.1, -0.45), rot=(-30, 0, -40 * sx), verts=6),
        ], material="Glass", transparency=0.05))
    return dict(color=(120, 230, 255), material="Glass", parts=parts, effects=[
        fx_particles("sparkle", "Torso", (0, 0.5, 0), (180, 250, 255), (255, 255, 255)),
        fx_light("Head", (0, 1.2, 0), (120, 230, 255), 14, 2.5),
    ])


def look_galaxy():
    """Cette methode permet de modeliser le Galaxy (astronaute equipe : bulle de verre et visiere doree, combinaison a
    protections et bandes lumineuses, sac de survie a antenne, anneau planetaire a trois bandes et asteroides, lunes en
    orbite) lorsque le catalogue se construit."""
    purple, pink, cyan, yellow = (100, 50, 210), (255, 110, 200), (90, 230, 255), (255, 220, 80)
    bubble = [ball(1.12, (0, 2.22, 0), seg=28)]
    visor = [box((1.25, 0.62, 0.12), (0, 2.32, -0.8), bevel=0.1, rot=(-8, 0, 0))]
    collar = [torus(0.74, 0.17, (0, 1.38, 0), seg=28), box((0.55, 0.32, 0.1), (0, 0.65, -0.62), bevel=0.04)]
    pads = []
    for sx in (-1, 1):
        pads.append(ball(0.55, (1.45 * sx, 1.12, 0), scale=(1, 0.55, 1), seg=16))
        pads.append(box((0.95, 0.5, 1.05), (0.5 * sx, -3.55, -0.05), bevel=0.15))  # bottes
        pads.append(box((1.05, 0.35, 1.05), (0.5 * sx, -2.5, 0), bevel=0.12))  # genouilleres
        pads.append(box((0.95, 0.35, 0.95), (1.45 * sx, -1.05, 0), bevel=0.12))  # gants
    pads.append(box((2.2, 0.3, 1.25), (0, -1.05, 0), bevel=0.1))  # ceinture
    stripes = []
    for sx in (-1, 1):
        stripes.append(box((0.1, 2.1, 0.06), (0.62 * sx, 0.1, -0.58), bevel=0.02))
        stripes.append(box((0.98, 0.08, 0.06), (0.5 * sx, -2.5, -0.55), bevel=0.02))
    stripes.append(torus(0.36, 0.05, (0, 0.35, -0.6), rot=(90, 0, 0), seg=20, minor_seg=5))
    pack = [
        box((1.7, 2.0, 0.75), (0, 0.15, 0.95), bevel=0.2, segments=3),
        box((1.3, 0.3, 0.5), (0, -0.95, 0.95), bevel=0.1),
        cyl(0.15, 0.65, (-0.6, 1.3, 0.95)),
        cyl(0.15, 0.65, (0.6, 1.3, 0.95)),
        cyl(0.04, 1.2, (0.6, 2.2, 0.95)),
        ball(0.11, (0.6, 2.85, 0.95), seg=8),
    ]
    lights = [box((0.18, 0.18, 0.08), (x, 0.55, 1.34), bevel=0.04) for x in (-0.48, -0.16, 0.16, 0.48)]
    lights += [ball(0.12, (-0.6, 1.66, 0.95), seg=8), ball(0.12, (0.6, 1.66, 0.95), seg=8)]
    ring = [annulus(1.9, 2.15, 0.06, (0, 0, 0), rot=(90, 0, 0)), annulus(2.3, 2.45, 0.05, (0, 0, 0), rot=(90, 0, 0)),
            annulus(2.6, 2.95, 0.04, (0, 0, 0), rot=(90, 0, 0))]
    ring = [group(ring, rot=(18, 0, 10), center=(0, 0.1, 0))]
    rocks = ring_of(10, 2.38, lambda x, z, a: box((0.16, 0.14, 0.16), (x, 0, z), bevel=0.04, rot=(a, a * 2, 0)))
    rocks = [group(rocks, rot=(18, 0, 10), center=(0, 0.1, 0))]
    moons = ring_of(4, 3.1, lambda x, z, a: ball(0.3 if int(a) % 180 == 0 else 0.22, (x, 0.5, z), seg=12))
    return dict(color=purple, pieces={"Torso": (235, 235, 245)}, parts=[
        Part("SpaceHelmet", "Head", (190, 225, 255), bubble, material="Glass", transparency=0.5),
        Part("GoldVisor", "Head", (255, 200, 70), visor, material="Foil"),
        Part("SuitCollar", "Head", WHITE, collar),
        Part("SuitPads", "Torso", WHITE, pads),
        Part("SuitStripes", "Torso", pink, stripes, material="Neon"),
        Part("LifePack", "Torso", WHITE, pack),
        Part("PackLights", "Torso", cyan, lights, material="Neon"),
        Part("PlanetRing", "Torso", pink, ring, material="Neon", transparency=0.15, spin=((0, 1, 0), 30)),
        Part("RingRocks", "Torso", yellow, rocks, material="Neon", spin=((0, 1, 0), 30)),
        Part("Moons", "Torso", yellow, moons, material="Neon", spin=((0, 1, 0), -50)),
    ], effects=[
        fx_particles("stars", "Torso", (0, 0.5, 0), (255, 255, 255), (200, 160, 255)),
        fx_light("Torso", (0, 1, -1.5), (180, 120, 255), 14, 2.5),
    ])


def look_ghost():
    """Cette methode permet de modeliser le Ghost (corps spectral sans jambes, cape dechiree a col en pointes, queue de
    fumee, couronne de flammes spectrales, chaines brisees, lanterne, feux follets en orbite) lorsque le catalogue se
    construit."""
    spirit, chain, cyan = (225, 240, 255), (90, 92, 105), (110, 255, 230)
    tail = []
    for i in range(6):
        t = i / 5
        w = 1.9 * (1 - t) + 0.25
        tail.append(box((w, 0.6, w * 0.6 + 0.1), (0.35 * math.sin(t * 3.2), -1.35 - 0.48 * i, 0.1 + 0.25 * t),
                        bevel=min(0.25, w * 0.3), rot=(10 * t, 0, 12 * math.sin(t * 3.2))))
    # Cape dechiree : bord bas en dents de scie, col en pointes autour de la tete
    cape_pts = [(-1.3, 1.3), (1.3, 1.3), (2.0, -1.2)]
    for k in range(9):
        x = 2.0 - 4.0 * (k + 0.5) / 9
        cape_pts.append((x, -3.2 - 0.6 * (k % 2) - 0.3 * math.sin(k)))
    cape_pts.append((-2.0, -1.2))
    cape = [prism(cape_pts, 0.12, (0, 0, 0.75), rot=(-6, 0, 0))]
    cape += [cone(0.18, 0.7, (0.95 * math.cos(math.radians(d)), 1.55, 0.95 * math.sin(math.radians(d))), verts=4)
             for d in range(-20, 201, 30)]  # col en pointes, sur l'arriere et les cotes
    parts = [Part("GhostTail", "Torso", spirit, tail, material="ForceField"),
             Part("GhostCape", "Torso", (180, 220, 255), cape, material="ForceField", transparency=0.15)]
    for side, sx in (("L", -1), ("R", 1)):
        x = 1.45 * sx
        links = [torus(0.5, 0.1, (x, -0.55, 0), seg=18, minor_seg=6)]
        for i in range(6):
            links.append(torus(0.14, 0.05, (x + 0.1 * sx * i, -0.95 - 0.22 * i, 0.1 * i),
                               rot=(0, 90 * (i % 2), 90), seg=12, minor_seg=5))
        links.append(ball(0.22, (x + 0.65 * sx, -2.35, 0.6), seg=10))  # boulet
        parts.append(Part("Shackle" + side, side == "L" and "LeftLowerArm" or "RightLowerArm", chain, links,
                          material="Metal"))
    lantern = [
        box((0.6, 0.12, 0.6), (1.45, -1.35, -0.45), bevel=0.03),
        box((0.6, 0.12, 0.6), (1.45, -2.15, -0.45), bevel=0.03),
        *[box((0.07, 0.7, 0.07), (1.45 + dx, -1.75, -0.45 + dz), bevel=0.01) for dx in (-0.25, 0.25)
          for dz in (-0.25, 0.25)],
        torus(0.14, 0.04, (1.45, -1.2, -0.45), rot=(90, 0, 0), seg=12, minor_seg=4),
        cone(0.32, 0.3, (1.45, -1.15, -0.45), verts=4),
    ]
    flames = ring_of(6, 0.62, lambda x, z, a: gem(0.13, 0.5 + 0.15 * (int(a) // 60 % 2), (x, HEAD_TOP + 0.45, z),
                                                  verts=5))
    flames.append(gem(0.2, 0.8, (0, HEAD_TOP + 0.7, 0), verts=6))
    parts += [
        Part("Lantern", "RightLowerArm", (40, 42, 50), lantern, material="Metal"),
        Part("LanternFlame", "RightLowerArm", cyan, [gem(0.2, 0.5, (1.45, -1.75, -0.45), verts=8)], material="Neon",
             bob=(0.05, 0.8)),
        Part("SpiritCrown", "Head", cyan, flames, material="Neon", bob=(0.08, 1.6)),
        Part("Wisps", "Torso", cyan, ring_of(6, 2.0, lambda x, z, a: ball(0.18 if int(a) % 120 == 0 else 0.13,
                                                                          (x, 0.4 * math.sin(math.radians(a * 2)), z),
                                                                          seg=10)),
             material="Neon", spin=((0, 1, 0), 70)),
        Part("GhostEyes", "Head", cyan, [box((0.22, 0.32, 0.06), (sx * 0.3, 2.31, -0.73), bevel=0.05)
                                         for sx in (-1, 1)], material="Neon"),
    ]
    return dict(color=(235, 245, 255), material="ForceField",
                hidden=["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"], parts=parts, effects=[
                    fx_particles("wisp", "Torso", (0, -2.5, 0), (180, 255, 240), (255, 255, 255)),
                    fx_light("Torso", (0, 0, -1.5), (110, 255, 230), 12, 2),
                ])


def tech_ring(radius, ticks, nodes):
    """Cette methode permet de modeliser un anneau technologique horizontal (tore fin, graduations, noeuds) autour de
    l'origine lorsque l'on habille le Neon."""
    out = [torus(radius, 0.06, (0, 0, 0), seg=48, minor_seg=6)]
    out += ring_of(ticks, radius, lambda x, z, a: box((0.07, 0.24, 0.07), (x, 0, z), bevel=0.02, segments=1))
    out += ring_of(nodes, radius, lambda x, z, a: box((0.26, 0.26, 0.26), (x, 0, z), bevel=0.07, rot=(0, -a, 45),
                                                      segments=2), phase=math.pi / nodes)
    return out


def look_neon():
    """Cette methode permet de modeliser le Neon (cyber : casque a visiere, oreillettes et antennes, crete, armure de
    plaques a lignes fluo, epaulettes et gantelets, ailes de lames lumineuses, halo segmente, deux anneaux gradues qui
    tournent) lorsque le catalogue se construit."""
    dark, metal, pink, cyan = (40, 40, 55), (70, 75, 95), (255, 60, 200), (60, 255, 255)
    visor = [box((1.62, 0.36, 1.2), (0, 2.32, -0.18), bevel=0.14)]
    mohawk = [box((0.2, 0.36 + 0.12 * (2 - abs(i - 2)), 0.3), (0, HEAD_TOP + 0.15 + 0.06 * (2 - abs(i - 2)),
                                                                   -0.45 + 0.24 * i), bevel=0.05,
                  rot=(-15 + 8 * i, 0, 0)) for i in range(5)]
    gear = []
    for sx in (-1, 1):
        gear.append(cyl(0.34, 0.24, (0.86 * sx, 2.2, 0), rot=(0, 0, 90), verts=16))
        gear.append(cyl(0.04, 0.9, (0.92 * sx, 2.85, 0.15), rot=(0, 0, -12 * sx)))
    tips = [ball(0.11, (1.01 * sx, 3.3, 0.15), seg=10) for sx in (-1, 1)]
    tips += [torus(0.22, 0.05, (0.99 * sx, 2.2, 0), rot=(0, 0, 90), seg=18, minor_seg=5) for sx in (-1, 1)]
    lines = [
        torus(0.5, 0.05, (0, 0.32, -0.66), rot=(90, 0, 0), seg=24, minor_seg=5),
        box((0.08, 1.9, 0.06), (-0.98, 0.15, -0.56), bevel=0.02),
        box((0.08, 1.9, 0.06), (0.98, 0.15, -0.56), bevel=0.02),
        box((1.9, 0.08, 0.06), (0, -0.75, -0.57), bevel=0.02),
        box((0.08, 1.9, 0.06), (-0.6, 0.15, 0.56), bevel=0.02),
        box((0.08, 1.9, 0.06), (0.6, 0.15, 0.56), bevel=0.02),
    ]
    for sx in (-1, 1):
        lines.append(box((0.08, 1.0, 0.06), (0.5 * sx + 0.3 * sx, -1.85, -0.5), bevel=0.02))
        lines.append(box((0.98, 0.08, 0.06), (0.5 * sx, -2.95, -0.5), bevel=0.02))
    armor = [box((1.75, 0.95, 0.16), (0, 0.55, -0.63), bevel=0.06)]
    armor += [box((1.4 - 0.12 * i, 0.2, 0.14), (0, -0.2 - 0.27 * i, -0.6), bevel=0.05) for i in range(3)]
    for sx in (-1, 1):
        armor.append(box((1.05, 0.4, 1.05), (0.5 * sx, -2.5, -0.05), bevel=0.12))  # genouilleres
        armor.append(box((1.0, 0.55, 1.1), (0.5 * sx, -3.6, -0.08), bevel=0.14))  # bottes
    core = [prism([(0.24 * math.cos(math.radians(30 + 60 * k)), 0.24 * math.sin(math.radians(30 + 60 * k)))
                   for k in range(6)], 0.1, (0, 0.55, -0.74))]
    core += [box((0.5, 0.06, 0.05), (0.55 * sx, 0.8, -0.73), bevel=0.02) for sx in (-1, 1)]
    core += [box((0.06, 0.3, 0.05), (0.18 * sx, -2.5, -0.59), bevel=0.02) for sx in (-1, 1)]
    # Ailes : 3 lames de lumiere par cote sur une armature, ancrees en haut du dos
    frame, blades, edges = [box((0.5, 1.6, 0.3), (0, 0.4, 0.72), bevel=0.08)], [], []
    for sx in (-1, 1):
        root = (0.3 * sx, 0.9, 0.85)
        for i in range(3):
            phi = 90 - sx * (28 + 30 * i)
            length = 2.7 - 0.35 * i
            frame.append(box((length * 0.55, 0.14, 0.14), root, bevel=0.04, rot=(0, 0, phi)))
            frame[-1] = place(frame[-1], (0, 0, 0), (0.5 * length * 0.55 * math.cos(math.radians(phi)),
                                                    0.5 * length * 0.55 * math.sin(math.radians(phi)), 0))
            pts = [(0.1, -0.12), (length, -0.32), (length + 0.35, 0.0), (0.1, 0.16)]
            blades.append(prism(pts, 0.06, (root[0], root[1], root[2] + 0.05 + 0.04 * i), rot=(0, 0, phi),
                                bevel=0.015))
            edge_pts = [(0.1, 0.12), (length + 0.35, 0.0), (length + 0.25, 0.08), (0.1, 0.22)]
            edges.append(prism(edge_pts, 0.08, (root[0], root[1], root[2] + 0.03 + 0.04 * i), rot=(0, 0, phi),
                               bevel=0.015))
    halo = []
    for k in range(4):  # quatre arcs symetriques : le halo tourne sur son centre
        a0 = k * 90
        for j in range(6):
            a = math.radians(a0 + j * 11)
            halo.append(box((0.32, 0.12, 0.08), (1.05 * math.cos(a), 1.05 * math.sin(a), 0), bevel=0.03,
                            rot=(0, 0, math.degrees(a) + 90)))
    halo = [group(halo, center=(0, 2.25, 0.95))]
    parts = [
        Part("CyberVisor", "Head", cyan, visor, material="Neon"),
        Part("Mohawk", "Head", pink, mohawk, material="Neon"),
        Part("HelmetGear", "Head", metal, gear, material="Metal"),
        Part("AntennaTips", "Head", pink, tips, material="Neon"),
        Part("NeonLines", "Torso", pink, lines, material="Neon"),
        Part("CyberArmor", "Torso", metal, armor, material="Metal"),
        Part("ArmorCore", "Torso", cyan, core, material="Neon"),
        Part("WingFrame", "Torso", metal, frame, material="Metal"),
        Part("WingBlades", "Torso", cyan, blades, material="Neon", transparency=0.25),
        Part("WingEdges", "Torso", pink, edges, material="Neon"),
        Part("HoloHalo", "Head", pink, halo, material="Neon", spin=((0, 0, 1), -60)),
        Part("RingA", "Torso", cyan, [group(tech_ring(1.95, 16, 4), rot=(20, 0, 0), center=(0, 0.2, 0))],
             material="Neon", spin=((0, 1, 0), 90)),
        Part("RingB", "Torso", pink, [group(tech_ring(2.3, 20, 3), rot=(-15, 0, 25), center=(0, 0.2, 0))],
             material="Neon", spin=((0, 1, 0), -70)),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        arm = side == "L" and "Left" or "Right"
        parts.append(Part("NeonPad" + side, arm + "UpperArm", cyan, [
            box((1.0, 0.24, 1.0), (1.48 * sx, 1.1, 0), bevel=0.08, rot=(0, 0, -12 * sx)),
            box((0.85, 0.2, 0.85), (1.58 * sx, 0.88, 0), bevel=0.07, rot=(0, 0, -22 * sx)),
            box((0.12, 0.6, 0.9), (1.95 * sx, 0.72, 0), bevel=0.04),
        ], material="Neon"))
        parts.append(Part("Gauntlet" + side, arm + "LowerArm", metal, [
            box((0.98, 0.55, 0.98), (1.45 * sx, -0.75, 0), bevel=0.12),
            box((0.2, 0.4, 0.5), (1.97 * sx, -0.7, 0), bevel=0.06),
        ], material="Metal"))
    return dict(color=dark, parts=parts, effects=[
        fx_particles("sparkle", "Torso", (0, 0.5, 0), pink, cyan),
        fx_light("Torso", (0, 1, -1.5), pink, 14, 3),
    ])


def look_king():
    """Cette methode permet de modeliser le Crash King (couronne fermee a deux etages, arceaux, globe et croix, rubis,
    saphirs et perles ; manteau a bordure d'or et hermine mouchetee ; sceptre a globe ; trone dore a dossier festonne,
    velours, colonnes a pommeaux et gemmes ; halo-soleil a rayons alternes) lorsque le catalogue se construit."""
    red, ruby, sapphire, ermine = (200, 20, 40), (255, 40, 70), (60, 130, 255), (250, 250, 250)
    top = HEAD_TOP
    crown = [torus(0.8, 0.13, (0, top + 0.08, 0), seg=32, minor_seg=8),
             torus(0.82, 0.08, (0, top + 0.42, 0), seg=32, minor_seg=6),
             cyl(0.78, 0.36, (0, top + 0.25, 0), verts=16, bevel=0.03)]
    crown += ring_of(8, 0.8, lambda x, z, a: cone(0.17 if int(a) % 90 == 0 else 0.13,
                                                 0.85 if int(a) % 90 == 0 else 0.55, (x, top + 0.75, z), verts=4))
    crown += [torus(0.72, 0.06, (0, top + 0.45, 0), rot=rot, seg=32, minor_seg=6) for rot in ((90, 0, 0),
                                                                                         (90, 90, 0))]
    crown += [ball(0.2, (0, top + 1.25, 0), seg=14), box((0.1, 0.5, 0.1), (0, top + 1.6, 0), bevel=0.03),
              box((0.34, 0.1, 0.1), (0, top + 1.65, 0), bevel=0.03)]
    gems = ring_of(4, 0.88, lambda x, z, a: gem(0.15, 0.34, (x, top + 0.25, z), rot=(90, -a - 90, 0)),
                   phase=math.pi / 2)
    sapphires = ring_of(4, 0.88, lambda x, z, a: gem(0.11, 0.26, (x, top + 0.25, z), rot=(90, -a - 90, 0)),
                        phase=math.pi / 4)
    pearls = ring_of(8, 0.8, lambda x, z, a: ball(0.09, (x, top + 0.75 + (0.45 if int(a) % 90 == 0 else 0.3), z),
                                                  seg=8))
    robe_pts = [(-1.15, 1.15), (1.15, 1.15), (1.9, -3.75), (-1.9, -3.75)]
    robe = [prism(robe_pts, 0.14, (0, 0, 0.74), rot=(-8, 0, 0))]
    trim = []
    for (x0, y0), (x1, y1) in ((robe_pts[1], robe_pts[2]), (robe_pts[2], robe_pts[3]), (robe_pts[3], robe_pts[0])):
        length = math.hypot(x1 - x0, y1 - y0)
        ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
        trim.append(place(box((length + 0.1, 0.18, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, 0), bevel=0.05,
                              rot=(0, 0, ang)), rot=(-8, 0, 0), center=(0, 0, 0.72)))
    trim += [box((0.12, 0.12, 0.12), (sx * 0.62, y, -0.6), bevel=0.03) for sx in (-1, 1) for y in (0.6, 0.1, -0.4)]
    fur = [
        box((2.4, 0.42, 1.5), (0, 1.12, 0.12), bevel=0.2, segments=4),
        box((0.28, 4.4, 0.18), (-1.45, -1.5, 0.92), bevel=0.08, rot=(-8, 0, 9)),
        box((0.28, 4.4, 0.18), (1.45, -1.5, 0.92), bevel=0.08, rot=(-8, 0, -9)),
    ]
    spots = [box((0.09, 0.16, 0.05), (x, 1.12, -0.64), bevel=0.02) for x in (-0.9, -0.45, 0.0, 0.45, 0.9)]
    spots += [box((0.09, 0.16, 0.05), (x, 1.34, 0.4), bevel=0.02) for x in (-0.7, 0.0, 0.7)]
    scepter = [
        cyl(0.09, 2.6, (1.45, -1.1, -0.45)),
        cyl(0.17, 0.16, (1.45, 0.2, -0.45)),
        cyl(0.14, 0.12, (1.45, -0.5, -0.45)),
        cyl(0.14, 0.12, (1.45, -1.6, -0.45)),
        cyl(0.17, 0.2, (1.45, -2.35, -0.45)),
        torus(0.3, 0.05, (1.45, 0.62, -0.45), rot=(90, 0, 0), seg=20, minor_seg=5),
        box((0.08, 0.36, 0.08), (1.45, 1.05, -0.45), bevel=0.02),
        box((0.26, 0.08, 0.08), (1.45, 1.08, -0.45), bevel=0.02),
    ]
    scepter_gem = [ball(0.27, (1.45, 0.62, -0.45), seg=14)]
    # Trone : dossier a sommet festonne, montants a pommeaux, accoudoirs a volutes, socle a deux marches
    back_pts = [(-1.7, -3.6), (1.7, -3.6), (1.7, 2.2)]
    for k in range(1, 12):
        a = math.radians(180 * k / 12)
        r = 1.95 if k % 2 else 1.7
        back_pts.append((r * math.cos(a), 2.2 + r * math.sin(a) * 1.15))
    back_pts.append((-1.7, 2.2))
    throne = [prism(back_pts, 0.4, (0, 0, 1.85), bevel=0.08)]
    for sx in (-1, 1):
        throne += [cyl(0.24, 6.0, (2.05 * sx, -0.6, 1.6), verts=12), ball(0.34, (2.05 * sx, 2.65, 1.6), seg=12),
                   cone(0.18, 0.6, (2.05 * sx, 3.2, 1.6), verts=8),
                   box((0.45, 0.35, 2.4), (2.05 * sx, -1.0, 0.6), bevel=0.12),
                   cyl(0.24, 0.5, (2.05 * sx, -1.0, -0.6), rot=(90, 0, 0), verts=12),
                   box((0.4, 2.4, 0.4), (2.05 * sx, -2.4, -0.4), bevel=0.1)]
    throne += [box((4.6, 0.3, 2.6), (0, -3.68, 1.0), bevel=0.08), box((5.2, 0.16, 3.0), (0, -3.78, 1.05), bevel=0.05)]
    cushion_pts = [(p[0] * 0.78, -3.0 + (p[1] + 3.6) * 0.86) for p in back_pts]
    cushion = [prism(cushion_pts, 0.12, (0, 0, 1.6), bevel=0.04)]
    tgems = []
    for k in range(1, 12, 2):
        a = math.radians(180 * k / 12)
        tgems.append(gem(0.14, 0.32, (1.72 * math.cos(a), 2.2 + 1.72 * math.sin(a) * 1.15, 1.6), rot=(90, 0, 0)))
    tgems += [gem(0.18, 0.4, (2.05 * sx, 1.2, 1.32), rot=(90, 0, 0)) for sx in (-1, 1)]
    trubies = [gem(0.3, 0.6, (0, 4.35, 1.6), rot=(90, 0, 0))]
    trubies += [gem(0.14, 0.3, (2.05 * sx, -0.1, 1.33), rot=(90, 0, 0)) for sx in (-1, 1)]
    halo = [torus(1.05, 0.08, (0, 0, 0), rot=(90, 0, 0), seg=40, minor_seg=6),
            torus(0.82, 0.05, (0, 0, 0), rot=(90, 0, 0), seg=40, minor_seg=5)]
    for k in range(24):
        a = 2 * math.pi * k / 24
        long_ray = k % 2 == 0
        r = 1.42 if long_ray else 1.3
        halo.append(cone(0.11 if long_ray else 0.08, 0.6 if long_ray else 0.35, (r * math.cos(a), r * math.sin(a), 0),
                         rot=(0, 0, math.degrees(a) - 90), verts=4))
        if long_ray:
            halo.append(ball(0.07, (1.8 * math.cos(a), 1.8 * math.sin(a), 0), seg=6))
    halo = [group(halo, center=(0, 2.35, 0.95))]
    return dict(color=(255, 200, 40), material="Foil", parts=[
        Part("Crown", "Head", GOLD, crown, material="Foil"),
        Part("CrownGems", "Head", ruby, gems, material="Neon"),
        Part("CrownSapphires", "Head", sapphire, sapphires, material="Neon"),
        Part("CrownPearls", "Head", WHITE, pearls),
        Part("Robe", "Torso", red, robe, material="Fabric"),
        Part("RobeTrim", "Torso", GOLD, trim, material="Foil"),
        Part("Ermine", "Torso", ermine, fur, material="Fabric"),
        Part("ErmineSpots", "Torso", BLACK, spots),
        Part("Scepter", "RightLowerArm", GOLD, scepter, material="Foil"),
        Part("ScepterGem", "RightLowerArm", ruby, scepter_gem, material="Neon"),
        Part("Throne", "Torso", (255, 190, 40), throne, material="Foil"),
        Part("ThroneCushion", "Torso", red, cushion, material="Fabric"),
        Part("ThroneSapphires", "Torso", sapphire, tgems, material="Neon"),
        Part("ThroneRubies", "Torso", ruby, trubies, material="Neon"),
        Part("SunHalo", "Head", (255, 215, 70), halo, material="Neon", spin=((0, 0, 1), 40)),
    ], effects=[
        fx_particles("sparkle", "Torso", (0, 1, 0), (255, 220, 90), (255, 255, 255)),
        fx_light("Torso", (0, 2, -2), (255, 200, 80), 18, 3),
    ])


def look_void():
    """Cette methode permet de modeliser le Void (trou noir dans le dos : horizon noir, anneau de photons, trois
    tourbillons d'accretion qui tournent de plus en plus vite vers le centre ; couronne d'eclats de cristal noir a
    coeurs violets ; ailes d'eclats ; fissures et yeux violets ; eclats en orbite) lorsque le catalogue se construit."""
    black, purple, magenta, hot, deep = (14, 10, 22), (170, 60, 255), (235, 80, 255), (255, 170, 110), (90, 30, 170)
    # Trou noir haut dans le dos (au-dessus des epaules) pour rester visible de face
    c = (0, 1.7, 2.0)
    core = [ball(1.3, c, scale=(1, 1, 0.6), seg=28)]
    photon = [torus(1.38, 0.08, (c[0], c[1], c[2] - 0.1), rot=(90, 0, 0), seg=48, minor_seg=6),
              torus(2.05, 0.04, (c[0], c[1], c[2] - 0.12), rot=(90, 0, 0), seg=48, minor_seg=5)]
    inner = [torus(1.6, 0.14, (c[0], c[1], c[2] - 0.05), rot=(90, 0, 0), seg=48, minor_seg=8)]
    mid = []
    outer = [annulus(3.3, 3.55, 0.05, (c[0], c[1], c[2] + 0.1))]
    for k in range(6):
        inner += spiral_arm(c, k * math.pi / 3, 1.5, 2.2, 1.4, 8, 0.34, 0.12, thickness=0.08, z=-0.06)
        mid += spiral_arm(c, k * math.pi / 3 + 0.4, 1.9, 3.0, 1.5, 10, 0.4, 0.12, thickness=0.07, z=0.0)
        outer += spiral_arm(c, k * math.pi / 3 + 0.9, 2.5, 3.5, 1.3, 9, 0.42, 0.14, thickness=0.06, z=0.06)
    outer += [box((0.24, 0.18, 0.14), (c[0] + 3.42 * math.cos(math.radians(a)),
                                       c[1] + 3.42 * math.sin(math.radians(a)), c[2] + 0.05), bevel=0.04,
                  rot=(a, a, a)) for a in range(0, 360, 30)]
    cracks = [
        box((0.07, 0.6, 0.05), (-0.3, 0.6, -0.57), bevel=0.02, rot=(0, 0, 25)),
        box((0.07, 0.5, 0.05), (-0.15, 0.15, -0.57), bevel=0.02, rot=(0, 0, -30)),
        box((0.07, 0.6, 0.05), (0.35, -0.2, -0.57), bevel=0.02, rot=(0, 0, 35)),
        box((0.07, 0.45, 0.05), (0.55, 0.45, -0.57), bevel=0.02, rot=(0, 0, -20)),
        box((0.07, 0.5, 0.05), (-0.6, -0.5, -0.57), bevel=0.02, rot=(0, 0, 15)),
        box((0.07, 0.5, 0.05), (-0.5, -1.9, -0.5), bevel=0.02, rot=(0, 0, 20)),
        box((0.07, 0.6, 0.05), (0.45, -2.9, -0.5), bevel=0.02, rot=(0, 0, -25)),
        box((0.07, 0.4, 0.05), (0.55, -1.6, -0.5), bevel=0.02, rot=(0, 0, 10)),
    ]
    eyes = [box((0.24, 0.3, 0.06), (sx * 0.3, 2.31, -0.73), bevel=0.05) for sx in (-1, 1)]
    heights = [1.25, 0.7, 0.95, 0.6, 0.95, 0.7, 1.25, 0.8]
    crown = [torus(0.8, 0.1, (0, HEAD_TOP + 0.05, 0), seg=32, minor_seg=6)]
    cores = []
    for i, h in enumerate(heights):
        a = 2 * math.pi * i / len(heights) + math.pi / 2
        x, z = 0.8 * math.cos(a), 0.8 * math.sin(a)
        tilt_x, tilt_z = 14 * math.sin(a), -14 * math.cos(a)
        crown.append(shard(0.16, h, (x, HEAD_TOP, z), rot=(tilt_x, 0, tilt_z), verts=5))
        cores.append(gem(0.08, 0.22, (x * 1.12, HEAD_TOP + h * 0.55, z * 1.12), verts=5))
    crown.append(shard(0.22, 1.6, (0, HEAD_TOP + 0.05, -0.75), verts=5))  # grand eclat frontal
    cores.append(gem(0.13, 0.35, (0, HEAD_TOP + 0.75, -0.95), verts=6))
    wings, tips = [], []
    for sx in (-1, 1):
        for i in range(3):
            ang = sx * (40 + 28 * i)
            length = 2.8 - 0.45 * i
            root = (0.35 * sx, 0.8 - 0.25 * i, 1.0)
            wings.append(shard(0.22 - 0.03 * i, length, root, rot=(0, 0, -ang), verts=5))
            a = math.radians(90 - ang)
            tips.append(gem(0.12, 0.34, (root[0] + length * 0.97 * math.cos(a), root[1] + length * 0.97 * math.sin(a),
                                         root[2] - 0.05), rot=(0, 0, -ang), verts=5))
            # Nervure lumineuse sur la face avant de l'eclat
            tips.append(box((0.06, length * 0.7, 0.04), (root[0] + length * 0.4 * math.cos(a),
                                                         root[1] + length * 0.4 * math.sin(a), root[2] - 0.2),
                            bevel=0.015, rot=(0, 0, -ang), segments=1))
    shards = ring_of(6, 2.35, lambda x, z, a: gem(0.2 if int(a) % 120 == 0 else 0.15, 0.65,
                                                  (x, 0.35 * (1 if int(a) % 120 == 0 else -1), z), rot=(20, a, 0),
                                                  verts=5))
    return dict(color=(24, 20, 36), parts=[
        Part("VoidCore", "Torso", black, core),
        Part("PhotonRing", "Torso", (245, 215, 255), photon, material="Neon"),
        Part("AccretionHot", "Torso", hot, inner, material="Neon", spin=((0, 0, 1), 140)),
        Part("Accretion", "Torso", magenta, mid, material="Neon", spin=((0, 0, 1), 90)),
        Part("AccretionOuter", "Torso", deep, outer, material="Neon", transparency=0.25, spin=((0, 0, 1), 45)),
        Part("VoidCracks", "Torso", purple, cracks, material="Neon"),
        Part("VoidEyes", "Head", purple, eyes, material="Neon"),
        Part("VoidCrown", "Head", (35, 25, 55), crown, material="Glass", transparency=0.1),
        Part("CrownCores", "Head", magenta, cores, material="Neon"),
        Part("VoidWings", "Torso", (85, 40, 140), wings, material="Glass", transparency=0.15),
        Part("WingTips", "Torso", magenta, tips, material="Neon"),
        Part("VoidShards", "Torso", deep, shards, material="Neon", spin=((0, 1, 0), -55)),
    ], effects=[
        fx_particles("vortex", "Torso", (0, 1.7, 2.0), (190, 90, 255), (40, 0, 80)),
        fx_light("Torso", (0, 1, 0), (170, 60, 255), 16, 3),
    ])


def look_cosmic():
    """Cette methode permet de modeliser le Cosmic (gardien cosmique en armure doree : galaxie spirale a quatre bras
    et etoiles semees qui tourne dans le dos, cerclee d'or et de gemmes, coeur lumineux ; couronne a pointes et grande
    etoile flottante ; epaulieres a gemmes ; planetes annelees en orbite) lorsque le catalogue se construit."""
    indigo, magenta, cyan, core_col = (70, 40, 170), (255, 70, 220), (90, 220, 255), (255, 245, 200)
    starc, deep = (255, 230, 90), (35, 15, 95)
    c = (0, 1.1, 1.85)
    disc = [cyl(3.05, 0.06, (c[0], c[1], c[2] + 0.1), rot=(90, 0, 0), verts=56, bevel=0.02)]
    arms_a = spiral_arm(c, 0.0, 0.5, 2.9, 3.4, 24, 0.7, 0.16, z=-0.02) + \
        spiral_arm(c, math.pi, 0.5, 2.9, 3.4, 24, 0.7, 0.16, z=-0.02)
    arms_b = spiral_arm(c, math.pi / 2, 0.5, 2.7, 3.2, 22, 0.55, 0.14, z=-0.04) + \
        spiral_arm(c, 3 * math.pi / 2, 0.5, 2.7, 3.2, 22, 0.55, 0.14, z=-0.04)
    rng = random.Random(7)
    stars = []
    for _ in range(16):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(0.9, 2.9)
        s = rng.uniform(0.13, 0.26)
        for sign in (1, -1):
            stars.append(star(s, s * 0.4, 0.05, (c[0] + sign * r * math.cos(a), c[1] + sign * r * math.sin(a),
                                                 c[2] - 0.1), rot=(0, 0, rng.uniform(0, 72)), points=4))
    core = [ball(0.55, c, scale=(1, 1, 0.6), seg=20), torus(0.82, 0.06, c, rot=(90, 0, 0), seg=32, minor_seg=5)]
    rim = [torus(3.15, 0.1, (c[0], c[1], c[2] + 0.08), rot=(90, 0, 0), seg=64, minor_seg=6)]
    rim += [ball(0.12, (c[0] + 3.15 * math.cos(math.radians(a)), c[1] + 3.15 * math.sin(math.radians(a)), c[2]),
                 seg=8) for a in range(15, 360, 30)]
    rim_gems = [gem(0.18, 0.4, (c[0] + 3.15 * math.cos(math.radians(a)), c[1] + 3.15 * math.sin(math.radians(a)),
                                c[2] - 0.05), rot=(90, 0, 0)) for a in range(0, 360, 30)]
    top = HEAD_TOP
    crown = [torus(0.8, 0.11, (0, top + 0.08, 0), seg=32, minor_seg=6)]
    crown += ring_of(10, 0.8, lambda x, z, a: cone(0.12, 0.9 if int(round(a)) % 72 == 0 else 0.5,
                                                  (x, top + 0.55 if int(round(a)) % 72 == 0 else top + 0.35, z),
                                                  verts=4))
    crown_gems = ring_of(5, 0.88, lambda x, z, a: gem(0.12, 0.28, (x, top + 0.1, z), rot=(90, -a - 90, 0)),
                         phase=math.pi / 5)
    big_star = [star(0.5, 0.22, 0.14, (0, top + 1.5, 0)), star(0.3, 0.13, 0.16, (0, top + 1.5, -0.02))]
    armor = [torus(0.5, 0.07, (0, 0.4, -0.62), rot=(90, 0, 0), seg=28, minor_seg=6),
             box((2.15, 0.28, 1.25), (0, -1.05, 0), bevel=0.1),
             box((0.5, 0.5, 0.12), (0, -1.05, -0.66), bevel=0.08, rot=(0, 0, 45))]
    for sx in (-1, 1):
        armor += [box((1.05, 0.35, 1.05), (0.5 * sx, -2.5, -0.02), bevel=0.12),
                  box((0.95, 0.4, 0.95), (1.45 * sx, -0.95, 0), bevel=0.12)]
    chest = [star(0.38, 0.17, 0.1, (0, 0.4, -0.68))]
    chest += [gem(0.09, 0.22, (0.5 * sx, -2.5, -0.58), rot=(90, 0, 0)) for sx in (-1, 1)]
    parts = [
        Part("GalaxyDisc", "Torso", deep, disc, material="Neon", transparency=0.1, spin=((0, 0, 1), 25)),
        Part("GalaxyArmsA", "Torso", magenta, arms_a, material="Neon", spin=((0, 0, 1), 25)),
        Part("GalaxyArmsB", "Torso", cyan, arms_b, material="Neon", spin=((0, 0, 1), 25)),
        Part("GalaxyStars", "Torso", WHITE, stars, material="Neon", spin=((0, 0, 1), 25)),
        Part("GalaxyCore", "Torso", core_col, core, material="Neon"),
        Part("GalaxyRim", "Torso", GOLD, rim, material="Foil"),
        Part("RimGems", "Torso", cyan, rim_gems, material="Neon"),
        Part("StarCrown", "Head", GOLD, crown, material="Foil"),
        Part("CrownGems", "Head", magenta, crown_gems, material="Neon"),
        Part("CrownStar", "Head", starc, big_star, material="Neon", spin=((0, 1, 0), 60), bob=(0.12, 2.0)),
        Part("CosmicArmor", "Torso", GOLD, armor, material="Foil"),
        Part("ArmorGems", "Torso", cyan, chest, material="Neon"),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        pad = [ball(0.62, (1.47 * sx, 1.12, 0), scale=(1, 0.55, 1), seg=18)]
        pad += [cone(0.12, 0.55, (1.47 * sx + 0.25 * sx * k, 1.45, -0.3 + 0.3 * k), rot=(0, 0, -25 * sx), verts=4)
                for k in range(3)]
        parts.append(Part("Pauldron" + side, ("Left" if side == "L" else "Right") + "UpperArm", GOLD, pad,
                          material="Foil"))
    planets = ring_of(4, 3.0, lambda x, z, a: ball(0.32 if int(a) % 180 == 0 else 0.24, (x, 0.25, z), seg=14))
    rings = ring_of(4, 3.0, lambda x, z, a: annulus(0.42, 0.6 if int(a) % 180 == 0 else 0.48, 0.03, (x, 0.25, z),
                                                    rot=(70, 0, 20)))
    parts += [
        Part("CosmicMoons", "Torso", (110, 255, 225), planets, material="Neon", spin=((0, 1, 0), -35)),
        Part("MoonRings", "Torso", magenta, rings, material="Neon", spin=((0, 1, 0), -35)),
    ]
    return dict(color=indigo, pieces={"Torso": (55, 28, 140)}, parts=parts, effects=[
        fx_particles("stars", "Torso", (0, 0.5, 0), (255, 255, 255), (255, 120, 230)),
        fx_light("Torso", (0, 1, -1.5), (220, 120, 255), 18, 3),
    ])


LOOKS = {
    "crash": lambda: dict(color=(255, 205, 40), parts=[]),
    "rookie": look_rookie,
    "traffic": look_traffic,
    "mint": look_mint,
    "biker": look_biker,
    "nerd": look_nerd,
    "ocean": look_ocean,
    "hero": look_hero,
    "pilot": look_pilot,
    "ice": look_ice,
    "toxic": look_toxic,
    "royal": look_royal,
    "gold": look_gold,
    "lava": look_lava,
    "diamond": look_diamond,
    "galaxy": look_galaxy,
    "ghost": look_ghost,
    "neon": look_neon,
    "king": look_king,
    "void": look_void,
    "cosmic": look_cosmic,
}


# --------------------------------------------------------------------------------------------------------------------
# Assemblage, mesures, export
# --------------------------------------------------------------------------------------------------------------------


def uv_project(obj):
    """Cette methode permet de deplier une piece en projection cubique (les materiaux Roblox des MeshPart suivent les
    UV du maillage) lorsqu'elle est terminee."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=2.0)
    bpy.ops.object.mode_set(mode="OBJECT")


def assemble(dummy_id, part):
    """Cette methode permet de fusionner les formes d'une piece ajoutee en un objet nomme <id>_<Piece>, deplie et
    adouci, lorsque le modele d'un mannequin se construit ; renvoie l'objet."""
    obj = merge(part.shapes)
    name = f"{dummy_id}_{part.name}"
    obj.name = name
    obj.data.name = name
    obj.data.materials.clear()
    obj.data.materials.append(export_material())
    vs = np.array([tuple(v.co) for v in obj.data.vertices])
    lo, hi = vs.min(axis=0), vs.max(axis=0)
    bpy.context.scene.cursor.location = tuple((lo + hi) / 2)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    uv_project(obj)
    return obj


def bounds(obj, piece):
    """Cette methode permet de mesurer la boite d'une piece ajoutee (taille, decalage du centre par rapport a sa piece
    porteuse, repere Roblox) lorsque l'export se prepare."""
    vs = np.array([tuple(br(obj.matrix_world @ v.co)) for v in obj.data.vertices])
    lo, hi = vs.min(axis=0), vs.max(axis=0)
    size = hi - lo
    mid = (hi + lo) / 2
    pc = np.array(PIECES[piece][1], dtype=float)
    return [round(float(v), 3) for v in size], [round(float(v), 3) for v in (mid - pc)], int(
        sum(len(p.vertices) - 2 for p in obj.data.polygons))


def lua_num(v):
    """Cette methode permet d'ecrire un nombre court en Luau lorsque le module de donnees est genere."""
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def lua_vec(v):
    """Cette methode permet d'ecrire un Vector3 Luau lorsque le module de donnees est genere."""
    return "Vector3.new(" + ", ".join(lua_num(x) for x in v) + ")"


def lua_rgb(c):
    """Cette methode permet d'ecrire un Color3 Luau (sRGB 0-255) lorsque le module de donnees est genere."""
    return f"Color3.fromRGB({c[0]}, {c[1]}, {c[2]})"


def write_luau(catalog):
    """Cette methode permet de generer src/shared/DummyModels.luau (pieces ajoutees et looks des mannequins) lorsque
    l'export est fini ; le fichier est ensuite formate par StyLua (tools/check.sh --fix)."""
    out = [
        "-- GENERE par assets/dummy/build_collection.py (#66) : ne pas modifier a la main, relancer le script.",
        "-- Modeles des mannequins de collection : pieces ajoutees (maillages de assets/dummy/export/collection.fbx,",
        "-- piece porteuse, boite, decalage du centre, couleur, materiau, animation) et look de chaque mannequin",
        "-- (couleur du corps, materiau, couleurs par piece, pieces masquees, pieces ajoutees, effets).",
        "local DummyModels = {}",
        "",
        "export type Addon = {",
        "\tpiece: string,",
        "\tsize: Vector3,",
        "\toffset: Vector3,",
        "\tcolor: Color3,",
        "\tmaterial: Enum.Material,",
        "\ttransparency: number?,",
        "\tspin: { axis: Vector3, speed: number }?,",
        "\tbob: { amplitude: number, period: number }?,",
        "}",
        "",
        "export type Effect = {",
        "\tkind: string,",
        "\tpreset: string?,",
        "\tpiece: string,",
        "\toffset: Vector3,",
        "\tcolor: Color3,",
        "\tcolor2: Color3?,",
        "\trange: number?,",
        "\tbrightness: number?,",
        "\tsize: number?, -- multiplicateur de taille des particules (ou du faisceau)",
        "\trate: number?, -- multiplicateur du debit des particules",
        "\theight: number?, -- faisceau : hauteur (studs, echelle 1)",
        "\twidth: number?, -- faisceau : largeur (studs, echelle 1)",
        "}",
        "",
        "export type Look = {",
        "\tcolor: Color3,",
        "\tmaterial: Enum.Material?,",
        "\tpieceColors: { [string]: Color3 }?,",
        "\thidden: { string }?,",
        "\taccessories: { string },",
        "\teffects: { Effect }?,",
        "}",
        "",
        "DummyModels.ADDONS = {",
    ]
    for dummy_id, look in catalog.items():
        for p in look["parts"]:
            fields = [
                f'piece = "{p["piece"]}"',
                f"size = {lua_vec(p['size'])}",
                f"offset = {lua_vec(p['offset'])}",
                f"color = {lua_rgb(p['color'])}",
                f"material = Enum.Material.{p['material']}",
            ]
            if p["transparency"]:
                fields.append(f"transparency = {lua_num(p['transparency'])}")
            if p["spin"]:
                fields.append(f"spin = {{ axis = {lua_vec(p['spin'][0])}, speed = {lua_num(p['spin'][1])} }}")
            if p["bob"]:
                fields.append(f"bob = {{ amplitude = {lua_num(p['bob'][0])}, period = {lua_num(p['bob'][1])} }}")
            out.append(f"\t{p['mesh']} = {{ " + ", ".join(fields) + " },")
    out += ["} :: { [string]: Addon }", "", "DummyModels.LOOKS = {"]
    for dummy_id, look in catalog.items():
        fields = [f"color = {lua_rgb(look['color'])}"]
        if look.get("material"):
            fields.append(f"material = Enum.Material.{look['material']}")
        if look.get("pieces"):
            pcs = ", ".join(f"{k} = {lua_rgb(v)}" for k, v in sorted(look["pieces"].items()))
            fields.append(f"pieceColors = {{ {pcs} }}")
        if look.get("hidden"):
            fields.append("hidden = { " + ", ".join(f'"{h}"' for h in look["hidden"]) + " }")
        fields.append("accessories = { " + ", ".join(f'"{p["mesh"]}"' for p in look["parts"]) + " }")
        if look.get("effects"):
            effects = []
            for e in look["effects"]:
                ef = [f'kind = "{e["kind"]}"', f'piece = "{e["piece"]}"', f"offset = {lua_vec(e['offset'])}",
                      f"color = {lua_rgb(e['color'])}"]
                if e["kind"] == "particles":
                    ef.insert(1, f'preset = "{e["preset"]}"')
                    ef.append(f"color2 = {lua_rgb(e['color2'])}")
                else:
                    ef += [f"range = {lua_num(e['range'])}", f"brightness = {lua_num(e['brightness'])}"]
                effects.append("{ " + ", ".join(ef) + " }")
            fields.append("effects = { " + ", ".join(effects) + " }")
        out.append(f"\t{dummy_id} = {{ " + ", ".join(fields) + " },")
    out += ["} :: { [string]: Look }", "", "return DummyModels", ""]
    with open(LUAU_OUT, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(out))
    print("[collection] module", LUAU_OUT)


# --------------------------------------------------------------------------------------------------------------------
# Apercus
# --------------------------------------------------------------------------------------------------------------------


def setup_render():
    """Cette methode permet de preparer le rendu des apercus (Eevee, fond transparent, soleil, ciel, camera
    orthographique trois-quarts face) lorsque les modeles sont construits ; renvoie la camera."""
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 520
    scene.render.resolution_y = 600
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.55, 0.6, 0.7, 1)
    bg.inputs["Strength"].default_value = 0.9
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(150)))
    bpy.context.active_object.data.energy = 3.5
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def frame_camera(cam, objs):
    """Cette methode permet de cadrer la camera trois-quarts face sur les objets visibles lorsque l'on rend un
    apercu."""
    pts = []
    for o in objs:
        pts += [o.matrix_world @ v.co for v in o.data.vertices]
    pts = np.array([tuple(p) for p in pts])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    center = Vector(tuple((lo + hi) / 2))
    direction = Vector((0.42, 1.0, 0.22)).normalized()
    cam.location = center + direction * 40
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    # Taille projetee : etendue des points dans le plan de la camera
    rot = cam.rotation_euler.to_matrix()
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    xs = [Vector(tuple(p)).dot(right) for p in pts]
    ys = [Vector(tuple(p)).dot(up) for p in pts]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    # Rendu plus haut que large : ortho_scale = hauteur visible, largeur visible = ortho_scale * 520 / 600
    cam.data.ortho_scale = max(h, w * 600 / 520, 7.6) * 1.08
    # Recentrer sur le centre projete
    cx = (max(xs) + min(xs)) / 2
    cy = (max(ys) + min(ys)) / 2
    c0 = center.dot(right), center.dot(up)
    cam.location += right * (cx - c0[0]) + up * (cy - c0[1])


def particle_specks(effect, rng):
    """Cette methode permet de figurer un emetteur de particules par des eclats lumineux (cubes emissifs semes autour
    de la piece) lorsque l'on rend l'apercu d'un mannequin anime."""
    piece = effect["piece"]
    base = Vector(PIECES[piece][1]) + Vector(effect["offset"])
    preset = effect["preset"]
    count, radius, size = {"sparkle": (16, 2.2, 0.16), "fire": (14, 0.6, 0.22), "embers": (16, 2.2, 0.12),
                           "wisp": (10, 1.0, 0.3), "stars": (22, 2.8, 0.16), "vortex": (18, 2.4, 0.14),
                           "aura": (0, 0, 0)}[preset]
    out = []
    for i in range(count):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if d.length > 1:
            d.normalize()
        if preset == "fire":
            d = Vector((d.x * 0.8, abs(d.y) * 2.2, d.z * 0.8))
        p = base + d * radius
        col = effect["color"] if i % 2 == 0 else effect["color2"]
        s = size * rng.uniform(0.6, 1.3)
        o = box((s, s, s), tuple(p), bevel=0, rot=(rng.uniform(0, 90), rng.uniform(0, 90), 0))
        o.data.materials.clear()
        o.data.materials.append(roblox_material(col, "Neon"))
        out.append(o)
    return out


def render_dummy(cam, dummy_id, look, body, addons, materials):
    """Cette methode permet de rendre l'apercu d'un mannequin (corps teinte ou au materiau du look, pieces masquees,
    pieces ajoutees, effets figures) dans export/collection/<id>.png lorsque l'export est fini."""
    body_mat_default, dark, target = materials
    temp = []
    for name, obj in body.items():
        obj.hide_render = name in look.get("hidden", [])
        slots = obj["orig_slots"]
        for i, slot in enumerate(obj.material_slots):
            orig = slots[i]
            if look.get("material"):
                slot.material = roblox_material(look["color"], look["material"])
            elif orig == "Body":
                tint = look.get("pieces", {}).get(name, look["color"])
                slot.material = body_tint(tint, body_mat_default)
            else:
                slot.material = {"Dark": dark, "Target": target}[orig]
    shown = []
    for o in addons.values():
        o.hide_render = True
    for p in look["parts"]:
        o = addons[p['mesh']]
        o.hide_render = False
        o.material_slots[0].material = roblox_material(p["color"], p["material"], p["transparency"])
        shown.append(o)
    rng = random.Random(dummy_id)
    lights = []
    for e in look.get("effects", []):
        if e["kind"] == "particles":
            temp += particle_specks(e, rng)
        elif e["kind"] == "light":
            bpy.ops.object.light_add(type="POINT", location=tuple(rb(Vector(PIECES[e["piece"]][1]) +
                                                                     Vector(e["offset"]))))
            light = bpy.context.active_object
            light.data.color = tuple(lin(c) for c in e["color"])
            light.data.energy = 120 * e["brightness"]
            lights.append(light)
    visible = [o for n, o in body.items() if not o.hide_render] + shown
    frame_camera(cam, visible)
    bpy.context.scene.render.filepath = os.path.join(RENDERS, f"{dummy_id}.png")
    bpy.ops.render.render(write_still=True)
    for o in temp + lights:
        bpy.data.objects.remove(o, do_unlink=True)


_TINTS = {}


def body_tint(rgb, template):
    """Cette methode permet de donner le materiau d'atlas du corps teinte d'une couleur (zones transparentes de
    l'atlas = couleur de la piece) lorsque l'on rend un apercu."""
    key = tuple(rgb)
    if key not in _TINTS:
        mat = template.copy()
        mix = next(n for n in mat.node_tree.nodes if n.type == "MIX")
        mix.inputs[6].default_value = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
        _TINTS[key] = mat
    return _TINTS[key]


def main():
    """Cette methode permet d'enchainer modelisation des 21 mannequins, mesures, export FBX, JSON et module Luau, puis
    apercus lorsque Blender lance le script."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    os.makedirs(RENDERS, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    catalog = {}
    addons = {}
    names = set()
    for dummy_id, make in LOOKS.items():
        look = make()
        parts = []
        for part in look["parts"]:
            obj = assemble(dummy_id, part)
            assert obj.name not in names, "nom de piece en double : " + obj.name
            names.add(obj.name)
            size, offset, tris = bounds(obj, part.piece)
            addons[obj.name] = obj
            parts.append({"name": part.name, "mesh": obj.name, "piece": part.piece, "size": size, "offset": offset,
                          "color": list(part.color), "material": part.material,
                          "transparency": part.transparency,
                          "spin": [list(part.spin[0]), part.spin[1]] if part.spin else None,
                          "bob": list(part.bob) if part.bob else None, "triangles": tris})
        entry = {k: v for k, v in look.items() if k != "parts"}
        entry["parts"] = parts
        catalog[dummy_id] = entry
        print(f"[collection] {dummy_id}: {len(parts)} pieces, {sum(p['triangles'] for p in parts)} triangles")

    with open(os.path.join(EXPORT, "collection.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=1)
    write_luau(catalog)

    # Export : pieces ajoutees seules (le corps reste dans dummy.fbx, deja publie)
    bpy.ops.object.select_all(action="DESELECT")
    for o in addons.values():
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(EXPORT, "collection.fbx"),
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        mesh_smooth_type="FACE",
        axis_forward="-Z",
        axis_up="Y",
    )
    if "--no-render" in argv:
        return

    # Corps du mannequin (memes pieces que build_dummy.py), atlas ecrit dans un dossier temporaire
    bd.EXPORT = os.path.join(bpy.app.tempdir or os.environ.get("TEMP", "."), "fad_atlas")
    os.makedirs(bd.EXPORT, exist_ok=True)
    atlas = bd.build_atlas()
    body_mat = bd.make_material("Body", atlas, bd.UV_BODY)
    dark = bd.make_material("Dark", atlas, bd.UV_DARK)
    target = bd.make_material("Target", atlas, bd.UV_TARGET)
    body = bd.build_pieces(body_mat, dark, target)
    for obj in body.values():
        obj["orig_slots"] = [s.material.name.split(".")[0] for s in obj.material_slots]
    cam = setup_render()
    for dummy_id, look in catalog.items():
        if only and dummy_id not in only:
            continue
        render_dummy(cam, dummy_id, look, body, addons, (body_mat, dark, target))
    print("[collection] apercus", RENDERS)


main()
