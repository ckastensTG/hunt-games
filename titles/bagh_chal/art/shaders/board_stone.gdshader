shader_type spatial;
// The scratched stone board (historical style). Textures from
// tools/art/make_stone_set.py. When the board "awakens" the chalked lines
// warm very slightly: much quieter than the brass board's glow.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D glow_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float awaken : hint_range(0.0, 1.0) = 0.0;
uniform float glow_energy = 0.45;

varying float facing_up;

void vertex() {
	facing_up = NORMAL.y;
}

void fragment() {
	vec3 orm = texture(orm_tex, UV).rgb;
	float top = smoothstep(0.5, 0.9, facing_up);
	// The weathered edge is a little darker and rougher than the face.
	ALBEDO = texture(albedo_tex, UV).rgb * mix(0.78, 1.0, top);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = mix(0.92, orm.g, top);
	METALLIC = 0.0;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, UV).rgb, top);
	EMISSION = glow_color * texture(glow_tex, UV).r * top * awaken * glow_energy;
}
