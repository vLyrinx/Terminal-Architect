extends Node3D
## Temporary renderer benchmark (checklist step 2).
## Builds its own test scene in code, runs a set of timed stages, prints the
## results to the output log and shows live stats on screen.
## Safe to delete once the renderer decision is made.

const STAGES := [
	{"name": "200 boxes, shadows on", "boxes": 200, "shadows": true, "scale": 1.0},
	{"name": "2000 boxes, shadows on", "boxes": 2000, "shadows": true, "scale": 1.0},
	{"name": "2000 boxes, shadows off", "boxes": 2000, "shadows": false, "scale": 1.0},
	{"name": "2000 boxes, shadows on, 50% resolution", "boxes": 2000, "shadows": true, "scale": 0.5},
]
const WARMUP_SECONDS := 2.0
const MEASURE_SECONDS := 5.0
## Very rough: assumes a typical laptop integrated GPU (Radeon 780M to Intel Iris Xe)
## is about 15 times slower than a desktop RX 7900 XTX.
const LAPTOP_GPU_FACTOR := 15.0
const FRAME_CAPS := [0, 60, 30]
const BOX_COLOURS := [
	Color("#e8eef2"), Color("#4f86c6"), Color("#f2b134"), Color("#ed553b"), Color("#47ab6c"),
]

var _camera: Camera3D
var _sun: DirectionalLight3D
var _boxes_root: Node3D
var _label: Label
var _box_mesh := BoxMesh.new()
var _materials: Array[StandardMaterial3D] = []

var _orbit_angle := 0.0
var _stage_index := -1          # -1 = manual mode
var _stage_time := 0.0
var _sample_frames := 0
var _sample_time := 0.0
var _sample_cpu_ms := 0.0
var _sample_gpu_ms := 0.0
var _results: Array[String] = []
var _cap_index := 0
var _box_count := 0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	_build_environment()
	_build_ground()
	_build_sun()
	_build_camera()
	_build_ui()
	for c in BOX_COLOURS:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		_materials.append(m)
	_boxes_root = Node3D.new()
	add_child(_boxes_root)

	print("BENCHMARK START | renderer=%s | gpu=%s" % [_renderer_name(), RenderingServer.get_video_adapter_name()])
	_start_stage(0)


func _process(delta: float) -> void:
	_orbit_camera(delta)
	_update_measurements(delta)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1: _set_manual(); _set_box_count(200)
		KEY_2: _set_manual(); _set_box_count(2000)
		KEY_3: _set_manual(); _set_box_count(5000)
		KEY_S: _set_manual(); _sun.shadow_enabled = not _sun.shadow_enabled
		KEY_R:
			_set_manual()
			var vp := get_viewport()
			vp.scaling_3d_scale = 0.5 if vp.scaling_3d_scale > 0.75 else 1.0
		KEY_C:
			_cap_index = (_cap_index + 1) % FRAME_CAPS.size()
			Engine.max_fps = FRAME_CAPS[_cap_index]
		KEY_B:
			_results.clear()
			_start_stage(0)


# --- Benchmark stages -------------------------------------------------------

func _start_stage(index: int) -> void:
	_stage_index = index
	var stage: Dictionary = STAGES[index]
	_set_box_count(stage.boxes)
	_sun.shadow_enabled = stage.shadows
	get_viewport().scaling_3d_scale = stage.scale
	Engine.max_fps = 0
	_cap_index = 0
	_stage_time = 0.0
	_reset_samples()


func _update_measurements(delta: float) -> void:
	_stage_time += delta
	if _stage_index < 0:
		# Manual mode: rolling one-second average.
		_add_sample(delta)
		if _sample_time >= 1.0:
			_reset_samples()
		return
	if _stage_time < WARMUP_SECONDS:
		return
	_add_sample(delta)
	if _stage_time >= WARMUP_SECONDS + MEASURE_SECONDS:
		_finish_stage()


func _add_sample(delta: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	_sample_frames += 1
	_sample_time += delta
	_sample_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	_sample_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)


func _reset_samples() -> void:
	_sample_frames = 0
	_sample_time = 0.0
	_sample_cpu_ms = 0.0
	_sample_gpu_ms = 0.0


