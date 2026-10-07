#version 330
// Vertex colour convention: R = face brightness, G = emissive, B = 0.
// A mesh without colours reads (1,1,1,1); B > 0.5 marks that case as plain lit.
in vec3 fragPos;
in vec3 fragNormal;
in vec4 fragColor;

uniform vec4 colDiffuse;
uniform vec4 lightDir;     // xyz: direction the light travels
uniform vec4 lightColor;
uniform vec4 ambient;
uniform vec4 fogColor;
uniform vec4 fogParams;    // x: start, y: end, z: amount (0 disables)
uniform vec4 viewPos;
uniform vec4 flash;        // rgb: flash colour, a: amount

out vec4 finalColor;

void main() {
    bool plain = fragColor.b > 0.5;
    float shade = plain ? 1.0 : fragColor.r;
    float emis = plain ? 0.0 : fragColor.g;

    vec3 n = normalize(fragNormal);
    vec3 v = normalize(viewPos.xyz - fragPos);
    vec3 albedo = colDiffuse.rgb;

    float ndl = max(dot(n, -normalize(lightDir.xyz)), 0.0);
    float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);
    vec3 lit = albedo * shade * (ambient.rgb + lightColor.rgb * ndl) + rim * 0.22 * lightColor.rgb * shade;
    vec3 c = mix(lit, albedo * (0.9 + 0.25 * shade), emis);

    float d = length(viewPos.xyz - fragPos);
    float f = clamp((d - fogParams.x) / (fogParams.y - fogParams.x), 0.0, 1.0) * fogParams.z;
    c = mix(c, fogColor.rgb, f * (1.0 - 0.5 * emis));
    c = mix(c, flash.rgb, flash.a);
    finalColor = vec4(c, colDiffuse.a);
}
