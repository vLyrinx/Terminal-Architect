extends Node3D
## Test for spawning passengers from flights (checklist step 29).
## Run this scene on its own (F6). It builds a small terminal, 30 x 16 m:
## landside with an entrance door in the south wall, and an airside room in
## the east with its own outside door (which must not count as an entrance).
## Then it checks that only the landside door is an entrance, that every
## departure flight in today's schedule has its passengers (seats times a
## load factor), tied to the flight, with arrival times from 2 hours to 45
## minutes before departure. It fast-forwards the clock to 07:40 and checks
## that nobody turned up before their arrival time and that every passenger
## of the 08:05 departure is waiting inside the entrance before it leaves.
## Prints PASS or FAIL for each check, then keeps running so you can watch:
##   F      fast-forward (20x) / back to 4x
##   D      close / open the entrance door
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
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State

## North-west corner of the terminal, in tiles (near the middle of the plot).
const B := Vector2i(2240, 990)
const SIZE := Vector2i(30, 16)
const AIRSIDE_X := 22
## Door positions relative to B (corner of the edge).
const ENTRANCE := Vector2i(8, 16)
const AIRSIDE_OUTSIDE_DOOR := Vector2i(26, 16)
const FAST_SPEED := 20.0
const CHECK_UNTIL := "07:40"

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _zones: TerminalZonesScript
var _objects: PlacedObjectsScript
var _paths: TerminalPathsScript
var _crowd: PassengerCrowdScript
var _spawner: PassengerSpawnerScript
var _label: Label
var _early := 0
var _checking := false
var _door_open := true


func _ready() -> void:
	print("TEST START | passenger spawning from flights")
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

	_check_entrances()
	_check_created()
	await _check_arrivals()
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
	_zones.paint_rect(Rect2i(B, Vector2i(AIRSIDE_X, SIZE.y)), Zone.LANDSIDE)
	_zones.paint_rect(Rect2i(B + Vector2i(AIRSIDE_X, 0), Vector2i(SIZE.x - AIRSIDE_X, SIZE.y)), Zone.AIRSIDE)
	var c0 := B
	var c1 := B + SIZE
	_walls.set_run(c0, Vector2i(c1.x, c0.y), true)
	_walls.set_run(Vector2i(c0.x, c1.y), c1, true)
	_walls.set_run(c0, Vector2i(c0.x, c1.y), true)
	_walls.set_run(Vector2i(c1.x, c0.y), c1, true)
	_walls.set_run(B + Vector2i(AIRSIDE_X, 0), B + Vector2i(AIRSIDE_X, SIZE.y), true)
	_walls.set_door(B + ENTRANCE, true, true)
	_walls.set_door(B + AIRSIDE_OUTSIDE_DOOR, true, true)


# --- Checks -----------------------------------------------------------------------

func _check_entrances() -> void:
	var entrances := _spawner.get_entrances()
	_expect("one entrance found (the airside outside door doesn't count)", entrances.size() == 1)
	if entrances.size() == 1:
		var e: Dictionary = entrances[0]
		_expect("entrance is the south landside door, facing out", e.inside == B + ENTRANCE + Vector2i(0, -1)
			and e.outside == B + ENTRANCE and e.outward == Vector2i(0, 1))


func _check_created() -> void:
	var start := GameClock.game_time
	var departures := 0
	var all_counts_ok := true
	var all_tied := true
	var all_times_ok := true
	var arrivals_empty := true
	for f: FlightScript in FlightSchedule.get_all_flights():
		if f.is_arrival():
			arrivals_empty = arrivals_empty and f.passengers.is_empty()
			continue
		departures += 1
		var seats: int = AircraftCatalog.get_type(f.aircraft_type).seats
		var n := f.passengers.size()
		if n < floori(seats * PassengerSpawnerScript.LOAD_MIN) or n > ceili(seats * PassengerSpawnerScript.LOAD_MAX):
			all_counts_ok = false
		for p: PassengerScript in f.passengers:
			if p.flight != f or _spawner.get_passenger(p.id) != p or p.state != State.EXPECTED:
				all_tied = false
			if p.arrival_time < f.scheduled_time - PassengerSpawnerScript.EARLIEST_BEFORE \
					or p.arrival_time > f.scheduled_time - PassengerSpawnerScript.LATEST_BEFORE or p.arrival_time < start:
				all_times_ok = false
	_expect("departures in the schedule: %d" % departures, departures > 0)
	_expect("each departure has 75-95% of its seats as passengers", all_counts_ok)
	_expect("each passenger is tied to their flight (both ways) and expected", all_tied)
	_expect("arrival times are 2 h to 45 min before departure (and not in the past)", all_times_ok)
	_expect("arrival flights get no departing passengers", arrivals_empty)


