extends Node
## Creates departing passengers from flights (checklist step 29).
##
## Every departure flight gets its passengers as soon as the schedule creates
## it: seats times a load factor, each with an arrival time between
## EARLIEST_BEFORE and LATEST_BEFORE its departure. Passengers are tied to
## the flight both ways (Passenger.flight and Flight.passengers).
##
## When a passenger's arrival time comes, they appear just outside a terminal
## entrance, walk in through the door and wait a few metres inside, where
## later steps (check-in, security, gate) pick them up. An entrance is a door
## between open ground and landside (or unzoned) terminal floor. With no
## entrance, passengers wait to arrive until one is built; anyone still not
## there at departure time doesn't come at all.
##
## It also owns passenger movement: walk() sends a visible passenger along a
## path (re-planned when the layout changes) and calls back when they arrive,
## so the check-in, security and gate systems only decide where people go.

const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")
const State := PassengerScript.State
const Piece := TerminalWallsScript.Piece
const Zone := TerminalZonesScript.Zone
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE

## Passengers arrive between these many game seconds before departure.
const EARLIEST_BEFORE := 2 * 3600
const LATEST_BEFORE := 45 * 60
## Share of seats sold on each flight (random in this range).
const LOAD_MIN := 0.75
const LOAD_MAX := 0.95
## How far outside the door passengers appear, and how widely spread (metres).
const SPAWN_DISTANCE := 2.5
const SPAWN_SPREAD := 1.2
## Passengers wait on landside floor within this many tiles of a spot this far inside the door.
const WAIT_INSIDE := 3
const WAIT_RADIUS := 3
## Walking speed in metres per real second at 1x (scaled by the game speed).
## Metres walked per game second, so walks keep to the schedule: 150 m through
## the terminal takes about 20 game minutes. On screen that is 3.6 m/s at 1x.
const WALK_SPEED := 0.12
## The walk cycle animation is timed for this real walking speed (m/s).
const ANIMATION_WALK_SPEED := 1.3
## Minimum game seconds between "no entrance" warnings.
const WARN_INTERVAL := 3600

## A flight's passengers were created.
signal passengers_created(flight: FlightScript)
## A passenger reached their waiting spot inside the entrance.
signal passenger_arrived(passenger: PassengerScript)

@export var terminal_floor: Node3D
@export var terminal_walls: Node3D
@export var terminal_zones: Node3D
@export var terminal_paths: TerminalPathsScript
@export var crowd: PassengerCrowdScript
@export var floor_index := 0

## Every passenger not yet removed, by id.
var _passengers := {}
## Passengers still to arrive, ordered by arrival time.
var _pending: Array[PassengerScript] = []
## Passengers walking in from the door.
var _walking: Array[PassengerScript] = []
## Entrances as dictionaries: inside and outside tile, outward direction (tiles).
var _entrances: Array[Dictionary] = []
var _entrances_dirty := true
var _next_id := 1
## Flight id -> passengers that have appeared so far.
var _arrived_count := {}
var _last_warning := -WARN_INTERVAL
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if terminal_floor != null:
		terminal_floor.floor_changed.connect(func(_r: Rect2i, _f: int) -> void: _entrances_dirty = true)
	if terminal_walls != null:
		terminal_walls.walls_changed.connect(func(_a: Vector2i, _b: Vector2i, _f: int) -> void: _entrances_dirty = true)
	if terminal_zones != null:
		terminal_zones.zones_changed.connect(func(_r: Rect2i, _f: int) -> void: _entrances_dirty = true)
	if terminal_paths != null:
		terminal_paths.paths_changed.connect(_on_paths_changed)
	FlightSchedule.flights_created.connect(_on_flights_created)
	GameClock.ticked.connect(_on_ticked)
	GameClock.day_passed.connect(_on_day_passed)
	_on_flights_created(0, FlightSchedule.get_all_flights())


func set_seed(value: int) -> void:
	_rng.seed = value


