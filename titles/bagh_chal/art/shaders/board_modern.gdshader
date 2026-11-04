shader_type spatial;
// "Modern edition" board: pale oak with a flush charcoal inlay
// (tools/art/make_modern_set.py). When the board awakens, the inlay warms
// from within, like a line of light set into the wood (art direction A).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D glow_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.6, 0.28);
uniform float awaken : hint_range(0.0, 1.0) = 0.0;
uniform float glow_energy = 1.1;
uniform float half_size = 2.75;

varying vec3 local_n;
varying vec3 local_p;

void vertex() {
	local_n = NORMAL;
	local_p = VERTEX;
}

void fragment() {
	float top = smoothstep(0.55, 0.9, local_n.y);
	// The sides show the same oak: long grain on the faces along x, a darker
	// end grain on the others, both sampled from the top texture.
	vec2 side_uv = abs(local_n.x) > abs(local_n.z)
		? vec2(0.5 + local_p.y * 0.35, local_p.z / (2.0 * half_size) + 0.5)
		: vec2(local_p.x / (2.0 * half_size) + 0.5, 0.5 + local_p.y * 0.35);
	// Stay clear of the inlay: sample the wood just outside the playing field.
	vec2 wood_uv = abs(local_n.x) > abs(local_n.z)
		? vec2(0.02 + fract(local_p.y * 0.35) * 0.03, side_uv.y)
		: vec2(side_uv.x, 0.02 + fract(local_p.y * 0.35) * 0.03);
	vec3 side = texture(albedo_tex, wood_uv).rgb * (abs(local_n.x) > abs(local_n.z) ? 0.86 : 0.95);
	vec3 alb = texture(albedo_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = mix(side, alb, top);
	AO = mix(1.0, orm.r, top);
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = mix(0.55, orm.g, top);
	METALLIC = 0.0;
	SPECULAR = 0.45;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, UV).rgb, top);
	float breathe = 0.82 + 0.18 * sin(TIME * 0.6);
	EMISSION = glow_color * texture(glow_tex, UV).r * top * awaken * glow_energy * breathe;
}
