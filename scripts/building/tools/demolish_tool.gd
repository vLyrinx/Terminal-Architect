extends "res://scripts/building/build_tool.gd"
## Demolish tool (checklist step 15): drag a rectangle to clear everything in it.
##
##   Left drag (or click)   remove runways, taxiways, stands, objects, walls, doors and floor in the rectangle
## Any stand, runway or taxiway piece the rectangle touches goes first, whole
## (one DeleteStandCommand, DeleteRunwayCommand or DeleteTaxiwayCommand each,
## checklist steps 16 to 18).
## Objects go next (one DeleteObjectCommand each), then every wall piece on
## the rectangle's grid lines, edges included (one SetWallsCommand), then the
## floor (one SetFloorCommand), which also clears its zones. Each part refunds
## part of its price (EconomySettings.sale_refund). The red ghost's label shows
## what will go and the refund.

const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const DeleteObjectCommandScript := preload("res://scripts/core/commands/delete_object_command.gd")
const SetWallsCommandScript := preload("res://scripts/core/commands/set_walls_command.gd")
const SetFloorCommandScript := preload("res://scripts/core/commands/set_floor_command.gd")
const DeleteRunwayCommandScript := preload("res://scripts/core/commands/delete_runway_command.gd")
const DeleteTaxiwayCommandScript := preload("res://scripts/core/commands/delete_taxiway_command.gd")
const DeleteStandCommandScript := preload("res://scripts/core/commands/delete_stand_command.gd")
const GHOST_HEIGHT := 0.3
const NO_TILE := Vector2i(-1, -1)

## The PlacedObjects node (placed_objects.gd).
@export var placed_objects: Node3D
## The TerminalFloor node (terminal_floor.gd).
@export var terminal_floor: Node3D
## The TerminalWalls node (terminal_walls.gd).
@export var terminal_walls: Node3D
## The Runways node (runways.gd).
@export var runways: Node3D
## The Taxiways node (taxiways.gd).
@export var taxiways: Node3D
## The Stands node (stands.gd).
@export var stands: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _ghost: MeshInstance3D
var _label: Label3D
var _dragging := false
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _hover_tile := NO_TILE
var _hover_in_plot := false


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = make_ghost(box)
	_ghost.material_override = ghost_material(false)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	_label.visible = false
	add_child(_label)


func deactivate() -> void:
	_dragging = false
	_ghost.visible = false
	_label.visible = false


func hover(tile: Vector2i, in_plot: bool) -> void:
	_hover_tile = tile
	_hover_in_plot = in_plot
	_update_ghost()


func press(tile: Vector2i) -> void:
	_dragging = true
	_start = tile
	_end = tile
	_update_ghost()


func drag(tile: Vector2i, in_plot: bool) -> void:
	# Off the plot the rectangle stops at the plot edge; over the UI it keeps its last size.
	if in_plot:
		_end = tile
	elif tile != NO_TILE:
		_end = BuildGrid.clamp_to_plot(tile)
	_update_ghost()


func release(tile: Vector2i, in_plot: bool) -> void:
	drag(tile, in_plot)
	_dragging = false
	var rect := BuildGrid.rect_from_tiles(_start, _end)
	var p := _preview(rect)
	if p.stands.size() + p.runways.size() + p.taxiways.size() + p.objects.size() + p.walls + p.floor > 0:
		for id: int in p.stands:
			command_runner.submit(DeleteStandCommandScript.new(id))
		for id: int in p.runways:
			command_runner.submit(DeleteRunwayCommandScript.new(id))
		for id: int in p.taxiways:
			command_runner.submit(DeleteTaxiwayCommandScript.new(id))
		for id: int in p.objects:
			command_runner.submit(DeleteObjectCommandScript.new(id))
		if p.walls > 0:
			command_runner.submit(SetWallsCommandScript.new(_wall_runs(rect), false, get_floor()))
		if p.floor > 0:
			command_runner.submit(SetFloorCommandScript.new(rect, false, get_floor()))
		print("BUILD | demolished %d stands, %d runways, %d taxiways, %d objects, %d walls, %d floor tiles in %d x %d" % [
			p.stands.size(), p.runways.size(), p.taxiways.size(), p.objects.size(), p.walls, p.floor, rect.size.x, rect.size.y])
	_hover_tile = tile
	_hover_in_plot = in_plot
	_update_ghost()


func cancel_drag() -> void:
	_dragging = false
	_update_ghost()


func get_hint() -> String:
	return "Drag: remove runways, taxiways, stands, objects, walls and floor   Refunds %d%%   Right click / Esc: cancel" % \
		roundi(Money.settings.sale_refund * 100.0)


