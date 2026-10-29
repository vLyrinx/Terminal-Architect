extends Node3D
## One aircraft moving along a FlightPath (checklist step 24): the airline's
## model, the flight it is flying and how far along the path it is.
##
## The simulation moves it: advance() is called on each GameClock tick and
## emits the path's events (touchdown, lift-off...) as they pass. Between ticks
## the drawn position runs a little ahead by the time since the last tick, so
## movement looks smooth at any frame rate and game speed.

const FlightScript := preload("res://scripts/flights/flight.gd")

## A path event passed: "gear_down", "touchdown", "stopped", "lift_off", "gear_up", "end".
signal path_event(aircraft: Node3D, event_name: String)
## The end of the path was reached.
signal path_finished(aircraft: Node3D)

var flight: FlightScript
var path: FlightPath
## Runway the path uses.
var runway_id := 0
## The liveried aircraft model (aircraft_model.gd), a child of this node.
var model: Node3D
## Game seconds since the start of the path.
var elapsed := 0.0

var _since_tick := 0.0


## start_at skips that many game seconds into the path (events before it are not emitted).
func setup(p_flight: FlightScript, p_path: FlightPath, p_model: Node3D, start_at := 0.0) -> void:
	flight = p_flight
	path = p_path
	elapsed = clampf(start_at, 0.0, path.duration)
	name = "Aircraft_%s" % p_flight.flight_number.replace(" ", "")
	if p_model:
		model = p_model
		add_child(model)
	_update_visual()


## Moves along the path by game_seconds of simulation time.
func advance(game_seconds: float) -> void:
	var before := elapsed
	elapsed = minf(elapsed + game_seconds, path.duration)
	_since_tick = 0.0
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


func _process(delta: float) -> void:
	if not GameClock.paused:
		_since_tick = minf(_since_tick + delta * GameClock.GAME_SECONDS_PER_REAL_SECOND * GameClock.speed,
			GameClock.TICK_GAME_SECONDS)
	_update_visual()


func _update_visual() -> void:
	var t := minf(elapsed + _since_tick, path.duration)
	transform = path.sample(t)
	if model and "gear_down" in model:
		var down := path.is_gear_down(t)
		if model.gear_down != down:
			model.gear_down = down
