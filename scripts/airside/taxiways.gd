extends Node3D
## Taxiways (checklist step 17): taxiway paving, laid tile by tile like floor.
##
## Stores which plot tiles are paved and draws them, in chunks of CHUNK_TILES
## x CHUNK_TILES tiles with filled tiles merged into as few rectangles as
## possible (the same approach as terminal_floor.gd). Paving is laid and
## removed in rectangles, 1 m at a time, so it can be fitted closely around
## buildings. It is never laid on runways, stands, runway ramps or terminal
## floor; those tiles are skipped.
## As in Airport CEO, paving is only the ground: aircraft follow the taxi
## lines painted on it (taxi_lines.gd), and how wide the paving is around a
## line decides which aircraft it takes (TaxiwayDef.width). TaxiLines and
## Stands check again on paving_changed. Changes come from SetPavingCommand.
##
## Keep this node at the world origin: meshes are built in world coordinates.

## Emitted after tiles change. rect is the area that was edited, in tiles.
signal paving_changed(rect: Rect2i)

const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")
## Chunk size in tiles. Paving covers large areas, so chunks are bigger than floor chunks.
const CHUNK_TILES := 64
## Lower than runway paving (runways.gd PAVING_HEIGHT), so runways draw on top where they touch.
const PAVING_HEIGHT := 0.025
## Taxi lines (taxi_lines.gd) sit this far above the paving.
const MARKING_LIFT := 0.01
const PAVING_COLOR := Color(0.33, 0.35, 0.38)
const PAVING_SIDE_COLOR := Color(0.25, 0.27, 0.3)

## The TerminalFloor node (terminal_floor.gd). Paving isn't laid on floor.
@export var terminal_floor: Node3D
## The Runways node (runways.gd). Paving isn't laid on runways.
@export var runways: Node3D
## Optional Stands node (stands.gd). Paving isn't laid on stands.
@export var stands: Node3D
## Optional Ramps node (ramps.gd). Paving isn't laid on runway ramps.
@export var ramps: Node3D

## One byte per plot tile, 1 = paved.
var _tiles := PackedByteArray()
## Vector2i(chunk x, chunk y) -> MeshInstance3D
var _chunks := {}
var _mesh := MeshBuilderScript.new()
static var _material: StandardMaterial3D


func _ready() -> void:
	_tiles.resize(BuildGrid.get_tile_count())
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95


# --- Queries --------------------------------------------------------------------

func is_paved(tile: Vector2i) -> bool:
	var index := BuildGrid.tile_to_index(tile)
	return index >= 0 and _tiles[index] == 1


## True if a grid-corner position (in tiles, may be fractional) is on paving.
func is_paved_at(corner: Vector2) -> bool:
	return is_paved(Vector2i(floori(corner.x), floori(corner.y)))


## How many tiles of rect are paved.
func count_paved_in(rect: Rect2i) -> int:
	rect = _clip_to_plot(rect)
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		count += _tiles.slice(row + rect.position.x, row + rect.end.x).count(1)
	return count


## Total paved tiles.
func get_paved_count() -> int:
	return _tiles.count(1)


## Number of tiles in rect that would change if it were paved (or cleared).
func count_changes(rect: Rect2i, paved: bool) -> int:
	rect = _clip_to_plot(rect)
	if not paved:
		return count_paved_in(rect)
	var blocked := _blockers(rect)
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			if _tiles[row + x] == 0 and not _is_blocked(Vector2i(x, y), blocked):
				count += 1
	return count


# --- Editing --------------------------------------------------------------------

## Paves (paved = true) or clears every tile in rect, skipping tiles that
## can't be paved. Returns how many tiles changed.
func set_rect(rect: Rect2i, paved: bool) -> int:
	rect = _clip_to_plot(rect)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0
	var value := 1 if paved else 0
	var blocked := _blockers(rect) if paved else {}
	var changed := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			if _tiles[row + x] == value or (paved and _is_blocked(Vector2i(x, y), blocked)):
				continue
			_tiles[row + x] = value
			changed += 1
	if changed > 0:
		_tiles_changed(rect)
	return changed


