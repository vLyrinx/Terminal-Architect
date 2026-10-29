shader_type spatial;
// Terminal walls (checklist steps 9 and 13). Colours come from vertex colours.
// With the cutaway on, walls standing between the camera and the inside of the
// terminal are lowered to cut_height right here in the vertex shader, so
// turning the camera never rebuilds a mesh.
//
// CUSTOM0 per vertex (set by terminal_walls.gd):
//   x: 0 = wall runs along X (horizontal edge), 1 = wall runs along Z
//   y: 1 if the tile on the wall's +Z (or +X) side has terminal floor
//   z: 1 if the tile on its -Z (or -X) side has terminal floor
//   w: 1 for door lintels (dropped out of sight instead of lowered)
render_mode specular_disabled;

uniform float cutaway = 0.0;
// Camera look direction on the ground: -1, 0 or 1 for world X and world Z.
uniform vec2 view_dir = vec2(0.0);
uniform float cut_height = 1.0;
uniform float floor_height = 4.0;

void vertex() {
	if (cutaway > 0.5) {
		float looking = CUSTOM0.x < 0.5 ? view_dir.y : view_dir.x;
		// The wall hides the inside when the tile beyond it, away from the camera, has floor.
		float lower = looking > 0.5 ? CUSTOM0.y : (looking < -0.5 ? CUSTOM0.z : 0.0);
		if (lower > 0.5) {
			float base = floor(VERTEX.y / floor_height + 0.001) * floor_height;
			if (CUSTOM0.w > 0.5) {
				VERTEX.y = base - 0.05;
			} else {
				VERTEX.y = min(VERTEX.y, base + cut_height);
			}
		}
	}
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.9;
}
