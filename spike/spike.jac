"""Blender -> glTF -> raylib model-loading spike for Jac native.

Loads the .glb assets produced by gen_assets.py through raylib's own
LoadModel / DrawModelEx, which pass raylib's 136-byte `Model` struct by value
(x86_64 SysV MEMORY class: byval in, sret out). The struct declarations below
mirror raylib 6.0's raylib.h field for field; the pointer members are read back
through bounds-checked `ptr[T].view(n)` windows to confirm the loader's arrays
arrived intact.

Run `./spike` to orbit the scene (Esc quits); `./spike --shot` renders a fixed
number of frames, writes shot.png and exits (used for verification).
"""

import math;
import sys;

import from raylib {
    obj Vector3 { has x: f32, y: f32, z: f32; }
    obj Matrix {
        has m0: f32, m4: f32, m8: f32, m12: f32,
            m1: f32, m5: f32, m9: f32, m13: f32,
            m2: f32, m6: f32, m10: f32, m14: f32,
            m3: f32, m7: f32, m11: f32, m15: f32;
    }
    obj Color { has r: u8, g: u8, b: u8, a: u8; }
    obj Camera3D { has position: Vector3, target: Vector3, up: Vector3, fovy: f32, projection: i32; }
    obj Texture { has id: u32, width: i32, height: i32, mipmaps: i32, format: i32; }
    obj Shader { has id: u32, locs: ptr[i32]; }
    obj MaterialMap { has texture: Texture, color: Color, value: f32; }
    obj Material { has shader: Shader, maps: ptr[MaterialMap], p0: f32, p1: f32, p2: f32, p3: f32; }
    obj Mesh {
        has vertexCount: i32, triangleCount: i32,
            vertices: ptr[f32], texcoords: ptr[f32], texcoords2: ptr[f32],
            normals: ptr[f32], tangents: ptr[f32], colors: ptr[u8], indices: ptr[u16],
            boneCount: i32, boneIndices: ptr[u8], boneWeights: ptr[f32],
            animVertices: ptr[f32], animNormals: ptr[f32],
            vaoId: u32, vboId: ptr[u32];
    }
    obj ModelSkeleton { has boneCount: i32, bones: ptr, bindPose: ptr; }
    obj Model {
        has transform: Matrix, meshCount: i32, materialCount: i32,
            meshes: ptr[Mesh], materials: ptr[Material], meshMaterial: ptr[i32],
            skeleton: ModelSkeleton, currentPose: ptr, boneMatrices: ptr;
    }
    obj BoundingBox { has min: Vector3, max: Vector3; }

    def SetConfigFlags(flags: u32) -> None;
    def InitWindow(width: i32, height: i32, title: str) -> None;
    def SetTargetFPS(fps: i32) -> None;
    def WindowShouldClose -> bool;
    def CloseWindow -> None;
    def BeginDrawing -> None;
    def EndDrawing -> None;
    def ClearBackground(color: Color) -> None;
    def BeginMode3D(camera: Camera3D) -> None;
    def EndMode3D -> None;
    def DrawGrid(slices: i32, spacing: f32) -> None;
    def DrawText(text: str, posX: i32, posY: i32, fontSize: i32, color: Color) -> None;
    def DrawFPS(posX: i32, posY: i32) -> None;
    def GetTime -> f64;
    def TakeScreenshot(fileName: str) -> None;

    def LoadModel(fileName: str) -> Model;
    def IsModelValid(model: Model) -> bool;
    def UnloadModel(model: Model) -> None;
    def GetModelBoundingBox(model: Model) -> BoundingBox;
    def DrawModelEx(
        model: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: f32,
        scale: Vector3, tint: Color
    ) -> None;
}

glob FLAG_MSAA_4X_HINT: int = 0x20,
     CAMERA_PERSPECTIVE: int = 0,
     SHOT_FRAMES: int = 90;

def vec3(x: float, y: float, z: float) -> Vector3 {
    return Vector3(x=f32(x), y=f32(y), z=f32(z));
}

