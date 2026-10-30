extends Node3D
## Test for the passenger figure and instancing (checklist step 27).
## Run this scene on its own (F6). It checks the figure mesh (low triangle
## count, about 1.77 m tall, standing on the ground), that a PassengerCrowd
## draws everyone from one MultiMesh, that passengers get a mix of looks, and
## that adding, moving and removing passengers keeps the right data per id.
## Prints PASS or FAIL for each check, then 1,000 passengers wander around a
## 160 x 160 m area with the FPS on screen:
##   ]      add 500 passengers
##   [      remove 500 passengers
##   P      stop / start walking
##   Camera as in the game (right drag rotate, WASD pan, wheel zoom)

const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const PassengerMeshScript := preload("res://scripts/passengers/passenger_mesh.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")

const START_COUNT := 1000
const STEP_COUNT := 500
const AREA := 80.0
const MAX_TRIANGLES := 300

var _failures := 0
var _crowd: PassengerCrowdScript
var _ids := PackedInt32Array()
var _targets: Array[Vector3] = []
var _speeds := PackedFloat32Array()
var _walking := true
var _rng := RandomNumberGenerator.new()
var _label: Label
var _fps_samples: Array[float] = []


func _ready() -> void:
	print("TEST START | passenger figure and instancing")
	# Uncapped, so the FPS shows what the crowd costs rather than the monitor's refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_rng.randomize()
	_add_view()
	_check_mesh()
	_crowd = PassengerCrowdScript.new()
	add_child(_crowd)
	_check_ids()
	_add_passengers(START_COUNT)
	# process_frame fires before nodes process, so wait two frames for the crowd to send its data.
	await get_tree().process_frame
	await get_tree().process_frame
	_check_crowd()
	var start := _crowd.get_passenger_position(_ids[0])
	for i in 10:
		await get_tree().process_frame
	_expect("passengers move between frames", _crowd.get_passenger_position(_ids[0]).distance_to(start) > 0.001)
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_report_fps_later()


