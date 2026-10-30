extends Node3D
## Test for check-in queues (checklist step 30).
## Run this scene on its own (F6). It builds a 40 x 24 m terminal: landside
## in the west with the entrance in the south wall and three check-in desks
## along the north, facing the entrance; a security strip; and airside in the
## east, where a fourth desk stands (and must not be used). Then it checks
## that the three landside desks get queues running out from their fronts,
## fast-forwards to 06:50 and checks that passengers are spread across the
## desks, stand on their queue spots and are served one at a time for the
## processing time. It removes the middle desk and checks its queue moves to
## the others, runs on to 07:30, and checks that every desk served people and
## that checked-in passengers moved on to wait by security.
## Prints PASS or FAIL for each check, then keeps running so you can watch:
##   F      fast-forward (20x) / back to 4x
##   X      remove / put back the middle desk
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
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State

const B := Vector2i(2240, 990)
const SIZE := Vector2i(40, 24)
const SECURITY_X := 28
const AIRSIDE_X := 32
const ENTRANCE := Vector2i(6, 24)
const SECURITY_DOOR := Vector2i(SECURITY_X, 12)
const AIRSIDE_DOOR := Vector2i(AIRSIDE_X, 12)
## Desk centres (tile corners, relative to B); desks are 2 x 2 and face south (+Z).
const DESKS: Array[Vector2i] = [Vector2i(8, 3), Vector2i(14, 3), Vector2i(20, 3)]
const AIRSIDE_DESK := Vector2i(36, 3)
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
var _label: Label
var _desk_ids: Array[int] = []
var _removed_desk := 0
## Passenger id -> desk id they were served at, and the order each desk served them.
var _served_at := {}
var _out_of_order := 0
var _two_at_once := 0


func _ready() -> void:
	print("TEST START | check-in queues")
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
	_check_in.passenger_checked_in.connect(_on_checked_in)

	_check_desks()
	await _run_until("06:50")
	_check_queues()
	await _check_desk_removed()
	await _run_until("07:30")
	_check_served()
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
	_walls.set_run(B + Vector2i(SECURITY_X, 0), B + Vector2i(SECURITY_X, SIZE.y), true)
	_walls.set_run(B + Vector2i(AIRSIDE_X, 0), B + Vector2i(AIRSIDE_X, SIZE.y), true)
	_walls.set_door(B + ENTRANCE, true, true)
	_walls.set_door(B + SECURITY_DOOR, false, true)
	_walls.set_door(B + AIRSIDE_DOOR, false, true)
	for corner in DESKS:
		_desk_ids.append(_add_desk(corner))
	_add_desk(AIRSIDE_DESK)


func _add_desk(corner: Vector2i) -> int:
	var pos := BuildGrid.tile_corner_to_world(B + corner)
	pos.y = _floor.get_surface_height(B + corner)
	return _objects.add_object(CheckInScript.DESK_ID, pos, 0.0)


# --- Checks -----------------------------------------------------------------------

func _check_desks() -> void:
	var desks := _check_in.get_desks()
	_expect("three desks in use (the airside desk isn't)", desks.size() == 3)
	var fronts_ok := true
	var spots_ok := true
	for d: CheckInScript.Desk in desks:
		var obj = _objects.get_object(d.id)
		var front_tile := BuildGrid.world_to_tile(d.spots[0])
		if d.spots[0].z <= obj.position.z + 1.0 or _objects.get_object_at(front_tile) != 0:
			fronts_ok = false
		for s in d.spots:
			var tile := BuildGrid.world_to_tile(s)
			if not _floor.has_floor(tile) or _zones.get_zone(tile) != Zone.LANDSIDE:
				spots_ok = false
		print("INFO | desk %d: queue of %d spots" % [d.id, d.spots.size()])
	_expect("queues start just in front of each desk", fronts_ok)
	_expect("queue spots are on landside floor", spots_ok)
	var long_enough := desks.all(func(d: CheckInScript.Desk) -> bool:
		# From 1.35 m in front of the desk to the south wall, 0.75 m apart.
		return d.spots.size() >= 25)
	_expect("queues run out to the south wall", long_enough)


func _check_queues() -> void:
	var desks := _check_in.get_desks()
	var sizes: Array[int] = []
	var on_spots := true
	for d: CheckInScript.Desk in desks:
		sizes.append(d.queue.size())
		for i in d.queue.size():
			var p := d.queue[i]
			if p.state == State.QUEUING_CHECKIN and not p.is_walking \
					and _crowd.get_passenger_position(p.crowd_id).distance_to(d.spots[i]) > 0.05:
				on_spots = false
	print("INFO | 06:50 queues: %s" % [sizes])
	_expect("every desk has a queue at 06:50", sizes.min() > 0)
	_expect("passengers are spread across the desks (queues within 4 of each other)", sizes.max() - sizes.min() <= 4)
	_expect("people queuing stand on their queue spots", on_spots)
	_expect("each desk serves one passenger at a time", _two_at_once == 0)
	_expect("each desk serves its queue in order", _out_of_order == 0)


