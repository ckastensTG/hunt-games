shader_type spatial;
// Prayer flags, used only for the shadows they cast across the board (the
// meshes are shadow-only). Plain cloth: no printed text or images.
render_mode cull_disabled;

uniform float flutter = 1.0;

void vertex() {
	// UV.y = 0 at the string; the free edge moves most.
	float free = UV.y;
	float t = TIME * 2.2 + VERTEX.x * 3.0;
	VERTEX.z += free * flutter * (0.06 * sin(t) + 0.03 * sin(t * 2.7 + 1.3));
	VERTEX.y += free * flutter * 0.02 * sin(t * 1.7);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
