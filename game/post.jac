"""Post-processing: the 3D scene renders supersampled into an offscreen target,
bloom is built at quarter resolution (bright-pass, then two separable blur
passes), and the composite pass downsamples, adds the glow and a vignette.

Frame order: scene_begin -> draw 3D -> scene_end -> post_apply ->
BeginDrawing -> post_draw -> 2D overlays -> EndDrawing.
"""

import from rl {
    Vector2, Vector4, Rectangle, Color, Shader, RenderTexture, LoadShader,
    GetShaderLocation, SetShaderValue, SetShaderValueTexture, LoadRenderTexture,
    UnloadRenderTexture, BeginTextureMode, EndTextureMode, BeginShaderMode,
    EndShaderMode, DrawTexturePro, SetTextureFilter, ClearBackground
}
import from gfx { rgba }

obj Post {
    has scene: RenderTexture,
        half: RenderTexture,
        a: RenderTexture,
        b: RenderTexture,
        bright: Shader,
        blur: Shader,
        composite: Shader,
        loc_bright: int = -1,
        loc_blur: int = -1,
        loc_comp: int = -1,
        loc_bloom: int = -1,
        w: int = 0,
        h: int = 0,
        ss: float = 2.0,
        bloom: float = 1.15;
}

def vec4_uniform(sh: Shader, loc: int, x: float, y: float, z: float, w: float) {
    v = Vector4(x=f32(x), y=f32(y), z=f32(z), w=f32(w));
    SetShaderValue(sh, i32(loc), &v, i32(3));
}

def make_target(w: int, h: int) -> RenderTexture {
    rt = LoadRenderTexture(i32(w), i32(h));
    SetTextureFilter(rt.texture, i32(1));
    return rt;
}

def post_load(base: str, w: int, h: int, ss: float) -> Post {
    vs = base + "/shaders/post.vs";
    p = Post(
        scene=make_target(int(float(w) * ss), int(float(h) * ss)),
        half=make_target(w // 2, h // 2),
        a=make_target(w // 4, h // 4),
        b=make_target(w // 4, h // 4),
        bright=LoadShader(vs, base + "/shaders/bright.fs"),
        blur=LoadShader(vs, base + "/shaders/blur.fs"),
        composite=LoadShader(vs, base + "/shaders/composite.fs"),
        w=w,
        h=h,
        ss=ss
    );
    p.loc_bright = int(GetShaderLocation(p.bright, "params"));
    p.loc_blur = int(GetShaderLocation(p.blur, "params"));
    p.loc_comp = int(GetShaderLocation(p.composite, "params"));
    p.loc_bloom = int(GetShaderLocation(p.composite, "bloomTex"));
    return p;
}

"""Recreate the targets when the window size changes (fullscreen toggle)."""
def post_resize(p: Post, w: int, h: int) {
    if w == p.w and h == p.h or w <= 0 or h <= 0 {
        return;
    }
    UnloadRenderTexture(p.scene);
    UnloadRenderTexture(p.half);
    UnloadRenderTexture(p.a);
    UnloadRenderTexture(p.b);
    p.scene = make_target(int(float(w) * p.ss), int(float(h) * p.ss));
    p.half = make_target(w // 2, h // 2);
    p.a = make_target(w // 4, h // 4);
    p.b = make_target(w // 4, h // 4);
    p.w = w;
    p.h = h;
}

def scene_begin(p: Post) {
    BeginTextureMode(p.scene);
    ClearBackground(rgba(0, 0, 0, 255));
}

def scene_end(p: Post) {
    EndTextureMode();
}

"""Draw `src` (a render texture, so flipped vertically) over all of `dst`."""
def blit(src: RenderTexture, dst_w: int, dst_h: int) {
    t = src.texture;
    DrawTexturePro(
        t,
        Rectangle(x=f32(0.0), y=f32(0.0), width=f32(float(t.width)), height=f32(-float(t.height))),
        Rectangle(x=f32(0.0), y=f32(0.0), width=f32(float(dst_w)), height=f32(float(dst_h))),
        Vector2(x=f32(0.0), y=f32(0.0)),
        f32(0.0),
        rgba(255, 255, 255, 255)
    );
}

def pass_into(dst: RenderTexture, src: RenderTexture, sh: Shader) {
    BeginTextureMode(dst);
    BeginShaderMode(sh);
    blit(src, int(dst.texture.width), int(dst.texture.height));
    EndShaderMode();
    EndTextureMode();
}

def post_apply(p: Post) {
    sw = float(p.scene.texture.width);
    sh = float(p.scene.texture.height);
    vec4_uniform(p.bright, p.loc_bright, 1.0 / sw, 1.0 / sh, 0.88, 0.12);
    pass_into(p.half, p.scene, p.bright);
    hw = float(p.half.texture.width);
    hh = float(p.half.texture.height);
    vec4_uniform(p.bright, p.loc_bright, 0.5 / hw, 0.5 / hh, 0.0, 0.0001);
    pass_into(p.a, p.half, p.bright);
    aw = 1.0 / float(p.a.texture.width);
    ah = 1.0 / float(p.a.texture.height);
    for spread in [1.0, 2.2] {
        vec4_uniform(p.blur, p.loc_blur, aw * spread, 0.0, 0.0, 0.0);
        pass_into(p.b, p.a, p.blur);
        vec4_uniform(p.blur, p.loc_blur, 0.0, ah * spread, 0.0, 0.0);
        pass_into(p.a, p.b, p.blur);
    }
}

"""Composite onto the screen; call between BeginDrawing and the 2D overlays."""
def post_draw(p: Post) {
    BeginShaderMode(p.composite);
    vec4_uniform(p.composite, p.loc_comp, p.bloom, 0.55, 0.08, 0.0);
    SetShaderValueTexture(p.composite, i32(p.loc_bloom), p.a.texture);
    blit(p.scene, p.w, p.h);
    EndShaderMode();
}
