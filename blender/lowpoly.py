"""Low-poly modelling helpers for EMBERWAKE's procedural assets.

Geometry is plain data: a shape is `(verts, faces)` in Blender space (+Y is the
model's forward, +Z up). An `Asset` collects shapes with a material key each,
then builds one mesh and exports it as .glb.

Vertex colours follow the game's convention (docs/DESIGN.md): lit models store
R = per-face brightness jitter, G = emissive amount, B = 0; skies store true
RGB for the unlit shader. Material base colours carry the hue.
"""

import math
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

# ---------------------------------------------------------------- transforms

def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def S(x, y=None, z=None):
    y = x if y is None else y
    z = x if z is None else z
    return Matrix.Diagonal((x, y, z, 1.0))


def align_y(direction):
    """Rotation taking +Y onto `direction`."""
    d = Vector(direction).normalized()
    return Vector((0, 1, 0)).rotation_difference(d).to_matrix().to_4x4()


def xform(shape, m):
    verts, faces = shape
    flip = m.to_3x3().determinant() < 0
    out = [tuple(m @ Vector(v)) for v in verts]
    return out, [tuple(reversed(f)) for f in faces] if flip else faces


# ---------------------------------------------------------------- primitives

def _from_bm(bm):
    bm.verts.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return verts, faces


