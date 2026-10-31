extends Node
## Check-in queues (checklist step 30).
##
## Every check-in desk on landside (or unzoned) floor has a queue: a line of
## standing spots running straight out from the front of the desk, as long
## as the floor allows (up to MAX_QUEUE, stopping at walls, objects and other
## zones). A passenger who reaches the terminal picks the desk with the best
## mix of short queue and short walk, walks to the back of its queue, steps
## up as people ahead are served, checks in at the front for a processing
## time and then moves on towards security. With no desk (or every queue
## full) passengers wait where they are until there is room.
##
## Queues follow the layout: when a desk is moved its queue moves with it,
## and when one is removed its passengers pick another desk.

const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const State := PassengerScript.State
const Zone := TerminalZonesScript.Zone
const Piece := TerminalWallsScript.Piece
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE

const DESK_ID := &"checkin_desk"
## Where the passenger being served stands, in the desk's local X/Z (its front faces +Z).
const SERVICE_LOCAL := Vector2(0.3, 1.35)
## Gap between people in a queue, in metres.
const QUEUE_SPACING := 0.75
const MAX_QUEUE := 30
## Game seconds a check-in takes (random in this range).
const PROCESS_MIN := 60
const PROCESS_MAX := 120
## When picking a desk, one more person in the queue counts as this many metres of extra walking.
const METRES_PER_PERSON := 12.0
## After check-in passengers wait within this many tiles of the security zone's nearest tile.
const AFTER_RADIUS := 3
const WARN_INTERVAL := 3600

## A passenger finished checking in and is moving on.
signal passenger_checked_in(passenger: PassengerScript)


class Desk:
	extends RefCounted
	var id := 0
	## Where the passenger being served stands, and the way they face (towards the desk).
	var service := Vector3.ZERO
	var facing := Vector3.ZERO
	## Standing spots from the front of the queue (index 0, at the desk) to the back.
	var spots := PackedVector3Array()
	## Everyone queuing or walking to the queue, front first; queue[0] is served first.
	var queue: Array[PassengerScript] = []
	var serving: PassengerScript
	var done_time := 0
	var served := 0


@export var placed_objects: Node3D
@export var terminal_floor: Node3D
@export var terminal_walls: Node3D
@export var terminal_zones: Node3D
@export var terminal_paths: TerminalPathsScript
@export var spawner: PassengerSpawnerScript
@export var floor_index := 0

## Placed object id -> Desk.
var _desks := {}
var _desks_dirty := true
## Passengers waiting for a desk with room.
var _waiting: Array[PassengerScript] = []
## Landside floor tiles and security floor tiles, for where people go after check-in.
var _landside_tiles: Array[Vector2i] = []
var _security_tiles: Array[Vector2i] = []
var _tiles_dirty := true
var _last_warning := -WARN_INTERVAL
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if placed_objects != null:
		placed_objects.object_added.connect(func(_id: int) -> void: _desks_dirty = true)
		placed_objects.object_removed.connect(func(_id: int) -> void: _desks_dirty = true)
		placed_objects.object_moved.connect(func(_id: int) -> void: _desks_dirty = true)
	if terminal_paths != null:
		terminal_paths.paths_changed.connect(_on_paths_changed)
	if spawner != null:
		spawner.passenger_arrived.connect(_assign)
	GameClock.ticked.connect(_on_ticked)


func set_seed(value: int) -> void:
	_rng.seed = value


# --- Queries ----------------------------------------------------------------------

## Check-in desks in use, as Desk records.
func get_desks() -> Array:
	_update_desks()
	return _desks.values()


func get_desk(id: int) -> Desk:
	_update_desks()
	return _desks.get(id)


func get_waiting_count() -> int:
	return _waiting.size()


# --- Passengers -------------------------------------------------------------------

