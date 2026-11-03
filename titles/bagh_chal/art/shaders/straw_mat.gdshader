shader_type spatial;
// A straw sitting mat (sukul): straws laid side by side, bound with rows of
// twisted straw rope, with a rope edge. Drawn entirely here, so it costs no
// texture memory. For a BoxMesh: coordinates are the mesh's own, in units.

uniform vec3 straw_light : source_color = vec3(0.8, 0.66, 0.4);
uniform vec3 straw_dark : source_color = vec3(0.58, 0.45, 0.25);
uniform vec3 rope_color : source_color = vec3(0.45, 0.33, 0.18);
uniform vec2 half_size = vec2(5.5, 4.5);
uniform float straw_width = 0.085;
uniform float row_spacing = 0.72;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = obj_pos.xz;
	// Straws run along x, each a little different in color, with joints.
	float strand = floor(p.y / straw_width);
	float across = fract(p.y / straw_width) * 2.0 - 1.0;        // -1..1 over one straw
	float round_shade = sqrt(max(1.0 - across * across, 0.0));
	float h = hash(strand);
	float joint = step(0.94, fract(p.x / (1.1 + h * 0.8) + h * 3.0));
	vec3 straw = mix(straw_dark, straw_light, 0.35 + 0.65 * h) * (0.7 + 0.3 * round_shade);
	straw *= 1.0 - 0.3 * joint;
	// Binding rows: a pair of twisted cords across the straws.
	float local_x = fract(p.x / row_spacing + 0.5) * row_spacing - row_spacing * 0.5;
	float cord_d = min(abs(local_x - 0.035), abs(local_x + 0.035));
	float in_cord = 1.0 - smoothstep(0.022, 0.03, cord_d);
	float twist = fract(p.y / 0.055 + local_x * 14.0);
	float twist_shade = 0.7 + 0.4 * smoothstep(0.15, 0.45, twist) * (1.0 - smoothstep(0.55, 0.9, twist));
	// Rope edge round the border, and on the mat's thin sides.
	vec2 edge_d = half_size - abs(p);
	float border = 1.0 - smoothstep(0.1, 0.14, min(edge_d.x, edge_d.y));
	float side = 1.0 - smoothstep(0.3, 0.6, obj_normal.y);
	float rope = max(in_cord, max(border, side));
	vec3 rope_col = rope_color * twist_shade;
	ALBEDO = mix(straw, rope_col, rope);
	ROUGHNESS = mix(0.7, 0.85, rope);
	SPECULAR = 0.35;
	// Each straw is round: tilt the normal across it.
	vec3 tilt = vec3(0.0, -across * 0.35 * (1.0 - rope), 1.0);
	NORMAL_MAP = normalize(tilt) * 0.5 + 0.5;
}
