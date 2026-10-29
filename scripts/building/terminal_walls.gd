class_name TerminalWalls
extends Node3D
## Terminal walls and doors (checklist step 9).
##
## Walls stand on tile edges. Each edge is empty, a wall or a door (a doorway
## with a lintel above it). An edge is addressed by the grid corner it starts
## from and its direction (see BuildGrid.world_to_edge):
##   horizontal: from corner (x, y) to (x + 1, y), along world X
##   vertical:   from corner (x, y) to (x, y + 1), along world Z
##
## Walls are drawn like floors: one mesh per chunk, rebuilt only when an edge in
## or next to it changes. Straight stretches of wall merge into single boxes.
## Joins stay clean with no overlapping faces: horizontal walls run on through
## the corner square, and vertical walls stop against their side. Free wall
## ends reach half a wall thickness past the corner so they look finished.
##
## Keep this node at the world origin: meshes are built in world coordinates.

## Emitted after edges change, with the corner range that was edited.
signal walls_changed(from_corner: Vector2i, to_corner: Vector2i, floor_index: int)

enum Piece { NONE, WALL, DOOR }

const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")
const CHUNK_TILES := 32
const HEIGHT := 3.2
const THICKNESS := 0.2
## Height of the doorway opening; a lintel fills the wall above it.
const DOOR_HEIGHT := 2.3
## Width of the doorway opening, centred on its tile edge. Solid jambs fill the
## rest of the edge, so a door beside a corner never cuts into the corner.
## Keep it at most TILE_SIZE - THICKNESS, so each jamb covers the corner square.
const DOOR_WIDTH := 0.8
const HALF := THICKNESS * 0.5

const WALL_COLOR := Color(0.96, 0.96, 0.94)
## Wall tops are darker so wall lines read clearly from above.
const TOP_COLOR := Color(0.52, 0.55, 0.60)
## Door lintels have a blue top so doorways show from above too.
const DOOR_TOP_COLOR := Color(0.36, 0.62, 0.92)

## Optional PlacedObjects node (placed_objects.gd): walls aren't built through objects.
@export var placed_objects: Node3D

## Per floor index: [horizontal edges, vertical edges], one byte per corner.
var _edges := {}
## Vector3i(chunk x, chunk y, floor index) -> MeshInstance3D
var _chunks := {}
var _material: StandardMaterial3D
var _mesh := MeshBuilderScript.new()
## Row length of the edge arrays (one entry per corner across the plot).
var _stride := BuildGrid.PLOT_TILES.x + 1


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.9


# --- Queries --------------------------------------------------------------------

func is_valid_edge(corner: Vector2i, horizontal: bool) -> bool:
	var plot := BuildGrid.PLOT_TILES
	if horizontal:
		return corner.x >= 0 and corner.x < plot.x and corner.y >= 0 and corner.y <= plot.y
	return corner.x >= 0 and corner.x <= plot.x and corner.y >= 0 and corner.y < plot.y


## Piece.NONE, Piece.WALL or Piece.DOOR.
func get_edge(corner: Vector2i, horizontal: bool, floor_index := 0) -> int:
	if not _edges.has(floor_index):
		return Piece.NONE
	return _piece(_edges[floor_index][0 if horizontal else 1], corner.x, corner.y, horizontal)


## Edges on the straight line between two corners, as [corner, horizontal] pairs.
## Empty if the corners are equal or not on one grid line.
func get_run_edges(from: Vector2i, to: Vector2i) -> Array:
	var edges := []
	if from.y == to.y:
		for x in range(mini(from.x, to.x), maxi(from.x, to.x)):
			if is_valid_edge(Vector2i(x, from.y), true):
				edges.append([Vector2i(x, from.y), true])
	elif from.x == to.x:
		for y in range(mini(from.y, to.y), maxi(from.y, to.y)):
			if is_valid_edge(Vector2i(from.x, y), false):
				edges.append([Vector2i(from.x, y), false])
	return edges


## How many edges set_run() would change.
func count_run_changes(from: Vector2i, to: Vector2i, place: bool, floor_index := 0) -> int:
	var count := 0
	for edge: Array in get_run_edges(from, to):
		var empty := get_edge(edge[0], edge[1], floor_index) == Piece.NONE
		if empty == place and not (place and _is_blocked(edge[0], edge[1], floor_index)):
			count += 1
	return count


## Total wall and door pieces on a floor: {"walls": int, "doors": int}.
func get_piece_counts(floor_index := 0) -> Dictionary:
	var counts := {"walls": 0, "doors": 0}
	if _edges.has(floor_index):
		for arr: PackedByteArray in _edges[floor_index]:
			counts.walls += arr.count(Piece.WALL)
			counts.doors += arr.count(Piece.DOOR)
	return counts


# --- Editing --------------------------------------------------------------------

