shader_type spatial;
// River stones and pebbles (historical style). Vertex color from
// tools/art/make_stone_set.py: R occlusion, G quartz vein, B edge wear.

uniform vec3 stone_color : source_color = vec3(0.14, 0.13, 0.12);
uniform vec3 grain_color : source_color = vec3(0.3, 0.28, 0.25);
uniform vec3 vein_color : source_color = vec3(0.82, 0.8, 0.74);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.45;
uniform float grain_scale = 60.0;
// Selection glow, driven by the game (0 = off).
uniform vec3 glow_color : source_color = vec3(1.0, 0.75, 0.4);
uniform float glow = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

float hash3(vec3 p) {
	return fract(sin(dot(floor(p), vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void fragment() {
	float ao = COLOR.r;
	float vein = COLOR.g;
	float wear = COLOR.b;
	float g = vnoise(obj_pos * grain_scale) * 0.6 + vnoise(obj_pos * grain_scale * 3.1) * 0.4;
	float speck = smoothstep(0.78, 0.82, vnoise(obj_pos * grain_scale * 5.0));
	vec3 base = mix(stone_color, grain_color, g * 0.55);
	base = mix(base, grain_color * 1.4, speck * 0.5);
	base = mix(base, vein_color, smoothstep(0.2, 0.7, vein));
	ALBEDO = base * mix(0.75, 1.0, ao);
	ROUGHNESS = clamp(roughness_base + 0.15 * (1.0 - ao) - 0.12 * wear, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.45;
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = glow_color * glow * (0.25 + rim * 1.5);
}
