extends "res://scripts/building/build_tool.gd"
## Floor tool (checklist step 8): lays and removes terminal floor tiles.
##
##   Left drag            lay floor in the rectangle
##   Shift + left drag    remove floor in the rectangle
## The ghost is green when laying and red when removing, and a label shows
## the rectangle size and the price (or refund). Shift is read when the mouse
## button is released, so it can be pressed or let go mid-drag.
## Changes go through a SetFloorCommand, which pays for them (checklist step 14).

const SetFloorCommandScript := preload("res://scripts/core/commands/set_floor_command.gd")
## Ghost is a little taller than the floor so it shows on top of existing tiles.
const GHOST_EXTRA_HEIGHT := 0.05
const NO_TILE := Vector2i(-1, -1)

## The TerminalFloor node (terminal_floor.gd).
@export var terminal_floor: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _ghost: MeshInstance3D
var _label: Label3D
var _dragging := false
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _hover_tile := NO_TILE
var _hover_in_plot := false
var _removing := false


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = make_ghost(box)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	_label.visible = false
	add_child(_label)


func _process(_delta: float) -> void:
	if manager == null or manager.active_tool != self:
		return
	var removing := Input.is_physical_key_pressed(KEY_SHIFT)
	if removing != _removing:
		_removing = removing
		_update_ghost()


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
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	var rect := BuildGrid.rect_from_tiles(_start, _end)
	var command := SetFloorCommandScript.new(rect, not _removing, get_floor())
	if command.preview(command_runner).tiles > 0 and command_runner.submit(command):
		print("BUILD | floor %s in %d x %d (total %d)" % [
			"removed" if _removing else "laid", rect.size.x, rect.size.y,
			terminal_floor.get_floor_tile_count(get_floor())])
	_hover_tile = tile
	_hover_in_plot = in_plot
	_update_ghost()


func cancel_drag() -> void:
	_dragging = false
	_update_ghost()


func get_hint() -> String:
	return "Drag: lay floor   Shift + drag: remove   Right click / Esc: cancel"


func get_cost_text() -> String:
	return "%s / tile" % Money.format(Money.settings.floor_tile_cost)


func _update_ghost() -> void:
	var shown := _dragging or _hover_in_plot
	_ghost.visible = shown
	_label.visible = shown and _dragging
	if not shown:
		return
	var rect := BuildGrid.rect_from_tiles(_start, _end) if _dragging else Rect2i(_hover_tile, Vector2i.ONE)
	var height: float = terminal_floor.THICKNESS + GHOST_EXTRA_HEIGHT
	var corner := BuildGrid.tile_corner_to_world(rect.position, get_floor())
	var size := Vector3(rect.size.x, 0.0, rect.size.y) * BuildGrid.TILE_SIZE
	_ghost.global_position = corner + size * 0.5 + Vector3.UP * height * 0.5
	_ghost.scale = Vector3(size.x, height, size.z)
	_ghost.material_override = ghost_material(not _removing)

	if _dragging:
		var p := SetFloorCommandScript.new(rect, not _removing, get_floor()).preview(command_runner)
		var affordable := Money.can_afford(-p.amount)
		_label.text = "%d x %d   %s %d   %s" % [rect.size.x, rect.size.y, "remove" if _removing else "lay",
			p.tiles, price_text(p.amount)]
		_label.modulate = Color.WHITE if affordable and not _removing else Color(1.0, 0.75, 0.75)
		_label.global_position = corner + size * 0.5 + Vector3.UP * 1.5
		if not affordable:
			_ghost.material_override = ghost_material(false)
