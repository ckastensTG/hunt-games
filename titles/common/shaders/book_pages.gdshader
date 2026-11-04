shader_type spatial;
// The edges of a book's page block (HuntArtStyle.book): fine page lines
// stacked along the block's thickness (object y), slightly uneven, paler at
// the middle and greyer toward the covers.

uniform vec3 paper : source_color = vec3(0.92, 0.89, 0.8);
uniform float thickness = 0.2;

varying vec3 op;

void vertex() {
	op = VERTEX;
}

float hash1(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void fragment() {
	float t = op.y / thickness + 0.5;                  // 0..1 across the block
	float pages = op.y * 1400.0;
	// Fade the single leaves out where they get smaller than a pixel.
	float k = 1.0 - smoothstep(0.25, 0.8, fwidth(pages));
	float line = mix(0.5, 0.5 + 0.5 * sin(pages * 6.2832), k);
	float leaf = mix(0.5, hash1(floor(pages)), k);
	float bands = fract(sin(floor(op.y * 160.0) * 12.9898) * 43758.5453);   // signatures
	vec3 c = paper * (0.9 + 0.08 * leaf) * (0.94 + 0.06 * line) * (0.96 + 0.04 * bands);
	c *= mix(0.86, 1.0, smoothstep(0.0, 0.2, t) * smoothstep(1.0, 0.8, t));
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
}
