extends Node3D
## Test for security queues (checklist step 31).
## Run this scene on its own (F6). It builds a 40 x 24 m terminal: landside
## in the west (entrance in the south wall, four check-in desks along the
## west wall), a security strip with two scanners facing landside, and
## airside in the east. A wall behind the scanners has a doorway only where
## each scanner's arch comes out, so the only way airside is through a
## scanner. A third scanner stands in airside facing airside (must not be
## used). It checks that the two scanners get queues, fast-forwards to 07:10
## and checks that checked-in passengers queue on their spots, are screened
## one at a time and in order, walk through the arch and come out airside;
## removes one scanner and checks its queue moves to the other; runs on to
## 07:40 and checks both scanners screened people for the processing time.
## Prints PASS or FAIL for each check, then keeps running so you can watch:
##   F      fast-forward (20x) / back to 4x
##   X      remove / put back the north scanner
##   Z      zone overlay
##   Space, 1, 2, 3   pause and game speed as in the game
##   Camera as in the game (right drag rotate, WASD pan, wheel zoom)

const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const CheckInScript := preload("res://scripts/passengers/check_in.gd")
const SecurityScript := preload("res://scripts/passengers/security.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE

const B := Vector2i(2240, 990)
const SIZE := Vector2i(40, 24)
const SECURITY_X := 20
const AIRSIDE_X := 28
## The wall behind the scanners.
const BACK_WALL_X := 26
const ENTRANCE := Vector2i(10, 24)
## Check-in desk centres (tile corners), facing east.
const DESKS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(3, 6), Vector2i(3, 18), Vector2i(3, 21)]
## Scanner centres (tile corners), facing west (front towards landside).
const SCANNERS: Array[Vector2i] = [Vector2i(24, 8), Vector2i(24, 14)]
const AIRSIDE_SCANNER := Vector2i(34, 20)
const FAST_SPEED := 20.0

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _zones: TerminalZonesScript
var _objects: PlacedObjectsScript
var _paths: TerminalPathsScript
var _crowd: PassengerCrowdScript
var _spawner: PassengerSpawnerScript
var _check_in: CheckInScript
var _security: SecurityScript
var _label: Label
var _scanner_ids: Array[int] = []
## Passenger id -> scanner id they were cleared through.
var _cleared_at := {}
## Passenger ids seen walking inside a scanner's footprint.
var _seen_in_arch := {}
## Tiles every scanner in use has covered.
var _scanner_tiles := {}
var _out_of_order := 0
var _two_at_once := 0
var _landside_on_airside := 0


func _ready() -> void:
	print("TEST START | security queues")
	_build_terminal()
	_add_view()
	_paths = TerminalPathsScript.new()
	_paths.terminal_floor = _floor
	_paths.terminal_walls = _walls
	_paths.terminal_zones = _zones
	_paths.placed_objects = _objects
	add_child(_paths)
	_crowd = PassengerCrowdScript.new()
	add_child(_crowd)
	_spawner = PassengerSpawnerScript.new()
	_spawner.terminal_floor = _floor
	_spawner.terminal_walls = _walls
	_spawner.terminal_zones = _zones
	_spawner.terminal_paths = _paths
	_spawner.crowd = _crowd
	add_child(_spawner)
	_check_in = CheckInScript.new()
	_check_in.placed_objects = _objects
	_check_in.terminal_floor = _floor
	_check_in.terminal_walls = _walls
	_check_in.terminal_zones = _zones
	_check_in.terminal_paths = _paths
	_check_in.spawner = _spawner
	add_child(_check_in)
	_security = SecurityScript.new()
	_security.placed_objects = _objects
	_security.terminal_floor = _floor
	_security.terminal_walls = _walls
	_security.terminal_zones = _zones
	_security.terminal_paths = _paths
	_security.spawner = _spawner
	_security.check_in = _check_in
	add_child(_security)
	_security.passenger_cleared.connect(func(p: PassengerScript) -> void: _cleared_at[p.id] = p.scanner_id)

	_check_scanners()
	await _run_until("07:10")
	_check_queues()
	_check_cleared()
	await _check_scanner_removed()
	await _run_until("07:40")
	_check_both_served()
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	GameClock.set_speed(4.0)


# --- Layout -----------------------------------------------------------------------