## Sends a passenger to the desk with the best mix of short queue and short walk.
func _assign(p: PassengerScript) -> void:
	_update_desks()
	p.desk_id = 0
	var pos: Vector3 = spawner.crowd.get_passenger_position(p.crowd_id)
	var best: Desk = null
	var best_score := INF
	for d: Desk in _desks.values():
		if d.queue.size() >= d.spots.size():
			continue
		var score := d.queue.size() + pos.distance_to(d.service) / METRES_PER_PERSON + _rng.randf() * 0.5
		if score < best_score:
			best_score = score
			best = d
	if best == null:
		p.state = State.WAITING_CHECKIN
		if p.is_walking:
			spawner.walk(p, spawner.crowd.get_passenger_position(p.crowd_id), Callable(), true)
		if not _waiting.has(p):
			_waiting.append(p)
		return
	_waiting.erase(p)
	best.queue.append(p)
	p.desk_id = best.id
	p.state = State.TO_CHECKIN
	spawner.walk(p, best.spots[best.queue.size() - 1], _on_reached_spot)


## Takes a passenger out of check-in (their desk's queue or the waiting list);
## the people behind them step up.
func drop(p: PassengerScript) -> void:
	_waiting.erase(p)
	var d: Desk = _desks.get(p.desk_id)
	if d == null or not d.queue.has(p):
		return
	if d.serving == p:
		d.serving = null
	d.queue.erase(p)
	_advance(d)


func _on_reached_spot(p: PassengerScript) -> void:
	var d: Desk = _desks.get(p.desk_id)
	if d == null or not d.queue.has(p):
		return
	if p.state != State.CHECKING_IN:
		p.state = State.QUEUING_CHECKIN
	spawner.face(p, d.facing)


func _on_ticked(_game_seconds: float) -> void:
	_update_desks()
	var now := GameClock.game_time
	for d: Desk in _desks.values():
		if d.serving != null and now >= d.done_time:
			_finish(d)
		if d.serving == null and not d.queue.is_empty():
			var p := d.queue[0]
			# Service starts as the front passenger steps up from the next spot, so
			# shuffling forward doesn't hold the desk up.
			if p.state == State.QUEUING_CHECKIN and (not p.is_walking or spawner.crowd.get_passenger_position(
					p.crowd_id).distance_to(d.spots[0]) <= QUEUE_SPACING * 1.1):
				d.serving = p
				d.done_time = now + _rng.randi_range(PROCESS_MIN, PROCESS_MAX)
				p.state = State.CHECKING_IN
	if not _waiting.is_empty():
		for p in _waiting.duplicate():
			_assign(p)
		if not _waiting.is_empty() and now - _last_warning >= WARN_INTERVAL:
			_last_warning = now
			print("CHECK-IN | %s %d passengers waiting: %s" % [GameClock.get_time_string(), _waiting.size(),
				"no check-in desk on landside" if _desks.is_empty() else "every queue is full"])


func _finish(d: Desk) -> void:
	var p := d.serving
	d.serving = null
	d.queue.erase(p)
	d.served += 1
	p.state = State.CHECKED_IN
	p.checked_in_time = GameClock.game_time
	spawner.walk(p, _after_spot(d))
	_advance(d)
	passenger_checked_in.emit(p)


## Everyone in the queue walks to their spot (straight ahead when just stepping up).
func _advance(d: Desk, direct := true) -> void:
	for i in d.queue.size():
		var q := d.queue[i]
		if q.state == State.QUEUING_CHECKIN:
			spawner.walk(q, d.spots[i], _on_reached_spot, direct)
		elif q.state == State.TO_CHECKIN:
			spawner.walk(q, d.spots[i], _on_reached_spot)


