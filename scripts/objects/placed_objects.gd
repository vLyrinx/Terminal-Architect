class_name PlacedObjects
extends Node3D
## Placed objects (checklist step 11): desks, seats, scanners and so on.
##
## Each object has a stable unique ID (never reused), the ID of its definition
## in the ObjectCatalog, and its exact position and rotation. The tiles it
## blocks are worked out from its real footprint at that position and rotation,
## not from grid steps, so free placement and free rotation can come later
## without a rewrite.
##
## Change objects through commands (CommandRunner) rather than calling
## add_object(), remove_object() or move_object() directly, so every change can
## be undone, saved and shared.
##
## Keep this node at the world origin.

signal object_added(id: int)
signal object_removed(id: int)
signal object_moved(id: int)

const PlacedObjectScript := preload("res://scripts/objects/placed_object.gd")
const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
## A tile counts as blocked when its centre is inside the footprint by more than this.
const FOOTPRINT_EPSILON := 0.01

## The TerminalFloor node (terminal_floor.gd).
@export var terminal_floor: Node3D
## The TerminalWalls node (terminal_walls.gd).
@export var terminal_walls: Node3D

## ID for the next new object. IDs start at 1; 0 means "no object".
var next_id := 1

## id -> PlacedObject
var _objects := {}
## floor index -> {Vector2i tile: object id}
var _occupancy := {}


# --- Queries --------------------------------------------------------------------

## The PlacedObject with this ID, or null.
func get_object(id: int) -> PlacedObjectScript:
	return _objects.get(id)


## ID of the object blocking a tile, or 0.
func get_object_at(tile: Vector2i, floor_index := 0) -> int:
	return _get_occupancy(floor_index).get(tile, 0)


func get_count() -> int:
	return _objects.size()


func get_ids() -> Array:
	return _objects.keys()


## Tiles a footprint blocks at an exact position and rotation: every tile whose
## centre lies inside the rotated footprint rectangle. On the grid at 90 degree
## steps this is exactly the footprint; off the grid it still works.
func footprint_tiles(def: Resource, pos: Vector3, yaw: float) -> Array[Vector2i]:
	var half := Vector2(def.footprint) * BuildGrid.TILE_SIZE * 0.5
	var c := cos(yaw)
	var s := sin(yaw)
	var extent := Vector2(absf(half.x * c) + absf(half.y * s), absf(half.x * s) + absf(half.y * c))
	var lo := BuildGrid.world_to_tile(pos - Vector3(extent.x, 0.0, extent.y))
	var hi := BuildGrid.world_to_tile(pos + Vector3(extent.x, 0.0, extent.y))
	var tiles: Array[Vector2i] = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var centre := BuildGrid.tile_to_world(Vector2i(x, y))
			var d := Vector2(centre.x - pos.x, centre.z - pos.z)
			# Into the object's own frame (undo its rotation around Y).
			var local := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
			if absf(local.x) < half.x - FOOTPRINT_EPSILON and absf(local.y) < half.y - FOOTPRINT_EPSILON:
				tiles.append(Vector2i(x, y))
	return tiles


## Why an object can't go here, or "" if it can. ignore_id lets an object being
## moved or rotated overlap its own old tiles.
func check_placement(def: Resource, pos: Vector3, yaw: float, floor_index := 0, ignore_id := 0) -> String:
	if def == null:
		return "Unknown object"
	var tiles := footprint_tiles(def, pos, yaw)
	if tiles.is_empty():
		return "No footprint"
	var occupancy := _get_occupancy(floor_index)
	var tile_set := {}
	for tile in tiles:
		if not BuildGrid.is_in_plot(tile):
			return "Outside the plot"
		if def.requires_floor and (terminal_floor == null or not terminal_floor.has_floor(tile, floor_index)):
			return "Needs terminal floor"
		var other: int = occupancy.get(tile, 0)
		if other != 0 and other != ignore_id:
			return "Blocked by another object"
		tile_set[tile] = true
	# A wall or door between two of the object's own tiles would cut through it.
	# Walls along the outside of the footprint are fine.
	if terminal_walls:
		for tile in tiles:
			var right := tile + Vector2i(1, 0)
			var below := tile + Vector2i(0, 1)
			if tile_set.has(right) and terminal_walls.get_edge(right, false, floor_index) != TerminalWallsScript.Piece.NONE:
				return "Blocked by a wall"
			if tile_set.has(below) and terminal_walls.get_edge(below, true, floor_index) != TerminalWallsScript.Piece.NONE:
				return "Blocked by a wall"
	return ""


## True if a tile edge lies inside an object (both tiles beside it belong to the
## same object). Walls can't be built there.
func is_edge_inside_object(corner: Vector2i, horizontal: bool, floor_index := 0) -> bool:
	var a := corner - (Vector2i(0, 1) if horizontal else Vector2i(1, 0))
	var occupancy := _get_occupancy(floor_index)
	var id: int = occupancy.get(a, 0)
	return id != 0 and occupancy.get(corner, 0) == id