## Builds walls on the empty edges between two corners (place = true), or removes
## walls and doors there (place = false). Existing doors are kept when placing,
## and edges that would cut through a placed object are skipped.
## The corners must be on one grid line. Returns how many edges changed.
func set_run(from: Vector2i, to: Vector2i, place: bool, floor_index := 0) -> int:
	var edges := get_run_edges(from, to)
	if edges.is_empty():
		return 0
	var data := _get_edges(floor_index)
	var slot := 0 if edges[0][1] else 1
	var arr: PackedByteArray = data[slot]
	var changed := 0
	for edge: Array in edges:
		var corner: Vector2i = edge[0]
		var i := corner.x + corner.y * _stride
		if place and arr[i] == Piece.NONE and not _is_blocked(corner, edge[1], floor_index):
			arr[i] = Piece.WALL
			changed += 1
		elif not place and arr[i] != Piece.NONE:
			arr[i] = Piece.NONE
			changed += 1
	data[slot] = arr  # packed arrays are copied on write, so store it back
	if changed > 0:
		_edges_changed(from.min(to), from.max(to), floor_index)
	return changed


## Turns a wall piece into a doorway (door = true) or a doorway back into wall.
## Returns false if the edge didn't hold the right piece.
func set_door(corner: Vector2i, horizontal: bool, door: bool, floor_index := 0) -> bool:
	var current := get_edge(corner, horizontal, floor_index)
	if current != (Piece.WALL if door else Piece.DOOR):
		return false
	var data := _get_edges(floor_index)
	var slot := 0 if horizontal else 1
	var arr: PackedByteArray = data[slot]
	arr[corner.x + corner.y * _stride] = Piece.DOOR if door else Piece.WALL
	data[slot] = arr
	var end := corner + (Vector2i(1, 0) if horizontal else Vector2i(0, 1))
	_edges_changed(corner, end, floor_index)
	return true


# --- Storage --------------------------------------------------------------------

func _get_edges(floor_index: int) -> Array:
	if not _edges.has(floor_index):
		var horizontal := PackedByteArray()
		horizontal.resize(_stride * (BuildGrid.PLOT_TILES.y + 1))
		_edges[floor_index] = [horizontal, horizontal.duplicate()]
	return _edges[floor_index]


func _piece(arr: PackedByteArray, x: int, y: int, horizontal: bool) -> int:
	if not is_valid_edge(Vector2i(x, y), horizontal):
		return Piece.NONE
	return arr[x + y * _stride]


## True if a wall on this edge would cut through a placed object.
func _is_blocked(corner: Vector2i, horizontal: bool, floor_index: int) -> bool:
	return placed_objects != null and placed_objects.is_edge_inside_object(corner, horizontal, floor_index)


## True if a horizontal wall or door touches a corner.
func _has_horizontal(h: PackedByteArray, corner: Vector2i) -> bool:
	return _piece(h, corner.x - 1, corner.y, true) != Piece.NONE \
		or _piece(h, corner.x, corner.y, true) != Piece.NONE


func _edges_changed(lo: Vector2i, hi: Vector2i, floor_index: int) -> void:
	# Joins depend on neighbouring edges, so rebuild one corner beyond the edit too.
	@warning_ignore("integer_division")
	var first := Vector2i(maxi(lo.x - 1, 0) / CHUNK_TILES, maxi(lo.y - 1, 0) / CHUNK_TILES)
	@warning_ignore("integer_division")
	var last := Vector2i((hi.x + 1) / CHUNK_TILES, (hi.y + 1) / CHUNK_TILES)
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			_rebuild_chunk(Vector3i(cx, cy, floor_index))
	walls_changed.emit(lo, hi, floor_index)


# --- Meshing --------------------------------------------------------------------

func _rebuild_chunk(key: Vector3i) -> void:
	var plot := BuildGrid.PLOT_TILES
	var x0 := key.x * CHUNK_TILES
	var y0 := key.y * CHUNK_TILES
	if x0 > plot.x or y0 > plot.y:
		return
	var data: Array = _edges[key.z]
	var h: PackedByteArray = data[0]
	var v: PackedByteArray = data[1]
	_mesh.clear()

	# Horizontal walls: each stretch runs on through corner squares, and its free
	# ends reach half a thickness past the corner. A stretch that carries on in
	# the next chunk has no extension at that end.
	for y in range(y0, mini(y0 + CHUNK_TILES, plot.y + 1)):
		var x := x0
		var x_end := mini(x0 + CHUNK_TILES, plot.x)
		while x < x_end:
			if _piece(h, x, y, true) == Piece.NONE:
				x += 1
				continue
			var start := x
			while x < x_end and _piece(h, x, y, true) != Piece.NONE:
				x += 1
			var start_adjust := 0.0 if _piece(h, start - 1, y, true) != Piece.NONE else -HALF
			var end_adjust := 0.0 if _piece(h, x, y, true) != Piece.NONE else HALF
			_add_run(h, Vector2i(start, y), x - start, true, start_adjust, end_adjust, key.z)

	# Vertical walls: split wherever a horizontal wall touches the corner, and
	# stop against its side there.
	for x in range(x0, mini(x0 + CHUNK_TILES, plot.x + 1)):
		var y := y0
		var y_end := mini(y0 + CHUNK_TILES, plot.y)
		while y < y_end:
			if _piece(v, x, y, false) == Piece.NONE:
				y += 1
				continue
			var start := y
			y += 1
			while y < y_end and _piece(v, x, y, false) != Piece.NONE \
					and not _has_horizontal(h, Vector2i(x, y)):
				y += 1
			var start_adjust := _vertical_end_adjust(h, v, Vector2i(x, start), -1)
			var end_adjust := _vertical_end_adjust(h, v, Vector2i(x, y), 1)
			_add_run(v, Vector2i(x, start), y - start, false, start_adjust, end_adjust, key.z)

	_apply_chunk_mesh(key)


