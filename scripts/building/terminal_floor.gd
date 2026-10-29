class_name TerminalFloor
extends Node3D
## Terminal floor tiles (checklist step 8).
##
## Stores which tiles have terminal floor and draws them as a thin slab.
## The plot is split into chunks of CHUNK_TILES x CHUNK_TILES tiles. Each chunk
## is one mesh (one draw call), rebuilt only when a tile inside it changes.
## Inside a chunk, filled tiles are merged into as few rectangles as possible
## (greedy meshing), so even a big hall is only a handful of triangles.
##
## The same rectangles also make the terminal roof (checklist step 13): a flat
## slab on top of the walls over every floor tile, in its own chunk meshes so
## the cutaway can hide it.
##
## Keep this node at the world origin: meshes are built in world coordinates.

## Emitted after tiles change. rect is the area that was edited, in tiles.
signal floor_changed(rect: Rect2i, floor_index: int)

const FLOOR_SHADER := preload("res://materials/terminal_floor.gdshader")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
## Chunk size in tiles. Bigger chunks mean fewer draw calls, smaller ones cheaper rebuilds.
const CHUNK_TILES := 32
## Thickness of the floor slab in metres. Things standing on the floor sit this high.
const THICKNESS := 0.1
## The roof sits on top of the walls.
const ROOF_BOTTOM := TerminalWallsScript.HEIGHT
const ROOF_THICKNESS := 0.2
const ROOF_TOP_COLOR := Color(0.8, 0.82, 0.85)
const ROOF_SIDE_COLOR := Color(0.66, 0.69, 0.73)

## Optional PlacedObjects node (placed_objects.gd): floor under objects can't be removed.
@export var placed_objects: Node3D
## Optional Runways node (runways.gd): floor is never laid on a runway (checklist step 16).
@export var runways: Node3D

## Per floor index: one byte per plot tile, 1 = floor.
var _tiles := {}
## Vector3i(chunk x, chunk y, floor index) -> MeshInstance3D
var _chunks := {}
var _material: ShaderMaterial
## Reused by every chunk rebuild.
var _mesh := MeshBuilderScript.new()

## Whether roofs are drawn (the cutaway hides them).
var roof_visible := true
## Vector3i(chunk x, chunk y, floor index) -> MeshInstance3D
var _roof_chunks := {}
var _roof_material: StandardMaterial3D
var _roof_mesh := MeshBuilderScript.new()
## Holds the roof chunks, so hiding roofs is one visibility change.
var _roofs: Node3D


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = FLOOR_SHADER
	_material.set_shader_parameter("tile_size", BuildGrid.TILE_SIZE)
	_roof_material = StandardMaterial3D.new()
	_roof_material.vertex_color_use_as_albedo = true
	_roof_material.vertex_color_is_srgb = true
	_roof_material.roughness = 0.9
	_roofs = Node3D.new()
	_roofs.name = "Roofs"
	add_child(_roofs)


func set_roof_visible(value: bool) -> void:
	roof_visible = value
	_roofs.visible = value


# --- Queries --------------------------------------------------------------------

func has_floor(tile: Vector2i, floor_index := 0) -> bool:
	var index := BuildGrid.tile_to_index(tile)
	return index >= 0 and _tiles.has(floor_index) and _tiles[floor_index][index] == 1


## Height of the walkable surface on a tile: on top of the floor slab, or the ground.
func get_surface_height(tile: Vector2i, floor_index := 0) -> float:
	var base := BuildGrid.get_floor_height(floor_index)
	return base + THICKNESS if has_floor(tile, floor_index) else base


## Number of tiles in rect that would change if it were set to filled.
func count_changes(rect: Rect2i, filled: bool, floor_index := 0) -> int:
	rect = _clip_to_plot(rect)
	var area := rect.get_area()
	if not _tiles.has(floor_index):
		return area - (runways.count_tiles_in(rect) if runways else 0) if filled else 0
	var tiles: PackedByteArray = _tiles[floor_index]
	var floored := 0
	var protected := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			floored += tiles[row + x]
			if not filled and tiles[row + x] == 1 and _has_object(Vector2i(x, y), floor_index):
				protected += 1
	if filled and runways:
		return area - floored - runways.count_tiles_in(rect)  # runway tiles never have floor
	return area - floored if filled else floored - protected


