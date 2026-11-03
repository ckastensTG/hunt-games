shader_type spatial;
// A tree leaf cut out of a quad, for dappled shadows. Used on shadow-only
// meshes: the player sees the leaves' moving shadows, not the leaves. The
// shape is computed here, so no texture is needed. (A plain leaf on purpose:
// no particular tree, and nothing that reads as a sacred motif, bible §8.)
render_mode cull_disabled;

uniform float sway = 1.0;

void vertex() {
	float t = TIME * 1.3 + MODEL_MATRIX[3].x * 0.7 + MODEL_MATRIX[3].z * 0.4;
	VERTEX.y += sway * 0.04 * sin(t + VERTEX.x * 3.0);
	VERTEX.x += sway * 0.03 * sin(t * 1.7);
}

void fragment() {
	// Ovate leaf with a pointed tip at +v.
	vec2 p = UV * 2.0 - 1.0;                 // -1..1
	float y = -p.y;                          // +1 at the tip
	float w = 0.62 * pow(max(0.0, 1.0 - y * y), 0.6) * (1.0 - 0.35 * smoothstep(0.2, 1.0, y));
	if (abs(p.x) > w) {
		discard;
	}
	ALBEDO = vec3(0.2, 0.32, 0.12);
	ROUGHNESS = 0.8;
}
