shader_type spatial;
// Cast-metal game pieces (Bagh Chal tigers and goats).
// Vertex color from tools/art/make_pieces.py:
//   R ambient occlusion: patina gathers in recesses
//   G where engraved marks may go (the tiger stripes are drawn here, per pixel)
//   B edge wear: ridges rubbed bright by handling

uniform vec3 metal_color : source_color = vec3(0.80, 0.60, 0.30);
uniform vec3 patina_color : source_color = vec3(0.16, 0.11, 0.06);
uniform vec3 marks_color : source_color = vec3(0.045, 0.035, 0.028);
uniform float polish_roughness : hint_range(0.0, 1.0) = 0.24;
uniform float patina_roughness : hint_range(0.0, 1.0) = 0.62;
uniform float stripes : hint_range(0.0, 1.0) = 0.0;
uniform float wear_shine : hint_range(0.0, 1.0) = 0.5;
// Selection / awakening rim glow, driven by the game (0 = off).
uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.25);
uniform float glow = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

// Same pattern as stripe_pattern() in tools/art/make_pieces.py.
float stripe_mask(vec3 p, float aa) {
	float w = sin(p.x * 23.0 + p.z * 11.0) * 0.5 + sin(p.z * 37.0 - p.y * 19.0) * 0.25;
	float width = 0.80 + 0.12 * clamp((p.y - 0.11) / 0.12, 0.0, 1.0);
	float flank_band = abs(sin(p.z * 31.0 + abs(p.x) * 10.0 + w * 1.6));
	float flank = smoothstep(width - aa, width + aa, flank_band)
		* step(-0.21, p.z) * step(p.z, 0.19);
	float head_band = abs(sin(p.x * 64.0 + w * 2.0));
	float head = smoothstep(0.86 - aa, 0.86 + aa, head_band)
		* step(p.z, -0.21) * step(-0.31, p.z) * step(0.21, p.y);
	float td = length(p - vec3(0.0, 0.19, 0.19));
	float tail = smoothstep(0.72 - aa, 0.72 + aa, abs(sin(td * 52.0))) * step(0.21, p.z);
	return max(flank, max(head, tail));
}

void fragment() {
	float ao = COLOR.r;
	float region = COLOR.g;
	float wear = COLOR.b;
	float patina = clamp((1.0 - ao) * 1.7, 0.0, 1.0);
	float aa = clamp(fwidth(obj_pos.z) * 30.0, 0.02, 0.2);
	float mark = stripes * smoothstep(0.35, 0.8, region) * stripe_mask(obj_pos, aa);

	vec3 base = mix(metal_color, patina_color, patina * 0.85);
	base = mix(base, metal_color * 1.12, wear * wear_shine);
	ALBEDO = mix(base, marks_color, mark);
	METALLIC = mix(1.0, 0.15, mark);
	ROUGHNESS = clamp(mix(mix(polish_roughness, patina_roughness, patina), 0.78, mark) - wear * 0.1, 0.05, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = glow_color * glow * (0.25 + rim * 1.5);
}
