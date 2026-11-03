shader_type spatial;
// Butter-lamp flame: a camera-facing teardrop that flickers.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.86, 0.55);
uniform vec3 edge_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float energy = 3.0;
uniform float seed = 0.0;

varying float flicker;

void vertex() {
	// Billboard around the local Y axis.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz * vec3(1.0, 0.0, 1.0)), 0.0),
		MODEL_MATRIX[3]);
	float t = TIME * 7.0 + seed * 13.0;
	flicker = 0.82 + 0.1 * sin(t) + 0.06 * sin(t * 2.3 + 1.0) + 0.04 * sin(t * 5.1);
	VERTEX.x += sin(t * 0.9) * 0.15 * VERTEX.y * VERTEX.y;
	VERTEX.y *= flicker;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;          // -1..1, y down
	p.y = -p.y;
	// Teardrop: round bottom, pointed top.
	float w = mix(1.0, 0.0, clamp((p.y + 0.4) / 1.4, 0.0, 1.0));
	float d = length(vec2(p.x / max(w, 0.05), (p.y + 0.4) * 0.9));
	float body = 1.0 - smoothstep(0.55, 1.0, d);
	float core = 1.0 - smoothstep(0.0, 0.55, length(vec2(p.x * 2.2, p.y + 0.55)));
	vec3 c = mix(edge_color, core_color, core);
	ALBEDO = c * (body + core) * energy * flicker;
}