func _finish_stage() -> void:
	var stage: Dictionary = STAGES[_stage_index]
	var fps := _sample_frames / maxf(_sample_time, 0.001)
	var cpu := _sample_cpu_ms / maxi(_sample_frames, 1)
	var gpu := _sample_gpu_ms / maxi(_sample_frames, 1)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var line := "RESULT | %s | %s | fps=%.0f | frame=%.2fms | cpu=%.2fms | gpu=%.2fms | draw_calls=%d | laptop_est_fps=%.0f" % [
		_renderer_name(), stage.name, fps, 1000.0 / maxf(fps, 0.001), cpu, gpu, draws, _laptop_fps(gpu)]
	print(line)
	_results.append("%s: %.0f fps (GPU %.2f ms, laptop est. %.0f fps)" % [stage.name, fps, gpu, _laptop_fps(gpu)])
	if _stage_index + 1 < STAGES.size():
		_start_stage(_stage_index + 1)
	else:
		print("BENCHMARK DONE | renderer=%s" % _renderer_name())
		_set_manual()
		_set_box_count(2000)
		_sun.shadow_enabled = true
		get_viewport().scaling_3d_scale = 1.0


func _set_manual() -> void:
	if _stage_index >= 0:
		_stage_index = -1
		_reset_samples()


# --- Scene building ---------------------------------------------------------

func _set_box_count(count: int) -> void:
	for child in _boxes_root.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in count:
		var box := MeshInstance3D.new()
		box.mesh = _box_mesh
		box.material_override = _materials[i % _materials.size()]
		var size := Vector3(rng.randf_range(2.0, 8.0), rng.randf_range(1.0, 10.0), rng.randf_range(2.0, 8.0))
		box.scale = size
		box.position = Vector3(rng.randf_range(-150.0, 150.0), size.y * 0.5, rng.randf_range(-150.0, 150.0))
		box.rotation.y = rng.randf_range(0.0, TAU)
		_boxes_root.add_child(box)
	_box_count = count


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#6fa8dc")
	sky_mat.sky_horizon_color = Color("#d9e8f5")
	sky_mat.ground_horizon_color = Color("#d9e8f5")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#9cc58a")
	mat.roughness = 1.0
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	add_child(ground)


func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_sun.light_energy = 1.2
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 250.0
	add_child(_sun)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.far = 1000.0
	add_child(_camera)
	_camera.make_current()


func _orbit_camera(delta: float) -> void:
	_orbit_angle += delta * 0.25
	_camera.position = Vector3(cos(_orbit_angle) * 140.0, 70.0, sin(_orbit_angle) * 140.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(_label)


func _update_label() -> void:
	var frames := maxi(_sample_frames, 1)
	var gpu := _sample_gpu_ms / frames
	var lines := PackedStringArray()
	lines.append("RENDERER BENCHMARK")
	lines.append("Renderer: %s" % _renderer_name())
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("FPS: %d   CPU: %.2f ms   GPU: %.2f ms" % [Engine.get_frames_per_second(), _sample_cpu_ms / frames, gpu])
	lines.append("Draw calls: %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	lines.append("Rough laptop estimate: %.0f fps" % _laptop_fps(gpu))
	lines.append("Boxes: %d   Shadows: %s   Resolution: %d%%   FPS cap: %s" % [
		_box_count, "on" if _sun.shadow_enabled else "off",
		int(get_viewport().scaling_3d_scale * 100), "none" if Engine.max_fps == 0 else str(Engine.max_fps)])
	lines.append("")
	if _stage_index >= 0:
		var phase := "warming up" if _stage_time < WARMUP_SECONDS else "measuring"
		lines.append("Auto test %d/%d: %s (%s)" % [_stage_index + 1, STAGES.size(), STAGES[_stage_index].name, phase])
	else:
		lines.append("Manual mode. 1/2/3: 200/2000/5000 boxes   S: shadows   R: 50% resolution")
		lines.append("C: FPS cap (none/60/30)   B: run the auto test again")
	for r in _results:
		lines.append(r)
	_label.text = "\n".join(lines)


func _renderer_name() -> String:
	return RenderingServer.get_current_rendering_method()


func _laptop_fps(gpu_ms: float) -> float:
	return 1000.0 / maxf(gpu_ms * LAPTOP_GPU_FACTOR, 0.001)
