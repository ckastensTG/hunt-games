shader_type spatial;
// "Modern edition" board: molded plastic, a teal field with raised sunflower
// lines and a coral rim (tools/art/make_modern_set.py). When the board
// awakens, the lines warm from within (art direction A).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D glow_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.72, 0.3);
uniform float awaken : hint_range(0.0, 1.0) = 0.0;
uniform float glow_energy = 0.6;
uniform float half_size = 2.75;

varying vec3 local_n;
varying vec3 local_p;

void vertex() {
	local_n = NORMAL;
	local_p = VERTEX;
}

void fragment() {
	float top = smoothstep(0.55, 0.9, local_n.y);
	// The sides are the rim's plastic: sample the rim colour at the board's edge.
	vec3 side = texture(albedo_tex, vec2(0.012, 0.5)).rgb;
	vec3 alb = texture(albedo_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = mix(side * 0.94, alb, top);
	AO = mix(1.0, orm.r, top);
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = mix(0.32, orm.g, top);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	CLEARCOAT = 0.25;
	CLEARCOAT_ROUGHNESS = 0.2;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, UV).rgb, top);
	float breathe = 0.82 + 0.18 * sin(TIME * 0.6);
	EMISSION = glow_color * texture(glow_tex, UV).r * top * awaken * glow_energy * breathe;
}