func _build_terminal() -> void:
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_walls = TerminalWallsScript.new()
	_walls.terminal_floor = _floor
	add_child(_walls)
	_zones = TerminalZonesScript.new()
	_zones.terminal_floor = _floor
	add_child(_zones)
	_objects = PlacedObjectsScript.new()
	_objects.terminal_floor = _floor
	_objects.terminal_walls = _walls
	add_child(_objects)
	_floor.placed_objects = _objects
	_walls.placed_objects = _objects
	_floor.set_roof_visible(false)

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
	_walls.set_run(B + Vector2i(BACK_WALL_X, 0), B + Vector2i(BACK_WALL_X, SIZE.y), true)
	_walls.set_door(B + ENTRANCE, true, true)
	for corner in DESKS:
		_add_object(CheckInScript.DESK_ID, corner, PI / 2.0)
	for corner in SCANNERS:
		_scanner_ids.append(_add_scanner(corner))
	_add_object(SecurityScript.SCANNER_ID, AIRSIDE_SCANNER, -PI / 2.0)


## A scanner facing west, with a doorway in the back wall where its arch comes out.
func _add_scanner(corner: Vector2i) -> int:
	_walls.set_door(B + Vector2i(BACK_WALL_X, corner.y), false, true)
	return _add_object(SecurityScript.SCANNER_ID, corner, -PI / 2.0)


func _add_object(def_id: StringName, corner: Vector2i, yaw: float) -> int:
	var pos := BuildGrid.tile_corner_to_world(B + corner)
	pos.y = _floor.get_surface_height(B + corner)
	return _objects.add_object(def_id, pos, yaw)


# --- Checks -----------------------------------------------------------------------

func _check_scanners() -> void:
	var scanners := _security.get_scanners()
	_expect("two scanners in use (the one facing airside isn't)", scanners.size() == 2)
	var spots_ok := true
	var front_ok := true
	for s: SecurityScript.Scanner in scanners:
		var obj = _objects.get_object(s.id)
		if s.spots[0].x >= obj.position.x - 2.0 or _objects.get_object_at(BuildGrid.world_to_tile(s.spots[0])) != 0:
			front_ok = false
		for spot in s.spots:
			var zone := _zones.get_zone(BuildGrid.world_to_tile(spot))
			if zone != Zone.LANDSIDE and zone != Zone.SECURITY:
				spots_ok = false
		var exit_zone := _zones.get_zone(BuildGrid.world_to_tile(s.exit))
		if s.exit.x <= obj.position.x + 2.0 or exit_zone != Zone.SECURITY:
			front_ok = false
		print("INFO | scanner %d: queue of %d spots" % [s.id, s.spots.size()])
	_expect("queues start at the scanner fronts and exits are behind them", front_ok)
	_expect("queue spots are on landside or security floor", spots_ok)
	_expect("landside people can't get behind the scanners except through them",
		_paths.find_path(BuildGrid.tile_to_world(B + Vector2i(10, 12)), BuildGrid.tile_to_world(B + Vector2i(27, 12)),
			LANDSIDE).is_empty())


func _check_queues() -> void:
	var sizes: Array[int] = []
	var on_spots := true
	for s: SecurityScript.Scanner in _security.get_scanners():
		sizes.append(s.queue.size())
		for i in s.queue.size():
			var p := s.queue[i]
			if p.state == State.QUEUING_SECURITY and not p.is_walking \
					and _crowd.get_passenger_position(p.crowd_id).distance_to(s.spots[i]) > 0.05:
				on_spots = false
	print("INFO | 07:10 security queues: %s" % [sizes])
	_expect("both scanners have a queue at 07:10", sizes.min() > 0)
	_expect("people queuing stand on their queue spots", on_spots)
	_expect("each scanner screens one passenger at a time", _two_at_once == 0)
	_expect("each scanner screens its queue in order", _out_of_order == 0)


func _check_cleared() -> void:
	var cleared := 0
	var through := true
	var in_airside := true
	var times_ok := true
	for p: PassengerScript in _spawner.get_all_passengers():
		if p.state != State.AIRSIDE:
			continue
		cleared += 1
		if not _seen_in_arch.has(p.id):
			through = false
		if p.access != AIRSIDE or p.cleared_time - p.checked_in_time < SecurityScript.PROCESS_MIN:
			times_ok = false
		if not p.is_walking:
			var tile := BuildGrid.world_to_tile(_crowd.get_passenger_position(p.crowd_id))
			if _zones.get_zone(tile) != Zone.AIRSIDE:
				in_airside = false
	_expect("%d passengers through security by 07:10" % cleared, cleared >= 20)
	_expect("each walked through a scanner's arch", through)
	_expect("each took at least the screening time and now walks airside", times_ok)
	_expect("they wait in the airside zone", in_airside)
	_expect("no landside passenger ever stood airside", _landside_on_airside == 0)


