shader_type spatial;
// The engraved brass board. Textures from tools/art/make_board.py; the
// playing lines glow faintly when the board "awakens" (art direction A).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D glow_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 side_color : source_color = vec3(0.55, 0.40, 0.19);
uniform vec3 glow_color : source_color = vec3(1.0, 0.52, 0.16);
uniform float awaken : hint_range(0.0, 1.0) = 0.0;
uniform float glow_energy = 1.4;

varying float facing_up;
varying vec2 plane_pos;

void vertex() {
	facing_up = NORMAL.y;
	plane_pos = VERTEX.xz;
}

void fragment() {
	float top = smoothstep(0.55, 0.9, facing_up);
	vec3 alb = texture(albedo_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = mix(side_color, alb, top);
	AO = mix(0.85, orm.r, top);
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = mix(0.45, orm.g, top);
	METALLIC = mix(1.0, orm.b, top);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, UV).rgb, top);
	NORMAL_MAP_DEPTH = 1.0;
	// A slow ripple runs outward from the center while the board is awake.
	float ripple = 0.7 + 0.3 * sin(TIME * 0.7 - length(plane_pos) * 1.6);
	EMISSION = glow_color * texture(glow_tex, UV).r * top * awaken * glow_energy * ripple;
}