def hull(points, merge_deg=1.0):
    """Convex hull; coplanar triangles are merged back into flat panels."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    if merge_deg:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(merge_deg), verts=bm.verts, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _from_bm(bm)


def ring(y, rx, rz=None, sides=6, phase=0.0, cx=0.0, cz=0.0):
    """Points of an elliptical ring in the XZ plane at depth y."""
    rz = rx if rz is None else rz
    return [
        (cx + rx * math.cos(phase + 2 * math.pi * i / sides), y, cz + rz * math.sin(phase + 2 * math.pi * i / sides))
        for i in range(sides)
    ]


def box(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    return hull([(x, y, z) for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)])


def prism(r, length, sides=6, r2=None, phase=None):
    """Prism/frustum along Y centred on the origin (r at -Y end, r2 at +Y end)."""
    r2 = r if r2 is None else r2
    phase = math.pi / sides if phase is None else phase
    return hull(ring(-length / 2, r, sides=sides, phase=phase) + ring(length / 2, r2, sides=sides, phase=phase))


def bipyramid(r, top, bottom, sides=6, phase=0.0):
    """Crystal: ring of radius r in XZ with apexes at +top and -bottom along Y."""
    return hull([(0, top, 0), (0, -bottom, 0)] + ring(0, r, sides=sides, phase=phase))


def ico(r=1.0, subdiv=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    return _from_bm(bm)


def uvsphere(r=1.0, u=16, v=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r)
    return _from_bm(bm)


def torus(R_, r, segs=24, sides=6, axis="Y"):
    """Torus around the given axis (default Y, so the ring faces forward)."""
    verts, faces = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ca, sa = math.cos(a), math.sin(a)
        for j in range(sides):
            b = 2 * math.pi * j / sides
            d = R_ + r * math.cos(b)
            # ring in XZ, tube offset along Y
            verts.append((d * ca, r * math.sin(b), d * sa))
    for i in range(segs):
        for j in range(sides):
            a = i * sides + j
            b = ((i + 1) % segs) * sides + j
            c = ((i + 1) % segs) * sides + (j + 1) % sides
            d = i * sides + (j + 1) % sides
            faces.append((a, d, c, b))
    shape = (verts, faces)
    if axis == "Z":
        shape = xform(shape, R("X", 90))
    elif axis == "X":
        shape = xform(shape, R("Z", 90))
    return _recalc(shape)


def annulus(r_in, r_out, segs=48, thickness=0.0):
    """Flat ring in the XY plane (normal +/-Z), closed with a thin edge so both sides render."""
    t = max(thickness, 1e-3) / 2
    verts = []
    for z in (t, -t):
        for i in range(segs):
            a = 2 * math.pi * i / segs
            verts.append((r_in * math.cos(a), r_in * math.sin(a), z))
            verts.append((r_out * math.cos(a), r_out * math.sin(a), z))
    faces = []
    n = 2 * segs
    for i in range(segs):
        i0, o0 = 2 * i, 2 * i + 1
        i1, o1 = 2 * ((i + 1) % segs), 2 * ((i + 1) % segs) + 1
        faces.append((i0, o0, o1, i1))  # top
        faces.append((n + i0, n + i1, n + o1, n + o0))  # bottom
        faces.append((o0, n + o0, n + o1, o1))  # outer rim
        faces.append((i0, i1, n + i1, n + i0))  # inner rim
    return _recalc((verts, faces))


def disc(r, segs=32, thickness=0.02):
    return hull(
        [(r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z) for i in range(segs) for z in (-thickness / 2, thickness / 2)]
    )


def rock(rng, r=1.0, n=36, stretch=(1.0, 1.0, 1.0), jitter=(0.75, 1.15)):
    pts = []
    for _ in range(n):
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        v *= r * rng.uniform(*jitter)
        pts.append((v.x * stretch[0], v.y * stretch[1], v.z * stretch[2]))
    return hull(pts)


def beam(a, b, w, h=None):
    """Box of cross-section w x h spanning point a to point b."""
    h = w if h is None else h
    a, b = Vector(a), Vector(b)
    d = b - a
    return xform(box(w, d.length, h), T(*((a + b) / 2)) @ align_y(d))


def _recalc(shape):
    verts, faces = shape
    bm = bmesh.new()
    bv = [bm.verts.new(v) for v in verts]
    for f in faces:
        try:
            bm.faces.new([bv[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _from_bm(bm)


# ---------------------------------------------------------------- asset

class Asset:
    def __init__(self, name, seed=1, jitter=0.06):
        self.name = name
        self.rng = random.Random(seed)
        self.jitter = jitter
        self.mats = {}
        self.parts = []
        self.sky_fn = None

    def mat(self, key, rgb, emissive=0.0, bright=1.0):
        """Register a material: display colour, emissive amount, brightness scale."""
        self.mats[key] = (tuple(rgb), emissive, bright)
        return key

    def add(self, shape, mat, m=None, mirror_x=False):
        if m is not None:
            shape = xform(shape, m)
        self.parts.append((shape, mat))
        if mirror_x:
            self.parts.append((xform(shape, S(-1, 1, 1)), mat))
        return self

    def build(self):
        keys = [k for k in self.mats if any(p[1] == k for p in self.parts)]
        verts, faces, mat_of = [], [], []
        for (pv, pf), key in self.parts:
            base = len(verts)
            verts.extend(pv)
            for f in pf:
                faces.append(tuple(base + i for i in f))
                mat_of.append(keys.index(key))
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(verts, [], faces)
        for poly, mi in zip(mesh.polygons, mat_of):
            poly.material_index = mi
        mesh.validate()
        for k in keys:
            rgb = (1.0, 1.0, 1.0) if self.sky_fn else self.mats[k][0]
            m = bpy.data.materials.new(f"{self.name}_{k}")
            bsdf = m.node_tree.nodes["Principled BSDF"]
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.7
            mesh.materials.append(m)
        attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        for poly in mesh.polygons:
            mi = poly.material_index
            poly.use_smooth = False
            _, emis, bright = self.mats[keys[mi]]
            if self.sky_fn:
                for li in poly.loop_indices:
                    c = self.sky_fn(Vector(mesh.vertices[mesh.loops[li].vertex_index].co).normalized(), keys[mi])
                    attr.data[li].color = (*c, 1.0)
            else:
                b = bright * (1.0 - self.jitter + 2 * self.jitter * self.rng.random())
                for li in poly.loop_indices:
                    attr.data[li].color = (min(b, 1.0), emis, 0.0, 1.0)
        mesh.color_attributes.active_color = attr
        mesh.color_attributes.render_color_index = mesh.color_attributes.find("Color")
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj

    def export(self, out_dir: Path):
        clear_scene()
        obj = self.build()
        path = out_dir / f"{self.name}.glb"
        bpy.ops.export_scene.gltf(
            filepath=str(path),
            export_format="GLB",
            export_vertex_color="ACTIVE",
            export_normals=True,
            export_yup=True,
            export_apply=True,
        )
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        dims = obj.dimensions
        print(f"  {self.name:<16} {tris:>6} tris  {dims.x:7.2f} x {dims.y:7.2f} x {dims.z:7.2f}")
        return path


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def fbm(v, scale=1.0, octaves=4):
    """Fractal noise in roughly [-1, 1]."""
    return noise.fractal(Vector(v) * scale, 0.5, 2.0, octaves, noise_basis="PERLIN_ORIGINAL")


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
