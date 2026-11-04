shader_type spatial;
// Turned pottery for set dressing (HuntArtStyle.clay_cup): bare fired clay,
// or a glaze over the clay that stops short of the foot. Works in object
// space: y up, the vessel's axis at x = z = 0, height = `height`.

uniform vec3 clay : source_color = vec3(0.62, 0.35, 0.22);
uniform vec3 clay_dark : source_color = vec3(0.4, 0.2, 0.12);      // fire marks
uniform float clay_roughness : hint_range(0.0, 1.0) = 0.9;
uniform vec3 glaze : source_color = vec3(0.56, 0.66, 0.58);
uniform vec3 glaze_thin : source_color = vec3(0.42, 0.36, 0.26);   // where the glaze breaks thin
uniform float glazed : hint_range(0.0, 1.0) = 0.0;
uniform float glaze_line : hint_range(0.0, 1.0) = 0.2;              // outside, as a fraction of the height
uniform float glaze_roughness : hint_range(0.0, 1.0) = 0.1;
uniform float height = 0.62;
uniform float throw_rings : hint_range(0.0, 2.0) = 1.0;            // the potter's finger ridges

varying vec3 op;
varying vec3 on;

void vertex() {
	op = VERTEX;
	on = NORMAL;
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
	float h = clamp(op.y / height, 0.0, 1.0);
	float r = length(op.xz);
	// The inside: walls that face the axis, and the floor of the cup.
	float facing_in = smoothstep(0.0, -0.2, dot(on.xz, op.xz) / max(r, 1e-4));
	float floor_in = step(0.5, on.y) * step(0.02, op.y) * step(h, 0.5);
	float inner = max(facing_in, floor_in);
	// Throwing rings: soft, uneven ridges up the wall.
	float wob = (vnoise(vec3(op.xz * 18.0, op.y * 4.0)) - 0.5) * 2.4;
	float u = op.y * 150.0 + wob;
	float slope = cos(u) * throw_rings * (1.0 - step(0.97, h)) * step(0.03, h);
	vec3 up_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(NORMAL + up_view * slope * 0.07);
	// Bare clay: mottled where the fire touched it, a fine grain, a slightly
	// paler rim worn by lips, dust settled inside.
	float mott = vnoise(op * 4.5) * 0.65 + vnoise(op * 15.0 + 4.0) * 0.35;
	vec3 c = mix(clay, clay_dark, smoothstep(0.45, 0.9, mott) * 0.35);
	c *= 0.9 + 0.14 * vnoise(op * 90.0);
	c = mix(c, c * 1.12, smoothstep(0.93, 1.0, h));
	float rough = clay_roughness;
	// Glaze: all of the inside, the outside down to a wavering dip line.
	float line = glaze_line + (vnoise(op * 12.0) - 0.5) * 0.06;
	float g = glazed * max(inner, smoothstep(line - 0.01, line + 0.01, h));
	float thin = max(smoothstep(0.95, 1.0, h), smoothstep(0.03, 0.0, abs(h - line)) * (1.0 - inner));
	vec3 gc = mix(glaze, glaze_thin, thin * 0.7);
	gc *= 0.95 + 0.1 * vnoise(op * 30.0);
	c = mix(c, gc, g);
	rough = mix(rough, glaze_roughness, g);
	// Light falls off down inside the cup.
	float occ = mix(1.0, mix(0.45, 1.0, smoothstep(0.1, 0.95, h)), inner);
	ALBEDO = c * mix(1.0, occ, 0.5);
	AO = occ;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.5, g);
}