## Grid-snapped position for an object centred near a world point: the
## footprint lines up with the tiles at 90 degree rotations.
func snap_position(def: Resource, world_pos: Vector3, yaw: float, floor_index := 0) -> Vector3:
	var size := _rotated_size(def, yaw)
	var t := BuildGrid.TILE_SIZE
	var o := BuildGrid.origin
	var start := Vector2(roundf((world_pos.x - o.x) / t - size.x * 0.5), roundf((world_pos.z - o.z) / t - size.y * 0.5))
	var centre := Vector3(o.x + (start.x + size.x * 0.5) * t, 0.0, o.z + (start.y + size.y * 0.5) * t)
	centre.y = _surface_height(def, centre, floor_index)
	return centre


## Position after turning an object in place to new_rotation, so it stays on the
## grid and four quarter turns bring it back where it started. Square footprints
## turn around their centre; others turn around the tile nearest their centre.
func rotate_in_place(def: Resource, pos: Vector3, yaw: float, new_rotation: float) -> Vector3:
	var fp: Vector2i = def.footprint
	var pivot_offset := Vector2.ZERO
	if fp.x != fp.y:
		pivot_offset = Vector2(0.0 if fp.x % 2 == 1 else -0.5, 0.0 if fp.y % 2 == 1 else -0.5) * BuildGrid.TILE_SIZE
	var pivot := pos + _rotate_local(pivot_offset, yaw)
	return pivot - _rotate_local(pivot_offset, new_rotation)


# --- Changes (use commands) -------------------------------------------------------

## Adds an object without checking placement (commands check first).
## Pass id to restore a known object (undo, load); 0 gives it a new ID.
## Returns the object's ID, or 0 on failure.
func add_object(def_id: StringName, pos: Vector3, yaw: float, floor_index := 0, id := 0) -> int:
	var def := ObjectCatalog.get_def(def_id)
	if def == null:
		push_error("PlacedObjects: unknown object %s" % def_id)
		return 0
	if id <= 0:
		id = next_id
	if _objects.has(id):
		push_error("PlacedObjects: ID %d is already in use" % id)
		return 0
	next_id = maxi(next_id, id + 1)

	var obj := PlacedObjectScript.new()
	obj.id = id
	obj.def_id = def_id
	obj.floor_index = floor_index
	obj.node = def.model.instantiate()
	obj.node.name = "Object_%d" % id
	add_child(obj.node)
	_objects[id] = obj
	_set_transform(obj, def, pos, yaw)
	object_added.emit(id)
	return id


## Removes an object. Returns its record (for undo), or null if there was none.
func remove_object(id: int) -> PlacedObjectScript:
	var obj := get_object(id)
	if obj == null:
		return null
	_clear_tiles(obj)
	obj.node.queue_free()
	obj.node = null
	_objects.erase(id)
	object_removed.emit(id)
	return obj


## Moves and/or rotates an object without checking placement (commands check first).
func move_object(id: int, pos: Vector3, yaw: float) -> void:
	var obj := get_object(id)
	if obj == null:
		return
	_clear_tiles(obj)
	_set_transform(obj, ObjectCatalog.get_def(obj.def_id), pos, yaw)
	object_moved.emit(id)


## Draws a highlight over an object (null removes it).
func set_highlight(id: int, material: Material) -> void:
	var obj := get_object(id)
	if obj and obj.node:
		_set_overlay(obj.node, material)


# --- Internals ------------------------------------------------------------------

func _get_occupancy(floor_index: int) -> Dictionary:
	if not _occupancy.has(floor_index):
		_occupancy[floor_index] = {}
	return _occupancy[floor_index]


func _set_transform(obj: PlacedObjectScript, def: Resource, pos: Vector3, yaw: float) -> void:
	obj.position = pos
	obj.rotation = yaw
	obj.tiles = footprint_tiles(def, pos, yaw)
	var occupancy := _get_occupancy(obj.floor_index)
	for tile in obj.tiles:
		occupancy[tile] = obj.id
	obj.node.position = pos
	obj.node.rotation = Vector3(0.0, yaw, 0.0)


func _clear_tiles(obj: PlacedObjectScript) -> void:
	var occupancy := _get_occupancy(obj.floor_index)
	for tile in obj.tiles:
		if occupancy.get(tile, 0) == obj.id:
			occupancy.erase(tile)
	obj.tiles.clear()


## Footprint size in tiles along world X and Z at a rotation.
func _rotated_size(def: Resource, yaw: float) -> Vector2:
	var fp := Vector2(def.footprint)
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return Vector2(fp.x * c + fp.y * s, fp.x * s + fp.y * c)


## A local X/Z offset turned to world space by a rotation around Y.
func _rotate_local(offset: Vector2, yaw: float) -> Vector3:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector3(offset.x * c + offset.y * s, 0.0, -offset.x * s + offset.y * c)


func _surface_height(def: Resource, centre: Vector3, floor_index: int) -> float:
	if def.requires_floor:
		return BuildGrid.get_floor_height(floor_index) + TerminalFloorScript.THICKNESS
	if terminal_floor:
		return terminal_floor.get_surface_height(BuildGrid.world_to_tile(centre), floor_index)
	return BuildGrid.get_floor_height(floor_index)


func _set_overlay(node: Node, material: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_overlay = material
	for child in node.get_children():
		_set_overlay(child, material)
