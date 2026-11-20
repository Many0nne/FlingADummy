# Mannequin de crash-test stylise (blocky, aretes adoucies) : 10 pieces dans le gabarit de Shared.DummyShape.
# Construit la scene, l'atlas de texture (zone transparente = couleur de la piece, noir, cible), sauvegarde
# dummy.blend, exporte export/dummy.fbx et export/dummy_atlas.png, et rend export/preview.png.
# Usage : blender -b --factory-startup --python assets/dummy/build_dummy.py [-- --no-render]
# Unite : 1 unite Blender = 1 stud. Axes : Blender Z = haut (Roblox Y), Blender +Y = avant (Roblox -Z, face du perso).
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = os.path.join(HERE, "export")
ATLAS_SIZE = 256

YELLOW = (1.0, 0.80, 0.16, 1.0)
DARK = (0.105, 0.11, 0.135, 1.0)

# Gabarit (identique a Shared.DummyShape.PIECES) : nom -> (taille XYZ Roblox, centre XYZ Roblox)
ARM = (0.8, 1.2, 0.8)
LEG = (0.95, 1.3, 0.95)
PIECES = {
    "Torso": ((2.0, 2.4, 1.1), (0, 0, 0)),
    "Head": ((1.5, 1.5, 1.5), (0, 2.1, 0)),
    "LeftUpperArm": (ARM, (-1.45, 0.6, 0)),
    "LeftLowerArm": (ARM, (-1.45, -0.62, 0)),
    "RightUpperArm": (ARM, (1.45, 0.6, 0)),
    "RightLowerArm": (ARM, (1.45, -0.62, 0)),
    "LeftUpperLeg": (LEG, (-0.5, -1.85, 0)),
    "LeftLowerLeg": (LEG, (-0.5, -3.17, 0)),
    "RightUpperLeg": (LEG, (0.5, -1.85, 0)),
    "RightLowerLeg": (LEG, (0.5, -3.17, 0)),
}

# Regions de l'atlas (u0, v0, u1, v1) : corps transparent (teinte de la piece), noir opaque, cible
UV_BODY = (0.0, 0.0, 0.5, 1.0)
UV_DARK = (0.5, 0.0, 1.0, 0.5)
UV_TARGET = (0.5, 0.5, 1.0, 1.0)


def rb(v):
    """Convertit un vecteur Roblox (x, y, z) en Blender (x, -z, y)."""
    return (v[0], -v[2], v[1])


def clear_scene():
    """Cette methode permet de repartir d'une scene vide lorsque le script demarre (reglages d'usine)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_atlas():
    """Atlas RGBA : moitie gauche transparente, quart bas-droit noir, quart haut-droit cible jaune/noire."""
    n = ATLAS_SIZE
    px = np.zeros((n, n, 4), dtype=np.float32)
    half = n // 2
    # Noir (v 0-0.5, u 0.5-1). Les lignes numpy vont de bas (v=0) en haut.
    px[0:half, half:n] = DARK
    # Cible (v 0.5-1, u 0.5-1)
    size = half
    ys, xs = np.mgrid[0:size, 0:size]
    cx = cy = (size - 1) / 2
    dx, dy = xs - cx, ys - cy
    r = np.sqrt(dx * dx + dy * dy)
    radius = size * 0.47
    ring = size * 0.075
    tile = np.zeros((size, size, 4), dtype=np.float32)
    inside = r <= radius
    tile[inside] = YELLOW
    # Deux quartiers noirs opposes (haut-gauche, bas-droit)
    quad = inside & (((dx < 0) & (dy > 0)) | ((dx >= 0) & (dy <= 0)))
    tile[quad] = (0.02, 0.02, 0.02, 1.0)
    tile[inside & (r > radius - ring)] = (0.02, 0.02, 0.02, 1.0)
    px[half:n, half:n] = tile
    img = bpy.data.images.new("dummy_atlas", n, n, alpha=True)
    img.pixels = px.ravel()
    img.filepath_raw = os.path.join(EXPORT, "dummy_atlas.png")
    img.file_format = "PNG"
    img.save()
    return img


def make_material(name, atlas, region):
    """Materiau d'apercu : atlas sur la couleur jaune (comme la piece Roblox teintee), region UV memorisee."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.45
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = atlas
    tex.interpolation = "Closest" if region is UV_DARK else "Linear"
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = YELLOW
    links.new(tex.outputs["Alpha"], mix.inputs[0])
    links.new(tex.outputs["Color"], mix.inputs[7])
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    mat["uv_region"] = region
    return mat


