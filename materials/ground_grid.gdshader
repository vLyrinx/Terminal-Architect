shader_type spatial;
// Ground with the build grid drawn on it (checklist step 6).
// Lines are anti-aliased and fade out as the camera zooms away, so the grid
// stays subtle and never shimmers. Costs almost nothing on integrated GPUs.
render_mode specular_disabled;

uniform vec3 grass_color : source_color = vec3(0.56, 0.71, 0.44);
uniform vec3 outside_color : source_color = vec3(0.50, 0.63, 0.41);
uniform vec3 line_color : source_color = vec3(1.0);
uniform float minor_line_alpha : hint_range(0.0, 1.0) = 0.16;
uniform float major_line_alpha : hint_range(0.0, 1.0) = 0.28;
uniform float border_alpha : hint_range(0.0, 1.0) = 0.6;
uniform float tile_size = 1.0;
uniform float major_every = 10.0;
uniform vec2 plot_min = vec2(-200.0);
uniform vec2 plot_max = vec2(200.0);
uniform float show_grid : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 on a grid line, 0 between lines; fades out when a pixel covers too much ground.
float grid_line(vec2 coord) {
	vec2 w = max(fwidth(coord), vec2(1e-4));
	vec2 g = abs(fract(coord - 0.5) - 0.5) / w;
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float fade = 1.0 - smoothstep(0.15, 0.5, max(w.x, w.y));
	return line * fade;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Derivatives are computed for every pixel (outside any branch).
	float minor = grid_line(p / tile_size);
	float major = grid_line(p / (tile_size * major_every));
	vec2 pw = max(fwidth(p), vec2(1e-4));
	vec2 to_edge = min(p - plot_min, plot_max - p) / pw;
	float border = 1.0 - smoothstep(1.0, 2.5, abs(min(to_edge.x, to_edge.y)));

	float inside = step(plot_min.x, p.x) * step(plot_min.y, p.y)
		* step(p.x, plot_max.x) * step(p.y, plot_max.y);
	vec3 col = mix(outside_color, grass_color, inside);
	float grid_amount = inside * show_grid;
	col = mix(col, line_color, minor * minor_line_alpha * grid_amount);
	col = mix(col, line_color, major * major_line_alpha * grid_amount);
	col = mix(col, line_color, border * border_alpha);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
