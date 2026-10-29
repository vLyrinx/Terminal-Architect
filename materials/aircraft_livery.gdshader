shader_type spatial;
// Aircraft livery (checklist step 19). One material is shared by every aircraft;
// each aircraft sets its airline's colours as per-instance parameters
// (GeometryInstance3D.set_instance_shader_parameter), so liveries never need
// extra materials and aircraft still batch.
// UV.x holds the livery slot of each vertex:
//   0 = fixed colour (vertex colour: wings, windows, gear, tyres)
//   1 = body, 2 = belly, 3 = tail, 4 = engines, 5 = accent (cheatline, winglets)
render_mode specular_schlick_ggx;

instance uniform vec4 body_colour : source_color = vec4(0.96, 0.96, 0.95, 1.0);
instance uniform vec4 belly_colour : source_color = vec4(0.80, 0.82, 0.85, 1.0);
instance uniform vec4 tail_colour : source_color = vec4(0.15, 0.62, 0.60, 1.0);
instance uniform vec4 engine_colour : source_color = vec4(0.90, 0.91, 0.92, 1.0);
instance uniform vec4 accent_colour : source_color = vec4(0.15, 0.62, 0.60, 1.0);

varying vec3 livery_albedo;

void vertex() {
	int slot = int(UV.x + 0.5);
	vec3 c = COLOR.rgb;
	if (slot == 1) {
		c = body_colour.rgb;
	} else if (slot == 2) {
		c = belly_colour.rgb;
	} else if (slot == 3) {
		c = tail_colour.rgb;
	} else if (slot == 4) {
		c = engine_colour.rgb;
	} else if (slot == 5) {
		c = accent_colour.rgb;
	}
	livery_albedo = c;
}

void fragment() {
	ALBEDO = livery_albedo;
	ROUGHNESS = 0.55;
}
