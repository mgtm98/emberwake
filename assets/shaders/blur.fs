#version 330
// Separable 9-tap Gaussian along params.xy (texel size times direction times spread).
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec4 params;
out vec4 finalColor;
void main() {
    float w[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec3 c = texture(texture0, fragTexCoord).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        vec2 o = params.xy * float(i);
        c += texture(texture0, fragTexCoord + o).rgb * w[i];
        c += texture(texture0, fragTexCoord - o).rgb * w[i];
    }
    finalColor = vec4(c, 1.0);
}
