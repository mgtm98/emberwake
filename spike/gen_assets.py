"""Procedurally build the spike's low-poly assets and export them as .glb.

Run headless:  blender -b --factory-startup -P gen_assets.py -- [out_dir]

Each part is the convex hull of a handful of points, which gives clean
flat-shaded low-poly solids without hand-placing faces. raylib's default shader
is unlit, so a directional light is baked into a per-corner FLOAT_COLOR
attribute (a grayscale shade factor); the material base color carries the hue
and raylib multiplies the two (colDiffuse * vertex color) at draw time.

Colors are written in the space raylib will display them in: the glTF exporter
passes float color attributes and baseColorFactor through unconverted, and
raylib scales them straight to bytes without a gamma step.
"""

import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

LIGHT = Vector((0.45, -0.35, 0.82)).normalized()  # Blender Z-up world


def out_dir() -> Path:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return Path(argv[0] if argv else Path(__file__).parent / "assets").resolve()


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, emissive=False):
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    if emissive:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    mat["unlit_shade"] = emissive
    return mat


def hull(name, points, mat):
    """Closed convex solid through `points`, one material slot."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts)
    # Hull can leave interior points behind as loose verts.
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # Merge coplanar triangles back into n-gons so each flat panel reads as one.
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts, edges=bm.edges)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def ring(y, w, h, z=0.0, sides=6):
    """Elliptical cross-section ring in the XZ plane at depth y."""
    return [
        (w * math.cos(2 * math.pi * i / sides), y, z + h * math.sin(2 * math.pi * i / sides))
        for i in range(sides)
    ]


def mirror_x(points):
    return [(-x, y, z) for (x, y, z) in points]


def bake_shade(obj):
    """Store a baked directional-light factor per face corner."""
    mesh = obj.data
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    for poly in mesh.polygons:
        mat = mesh.materials[poly.material_index]
        if mat.get("unlit_shade"):
            s = 1.0
        else:
            n = poly.normal
            diffuse = max(0.0, n.dot(LIGHT))
            sky = 0.5 + 0.5 * n.z  # hemisphere fill: tops brighter than bellies
            s = min(1.0, 0.22 + 0.62 * diffuse + 0.22 * sky)
        for li in poly.loop_indices:
            attr.data[li].color = (s, s, s, 1.0)
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = mesh.color_attributes.find("Color")


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ship = bpy.context.view_layer.objects.active
    ship.name = name
    for poly in ship.data.polygons:
        poly.use_smooth = False
    return ship


def export(path: Path):
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_vertex_color="ACTIVE",
        export_normals=True,
        export_yup=True,
        export_apply=True,
    )
    print(f"wrote {path} ({path.stat().st_size} bytes)")


def build_ship():
    """Low-poly fighter; nose points along Blender -Y (glTF/raylib +Z)."""
    hull_m = material("hull", (0.78, 0.82, 0.88))
    wing_m = material("wing", (0.85, 0.28, 0.18))
    glass_m = material("glass", (0.20, 0.75, 0.95))
    engine_m = material("engine", (0.30, 0.31, 0.34))
    glow_m = material("glow", (1.00, 0.62, 0.15), emissive=True)

    parts = []
    parts.append(hull("fuselage", [(0, -2.3, 0.02)] + ring(-0.7, 0.42, 0.30) + ring(0.9, 0.52, 0.34) + ring(1.5, 0.38, 0.24), hull_m))

    wing = [(0.35, -0.3, 0.04), (0.35, 1.2, 0.04), (0.35, -0.3, -0.06), (0.35, 1.2, -0.06),
            (2.1, 0.9, -0.02), (2.1, 1.35, -0.02), (2.1, 0.9, -0.06), (2.1, 1.35, -0.06)]
    parts.append(hull("wing_r", wing, wing_m))
    parts.append(hull("wing_l", mirror_x(wing), wing_m))

    fin = [(0, 0.7, 0.2), (0, 1.5, 0.2), (0, 1.55, 0.95), (0, 1.25, 0.95)]
    fin = [(x + dx, y, z) for (x, y, z) in fin for dx in (-0.04, 0.04)]
    parts.append(hull("fin", fin, wing_m))

    parts.append(hull("cockpit", [(0, -1.3, 0.22)] + ring(-0.6, 0.22, 0.12, z=0.3) + ring(0.15, 0.24, 0.10, z=0.28), glass_m))

    for side in (1, -1):
        cx = 0.55 * side
        body = [(cx + x, y, z - 0.08) for (x, y, z) in ring(0.2, 0.2, 0.2, sides=8) + ring(1.75, 0.22, 0.22, sides=8)]
        parts.append(hull(f"engine_{side}", body, engine_m))
        nozzle = [(cx + x, y, z - 0.08) for (x, y, z) in ring(1.76, 0.15, 0.15, sides=8) + ring(1.82, 0.15, 0.15, sides=8)]
        parts.append(hull(f"glow_{side}", nozzle, glow_m))

    for p in parts:
        bake_shade(p)
    return join(parts, "Ship")


def build_rock(seed=7):
    """Lumpy asteroid: hull of jittered points on a sphere."""
    rng = random.Random(seed)
    rock_m = material("rock", (0.55, 0.47, 0.40))
    pts = []
    for _ in range(40):
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        pts.append(tuple(v * rng.uniform(0.8, 1.15)))
    rock = hull("Rock", pts, rock_m)
    bake_shade(rock)
    for poly in rock.data.polygons:
        poly.use_smooth = False
    return rock


def main():
    out = out_dir()
    out.mkdir(parents=True, exist_ok=True)

    reset_scene()
    build_ship()
    export(out / "ship.glb")

    reset_scene()
    build_rock()
    export(out / "rock.glb")


main()
