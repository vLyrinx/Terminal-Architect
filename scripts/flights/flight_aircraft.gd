extends Node3D
## One aircraft moving along a FlightPath (checklist step 24) or taxiing along
## a TaxiRoute (step 25): the airline's model, the flight it is flying and how
## far along it is.
##
## The simulation moves it: advance() is called on each GameClock tick and
## emits the path's events (touchdown, lift-off...) as they pass. Between ticks
## the drawn position runs a little ahead by the time since the last tick, so
## movement looks smooth at any frame rate and game speed.
##
## Taxiing, it speeds up and slows down within the route's speed limits, and
## never faster than traffic_limit (set by AirTraffic for aircraft ahead). It
## waits short of a runway at the route's hold point until hold_cleared. Once
## at the end of a route to a stand it is parked: it stays there, not moving.

const FlightScript := preload("res://scripts/flights/flight.gd")
## Taxiing never slower than this (real m/s) while it may move, so stops are reached.
const CREEP_SPEED := 0.5

## A path event passed: "gear_down", "touchdown", "stopped", "lift_off", "gear_up", "end".
signal path_event(aircraft: Node3D, event_name: String)
## The end of the path was reached.
signal path_finished(aircraft: Node3D)
## The end of the taxi route was reached.
signal taxi_finished(aircraft: Node3D)

var flight: FlightScript
var path: FlightPath
## Runway the path uses (0 when not on one: taxiing to or parked on a stand).
var runway_id := 0
## The runway end (runway.ends[0] or [1]) the path uses.
var runway_end: Dictionary
## The liveried aircraft model (aircraft_model.gd), a child of this node.
var model: Node3D
## Game seconds since the start of the path.
var elapsed := 0.0

## Taxiing: the route, metres along it and the speed now (real m/s).
var taxi: TaxiRoute
var taxi_distance := 0.0
var taxi_speed := 0.0
## Fastest it may go this tick for traffic ahead (real m/s).
var traffic_limit := INF
## May pass the route's hold point (onto the runway).
var hold_cleared := true
## Standing on a stand.
var parked := false

var _since_tick := 0.0
var _draw_limit := 0.0


## start_at skips that many game seconds into the path (events before it are not emitted).
func setup(p_flight: FlightScript, p_path: FlightPath, p_model: Node3D, start_at := 0.0) -> void:
	flight = p_flight
	path = p_path
	elapsed = clampf(start_at, 0.0, path.duration)
	_name_after(p_flight)
	if p_model:
		model = p_model
		add_child(model)
	_update_visual()


## Switches to flying (or rolling along) a new path from its start.
func start_path(p_path: FlightPath) -> void:
	path = p_path
	elapsed = 0.0
	taxi = null
	parked = false
	_update_visual()


## Starts taxiing along a route from its start.
func start_taxi(route: TaxiRoute) -> void:
	taxi = route
	taxi_distance = 0.0
	taxi_speed = 0.0
	hold_cleared = route.hold_at < 0.0
	traffic_limit = INF
	parked = false
	_draw_limit = 0.0
	_update_visual()


## Stops where it is and stays (on a stand).
func park() -> void:
	parked = true
	taxi = null
	taxi_speed = 0.0
	runway_id = 0


## Flies another flight from now on (the departure after the arrival).
func set_flight(p_flight: FlightScript) -> void:
	flight = p_flight
	_name_after(p_flight)


func is_taxiing() -> bool:
	return taxi != null


## True if stopped at the hold point, waiting to be cleared onto the runway.
func is_waiting_at_hold() -> bool:
	return taxi != null and not hold_cleared and taxi_distance >= taxi.hold_at - 0.5


## Flat unit vector it is moving along (or pointing along when still).
func get_motion() -> Vector3:
	if taxi:
		return taxi.motion_at(taxi_distance)
	var forward := -global_transform.basis.z
	return Vector3(forward.x, 0.0, forward.z).normalized()


## Moves along the path or route by game_seconds of simulation time.
func advance(game_seconds: float) -> void:
	_since_tick = 0.0
	if parked:
		return
	if taxi:
		_advance_taxi(game_seconds)
		return
	var before := elapsed
	elapsed = minf(elapsed + game_seconds, path.duration)
	_update_visual()
	for e in path.events:
		if e.time > before and e.time <= elapsed:
			path_event.emit(self, e.name)
	if before < path.duration and elapsed >= path.duration:
		path_finished.emit(self)


func is_finished() -> bool:
	return elapsed >= path.duration


## Height of the wheels above the runway, in metres.
func get_height() -> float:
	return position.y - FlightPath.GROUND_Y


func _advance_taxi(game_seconds: float) -> void:
	var real_seconds := game_seconds / FlightPath.TIME_STRETCH
	var stop := taxi.next_stop(taxi_distance, hold_cleared)
	var limit := minf(minf(taxi.speed_limit_at(taxi_distance), TaxiRoute.stopping_speed(stop - taxi_distance)),
		traffic_limit)
	taxi_speed = minf(limit, taxi_speed + TaxiRoute.ACCEL * real_seconds)
	var step := taxi_speed * real_seconds
	if traffic_limit > CREEP_SPEED:
		step = maxf(step, CREEP_SPEED * real_seconds)
	taxi_distance = minf(taxi_distance + step, stop)
	if taxi_distance >= stop - 0.01:
		taxi_speed = 0.0
	_draw_limit = stop
	_update_visual()
	if taxi_distance >= taxi.length - 0.01:
		taxi_finished.emit(self)


func _process(delta: float) -> void:
	if not GameClock.paused:
		_since_tick = minf(_since_tick + delta * GameClock.GAME_SECONDS_PER_REAL_SECOND * GameClock.speed,
			GameClock.TICK_GAME_SECONDS)
	_update_visual()


func _update_visual() -> void:
	if parked:
		return
	if taxi:
		var ahead := taxi_speed * _since_tick / FlightPath.TIME_STRETCH
		transform = taxi.sample(minf(taxi_distance + ahead, maxf(_draw_limit, taxi_distance)))
		if model and "gear_down" in model and not model.gear_down:
			model.gear_down = true
		return
	var t := minf(elapsed + _since_tick, path.duration)
	transform = path.sample(t)
	if model and "gear_down" in model:
		var down := path.is_gear_down(t)
		if model.gear_down != down:
			model.gear_down = down


func _name_after(p_flight: FlightScript) -> void:
	name = "Aircraft_%s" % p_flight.flight_number.replace(" ", "")