func _process(delta: float) -> void:
	if crowd != null:
		crowd.animation_speed = 0.0 if GameClock.paused else \
			GameClock.speed * WALK_SPEED * GameClock.GAME_SECONDS_PER_REAL_SECOND / ANIMATION_WALK_SPEED
	if GameClock.paused or _walking.is_empty():
		return
	var step := WALK_SPEED * GameClock.GAME_SECONDS_PER_REAL_SECOND * GameClock.speed * delta
	var still: Array[PassengerScript] = []
	var done: Array[PassengerScript] = []
	for p in _walking:
		if _walk(p, step):
			still.append(p)
		else:
			done.append(p)
	_walking = still
	for p in done:
		_finish_walk(p)


## Sends a visible passenger walking to target (on their access level's paths);
## done is called with the passenger when they get there. direct walks in a
## straight line, for short moves such as stepping up in a queue.
func walk(p: PassengerScript, target: Vector3, done := Callable(), direct := false) -> void:
	p.target = target
	p.on_arrive = done
	p.walk_direct = direct
	var pos := crowd.get_passenger_position(p.crowd_id)
	if direct or terminal_paths == null:
		p.path = PackedVector3Array([pos, target])
	else:
		p.path = terminal_paths.find_path(pos, target, p.access, true)
	p.path_next = 1
	if p.path.size() < 2:
		_finish_walk(p)
		return
	crowd.set_walking(p.crowd_id, true)
	if not p.is_walking:
		p.is_walking = true
		_walking.append(p)


## Turns a standing passenger to face along direction.
func face(p: PassengerScript, direction: Vector3) -> void:
	if p.crowd_id >= 0 and direction.length_squared() > 0.0001:
		crowd.set_pose(p.crowd_id, crowd.get_passenger_position(p.crowd_id), PassengerCrowdScript.yaw_towards(direction))


## Every passenger not yet removed.
func get_all_passengers() -> Array:
	return _passengers.values()


# --- Queries ----------------------------------------------------------------------

func get_passenger(id: int) -> PassengerScript:
	return _passengers.get(id)


func get_passengers_of(flight: FlightScript) -> Array:
	return flight.passengers


## Number of passengers in each state, as {State: count}.
func get_state_counts() -> Dictionary:
	var counts := {}
	for s: int in State.values():
		counts[s] = 0
	for p: PassengerScript in _passengers.values():
		counts[p.state] += 1
	return counts


## Entrances as dictionaries with "inside" and "outside" tiles and "outward" (a tile step).
func get_entrances() -> Array[Dictionary]:
	_update_entrances()
	return _entrances


## Adds a visible passenger for an arriving flight (step 33) at a world point,
## facing yaw, tied to the flight. The caller sends them on with walk().
func add_arriving(flight: FlightScript, position: Vector3, yaw: float) -> PassengerScript:
	var p := PassengerScript.new()
	p.id = _next_id
	_next_id += 1
	p.flight = flight
	p.arrival_time = GameClock.game_time
	p.state = State.TO_EXIT
	p.crowd_id = crowd.add(position, yaw) if crowd != null else -1
	flight.passengers.append(p)
	_passengers[p.id] = p
	return p


## Removes a passenger completely (later steps call this when they leave or board).
func remove_passenger(p: PassengerScript) -> void:
	_passengers.erase(p.id)
	_pending.erase(p)
	_walking.erase(p)
	p.is_walking = false
	p.on_arrive = Callable()
	if p.crowd_id >= 0 and crowd != null:
		crowd.remove(p.crowd_id)
		p.crowd_id = -1
	if p.flight != null:
		p.flight.passengers.erase(p)


# --- Creating passengers ----------------------------------------------------------

func _on_flights_created(_day_start: int, flights: Array) -> void:
	var added := false
	for f: FlightScript in flights:
		if not f.is_arrival() and f.passengers.is_empty() and _create_passengers(f):
			added = true
	if added:
		_pending.sort_custom(func(a: PassengerScript, b: PassengerScript) -> bool:
			return a.arrival_time < b.arrival_time if a.arrival_time != b.arrival_time else a.id < b.id)


