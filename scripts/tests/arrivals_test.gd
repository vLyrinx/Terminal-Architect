extends Node3D
## Test for arriving passengers (checklist step 33).
## Run this scene on its own (F6). It builds a 40 x 24 m terminal: landside
## in the west with the entrance in the south wall, a security strip, and
## airside in the east, cut off from the rest by a wall with one door (the way
## through for arrivals). A door in the east wall leads out to a stand on the
## apron, and a gate desk stands by it. At 07:15 BQ 101 is put on the stand
## (there are no taxiways here) and its passengers start getting off.
## It checks that they get off one at a time by the aircraft's front door,
## walk across the apron, come in by the east door, walk through airside,
## security and landside and leave by the entrance, where they disappear;
## that they don't go round the outside of the building; and that BQ 102's
## boarding waits until everyone is off.
## Departing passengers (no check-in here) just wait inside the entrance.
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
const GatesScript := preload("res://scripts/passengers/gates.gd")
const ArrivalsScript := preload("res://scripts/passengers/arrivals.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const StandsScript := preload("res://scripts/airside/stands.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE
const ARRIVALS := TerminalPathsScript.Access.ARRIVALS

const B := Vector2i(2240, 990)
const SIZE := Vector2i(40, 24)
const SECURITY_X := 20
const AIRSIDE_X := 28
const ENTRANCE := Vector2i(10, 24)
## The one door from airside into the security strip (vertical edge corner).
const ARRIVALS_DOOR := Vector2i(AIRSIDE_X, 20)
## Door in the east wall out to the apron (vertical edge corner).
const APRON_DOOR := Vector2i(40, 12)
const GATE := Vector2(37.5, 12.0)
const STAND_ANCHOR := Vector2i(112, 12)
const STAND_FACING := 3
const FAST_SPEED := 20.0

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _zones: TerminalZonesScript
var _objects: PlacedObjectsScript
var _paths: TerminalPathsScript
var _crowd: PassengerCrowdScript
var _spawner: PassengerSpawnerScript
var _stands: StandsScript
var _gates: GatesScript
var _arrivals: ArrivalsScript
var _label: Label
var _stand_id := 0
var _arrival: FlightScript
var _departure: FlightScript
var _boarding_opened_at := -1
## Per arriving passenger id: where and when first seen, which zones they were seen in,
## whether they have been inside yet, and where they were last seen.
var _first_pos := {}
var _first_time := {}
var _zones_seen := {}
var _been_inside := {}
var _last_pos := {}
var _outside_after_inside := 0
var _exited: Array[PassengerScript] = []


func _ready() -> void:
	print("TEST START | arriving passengers")
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
	_stands = StandsScript.new()
	_stands.terminal_floor = _floor
	add_child(_stands)
	_stand_id = _stands.add_stand(&"medium", B + STAND_ANCHOR, STAND_FACING)
	_arrivals = ArrivalsScript.new()
	_gates = GatesScript.new()
	_gates.placed_objects = _objects
	_gates.terminal_floor = _floor
	_gates.terminal_walls = _walls
	_gates.terminal_zones = _zones
	_gates.terminal_paths = _paths
	_gates.spawner = _spawner
	_gates.stands = _stands
	_gates.arrivals = _arrivals
	add_child(_gates)
	_arrivals.terminal_floor = _floor
	_arrivals.terminal_paths = _paths
	_arrivals.spawner = _spawner
	_arrivals.gates = _gates
	add_child(_arrivals)
	_arrivals.passenger_exited.connect(func(p: PassengerScript) -> void: _exited.append(p))

	_departure = _first_departure()
	_arrival = _departure.pair
	_gates.boarding_opened.connect(func(f: FlightScript) -> void:
		if f == _departure:
			_boarding_opened_at = GameClock.game_time)

	_check_paths()
	await _run_until(_arrival.scheduled_time)
	# No taxiways in this test: put the aircraft on its stand by hand.
	_arrival.stand_id = _stand_id
	_departure.stand_id = _stand_id
	_arrival.status = FlightScript.Status.ON_STAND
	_arrivals.start(_arrival)
	_check_started()
	await _run_until(_arrival.scheduled_time + 3 * 3600, func() -> bool:
		var d: ArrivalsScript.Deplaning = _arrivals.get_deplaning(_arrival)
		return d.exited >= d.total)
	_check_finished()
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
	_walls.set_run(B + Vector2i(AIRSIDE_X, 0), B + Vector2i(AIRSIDE_X, SIZE.y), true)
	_walls.set_door(B + ENTRANCE, true, true)
	_walls.set_door(B + ARRIVALS_DOOR, false, true)
	_walls.set_door(B + APRON_DOOR, false, true)
	var pos := BuildGrid.tile_corner_to_world(B) + Vector3(GATE.x, 0.0, GATE.y)
	pos.y = _floor.get_surface_height(BuildGrid.world_to_tile(pos))
	_objects.add_object(GatesScript.GATE_ID, pos, -PI / 2.0)


# --- Checks -----------------------------------------------------------------------

func _check_paths() -> void:
	var apron_inside := _tile_world(APRON_DOOR - Vector2i(1, 0))
	var entrance_inside := _tile_world(ENTRANCE - Vector2i(0, 1))
	var path := _paths.find_path(apron_inside, entrance_inside, ARRIVALS)
	_expect("arrivals can walk from the apron door through the terminal to the entrance", not path.is_empty())
	_expect("their way goes through the airside door", _passes_door(path))
	_expect("but arrivals can't walk on the ground outside",
		not _paths.is_walkable(B + ENTRANCE + Vector2i(0, 2), ARRIVALS))
	_expect("landside people still can't reach airside", _paths.find_path(entrance_inside, apron_inside,
		LANDSIDE).is_empty())
	_expect("airside people still can't reach the entrance", _paths.find_path(apron_inside, entrance_inside,
		AIRSIDE).is_empty())


func _check_started() -> void:
	var d: ArrivalsScript.Deplaning = _arrivals.get_deplaning(_arrival)
	var seats: int = AircraftCatalog.get_type(_arrival.aircraft_type).seats
	_expect("deplaning started for %s with %d passengers" % [_arrival.flight_number, d.total if d else 0],
		d != null and d.total >= floori(seats * ArrivalsScript.LOAD_MIN) and d.total <= ceili(seats * ArrivalsScript.LOAD_MAX))
	_expect("it isn't finished yet", not _arrivals.is_deplaned(_arrival))


func _check_finished() -> void:
	var d: ArrivalsScript.Deplaning = _arrivals.get_deplaning(_arrival)
	var door := _gates.get_aircraft_door_at(_stand_id)
	_expect("all %d got off, by %s" % [d.total, _clock(d.finished_at)], d.off == d.total and d.finished_at >= 0)
	_expect("one at a time, %d s apart" % ArrivalsScript.DEPLANE_INTERVAL,
		d.finished_at - d.started_at >= (d.total - 1) * ArrivalsScript.DEPLANE_INTERVAL)
	var at_door := true
	var through := true
	var out_entrance := true
	var exit := BuildGrid.tile_to_world(B + ENTRANCE)
	for p in _exited:
		var first: Vector3 = _first_pos.get(p.id, Vector3.INF)
		if Vector2(first.x - door.x, first.z - door.z).length() > 1.0:
			at_door = false
		var seen: Dictionary = _zones_seen.get(p.id, {})
		if not (seen.has(Zone.AIRSIDE) and seen.has(Zone.SECURITY) and seen.has(Zone.LANDSIDE) and seen.has(-1)):
			through = false
		var last: Vector3 = _last_pos.get(p.id, Vector3.INF)
		if _floor.has_floor(BuildGrid.world_to_tile(last)) or last.distance_to(exit) > 6.0:
			out_entrance = false
	_expect("they appeared by the aircraft's front door", at_door)
	_expect("each walked across the apron, then airside, security and landside", through)
	_expect("nobody went outside again before the exit", _outside_after_inside == 0)
	_expect("each left by the entrance and disappeared outside it", out_entrance)
	_expect("all %d have left the terminal, by %s" % [d.total, GameClock.get_time_string()],
		d.exited == d.total and _exited.size() == d.total)
	_expect("none of them are left on screen", _spawner.get_state_counts()[State.TO_EXIT] == 0
		and _arrival.passengers.is_empty())
	_expect("BQ 102 boarding waited until everyone was off (opened %s, all off %s)" % [_clock(_boarding_opened_at),
		_clock(d.finished_at)], _boarding_opened_at >= d.finished_at)


func _process(_delta: float) -> void:
	if _spawner == null:
		return
	for p: PassengerScript in _spawner.get_all_passengers():
		if p.state != State.TO_EXIT or p.crowd_id < 0:
			continue
		var pos := _crowd.get_passenger_position(p.crowd_id)
		if not _first_pos.has(p.id):
			_first_pos[p.id] = pos
			_first_time[p.id] = GameClock.game_time
			_zones_seen[p.id] = {}
		var tile := BuildGrid.world_to_tile(pos)
		var inside := _floor.has_floor(tile)
		_zones_seen[p.id][_zones.get_zone(tile) if inside else -1] = true
		if inside:
			_been_inside[p.id] = true
		elif _been_inside.has(p.id) and pos.distance_to(BuildGrid.tile_to_world(B + ENTRANCE)) > 6.0:
			_outside_after_inside += 1
		_last_pos[p.id] = pos
	_update_label()


# --- Helpers ----------------------------------------------------------------------

func _tile_world(tile: Vector2i) -> Vector3:
	return BuildGrid.tile_to_world(B + tile)


## True if the path crosses the arrivals door between airside and security.
func _passes_door(path: PackedVector3Array) -> bool:
	for i in range(1, path.size()):
		var a := BuildGrid.world_to_tile(path[i - 1]) - B
		var b := BuildGrid.world_to_tile(path[i]) - B
		if (a.x >= AIRSIDE_X) != (b.x >= AIRSIDE_X):
			var t := (float(AIRSIDE_X) - (path[i - 1].x - BuildGrid.tile_corner_to_world(B).x)) / (path[i].x - path[i - 1].x)
			var z := path[i - 1].lerp(path[i], t).z - BuildGrid.tile_corner_to_world(B).z
			return z >= ARRIVALS_DOOR.y and z <= ARRIVALS_DOOR.y + 1
	return false


func _run_until(until: int, stop := Callable()) -> void:
	GameClock.set_speed(FAST_SPEED)
	while GameClock.game_time < until:
		if stop.is_valid() and stop.call():
			break
		await get_tree().process_frame
	GameClock.set_paused(true)


func _first_departure() -> FlightScript:
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and not f.passengers.is_empty() and f.pair != null:
			return f
	return null


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		GameClock.set_speed(4.0 if GameClock.speed >= FAST_SPEED else FAST_SPEED)


func _update_label() -> void:
	var d: ArrivalsScript.Deplaning = _arrivals.get_deplaning(_arrival) if _arrival else null
	var status := "waiting for %s to park" % (_arrival.flight_number if _arrival else "the arrival")
	if d != null:
		status = "%s: %d of %d off the aircraft, %d walking to the exit, %d left the terminal" % [
			_arrival.flight_number, d.off, d.total, d.off - d.exited, d.exited]
	_label.text = "Arrivals   %s %s   speed %s\n%s\nF: fast-forward   Z: zones   Space / 1 2 3: speed" % [
		GameClock.get_date_string(), GameClock.get_time_string(),
		"paused" if GameClock.paused else "%dx" % GameClock.speed, status]


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
	ground.position = BuildGrid.tile_corner_to_world(B + SIZE / 2) + Vector3(20, -0.01, 0)
	add_child(ground)
	var camera := OrbitCameraScript.new()
	camera.start_distance = 75.0
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
