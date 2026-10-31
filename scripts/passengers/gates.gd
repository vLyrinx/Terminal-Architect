extends Node
## Gate waiting and boarding (checklist step 32).
##
## A gate is a gate desk on airside floor. Each departure uses the gate desk
## nearest its stand (or, with no stand, the gate with the fewest flights).
## Seat rows within SEAT_RADIUS of a gate desk (each seat belongs to the
## nearest gate) are that gate's seats.
##
## Passengers coming out of security walk to their flight's gate and sit on
## a free seat there, or stand near the desk when every seat is taken.
## Boarding opens open_before seconds before departure (once the aircraft is
## on its stand, or at departure time if it never parks there). Waiting
## passengers are called in groups of CALL_GROUP every CALL_INTERVAL; they
## get up, walk to the desk and are scanned one every SCAN_TIME. Then they go
## out through the gate's door to the apron (the airside door nearest the
## desk by walking distance) and across to the front door of the aircraft on
## the flight's stand, where they board and are counted on board. A gate with
## no door out boards passengers at the desk. Boarding closes
## close_before seconds before departure (open at least MIN_OPEN), and is
## finished once it has closed and everyone called has reached the aircraft, or as soon as
## every passenger of the flight is on board. AirTraffic keeps the aircraft
## on stand until then (is_boarding_finished()).
##
## Passengers not on board when boarding finishes miss the flight
## (MissedFlights, step 34).

