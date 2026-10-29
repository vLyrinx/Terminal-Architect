shader_type spatial;
// Terminal floor tiles (checklist step 8): flat colour with thin grout lines.
// Lines are drawn from world position, so merged tile rectangles still look
// like 1 m tiles. They fade out as the camera zooms away, so the floor never
// shimmers. Vertex colour red = 1 marks top faces; slab sides use side_color.
render_mode specular_disabled;

uniform vec3 floor_color : source_color = vec3(0.89, 0.90, 0.91);
uniform vec3 grout_color : source_color = vec3(0.74, 0.76, 0.79);
uniform vec3 side_color : source_color = vec3(0.70, 0.72, 0.75);
uniform float grout_alpha : hint_range(0.0, 1.0) = 0.7;
uniform float tile_size = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 on a tile edge, 0 between edges; fades out when a pixel covers too much floor.
float grout_line(vec2 coord) {
	vec2 w = max(fwidth(coord), vec2(1e-4));
	vec2 g = abs(fract(coord - 0.5) - 0.5) / w;
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float fade = 1.0 - smoothstep(0.1, 0.35, max(w.x, w.y));
	return line * fade;
}

void fragment() {
	// Derivatives are computed for every pixel (outside any branch).
	float grout = grout_line(world_pos.xz / tile_size);
	vec3 top = mix(floor_color, grout_color, grout * grout_alpha);
	ALBEDO = mix(side_color, top, COLOR.r);
	ROUGHNESS = 0.9;
}
