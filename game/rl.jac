"""raylib 6.0 bindings used by EMBERWAKE.

Struct layouts mirror raylib.h field for field; the native backend passes them
by value per the platform C ABI. Import names explicitly from this module: a
wildcard import loses the externs' return types.
"""

import from raylib {
    obj Vector2 { has x: f32, y: f32; }
    obj Vector3 { has x: f32, y: f32, z: f32; }
    obj Vector4 { has x: f32, y: f32, z: f32, w: f32; }
    obj Matrix {
        has m0: f32, m4: f32, m8: f32, m12: f32,
            m1: f32, m5: f32, m9: f32, m13: f32,
            m2: f32, m6: f32, m10: f32, m14: f32,
            m3: f32, m7: f32, m11: f32, m15: f32;
    }
    obj Color { has r: u8, g: u8, b: u8, a: u8; }
    obj Rectangle { has x: f32, y: f32, width: f32, height: f32; }
    obj Camera3D { has position: Vector3, target: Vector3, up: Vector3, fovy: f32, projection: i32; }
    obj Texture { has id: u32, width: i32, height: i32, mipmaps: i32, format: i32; }
    obj Shader { has id: u32, locs: ptr[i32]; }
    obj MaterialMap { has texture: Texture, color: Color, value: f32; }
    obj Material { has shader: Shader, maps: ptr[MaterialMap], p0: f32, p1: f32, p2: f32, p3: f32; }
    obj Mesh;
    obj ModelSkeleton { has boneCount: i32, bones: ptr, bindPose: ptr; }
    obj Model {
        has transform: Matrix, meshCount: i32, materialCount: i32,
            meshes: ptr[Mesh], materials: ptr[Material], meshMaterial: ptr[i32],
            skeleton: ModelSkeleton, currentPose: ptr, boneMatrices: ptr;
    }
    obj BoundingBox { has min: Vector3, max: Vector3; }
    obj AudioStream { has buffer: ptr, processor: ptr, sampleRate: u32, sampleSize: u32, channels: u32; }
    obj Sound { has stream: AudioStream, frameCount: u32; }
    obj Music { has stream: AudioStream, frameCount: u32, looping: bool, ctxType: i32, ctxData: ptr; }
    obj Font { has baseSize: i32, glyphCount: i32, glyphPadding: i32, texture: Texture, recs: ptr[Rectangle], glyphs: ptr; }
    obj RenderTexture { has id: u32, texture: Texture, depth: Texture; }

    # window / frame
    def SetConfigFlags(flags: u32) -> None;
    def SetTraceLogLevel(logLevel: i32) -> None;
    def InitWindow(width: i32, height: i32, title: str) -> None;
    def CloseWindow -> None;
    def WindowShouldClose -> bool;
    def SetTargetFPS(fps: i32) -> None;
    def SetExitKey(key: i32) -> None;
    def ToggleFullscreen -> None;
    def GetScreenWidth -> i32;
    def GetScreenHeight -> i32;
    def GetFrameTime -> f32;
    def GetTime -> f64;
    def GetFPS -> i32;
    def HideCursor -> None;
    def BeginDrawing -> None;
    def EndDrawing -> None;
    def ClearBackground(color: Color) -> None;
    def BeginMode3D(camera: Camera3D) -> None;
    def EndMode3D -> None;
    def BeginBlendMode(mode: i32) -> None;
    def EndBlendMode -> None;
    def TakeScreenshot(fileName: str) -> None;
    def GetWorldToScreen(position: Vector3, camera: Camera3D) -> Vector2;

    # rlgl state
    def rlEnableDepthMask -> None;
    def rlDisableDepthMask -> None;
    def rlEnableBackfaceCulling -> None;
    def rlDisableBackfaceCulling -> None;
    def rlDrawRenderBatchActive -> None;

    # input
    def IsKeyDown(key: i32) -> bool;
    def IsKeyPressed(key: i32) -> bool;
    def IsGamepadAvailable(gamepad: i32) -> bool;
    def IsGamepadButtonDown(gamepad: i32, button: i32) -> bool;
    def IsGamepadButtonPressed(gamepad: i32, button: i32) -> bool;
    def GetGamepadAxisMovement(gamepad: i32, axis: i32) -> f32;

    # files
    def FileExists(fileName: str) -> bool;
    def LoadFileText(fileName: str) -> str;
    def SaveFileText(fileName: str, text: str) -> bool;

    # 2D
    def DrawRectangle(posX: i32, posY: i32, width: i32, height: i32, color: Color) -> None;
    def DrawRectangleLinesEx(rec: Rectangle, lineThick: f32, color: Color) -> None;
    def DrawRectangleGradientV(posX: i32, posY: i32, width: i32, height: i32, top: Color, bottom: Color) -> None;
    def DrawLineEx(startPos: Vector2, endPos: Vector2, thick: f32, color: Color) -> None;
    def DrawCircleLines(centerX: i32, centerY: i32, radius: f32, color: Color) -> None;
    def DrawRing(center: Vector2, innerRadius: f32, outerRadius: f32, startAngle: f32, endAngle: f32, segments: i32, color: Color) -> None;
    def DrawText(text: str, posX: i32, posY: i32, fontSize: i32, color: Color) -> None;
    def MeasureText(text: str, fontSize: i32) -> i32;

    # 3D
    def DrawCube(position: Vector3, width: f32, height: f32, length: f32, color: Color) -> None;
    def DrawSphereEx(centerPos: Vector3, radius: f32, rings: i32, slices: i32, color: Color) -> None;
    def DrawCylinderEx(startPos: Vector3, endPos: Vector3, startRadius: f32, endRadius: f32, sides: i32, color: Color) -> None;
    def DrawLine3D(startPos: Vector3, endPos: Vector3, color: Color) -> None;

    # fonts
    def LoadFontEx(fileName: str, fontSize: i32, codepoints: ptr[i32] | None, codepointCount: i32) -> Font;
    def IsFontValid(font: Font) -> bool;
    def DrawTextEx(font: Font, text: str, position: Vector2, fontSize: f32, spacing: f32, tint: Color) -> None;
    def MeasureTextEx(font: Font, text: str, fontSize: f32, spacing: f32) -> Vector2;

    # textures + render targets
    def GenTextureMipmaps(texture: &mut Texture) -> None;
    def SetTextureFilter(texture: Texture, filter: i32) -> None;
    def LoadRenderTexture(width: i32, height: i32) -> RenderTexture;
    def IsRenderTextureValid(target: RenderTexture) -> bool;
    def UnloadRenderTexture(target: RenderTexture) -> None;
    def BeginTextureMode(target: RenderTexture) -> None;
    def EndTextureMode -> None;
    def BeginShaderMode(shader: Shader) -> None;
    def EndShaderMode -> None;
    def DrawTexturePro(texture: Texture, source: Rectangle, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) -> None;
    def SetShaderValueTexture(shader: Shader, locIndex: i32, texture: Texture) -> None;

    # models + shaders
    def LoadModel(fileName: str) -> Model;
    def IsModelValid(model: Model) -> bool;
    def GetModelBoundingBox(model: Model) -> BoundingBox;
    def DrawModel(model: Model, position: Vector3, scale: f32, tint: Color) -> None;
    def LoadShader(vsFileName: str, fsFileName: str) -> Shader;
    def IsShaderValid(shader: Shader) -> bool;
    def GetShaderLocation(shader: Shader, uniformName: str) -> i32;
    def SetShaderValue(shader: Shader, locIndex: i32, value: &Vector4, uniformType: i32) -> None;

    # audio
    def InitAudioDevice -> None;
    def IsAudioDeviceReady -> bool;
    def CloseAudioDevice -> None;
    def SetMasterVolume(volume: f32) -> None;
    def LoadSound(fileName: str) -> Sound;
    def LoadSoundAlias(source: Sound) -> Sound;
    def PlaySound(sound: Sound) -> None;
    def StopSound(sound: Sound) -> None;
    def IsSoundPlaying(sound: Sound) -> bool;
    def SetSoundVolume(sound: Sound, volume: f32) -> None;
    def SetSoundPitch(sound: Sound, pitch: f32) -> None;
    def LoadMusicStream(fileName: str) -> Music;
    def PlayMusicStream(music: Music) -> None;
    def StopMusicStream(music: Music) -> None;
    def UpdateMusicStream(music: Music) -> None;
    def SetMusicVolume(music: Music, volume: f32) -> None;
}