func get_cost_text() -> String:
	return "Refund %d%%" % roundi(Money.settings.sale_refund * 100.0)


## What demolishing rect would remove: {"stands", "runways", "taxiways": IDs, "objects":
## object IDs, "walls": wall pieces, "floor": floor tiles, "refund": money back}.
## Counts use whole-row and per-object checks rather than visiting every tile,
## so dragging across a large part of the 4.5 km plot stays smooth. The refund
## counts doors as plain wall, so it can be slightly low.
func _preview(rect: Rect2i) -> Dictionary:
	var object_ids: Array[int] = []
	var value := 0
	for id: int in placed_objects.get_ids():
		var obj: RefCounted = placed_objects.get_object(id)
		if obj.floor_index == get_floor() and obj.tiles.any(func(t: Vector2i) -> bool: return rect.has_point(t)):
			object_ids.append(id)
			var def := ObjectCatalog.get_def(obj.def_id)
			value += def.cost if def else 0
	var tiles: int = terminal_floor.count_floor_tiles(rect, get_floor())
	var walls: int = terminal_walls.count_pieces_in(rect, get_floor())
	value += tiles * Money.settings.floor_tile_cost + walls * Money.settings.wall_cost
	var refund := Money.refund_for(value)
	var runway_ids: Array[int] = runways.get_runways_in(rect) if runways else ([] as Array[int])
	for id in runway_ids:
		refund += DeleteRunwayCommandScript.new(id).preview(command_runner)
	var taxiway_ids: Array[int] = taxiways.get_taxiways_in(rect) if taxiways else ([] as Array[int])
	for id in taxiway_ids:
		refund += DeleteTaxiwayCommandScript.new(id).preview(command_runner)
	var stand_ids: Array[int] = stands.get_stands_in(rect) if stands else ([] as Array[int])
	for id in stand_ids:
		refund += DeleteStandCommandScript.new(id).preview(command_runner)
	return {"stands": stand_ids, "runways": runway_ids, "taxiways": taxiway_ids, "objects": object_ids, "walls": walls, "floor": tiles, "refund": refund}


## Every grid line inside rect, edges included, as wall runs.
func _wall_runs(rect: Rect2i) -> Array:
	var runs := []
	for y in range(rect.position.y, rect.end.y + 1):
		runs.append([Vector2i(rect.position.x, y), Vector2i(rect.end.x, y)])
	for x in range(rect.position.x, rect.end.x + 1):
		runs.append([Vector2i(x, rect.position.y), Vector2i(x, rect.end.y)])
	return runs


func _update_ghost() -> void:
	var shown := _dragging or _hover_in_plot
	_ghost.visible = shown
	_label.visible = shown and _dragging
	if not shown:
		return
	var rect := BuildGrid.rect_from_tiles(_start, _end) if _dragging else Rect2i(_hover_tile, Vector2i.ONE)
	var corner := BuildGrid.tile_corner_to_world(rect.position, get_floor())
	var size := Vector3(rect.size.x, 0.0, rect.size.y) * BuildGrid.TILE_SIZE
	_ghost.global_position = corner + size * 0.5 + Vector3.UP * GHOST_HEIGHT * 0.5
	_ghost.scale = Vector3(size.x + 0.1, GHOST_HEIGHT, size.z + 0.1)

	if _dragging:
		var p := _preview(rect)
		var parts: Array[String] = []
		if p.stands.size() > 0:
			parts.append("%d stand%s" % [p.stands.size(), "s" if p.stands.size() > 1 else ""])
		if p.runways.size() > 0:
			parts.append("%d runway%s" % [p.runways.size(), "s" if p.runways.size() > 1 else ""])
		if p.taxiways.size() > 0:
			parts.append("%d taxiway%s" % [p.taxiways.size(), "s" if p.taxiways.size() > 1 else ""])
		if p.objects.size() > 0:
			parts.append("%d objects" % p.objects.size())
		if p.walls > 0:
			parts.append("%d walls" % p.walls)
		if p.floor > 0:
			parts.append("%d floor" % p.floor)
		_label.text = "%d x %d   %s" % [rect.size.x, rect.size.y,
			"nothing to remove" if parts.is_empty() else "%s   %s" % [", ".join(parts), price_text(p.refund)]]
		_label.modulate = Color(1.0, 0.75, 0.75)
		_label.global_position = corner + size * 0.5 + Vector3.UP * (TerminalWallsScript.HEIGHT + 0.8)