func _create_passengers(f: FlightScript) -> bool:
	var type: Resource = AircraftCatalog.get_type(f.aircraft_type)
	if type == null:
		return false
	var latest := f.scheduled_time - LATEST_BEFORE
	var earliest := maxi(f.scheduled_time - EARLIEST_BEFORE, GameClock.game_time)
	if earliest > latest:
		print("PASSENGERS | %s %s: too close to departure, no passengers" % [f.get_time_string(), f.flight_number])
		return false
	var count := roundi(type.seats * _rng.randf_range(LOAD_MIN, LOAD_MAX))
	for n in count:
		var p := PassengerScript.new()
		p.id = _next_id
		_next_id += 1
		p.flight = f
		p.arrival_time = _rng.randi_range(earliest, latest)
		f.passengers.append(p)
		_passengers[p.id] = p
		_pending.append(p)
	print("PASSENGERS | %s %s: %d of %d seats, arriving %s to %s" % [f.get_time_string(), f.flight_number, count,
		type.seats, _clock(earliest), _clock(latest)])
	passengers_created.emit(f)
	return true


# --- Arriving ---------------------------------------------------------------------

func _on_ticked(_game_seconds: float) -> void:
	var now := GameClock.game_time
	while not _pending.is_empty() and _pending[0].arrival_time <= now:
		var p: PassengerScript = _pending[0]
		var f := p.flight
		if now >= f.scheduled_time or f.status == FlightScript.Status.DEPARTED \
				or f.status == FlightScript.Status.CANCELLED:
			_pending.pop_front()
			remove_passenger(p)
			continue
		if get_entrances().is_empty():
			if now - _last_warning >= WARN_INTERVAL:
				_last_warning = now
				print("PASSENGERS | No terminal entrance: %d passengers can't arrive" % _count_due(now))
			return
		_pending.pop_front()
		_spawn(p)


func _count_due(now: int) -> int:
	var n := 0
	for p in _pending:
		if p.arrival_time > now:
			break
		n += 1
	return n


func _spawn(p: PassengerScript) -> void:
	p.entrance = _rng.randi() % _entrances.size()
	var e: Dictionary = _entrances[p.entrance]
	var out := Vector3(e.outward.x, 0.0, e.outward.y)
	var side := Vector3(-out.z, 0.0, out.x)
	var door: Vector3 = (BuildGrid.tile_to_world(e.inside, floor_index) + BuildGrid.tile_to_world(e.outside, floor_index)) * 0.5
	var start := door + out * SPAWN_DISTANCE + side * _rng.randf_range(-SPAWN_SPREAD, SPAWN_SPREAD)
	start.y = 0.0
	p.state = State.ARRIVING
	p.access = LANDSIDE
	p.crowd_id = crowd.add(start, PassengerCrowdScript.yaw_towards(-out)) if crowd != null else -1
	var arrived: int = _arrived_count.get(p.flight.id, 0) + 1
	_arrived_count[p.flight.id] = arrived
	if arrived == 1:
		print("PASSENGERS | %s first passenger for %s (departs %s)" % [GameClock.get_time_string(), p.flight.flight_number,
			p.flight.get_time_string()])
	if p.crowd_id < 0:
		_arrive(p)
		return
	walk(p, _wait_spot(e), _arrive)


## A random landside floor tile a few tiles inside the entrance, as a world point.
func _wait_spot(e: Dictionary) -> Vector3:
	var centre: Vector2i = e.inside - e.outward * WAIT_INSIDE
	var options: Array[Vector2i] = []
	for dy in range(-WAIT_RADIUS, WAIT_RADIUS + 1):
		for dx in range(-WAIT_RADIUS, WAIT_RADIUS + 1):
			var tile := centre + Vector2i(dx, dy)
			if terminal_floor.has_floor(tile, floor_index) and _landside_floor(tile) \
					and (terminal_paths == null or terminal_paths.is_walkable(tile, LANDSIDE)):
				options.append(tile)
	var tile: Vector2i = e.inside if options.is_empty() else options[_rng.randi() % options.size()]
	var jitter := Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))
	return BuildGrid.tile_to_world(tile, floor_index) + jitter


