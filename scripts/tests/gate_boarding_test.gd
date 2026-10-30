extends Node3D
## Test for gate waiting and boarding (checklist step 32).
## Run this scene on its own (F6). It builds a 40 x 24 m terminal: landside
## (entrance, four check-in desks), a security strip with two scanners, and
## airside in the east with a gate desk facing west, four rows of seats
## (16 seats) facing it and a door behind it out to a stand on the apron,
## plus a runway to the south so departures can take off. BQ 101/102 use the
## stand; with no taxiways here the test counts BQ 101 as parked once it has
## landed. Boarding here closes 10 minutes after departure time, so BQ 102
## has to wait for it. It checks the gate, its seats and its door, fast-
## forwards to 07:20 and checks that passengers sit on free seats at their
## gate (one each) or stand near it, then runs on and checks that boarding
## opens 40 minutes before departure, passengers are called in groups, walk
## to the desk, go out of the door and across the apron to the aircraft's
## front door and board there, that BQ 102 doesn't take off until boarding
## has finished, and that it takes off with everyone who boarded.
## Prints PASS or FAIL for each check, then keeps running so you can watch:
##   F      fast-forward (20x) / back to 4x
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
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const StandsScript := preload("res://scripts/airside/stands.gd")
const AirTrafficScript := preload("res://scripts/flights/air_traffic.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State

const B := Vector2i(2240, 990)
const SIZE := Vector2i(40, 24)
const SECURITY_X := 20
const AIRSIDE_X := 28
const BACK_WALL_X := 26
const ENTRANCE := Vector2i(10, 24)
const DESKS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(3, 6), Vector2i(3, 18), Vector2i(3, 21)]
const SCANNERS: Array[Vector2i] = [Vector2i(24, 8), Vector2i(24, 14)]
## Gate desk centre (x on a tile centre, 1 x 2 tiles once turned), facing west.
const GATE := Vector2(37.5, 12.0)
## Seat row centres (4 seats along Z once turned), facing east towards the gate.
const SEAT_ROWS: Array[Vector2] = [Vector2(31.5, 8.0), Vector2(31.5, 16.0), Vector2(33.5, 8.0), Vector2(33.5, 16.0)]
## Door in the east wall behind the gate desk (vertical edge corner).
const GATE_DOOR := Vector2i(40, 12)
## Stand east of the terminal: middle of its entry edge, entry facing +X (index 3), so
## the aircraft parks nose in towards the terminal with its back edge 2 m from the wall.
const STAND_ANCHOR := Vector2i(112, 12)
const STAND_FACING := 3
const FAST_SPEED := 20.0
## Boarding closes this long after departure in this test, so the aircraft has to wait.
const CLOSE_AFTER := 10 * 60

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
var _runways: RunwaysScript
var _stands: StandsScript
var _stand_id := 0
var _traffic: AirTrafficScript
## Passenger id -> where they were last seen walking to the aircraft, and ids seen outside the terminal.
var _last_apron_pos := {}
var _seen_outside := {}
var _boarded_away_from_door := 0
var _boarded_not_outside := 0
var _label: Label
var _gate_id := 0
var _flight: FlightScript
## Game times of events for BQ 102.
var _opened_at := -1
var _took_off_at := -1
var _aircraft_while_boarding := 0
var _boarded_before_open := 0
var _double_seated := 0
## Most passengers called to board in one simulation tick, and how many had been called by the last tick.
var _max_called_per_call := 0
var _last_called_count := 0


func _ready() -> void:
	print("TEST START | gate waiting and boarding")
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
	_stands = StandsScript.new()
	_stands.terminal_floor = _floor
	add_child(_stands)
	_stand_id = _stands.add_stand(&"medium", B + STAND_ANCHOR, STAND_FACING)
	_gates = GatesScript.new()
	_gates.placed_objects = _objects
	_gates.terminal_floor = _floor
	_gates.terminal_walls = _walls
	_gates.stands = _stands
	_gates.terminal_zones = _zones
	_gates.terminal_paths = _paths
	_gates.spawner = _spawner
	_gates.security = _security
	_gates.close_before = -CLOSE_AFTER
	add_child(_gates)
	_runways = RunwaysScript.new()
	add_child(_runways)
	_runways.add_runway(&"medium", Vector2i(1000, 1400), Vector2i(3400, 1400))
	_traffic = AirTrafficScript.new()
	_traffic.runways = _runways
	_traffic.gates = _gates
	add_child(_traffic)

	_flight = _first_departure()
	_flight.stand_id = _stand_id
	_flight.pair.stand_id = _stand_id
	# No taxiways in this test: count the arrival as parked on the stand once it has landed.
	_traffic.rollout_finished.connect(func(f: FlightScript, _a: Node3D) -> void:
		if f == _flight.pair:
			f.status = FlightScript.Status.ON_STAND)
	_gates.passenger_boarded.connect(_on_boarded)
	_gates.boarding_opened.connect(func(f: FlightScript) -> void:
		if f == _flight:
			_opened_at = GameClock.game_time)
	_gates.passenger_boarded.connect(func(p: PassengerScript) -> void:
		if p.flight == _flight and _opened_at < 0:
			_boarded_before_open += 1)
	GameClock.ticked.connect(_count_calls)
	_traffic.took_off.connect(func(f: FlightScript, _a: Node3D) -> void:
		if f == _flight:
			_took_off_at = GameClock.game_time)

	_check_gate()
	await _run_until(_flight.scheduled_time - _gates.open_before - 5 * 60)
	_check_waiting()
	await _run_until(_flight.scheduled_time + CLOSE_AFTER + 30 * 60, func() -> bool: return _took_off_at >= 0)
	_check_boarding()
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
		_add_object(CheckInScript.DESK_ID, Vector2(corner), PI / 2.0)
	for corner in SCANNERS:
		_walls.set_door(B + Vector2i(BACK_WALL_X, corner.y), false, true)
		_add_object(SecurityScript.SCANNER_ID, Vector2(corner), -PI / 2.0)
	_gate_id = _add_object(GatesScript.GATE_ID, GATE, -PI / 2.0)
	for row in SEAT_ROWS:
		_add_object(GatesScript.SEAT_ROW_ID, row, PI / 2.0)
	_walls.set_door(B + GATE_DOOR, false, true)


