extends Node3D
## Test for landing and take-off (checklist step 24).
## Run this scene on its own (F6). It builds a 2,400 m runway and a short
## 1,800 m one, checks the approach and take-off paths (glideslope, flare,
## touchdown on the runway, stopping and lifting off before the end, smooth
## turning), then flies Friday's first Brightwater rotation through AirTraffic
## and checks the flight statuses and timings, and the warning when no runway
## is long enough. Prints PASS or FAIL for each check, then keeps landing and
## launching aircraft on the long runway so the movement can be watched
## (orbit camera: right drag rotates, wheel zooms, WASD pans; 1/2/3 speed).

const RunwaysScript := preload("res://scripts/airside/runways.gd")
const AirTrafficScript := preload("res://scripts/flights/air_traffic.gd")
const FlightAircraftScript := preload("res://scripts/flights/flight_aircraft.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const GroundScript := preload("res://scripts/building/ground.gd")
const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const DAY := 86400
const TICK := 5

var _failures := 0
var _runways: RunwaysScript
var _traffic: AirTrafficScript
var _long_id := 0
var _short_id := 0
var _log: Array[String] = []
var _demo: Node3D
var _demo_landing := true
var _demo_count := 0


func _ready() -> void:
	print("TEST START | landing and take-off")
	GameClock.set_paused(true)
	_runways = RunwaysScript.new()
	add_child(_runways)
	_long_id = _runways.add_runway(&"medium", Vector2i(1000, 1000), Vector2i(3400, 1000))
	_short_id = _runways.add_runway(&"medium", Vector2i(1000, 1400), Vector2i(2800, 1400))
	_traffic = AirTrafficScript.new()
	_traffic.automatic = false
	_traffic.runways = _runways
	add_child(_traffic)
	for s in ["approach_started", "touched_down", "rollout_finished", "took_off"]:
		_traffic.connect(s, func(f: FlightScript, _a: Node3D) -> void: _log.append("%s %s" % [s, f.flight_number]))
	_traffic.runway_missing.connect(func(f: FlightScript) -> void: _log.append("runway_missing %s" % f.flight_number))

	var runway: RefCounted = _runways.get_runway(_long_id)
	_check_approach(runway)
	_check_takeoff(runway)
	_check_runway_choice()
	_check_rotation()
	_check_no_runway()

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_start_demo(runway)
	# Stays open with aircraft landing and taking off. Close the window when done.


# --- Paths -----------------------------------------------------------------------

func _check_approach(runway: RefCounted) -> void:
	var end: Dictionary = runway.ends[0]
	var path := FlightPath.approach(end, runway.length, true)
	var t_td := path.get_event_time("touchdown")
	var t_stop := path.get_event_time("stopped")
	var start := path.sample(0.0).origin
	_expect("approach starts in the air (%.0f m) and well out" % start.y,
		start.y > 150.0 and _along(end, start) < -3000.0)
	_expect("the approach lasts %.1f game minutes to touchdown" % (t_td / 60.0), t_td > 600.0 and t_td < 2400.0)
	# Lined up on final, on a 3 degree slope.
	var lined_up := true
	var on_slope := true
	for t in range(int(t_td * 0.6), int(t_td) - 30, 5):
		var p := path.sample(t).origin
		var along := _along(end, p)
		if along > -3000.0 and absf(_across(end, p)) > 0.5:
			lined_up = false
		var to_touchdown := FlightPath.AIM_POINT - along
		if to_touchdown > 600.0 and to_touchdown < 3500.0 and absf(p.y - FlightPath.GROUND_Y - to_touchdown * tan(deg_to_rad(3.0))) > 1.0:
			on_slope = false
	_expect("lined up with the centreline on final", lined_up)
	_expect("descends on a 3 degree glideslope", on_slope)
	var over_threshold := _height_at_along(path, end, 0.0)
	_expect("crosses the threshold at %.1f m" % over_threshold, over_threshold > 8.0 and over_threshold < 20.0)
	var td := path.sample(t_td).origin
	_expect("touches down on the runway %.0f m past the threshold" % _along(end, td),
		td.y - FlightPath.GROUND_Y < 0.05 and absf(_along(end, td) - FlightPath.AIM_POINT) < 2.0
		and runway.rect.has_point(BuildGrid.world_to_tile(td)))
	var sink := (path.sample(t_td - 5.0).origin.y - td.y)
	_expect("the flare gives a gentle touchdown (%.2f m in the last 5 s)" % sink, sink > 0.0 and sink < 1.5)
	var pitch_td := _pitch_deg(path.sample(t_td))
	_expect("nose up at touchdown (%.1f deg)" % pitch_td, pitch_td > 3.0 and pitch_td < 8.0)
	var stop := path.sample(t_stop)
	_expect("stops %.0f m along, before the far end" % _along(end, stop.origin),
		_along(end, stop.origin) < runway.length - FlightPath.RUNWAY_MARGIN + 1.0)
	_expect("nose wheel down and level once stopped", absf(_pitch_deg(stop)) < 0.5 and stop.origin.y - FlightPath.GROUND_Y < 0.01)
	_expect("gear comes down before touchdown", not path.is_gear_down(1.0) and path.is_gear_down(t_td - 60.0))
	var max_bank := _max_bank(path)
	_expect("banks into the turn onto final (%.0f deg)" % max_bank, max_bank > 15.0 and max_bank < 35.0)
	_expect("never turns or jumps suddenly (%.2f deg/s)" % _max_turn_rate(path), _max_turn_rate(path) < 3.0)
	var short_path := FlightPath.approach(end, 1500.0, true)
	var short_stop := _along(end, short_path.sample(short_path.get_event_time("stopped")).origin)
	_expect("brakes harder on a shorter runway (stops at %.0f m of 1,500)" % short_stop, short_stop <= 1400.5)


func _check_takeoff(runway: RefCounted) -> void:
	var end: Dictionary = runway.ends[0]
	var path := FlightPath.takeoff(end, runway.length, false)
	var t_lo := path.get_event_time("lift_off")
	var start := path.sample(0.0).origin
	_expect("take-off starts lined up on the runway", absf(_along(end, start) - FlightPath.LINEUP_OFFSET) < 0.5
		and absf(_across(end, start)) < 0.1 and start.y - FlightPath.GROUND_Y < 0.01)
	var on_ground := true
	for t in range(0, int(t_lo), 5):
		if path.sample(t).origin.y - FlightPath.GROUND_Y > 0.01:
			on_ground = false
	_expect("stays on the ground until lift-off", on_ground)
	var lo := path.sample(t_lo)
	_expect("lifts off %.0f m along, before the far end" % _along(end, lo.origin),
		_along(end, lo.origin) < runway.length - FlightPath.RUNWAY_MARGIN)
	_expect("rotated nose up at lift-off (%.1f deg)" % _pitch_deg(lo), _pitch_deg(lo) > 6.0)
	_expect("accelerates down the runway", path.speed_at(t_lo * 0.5) < path.speed_at(t_lo) and path.speed_at(t_lo) > 70.0)
	var climbing := true
	var last := -1.0
	for t in range(int(t_lo), int(path.duration), 5):
		var y := path.sample(t).origin.y
		if y < last:
			climbing = false
		last = y
	_expect("climbs all the way out", climbing)
	_expect("climbs away to %.0f m" % path.sample(path.duration).origin.y, path.sample(path.duration).origin.y > 400.0)
	_expect("gear goes up after lift-off", path.is_gear_down(t_lo) and not path.is_gear_down(path.duration))
	_expect("never turns or jumps suddenly (%.2f deg/s)" % _max_turn_rate(path), _max_turn_rate(path) < 3.0)
	var short_path := FlightPath.takeoff(end, 1500.0, false)
	_expect("accelerates harder on a shorter runway", _along(end, short_path.sample(short_path.get_event_time("lift_off")).origin)
		< 1500.0 - FlightPath.RUNWAY_MARGIN + 1.0)


# --- AirTraffic --------------------------------------------------------------------

func _check_runway_choice() -> void:
	var pick := _traffic.pick_runway(&"a320")
	_expect("an A320 uses the 2,400 m runway, not the 1,800 m one", not pick.is_empty() and pick.runway.id == _long_id)


func _check_rotation() -> void:
	var friday := GameClock.game_time - GameClock.game_time % DAY
	FlightSchedule.clear()
	FlightSchedule.create_day(friday)
	var arrival := _find("BQ 101")
	var departure := arrival.pair
	GameClock.game_time = friday + 6 * 3600
	var touchdown_at := -1
	var lift_off_at := -1
	var gone_at := -1
	var dep_gone_at := -1
	var aircraft: Node3D
	var end := friday + 9 * 3600
	while GameClock.game_time < end:
		GameClock.game_time += TICK
		_traffic.advance(TICK)
		if GameClock.game_time % 60 == 0:
			_traffic.update()
		if aircraft == null and _traffic.get_aircraft_for(arrival):
			aircraft = _traffic.get_aircraft_for(arrival)
			_expect("BQ 101 starts its approach before 07:15 (%s)" % GameClock.get_time_string(),
				arrival.status == FlightScript.Status.APPROACHING and GameClock.game_time < arrival.scheduled_time)
			_expect("in Brightwater livery, gear up", aircraft.model != null and not aircraft.model.gear_down)
			_expect("the runway is held for its landing", not _traffic.is_runway_free(_long_id, arrival.scheduled_time, arrival.scheduled_time + 60))
		if touchdown_at < 0 and arrival.status == FlightScript.Status.LANDED:
			touchdown_at = GameClock.game_time
			_expect("gear down at touchdown", aircraft.model.gear_down)
		if touchdown_at > 0 and gone_at < 0 and _traffic.get_aircraft_for(arrival) == null:
			gone_at = GameClock.game_time
		if lift_off_at < 0 and departure.status == FlightScript.Status.DEPARTED:
			lift_off_at = GameClock.game_time
		if lift_off_at > 0 and dep_gone_at < 0 and _traffic.get_aircraft_for(departure) == null:
			dep_gone_at = GameClock.game_time
	_expect("BQ 101 touches down at 07:15 (%s)" % _clock(touchdown_at), absi(touchdown_at - arrival.scheduled_time) <= TICK)
	_expect("it stops, waits and leaves the runway (%s)" % _clock(gone_at), gone_at > touchdown_at
		and _log.has("rollout_finished BQ 101"))
	_expect("BQ 102 takes off after its 08:05 departure (%s)" % _clock(lift_off_at),
		lift_off_at > departure.scheduled_time and lift_off_at < departure.scheduled_time + 600)
	_expect("and climbs away out of sight (%s)" % _clock(dep_gone_at), dep_gone_at > lift_off_at)
	_expect("signals came in order", _log.find("approach_started BQ 101") < _log.find("touched_down BQ 101")
		and _log.find("touched_down BQ 101") < _log.find("took_off BQ 102"))


func _check_no_runway() -> void:
	_runways.remove_runway(_long_id)
	var a211 := _find("BQ 211")
	GameClock.game_time = a211.scheduled_time - 600
	GameClock.game_time -= GameClock.game_time % 60
	_traffic.update()
	_traffic.update()
	var warnings := _log.filter(func(line: String) -> bool: return line == "runway_missing BQ 211")
	_expect("with only an 1,800 m runway, BQ 211 is warned about once", warnings.size() == 1)
	_expect("and doesn't start an approach", a211.status == FlightScript.Status.SCHEDULED and _traffic.get_aircraft().is_empty())
	_long_id = _runways.add_runway(&"medium", Vector2i(1000, 1000), Vector2i(3400, 1000))
	_traffic.update()
	_expect("once a long runway is built it flies the whole approach", _traffic.get_aircraft_for(a211) != null
		and _traffic.get_aircraft_for(a211).elapsed == 0.0)
	FlightSchedule.clear()
	for aircraft: Node3D in _traffic.get_aircraft():
		aircraft.queue_free()


# --- Demo ------------------------------------------------------------------------

## Lands and launches aircraft one after another on the long runway, on the live clock.
func _start_demo(runway: RefCounted) -> void:
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
	camera.start_distance = 1400.0
	camera.start_pitch_deg = 20.0
	camera._target_focus = runway.ends[0].position + runway.ends[0].direction * 300.0
	add_child(camera)
	camera.current = true
	GameClock.ticked.connect(func(s: float) -> void:
		if is_instance_valid(_demo):
			_demo.advance(s)
		else:
			_next_demo(runway))
	GameClock.set_speed(1.0)


func _next_demo(runway: RefCounted) -> void:
	var f := FlightScript.new()
	f.airline_id = &"brightwater"
	_demo_count += 1
	f.aircraft_type = &"a320" if _demo_count % 2 == 0 else &"b738"
	f.flight_number = "BQ %d" % (900 + _demo_count)
	var left := (_demo_count >> 1) % 2 == 0
	var path := FlightPath.approach(runway.ends[0], runway.length, left, 30.0) if _demo_landing \
		else FlightPath.takeoff(runway.ends[0], runway.length, left)
	print("DEMO | %s %s" % [f.flight_number, "landing" if _demo_landing else "taking off"])
	_demo_landing = not _demo_landing
	_demo = FlightAircraftScript.new()
	_demo.setup(f, path, AirlineCatalog.make_aircraft_model(f.airline_id, f.aircraft_type))
	_demo.path_finished.connect(func(a: Node3D) -> void: a.queue_free())
	add_child(_demo)


# --- Helpers -----------------------------------------------------------------------

func _along(end: Dictionary, p: Vector3) -> float:
	var flat: Vector3 = Vector3(p.x, 0.0, p.z) - end.position
	return flat.dot(end.direction)


func _across(end: Dictionary, p: Vector3) -> float:
	var flat: Vector3 = Vector3(p.x, 0.0, p.z) - end.position
	return flat.dot(end.direction.cross(Vector3.UP))


## Height of the wheels where the path passes `along` metres from the threshold.
func _height_at_along(path: FlightPath, end: Dictionary, along: float) -> float:
	var t := 0.0
	while t < path.duration:
		var p := path.sample(t).origin
		if _along(end, p) >= along:
			return p.y - FlightPath.GROUND_Y
		t += 0.25
	return -1.0


func _pitch_deg(xform: Transform3D) -> float:
	var forward := -xform.basis.z
	return rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))


func _max_bank(path: FlightPath) -> float:
	var most := 0.0
	var t := 0.0
	while t < path.duration:
		var right := path.sample(t).basis.x
		most = maxf(most, absf(rad_to_deg(asin(clampf(right.y, -1.0, 1.0)))))
		t += 5.0
	return most


## Largest change of orientation per game second along the path, in degrees.
func _max_turn_rate(path: FlightPath) -> float:
	var most := 0.0
	var t := 0.0
	var q := path.sample(0.0).basis.get_rotation_quaternion()
	while t < path.duration:
		t += 1.0
		var next := path.sample(t).basis.get_rotation_quaternion()
		most = maxf(most, rad_to_deg(q.angle_to(next)))
		q = next
	return most


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