glob FLAG_VSYNC_HINT: int = 0x40,
     FLAG_MSAA_4X_HINT: int = 0x20,
     LOG_WARNING: int = 4,
     BLEND_ALPHA: int = 0,
     BLEND_ADDITIVE: int = 1,
     SHADER_UNIFORM_VEC4: int = 3,
     FILTER_BILINEAR: int = 1,
     FILTER_TRILINEAR: int = 2;

glob KEY_SPACE: int = 32,
     KEY_A: int = 65,
     KEY_B: int = 66,
     KEY_D: int = 68,
     KEY_E: int = 69,
     KEY_J: int = 74,
     KEY_K: int = 75,
     KEY_M: int = 77,
     KEY_P: int = 80,
     KEY_Q: int = 81,
     KEY_S: int = 83,
     KEY_W: int = 87,
     KEY_X: int = 88,
     KEY_C: int = 67,
     KEY_L: int = 76,
     KEY_TAB: int = 258,
     KEY_LEFT_CONTROL: int = 341,
     KEY_RIGHT_CONTROL: int = 345,
     KEY_ESCAPE: int = 256,
     KEY_ENTER: int = 257,
     KEY_RIGHT: int = 262,
     KEY_LEFT: int = 263,
     KEY_DOWN: int = 264,
     KEY_UP: int = 265,
     KEY_F11: int = 300,
     KEY_F12: int = 301,
     KEY_LEFT_SHIFT: int = 340,
     KEY_RIGHT_SHIFT: int = 344;

glob PAD_UP: int = 1,
     PAD_DOWN: int = 3,
     PAD_Y: int = 5,
     PAD_B: int = 6,
     PAD_A: int = 7,
     PAD_X: int = 8,
     PAD_LB: int = 9,
     PAD_RB: int = 11,
     PAD_RT: int = 12,
     PAD_LT: int = 10,
     PAD_START: int = 15,
     PAD_AXIS_X: int = 0,
     PAD_AXIS_Y: int = 1;