## Places an object centred at a point given in tiles from B.
func _add_object(def_id: StringName, at: Vector2, yaw: float) -> int:
	var pos := BuildGrid.tile_corner_to_world(B) + Vector3(at.x, 0.0, at.y) * BuildGrid.TILE_SIZE
	pos.y = _floor.get_surface_height(BuildGrid.world_to_tile(pos))
	return _objects.add_object(def_id, pos, yaw)


# --- Checks -----------------------------------------------------------------------

func _check_gate() -> void:
	var gates := _gates.get_gates()
	_expect("one gate (the gate desk on airside)", gates.size() == 1)
	var gate: GatesScript.Gate = _gates.get_gate(_gate_id)
	_expect("the gate has the 16 seats around it", gate != null and gate.seats.size() == 16)
	_expect("%s uses that gate" % _flight.flight_number, _gates.get_gate_for(_flight) == gate)
	_expect("the gate's way out is the door behind the desk", gate != null and gate.has_exit
		and BuildGrid.world_to_tile(gate.exit_inside) == B + GATE_DOOR - Vector2i(1, 0)
		and BuildGrid.world_to_tile(gate.exit_outside).y == B.y + GATE_DOOR.y
		and BuildGrid.world_to_tile(gate.exit_outside).x >= B.x + GATE_DOOR.x
		and not _floor.has_floor(BuildGrid.world_to_tile(gate.exit_outside)))
	_expect("the departure has %d passengers" % _flight.passengers.size(), not _flight.passengers.is_empty())


func _check_waiting() -> void:
	var gate: GatesScript.Gate = _gates.get_gate(_gate_id)
	var seated := 0
	var standing := 0
	var seats_ok := true
	var standing_ok := true
	for p: PassengerScript in _flight.passengers:
		if p.state != State.AT_GATE:
			continue
		var pos := _crowd.get_passenger_position(p.crowd_id)
		if p.seated:
			seated += 1
			var seat: GatesScript.GateSeat = p.seat
			if seat == null or seat.taken != p or pos.distance_to(seat.pos - Vector3(0, GatesScript.SIT_DROP, 0)) > 0.05:
				seats_ok = false
		else:
			standing += 1
			var tile := BuildGrid.world_to_tile(pos)
			if _zones.get_zone(tile) != Zone.AIRSIDE or pos.distance_to(gate.board_point) > 9.0:
				standing_ok = false
	var taken := gate.seats.filter(func(s: GatesScript.GateSeat) -> bool: return s.taken != null).size()
	print("INFO | %s: %d seated, %d standing at the gate; %d of 16 seats taken" % [GameClock.get_time_string(),
		seated, standing, taken])
	_expect("passengers are waiting at the gate before boarding opens", seated + standing > 0)
	_expect("seats fill first (%d seated)" % seated, seated == mini(16, seated + standing))
	_expect("each seated passenger sits on their own seat", seats_ok and _double_seated == 0)
	_expect("the rest stand on airside floor near the desk", standing_ok)
	_expect("nobody boarded yet", _flight.passengers.all(func(p: PassengerScript) -> bool:
		return p.state != State.BOARDING and p.state != State.BOARDED))


