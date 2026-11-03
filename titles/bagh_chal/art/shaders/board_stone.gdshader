shader_type spatial;
// The cut stone board (historical style). Textures from
// tools/art/make_stone_set.py.
// - The face uses the board textures (grid grooves, chalk, wear) by UV.
// - The chamfer and the split-face sides use a tileable side texture mapped
//   triplanar in the mesh's own space, so they don't smear.
// When the board "awakens" the chalked lines warm very slightly: much quieter
// than the brass board's glow.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D glow_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D side_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D side_orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D side_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float side_span = 1.0;   // units covered by one tile of the side texture
uniform vec3 glow_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float awaken : hint_range(0.0, 1.0) = 0.0;
uniform float glow_energy = 0.45;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

// Triplanar sample of the side texture around the slab (x and z faces; the
// y face only matters on the chamfer).
vec4 tri(sampler2D tex, vec3 p, vec3 w) {
	vec4 a = texture(tex, p.zy / side_span);
	vec4 b = texture(tex, p.xy / side_span + vec2(0.37, 0.0));
	vec4 c = texture(tex, p.xz / side_span + vec2(0.0, 0.61));
	return a * w.x + b * w.z + c * w.y;
}

void fragment() {
	vec3 n_obj = normalize(obj_normal);
	float top = smoothstep(0.75, 0.97, n_obj.y);
	vec3 w = pow(abs(n_obj), vec3(4.0));
	w /= (w.x + w.y + w.z);

	vec3 face_alb = texture(albedo_tex, UV).rgb;
	vec3 face_orm = texture(orm_tex, UV).rgb;
	vec3 face_n = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	vec3 side_alb = tri(side_albedo_tex, obj_pos, w).rgb;
	vec3 side_orm = tri(side_orm_tex, obj_pos, w).rgb;

	// Side normal: the triplanar map's tangent-space normal, turned to the
	// face it was projected on, in the mesh's space, then to view space.
	vec3 nx = texture(side_normal_tex, obj_pos.zy / side_span).rgb * 2.0 - 1.0;
	vec3 nz = texture(side_normal_tex, obj_pos.xy / side_span + vec2(0.37, 0.0)).rgb * 2.0 - 1.0;
	vec3 ny = texture(side_normal_tex, obj_pos.xz / side_span + vec2(0.0, 0.61)).rgb * 2.0 - 1.0;
	vec3 bump = vec3(0.0);
	bump += w.x * vec3(0.0, nx.y, nx.x * sign(n_obj.x));
	bump += w.z * vec3(nz.x * sign(n_obj.z), nz.y, 0.0);
	bump += w.y * vec3(ny.x, 0.0, ny.y);
	vec3 side_n_obj = normalize(n_obj + bump * 1.2);
	vec3 side_n_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(side_n_obj, 0.0)).xyz);
	vec3 face_n_view = normalize(TANGENT * face_n.x + BINORMAL * face_n.y + NORMAL * face_n.z);

	ALBEDO = mix(side_alb, face_alb, top);
	AO = mix(side_orm.r, face_orm.r, top);
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = mix(side_orm.g, face_orm.g, top);
	METALLIC = 0.0;
	SPECULAR = 0.4;
	NORMAL = normalize(mix(side_n_view, face_n_view, top));
	EMISSION = glow_color * texture(glow_tex, UV).r * top * awaken * glow_energy;
}
