shader_type spatial;
// "Modern edition" pieces: glazed ceramic figurines
// (tools/art/make_modern_set.py). Vertex color:
//   R ambient occlusion   G where the tiger's stripes may go   B edges
// The tiger's stripes are a bold graphic pattern drawn per pixel from the
// figure's own position, so they stay crisp at any size.

uniform vec3 glaze_color : source_color = vec3(0.86, 0.43, 0.17);
uniform vec3 stripe_color : source_color = vec3(0.07, 0.065, 0.06);
uniform float stripes : hint_range(0.0, 1.0) = 0.0;
uniform float glaze_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.5;
// Iron specks in the clay body (speckled stoneware), 0 = none.
uniform float specks : hint_range(0.0, 1.0) = 0.0;
// Selection glow, driven by the game (0 = off).
uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.25);
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

// The lying tiger faces -z: head near z = -0.16, rump near z = +0.15, the
// tail curling round its right side (+x).
float stripe_mask(vec3 p, float aa) {
	// Back and flanks: chevrons pointing toward the head, tapering down the sides.
	float side = abs(p.x);
	float band = abs(sin(p.z * 34.0 - side * 9.0 + 0.6));
	float width = mix(0.9, 0.74, clamp((p.y - 0.05) / 0.12, 0.0, 1.0));
	float body = smoothstep(width - aa, width + aa, band) * step(-0.09, p.z) * step(p.z, 0.2)
		* step(p.x, 0.115);
	// Forehead: three short marks.
	float fore = smoothstep(0.84 - aa, 0.84 + aa, abs(cos(p.x * 58.0)))
		* step(p.z, -0.12) * step(0.235, p.y) * step(side, 0.07);
	// Cheeks: one sweep each side.
	float cheek = smoothstep(0.86 - aa, 0.86 + aa, abs(sin(p.y * 70.0 + p.z * 20.0)))
		* step(0.075, side) * step(p.z, -0.11) * step(0.15, p.y);
	// Tail: rings.
	float tl = smoothstep(0.75 - aa, 0.75 + aa, abs(sin((p.z - p.x * 0.4) * 46.0)))
		* step(0.115, p.x) * step(p.y, 0.075);
	return max(max(body, fore), max(cheek, tl));
}

void fragment() {
	float ao = COLOR.r;
	float region = COLOR.g;
	float aa = clamp(fwidth(obj_pos.z) * 30.0, 0.02, 0.2);
	float mark = stripes * smoothstep(0.35, 0.8, region) * stripe_mask(obj_pos, aa);
	vec3 base = glaze_color;
	float sp = specks * smoothstep(0.86, 0.9, vnoise(obj_pos * 260.0)) * smoothstep(0.5, 0.7, vnoise(obj_pos * 31.0 + 7.0));
	base = mix(base, base * 0.45, sp);
	// The glaze pools darker in the recesses.
	base *= mix(0.8, 1.0, ao);
	ALBEDO = mix(base, stripe_color, mark);
	ROUGHNESS = mix(glaze_roughness, 0.55, mark);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat_amount * (1.0 - mark * 0.6);
	CLEARCOAT_ROUGHNESS = 0.15;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = glow_color * glow * (0.25 + rim * 1.5);
}
