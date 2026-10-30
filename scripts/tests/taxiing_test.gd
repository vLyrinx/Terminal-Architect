extends Node3D
## Test for taxiing (checklist step 25).
## Run this scene on its own (F6). It builds a 2,400 m runway (09 at the west
## end) with straight ramps at x = 1200 and x = 2700, a taxiway along y = 1100
## between them and two medium stands south of it. It checks TaxiRoute's
## rounded corners and U-turns, then flies Friday's BQ 101 / BQ 102 rotation
## through AirTraffic: landing, taxiing off at the exit ahead to its stand,
## parking, backing out at departure time, taxiing to runway 09 (a U-turn at
## the threshold), holding short, lining up and taking off. It checks the
## aircraft stays on the route graph and turns smoothly, then that a second
## aircraft taxiing behind another keeps a safe distance. Prints PASS or FAIL
## for each check, then keeps flying the day's schedule so taxiing can be
## watched (right drag rotates, wheel zooms, WASD pans; 1/2/3 speed).

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const RampsScript := preload("res://scripts/airside/ramps.gd")
const TaxiLinesScript := preload("res://scripts/airside/taxi_lines.gd")
const StandsScript := preload("res://scripts/airside/stands.gd")
const RouteGraphScript := preload("res://scripts/airside/route_graph.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const PlaceRunwayCmd := preload("res://scripts/core/commands/place_runway_command.gd")
const PlaceRampCmd := preload("res://scripts/core/commands/place_ramp_command.gd")
const SetPavingCmd := preload("res://scripts/core/commands/set_paving_command.gd")
const PlaceTaxiLineCmd := preload("res://scripts/core/commands/place_taxi_line_command.gd")
const PlaceStandCmd := preload("res://scripts/core/commands/place_stand_command.gd")
const StandAllocatorScript := preload("res://scripts/flights/stand_allocator.gd")
const AirTrafficScript := preload("res://scripts/flights/air_traffic.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const GroundScript := preload("res://scripts/building/ground.gd")
const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const DAY := 86400
const TICK := 5

var _failures := 0
var _runways: RunwaysScript
var _ramps: RampsScript
var _stands: StandsScript
var _graph: RouteGraphScript
var _runner: CommandRunnerScript
var _allocator: StandAllocatorScript
var _traffic: AirTrafficScript
var _log: Array[String] = []


func _ready() -> void:
	print("TEST START | taxiing")
	GameClock.set_paused(true)
	Money.reset(10000000)
	_build_world()
	await get_tree().process_frame
	_expect("route graph has the runway, both ramps, the taxiway and two stands",
		_graph.find_runway_end("09") >= 0 and _graph.find_stand(1) >= 0 and _graph.find_stand(2) >= 0)

	_check_routes()
	_check_rotation()
	await _check_spacing()

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_start_demo()


# --- World -----------------------------------------------------------------------

func _build_world() -> void:
	var floor_node := TerminalFloorScript.new()
	add_child(floor_node)
	var objects := PlacedObjectsScript.new()
	floor_node.placed_objects = objects
	var walls := TerminalWallsScript.new()
	walls.placed_objects = objects
	walls.terminal_floor = floor_node
	add_child(walls)
	objects.terminal_floor = floor_node
	objects.terminal_walls = walls
	add_child(objects)
	_runways = RunwaysScript.new()
	_runways.terminal_floor = floor_node
	add_child(_runways)
	var taxiways := TaxiwaysScript.new()
	taxiways.terminal_floor = floor_node
	taxiways.runways = _runways
	add_child(taxiways)
	_ramps = RampsScript.new()
	_ramps.terminal_floor = floor_node
	_ramps.runways = _runways
	add_child(_ramps)
	_stands = StandsScript.new()
	_stands.terminal_floor = floor_node
	_stands.runways = _runways
	_stands.taxiways = taxiways
	_stands.ramps = _ramps
	add_child(_stands)
	var lines := TaxiLinesScript.new()
	lines.taxiways = taxiways
	lines.ramps = _ramps
	lines.runways = _runways
	add_child(lines)
	floor_node.runways = _runways
	floor_node.taxiways = taxiways
	floor_node.ramps = _ramps
	floor_node.stands = _stands
	taxiways.ramps = _ramps
	taxiways.stands = _stands
	_runways.taxiways = taxiways
	_runways.stands = _stands
	_graph = RouteGraphScript.new()
	_graph.runways = _runways
	_graph.ramps = _ramps
	_graph.taxi_lines = lines
	_graph.stands = _stands
	add_child(_graph)
	_runner = CommandRunnerScript.new()
	_runner.placed_objects = objects
	_runner.terminal_floor = floor_node
	_runner.terminal_walls = walls
	_runner.runways = _runways
	_runner.taxiways = taxiways
	_runner.ramps = _ramps
	_runner.taxi_lines = lines
	_runner.stands = _stands
	add_child(_runner)
	_runner.command_failed.connect(func(c: RefCounted) -> void: print("INFO | refused %s: %s" % [c.describe(), c.error]))

	# Runway 09/27 along y = 1000, 2,400 m from x = 1000.
	_runner.submit(PlaceRunwayCmd.new(&"medium", Vector2i(1000, 1000), Vector2i(3400, 1000)))
	var runway_id: int = _runways.get_ids()[0]
	var ramp_def := RampCatalog.get_def(&"medium_straight")
	_runner.submit(SetPavingCmd.new(Rect2i(1188, 1088, 1524, 24), true))
	_runner.submit(PlaceTaxiLineCmd.new(Vector2i(1200, 1100), Vector2i(2700, 1100)))
	for x in [1200, 2700]:
		var anchor: Vector2i = _ramps.snap(ramp_def, Vector2(x, 1040)).anchor
		_runner.submit(PlaceRampCmd.new(&"medium_straight", runway_id, anchor, 1))
		_runner.submit(SetPavingCmd.new(Rect2i(x - 12, anchor.y, 24, 1088 - anchor.y), true))
		_runner.submit(PlaceTaxiLineCmd.new(anchor, Vector2i(x, 1100)))
	var stand_def := StandCatalog.get_def(&"medium")
	for x in [1800, 1900]:
		_runner.submit(PlaceStandCmd.new(&"medium", _stands.snap_anchor(stand_def, _world(Vector2i(x, 1145)), 2), 2))

	_allocator = StandAllocatorScript.new()
	_allocator.automatic = false
	_allocator.stands = _stands
	add_child(_allocator)
	_traffic = AirTrafficScript.new()
	_traffic.automatic = false
	_traffic.runways = _runways
	_traffic.route_graph = _graph
	add_child(_traffic)
	for s in ["touched_down", "rollout_finished", "taxi_started", "arrived_on_stand", "cleared_onto_runway", "took_off"]:
		_traffic.connect(s, func(f: FlightScript, _a: Node3D) -> void: _log.append("%s %s" % [s, f.flight_number]))
	_traffic.taxi_route_missing.connect(func(f: FlightScript) -> void: _log.append("taxi_route_missing %s" % f.flight_number))


# --- TaxiRoute --------------------------------------------------------------------

func _check_routes() -> void:
	var corner := TaxiRoute.through([Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(100, 0, 100)] as Array[Vector3])
	var points := corner.get_points()
	var closest := INF
	for p in points:
		closest = minf(closest, p.distance_to(Vector3(100, 0, 0)))
	_expect("a 90 degree corner is rounded (passes %.1f m inside it)" % closest, closest > 10.0 and closest < 15.0)
	_expect("and is shorter than the two legs (%.1f m)" % corner.length, corner.length < 200.0 and corner.length > 180.0)
	_expect("it slows for the turn and stops at the end", corner.speed_limit_at(100.0) < TaxiRoute.TAXI_SPEED - 3.0
		and corner.speed_limit_at(corner.length) == 0.0 and corner.speed_limit_at(5.0) == TaxiRoute.TAXI_SPEED)
	_expect("turns smoothly (%.1f deg per 2 m at most)" % _max_turn(corner), _max_turn(corner) < 6.0)

	var back := TaxiRoute.through([Vector3(0, 0, 0), Vector3(200, 0, 0), Vector3(150, 0, 0)] as Array[Vector3])
	var end_facing := -back.sample(back.length).basis.z
	_expect("doubling back makes a U-turn: ends heading back the other way",
		end_facing.dot(Vector3(-1, 0, 0)) > 0.99 and back.sample(back.length).origin.distance_to(Vector3(150, FlightPath.GROUND_Y, 0)) < 0.01)
	var furthest := 0.0
	for p in back.get_points():
		furthest = maxf(furthest, p.x)
	_expect("without going past the corner (%.1f m)" % furthest, furthest <= 200.01)
	_expect("and turns smoothly (%.1f deg per 2 m)" % _max_turn(back), _max_turn(back) < 12.0)

	var reverse := TaxiRoute.new()
	reverse.add_leg([Vector3(0, 0, 0), Vector3(0, 0, -40)] as Array[Vector3], [], true)
	reverse.add_leg([Vector3(0, 0, -40), Vector3(100, 0, -40)] as Array[Vector3])
	_expect("a reverse leg keeps the nose pointing the other way", (-reverse.sample(10.0).basis.z).dot(Vector3(0, 0, 1)) > 0.99)
	_expect("it is slow, and stops before the forward leg",
		reverse.speed_limit_at(10.0) <= TaxiRoute.REVERSE_SPEED and reverse.next_stop(5.0, true) == 40.0)


# --- One rotation through AirTraffic ------------------------------------------------

func _check_rotation() -> void:
	var friday := GameClock.game_time - GameClock.game_time % DAY
	FlightSchedule.clear()
	FlightSchedule.create_day(friday)
	GameClock.game_time = friday + 6 * 3600
	var arrival := _find("BQ 101")
	var departure := arrival.pair
	_allocator.allocate(arrival)
	var stand: RefCounted = _stands.get_stand(arrival.stand_id)
	_expect("BQ 101 is given stand %d" % arrival.stand_id, stand != null)

	var off_graph := 0.0
	var max_turn := 0.0
	var max_jump := 0.0
	var used_far_exit := false
	var passed_threshold := false
	var on_stand_at := -1
	var parked_ok := false
	var left_stand_at := -1
	var held_at := -1
	var lift_off_at := -1
	var last_pos := Vector3.ZERO
	var last_facing := Vector3.ZERO
	var aircraft: Node3D
	var end := friday + 10 * 3600
	while GameClock.game_time < end and lift_off_at < 0:
		GameClock.game_time += TICK
		if GameClock.game_time % 60 == 0:
			_traffic.update()
		_traffic.advance(TICK)
		aircraft = _traffic.get_aircraft_for(arrival)
		if aircraft == null:
			aircraft = _traffic.get_aircraft_for(departure)
		if aircraft == null or not is_instance_valid(aircraft):
			continue
		var p := Vector3(aircraft.position.x, 0.0, aircraft.position.z)
		var facing := -aircraft.global_transform.basis.z
		facing = Vector3(facing.x, 0.0, facing.z).normalized()
		if aircraft.is_taxiing():
			off_graph = maxf(off_graph, _distance_to_graph(p))
			if last_facing != Vector3.ZERO:
				max_turn = maxf(max_turn, rad_to_deg(last_facing.angle_to(facing)))
				max_jump = maxf(max_jump, p.distance_to(last_pos))
			if p.distance_to(_world(Vector2i(2700, 1085))) < 10.0:
				used_far_exit = true
			if p.x < _world(Vector2i(1060, 1000)).x and absf(p.z - _world(Vector2i(1000, 1000)).z) < 30.0:
				passed_threshold = true
			if held_at < 0 and aircraft.is_waiting_at_hold():
				held_at = GameClock.game_time
			last_facing = facing
			last_pos = p
		else:
			last_facing = Vector3.ZERO
		if on_stand_at < 0 and arrival.status == FlightScript.Status.ON_STAND:
			on_stand_at = GameClock.game_time
			parked_ok = aircraft.parked and p.distance_to(Vector3(stand.stop.x, 0.0, stand.stop.z)) < 1.0 \
				and facing.dot(Vector3(0, 0, 1)) > 0.99
		if left_stand_at < 0 and departure.status == FlightScript.Status.TAXIING:
			left_stand_at = GameClock.game_time
		if departure.status == FlightScript.Status.DEPARTED:
			lift_off_at = GameClock.game_time

	_expect("after landing BQ 101 taxis off the runway", _log.has("taxi_started BQ 101")
		and _log.find("rollout_finished BQ 101") < _log.find("taxi_started BQ 101"))
	_expect("by the exit ahead of it (x = 2700), not the one behind", used_far_exit)
	_expect("it parks on stand %d at the stop bar, nose in, at %s" % [arrival.stand_id, _clock(on_stand_at)],
		on_stand_at > 0 and parked_ok and on_stand_at < departure.scheduled_time)
	_expect("it stays there until BQ 102's 08:05 departure (left %s)" % _clock(left_stand_at),
		left_stand_at >= departure.scheduled_time and left_stand_at < departure.scheduled_time + 120)
	_expect("it holds short of the runway before entering it (%s)" % _clock(held_at),
		held_at > left_stand_at and _log.has("cleared_onto_runway BQ 102"))
	_expect("turns round at the runway 09 threshold to line up", passed_threshold)
	_expect("BQ 102 takes off at %s" % _clock(lift_off_at), lift_off_at > held_at and _log.has("took_off BQ 102"))
	_expect("taxiing stays on the route graph (within %.1f m, U-turns included)" % off_graph,
		off_graph <= TaxiRoute.U_TURN_RADIUS * 2.0 + 1.0)
	_expect("turns smoothly (%.1f deg per tick at most)" % max_turn, max_turn < 20.0)
	_expect("never jumps (%.1f m per tick at most)" % max_jump,
		max_jump <= TaxiRoute.TAXI_SPEED * TICK / FlightPath.TIME_STRETCH + 0.5)
	FlightSchedule.clear()
	for a: Node3D in _traffic.get_aircraft():
		_traffic._remove(a)


# --- Spacing ----------------------------------------------------------------------

func _check_spacing() -> void:
	await get_tree().process_frame
	var runway: RefCounted = _runways.get_all()[0]
	var a := Vector3(_world(Vector2i(1300, 1100)).x, 0.0, _world(Vector2i(1300, 1100)).z)
	var b := Vector3(_world(Vector2i(2400, 1100)).x, 0.0, _world(Vector2i(2400, 1100)).z)
	var leader := _taxi_on(901, [a, b] as Array[Vector3], runway)
	for i in 60:
		_traffic.advance(TICK)
	var follower := _taxi_on(902, [a, b] as Array[Vector3], runway)
	var closest := INF
	for i in 2000:
		GameClock.game_time += TICK
		_traffic.advance(TICK)
		closest = minf(closest, leader.position.distance_to(follower.position))
	var gap := leader.position.distance_to(follower.position)
	_expect("the leader taxis to the end of its route and stops", leader.parked)
	_expect("the aircraft behind never gets closer than %.0f m (closest %.1f m)" % [AirTrafficScript.SAFE_DISTANCE, closest],
		closest >= AirTrafficScript.SAFE_DISTANCE - 2.0)
	_expect("and waits behind it (%.1f m back, stopped)" % gap, absf(gap - AirTrafficScript.SAFE_DISTANCE) < 3.0
		and follower.taxi_speed < 0.05 and not follower.parked)
	for aircraft: Node3D in _traffic.get_aircraft():
		_traffic._remove(aircraft)


## An aircraft of a made-up flight taxiing along points, through AirTraffic.
func _taxi_on(number: int, points: Array[Vector3], runway: RefCounted) -> Node3D:
	var f := FlightScript.new()
	f.id = 100000 + number
	f.airline_id = &"brightwater"
	f.aircraft_type = &"a320"
	f.flight_number = "BQ %d" % number
	f.pair = FlightScript.new()
	var aircraft: Node3D = _traffic._spawn(f, FlightPath.takeoff(runway.ends[0], runway.length), 0, runway.ends[0])
	aircraft.start_taxi(TaxiRoute.through(points))
	return aircraft


# --- Demo ------------------------------------------------------------------------

## Flies Friday's schedule from 07:00 on the live clock, so taxiing can be watched.
func _start_demo() -> void:
	add_child(GroundScript.new())
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.78, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.8)
	add_child(env)
	var camera := OrbitCameraScript.new()
	camera.far = 12000.0
	camera.start_distance = 900.0
	camera.start_pitch_deg = 35.0
	camera._target_focus = _world(Vector2i(2000, 1080))
	add_child(camera)
	camera.current = true

	var friday := GameClock.game_time - GameClock.game_time % DAY
	FlightSchedule.clear()
	FlightSchedule.create_day(friday)
	GameClock.game_time = friday + 7 * 3600
	GameClock.ticked.connect(_traffic.advance)
	GameClock.minute_passed.connect(func(_m: int) -> void:
		_allocator.allocate_upcoming()
		_traffic.update())
	_allocator.allocate_upcoming()
	GameClock.set_speed(1.0)
	print("DEMO | flying Friday's schedule from 07:00")


# --- Helpers -----------------------------------------------------------------------

func _distance_to_graph(p: Vector3) -> float:
	var best := INF
	for edge: Dictionary in _graph.edges.values():
		var a: Vector3 = _graph.nodes[edge.a].position
		var b: Vector3 = _graph.nodes[edge.b].position
		best = minf(best, Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p))
	return best


## Largest change of heading between neighbouring points of a route, in degrees.
func _max_turn(route: TaxiRoute) -> float:
	var most := 0.0
	var s := 0.0
	var last := -route.sample(0.0).basis.z
	while s < route.length:
		s += TaxiRoute.SAMPLE_STEP
		var next := -route.sample(s).basis.z
		most = maxf(most, rad_to_deg(last.angle_to(next)))
		last = next
	return most


func _world(corner: Vector2i) -> Vector3:
	return BuildGrid.tile_corner_to_world(corner)


func _find(number: String) -> FlightScript:
	for f in FlightSchedule.get_all_flights():
		if f.flight_number == number:
			return f
	return null


func _clock(time: int) -> String:
	return "--:--" if time < 0 else AirTrafficScript._clock(time)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