func _check_arrivals() -> void:
	var first := _first_departure()
	var later := _next_departure_after(first)
	var until := _time_today(CHECK_UNTIL)
	print("INFO | fast-forwarding to %s at %dx (first departure %s %s)" % [CHECK_UNTIL, FAST_SPEED,
		first.get_time_string(), first.flight_number])
	_checking = true
	GameClock.set_speed(FAST_SPEED)
	while GameClock.game_time < until:
		await get_tree().process_frame
	GameClock.set_paused(true)
	_checking = false

	_expect("nobody appeared before their arrival time", _early == 0)
	var all_in := true
	var in_time := true
	var inside := true
	for p: PassengerScript in first.passengers:
		if p.state != State.AT_ENTRANCE:
			all_in = false
			continue
		if p.entered_time < p.arrival_time or p.entered_time >= first.scheduled_time:
			in_time = false
		var tile := BuildGrid.world_to_tile(_crowd.get_passenger_position(p.crowd_id))
		if not _floor.has_floor(tile) or _zones.get_zone(tile) != Zone.LANDSIDE:
			inside = false
	_expect("all %d passengers for %s are at the entrance by %s" % [first.passengers.size(), first.flight_number,
		CHECK_UNTIL], all_in)
	_expect("each came in after their arrival time and before departure", in_time)
	_expect("they wait on landside floor inside the entrance", inside)
	if later != null:
		var none_yet := later.passengers.all(func(p: PassengerScript) -> bool: return p.state == State.EXPECTED)
		_expect("passengers for %s (%s) haven't arrived yet" % [later.flight_number, later.get_time_string()], none_yet)
	_expect("crowd shows one figure per passenger that has arrived", _crowd.get_count() == _visible_count())
	GameClock.set_paused(false)


func _first_departure() -> FlightScript:
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and not f.passengers.is_empty():
			return f
	return null


func _next_departure_after(first: FlightScript) -> FlightScript:
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and f.scheduled_time > first.scheduled_time and not f.passengers.is_empty():
			return f
	return null


func _time_today(hh_mm: String) -> int:
	var parts := hh_mm.split(":")
	return FlightSchedule.get_today_start() + int(parts[0]) * 3600 + int(parts[1]) * 60


func _visible_count() -> int:
	var counts := _spawner.get_state_counts()
	return counts[State.ARRIVING] + counts[State.AT_ENTRANCE]


# --- Demo -------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _spawner == null:
		return
	if _checking:
		var now := GameClock.game_time
		for f: FlightScript in FlightSchedule.get_all_flights():
			for p: PassengerScript in f.passengers:
				if p.state != State.EXPECTED and p.arrival_time > now:
					_early += 1
	var counts := _spawner.get_state_counts()
	var next := ""
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and f.scheduled_time > GameClock.game_time and not f.passengers.is_empty():
			var arrived := f.passengers.filter(func(p: PassengerScript) -> bool: return p.state != State.EXPECTED).size()
			next += "\n  %s %s: %d / %d arrived" % [f.get_time_string(), f.flight_number, arrived, f.passengers.size()]
			if next.count("\n") >= 3:
				break
	_label.text = "Passenger spawning   %s %s   speed %s\nExpected %d   Walking in %d   At entrance %d\nNext departures:%s\nF: fast-forward   D: %s the entrance door   Space / 1 2 3: speed" % [
		GameClock.get_date_string(), GameClock.get_time_string(),
		"paused" if GameClock.paused else "%dx" % GameClock.speed,
		counts[State.EXPECTED], counts[State.ARRIVING], counts[State.AT_ENTRANCE], next,
		"close" if _door_open else "open"]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		GameClock.set_speed(4.0 if GameClock.speed >= FAST_SPEED else FAST_SPEED)
	elif key.keycode == KEY_D:
		_door_open = not _door_open
		_walls.set_door(B + ENTRANCE, true, _door_open)


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
	plane.size = Vector2(120, 80)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.45)
	plane.material = mat
	ground.mesh = plane
	ground.position = BuildGrid.tile_corner_to_world(B + SIZE / 2) + Vector3(0, -0.01, 0)
	add_child(ground)
	var camera := OrbitCameraScript.new()
	camera.start_distance = 55.0
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
