shader_type spatial;
// Move highlights as opaque ink, for pale boards where added light would not
// show (HuntArtStyle.mark_ink). Same shapes as mark.gdshader.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://scenes/greybox/mark_shapes.gdshaderinc"

uniform int shape = 0;
uniform vec3 color : source_color = vec3(0.9, 0.4, 0.05);
uniform float energy = 1.6;    // unused: kept so both shaders take the same parameters

void fragment() {
	vec2 m = mark_shape(UV, shape, TIME);
	ALBEDO = color;
	ALPHA = clamp(m.x + m.y * 0.7, 0.0, 1.0);
}
