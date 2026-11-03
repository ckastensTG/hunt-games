shader_type spatial;
// Courtyard paving: basket-weave brick, worn and dusty. Seen out of focus at
// the frame edges, so it only needs the right rhythm and color.

uniform vec3 brick_a : source_color = vec3(0.40, 0.18, 0.10);
uniform vec3 brick_b : source_color = vec3(0.27, 0.12, 0.07);
uniform vec3 mortar : source_color = vec3(0.17, 0.15, 0.13);
uniform float brick_width = 0.22;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Rotate 45 degrees, then 2x2 cells holding two bricks each, alternating
	// direction like a checkerboard.
	vec2 p = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * world.xz / brick_width;
	vec2 cell = floor(p / 2.0);
	vec2 f = p - cell * 2.0;                 // 0..2 inside the cell
	bool flip = mod(cell.x + cell.y, 2.0) == 1.0;
	if (flip) { f = f.yx; }
	float row = floor(f.y);                  // which of the two bricks
	vec2 local = vec2(f.x / 2.0, fract(f.y)); // 0..1 along, 0..1 across
	float edge = min(min(local.x, 1.0 - local.x) * 2.0, min(local.y, 1.0 - local.y));
	float m = smoothstep(0.02, 0.06, edge);
	vec2 id = cell * 3.0 + vec2(row, flip ? 1.0 : 0.0);
	float h = hash(id);
	vec3 brick = mix(brick_a, brick_b, h) * (0.85 + 0.3 * hash(id + 3.1));
	ALBEDO = mix(mortar, brick, m);
	ROUGHNESS = mix(0.95, 0.82, m);
}
