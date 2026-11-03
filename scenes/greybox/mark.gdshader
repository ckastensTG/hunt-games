shader_type spatial;
// Move highlights, drawn flat on the board. They differ in shape as well as
// color, so they read for colorblind players too (framework §6):
//   0 selected piece   a double ring that breathes
//   1 legal step       a small solid dot
//   2 capture landing  a ring broken into four arcs
//   3 last move        a thin diamond
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform int shape = 0;
uniform vec3 color : source_color = vec3(1.0, 0.8, 0.4);
uniform float energy = 1.6;

float band(float d, float r, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.012, abs(d - r));
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * 0.5;     // the quad is 1 unit: p in -0.5..0.5
	float d = length(p);
	float a = 0.0;
	float glow = 0.0;
	if (shape == 0) {
		float breathe = 0.85 + 0.15 * sin(TIME * 3.0);
		a = max(band(d, 0.36, 0.035), band(d, 0.3, 0.012) * 0.7) * breathe;
		glow = exp(-pow((d - 0.36) / 0.06, 2.0)) * 0.35;
	} else if (shape == 1) {
		a = 1.0 - smoothstep(0.075, 0.09, d);
		glow = exp(-pow(d / 0.16, 2.0)) * 0.4;
	} else if (shape == 2) {
		float ang = atan(p.y, p.x);
		float gaps = smoothstep(0.18, 0.3, abs(sin(ang * 2.0)));
		a = band(d, 0.3, 0.04) * gaps + (1.0 - smoothstep(0.045, 0.06, d));
		glow = exp(-pow((d - 0.3) / 0.07, 2.0)) * 0.35;
	} else {
		float dd = abs(p.x) + abs(p.y);
		a = band(dd, 0.32, 0.018);
	}
	ALBEDO = color * energy * (a + glow);
}