## Moves a walking passenger by step metres. False once they have arrived.
func _walk(p: PassengerScript, step: float) -> bool:
	var pos := crowd.get_passenger_position(p.crowd_id)
	while step > 0.0 and p.path_next < p.path.size():
		var goal := p.path[p.path_next]
		var to := goal - pos
		var dist := to.length()
		if dist <= step:
			pos = goal
			step -= dist
			p.path_next += 1
		else:
			pos += to / dist * step
			step = 0.0
		if dist > 0.001:
			crowd.set_pose(p.crowd_id, pos, PassengerCrowdScript.yaw_towards(to))
	if p.entered_time < 0 and terminal_floor.has_floor(BuildGrid.world_to_tile(pos), floor_index):
		p.entered_time = GameClock.game_time
	return p.path_next < p.path.size()


## A walk ended: stop the walk animation and tell whoever sent them.
func _finish_walk(p: PassengerScript) -> void:
	p.is_walking = false
	if p.crowd_id >= 0:
		crowd.set_walking(p.crowd_id, false)
	var done := p.on_arrive
	p.on_arrive = Callable()
	if done.is_valid():
		done.call(p)


func _arrive(p: PassengerScript) -> void:
	p.state = State.AT_ENTRANCE
	if p.entered_time < 0:
		p.entered_time = GameClock.game_time
	passenger_arrived.emit(p)
	if p.flight.passengers.all(func(q: PassengerScript) -> bool:
			return q.state != State.EXPECTED and q.state != State.ARRIVING):
		print("PASSENGERS | %s all %d passengers for %s are in (departs %s)" % [GameClock.get_time_string(),
			p.flight.passengers.size(), p.flight.flight_number, p.flight.get_time_string()])


## Drops passengers of flights the schedule no longer keeps (they and their
## flight reference each other, so they would never be freed otherwise).
func _on_day_passed(_datetime: Dictionary) -> void:
	var oldest := FlightSchedule.get_today_start() - FlightSchedule.DAY
	for p: PassengerScript in _passengers.values():
		if p.flight.scheduled_time < oldest:
			remove_passenger(p)
	for flight_id: int in _arrived_count.keys():
		if FlightSchedule.get_flight(flight_id) == null:
			_arrived_count.erase(flight_id)


func _on_paths_changed() -> void:
	for p in _walking:
		if p.walk_direct:
			continue
		var path := terminal_paths.find_path(crowd.get_passenger_position(p.crowd_id), p.target, p.access, true)
		if path.size() >= 2:
			p.path = path
			p.path_next = 1


# --- Entrances --------------------------------------------------------------------

func _update_entrances() -> void:
	if not _entrances_dirty:
		return
	_entrances_dirty = false
	_entrances.clear()
	if terminal_floor == null or terminal_walls == null:
		return
	var bounds: Rect2i = terminal_floor.get_floor_bounds(floor_index)
	if not bounds.has_area():
		return
	for y in range(bounds.position.y, bounds.end.y + 1):
		for x in range(bounds.position.x, bounds.end.x + 1):
			var corner := Vector2i(x, y)
			_check_door(corner, true)
			_check_door(corner, false)


## Adds the edge as an entrance if it is a door with landside floor on exactly one side.
func _check_door(corner: Vector2i, horizontal: bool) -> void:
	if terminal_walls.get_edge(corner, horizontal, floor_index) != Piece.DOOR:
		return
	var minus := corner - (Vector2i(0, 1) if horizontal else Vector2i(1, 0))
	var plus_floor: bool = terminal_floor.has_floor(corner, floor_index)
	var minus_floor: bool = terminal_floor.has_floor(minus, floor_index)
	if plus_floor == minus_floor:
		return
	var inside := corner if plus_floor else minus
	var outside := minus if plus_floor else corner
	if not _landside_floor(inside):
		return
	_entrances.append({"inside": inside, "outside": outside, "outward": outside - inside})


func _landside_floor(tile: Vector2i) -> bool:
	var zone: int = terminal_zones.get_zone(tile, floor_index) if terminal_zones != null else Zone.NONE
	return zone == Zone.NONE or zone == Zone.LANDSIDE


func _clock(time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(time)
	return "%02d:%02d" % [dt.hour, dt.minute]
