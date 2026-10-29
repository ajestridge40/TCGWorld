shader_type canvas_item;
// Holographic foil sheen: a slow diagonal rainbow band plus sparkle noise.
// `strength` 0..1. Set `prism` for the stronger secret-rare look.

uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform float prism = 0.0;
uniform vec2 tilt = vec2(0.0, 0.0);

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float band = UV.x * 1.2 + UV.y * 0.8 + TIME * 0.25 + tilt.x * 0.6 + tilt.y * 0.4;
	vec3 rainbow = hue(fract(band));
	float sheen = smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(band * 6.2831 * (1.0 + prism)));
	float sparkle = step(0.985 - prism * 0.01, hash(floor(UV * 90.0) + floor(TIME * 3.0)));
	vec3 col = mix(base.rgb, base.rgb * 0.6 + rainbow * 0.6, strength * sheen);
	col += sparkle * strength * 0.8;
	COLOR = vec4(col, base.a);
}
