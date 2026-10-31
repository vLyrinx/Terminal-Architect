extends Node
## Security queues (checklist step 31).
##
## Every security scanner whose front (the bag in-feed, local +Z) opens onto
## landside or security floor and whose back opens onto floor airside people
## may use has a queue: a line of standing spots straight out from its front,
## like a check-in queue. Passengers who have checked in pick the scanner with
## the best mix of short queue and short walk, queue, are screened at the
## front for a processing time, then walk through the arch and out of the
## back. From there they are airside: they walk on into the airside zone and
## wait for their gate (step 32). With no scanner (or every queue full) they
## wait where check-in sent them until there is room.

const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const CheckInScript := preload("res://scripts/passengers/check_in.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const State := PassengerScript.State
const Zone := TerminalZonesScript.Zone
const Piece := TerminalWallsScript.Piece
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE

const SCANNER_ID := &"security_scanner"
## In the scanner's local X/Z: where the passenger being screened stands (in
## front of the arch), the middle of the arch, and the spot just behind it.
const SERVICE_LOCAL := Vector2(0.5, 2.4)
const ARCH_LOCAL := Vector2(0.5, 0.0)
const EXIT_LOCAL := Vector2(0.5, -2.5)
## Gap between people in a queue, in metres.
const QUEUE_SPACING := 0.75
const MAX_QUEUE := 30
## Game seconds screening takes (random in this range).
const PROCESS_MIN := 45
const PROCESS_MAX := 90
## When picking a scanner, one more person in the queue counts as this many metres of extra walking.
const METRES_PER_PERSON := 12.0
## After security passengers wait on airside floor within this many tiles of a spot this far past the exit.
const AFTER_AHEAD := 4
const AFTER_RADIUS := 3
const WARN_INTERVAL := 3600

## A passenger came out of a scanner into airside.
signal passenger_cleared(passenger: PassengerScript)


class Scanner:
	extends RefCounted
	var id := 0
	## Where the passenger being screened stands, the way they face, the arch and the exit.
	var service := Vector3.ZERO
	var facing := Vector3.ZERO
	var arch := Vector3.ZERO
	var exit := Vector3.ZERO
	## Standing spots from the front of the queue (index 0, at the scanner) to the back.
	var spots := PackedVector3Array()
	## Everyone queuing or walking to the queue, front first.
	var queue: Array[PassengerScript] = []
	var serving: PassengerScript
	var done_time := 0
	var served := 0
	## Tiles past the exit where people wait once airside (worked out when first needed).
	var after_tiles: Array[Vector2i] = []
	var after_ready := false


@export var placed_objects: Node3D
@export var terminal_floor: Node3D
@export var terminal_walls: Node3D
@export var terminal_zones: Node3D
@export var terminal_paths: TerminalPathsScript
@export var spawner: PassengerSpawnerScript
@export var check_in: CheckInScript
@export var floor_index := 0

## Placed object id -> Scanner.
var _scanners := {}
var _scanners_dirty := true
## Checked-in passengers waiting for a scanner with room.
var _waiting: Array[PassengerScript] = []
var _last_warning := -WARN_INTERVAL
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if placed_objects != null:
		placed_objects.object_added.connect(func(_id: int) -> void: _scanners_dirty = true)
		placed_objects.object_removed.connect(func(_id: int) -> void: _scanners_dirty = true)
		placed_objects.object_moved.connect(func(_id: int) -> void: _scanners_dirty = true)
	if terminal_paths != null:
		terminal_paths.paths_changed.connect(func() -> void: _scanners_dirty = true)
	if check_in != null:
		check_in.passenger_checked_in.connect(_assign)
	GameClock.ticked.connect(_on_ticked)


func set_seed(value: int) -> void:
	_rng.seed = value


# --- Queries ----------------------------------------------------------------------

## Scanners in use, as Scanner records.
func get_scanners() -> Array:
	_update_scanners()
	return _scanners.values()


func get_scanner(id: int) -> Scanner:
	_update_scanners()
	return _scanners.get(id)


func get_waiting_count() -> int:
	return _waiting.size()


# --- Passengers -------------------------------------------------------------------

## Sends a checked-in passenger to the scanner with the best mix of short queue and short walk.
func _assign(p: PassengerScript) -> void:
	_update_scanners()
	p.scanner_id = 0
	var pos: Vector3 = spawner.crowd.get_passenger_position(p.crowd_id)
	var best: Scanner = null
	var best_score := INF
	for s: Scanner in _scanners.values():
		if s.queue.size() >= s.spots.size():
			continue
		var score := s.queue.size() + pos.distance_to(s.service) / METRES_PER_PERSON + _rng.randf() * 0.5
		if score < best_score:
			best_score = score
			best = s
	if best == null:
		# They keep walking to (or standing at) the spot check-in sent them to.
		p.state = State.CHECKED_IN
		if not _waiting.has(p):
			_waiting.append(p)
		return
	_waiting.erase(p)
	best.queue.append(p)
	p.scanner_id = best.id
	p.state = State.TO_SECURITY
	spawner.walk(p, best.spots[best.queue.size() - 1], _on_reached_spot)


## Takes a passenger out of security (their scanner's queue or the waiting
## list); the people behind them step up.
func drop(p: PassengerScript) -> void:
	_waiting.erase(p)
	var s: Scanner = _scanners.get(p.scanner_id)
	if s == null or not s.queue.has(p):
		return
	if s.serving == p:
		s.serving = null
	s.queue.erase(p)
	_advance(s)


func _on_reached_spot(p: PassengerScript) -> void:
	var s: Scanner = _scanners.get(p.scanner_id)
	if s == null or not s.queue.has(p):
		return
	if p.state != State.SCREENING:
		p.state = State.QUEUING_SECURITY
	spawner.face(p, s.facing)


func _on_ticked(_game_seconds: float) -> void:
	_update_scanners()
	var now := GameClock.game_time
	for s: Scanner in _scanners.values():
		if s.serving != null and now >= s.done_time:
			_pass_through(s)
		if s.serving == null and not s.queue.is_empty():
			var p := s.queue[0]
			# Screening starts as the front passenger steps up from the next spot.
			if p.state == State.QUEUING_SECURITY and (not p.is_walking or spawner.crowd.get_passenger_position(
					p.crowd_id).distance_to(s.spots[0]) <= QUEUE_SPACING * 1.1):
				s.serving = p
				s.done_time = now + _rng.randi_range(PROCESS_MIN, PROCESS_MAX)
				p.state = State.SCREENING
	if not _waiting.is_empty():
		for p in _waiting.duplicate():
			_assign(p)
		if not _waiting.is_empty() and now - _last_warning >= WARN_INTERVAL:
			_last_warning = now
			print("SECURITY | %s %d passengers waiting: %s" % [GameClock.get_time_string(), _waiting.size(),
				"no usable security scanner" if _scanners.is_empty() else "every queue is full"])


## Screening done: the passenger walks through the arch and out of the back,
## and the next in the queue steps up.
func _pass_through(s: Scanner) -> void:
	var p := s.serving
	s.serving = null
	s.queue.erase(p)
	s.served += 1
	var exit := s.exit
	var after := _after_spot(s)
	spawner.walk(p, s.arch, func(q: PassengerScript) -> void:
		spawner.walk(q, exit, func(r: PassengerScript) -> void: _cleared(r, after), true), true)
	_advance(s)


func _cleared(p: PassengerScript, after: Vector3) -> void:
	p.access = AIRSIDE
	p.state = State.AIRSIDE
	p.cleared_time = GameClock.game_time
	spawner.walk(p, after)
	passenger_cleared.emit(p)


## Everyone in the queue walks to their spot (straight ahead when just stepping up).
func _advance(s: Scanner, direct := true) -> void:
	for i in s.queue.size():
		var q := s.queue[i]
		if q.state == State.QUEUING_SECURITY:
			spawner.walk(q, s.spots[i], _on_reached_spot, direct)
		elif q.state == State.TO_SECURITY:
			spawner.walk(q, s.spots[i], _on_reached_spot)


## A random airside floor tile a little way past the scanner's exit (airside
## zone if there is some nearby, else any floor airside people may use).
func _after_spot(s: Scanner) -> Vector3:
	if not s.after_ready:
		s.after_tiles = _after_tiles(s)
		s.after_ready = true
	if s.after_tiles.is_empty():
		return s.exit
	var tile := s.after_tiles[_rng.randi() % s.after_tiles.size()]
	return BuildGrid.tile_to_world(tile, floor_index) + Vector3(_rng.randf_range(-0.35, 0.35), 0.0,
		_rng.randf_range(-0.35, 0.35))


func _after_tiles(s: Scanner) -> Array[Vector2i]:
	var out := (s.exit - s.arch).normalized()
	var centre := BuildGrid.world_to_tile(s.exit + out * AFTER_AHEAD)
	var airside: Array[Vector2i] = []
	var other: Array[Vector2i] = []
	for dy in range(-AFTER_RADIUS, AFTER_RADIUS + 1):
		for dx in range(-AFTER_RADIUS, AFTER_RADIUS + 1):
			var tile := centre + Vector2i(dx, dy)
			if not terminal_floor.has_floor(tile, floor_index) or not terminal_paths.is_walkable(tile, AIRSIDE):
				continue
			if terminal_paths.find_path(s.exit, BuildGrid.tile_to_world(tile, floor_index), AIRSIDE).is_empty():
				continue
			if terminal_zones.get_zone(tile, floor_index) == Zone.AIRSIDE:
				airside.append(tile)
			else:
				other.append(tile)
	return airside if not airside.is_empty() else other


# --- Scanners and queues ----------------------------------------------------------

func _update_scanners() -> void:
	if not _scanners_dirty or placed_objects == null:
		return
	_scanners_dirty = false
	var old := _scanners
	_scanners = {}
	var orphans: Array[PassengerScript] = []
	for id: int in placed_objects.get_ids():
		var obj = placed_objects.get_object(id)
		if obj.def_id != SCANNER_ID or obj.floor_index != floor_index:
			continue
		var forward := _rotate_local(Vector2(0.0, 1.0), obj.rotation)
		var service: Vector3 = obj.position + _rotate_local(SERVICE_LOCAL, obj.rotation)
		var exit: Vector3 = obj.position + _rotate_local(EXIT_LOCAL, obj.rotation)
		if not _exit_ok(exit, forward):
			continue
		var spots := _queue_spots(service, forward)
		if spots.is_empty() or not _step_clear(BuildGrid.world_to_tile(service - forward),
				BuildGrid.world_to_tile(service)):
			continue
		var s: Scanner = old.get(id, Scanner.new())
		old.erase(id)
		s.id = id
		s.service = spots[0]
		s.facing = -forward
		s.arch = obj.position + _rotate_local(ARCH_LOCAL, obj.rotation)
		s.exit = exit
		s.after_ready = false
		var moved := s.spots != spots
		s.spots = spots
		while s.queue.size() > spots.size():
			var extra: PassengerScript = s.queue.pop_back()
			if extra == s.serving:
				s.serving = null
			orphans.append(extra)
		_scanners[id] = s
		if moved:
			if s.serving != null:
				# The scanner moved: whoever was being screened starts again at the new front.
				s.serving.state = State.QUEUING_SECURITY
				s.serving = null
			_advance(s, false)
	for s: Scanner in old.values():
		orphans.append_array(s.queue)
	for p in orphans:
		_assign(p)


## The spot behind the scanner must be floor airside people may use, with no wall in the way.
func _exit_ok(exit: Vector3, forward: Vector3) -> bool:
	var tile := BuildGrid.world_to_tile(exit)
	if not terminal_floor.has_floor(tile, floor_index):
		return false
	if terminal_paths != null and not terminal_paths.is_walkable(tile, AIRSIDE):
		return false
	return _step_clear(BuildGrid.world_to_tile(exit + forward), tile)


## Standing spots in a straight line out from the scanner front, for as long
## as they stay on open landside or security floor with no wall in between.
func _queue_spots(service: Vector3, forward: Vector3) -> PackedVector3Array:
	var spots := PackedVector3Array()
	var prev_tile := Vector2i(-1, -1)
	for k in MAX_QUEUE:
		var pos := service + forward * (k * QUEUE_SPACING)
		var tile := BuildGrid.world_to_tile(pos)
		if not _queue_tile_ok(tile):
			break
		if k > 0 and tile != prev_tile and not _step_clear(prev_tile, tile):
			break
		pos.y = terminal_floor.get_surface_height(tile, floor_index)
		spots.append(pos)
		prev_tile = tile
	return spots


func _queue_tile_ok(tile: Vector2i) -> bool:
	if not terminal_floor.has_floor(tile, floor_index):
		return false
	var zone: int = terminal_zones.get_zone(tile, floor_index) if terminal_zones != null else Zone.NONE
	if zone == Zone.AIRSIDE:
		return false
	return terminal_paths == null or terminal_paths.is_walkable(tile, LANDSIDE)


## True if stepping between neighbouring tiles crosses no wall.
func _step_clear(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if absi(d.x) + absi(d.y) != 1 or terminal_walls == null:
		return absi(d.x) + absi(d.y) == 1
	if d.y == 0:
		return terminal_walls.get_edge(Vector2i(maxi(a.x, b.x), a.y), false, floor_index) != Piece.WALL
	return terminal_walls.get_edge(Vector2i(a.x, maxi(a.y, b.y)), true, floor_index) != Piece.WALL


## A local X/Z offset turned to world space by a rotation around Y (as PlacedObjects does).
static func _rotate_local(offset: Vector2, yaw: float) -> Vector3:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector3(offset.x * c + offset.y * s, 0.0, -offset.x * s + offset.y * c)
