extends Node
## Missed flights (checklist step 34).
##
## When a departure's boarding finishes (Gates.boarding_finished), everyone
## booked on it who isn't on board has missed it. They leave whatever they
## were doing (a check-in or security queue, a gate seat, the walk to the
## gate), walk through the terminal (any terminal floor, see
## TerminalPaths.Access.ARRIVALS) to the nearest landside entrance and
## disappear a few metres outside it. Passengers who hadn't come in yet are
## simply dropped. A departure that leaves without boarding (no gate desk)
## does the same once it has departed.
##
## With no way to an entrance, missed passengers wait where they are until
## there is one.
##
## Missed passengers are counted per game day (get_missed_today(),
## get_missed_on(day)) and per flight (get_missed_for()).

const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const CheckInScript := preload("res://scripts/passengers/check_in.gd")
const SecurityScript := preload("res://scripts/passengers/security.gd")
const GatesScript := preload("res://scripts/passengers/gates.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const State := PassengerScript.State
const ARRIVALS := TerminalPathsScript.Access.ARRIVALS

## Passengers step this far out of the entrance before they disappear.
const EXIT_STEP := 3.0
const WARN_INTERVAL := 3600

## A passenger missed their flight (they start walking out).
signal passenger_missed(passenger: PassengerScript)
## A missed passenger walked out of the terminal.
signal passenger_left(passenger: PassengerScript)
## The number of missed passengers today changed.
signal missed_changed(today: int)

@export var terminal_floor: Node3D
@export var terminal_paths: TerminalPathsScript
@export var spawner: PassengerSpawnerScript
@export var check_in: CheckInScript
@export var security: SecurityScript
@export var gates: GatesScript
@export var floor_index := 0

## Game day number (GameClock.get_day_number()) -> passengers who missed a flight that day.
var _by_day := {}
## Flight id -> passengers who missed it.
var _by_flight := {}
## Flight ids already handled.
var _handled := {}
## Missed passengers with no way to an entrance yet.
var _stuck: Array[PassengerScript] = []
var _last_warning := -WARN_INTERVAL
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if gates != null:
		gates.boarding_finished.connect(_on_boarding_finished)
	GameClock.ticked.connect(_on_ticked)
	GameClock.day_passed.connect(_on_day_passed)


func set_seed(value: int) -> void:
	_rng.seed = value


# --- Queries ----------------------------------------------------------------------

func get_missed_today() -> int:
	return get_missed_on(GameClock.get_day_number())


## Passengers who missed a flight on a game day (GameClock.get_day_number()).
func get_missed_on(day: int) -> int:
	return _by_day.get(day, 0)


func get_missed_for(flight: FlightScript) -> int:
	return _by_flight.get(flight.id, 0)


func get_total_missed() -> int:
	var total := 0
	for n: int in _by_day.values():
		total += n
	return total


# --- Missing the flight -----------------------------------------------------------

func _on_boarding_finished(flight: FlightScript) -> void:
	_miss_all(flight)


func _on_ticked(_game_seconds: float) -> void:
	var now := GameClock.game_time
	# Departures that left without boarding (no gate desk anywhere).
	for f: FlightScript in FlightSchedule.get_all_flights():
		if f.scheduled_time > now:
			break
		if not f.is_arrival() and f.status == FlightScript.Status.DEPARTED and not _handled.has(f.id):
			_miss_all(f)
	if not _stuck.is_empty():
		var p := _stuck[0]
		if not _nearest_exit(spawner.crowd.get_passenger_position(p.crowd_id)).is_empty():
			for q in _stuck.duplicate():
				_walk_out(q)
		elif now - _last_warning >= WARN_INTERVAL:
			_last_warning = now
			print("MISSED | %s %d passengers who missed their flight can't reach a landside exit" % [
				GameClock.get_time_string(), _stuck.size()])


## Everyone booked on the flight who isn't on board misses it.
func _miss_all(flight: FlightScript) -> void:
	if _handled.has(flight.id):
		return
	_handled[flight.id] = true
	var count := 0
	for p: PassengerScript in flight.passengers.duplicate():
		if p.state == State.BOARDED or p.state == State.MISSED:
			continue
		_miss(p)
		count += 1
	if count == 0:
		return
	var day := GameClock.get_day_number()
	_by_day[day] = _by_day.get(day, 0) + count
	_by_flight[flight.id] = count
	print("MISSED | %s %s: %d passengers missed the flight (%d today)" % [GameClock.get_time_string(),
		flight.flight_number, count, _by_day[day]])
	missed_changed.emit(_by_day[day])


func _miss(p: PassengerScript) -> void:
	if check_in != null:
		check_in.drop(p)
	if security != null:
		security.drop(p)
	if gates != null:
		gates.drop(p)
	p.missed_time = GameClock.game_time
	var visible := p.crowd_id >= 0
	p.state = State.MISSED
	passenger_missed.emit(p)
	if not visible:
		# They never came in: nobody to walk out.
		spawner.remove_passenger(p)
		return
	p.access = ARRIVALS
	_walk_out(p)


## Through the terminal to the nearest landside entrance and out of it.
func _walk_out(p: PassengerScript) -> void:
	var exit := _nearest_exit(spawner.crowd.get_passenger_position(p.crowd_id))
	if exit.is_empty():
		if not _stuck.has(p):
			_stuck.append(p)
		# Stop wherever they are.
		spawner.walk(p, spawner.crowd.get_passenger_position(p.crowd_id), Callable(), true)
		return
	_stuck.erase(p)
	var inside := BuildGrid.tile_to_world(exit.inside, floor_index)
	var out := Vector3(exit.outward.x, 0.0, exit.outward.y)
	var gone := inside + out * (0.5 + EXIT_STEP) + Vector3(-out.z, 0.0, out.x) * _rng.randf_range(-1.0, 1.0)
	gone.y = 0.0
	spawner.walk(p, inside, func(q: PassengerScript) -> void:
		spawner.walk(q, gone, _left, true))


func _left(p: PassengerScript) -> void:
	if p.state != State.MISSED:
		return
	passenger_left.emit(p)
	spawner.remove_passenger(p)


## The landside entrance that can be reached from pos with the shortest walk, or {}.
func _nearest_exit(pos: Vector3) -> Dictionary:
	var best := {}
	var best_length := INF
	for e: Dictionary in spawner.get_entrances():
		var path := terminal_paths.find_path(pos, BuildGrid.tile_to_world(e.inside, floor_index), ARRIVALS)
		if path.is_empty():
			continue
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if length < best_length:
			best_length = length
			best = e
	return best


func _on_day_passed(_datetime: Dictionary) -> void:
	var yesterday := GameClock.get_day_number() - 1
	print("MISSED | Day %d: %d passengers missed their flights" % [yesterday, get_missed_on(yesterday)])
	for id: int in _handled.keys():
		if FlightSchedule.get_flight(id) == null:
			_handled.erase(id)
			_by_flight.erase(id)
	missed_changed.emit(get_missed_today())
