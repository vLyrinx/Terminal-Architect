shader_type spatial;
// Highlight for the tile under the mouse (checklist step 6): a soft fill with a bright edge.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.95, 0.6);
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.25;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.9;
uniform float edge_width : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float on_edge = 1.0 - smoothstep(edge_width - fwidth(edge), edge_width, edge);
	ALBEDO = color;
	ALPHA = mix(fill_alpha, edge_alpha, on_edge);
}