func _check_boarding() -> void:
	var b: GatesScript.Boarding = _gates.get_boarding(_flight)
	var opens := _flight.scheduled_time - _gates.open_before
	_expect("boarding opened at %s (40 min before departure)" % _clock(_opened_at), _opened_at >= opens
		and _opened_at < opens + 60)
	_expect("nobody boarded before boarding opened", _boarded_before_open == 0)
	_expect("passengers were called in groups of up to %d" % GatesScript.CALL_GROUP,
		_max_called_per_call > 0 and _max_called_per_call <= GatesScript.CALL_GROUP)
	var boarded := 0
	var order_ok := true
	for p: PassengerScript in _flight.passengers:
		if p.state != State.BOARDED:
			continue
		boarded += 1
		if p.called_time < _opened_at or p.boarded_time < p.called_time or p.crowd_id != -1 or p.seat != null:
			order_ok = false
	_expect("%d of %d passengers boarded" % [boarded, _flight.passengers.size()], boarded > 0 and boarded == b.boarded)
	_expect("each was called, walked to the desk and is now on board", order_ok)
	_expect("each went out of the gate door onto the apron", _boarded_not_outside == 0)
	_expect("each boarded at the aircraft's front door", _boarded_away_from_door == 0)
	_expect("boarding finished at %s (closes %d min after departure)" % [_clock(b.finished_at), CLOSE_AFTER / 60],
		b.finished and (b.finished_at >= _flight.scheduled_time + CLOSE_AFTER or boarded == _flight.passengers.size()))
	_expect("%s took off at %s, after boarding finished" % [_flight.flight_number, _clock(_took_off_at)],
		_took_off_at >= b.finished_at and _took_off_at >= 0)
	_expect("no aircraft left for %s while boarding was on" % _flight.flight_number, _aircraft_while_boarding == 0)
	var gate: GatesScript.Gate = _gates.get_gate(_gate_id)
	_expect("seats are freed as people board", gate.seats.all(func(s: GatesScript.GateSeat) -> bool:
		return s.taken == null or s.taken.state != State.BOARDED))


func _process(_delta: float) -> void:
	if _gates == null or _flight == null:
		return
	var b: GatesScript.Boarding = _gates.get_boarding(_flight)
	if (b == null or not b.finished) and _traffic.get_aircraft_for(_flight) != null:
		_aircraft_while_boarding += 1
	var seen := {}
	for p: PassengerScript in _spawner.get_all_passengers():
		if p.seated:
			if seen.has(p.seat):
				_double_seated += 1
			seen[p.seat] = true
		if p.state == State.TO_AIRCRAFT:
			var pos := _crowd.get_passenger_position(p.crowd_id)
			_last_apron_pos[p.id] = pos
			if not _floor.has_floor(BuildGrid.world_to_tile(pos)):
				_seen_outside[p.id] = true
	_update_label()


func _on_boarded(p: PassengerScript) -> void:
	if p.flight != _flight:
		return
	if not _seen_outside.has(p.id):
		_boarded_not_outside += 1
	var stand = _stands.get_stand(_stand_id)
	var nose: Vector3 = stand.get_nose_direction()
	var door: Vector3 = stand.stop + nose * GatesScript.DOOR_AHEAD + Vector3(nose.z, 0.0, -nose.x) * GatesScript.DOOR_SIDE
	var last: Vector3 = _last_apron_pos.get(p.id, Vector3.INF)
	if Vector2(last.x - door.x, last.z - door.z).length() > 3.0:
		_boarded_away_from_door += 1


func _count_calls(_game_seconds: float) -> void:
	if _flight == null:
		return
	var called := 0
	for p: PassengerScript in _flight.passengers:
		if p.called_time >= 0:
			called += 1
	var b: GatesScript.Boarding = _gates.get_boarding(_flight)
	if b != null and b.open and called > _last_called_count:
		_max_called_per_call = maxi(_max_called_per_call, called - _last_called_count)
	_last_called_count = called


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
	var counts := _spawner.get_state_counts()
	var lines := ""
	for f: FlightScript in FlightSchedule.get_all_flights():
		if f.is_arrival() or f.passengers.is_empty() or f.scheduled_time < GameClock.game_time - 3600:
			continue
		var b: GatesScript.Boarding = _gates.get_boarding(f)
		var state := "boarding finished" if b and b.finished else ("boarding" if b and b.open else "not boarding")
		lines += "\n  %s %s (%s): %s, %d on board" % [f.get_time_string(), f.flight_number, f.get_status_name(),
			state, b.boarded if b else 0]
		if lines.count("\n") >= 2:
			break
	_label.text = "Gate and boarding   %s %s   speed %s\nIn security %d   Airside %d   Going to gate %d   At gate %d   Boarding %d   On board %d%s\nF: fast-forward   Space / 1 2 3: speed" % [
		GameClock.get_date_string(), GameClock.get_time_string(),
		"paused" if GameClock.paused else "%dx" % GameClock.speed,
		counts[State.TO_SECURITY] + counts[State.QUEUING_SECURITY] + counts[State.SCREENING],
		counts[State.AIRSIDE], counts[State.TO_GATE], counts[State.AT_GATE], counts[State.BOARDING],
		counts[State.BOARDED], lines]


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


static func _clock(time: int) -> String:
	if time < 0:
		return "--:--"
	var dt := Time.get_datetime_dict_from_unix_time(time)
	return "%02d:%02d" % [dt.hour, dt.minute]
