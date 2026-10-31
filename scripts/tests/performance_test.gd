extends Node3D
## Performance test (checklist step 39).
## Run this scene on its own (F6). It loads the full main scene (all game
## systems, UI, sun with shadows), builds a 120 x 60 m terminal (landside with
## check-in desks, security scanners, airside with seat rows and gate desks)
## and a 2,400 m runway, then measures the frame rate in stages:
##   baseline        terminal and runway, nobody about
##   standing        + 1,500 passengers standing still
##   walking         + all 1,500 walking around on terminal paths (pathfinding)
##   full            + 10 aircraft: 4 parked, 6 landing and taking off
##   full 4x         the same at 4x game speed
##   full no shadows the same at 1x with sun shadows off
##   full default    the same with the project's default (not low-end) settings
## Low-end settings: 1920 x 1080 window, vsync off, no MSAA / FXAA / TAA,
## 2048 directional shadow map with hard shadows.
## Each stage warms up for WARMUP seconds, then samples for SAMPLE seconds.
## Prints a results table (and saves it to user://performance_results.txt),
## then keeps running with an FPS label. Camera as in the game.

const MainScene := preload("res://scenes/main.tscn")
const FlightScript := preload("res://scripts/flights/flight.gd")
const FlightAircraftScript := preload("res://scripts/flights/flight_aircraft.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const GatesScript := preload("res://scripts/passengers/gates.gd")
const Zone := TerminalZonesScript.Zone
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE

const PASSENGERS := 1500
const AIRSIDE_SHARE := 0.6
const PARKED_AIRCRAFT := 4
const FLYING_AIRCRAFT := 6
const WARMUP := 3.0
const SAMPLE := 10.0
const WINDOW := Vector2i(1920, 1080)
const PATH_BENCH := 500

## Terminal corner tile and size; zones run west to east.
const B := Vector2i(2190, 960)
const SIZE := Vector2i(120, 60)
const SECURITY_X := 50
const AIRSIDE_X := 62
const RUNWAY_Y := 1200

var _main: Node3D
var _floor: Node3D
var _walls: Node3D
var _zones: Node3D
var _objects: Node3D
var _paths: TerminalPathsScript
var _crowd: MultiMeshInstance3D
var _spawner: Node
var _camera: Camera3D
var _sun: DirectionalLight3D
var _label: Label
var _passengers: Array[PassengerScript] = []
var _flying: Array[Node3D] = []
var _parked: Array[Node3D] = []
var _runway: RefCounted
var _rng := RandomNumberGenerator.new()
var _wandering := false

# Timings for the current frame and per stage (microseconds).
var _sample := false
var _last_frame_us := 0
var _frame_ms := PackedFloat32Array()
var _sum := {}
var _path_calls := 0
var _results: Array[Dictionary] = []
var _stage := ""


func _ready() -> void:
	print("TEST START | performance")
	_rng.seed = 39
	_apply_low_end()
	# No scheduled flights: the test makes all the passengers and aircraft itself.
	FlightSchedule.clear()
	_main = MainScene.instantiate()
	_main.get_node("Camera3D").start_distance = 190.0
	_main.get_node("Camera3D").start_pitch_deg = 50.0
	add_child(_main)
	_floor = _main.get_node("TerminalFloor")
	_walls = _main.get_node("TerminalWalls")
	_zones = _main.get_node("TerminalZones")
	_objects = _main.get_node("PlacedObjects")
	_paths = _main.get_node("TerminalPaths")
	_crowd = _main.get_node("PassengerCrowd")
	_spawner = _main.get_node("PassengerSpawner")
	_camera = _main.get_node("Camera3D")
	_sun = _main.get_node("Sun")
	# The test calls these itself so it can time them.
	_spawner.set_process(false)
	_crowd.set_process(false)
	GameClock.set_process(false)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_add_label()
	_build_terminal()
	_runway = _main.get_node("Runways").get_runway(
		_main.get_node("Runways").add_runway(&"medium", Vector2i(1050, RUNWAY_Y), Vector2i(3450, RUNWAY_Y)))
	_camera.focus_on(BuildGrid.tile_corner_to_world(B + Vector2i(SIZE.x >> 1, SIZE.y >> 1)) + Vector3(20, 0, 10))
	GameClock.set_speed(1.0)
	GameClock.set_paused(false)
	for i in 5:
		await get_tree().process_frame

	await _measure("baseline")
	_add_passengers()
	await _measure("standing")
	_wandering = true
	for p in _passengers:
		_wander(p)
	await _measure("walking")
	_add_aircraft()
	await _measure("full")
	GameClock.set_speed(4.0)
	await _measure("full 4x")
	GameClock.set_speed(1.0)
	_sun.shadow_enabled = false
	await _measure("full no shadows")
	_sun.shadow_enabled = true
	_apply_default()
	await _measure("full default")
	_apply_low_end()
	_bench_paths()
	_report()
	print("TEST DONE | measured %d stages" % _results.size())


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _sample and _last_frame_us > 0:
		_frame_ms.append((now - _last_frame_us) / 1000.0)
	_last_frame_us = now
	var t := Time.get_ticks_usec()
	GameClock._process(delta)
	_add_time("sim_tick", t)
	t = Time.get_ticks_usec()
	_spawner._process(delta)
	_add_time("walking", t)
	t = Time.get_ticks_usec()
	_crowd._process(delta)
	_add_time("crowd_upload", t)
	if _sample:
		var vp := get_viewport().get_viewport_rid()
		_sum["render_cpu"] = _sum.get("render_cpu", 0.0) + RenderingServer.viewport_get_measured_render_time_cpu(vp)
		_sum["render_gpu"] = _sum.get("render_gpu", 0.0) + RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_sum["draw_calls"] = _sum.get("draw_calls", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_sum["primitives"] = _sum.get("primitives", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_sum["objects"] = _sum.get("objects", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_label.text = "Performance test   %s\nFPS %d   passengers %d   aircraft %d   draw calls %d   %s" % [
		_stage if _stage != "" else "done", Engine.get_frames_per_second(), _crowd.get_count(),
		_flying.size() + _parked.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"%dx" % GameClock.speed]


func _add_time(key: String, since: int) -> void:
	if _sample:
		_sum[key] = _sum.get(key, 0.0) + (Time.get_ticks_usec() - since) / 1000.0


# --- Stages -----------------------------------------------------------------------

func _measure(stage: String) -> void:
	_stage = stage
	print("STAGE | %s" % stage)
	await _wait(WARMUP)
	_frame_ms.clear()
	_sum.clear()
	_path_calls = 0
	_last_frame_us = 0
	_sample = true
	var started := Time.get_ticks_usec()
	await _wait(SAMPLE)
	_sample = false
	var seconds := (Time.get_ticks_usec() - started) / 1000000.0
	var frames := _frame_ms.size()
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	for ms in _frame_ms:
		total += ms
		if ms > 1000.0 / 60.0:
			slow += 1
	var r := {
		"stage": stage,
		"frames": frames,
		"fps": frames / seconds,
		"avg_ms": total / maxi(frames, 1),
		"p99_ms": sorted[int(frames * 0.99)] if frames > 0 else 0.0,
		"max_ms": sorted[frames - 1] if frames > 0 else 0.0,
		"paths_per_s": _path_calls / seconds,
		"slow_frames": slow,
	}
	for key: String in _sum:
		r[key] = _sum[key] / maxi(frames, 1)
	_results.append(r)
	print("RESULT | %s: %.0f fps, %.2f ms avg, %.2f ms 1%% low, %.2f ms worst" % [stage, r.fps, r.avg_ms, r.p99_ms, r.max_ms])


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Times PATH_BENCH long paths straight across each zone (separate from the stages).
func _bench_paths() -> void:
	var land_a := BuildGrid.tile_to_world(B + Vector2i(2, 2))
	var land_b := BuildGrid.tile_to_world(B + Vector2i(SECURITY_X - 3, SIZE.y - 3))
	var air_a := BuildGrid.tile_to_world(B + Vector2i(AIRSIDE_X + 2, 2))
	var air_b := BuildGrid.tile_to_world(B + Vector2i(SIZE.x - 3, SIZE.y - 3))
	var t := Time.get_ticks_usec()
	for i in PATH_BENCH:
		if i % 2 == 0:
			_paths.find_path(land_a, land_b, LANDSIDE, true)
		else:
			_paths.find_path(air_a, air_b, AIRSIDE, true)
	var each := (Time.get_ticks_usec() - t) / 1000.0 / PATH_BENCH
	_results.append({"stage": "path bench", "path_ms": each})
	print("RESULT | one long terminal path takes %.3f ms (%d paths)" % [each, PATH_BENCH])


func _report() -> void:
	var lines: Array[String] = []
	lines.append("Performance test, %s, %s, %d x %d" % [Time.get_datetime_string_from_system(false, true),
		RenderingServer.get_video_adapter_name(), get_window().size.x, get_window().size.y])
	lines.append("%-16s %6s %8s %8s %8s | %7s %7s %7s %7s %7s | %7s %7s %7s | %6s %9s %6s" % ["stage", "fps", "avg ms",
		"1% low", "worst", "sim", "walk", "paths", "crowd", ">16.7ms", "rend cpu", "gpu", "paths/s", "draws", "triangles", "objs"])
	for r in _results:
		if r.stage == "path bench":
			lines.append("one long terminal path (cross-zone): %.3f ms" % r.path_ms)
			continue
		lines.append("%-16s %6.0f %8.2f %8.2f %8.2f | %7.2f %7.2f %7.2f %7.2f %7d | %7.2f %7.2f %7.1f | %6.0f %9.0f %6.0f" % [
			r.stage, r.fps, r.avg_ms, r.p99_ms, r.max_ms, r.get("sim_tick", 0.0), r.get("walking", 0.0), r.get("new_paths", 0.0),
			r.get("crowd_upload", 0.0), r.slow_frames, r.get("render_cpu", 0.0), r.get("render_gpu", 0.0),
			r.paths_per_s, r.get("draw_calls", 0.0), r.get("primitives", 0.0), r.get("objects", 0.0)])
	lines.append("sim = GameClock ticks (all simulation), walk = PassengerSpawner movement (includes paths), paths = finding new paths, crowd = MultiMesh upload (ms per frame), >16.7ms = frames slower than 60 fps")
	var text := "\n".join(lines)
	print("RESULTS\n" + text)
	var file := FileAccess.open("user://performance_results.txt", FileAccess.WRITE)
	if file:
		file.store_string(text + "\n")
		print("RESULTS SAVED | %s" % ProjectSettings.globalize_path("user://performance_results.txt"))


# --- Settings ---------------------------------------------------------------------

func _apply_low_end() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var window := get_window()
	if window.mode == Window.MODE_WINDOWED and window.size != WINDOW:
		window.size = WINDOW
		window.position = Vector2i((DisplayServer.screen_get_size() - WINDOW) * 0.5)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.scaling_3d_scale = 1.0
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)


## The project's own settings (Godot defaults: 4096 shadow map, soft shadows on low).
func _apply_default() -> void:
	RenderingServer.directional_shadow_atlas_set_size(
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits"))
	RenderingServer.directional_soft_shadow_filter_set_quality(
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
	var vp := get_viewport()
	vp.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
	vp.screen_space_aa = ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa")
	vp.use_taa = ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa")


# --- Layout -----------------------------------------------------------------------

func _build_terminal() -> void:
	_floor.set_rect(Rect2i(B, SIZE), true)
	_zones.paint_rect(Rect2i(B, Vector2i(SECURITY_X, SIZE.y)), Zone.LANDSIDE)
	_zones.paint_rect(Rect2i(B + Vector2i(SECURITY_X, 0), Vector2i(AIRSIDE_X - SECURITY_X, SIZE.y)), Zone.SECURITY)
	_zones.paint_rect(Rect2i(B + Vector2i(AIRSIDE_X, 0), Vector2i(SIZE.x - AIRSIDE_X, SIZE.y)), Zone.AIRSIDE)
	var c0 := B
	var c1 := B + SIZE
	_walls.set_run(c0, Vector2i(c1.x, c0.y), true)
	_walls.set_run(Vector2i(c0.x, c1.y), c1, true)
	_walls.set_run(c0, Vector2i(c0.x, c1.y), true)
	_walls.set_run(Vector2i(c1.x, c0.y), c1, true)
	# Wall between security and airside, with a door after each scanner lane.
	_walls.set_run(B + Vector2i(AIRSIDE_X, 0), B + Vector2i(AIRSIDE_X, SIZE.y), true)
	for z in [8, 20, 32, 44, 56]:
		_walls.set_door(B + Vector2i(AIRSIDE_X, z), false, true)
	# Entrances in the south wall, apron doors in the east wall.
	for x in [8, 24, 40]:
		_walls.set_door(B + Vector2i(x, SIZE.y), true, true)
	for z in [10, 30, 50]:
		_walls.set_door(B + Vector2i(SIZE.x, z), false, true)
	# Check-in desks along the north of landside.
	for x in range(6, 46, 4):
		_add(&"checkin_desk", Vector2i(x, 8), Vector2i(2, 2))
	# Scanners in the security strip.
	for z in [4, 16, 28, 40, 52]:
		_add(&"security_scanner", Vector2i(55, z), Vector2i(2, 4))
	# Seat rows and gate desks airside.
	for x in range(70, 110, 6):
		for z in range(6, 56, 4):
			_add(&"seat_row", Vector2i(x, z), Vector2i(4, 1))
	for z in [10, 20, 30, 40, 50]:
		_add(GatesScript.GATE_ID, Vector2i(114, z), Vector2i(2, 1))
	_add(&"toilet_block", Vector2i(2, 40), Vector2i(3, 2))
	_add(&"toilet_block", Vector2i(64, 40), Vector2i(3, 2))


## Places an object with its footprint's corner at a tile offset from B (yaw 0).
func _add(def_id: StringName, offset: Vector2i, footprint: Vector2i) -> void:
	var tile := B + offset
	var pos := BuildGrid.tile_corner_to_world(tile) + Vector3(footprint.x * 0.5, 0.0, footprint.y * 0.5)
	pos.y = _floor.get_surface_height(tile)
	_objects.add_object(def_id, pos, 0.0)


# --- Passengers -------------------------------------------------------------------

func _add_passengers() -> void:
	var land := FlightScript.new()
	land.flight_number = "PERF 1"
	var air := FlightScript.new()
	air.flight_number = "PERF 2"
	for i in PASSENGERS:
		var airside := i < PASSENGERS * AIRSIDE_SHARE
		var access := AIRSIDE if airside else LANDSIDE
		var p: PassengerScript = _spawner.add_arriving(air if airside else land, _random_point(access), _rng.randf() * TAU)
		p.access = access
		p.state = PassengerScript.State.AIRSIDE if airside else PassengerScript.State.AT_ENTRANCE
		_crowd.set_walking(p.crowd_id, false)
		_passengers.append(p)


## Sends a passenger to a random walkable spot in their zone, and again when they get there.
func _wander(p: PassengerScript) -> void:
	if not _wandering or p.crowd_id < 0:
		return
	var t := Time.get_ticks_usec()
	_spawner.walk(p, _random_point(p.access), _wander)
	_path_calls += 1
	_add_time("new_paths", t)


func _random_point(access: int) -> Vector3:
	var x0 := AIRSIDE_X if access == AIRSIDE else 0
	var x1 := SIZE.x if access == AIRSIDE else SECURITY_X
	for attempt in 20:
		var tile := B + Vector2i(_rng.randi_range(x0 + 1, x1 - 2), _rng.randi_range(1, SIZE.y - 2))
		if _paths.is_walkable(tile, access):
			var pos := BuildGrid.tile_to_world(tile) + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
			pos.y = _floor.get_surface_height(tile)
			return pos
	return BuildGrid.tile_to_world(B + Vector2i((x0 + x1) >> 1, SIZE.y >> 1))


# --- Aircraft ---------------------------------------------------------------------

func _add_aircraft() -> void:
	# Parked east of the terminal, nose to the building.
	for i in PARKED_AIRCRAFT:
		var a := _new_aircraft(i)
		var pos := BuildGrid.tile_corner_to_world(B + Vector2i(SIZE.x + 30, -20 + i * 40))
		pos.y = FlightPath.GROUND_Y
		a.setup(a.flight, FlightPath.approach(_runway.ends[0], _runway.length, true), null)
		a.park()
		a.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), pos)
		_parked.append(a)
	# Landing and taking off, spread along their paths.
	for i in FLYING_AIRCRAFT:
		var a := _new_aircraft(PARKED_AIRCRAFT + i)
		var landing := i % 2 == 0
		var path := _path_for(landing, i)
		a.setup(a.flight, path, null, path.duration * (i >> 1) / (FLYING_AIRCRAFT / 2.0))
		a.set_meta(&"landing", landing)
		a.path_finished.connect(_next_path.bind(i), CONNECT_DEFERRED)
		_flying.append(a)
	GameClock.ticked.connect(func(s: float) -> void:
		for a in _flying:
			a.advance(s))


func _new_aircraft(i: int) -> Node3D:
	var f := FlightScript.new()
	f.airline_id = &"brightwater"
	f.aircraft_type = &"a320" if i % 2 == 0 else &"b738"
	f.flight_number = "PERF %d" % (100 + i)
	var a := FlightAircraftScript.new()
	a.flight = f
	a.model = AirlineCatalog.make_aircraft_model(f.airline_id, f.aircraft_type)
	a.add_child(a.model)
	add_child(a)
	return a


func _path_for(landing: bool, i: int) -> FlightPath:
	var end: Dictionary = _runway.ends[0]
	return FlightPath.approach(end, _runway.length, i % 4 < 2, 30.0) if landing \
		else FlightPath.takeoff(end, _runway.length, i % 4 < 2)


## Arrivals turn into departures and back, so there are always six moving.
func _next_path(a: Node3D, i: int) -> void:
	var landing: bool = not a.get_meta(&"landing")
	a.set_meta(&"landing", landing)
	a.start_path(_path_for(landing, i))


func _add_label() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(16, 60)
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_color", Color(0.1, 0.12, 0.15))
	ui.add_child(_label)