func _check_scanner_removed() -> void:
	var north := _scanner_ids[0]
	var queue: Array = _security.get_scanner(north).queue.duplicate()
	_objects.remove_object(north)
	await get_tree().process_frame
	await get_tree().process_frame
	var moved := 0
	var waiting := 0
	for p: PassengerScript in queue:
		if p.scanner_id == _scanner_ids[1] and p.state == State.TO_SECURITY:
			moved += 1
		elif p.scanner_id == 0 and p.state == State.CHECKED_IN:
			waiting += 1
	print("INFO | removed scanner's queue: %d joined the other queue, %d waiting for room" % [moved, waiting])
	_expect("removing a scanner sends its %d queuing passengers to the other one (or to wait if it's full)"
		% queue.size(), moved + waiting == queue.size() and (queue.is_empty() or moved > 0))
	_expect("and one scanner is left", _security.get_scanners().size() == 1)


func _check_both_served() -> void:
	var per_scanner := {}
	for id: int in _cleared_at.values():
		per_scanner[id] = per_scanner.get(id, 0) + 1
	print("INFO | 07:40 screened per scanner: %s" % [per_scanner])
	_expect("both scanners screened passengers", _scanner_ids.all(func(id: int) -> bool:
		return per_scanner.get(id, 0) > 0))
	var through := true
	for id: int in _cleared_at:
		if not _seen_in_arch.has(id):
			through = false
	_expect("everyone cleared walked through an arch", through)
	_expect("each scanner screened one passenger at a time", _two_at_once == 0)
	_expect("each scanner screened its queue in order", _out_of_order == 0)
	_expect("no landside passenger ever stood airside", _landside_on_airside == 0)


func _process(_delta: float) -> void:
	if _security == null:
		return
	for s: SecurityScript.Scanner in _security.get_scanners():
		var screening := 0
		for i in s.queue.size():
			if s.queue[i].state == State.SCREENING:
				screening += 1
				if i != 0:
					_out_of_order += 1
		if screening > 1:
			_two_at_once += 1
		# Kept after a scanner is removed, for anyone who was walking through it at the time.
		for tile in _objects.get_object(s.id).tiles:
			_scanner_tiles[tile] = true
	for p: PassengerScript in _spawner.get_all_passengers():
		if p.crowd_id < 0:
			continue
		var tile := BuildGrid.world_to_tile(_crowd.get_passenger_position(p.crowd_id))
		if _scanner_tiles.has(tile) and p.state == State.SCREENING:
			_seen_in_arch[p.id] = true
		if p.access == LANDSIDE and _zones.get_zone(tile) == Zone.AIRSIDE:
			_landside_on_airside += 1
	_update_label()


func _run_until(hh_mm: String) -> void:
	var parts := hh_mm.split(":")
	var until := FlightSchedule.get_today_start() + int(parts[0]) * 3600 + int(parts[1]) * 60
	GameClock.set_speed(FAST_SPEED)
	while GameClock.game_time < until:
		await get_tree().process_frame
	GameClock.set_paused(true)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		GameClock.set_speed(4.0 if GameClock.speed >= FAST_SPEED else FAST_SPEED)
	elif key.keycode == KEY_X:
		if _objects.get_object(_scanner_ids[0]) != null:
			_objects.remove_object(_scanner_ids[0])
		else:
			_scanner_ids[0] = _add_scanner(SCANNERS[0])


func _update_label() -> void:
	var counts := _spawner.get_state_counts()
	var queues := ""
	for s: SecurityScript.Scanner in _security.get_scanners():
		queues += "  scanner %d: %d in queue, %d screened" % [s.id, s.queue.size(), s.served]
	_label.text = "Security   %s %s   speed %s\nCheck-in %d   Checked in %d   Going to / in security queue %d   Screening %d   Airside %d\n%s\nF: fast-forward   X: remove / put back the north scanner   Z: zones   Space / 1 2 3: speed" % [
		GameClock.get_date_string(), GameClock.get_time_string(),
		"paused" if GameClock.paused else "%dx" % GameClock.speed,
		counts[State.TO_CHECKIN] + counts[State.QUEUING_CHECKIN] + counts[State.CHECKING_IN],
		counts[State.CHECKED_IN], counts[State.TO_SECURITY] + counts[State.QUEUING_SECURITY],
		counts[State.SCREENING], counts[State.AIRSIDE], queues]


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
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.45)
	plane.material = mat
	ground.mesh = plane
	ground.position = BuildGrid.tile_corner_to_world(B + SIZE / 2) + Vector3(0, -0.01, 0)
	add_child(ground)
	var camera := OrbitCameraScript.new()
	camera.start_distance = 60.0
	camera.start_pitch_deg = 55.0
	add_child(camera)  # the terminal is near the world origin, where the camera looks
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
