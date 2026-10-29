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
## Keep this node at the world origin: meshes are built in world coordinates.

## Emitted after tiles change. rect is the area that was edited, in tiles.
signal floor_changed(rect: Rect2i, floor_index: int)

const FLOOR_SHADER := preload("res://materials/terminal_floor.gdshader")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")
## Chunk size in tiles. Bigger chunks mean fewer draw calls, smaller ones cheaper rebuilds.
const CHUNK_TILES := 32
## Thickness of the floor slab in metres. Things standing on the floor sit this high.
const THICKNESS := 0.1

## Per floor index: one byte per plot tile, 1 = floor.
var _tiles := {}
## Vector3i(chunk x, chunk y, floor index) -> MeshInstance3D
var _chunks := {}
var _material: ShaderMaterial
## Reused by every chunk rebuild.
var _mesh := MeshBuilderScript.new()


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = FLOOR_SHADER
	_material.set_shader_parameter("tile_size", BuildGrid.TILE_SIZE)


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
		return area if filled else 0
	var tiles: PackedByteArray = _tiles[floor_index]
	var floored := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			floored += tiles[row + x]
	return area - floored if filled else floored


## Total floor tiles on a floor.
func get_floor_tile_count(floor_index := 0) -> int:
	if not _tiles.has(floor_index):
		return 0
	return (_tiles[floor_index] as PackedByteArray).count(1)


# --- Editing --------------------------------------------------------------------

## Lays floor on (filled = true) or removes it from every tile in rect.
## Returns how many tiles changed.
func set_rect(rect: Rect2i, filled: bool, floor_index := 0) -> int:
	rect = _clip_to_plot(rect)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0
	var tiles := _get_tiles(floor_index)
	var value := 1 if filled else 0
	var changed := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			if tiles[row + x] != value:
				tiles[row + x] = value
				changed += 1
	_tiles[floor_index] = tiles  # PackedByteArray is copied on assignment
	if changed == 0:
		return 0

	# Rebuild every chunk the rect touches, plus neighbours whose slab sides
	# may now be hidden or exposed.
	@warning_ignore("integer_division")
	var first := Vector2i((rect.position.x - 1) / CHUNK_TILES, (rect.position.y - 1) / CHUNK_TILES)
	@warning_ignore("integer_division")
	var last := Vector2i(rect.end.x / CHUNK_TILES, rect.end.y / CHUNK_TILES)
	for cy in range(maxi(first.y, 0), last.y + 1):
		for cx in range(maxi(first.x, 0), last.x + 1):
			_rebuild_chunk(Vector3i(cx, cy, floor_index))
	floor_changed.emit(rect, floor_index)
	return changed


# --- Meshing --------------------------------------------------------------------

func _get_tiles(floor_index: int) -> PackedByteArray:
	if not _tiles.has(floor_index):
		var tiles := PackedByteArray()
		tiles.resize(BuildGrid.get_tile_count())
		_tiles[floor_index] = tiles
	return _tiles[floor_index]


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
