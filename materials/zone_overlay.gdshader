shader_type spatial;
// Zone overlay (checklist step 10): tints each tile by its zone and outlines
// where zones meet. One plane over the whole plot reads a small texture with
// one pixel per tile, so the overlay is a single draw call however much is painted.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// One pixel per tile; red channel = zone index (0 = no zone).
uniform sampler2D zone_map : filter_nearest, repeat_disable;
uniform vec2 plot_min = vec2(-200.0);
uniform float tile_size = 1.0;
uniform vec3 landside_color : source_color = vec3(0.30, 0.62, 0.96);
uniform vec3 security_color : source_color = vec3(0.98, 0.72, 0.20);
uniform vec3 airside_color : source_color = vec3(0.64, 0.42, 0.92);
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.42;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.9;
// Outline width in metres (never thinner than about 1.5 pixels).
uniform float edge_width = 0.07;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

int zone_at(ivec2 tile) {
	ivec2 size = textureSize(zone_map, 0);
	if (tile.x < 0 || tile.y < 0 || tile.x >= size.x || tile.y >= size.y) {
		return 0;
	}
	return int(texelFetch(zone_map, tile, 0).r * 255.0 + 0.5);
}

vec3 zone_color(int zone) {
	if (zone == 1) {
		return landside_color;
	}
	if (zone == 2) {
		return security_color;
	}
	return airside_color;
}

void fragment() {
	vec2 local = (world_pos.xz - plot_min) / tile_size;
	// Derivatives are computed for every pixel, before any discard.
	float pixel = max(fwidth(local.x), fwidth(local.y));

	ivec2 tile = ivec2(floor(local));
	int zone = zone_at(tile);
	if (zone == 0) {
		discard;
	}
	// Distance to the nearest tile side whose neighbour is in another zone.
	vec2 f = fract(local);
	float d = 1.0;
	if (zone_at(tile + ivec2(-1, 0)) != zone) { d = min(d, f.x); }
	if (zone_at(tile + ivec2(1, 0)) != zone) { d = min(d, 1.0 - f.x); }
	if (zone_at(tile + ivec2(0, -1)) != zone) { d = min(d, f.y); }
	if (zone_at(tile + ivec2(0, 1)) != zone) { d = min(d, 1.0 - f.y); }
	float width = max(edge_width / tile_size, pixel * 1.5);
	float edge = 1.0 - smoothstep(width - pixel, width, d);

	ALBEDO = zone_color(zone);
	ALPHA = mix(fill_alpha, edge_alpha, edge);
}
