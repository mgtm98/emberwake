#version 330
// Final image: supersampled scene + bloom, vignette, gentle filmic shoulder.
in vec2 fragTexCoord;
uniform sampler2D texture0;   // scene
uniform sampler2D bloomTex;   // blurred bright-pass
uniform vec4 params;          // x: bloom strength, y: vignette, z: saturation boost
out vec4 finalColor;
void main() {
    vec3 base = texture(texture0, fragTexCoord).rgb;
    vec3 glow = texture(bloomTex, fragTexCoord).rgb;
    vec3 c = base + glow * params.x;
    c = c / (1.0 + max(c - 1.0, 0.0));                 // soft shoulder above 1.0
    float g = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(g), c, 1.0 + params.z);
    vec2 d = fragTexCoord - 0.5;
    c *= clamp(1.0 - dot(d, d) * params.y, 0.0, 1.0);
    finalColor = vec4(c, 1.0);
}