## The tiles in rect (clipped to the plot), one byte each, row by row: saved
## by commands so undo can put them back with set_rect_state().
func get_rect_state(rect: Rect2i) -> PackedByteArray:
	rect = _clip_to_plot(rect)
	var state := PackedByteArray()
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		state.append_array(_tiles.slice(row + rect.position.x, row + rect.end.x))
	return state


## Puts back tiles saved by get_rect_state() for the same rect.
func set_rect_state(rect: Rect2i, state: PackedByteArray) -> void:
	rect = _clip_to_plot(rect)
	if state.size() != rect.get_area() or state.is_empty():
		return
	var i := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			_tiles[row + x] = state[i]
			i += 1
	_tiles_changed(rect)


## What stops paving inside rect: {"rects": runway and stand rectangles,
## "ramps": runway ramps whose paving box overlaps rect}.
func _blockers(rect: Rect2i) -> Dictionary:
	var rects: Array[Rect2i] = []
	if runways:
		rects.append_array(runways.get_rects_in(rect))
	if stands:
		rects.append_array(stands.get_rects_in(rect))
	var ramp_list := []
	if ramps:
		for id: int in ramps.get_ramps_in(rect):
			ramp_list.append(ramps.get_ramp(id))
	return {"rects": rects, "ramps": ramp_list}


func _is_blocked(tile: Vector2i, blocked: Dictionary) -> bool:
	for r: Rect2i in blocked.get("rects", []):
		if r.has_point(tile):
			return true
	for ramp: RefCounted in blocked.get("ramps", []):
		if ramp.rect.has_point(tile) and ramp.covers(Vector2(tile) + Vector2(0.5, 0.5), 0.0):
			return true
	return terminal_floor != null and terminal_floor.has_floor(tile)


func _clip_to_plot(rect: Rect2i) -> Rect2i:
	return rect.intersection(Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES))


# --- Mesh -----------------------------------------------------------------------

## Rebuilds every chunk rect touches and tells listeners.
func _tiles_changed(rect: Rect2i) -> void:
	@warning_ignore("integer_division")
	var first := Vector2i(rect.position.x / CHUNK_TILES, rect.position.y / CHUNK_TILES)
	@warning_ignore("integer_division")
	var last := Vector2i((rect.end.x - 1) / CHUNK_TILES, (rect.end.y - 1) / CHUNK_TILES)
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			_rebuild_chunk(Vector2i(cx, cy))
	paving_changed.emit(rect)


func _rebuild_chunk(key: Vector2i) -> void:
	var x0 := key.x * CHUNK_TILES
	var y0 := key.y * CHUNK_TILES
	var w := mini(CHUNK_TILES, BuildGrid.PLOT_TILES.x - x0)
	var h := mini(CHUNK_TILES, BuildGrid.PLOT_TILES.y - y0)
	_mesh.clear()
	# Greedy merge: 1 = paved, not yet covered by a rectangle; 2 = covered.
	var mask := PackedByteArray()
	mask.resize(w * h)
	for ly in h:
		var row := (y0 + ly) * BuildGrid.PLOT_TILES.x + x0
		for lx in w:
			mask[lx + ly * w] = _tiles[row + lx]
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
			var lo := BuildGrid.tile_corner_to_world(Vector2i(x0 + lx, y0 + ly))
			var hi := BuildGrid.tile_corner_to_world(Vector2i(x0 + lx + rw, y0 + ly + rh))
			_mesh.add_box(lo, Vector3(hi.x, PAVING_HEIGHT, hi.z), PAVING_SIDE_COLOR, PAVING_COLOR)
			lx += rw

	var mi: MeshInstance3D = _chunks.get(key)
	if _mesh.is_empty():
		if mi:
			mi.queue_free()
			_chunks.erase(key)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Paving_%d_%d" % [key.x, key.y]
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks[key] = mi
	mi.mesh = _mesh.commit()