## How many tiles in rect have floor.
func count_floor_tiles(rect: Rect2i, floor_index := 0) -> int:
	rect = _clip_to_plot(rect)
	if not _tiles.has(floor_index):
		return 0
	var tiles: PackedByteArray = _tiles[floor_index]
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		count += tiles.slice(row + rect.position.x, row + rect.end.x).count(1)
	return count


## Total floor tiles on a floor.
func get_floor_tile_count(floor_index := 0) -> int:
	if not _tiles.has(floor_index):
		return 0
	return (_tiles[floor_index] as PackedByteArray).count(1)


# --- Editing --------------------------------------------------------------------

## Lays floor on (filled = true) or removes it from every tile in rect.
## Floor under placed objects is kept, and none is laid on runways.
## Returns how many tiles changed.
func set_rect(rect: Rect2i, filled: bool, floor_index := 0) -> int:
	rect = _clip_to_plot(rect)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0
	var tiles := _get_tiles(floor_index)
	var value := 1 if filled else 0
	# Only the few runways overlapping rect are checked per tile.
	var runway_rects: Array[Rect2i] = []
	if filled and runways:
		for id: int in runways.get_runways_in(rect):
			runway_rects.append(runways.get_runway(id).rect)
	var changed := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			if not runway_rects.is_empty() and runway_rects.any(
					func(r: Rect2i) -> bool: return r.has_point(Vector2i(x, y))):
				continue
			if tiles[row + x] != value and (filled or not _has_object(Vector2i(x, y), floor_index)):
				tiles[row + x] = value
				changed += 1
	_tiles[floor_index] = tiles  # PackedByteArray is copied on assignment
	if changed > 0:
		_tiles_changed(rect, floor_index)
	return changed


## The tiles in rect (clipped to the plot), one byte each, row by row: saved
## by commands so undo can put them back with set_rect_state().
func get_rect_state(rect: Rect2i, floor_index := 0) -> PackedByteArray:
	rect = _clip_to_plot(rect)
	var tiles := _get_tiles(floor_index)
	var state := PackedByteArray()
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		state.append_array(tiles.slice(row + rect.position.x, row + rect.end.x))
	return state


## Puts back tiles saved by get_rect_state() for the same rect.
func set_rect_state(rect: Rect2i, state: PackedByteArray, floor_index := 0) -> void:
	rect = _clip_to_plot(rect)
	if state.size() != rect.get_area() or state.is_empty():
		return
	var tiles := _get_tiles(floor_index)
	var i := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			tiles[row + x] = state[i]
			i += 1
	_tiles[floor_index] = tiles
	_tiles_changed(rect, floor_index)


## Rebuilds every chunk rect touches, plus neighbours whose slab sides may now
## be hidden or exposed, and tells listeners.
func _tiles_changed(rect: Rect2i, floor_index: int) -> void:
	@warning_ignore("integer_division")
	var first := Vector2i((rect.position.x - 1) / CHUNK_TILES, (rect.position.y - 1) / CHUNK_TILES)
	@warning_ignore("integer_division")
	var last := Vector2i(rect.end.x / CHUNK_TILES, rect.end.y / CHUNK_TILES)
	for cy in range(maxi(first.y, 0), last.y + 1):
		for cx in range(maxi(first.x, 0), last.x + 1):
			_rebuild_chunk(Vector3i(cx, cy, floor_index))
	floor_changed.emit(rect, floor_index)


# --- Meshing --------------------------------------------------------------------

func _get_tiles(floor_index: int) -> PackedByteArray:
	if not _tiles.has(floor_index):
		var tiles := PackedByteArray()
		tiles.resize(BuildGrid.get_tile_count())
		_tiles[floor_index] = tiles
	return _tiles[floor_index]


func _has_object(tile: Vector2i, floor_index: int) -> bool:
	return placed_objects != null and placed_objects.get_object_at(tile, floor_index) != 0


