extends Node3D
## Test for missed flights (checklist step 34).
## Run this scene on its own (F6). It builds the 40 x 24 m terminal of the
## arrivals test: landside in the west with the entrance in the south wall, a
## security strip, and airside in the east behind a wall with one door, with
## a gate desk by the east door to the apron. There are no check-in desks or
## scanners, so the test moves BQ 102's passengers by hand as they come in,
## in turn:
##   on time  - put on airside and sent to the gate (they board)
##   shopping - put on airside but never go to the gate
##   stuck    - left waiting landside for a check-in desk that doesn't exist
## It checks that when boarding finishes everyone not on board (shopping and
## stuck) misses the flight, is taken out of the check-in and gate lists,
## walks to the entrance (shoppers back through security) and disappears
## outside it, and that they are counted for the flight and for today.
## Prints PASS or FAIL for each check, then keeps running so you can watch:
##   F      fast-forward (20x) / back to 4x
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
const GatesScript := preload("res://scripts/passengers/gates.gd")
const MissedFlightsScript := preload("res://scripts/passengers/missed_flights.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE

const B := Vector2i(2240, 990)
const SIZE := Vector2i(40, 24)
const SECURITY_X := 20
const AIRSIDE_X := 28
const ENTRANCE := Vector2i(10, 24)
const ARRIVALS_DOOR := Vector2i(AIRSIDE_X, 20)
const APRON_DOOR := Vector2i(40, 12)
const GATE := Vector2(37.5, 12.0)
## Where passengers are put on airside, and the area shoppers wander to.
const AIRSIDE_DROP := Vector2i(30, 4)
const SHOP_AREA := Rect2i(Vector2i(29, 2), Vector2i(5, 6))
const FAST_SPEED := 20.0

enum Group { ON_TIME, SHOPPING, STUCK }

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
var _gates: GatesScript
var _missed: MissedFlightsScript
var _label: Label
var _departure: FlightScript
var _rng := RandomNumberGenerator.new()
## Passenger id -> Group, for BQ 102's passengers as they come in.
var _group := {}
var _came_in := 0
var _finished_at := -1
var _boarded_at_finish := 0
## Missed passengers: the passengers, which zones they were seen in, where they were last seen.
var _missed_list: Array[PassengerScript] = []
var _zones_seen := {}
var _last_pos := {}
var _left: Array[PassengerScript] = []


func _ready() -> void:
	print("TEST START | missed flights")
	_rng.seed = 34
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
	_gates = GatesScript.new()
	_gates.placed_objects = _objects
	_gates.terminal_floor = _floor
	_gates.terminal_walls = _walls
	_gates.terminal_zones = _zones
	_gates.terminal_paths = _paths
	_gates.spawner = _spawner
	_gates.security = _security
	add_child(_gates)
	_missed = MissedFlightsScript.new()
	_missed.terminal_floor = _floor
	_missed.terminal_paths = _paths
	_missed.spawner = _spawner
	_missed.check_in = _check_in
	_missed.security = _security
	_missed.gates = _gates
	add_child(_missed)

	_departure = _first_departure()
	# After CheckIn has put them on its waiting list.
	_spawner.passenger_arrived.connect(_on_passenger_arrived)
	_gates.boarding_finished.connect(func(f: FlightScript) -> void:
		if f == _departure:
			_finished_at = GameClock.game_time
			_boarded_at_finish = _gates.get_boarding(f).boarded)
	_missed.passenger_missed.connect(func(p: PassengerScript) -> void:
		if p.flight == _departure:
			_missed_list.append(p)
			_zones_seen[p.id] = {})
	_missed.passenger_left.connect(func(p: PassengerScript) -> void:
		if p.flight == _departure:
			_left.append(p))

	await _run_until(_departure.scheduled_time, func() -> bool: return _finished_at >= 0)
	_check_missed()
	await _run_until(_departure.scheduled_time + 2 * 3600, func() -> bool:
		return _left.size() >= _missed_list.size())
	_check_left()
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	GameClock.set_speed(4.0)


## BQ 102's passengers are put in the three groups in turn as they come in.
func _on_passenger_arrived(p: PassengerScript) -> void:
	if p.flight != _departure:
		return
	var g: Group = (_came_in % 3) as Group
	_came_in += 1
	_group[p.id] = g
	if g == Group.STUCK:
		return
	_check_in.drop(p)
	var tile := B + AIRSIDE_DROP + Vector2i(_rng.randi_range(0, 2), _rng.randi_range(0, 2))
	var pos := BuildGrid.tile_to_world(tile)
	pos.y = _floor.get_surface_height(tile)
	_crowd.set_pose(p.crowd_id, pos, 0.0)
	p.access = AIRSIDE
	p.state = State.AIRSIDE
	p.cleared_time = GameClock.game_time
	if g == Group.ON_TIME:
		_security.passenger_cleared.emit(p)
	else:
		var shop := B + SHOP_AREA.position + Vector2i(_rng.randi_range(0, SHOP_AREA.size.x - 1),
			_rng.randi_range(0, SHOP_AREA.size.y - 1))
		_spawner.walk(p, BuildGrid.tile_to_world(shop))


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
	_walls.set_run(B + Vector2i(AIRSIDE_X, 0), B + Vector2i(AIRSIDE_X, SIZE.y), true)
	_walls.set_door(B + ENTRANCE, true, true)
	_walls.set_door(B + ARRIVALS_DOOR, false, true)
	_walls.set_door(B + APRON_DOOR, false, true)
	var pos := BuildGrid.tile_corner_to_world(B) + Vector3(GATE.x, 0.0, GATE.y)
	pos.y = _floor.get_surface_height(BuildGrid.world_to_tile(pos))
	_objects.add_object(GatesScript.GATE_ID, pos, -PI / 2.0)


# --- Checks -----------------------------------------------------------------------

func _check_missed() -> void:
	var counts := [0, 0, 0]
	for id: int in _group:
		counts[_group[id]] += 1
	var b: GatesScript.Boarding = _gates.get_boarding(_departure)
	_expect("%s boarding finished at %s, after it closed at %s" % [_departure.flight_number, _clock(_finished_at),
		_clock(b.closes_at if b else -1)], _finished_at >= 0 and b != null and _finished_at >= b.closes_at)
	_expect("the %d on-time passengers boarded" % counts[Group.ON_TIME], _boarded_at_finish == counts[Group.ON_TIME])
	var shopping := 0
	var stuck := 0
	var all_missed := true
	for p in _missed_list:
		if p.missed_time != _finished_at:
			all_missed = false
		match _group.get(p.id, -1):
			Group.SHOPPING: shopping += 1
			Group.STUCK: stuck += 1
			_: all_missed = false
	_expect("%d shoppers and %d stuck at check-in missed it, as boarding finished" % [shopping, stuck],
		all_missed and shopping == counts[Group.SHOPPING] and stuck == counts[Group.STUCK])
	_expect("counted for the flight: %d" % _missed.get_missed_for(_departure),
		_missed.get_missed_for(_departure) == _missed_list.size() and not _missed_list.is_empty())
	_expect("counted for today: %d" % _missed.get_missed_today(), _missed.get_missed_today() >= _missed_list.size())
	var in_lists := 0
	for p in _missed_list:
		if p.state != State.MISSED or _check_in._waiting.has(p) or _gates._waiting.has(p):
			in_lists += 1
	_expect("they are all leaving and off the check-in and gate lists", in_lists == 0)


func _check_left() -> void:
	var exit := BuildGrid.tile_to_world(B + ENTRANCE)
	var out_entrance := true
	var through := true
	for p in _left:
		var last: Vector3 = _last_pos.get(p.id, Vector3.INF)
		if _floor.has_floor(BuildGrid.world_to_tile(last)) or last.distance_to(exit) > 6.0:
			out_entrance = false
		var seen: Dictionary = _zones_seen.get(p.id, {})
		if _group.get(p.id) == Group.SHOPPING and not (seen.has(Zone.AIRSIDE) and seen.has(Zone.SECURITY)
				and seen.has(Zone.LANDSIDE)):
			through = false
	_expect("all %d missed passengers have left, by %s" % [_missed_list.size(), GameClock.get_time_string()],
		_left.size() == _missed_list.size())
	_expect("shoppers walked back through security and landside", through)
	_expect("each left by the entrance and disappeared outside it", out_entrance)
	var left_over := 0
	for p: PassengerScript in _spawner.get_all_passengers():
		if p.flight == _departure and p.state != State.BOARDED:
			left_over += 1
	_expect("none of %s's passengers are left on screen" % _departure.flight_number, left_over == 0)


func _process(_delta: float) -> void:
	if _spawner == null:
		return
	for p in _missed_list:
		if p.crowd_id < 0:
			continue
		var pos := _crowd.get_passenger_position(p.crowd_id)
		var tile := BuildGrid.world_to_tile(pos)
		_zones_seen[p.id][_zones.get_zone(tile) if _floor.has_floor(tile) else -1] = true
		_last_pos[p.id] = pos
	_update_label()


# --- Helpers ----------------------------------------------------------------------

func _run_until(until: int, stop := Callable()) -> void:
	GameClock.set_speed(FAST_SPEED)
	while GameClock.game_time < until:
		if stop.is_valid() and stop.call():
			break
		await get_tree().process_frame
	GameClock.set_paused(true)


func _first_departure() -> FlightScript:
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and not f.passengers.is_empty():
			return f
	return null


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		GameClock.set_speed(4.0 if GameClock.speed >= FAST_SPEED else FAST_SPEED)


func _update_label() -> void:
	var b: GatesScript.Boarding = _gates.get_boarding(_departure) if _departure else null
	var boarding := "not open"
	if b != null and b.finished:
		boarding = "finished, %d on board" % b.boarded
	elif b != null and b.open:
		boarding = "closes %s" % _clock(b.closes_at)
	var status := "%s: %d in, boarding %s" % [_departure.flight_number if _departure else "-", _came_in, boarding]
	_label.text = "Missed flights   %s %s   speed %s\n%s\nMissed: %d this flight, %d leaving, %d today\nF: fast-forward   Z: zones   Space / 1 2 3: speed" % [
		GameClock.get_date_string(), GameClock.get_time_string(),
		"paused" if GameClock.paused else "%dx" % GameClock.speed, status,
		_missed.get_missed_for(_departure) if _departure else 0, _missed_list.size() - _left.size(),
		_missed.get_missed_today()]


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
	plane.size = Vector2(160, 100)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.45)
	plane.material = mat
	ground.mesh = plane
	ground.position = BuildGrid.tile_corner_to_world(B + Vector2i(SIZE.x >> 1, SIZE.y >> 1)) + Vector3(20, -0.01, 0)
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


static func _clock(time: int) -> String:
	if time < 0:
		return "--:--"
	var dt := Time.get_datetime_dict_from_unix_time(time)
	return "%02d:%02d" % [dt.hour, dt.minute]