def rgba(r: int, g: int, b: int, a: int) -> Color {
    return Color(r=u8(r), g=u8(g), b=u8(b), a=u8(a));
}

"""Print what the loader produced: per-mesh geometry and the diffuse color
each material carries (Blender's base color, scaled to bytes by raylib)."""
def describe(name: str, model: Model) {
    box = GetModelBoundingBox(model);
    print(
        f"{name}: valid={IsModelValid(model)} meshes={model.meshCount} "
        f"materials={model.materialCount} bones={model.skeleton.boneCount}"
    );
    print(
        f"  bbox min=({box.min.x:.2f}, {box.min.y:.2f}, {box.min.z:.2f}) "
        f"max=({box.max.x:.2f}, {box.max.y:.2f}, {box.max.z:.2f})"
    );
    meshes = model.meshes.view(int(model.meshCount));
    links = model.meshMaterial.view(int(model.meshCount));
    mats = model.materials.view(int(model.materialCount));
    for i in range(len(meshes)) {
        m = meshes[i];
        diffuse = mats[int(links[i])].maps.view(1)[0].color;
        print(
            f"  mesh {i}: verts={m.vertexCount} tris={m.triangleCount} "
            f"vertex_colors={not m.colors.is_null()} material={links[i]} "
            f"diffuse=({diffuse.r}, {diffuse.g}, {diffuse.b})"
        );
    }
}

with entry {
    shot_mode = "--shot" in sys.argv;

    SetConfigFlags(u32(FLAG_MSAA_4X_HINT));
    InitWindow(i32(1024), i32(640), "jblender spike");
    SetTargetFPS(i32(60));

    ship = LoadModel("assets/ship.glb");
    rock = LoadModel("assets/rock.glb");
    describe("ship.glb", ship);
    describe("rock.glb", rock);

    sky = rgba(14, 16, 26, 255);
    white = rgba(255, 255, 255, 255);
    label = rgba(200, 210, 230, 255);
    up = vec3(0.0, 1.0, 0.0);

    cam = Camera3D(
        position=vec3(6.0, 3.5, 6.0), target=vec3(0.0, 0.3, 0.0), up=up,
        fovy=f32(45.0), projection=i32(CAMERA_PERSPECTIVE)
    );

    frame = 0;
    while not WindowShouldClose() {
        t = float(GetTime());
        if shot_mode {
            t = float(frame) / 60.0;
        }
        orbit = 0.6 + 0.25 * t;
        cam.position = vec3(7.0 * math.cos(orbit), 3.2, 7.0 * math.sin(orbit));

        BeginDrawing();
        ClearBackground(sky);
        BeginMode3D(cam);
        DrawGrid(i32(24), f32(1.0));

        bank = 12.0 * math.sin(t * 1.3);
        DrawModelEx(ship, vec3(0.0, 1.2 + 0.15 * math.sin(t * 2.0), 0.0), vec3(0.0, 0.0, 1.0), f32(bank), vec3(1.0, 1.0, 1.0), white);

        for k in range(6) {
            a = float(k) * 1.047 + 0.4 * t;
            s = 0.45 + 0.12 * float(k % 3);
            DrawModelEx(
                rock, vec3(4.2 * math.cos(a), 0.9 + 0.5 * math.sin(a * 2.0), 4.2 * math.sin(a)),
                vec3(0.3, 1.0, 0.2), f32(40.0 * t + 60.0 * float(k)), vec3(s, s, s), white
            );
        }
        EndMode3D();

        DrawText("jac native + raylib LoadModel: assets/ship.glb, assets/rock.glb (made in Blender)", i32(14), i32(12), i32(18), label);
        DrawFPS(i32(14), i32(38));
        EndDrawing();

        frame += 1;
        if shot_mode and frame == SHOT_FRAMES {
            TakeScreenshot("shot.png");
            break;
        }
    }

    UnloadModel(ship);
    UnloadModel(rock);
    CloseWindow();
}