## Where a passenger goes after check-in: landside floor near the security
## zone if there is one, else anywhere on landside away from the queues.
func _after_spot(d: Desk) -> Vector3:
	_update_tiles()
	var options: Array[Vector2i] = []
	if not _security_tiles.is_empty():
		var nearest := _security_tiles[0]
		var best := INF
		for t in _security_tiles:
			var dist := BuildGrid.tile_to_world(t, floor_index).distance_squared_to(d.service)
			if dist < best:
				best = dist
				nearest = t
		for t in _landside_tiles:
			if absi(t.x - nearest.x) <= AFTER_RADIUS and absi(t.y - nearest.y) <= AFTER_RADIUS:
				options.append(t)
	if options.is_empty():
		var queue_tiles := {}
		for desk: Desk in _desks.values():
			for s in desk.spots:
				queue_tiles[BuildGrid.world_to_tile(s)] = true
		for t in _landside_tiles:
			if not queue_tiles.has(t):
				options.append(t)
	if options.is_empty():
		return d.service + (d.service - d.spots[d.spots.size() - 1]).normalized()
	var tile := options[_rng.randi() % options.size()]
	return BuildGrid.tile_to_world(tile, floor_index) + Vector3(_rng.randf_range(-0.35, 0.35), 0.0,
		_rng.randf_range(-0.35, 0.35))


# --- Desks and queues -------------------------------------------------------------

func _on_paths_changed() -> void:
	_desks_dirty = true
	_tiles_dirty = true


func _update_desks() -> void:
	if not _desks_dirty or placed_objects == null:
		return
	_desks_dirty = false
	var old := _desks
	_desks = {}
	var orphans: Array[PassengerScript] = []
	for id: int in placed_objects.get_ids():
		var obj = placed_objects.get_object(id)
		if obj.def_id != DESK_ID or obj.floor_index != floor_index:
			continue
		var forward := _rotate_local(Vector2(0.0, 1.0), obj.rotation)
		var service: Vector3 = obj.position + _rotate_local(SERVICE_LOCAL, obj.rotation)
		var spots := _queue_spots(service, forward)
		if spots.is_empty():
			continue
		var d: Desk = old.get(id, Desk.new())
		old.erase(id)
		d.id = id
		d.service = service
		d.facing = -forward
		var moved := d.spots != spots
		d.spots = spots
		while d.queue.size() > spots.size():
			var extra: PassengerScript = d.queue.pop_back()
			if extra == d.serving:
				d.serving = null
			orphans.append(extra)
		_desks[id] = d
		if moved:
			if d.serving != null:
				# The desk moved: whoever was being served starts again at the new front.
				d.serving.state = State.QUEUING_CHECKIN
				d.serving = null
			_advance(d, false)
	for d: Desk in old.values():
		orphans.append_array(d.queue)
	for p in orphans:
		_assign(p)


## Standing spots in a straight line out from the desk front, for as long as
## they stay on open landside floor with no wall in between.
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
	if not terminal_floor.has_floor(tile, floor_index) or not _landside_zone(tile):
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


func _landside_zone(tile: Vector2i) -> bool:
	var zone: int = terminal_zones.get_zone(tile, floor_index) if terminal_zones != null else Zone.NONE
	return zone == Zone.NONE or zone == Zone.LANDSIDE


func _update_tiles() -> void:
	if not _tiles_dirty:
		return
	_tiles_dirty = false
	_landside_tiles.clear()
	_security_tiles.clear()
	var bounds: Rect2i = terminal_floor.get_floor_bounds(floor_index)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			if not terminal_floor.has_floor(tile, floor_index):
				continue
			var zone: int = terminal_zones.get_zone(tile, floor_index) if terminal_zones != null else Zone.NONE
			if zone == Zone.SECURITY:
				_security_tiles.append(tile)
			elif (zone == Zone.NONE or zone == Zone.LANDSIDE) \
					and (terminal_paths == null or terminal_paths.is_walkable(tile, LANDSIDE)):
				_landside_tiles.append(tile)


## A local X/Z offset turned to world space by a rotation around Y (as PlacedObjects does).
static func _rotate_local(offset: Vector2, yaw: float) -> Vector3:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector3(offset.x * c + offset.y * s, 0.0, -offset.x * s + offset.y * c)