## How far a vertical stretch's end moves along Z at a corner. direction is -1
## for the start of the stretch and 1 for its end.
func _vertical_end_adjust(h: PackedByteArray, v: PackedByteArray, corner: Vector2i, direction: int) -> float:
	if _has_horizontal(h, corner):
		return -HALF * direction  # stop against the horizontal wall
	var beyond: Vector2i = corner + Vector2i(0, -1) if direction < 0 else corner
	if _piece(v, beyond.x, beyond.y, false) != Piece.NONE:
		return 0.0  # carries on in the next chunk
	return HALF * direction  # free end


## Adds the boxes for `count` edges in a straight line from corner `start`.
## Walls next to each other merge into one box; doorways get a lintel.
func _add_run(arr: PackedByteArray, start: Vector2i, count: int, horizontal: bool,
		start_adjust: float, end_adjust: float, floor_index: int) -> void:
	var t := BuildGrid.TILE_SIZE
	var jamb := (t - DOOR_WIDTH) * 0.5
	var along := start.x if horizontal else start.y
	# Pieces as [from, to, is_wall] in metres along the run. A doorway is a jamb,
	# the opening (lintel only) and another jamb.
	var pieces := []
	for i in count:
		var corner := start + (Vector2i(i, 0) if horizontal else Vector2i(0, i))
		var a := (along + i) * t
		var b := a + t
		if _piece(arr, corner.x, corner.y, horizontal) == Piece.DOOR:
			pieces.append([a, a + jamb, true])
			pieces.append([a + jamb, b - jamb, false])
			pieces.append([b - jamb, b, true])
		else:
			pieces.append([a, b, true])
	# Extensions are full height even beside a doorway, so corners never have holes.
	if start_adjust < 0.0:
		pieces.push_front([pieces[0][0] + start_adjust, pieces[0][0], true])
	else:
		pieces[0][0] += start_adjust
	if end_adjust > 0.0:
		pieces.append([pieces[-1][1], pieces[-1][1] + end_adjust, true])
	else:
		pieces[-1][1] += end_adjust

	var merged := []
	for piece: Array in pieces:
		if piece[1] - piece[0] < 0.001:
			continue  # a jamb fully hidden where a vertical wall stops against a horizontal one
		if not merged.is_empty() and merged[-1][2] == piece[2]:
			merged[-1][1] = piece[1]
		else:
			merged.append(piece)

	var o := BuildGrid.origin
	var base := BuildGrid.get_floor_height(floor_index)
	var across := (start.y if horizontal else start.x) * t
	for piece: Array in merged:
		var is_wall: bool = piece[2]
		var y_lo: float = base if is_wall else base + DOOR_HEIGHT
		var y_hi := base + HEIGHT
		var lo: Vector3
		var hi: Vector3
		if horizontal:
			lo = Vector3(o.x + piece[0], y_lo, o.z + across - HALF)
			hi = Vector3(o.x + piece[1], y_hi, o.z + across + HALF)
		else:
			lo = Vector3(o.x + across - HALF, y_lo, o.z + piece[0])
			hi = Vector3(o.x + across + HALF, y_hi, o.z + piece[1])
		if is_wall:
			_mesh.add_box(lo, hi, WALL_COLOR, TOP_COLOR)
		else:
			_mesh.add_box(lo, hi, WALL_COLOR, DOOR_TOP_COLOR, true)


func _apply_chunk_mesh(key: Vector3i) -> void:
	var mi: MeshInstance3D = _chunks.get(key)
	if _mesh.is_empty():
		if mi:
			mi.queue_free()
			_chunks.erase(key)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d_%d" % [key.x, key.y, key.z]
		mi.material_override = _material
		add_child(mi)
		_chunks[key] = mi
	mi.mesh = _mesh.commit()