const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")
const SecurityScript := preload("res://scripts/passengers/security.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const State := PassengerScript.State
const Zone := TerminalZonesScript.Zone
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE

const GATE_ID := &"gate_desk"
const SEAT_ROW_ID := &"seat_row"
## Where boarding passengers step up to the desk, in its local X/Z (its front faces +Z).
const BOARD_LOCAL := Vector2(0.45, 1.0)
## Seats of a seat row in its local X/Z: x of each seat, the seat itself and the spot in front of it.
const SEAT_XS: Array[float] = [-1.5, -0.5, 0.5, 1.5]
const SEAT_Z := 0.05
const SEAT_APPROACH_Z := 0.95
## How far a seated passenger is lowered so they sit on the seat.
const SIT_DROP := 0.3
## Seats this close to a gate desk (metres) belong to it.
const SEAT_RADIUS := 16.0
## Without a free seat passengers stand on airside floor within this many tiles of the desk.
const STAND_RADIUS := 4
## Boarding calls: how many passengers, and game seconds between calls.
const CALL_GROUP := 10
const CALL_INTERVAL := 45
## Game seconds to scan one boarding pass.
const SCAN_TIME := 4
## Boarding stays open at least this long, in game seconds.
const MIN_OPEN := 900
## Gate doors out to the apron count for a gate desk up to this far away (metres).
const EXIT_RANGE := 60.0
## Where passengers walk to beside a parked aircraft: this far ahead of the
## nose wheel (the stop bar) and this far out to its left, by the front door.
const DOOR_AHEAD := 2.0
const DOOR_SIDE := 3.5
## With no stand, passengers walk this far out from the gate door before boarding.
const APRON_WALK := 10.0
## Passengers step this far outside the door before crossing the apron.
const DOOR_STEP := 1.5

## Game seconds before departure that boarding opens and closes.
@export var open_before := 40 * 60
@export var close_before := 10 * 60

signal boarding_opened(flight: FlightScript)
signal boarding_finished(flight: FlightScript)
signal passenger_boarded(passenger: PassengerScript)


class GateSeat:
	extends RefCounted
	var object_id := 0
	var index := 0
	var gate_id := 0
	## The seat, the spot in front of it, and the way a seated passenger faces.
	var pos := Vector3.ZERO
	var approach := Vector3.ZERO
	var facing := Vector3.ZERO
	var taken: PassengerScript


class Gate:
	extends RefCounted
	var id := 0
	## Where boarding passengers step up to the desk, and the way they face.
	var board_point := Vector3.ZERO
	var facing := Vector3.ZERO
	var seats: Array[GateSeat] = []
	## Airside floor tiles near the desk for passengers without a seat.
	var stand_tiles: Array[Vector2i] = []
	## Passengers at the desk waiting to be scanned, in order.
	var scan_queue: Array[PassengerScript] = []
	var next_scan := 0
	## The door out to the apron that boarded passengers use: a point just
	## inside it, one just outside it, and the way out.
	var has_exit := false
	var exit_inside := Vector3.ZERO
	var exit_outside := Vector3.ZERO
	var exit_out := Vector3.ZERO


class Boarding:
	extends RefCounted
	var flight: FlightScript
	var gate_id := 0
	var open := false
	var finished := false
	var opened_at := -1
	var closes_at := -1
	var finished_at := -1
	var next_call := 0
	var boarded := 0


@export var placed_objects: Node3D
@export var terminal_floor: Node3D
@export var terminal_walls: Node3D
@export var terminal_zones: Node3D
@export var terminal_paths: TerminalPathsScript
@export var spawner: PassengerSpawnerScript
@export var security: SecurityScript
## Stands node (optional): flights use the gate nearest their stand.
@export var stands: Node3D
## Arrivals node (optional, step 33): boarding waits until the arriving passengers are off.
@export var arrivals: Node
@export var floor_index := 0

## Gate desk id -> Gate.
var _gates := {}
var _gates_dirty := true
## Flight id -> Boarding.
var _boardings := {}
## Flight id -> gate desk id.
var _flight_gate := {}
## Airside passengers whose flight has no gate yet.
var _waiting: Array[PassengerScript] = []
var _no_gate_warned := {}
var _no_exit_warned := {}
## Doors between airside floor and the apron (worked out with the gates).
var _exits: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if placed_objects != null:
		placed_objects.object_added.connect(func(_id: int) -> void: _gates_dirty = true)
		placed_objects.object_removed.connect(func(_id: int) -> void: _gates_dirty = true)
		placed_objects.object_moved.connect(func(_id: int) -> void: _gates_dirty = true)
	if terminal_paths != null:
		terminal_paths.paths_changed.connect(func() -> void: _gates_dirty = true)
	if security != null:
		security.passenger_cleared.connect(_go_to_gate)
	GameClock.ticked.connect(_on_ticked)
	GameClock.day_passed.connect(_on_day_passed)


func set_seed(value: int) -> void:
	_rng.seed = value


# --- Queries ----------------------------------------------------------------------

## True once a departure may leave: its boarding has finished, it has no
## passengers, or there is no gate for anyone to board at.
func is_boarding_finished(flight: FlightScript) -> bool:
	if flight.passengers.is_empty():
		return true
	_update_gates()
	if _gates.is_empty():
		if not _no_gate_warned.has(flight.id):
			_no_gate_warned[flight.id] = true
			print("BOARDING | No gate desk on airside: %s leaves without its passengers" % flight.flight_number)
		return true
	var b: Boarding = _boardings.get(flight.id)
	return b != null and b.finished


func get_boarding(flight: FlightScript) -> Boarding:
	return _boardings.get(flight.id)


func get_gates() -> Array:
	_update_gates()
	return _gates.values()


func get_gate(id: int) -> Gate:
	_update_gates()
	return _gates.get(id)


## The gate desk a departure uses, or null if there is none.
func get_gate_for(flight: FlightScript) -> Gate:
	_update_gates()
	var id: int = _flight_gate.get(flight.id, 0)
	if _gates.has(id):
		return _gates[id]
	var gate := _pick_gate(flight)
	if gate != null:
		_flight_gate[flight.id] = gate.id
	return gate


## Takes a passenger away from the gates (their seat, the desk queue or the
## list of those still looking for a gate).
func drop(p: PassengerScript) -> void:
	_free_seat(p)
	_waiting.erase(p)
	var gate: Gate = _gates.get(p.gate_id)
	if gate != null:
		gate.scan_queue.erase(p)


# --- Going to the gate ------------------------------------------------------------

func _go_to_gate(p: PassengerScript) -> void:
	_free_seat(p)
	var gate := get_gate_for(p.flight)
	if gate == null:
		p.state = State.AIRSIDE
		p.gate_id = 0
		if not _waiting.has(p):
			_waiting.append(p)
		return
	_waiting.erase(p)
	p.gate_id = gate.id
	p.state = State.TO_GATE
	var free := gate.seats.filter(func(s: GateSeat) -> bool: return s.taken == null)
	if not free.is_empty():
		var seat: GateSeat = free[_rng.randi() % free.size()]
		seat.taken = p
		p.seat = seat
		spawner.walk(p, seat.approach, _on_seat_approach)
	else:
		spawner.walk(p, _stand_spot(gate), _on_stand_spot)


func _on_seat_approach(p: PassengerScript) -> void:
	var seat: GateSeat = p.seat
	if p.state != State.TO_GATE or seat == null:
		return
	spawner.walk(p, seat.pos, _sit, true)


func _sit(p: PassengerScript) -> void:
	var seat: GateSeat = p.seat
	if p.state != State.TO_GATE or seat == null:
		return
	p.state = State.AT_GATE
	p.seated = true
	spawner.crowd.set_pose(p.crowd_id, seat.pos - Vector3(0.0, SIT_DROP, 0.0),
		PassengerCrowdScript.yaw_towards(seat.facing))


func _on_stand_spot(p: PassengerScript) -> void:
	if p.state != State.TO_GATE:
		return
	p.state = State.AT_GATE
	var gate: Gate = _gates.get(p.gate_id)
	if gate != null:
		spawner.face(p, gate.board_point - spawner.crowd.get_passenger_position(p.crowd_id))


func _stand_spot(gate: Gate) -> Vector3:
	if gate.stand_tiles.is_empty():
		return gate.board_point
	var tile := gate.stand_tiles[_rng.randi() % gate.stand_tiles.size()]
	return BuildGrid.tile_to_world(tile, floor_index) + Vector3(_rng.randf_range(-0.35, 0.35), 0.0,
		_rng.randf_range(-0.35, 0.35))


## Gets a passenger off their seat (standing them up if they sat down).
func _free_seat(p: PassengerScript) -> void:
	var seat: GateSeat = p.seat
	if seat != null and seat.taken == p:
		seat.taken = null
	p.seat = null
	if p.seated:
		p.seated = false
		if p.crowd_id >= 0:
			var pos := spawner.crowd.get_passenger_position(p.crowd_id) + Vector3(0.0, SIT_DROP, 0.0)
			spawner.crowd.set_pose(p.crowd_id, pos, PassengerCrowdScript.yaw_towards(seat.facing if seat else Vector3.FORWARD))


# --- Boarding ---------------------------------------------------------------------

func _on_ticked(_game_seconds: float) -> void:
	_update_gates()
	var now := GameClock.game_time
	if not _waiting.is_empty():
		for p in _waiting.duplicate():
			_go_to_gate(p)
	for f: FlightScript in FlightSchedule.get_all_flights():
		if f.scheduled_time - open_before > now:
			break
		if f.is_arrival() or f.passengers.is_empty():
			continue
		var b: Boarding = _boardings.get(f.id)
		if b == null:
			b = Boarding.new()
			b.flight = f
			_boardings[f.id] = b
		if b.finished:
			continue
		if not b.open:
			_try_open(b, now)
		if b.open:
			_run_boarding(b, now)
	for gate: Gate in _gates.values():
		if not gate.scan_queue.is_empty() and now >= gate.next_scan:
			_scanned(gate.scan_queue.pop_front())
			gate.next_scan = now + SCAN_TIME


func _try_open(b: Boarding, now: int) -> void:
	var f := b.flight
	if f.status != FlightScript.Status.SCHEDULED:
		return
	# Wait for the aircraft to park on its stand (unless it is already departure time).
	if now < f.scheduled_time and f.stand_id >= 0 and f.pair != null \
			and f.pair.status != FlightScript.Status.ON_STAND:
		return
	# And for the arriving passengers to get off first (step 33).
	if arrivals != null and f.pair != null and not arrivals.is_deplaned(f.pair):
		return
	var gate := get_gate_for(f)
	if gate == null:
		return
	b.open = true
	b.gate_id = gate.id
	b.opened_at = now
	b.closes_at = maxi(f.scheduled_time - close_before, now + MIN_OPEN)
	b.next_call = now
	f.status = FlightScript.Status.BOARDING
	print("BOARDING | %s %s boarding at gate %d, closes %s" % [GameClock.get_time_string(), f.flight_number, gate.id,
		_clock(b.closes_at)])
	boarding_opened.emit(f)


func _run_boarding(b: Boarding, now: int) -> void:
	var f := b.flight
	var gate := get_gate_for(f)
	if gate != null:
		b.gate_id = gate.id
	if gate != null and now < b.closes_at and now >= b.next_call:
		b.next_call = now + CALL_INTERVAL
		var called := 0
		for p: PassengerScript in f.passengers:
			if called >= CALL_GROUP:
				break
			if p.state == State.AT_GATE and p.gate_id == gate.id:
				_call(p, gate)
				called += 1
	var all_on := true
	var any_boarding := false
	for p: PassengerScript in f.passengers:
		if p.state != State.BOARDED:
			all_on = false
		if p.state == State.BOARDING or p.state == State.TO_AIRCRAFT:
			any_boarding = true
	if all_on or (now >= b.closes_at and not any_boarding):
		b.finished = true
		b.finished_at = now
		print("BOARDING | %s %s boarding finished: %d of %d on board" % [GameClock.get_time_string(), f.flight_number,
			b.boarded, f.passengers.size()])
		boarding_finished.emit(f)


func _call(p: PassengerScript, gate: Gate) -> void:
	_free_seat(p)
	p.state = State.BOARDING
	p.called_time = GameClock.game_time
	var side := Vector3(-gate.facing.z, 0.0, gate.facing.x)
	var spot := gate.board_point + side * _rng.randf_range(-0.5, 0.5) - gate.facing * _rng.randf_range(0.0, 0.6)
	spawner.walk(p, spot, _on_at_desk)


func _on_at_desk(p: PassengerScript) -> void:
	if p.state != State.BOARDING:
		return
	var gate: Gate = _gates.get(p.gate_id)
	if gate == null:
		_go_to_gate(p)
		return
	spawner.face(p, gate.facing)
	gate.scan_queue.append(p)


## Boarding pass scanned: out through the gate's door and across the apron
## to the aircraft door (or straight on board if the gate has no door out).
func _scanned(p: PassengerScript) -> void:
	if p.state != State.BOARDING:
		return
	var gate: Gate = _gates.get(p.gate_id)
	if gate == null or not gate.has_exit:
		if gate != null and not _no_exit_warned.has(gate.id):
			_no_exit_warned[gate.id] = true
			print("BOARDING | Gate %d has no door out to the apron: passengers board at the desk" % gate.id)
		_board(p)
		return
	p.state = State.TO_AIRCRAFT
	var outside := gate.exit_outside
	var door := _aircraft_door(p.flight, gate)
	var side := Vector3(-gate.exit_out.z, 0.0, gate.exit_out.x)
	outside += side * _rng.randf_range(-0.25, 0.25)
	spawner.walk(p, gate.exit_inside, func(q: PassengerScript) -> void:
		spawner.walk(q, outside, func(r: PassengerScript) -> void:
			spawner.walk(r, door, _board, true), true))


## The spot on the ground beside the front door (on the left) of an aircraft
## parked on a stand, or Vector3.INF if there is no such stand.
func get_aircraft_door_at(stand_id: int) -> Vector3:
	if stands == null or stand_id < 0:
		return Vector3.INF
	var stand = stands.get_stand(stand_id)
	if stand == null:
		return Vector3.INF
	var nose: Vector3 = stand.get_nose_direction()
	var left := Vector3(nose.z, 0.0, -nose.x)
	var door: Vector3 = stand.stop + nose * DOOR_AHEAD + left * DOOR_SIDE
	door.y = 0.0
	return door


## Doors between airside floor and the apron, as {inside, outside} tiles.
func get_apron_doors() -> Array[Dictionary]:
	_update_gates()
	return _exits


## Where passengers walk to on the apron: beside the front door on the left
## of the aircraft parked on the flight's stand, or (with no stand) a little
## way out from the gate's door.
func _aircraft_door(f: FlightScript, gate: Gate) -> Vector3:
	var jitter := Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
	var door := get_aircraft_door_at(f.stand_id)
	if door.is_finite():
		return door + jitter
	var spot := gate.exit_outside + gate.exit_out * APRON_WALK + jitter
	spot.y = 0.0
	return spot


func _board(p: PassengerScript) -> void:
	if p.state != State.BOARDING and p.state != State.TO_AIRCRAFT:
		return
	p.state = State.BOARDED
	p.boarded_time = GameClock.game_time
	if p.crowd_id >= 0:
		spawner.crowd.remove(p.crowd_id)
		p.crowd_id = -1
	var b: Boarding = _boardings.get(p.flight.id)
	if b != null:
		b.boarded += 1
	passenger_boarded.emit(p)


# --- Gates and seats --------------------------------------------------------------

func _pick_gate(flight: FlightScript) -> Gate:
	if _gates.is_empty():
		return null
	if stands != null and flight.stand_id >= 0:
		var stand = stands.get_stand(flight.stand_id)
		if stand != null:
			var best: Gate = null
			var best_dist := INF
			for gate: Gate in _gates.values():
				var d := gate.board_point.distance_squared_to(stand.stop)
				if d < best_dist:
					best_dist = d
					best = gate
			return best
	# No stand: the gate with the fewest upcoming flights.
	var load := {}
	var now := GameClock.game_time
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and f.scheduled_time >= now and _gates.has(_flight_gate.get(f.id, 0)):
			load[_flight_gate[f.id]] = load.get(_flight_gate[f.id], 0) + 1
	var ids := _gates.keys()
	ids.sort()
	var pick: int = ids[0]
	for id: int in ids:
		if load.get(id, 0) < load.get(pick, 0):
			pick = id
	return _gates[pick]


func _update_gates() -> void:
	if not _gates_dirty or placed_objects == null:
		return
	_gates_dirty = false
	var old := _gates
	var old_seats := {}
	for gate: Gate in old.values():
		for seat in gate.seats:
			if seat.taken != null:
				old_seats["%d:%d" % [seat.object_id, seat.index]] = seat
	_gates = {}
	for id: int in placed_objects.get_ids():
		var obj = placed_objects.get_object(id)
		if obj.def_id != GATE_ID or obj.floor_index != floor_index:
			continue
		var forward := _rotate_local(Vector2(0.0, 1.0), obj.rotation)
		var board: Vector3 = obj.position + _rotate_local(BOARD_LOCAL, obj.rotation)
		var tile := BuildGrid.world_to_tile(board)
		if not _airside_tile(tile):
			continue
		var gate: Gate = old.get(id, Gate.new())
		gate.id = id
		board.y = terminal_floor.get_surface_height(tile, floor_index)
		gate.board_point = board
		gate.facing = -forward
		gate.seats.clear()
		_gates[id] = gate
	var seat_tiles := {}
	for id: int in placed_objects.get_ids():
		var obj = placed_objects.get_object(id)
		if obj.def_id != SEAT_ROW_ID or obj.floor_index != floor_index:
			continue
		for t in obj.tiles:
			seat_tiles[t] = true
		for i in SEAT_XS.size():
			var pos: Vector3 = obj.position + _rotate_local(Vector2(SEAT_XS[i], SEAT_Z), obj.rotation)
			var approach: Vector3 = obj.position + _rotate_local(Vector2(SEAT_XS[i], SEAT_APPROACH_Z), obj.rotation)
			if not _airside_tile(BuildGrid.world_to_tile(approach)):
				continue
			var gate := _nearest_gate(pos)
			if gate == null:
				continue
			var seat := GateSeat.new()
			seat.object_id = id
			seat.index = i
			seat.gate_id = gate.id
			seat.pos = pos
			seat.approach = approach
			seat.approach.y = terminal_floor.get_surface_height(BuildGrid.world_to_tile(approach), floor_index)
			seat.facing = _rotate_local(Vector2(0.0, 1.0), obj.rotation)
			var was: GateSeat = old_seats.get("%d:%d" % [id, i])
			if was != null and was.gate_id == gate.id and was.pos.is_equal_approx(pos):
				seat.taken = was.taken
				seat.taken.seat = seat
				old_seats.erase("%d:%d" % [id, i])
			gate.seats.append(seat)
	_exits = _apron_doors()
	for gate: Gate in _gates.values():
		gate.stand_tiles = _stand_tiles(gate, seat_tiles)
		_pick_exit(gate, _exits)
	# Anyone whose gate or seat went away finds their place again.
	var lost: Array[PassengerScript] = []
	for seat: GateSeat in old_seats.values():
		if seat.taken != null and seat.taken.seat == seat:
			lost.append(seat.taken)
	for gate: Gate in old.values():
		if not _gates.has(gate.id):
			for p in gate.scan_queue:
				if not lost.has(p):
					lost.append(p)
	for p: PassengerScript in spawner.get_all_passengers():
		if (p.state == State.TO_GATE or p.state == State.AT_GATE) and not _gates.has(p.gate_id) and not lost.has(p):
			lost.append(p)
	for p in lost:
		if p.state == State.BOARDING:
			var gate := get_gate_for(p.flight)
			if gate != null:
				p.gate_id = gate.id
				_call(p, gate)
				continue
		_go_to_gate(p)


## Doors between airside floor and the outside, as {inside, outside} tiles.
func _apron_doors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if terminal_walls == null:
		return out
	var bounds: Rect2i = terminal_floor.get_floor_bounds(floor_index)
	if not bounds.has_area():
		return out
	for y in range(bounds.position.y, bounds.end.y + 1):
		for x in range(bounds.position.x, bounds.end.x + 1):
			for horizontal: bool in [true, false]:
				var corner := Vector2i(x, y)
				if terminal_walls.get_edge(corner, horizontal, floor_index) != TerminalWallsScript.Piece.DOOR:
					continue
				var minus := corner - (Vector2i(0, 1) if horizontal else Vector2i(1, 0))
				var plus_floor: bool = terminal_floor.has_floor(corner, floor_index)
				if plus_floor == terminal_floor.has_floor(minus, floor_index):
					continue
				var inside := corner if plus_floor else minus
				if _airside_tile(inside):
					out.append({"inside": inside, "outside": minus if plus_floor else corner})
	return out


## The gate's way out to the apron: the door with the shortest walk from the desk.
func _pick_exit(gate: Gate, exits: Array[Dictionary]) -> void:
	gate.has_exit = false
	var best := EXIT_RANGE
	for e in exits:
		var inside := BuildGrid.tile_to_world(e.inside, floor_index)
		if inside.distance_to(gate.board_point) > best:
			continue
		var path := terminal_paths.find_path(gate.board_point, inside, AIRSIDE)
		if path.is_empty():
			continue
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if length < best:
			best = length
			var out := Vector3(e.outside.x - e.inside.x, 0.0, e.outside.y - e.inside.y)
			gate.has_exit = true
			gate.exit_inside = inside
			gate.exit_out = out
			gate.exit_outside = inside + out * (0.5 + DOOR_STEP)
			gate.exit_outside.y = 0.0


func _nearest_gate(pos: Vector3) -> Gate:
	var best: Gate = null
	var best_dist := SEAT_RADIUS * SEAT_RADIUS
	for gate: Gate in _gates.values():
		var d := gate.board_point.distance_squared_to(pos)
		if d <= best_dist:
			best_dist = d
			best = gate
	return best


func _stand_tiles(gate: Gate, seat_tiles: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var centre := BuildGrid.world_to_tile(gate.board_point - gate.facing * 2.0)
	for dy in range(-STAND_RADIUS, STAND_RADIUS + 1):
		for dx in range(-STAND_RADIUS, STAND_RADIUS + 1):
			var tile := centre + Vector2i(dx, dy)
			if _airside_tile(tile) and not seat_tiles.has(tile) \
					and tile != BuildGrid.world_to_tile(gate.board_point):
				out.append(tile)
	return out


## Airside zone floor that airside people may stand on.
func _airside_tile(tile: Vector2i) -> bool:
	if not terminal_floor.has_floor(tile, floor_index):
		return false
	if terminal_zones != null and terminal_zones.get_zone(tile, floor_index) != Zone.AIRSIDE:
		return false
	return terminal_paths == null or terminal_paths.is_walkable(tile, AIRSIDE)


func _on_day_passed(_datetime: Dictionary) -> void:
	for id: int in _boardings.keys():
		if FlightSchedule.get_flight(id) == null:
			_boardings.erase(id)
			_flight_gate.erase(id)
			_no_gate_warned.erase(id)
	for gate: Gate in _gates.values():
		for seat in gate.seats:
			if seat.taken != null and spawner.get_passenger(seat.taken.id) == null:
				seat.taken = null


## A local X/Z offset turned to world space by a rotation around Y (as PlacedObjects does).
static func _rotate_local(offset: Vector2, yaw: float) -> Vector3:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector3(offset.x * c + offset.y * s, 0.0, -offset.x * s + offset.y * c)


static func _clock(time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(time)
	return "%02d:%02d" % [dt.hour, dt.minute]
