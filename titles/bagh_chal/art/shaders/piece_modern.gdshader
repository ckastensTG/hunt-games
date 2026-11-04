shader_type spatial;
// "Modern edition" pieces: glossy plastic figures, painted like designer
// vinyl toys (the same parameters also make glazed ceramic, for the mug).
// tools/art/make_modern_set.py. Vertex color:
//   R ambient occlusion   G where the tiger's stripes may go   B edges
// The tiger's markings (stripes, white muzzle, cheeks, chest and belly,
// eyes, nose, black ear backs and tail tip) are painted per pixel from the
// figure's own position, so they stay crisp at any size. The positions
// match the tiger in make_modern_set.py (it faces -z, head near z = -0.2).

uniform vec3 glaze_color : source_color = vec3(0.97, 0.44, 0.07);
uniform vec3 stripe_color : source_color = vec3(0.06, 0.055, 0.05);
uniform vec3 white_color : source_color = vec3(0.96, 0.94, 0.9);
uniform vec3 eye_color : source_color = vec3(0.03, 0.028, 0.026);
uniform vec3 nose_color : source_color = vec3(0.45, 0.2, 0.18);
// 1 paints the tiger's markings; 0 leaves the plain glaze (goats, the mug).
uniform float stripes : hint_range(0.0, 1.0) = 0.0;
uniform float glaze_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.5;
// Iron specks in the clay body (speckled stoneware), 0 = none.
uniform float specks : hint_range(0.0, 1.0) = 0.0;
// Selection glow, driven by the game (0 = off).
uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.25);
uniform float glow = 0.0;

varying vec3 obj_pos;
varying vec3 obj_n;

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
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

// Inside an ellipsoid round c (1 inside, 0 outside, antialiased).
float blob(vec3 p, vec3 c, vec3 r) {
	float e = length((p - c) / r);
	float aa = max(fwidth(e), 0.02);
	return 1.0 - smoothstep(1.0 - aa, 1.0 + aa, e);
}

float band_mask(float band, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, band);
}

// Stripes round the girth that sweep back down the flanks from the spine and
// taper to points toward the belly; their spacing and width vary like fur.
float body_stripes(vec3 p) {
	float a = atan(abs(p.x), p.y - 0.06);          // 0 on the spine, ~1.6 at mid-flank
	float t = clamp(a / 1.9, 0.0, 1.0);
	float warp = (vnoise(p * 24.0) - 0.5) * 0.7 + (vnoise(p * 61.0 + 3.1) - 0.5) * 0.2;
	float u = p.z * 24.0 + a * 1.3 + warp;
	float id = floor(u);
	float band = abs(fract(u) - 0.5) * 2.0;
	float w = (0.3 + 0.22 * hash3(vec3(id, 2.0, 5.0))) * pow(1.0 - t, 0.7);
	// Some stripes break on the spine, some stop high on the flank.
	w *= step(0.18, a) + step(hash3(vec3(id, 7.0, 1.0)), 0.6);
	w *= 1.0 - step(0.55 + 0.4 * hash3(vec3(id, 3.0, 9.0)), t);
	float aa = clamp(fwidth(u) * 1.5, 0.02, 0.3);
	float region = smoothstep(-0.115, -0.085, p.z) * (1.0 - smoothstep(0.205, 0.225, p.z));
	return band_mask(band, w, aa) * region;
}

float head_stripes(vec3 p) {
	float aa = 0.06;
	// Forehead: three thin marks running back over the crown.
	float fore = band_mask(abs(fract(p.x * 31.0 + 0.5) - 0.5) * 2.0, 0.28, aa)
		* step(0.25, p.y) * step(p.z, -0.125) * step(-0.235, p.z) * step(abs(p.x), 0.05);
	// Cheeks: three short sweeps on each side, rising toward the ears and
	// tapering to points at the front.
	float cu = (p.y - 0.4 * (p.z + 0.17)) * 75.0;
	float taper = smoothstep(-0.21, -0.165, p.z) * (1.0 - smoothstep(-0.13, -0.115, p.z));
	float cheek = band_mask(abs(fract(cu) - 0.5) * 2.0, 0.34 * taper, aa)
		* step(0.066, abs(p.x)) * smoothstep(0.172, 0.18, p.y) * (1.0 - smoothstep(0.222, 0.232, p.y));
	return max(fore, cheek);
}