func _check_desk_removed() -> void:
	var middle := _desk_ids[1]
	var queue: Array = _check_in.get_desk(middle).queue.duplicate()
	_removed_desk = _remove_desk(middle)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_in.get_desks()
	var moved := 0
	var waiting := 0
	for p: PassengerScript in queue:
		if (p.desk_id == _desk_ids[0] or p.desk_id == _desk_ids[2]) and p.state == State.TO_CHECKIN:
			moved += 1
		elif p.desk_id == 0 and p.state == State.WAITING_CHECKIN:
			waiting += 1
	print("INFO | removed desk's queue: %d joined other queues, %d waiting for room" % [moved, waiting])
	_expect("removing a desk sends its %d queuing passengers to the other desks (or to wait if they're full)"
		% queue.size(), moved > 0 and moved + waiting == queue.size())
	if waiting > 0:
		await _run_until("07:00")
		var still := queue.filter(func(p: PassengerScript) -> bool: return p.state == State.WAITING_CHECKIN).size()
		_expect("by 07:00 those waiting have joined a queue as room opened", still == 0)
	_expect("and only two desks are left", _check_in.get_desks().size() == 2)


func _check_served() -> void:
	var per_desk := {}
	for desk_id: int in _served_at.values():
		per_desk[desk_id] = per_desk.get(desk_id, 0) + 1
	print("INFO | 07:30 served per desk: %s" % [per_desk])
	_expect("all three desks served passengers", _desk_ids.all(func(id: int) -> bool: return per_desk.get(id, 0) > 0))
	var times_ok := true
	var waiting_ok := true
	var count := 0
	for p: PassengerScript in _spawner.get_all_passengers():
		if p.state != State.CHECKED_IN:
			continue
		count += 1
		if p.checked_in_time - p.entered_time < CheckInScript.PROCESS_MIN:
			times_ok = false
		if p.is_walking:
			continue
		var tile := BuildGrid.world_to_tile(_crowd.get_passenger_position(p.crowd_id))
		var rel := tile - B
		if _zones.get_zone(tile) != Zone.LANDSIDE or rel.x < SECURITY_X - CheckInScript.AFTER_RADIUS - 1:
			waiting_ok = false
	_expect("%d passengers checked in by 07:30" % count, count >= 45)
	_expect("each took at least the processing time", times_ok)
	_expect("checked-in passengers wait on landside next to security", waiting_ok)
	_expect("each desk served one passenger at a time", _two_at_once == 0)
	_expect("each desk served its queue in order", _out_of_order == 0)


func _on_checked_in(p: PassengerScript) -> void:
	_served_at[p.id] = p.desk_id




func _process(_delta: float) -> void:
	if _check_in == null:
		return
	for d: CheckInScript.Desk in _check_in.get_desks():
		var serving := 0
		for i in d.queue.size():
			var p := d.queue[i]
			if p.state == State.CHECKING_IN:
				serving += 1
				if i != 0:
					_out_of_order += 1
		if serving > 1:
			_two_at_once += 1
	_update_label()


func _run_until(hh_mm: String) -> void:
	var parts := hh_mm.split(":")
	var until := FlightSchedule.get_today_start() + int(parts[0]) * 3600 + int(parts[1]) * 60
	GameClock.set_speed(FAST_SPEED)
	while GameClock.game_time < until:
		await get_tree().process_frame
	GameClock.set_paused(true)


func _remove_desk(id: int) -> int:
	_objects.remove_object(id)
	return id


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		GameClock.set_speed(4.0 if GameClock.speed >= FAST_SPEED else FAST_SPEED)
	elif key.keycode == KEY_X:
		if _objects.get_object(_desk_ids[1]) != null:
			_objects.remove_object(_desk_ids[1])
		else:
			_desk_ids[1] = _add_desk(DESKS[1])


func _update_label() -> void:
	var counts := _spawner.get_state_counts()
	var queues := ""
	for d: CheckInScript.Desk in _check_in.get_desks():
		queues += "  desk %d: %d in queue, %d served" % [d.id, d.queue.size(), d.served]
	_label.text = "Check-in   %s %s   speed %s\nArriving %d   Going to / in queue %d   Checking in %d   Checked in %d\n%s\nF: fast-forward   X: remove / put back the middle desk   Space / 1 2 3: speed" % [
		GameClock.get_date_string(), GameClock.get_time_string(),
		"paused" if GameClock.paused else "%dx" % GameClock.speed,
		counts[State.ARRIVING] + counts[State.AT_ENTRANCE], counts[State.TO_CHECKIN] + counts[State.QUEUING_CHECKIN],
		counts[State.CHECKING_IN], counts[State.CHECKED_IN], queues]


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
