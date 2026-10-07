#version 330
// Bloom bright-pass: 4-tap box downsample, keep what is brighter than the threshold.
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec4 params;   // xy: source texel size, z: threshold, w: knee
out vec4 finalColor;
void main() {
    vec2 o = params.xy;
    vec3 c = texture(texture0, fragTexCoord + vec2(-o.x, -o.y)).rgb
           + texture(texture0, fragTexCoord + vec2( o.x, -o.y)).rgb
           + texture(texture0, fragTexCoord + vec2(-o.x,  o.y)).rgb
           + texture(texture0, fragTexCoord + vec2( o.x,  o.y)).rgb;
    c *= 0.25;
    float l = max(c.r, max(c.g, c.b));
    float k = smoothstep(params.z, params.z + params.w, l);
    finalColor = vec4(c * k, 1.0);
}