float leg_tail_stripes(vec3 p) {
	float aa = 0.08;
	// Front legs: rings on the outside, not on the paws.
	float leg = band_mask(abs(fract(p.z * 36.0) - 0.5) * 2.0, 0.3, aa)
		* step(p.z, -0.12) * step(-0.19, p.z) * step(p.y, 0.1) * step(0.035, p.y)
		* step(0.03, abs(p.x));
	// Tail: rings along its length.
	float tail_zone = step(0.105, p.x) * step(p.y, 0.065) + step(0.19, p.z) * step(0.02, p.x);
	float tu = (p.z * 0.8 - p.x * 0.6) * 44.0;
	float tail = band_mask(abs(fract(tu) - 0.5) * 2.0, 0.38, aa) * clamp(tail_zone, 0.0, 1.0);
	return max(leg, tail);
}

void fragment() {
	float ao = COLOR.r;
	float region = COLOR.g;
	vec3 p = obj_pos;
	vec3 mx = vec3(abs(p.x), p.y, p.z);                  // mirrored for paired marks
	vec3 base = glaze_color;
	float sp = specks * smoothstep(0.86, 0.9, vnoise(p * 260.0)) * smoothstep(0.5, 0.7, vnoise(p * 31.0 + 7.0));
	base = mix(base, base * 0.45, sp);
	vec3 col = base;
	float rough = glaze_roughness;
	if (stripes > 0.5) {
		float allowed = smoothstep(0.3, 0.7, region);
		float s = max(max(body_stripes(p), head_stripes(p)), leg_tail_stripes(p)) * allowed;
		// White: muzzle and chin, lower cheeks, spots over the eyes, chest,
		// belly, the inside of the ears.
		float white = max(blob(p, vec3(0.0, 0.19, -0.238), vec3(0.052, 0.04, 0.04)),
			blob(p, vec3(0.0, 0.162, -0.215), vec3(0.04, 0.026, 0.035)));
		white = max(white, blob(mx, vec3(0.06, 0.176, -0.2), vec3(0.042, 0.03, 0.04)));
		white = max(white, blob(mx, vec3(0.03, 0.258, -0.219), vec3(0.015, 0.009, 0.012)));
		white = max(white, blob(p, vec3(0.0, 0.122, -0.145), vec3(0.04, 0.045, 0.04)));
		white = max(white, smoothstep(-0.15, -0.45, obj_n.y) * (1.0 - smoothstep(0.03, 0.05, p.y)));
		float ear = blob(mx, vec3(0.06, 0.29, -0.145), vec3(0.04, 0.04, 0.03));
		white = max(white, ear * smoothstep(-0.1, -0.5, obj_n.z));
		float dark = s * (1.0 - white);
		dark = max(dark, ear * smoothstep(0.1, 0.5, obj_n.z));                     // black ear backs
		dark = max(dark, blob(p, vec3(0.122, 0.02, -0.058), vec3(0.03, 0.03, 0.03))); // tail tip
		col = mix(col, white_color, white);
		col = mix(col, stripe_color, dark);
		rough = mix(rough, 0.34, dark);
		// Eyes and nose: glossy paint.
		float eye = blob(mx, vec3(0.033, 0.232, -0.226), vec3(0.016, 0.0095, 0.012));
		float nose = blob(p, vec3(0.0, 0.207, -0.258), vec3(0.017, 0.011, 0.012));
		float mouth = blob(p, vec3(0.0, 0.188, -0.261), vec3(0.0035, 0.016, 0.012));
		col = mix(col, eye_color, eye);
		col = mix(col, nose_color, max(nose, mouth * 0.85));
		rough = mix(rough, 0.12, max(eye, nose));
	}
	// The glaze pools darker in the recesses.
	col *= mix(0.8, 1.0, ao);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = 0.15;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = glow_color * glow * (0.25 + rim * 1.5);
}
