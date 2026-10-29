extends "res://scripts/building/build_tool.gd"
## Door tool (checklist step 9): turns wall pieces into doorways.
##
##   Left click           turn the wall piece under the mouse into a doorway
##   Shift + left click   turn a doorway back into wall
## The ghost sits on the tile edge nearest the mouse: green over a wall piece,
## red where there is no wall. With Shift held it shows red over doorways only.
## The mouse is read just below the cutaway wall height, so pointing at a wall's side picks it.
## Each click is a SetDoorCommand, which pays for the door (checklist step 14);
## the ghost is red when there isn't enough money.

const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const SetDoorCommandScript := preload("res://scripts/core/commands/set_door_command.gd")
const GHOST_GROW := 0.08

## The TerminalWalls node (terminal_walls.gd).
@export var terminal_walls: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _ghost: MeshInstance3D
var _edge := {"corner": Vector2i.ZERO, "horizontal": true}
var _has_edge := false
var _removing := false


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = make_ghost(box)


func _process(_delta: float) -> void:
	if not is_active():
		return
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	# Pick a little below the cutaway height, so pointing at the side of a wall
	# finds that wall whether it is lowered or not.
	var pick := mouse_pick(TerminalWallsScript.CUT_HEIGHT * 0.8)
	_has_edge = false
	if pick.hit:
		_edge = BuildGrid.world_to_edge(pick.position)
		_has_edge = terminal_walls.is_valid_edge(_edge.corner, _edge.horizontal)
	_update_ghost()


func deactivate() -> void:
	_ghost.visible = false


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _has_edge:
		return
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	var command := SetDoorCommandScript.new(_edge.corner, _edge.horizontal, not _removing, get_floor())
	if command.preview(command_runner).ok and command_runner.submit(command):
		var counts: Dictionary = terminal_walls.get_piece_counts(get_floor())
		print("BUILD | %s at corner %s, %s (total %d walls, %d doors)" % [
			"wall restored" if _removing else "door placed", _edge.corner,
			"horizontal" if _edge.horizontal else "vertical", counts.walls, counts.doors])


func get_hint() -> String:
	return "Click a wall: add door (%s)   Shift + click a door: back to wall   Right click / Esc: cancel" % \
		Money.format(Money.settings.door_cost)


func _update_ghost() -> void:
	var piece: int = terminal_walls.get_edge(_edge.corner, _edge.horizontal, get_floor()) if _has_edge \
		else TerminalWallsScript.Piece.NONE
	var shown := _has_edge and (not _removing or piece == TerminalWallsScript.Piece.DOOR)
	_ghost.visible = shown
	if not shown:
		return
	var corner: Vector2i = _edge.corner
	var a := BuildGrid.tile_corner_to_world(corner, get_floor())
	var b := BuildGrid.tile_corner_to_world(corner + (Vector2i(1, 0) if _edge.horizontal else Vector2i(0, 1)), get_floor())
	var thickness := TerminalWallsScript.THICKNESS + GHOST_GROW * 2.0
	var height := TerminalWallsScript.DOOR_HEIGHT
	var length := TerminalWallsScript.DOOR_WIDTH
	_ghost.global_position = (a + b) * 0.5 + Vector3.UP * height * 0.5
	_ghost.scale = Vector3(length, height, thickness) if _edge.horizontal else Vector3(thickness, height, length)
	_ghost.material_override = ghost_material(not _removing and piece == TerminalWallsScript.Piece.WALL
		and Money.can_afford(Money.settings.door_cost))
