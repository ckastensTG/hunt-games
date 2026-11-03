shader_type spatial;
// The straw sitting mat (sukul) under the stone board. The weave is a baked,
// tileable texture (tools/art/make_stone_set.py) so it filters cleanly at a
// distance; this shader only tiles it over the mat's top and darkens the
// thin sides. The rope round the edge is its own mesh (stone_style.gd).
// For a BoxMesh: coordinates are the mesh's own, in units.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_span = 1.0;   // units covered by one tile of the weave
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec2 uv = obj_pos.xz / tile_span;
	float side = 1.0 - smoothstep(0.3, 0.6, obj_normal.y);
	if (side > 0.5) {
		// The cut ends of the straws.
		uv = vec2(obj_pos.x + obj_pos.z, obj_pos.y * 4.0) / tile_span;
	}
	vec3 orm = texture(orm_tex, uv).rgb;
	ALBEDO = texture(albedo_tex, uv).rgb * tint * mix(1.0, 0.6, side);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = orm.g;
	SPECULAR = 0.35;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
}