def rounded_box(name, size, center, bevel, mat, segments=3):
    """Pave aux aretes adoucies (taille et centre en coordonnees Roblox)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=rb(center))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "NONE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, radius, depth, center, axis, mat, bevel=0.04):
    """Cylindre (articulation, cou) d'axe 'X', 'Y' ou 'Z' Roblox."""
    rot = {"X": (0, math.pi / 2, 0), "Y": (0, 0, 0), "Z": (math.pi / 2, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=radius, depth=depth, location=rb(center), rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(rotation=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    return obj


def target_disc(name, center, normal, diameter, mat):
    """Cible plaquee (fine galette) dont la face visible regarde `normal` (Roblox), UV sur la region cible."""
    axis = {"X": "X", "-X": "X", "Z": "Z", "-Z": "Z"}[normal]
    obj = cylinder(name, diameter / 2, 0.04, center, axis, mat, bevel=0.012)
    obj["disc_radius"] = diameter / 2
    obj["disc_center"] = rb(center)
    obj["disc_axis"] = 0 if axis == "X" else 1
    return obj


def assign_uvs(obj):
    """Projette chaque face sur la region UV de son materiau : point unique pour le corps et le noir, projection
    plane (dans le plan de la face) pour la cible."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        mat = obj.material_slots[poly.material_index].material
        region = tuple(mat["uv_region"])
        u0, v0, u1, v1 = region
        if region == UV_TARGET:
            # Projection plane depuis le centre de la galette, le long de son axe ; le chant est peint en noir
            n = poly.normal
            axis = obj["disc_axis"]
            c = np.array(obj["disc_center"])
            facing = abs(n[axis])
            if facing < 0.6:
                mid = ((UV_DARK[0] + UV_DARK[2]) / 2, (UV_DARK[1] + UV_DARK[3]) / 2)
                for li in poly.loop_indices:
                    uv[li].uv = mid
                continue
            sign = 1 if n[axis] > 0 else -1
            radius = obj["disc_radius"]
            for li in poly.loop_indices:
                co = np.array(me.vertices[me.loops[li].vertex_index].co) - c
                if axis == 0:
                    a, b = co[1] * sign, co[2]
                elif axis == 1:
                    a, b = -co[0] * sign, co[2]
                else:
                    a, b = co[0], co[1]
                fu = min(max(0.5 + a / (2 * radius), 0.0), 1.0)
                fv = min(max(0.5 + b / (2 * radius), 0.0), 1.0)
                uv[li].uv = (u0 + fu * (u1 - u0), v0 + fv * (v1 - v0))
        else:
            mid = ((u0 + u1) / 2, (v0 + v1) / 2)
            for li in poly.loop_indices:
                uv[li].uv = mid


def join(name, parts, center):
    """Fusionne les sous-formes d'une piece, origine au centre du gabarit."""
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        assign_uvs(p)
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    bpy.context.scene.cursor.location = rb(center)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    for poly in obj.data.polygons:
        poly.use_smooth = True
    # Normales adoucies seulement sur les arrondis (aretes vives au-dela de 40 degres)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return obj


def build_pieces(body, dark, target):
    """Cette methode permet de modeliser les 10 pieces du gabarit (blocs arrondis, articulations, cibles) lorsque
    le script construit le mannequin ; retourne nom -> objet."""
    objs = {}
    # Torse : bloc arrondi, ceinture noire, cibles devant et derriere, plaque de poitrine
    size, c = PIECES["Torso"]
    torso = [
        rounded_box("t_body", (2.0, 2.05, 1.02), (0, 0.17, 0), 0.22, body),
        rounded_box("t_belt", (1.86, 0.42, 1.06), (0, -0.98, 0), 0.12, dark),
        rounded_box("t_neck", (0.7, 0.12, 0.6), (0, 1.14, 0), 0.04, dark),
        target_disc("t_tf", (0, 0.32, -0.53), "-Z", 0.95, target),
        target_disc("t_tb", (0, 0.32, 0.53), "Z", 0.95, target),
    ]
    # Garder la boite exacte du gabarit (2 x 2.4 x 1.1) : coins invisibles d'ajustement
    torso.append(rounded_box("t_hip", (1.7, 0.2, 1.1), (0, -1.1, 0), 0.06, dark))
    objs["Torso"] = join("Torso", torso, c)

    # Tete : cube arrondi, cou noir, cibles sur les tempes, deux yeux noirs
    size, c = PIECES["Head"]
    hx, hy, hz = c
    head = [
        rounded_box("h_body", (1.5, 1.28, 1.42), (hx, hy + 0.11, hz), 0.3, body, segments=4),
        cylinder("h_neck", 0.3, 0.26, (hx, hy - 0.62, hz), "Y", dark),
        target_disc("h_tl", (hx - 0.73, hy + 0.13, hz), "-X", 0.78, target),
        target_disc("h_tr", (hx + 0.73, hy + 0.13, hz), "X", 0.78, target),
        rounded_box("h_eyeL", (0.2, 0.28, 0.06), (hx - 0.3, hy + 0.2, hz - 0.71), 0.06, dark),
        rounded_box("h_eyeR", (0.2, 0.28, 0.06), (hx + 0.3, hy + 0.2, hz - 0.71), 0.06, dark),
        # profondeur du gabarit (1.5) sans grossir la tete : fine plaque nucale noire
        rounded_box("h_back", (0.7, 0.3, 0.04), (hx, hy - 0.2, hz + 0.73), 0.015, dark),
        rounded_box("h_front", (0.5, 0.06, 0.04), (hx, hy - 0.25, hz - 0.73), 0.015, dark),
    ]
    objs["Head"] = join("Head", head, c)

    for side, sx in (("Left", -1), ("Right", 1)):
        # Bras : epaule noire, bras jaune ; avant-bras : coude noir, avant-bras jaune, main noire
        _, c = PIECES[side + "UpperArm"]
        x, y, z = c
        objs[side + "UpperArm"] = join(
            side + "UpperArm",
            [
                rounded_box("ua_sh", (0.8, 0.42, 0.8), (x, y + 0.39, z), 0.18, dark),
                rounded_box("ua_body", (0.7, 0.86, 0.7), (x, y - 0.17, z), 0.16, body),
            ],
            c,
        )
        _, c = PIECES[side + "LowerArm"]
        x, y, z = c
        objs[side + "LowerArm"] = join(
            side + "LowerArm",
            [
                cylinder("la_elbow", 0.3, 0.24, (x, y + 0.48, z), "Y", dark),
                rounded_box("la_body", (0.7, 0.62, 0.7), (x, y + 0.06, z), 0.16, body),
                rounded_box("la_hand", (0.8, 0.36, 0.8), (x, y - 0.42, z), 0.14, dark),
            ],
            c,
        )
        # Jambes : hanche noire, cuisse jaune ; tibia : genou noir, tibia jaune, pied noir
        _, c = PIECES[side + "UpperLeg"]
        x, y, z = c
        objs[side + "UpperLeg"] = join(
            side + "UpperLeg",
            [
                rounded_box("ul_hip", (0.95, 0.3, 0.95), (x, y + 0.5, z), 0.12, dark),
                rounded_box("ul_body", (0.88, 1.0, 0.88), (x, y - 0.15, z), 0.18, body),
            ],
            c,
        )
        _, c = PIECES[side + "LowerLeg"]
        x, y, z = c
        objs[side + "LowerLeg"] = join(
            side + "LowerLeg",
            [
                cylinder("ll_knee", 0.36, 0.24, (x, y + 0.53, z), "Y", dark),
                rounded_box("ll_body", (0.86, 0.66, 0.86), (x, y + 0.08, z), 0.16, body),
                rounded_box("ll_foot", (0.95, 0.34, 0.95), (x, y - 0.48, z), 0.12, dark),
            ],
            c,
        )
    return objs


def build_accessories(body, dark, target):
    """Accessoires de declinaison (collection, boutique) : maillages separes, poses sur la piece porteuse.
    Retourne nom -> (objet, piece porteuse)."""
    _, (hx, hy, hz) = PIECES["Head"]
    helmet = join(
        "Acc_Helmet",
        [
            rounded_box("hm_shell", (1.64, 0.64, 1.58), (hx, hy + 0.7, hz), 0.3, body, segments=5),
            rounded_box("hm_stripe", (0.3, 0.66, 1.62), (hx, hy + 0.72, hz), 0.12, dark),
            rounded_box("hm_brim", (1.5, 0.1, 0.3), (hx, hy + 0.42, hz - 0.78), 0.04, dark),
        ],
        (hx, hy + 0.7, hz),
    )
    glasses = join(
        "Acc_Glasses",
        [
            rounded_box("gl_l", (0.48, 0.36, 0.08), (hx - 0.32, hy + 0.2, hz - 0.78), 0.08, dark),
            rounded_box("gl_r", (0.48, 0.36, 0.08), (hx + 0.32, hy + 0.2, hz - 0.78), 0.08, dark),
            rounded_box("gl_bridge", (0.3, 0.08, 0.06), (hx, hy + 0.28, hz - 0.78), 0.02, dark),
            rounded_box("gl_al", (0.06, 0.08, 0.5), (hx - 0.77, hy + 0.28, hz - 0.55), 0.02, dark),
            rounded_box("gl_ar", (0.06, 0.08, 0.5), (hx + 0.77, hy + 0.28, hz - 0.55), 0.02, dark),
        ],
        (hx, hy + 0.2, hz - 0.65),
    )
    cape = join(
        "Acc_Cape",
        [
            rounded_box("cp_cloth", (1.9, 2.9, 0.1), (0, -0.3, 0.63), 0.05, body),
            rounded_box("cp_collar", (1.6, 0.18, 0.3), (0, 1.12, 0.52), 0.06, dark),
            target_disc("cp_mark", (0, 0.1, 0.70), "Z", 0.9, target),
        ],
        (0, -0.2, 0.62),
    )
    return {"Helmet": (helmet, "Head"), "Glasses": (glasses, "Head"), "Cape": (cape, "Torso")}


def accessory_bounds(accs):
    """Gabarit de chaque accessoire en coordonnees Roblox : taille et decalage du centre par rapport au centre de
    sa piece porteuse (copie dans Shared.DummyShape.ACCESSORIES)."""
    out = {}
    for name, (obj, piece) in accs.items():
        vs = np.array([obj.matrix_world @ v.co for v in obj.data.vertices])
        lo, hi = vs.min(axis=0), vs.max(axis=0)
        size_b, mid_b = hi - lo, (hi + lo) / 2
        size = (size_b[0], size_b[2], size_b[1])
        mid = (mid_b[0], mid_b[2], -mid_b[1])
        pc = PIECES[piece][1]
        offset = tuple(round(float(mid[i] - pc[i]), 3) for i in range(3))
        out[name] = {"piece": piece, "size": [round(float(v), 3) for v in size], "offset": list(offset)}
        print(f"[acc] {name}: piece {piece} taille {out[name]['size']} decalage {out[name]['offset']}")
    return out


def check_bounds(objs):
    """Verifie que chaque piece remplit exactement la boite du gabarit (taille et centre), condition pour que la
    MeshPart redimensionnee a la taille du gabarit garde ses proportions."""
    ok = True
    for name, (size, center) in PIECES.items():
        obj = objs[name]
        vs = np.array([obj.matrix_world @ v.co for v in obj.data.vertices])
        lo, hi = vs.min(axis=0), vs.max(axis=0)
        got = hi - lo
        mid = (hi + lo) / 2
        want = np.array(rb(size))
        want = np.abs(want)
        want_c = np.array(rb(center))
        err = max(np.abs(got - want).max(), np.abs(mid - want_c).max())
        flag = "ok" if err < 1e-3 else "ECART"
        if err >= 1e-3:
            ok = False
        print(f"[bounds] {name:14s} taille {got.round(3)} attendu {want} centre {mid.round(3)} {flag}")
    return ok


def render_preview(path):
    """Cette methode permet de rendre une image d'apercu du mannequin lorsque l'export est fini."""
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.45, 0.85, 0.35, 1)
    bg.inputs["Strength"].default_value = 0.9
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(150)))
    bpy.context.active_object.data.energy = 4.0
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    # Trois-quarts face (le perso regarde Blender +Y, soit Roblox -Z)
    cam.location = (6.5, 10.5, 2.6)
    target = (0, 0, -0.4)
    direction = np.array(target) - np.array(cam.location)
    from mathutils import Vector

    cam.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 70
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    # Vue de face
    cam.location = (0, 13, 0.6)
    cam.rotation_euler = Vector((0, -13, -0.9)).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 60
    scene.render.filepath = path.replace(".png", "_front.png")
    bpy.ops.render.render(write_still=True)