func _process(delta: float) -> void:
	if _crowd == null:
		return
	if _walking:
		for i in _ids.size():
			var id := _ids[i]
			var pos := _crowd.get_passenger_position(id)
			var to := _targets[i] - pos
			var step := _speeds[i] * delta
			if to.length() <= step:
				pos = _targets[i]
				_targets[i] = _random_point()
			else:
				pos += to.normalized() * step
			_crowd.set_pose(id, pos, PassengerCrowdScript.yaw_towards(_targets[i] - pos))
	_label.text = "FPS %d    passengers %d    draw calls %d    triangles %d\n] add %d   [ remove %d   P %s" % [
		Engine.get_frames_per_second(), _crowd.get_count(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		STEP_COUNT, STEP_COUNT, "stop walking" if _walking else "start walking"]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_BRACKETRIGHT:
		_add_passengers(STEP_COUNT)
	elif key.keycode == KEY_BRACKETLEFT:
		for n in mini(STEP_COUNT, _ids.size()):
			_crowd.remove(_ids[_ids.size() - 1])
			_ids.resize(_ids.size() - 1)
			_targets.pop_back()
			_speeds.resize(_speeds.size() - 1)
	elif key.keycode == KEY_P:
		_walking = not _walking
		for id in _ids:
			_crowd.set_walking(id, _walking)


func _add_passengers(count: int) -> void:
	for n in count:
		var pos := _random_point()
		var target := _random_point()
		_ids.append(_crowd.add(pos, PassengerCrowdScript.yaw_towards(target - pos), _walking))
		_targets.append(target)
		_speeds.append(_rng.randf_range(1.1, 1.5))


func _random_point() -> Vector3:
	return Vector3(_rng.randf_range(-AREA, AREA), 0.0, _rng.randf_range(-AREA, AREA))


func _check_mesh() -> void:
	var mesh := PassengerMeshScript.build()
	var tris := floori(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3.0)
	var box := mesh.get_aabb()
	print("INFO | figure has %d triangles, %.2f m tall, %.2f m wide" % [tris, box.end.y, box.size.x])
	_expect("figure stays under %d triangles" % MAX_TRIANGLES, tris > 0 and tris < MAX_TRIANGLES)
	_expect("figure is about 1.7-1.85 m tall", box.end.y > 1.7 and box.end.y < 1.85)
	_expect("figure stands on the ground", absf(box.position.y) < 0.01)
	_expect("figure is centred", absf(box.position.x + box.end.x) < 0.01)


## Adds, moves and removes a few passengers and checks each id keeps its own data.
func _check_ids() -> void:
	var a := _crowd.add(Vector3(1, 0, 0), 0.0)
	var b := _crowd.add(Vector3(2, 0, 0), 0.0)
	var c := _crowd.add(Vector3(3, 0, 0), 0.0)
	var look_c := _crowd.get_look(c)
	_crowd.set_pose(c, Vector3(5, 0, 7), PI * 0.5)
	_crowd.remove(a)
	_expect("removed passenger is gone", not _crowd.has_passenger(a) and _crowd.get_count() == 2)
	_expect("other passengers keep their position", _crowd.get_passenger_position(b) == Vector3(2, 0, 0)
		and _crowd.get_passenger_position(c) == Vector3(5, 0, 7))
	_expect("moved passenger keeps its look", _crowd.get_look(c) == look_c)
	_crowd.set_walking(c, false)
	_expect("walking flag can be cleared without changing the look",
		int(_crowd.get_look(c).a) == int(look_c.a) & ~PassengerCrowdScript.WALKING_BIT)
	_expect("yaw_towards faces -Z at 0", is_zero_approx(PassengerCrowdScript.yaw_towards(Vector3.FORWARD)))
	_crowd.clear()
	_expect("clear removes everyone", _crowd.get_count() == 0)


func _check_crowd() -> void:
	_expect("%d passengers in the crowd" % START_COUNT, _crowd.get_count() == START_COUNT)
	_expect("MultiMesh draws all of them", _crowd.multimesh.visible_instance_count == START_COUNT
		and _crowd.multimesh.instance_count >= START_COUNT)
	_expect("whole crowd is one mesh node", _count_mesh_nodes(self) == 1)
	var shirts := {}
	var looks := {}
	for id in _ids:
		var look := _crowd.get_look(id)
		shirts[Color(look.r, look.g, look.b)] = true
		looks[look] = true
	print("INFO | %d shirt colours, %d different looks" % [shirts.size(), looks.size()])
	_expect("at least 6 shirt colours", shirts.size() >= 6)
	_expect("at least 50 different looks", looks.size() >= 50)


## Counts the visible geometry nodes under node, apart from the ground.
func _count_mesh_nodes(node: Node) -> int:
	var count := 1 if node is GeometryInstance3D and node.name != &"Ground" else 0
	for child in node.get_children():
		count += _count_mesh_nodes(child)
	return count


## Prints the average FPS over a few seconds of wandering (not a pass/fail check).
func _report_fps_later() -> void:
	await get_tree().create_timer(1.0).timeout
	for n in 30:
		await get_tree().create_timer(0.1).timeout
		_fps_samples.append(Engine.get_frames_per_second())
	var total := 0.0
	for f in _fps_samples:
		total += f
	print("INFO | %d passengers walking: about %d FPS, %d draw calls" % [_crowd.get_count(),
		roundi(total / _fps_samples.size()),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _add_view() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.78, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.80, 0.88)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	ground.name = &"Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(AREA * 2.5, AREA * 2.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.78, 0.76)
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	var camera := OrbitCameraScript.new()
	camera.start_distance = 60.0
	camera.start_pitch_deg = 35.0
	add_child(camera)
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_color", Color(0.1, 0.12, 0.15))
	ui.add_child(_label)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
