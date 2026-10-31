extends Node
## Arriving passengers (checklist step 33).
##
## When an arriving aircraft parks on its stand (AirTraffic.arrived_on_stand,
## or start() directly), its passengers (seats times a load factor) get off
## one every DEPLANE_INTERVAL by the front door on the aircraft's left. Each
## walks across the apron to the terminal door nearest the aircraft (a door
## between airside floor and the outside), comes in, walks through the
## building to the nearest landside entrance (any terminal floor, see
## TerminalPaths.Access.ARRIVALS) and leaves through it, disappearing a few
## metres outside.
##
## With no door in from the apron nobody gets off (warned once) until one
## is built; with no way through the building to an entrance, passengers
## wait just inside the apron door until there is one.

const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")
const GatesScript := preload("res://scripts/passengers/gates.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const State := PassengerScript.State
const ARRIVALS := TerminalPathsScript.Access.ARRIVALS

## Game seconds between passengers getting off.
const DEPLANE_INTERVAL := 4
## Share of seats taken on each arriving flight (random in this range).
const LOAD_MIN := 0.75
const LOAD_MAX := 0.95
## Passengers step this far outside a door: in from the apron, and out of the exit before they disappear.
const DOOR_STEP := 1.5
const EXIT_STEP := 3.0
const WARN_INTERVAL := 3600

## Every passenger of an arriving flight is off the aircraft.
signal deplaning_finished(flight: FlightScript)
## An arriving passenger walked out of the terminal.
signal passenger_exited(passenger: PassengerScript)


class Deplaning:
	extends RefCounted
	var flight: FlightScript
	## Where passengers get off, and how many there are.
	var door := Vector3.ZERO
	var total := 0
	var off := 0
	var exited := 0
	var next_time := 0
	var started_at := -1
	var finished_at := -1
	## True while nobody can get off because there is no door in from the apron.
	var blocked := false


## The AirTraffic node (optional): deplaning starts when an arrival parks.
@export var air_traffic: Node
@export var terminal_floor: Node3D
@export var terminal_paths: TerminalPathsScript
@export var spawner: PassengerSpawnerScript
@export var gates: GatesScript
@export var floor_index := 0

## Flight id -> Deplaning.
var _deplanings := {}
## Passengers inside the apron door with no way to the exit yet.
var _stuck: Array[PassengerScript] = []
var _last_warning := -WARN_INTERVAL
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if air_traffic != null:
		air_traffic.arrived_on_stand.connect(func(f: FlightScript, _aircraft: Node3D) -> void: start(f))
	GameClock.ticked.connect(_on_ticked)
	GameClock.day_passed.connect(_on_day_passed)


func set_seed(value: int) -> void:
	_rng.seed = value


## Starts getting an arrival's passengers off its aircraft on its stand.
func start(flight: FlightScript) -> void:
	if not flight.is_arrival() or _deplanings.has(flight.id):
		return
	var door := gates.get_aircraft_door_at(flight.stand_id) if gates != null else Vector3.INF
	var type: Resource = AircraftCatalog.get_type(flight.aircraft_type)
	if not door.is_finite() or type == null:
		return
	var d := Deplaning.new()
	d.flight = flight
	d.door = door
	d.total = roundi(type.seats * _rng.randf_range(LOAD_MIN, LOAD_MAX))
	d.started_at = GameClock.game_time
	d.next_time = GameClock.game_time
	_deplanings[flight.id] = d
	print("ARRIVALS | %s %s on stand %d: %d passengers getting off" % [GameClock.get_time_string(),
		flight.flight_number, flight.stand_id, d.total])


## True once an arrival's passengers are all off its aircraft (or none can get off).
func is_deplaned(flight: FlightScript) -> bool:
	var d: Deplaning = _deplanings.get(flight.id)
	return d == null or d.off >= d.total or d.blocked


func get_deplaning(flight: FlightScript) -> Deplaning:
	return _deplanings.get(flight.id)


# --- Getting off and walking out --------------------------------------------------

func _on_ticked(_game_seconds: float) -> void:
	var now := GameClock.game_time
	var doors: Array[Dictionary] = []
	var doors_read := false
	for d: Deplaning in _deplanings.values():
		if d.off >= d.total or now < d.next_time:
			continue
		if not doors_read:
			doors = gates.get_apron_doors()
			doors_read = true
		if doors.is_empty():
			if not d.blocked:
				print("ARRIVALS | %s %s: no door from the apron into the terminal, nobody can get off" % [
					GameClock.get_time_string(), d.flight.flight_number])
			d.blocked = true
			continue
		d.blocked = false
		_get_off(d, _nearest_door(doors, d.door))
		d.off += 1
		d.next_time = now + DEPLANE_INTERVAL
		if d.off >= d.total:
			d.finished_at = now
			print("ARRIVALS | %s %s: all %d passengers off" % [GameClock.get_time_string(), d.flight.flight_number,
				d.total])
			deplaning_finished.emit(d.flight)
	if not _stuck.is_empty():
		var p := _stuck[0]
		var exit := _nearest_exit(spawner.crowd.get_passenger_position(p.crowd_id))
		if not exit.is_empty():
			for q in _stuck.duplicate():
				_walk_to_exit(q)
		elif now - _last_warning >= WARN_INTERVAL:
			_last_warning = now
			print("ARRIVALS | %s %d arriving passengers can't reach a landside exit" % [GameClock.get_time_string(),
				_stuck.size()])


## One passenger steps off by the aircraft door and heads for the terminal door.
func _get_off(d: Deplaning, door: Dictionary) -> void:
	var start := d.door + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
	var inside := BuildGrid.tile_to_world(door.inside, floor_index)
	var out := Vector3(door.outside.x - door.inside.x, 0.0, door.outside.y - door.inside.y)
	var outside := inside + out * (0.5 + DOOR_STEP) + Vector3(-out.z, 0.0, out.x) * _rng.randf_range(-0.25, 0.25)
	outside.y = 0.0
	var p := spawner.add_arriving(d.flight, start, PassengerCrowdScript.yaw_towards(outside - start))
	p.access = ARRIVALS
	spawner.walk(p, outside, func(q: PassengerScript) -> void:
		spawner.walk(q, inside, _walk_to_exit, true), true)


## From inside the apron door through the terminal to the nearest landside exit.
func _walk_to_exit(p: PassengerScript) -> void:
	var pos := spawner.crowd.get_passenger_position(p.crowd_id)
	var exit := _nearest_exit(pos)
	if exit.is_empty():
		if not _stuck.has(p):
			_stuck.append(p)
		return
	_stuck.erase(p)
	var inside := BuildGrid.tile_to_world(exit.inside, floor_index)
	var out := Vector3(exit.outward.x, 0.0, exit.outward.y)
	var gone := inside + out * (0.5 + EXIT_STEP) + Vector3(-out.z, 0.0, out.x) * _rng.randf_range(-1.0, 1.0)
	gone.y = 0.0
	spawner.walk(p, inside, func(q: PassengerScript) -> void:
		spawner.walk(q, gone, _exit, true))


func _exit(p: PassengerScript) -> void:
	p.state = State.EXITED
	var d: Deplaning = _deplanings.get(p.flight.id)
	if d != null:
		d.exited += 1
		if d.exited == d.total:
			print("ARRIVALS | %s all %d passengers from %s have left the terminal" % [GameClock.get_time_string(),
				d.total, d.flight.flight_number])
	passenger_exited.emit(p)
	spawner.remove_passenger(p)


## The landside entrance that can be reached from pos with the shortest walk, or {}.
func _nearest_exit(pos: Vector3) -> Dictionary:
	var best := {}
	var best_length := INF
	for e: Dictionary in spawner.get_entrances():
		var inside := BuildGrid.tile_to_world(e.inside, floor_index)
		# A quick check first: a failed search costs a scan of everything reachable.
		if not terminal_paths.can_reach(pos, inside, ARRIVALS):
			continue
		var path := terminal_paths.find_path(pos, inside, ARRIVALS)
		if path.is_empty():
			continue
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if length < best_length:
			best_length = length
			best = e
	return best


static func _nearest_door(doors: Array[Dictionary], to: Vector3) -> Dictionary:
	var best: Dictionary = doors[0]
	var best_dist := INF
	for door in doors:
		var dist := BuildGrid.tile_to_world(door.outside).distance_squared_to(to)
		if dist < best_dist:
			best_dist = dist
			best = door
	return best


func _on_day_passed(_datetime: Dictionary) -> void:
	for id: int in _deplanings.keys():
		if FlightSchedule.get_flight(id) == null:
			_deplanings.erase(id)