def main():
    """Cette methode permet d'enchainer construction, verification, sauvegarde, export et apercu lorsque Blender
    lance le script."""
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    os.makedirs(EXPORT, exist_ok=True)
    clear_scene()
    atlas = build_atlas()
    body = make_material("Body", atlas, UV_BODY)
    dark = make_material("Dark", atlas, UV_DARK)
    target = make_material("Target", atlas, UV_TARGET)
    objs = build_pieces(body, dark, target)
    ok = check_bounds(objs)
    accs = build_accessories(body, dark, target)
    import json

    with open(os.path.join(EXPORT, "accessories.json"), "w", encoding="utf-8") as f:
        json.dump(accessory_bounds(accs), f, indent=2)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "dummy.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs.values():
        obj.select_set(True)
    for obj, _ in accs.values():
        obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(EXPORT, "dummy.fbx"),
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        mesh_smooth_type="FACE",
        axis_forward="-Z",
        axis_up="Y",
        path_mode="COPY",
        embed_textures=True,
    )
    if "--no-render" not in argv:
        for obj, _ in accs.values():
            obj.hide_render = True
        render_preview(os.path.join(EXPORT, "preview.png"))
        # Declinaison : couleur de piece rouge, casque, lunettes et cape
        for obj, _ in accs.values():
            obj.hide_render = False
        mix = next(n for n in body.node_tree.nodes if n.type == "MIX")
        mix.inputs[6].default_value = (0.85, 0.12, 0.1, 1)
        bpy.context.scene.render.filepath = os.path.join(EXPORT, "preview_variant.png")
        bpy.ops.render.render(write_still=True)
    print("[dummy] termine, gabarit " + ("respecte" if ok else "NON respecte"))


main()