func _clip_to_plot(rect: Rect2i) -> Rect2i:
	return rect.intersection(Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES))


func _is_filled(tiles: PackedByteArray, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= BuildGrid.PLOT_TILES.x or y >= BuildGrid.PLOT_TILES.y:
		return false
	return tiles[x + y * BuildGrid.PLOT_TILES.x] == 1


func _rebuild_chunk(key: Vector3i) -> void:
	var x0 := key.x * CHUNK_TILES
	var y0 := key.y * CHUNK_TILES
	if x0 >= BuildGrid.PLOT_TILES.x or y0 >= BuildGrid.PLOT_TILES.y:
		return
	var w := mini(CHUNK_TILES, BuildGrid.PLOT_TILES.x - x0)
	var h := mini(CHUNK_TILES, BuildGrid.PLOT_TILES.y - y0)
	var tiles: PackedByteArray = _tiles[key.z]
	_mesh.clear()
	_roof_mesh.clear()

	# Top faces: greedy merge. 1 = floor not yet covered by a rectangle, 2 = covered.
	var mask := PackedByteArray()
	mask.resize(w * h)
	for ly in h:
		for lx in w:
			mask[lx + ly * w] = tiles[(x0 + lx) + (y0 + ly) * BuildGrid.PLOT_TILES.x]
	for ly in h:
		var lx := 0
		while lx < w:
			if mask[lx + ly * w] != 1:
				lx += 1
				continue
			var rw := 1
			while lx + rw < w and mask[lx + rw + ly * w] == 1:
				rw += 1
			var rh := 1
			var can_grow := true
			while can_grow and ly + rh < h:
				for i in rw:
					if mask[lx + i + (ly + rh) * w] != 1:
						can_grow = false
						break
				if can_grow:
					rh += 1
			for j in rh:
				for i in rw:
					mask[lx + i + (ly + j) * w] = 2
			_add_top(Vector2i(x0 + lx, y0 + ly), Vector2i(rw, rh), key.z)
			_add_roof(Vector2i(x0 + lx, y0 + ly), Vector2i(rw, rh), key.z)
			lx += rw

	# Slab sides: only where floor meets no floor, merged into runs along each edge.
	for ly in h:
		var y := y0 + ly
		for side: int in [-1, 1]:
			var run_start := -1
			for lx in w + 1:
				var x := x0 + lx
				var exposed := lx < w and _is_filled(tiles, x, y) and not _is_filled(tiles, x, y + side)
				if exposed and run_start < 0:
					run_start = x
				elif not exposed and run_start >= 0:
					var edge_z := y + (1 if side > 0 else 0)
					_add_side(Vector2i(run_start, edge_z), Vector2i(x, edge_z), Vector3(0, 0, side), key.z)
					_add_roof_rim(tiles, run_start, x, y, side, true, key.z)
					run_start = -1
	for lx in w:
		var x := x0 + lx
		for side: int in [-1, 1]:
			var run_start := -1
			for ly in h + 1:
				var y := y0 + ly
				var exposed := ly < h and _is_filled(tiles, x, y) and not _is_filled(tiles, x + side, y)
				if exposed and run_start < 0:
					run_start = y
				elif not exposed and run_start >= 0:
					var edge_x := x + (1 if side > 0 else 0)
					_add_side(Vector2i(edge_x, run_start), Vector2i(edge_x, y), Vector3(side, 0, 0), key.z)
					_add_roof_rim(tiles, run_start, y, x, side, false, key.z)
					run_start = -1

	_apply_chunk_mesh(key)


## Top face of a rectangle of tiles starting at tile `from`.
func _add_top(from: Vector2i, size: Vector2i, floor_index: int) -> void:
	var lift := Vector3.UP * THICKNESS
	var a := BuildGrid.tile_corner_to_world(from, floor_index) + lift
	var b := BuildGrid.tile_corner_to_world(from + Vector2i(size.x, 0), floor_index) + lift
	var c := BuildGrid.tile_corner_to_world(from + size, floor_index) + lift
	var d := BuildGrid.tile_corner_to_world(from + Vector2i(0, size.y), floor_index) + lift
	_mesh.add_quad([a, b, c, d], Vector3.UP, Color.WHITE)


## Vertical slab side between two grid corners, facing `normal`.
func _add_side(from: Vector2i, to: Vector2i, normal: Vector3, floor_index: int) -> void:
	var lift := Vector3.UP * THICKNESS
	var a := BuildGrid.tile_corner_to_world(from, floor_index)
	var b := BuildGrid.tile_corner_to_world(to, floor_index)
	_mesh.add_quad([a, b, b + lift, a + lift], normal, Color.BLACK)


## Roof slab over a rectangle of tiles starting at tile `from`.
func _add_roof(from: Vector2i, size: Vector2i, floor_index: int) -> void:
	var lo := BuildGrid.tile_corner_to_world(from, floor_index) + Vector3.UP * ROOF_BOTTOM
	var hi := BuildGrid.tile_corner_to_world(from + size, floor_index) + Vector3.UP * (ROOF_BOTTOM + ROOF_THICKNESS)
	_roof_mesh.add_box(lo, hi, ROOF_SIDE_COLOR, ROOF_TOP_COLOR, true)


## Roof overhang along an outside edge of the floor, half a wall thick, so the
## roof reaches the outer face of the walls standing on that edge. The edge runs
## from tile `from` to `to` (exclusive) along row or column `line`, on the `side`
## (-1 or 1) where there is no floor. Horizontal rims run on over outer corners
## and stop short at inner corners; vertical rims stop at the corner line. That
## way every corner square is covered by exactly one rim, so no faces overlap.
func _add_roof_rim(tiles: PackedByteArray, from: int, to: int, line: int, side: int, horizontal: bool,
		floor_index: int) -> void:
	var t := BuildGrid.TILE_SIZE
	var half := TerminalWallsScript.HALF
	var start := float(from) * t
	var end := float(to) * t
	if horizontal:
		start -= _rim_extension(tiles, from - 1, line, side)
		end += _rim_extension(tiles, to, line, side)
	var edge := float(line + (1 if side > 0 else 0)) * t
	var across_lo := edge if side > 0 else edge - half
	var o := BuildGrid.origin
	var y_lo := BuildGrid.get_floor_height(floor_index) + ROOF_BOTTOM
	var y_hi := y_lo + ROOF_THICKNESS
	var lo: Vector3
	var hi: Vector3
	if horizontal:
		lo = Vector3(o.x + start, y_lo, o.z + across_lo)
		hi = Vector3(o.x + end, y_hi, o.z + across_lo + half)
	else:
		lo = Vector3(o.x + across_lo, y_lo, o.z + start)
		hi = Vector3(o.x + across_lo + half, y_hi, o.z + end)
	_roof_mesh.add_box(lo, hi, ROOF_SIDE_COLOR, ROOF_TOP_COLOR, true)


## How far a horizontal rim reaches past its end, where the next tile along the
## row is (x, y): over an outer corner it covers the corner square (+half), at an
## inner corner it stops short of the vertical rim there (-half), and where the
## edge simply carries on into the next chunk it stays put (0).
func _rim_extension(tiles: PackedByteArray, x: int, y: int, side: int) -> float:
	if not _is_filled(tiles, x, y):
		return TerminalWallsScript.HALF
	if _is_filled(tiles, x, y + side):
		return -TerminalWallsScript.HALF
	return 0.0


func _apply_chunk_mesh(key: Vector3i) -> void:
	_apply_mesh(_chunks, key, _mesh, _material, self, "Chunk")
	_apply_mesh(_roof_chunks, key, _roof_mesh, _roof_material, _roofs, "Roof")


func _apply_mesh(chunks: Dictionary, key: Vector3i, builder: RefCounted, material: Material,
		parent: Node3D, prefix: String) -> void:
	var mi: MeshInstance3D = chunks.get(key)
	if builder.is_empty():
		if mi:
			mi.queue_free()
			chunks.erase(key)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "%s_%d_%d_%d" % [prefix, key.x, key.y, key.z]
		mi.material_override = material
		parent.add_child(mi)
		chunks[key] = mi
	mi.mesh = builder.commit()
