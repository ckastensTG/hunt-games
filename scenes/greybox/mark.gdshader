shader_type spatial;
// Move highlights as added light, drawn flat on the board: they glow on dark
// and metal boards. Shapes: mark_shapes.gdshaderinc.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://scenes/greybox/mark_shapes.gdshaderinc"

uniform int shape = 0;
uniform vec3 color : source_color = vec3(1.0, 0.8, 0.4);
uniform float energy = 1.6;

void fragment() {
	vec2 m = mark_shape(UV, shape, TIME);
	ALBEDO = color * energy * (m.x + m.y);
}
