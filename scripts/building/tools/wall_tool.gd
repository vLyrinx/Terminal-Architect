extends "res://scripts/building/build_tool.gd"
## Wall tool (checklist step 9): drag along tile edges to build straight walls.
##
##   Left drag            build a straight wall between two grid corners
##   Shift + left drag    remove walls and doors along the line
## The line snaps to whichever axis the mouse has moved further along. The ghost
## is a post on the nearest corner while hovering, then the whole wall while
## dragging: green when building, red when removing. Shift is read when the
## mouse button is released, so it can be pressed or let go mid-drag.

const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
## Ghost is a little bigger than the wall so it shows over existing walls.
const GHOST_GROW := 0.06

## The TerminalWalls node (terminal_walls.gd).
@export var terminal_walls: Node3D

var _ghost: MeshInstance3D
var _label: Label3D
var _dragging := false
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _hover_corner := Vector2i.ZERO
var _has_hover := false
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
	if not is_active():
		return
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	var pick := mouse_pick()
	_has_hover = pick.hit and pick.in_plot
	if pick.hit and (_has_hover or _dragging):
		_hover_corner = BuildGrid.clamp_corner_to_plot(BuildGrid.world_to_corner(pick.position))
		if _dragging:
			_end = _straighten(_hover_corner)
	_update_ghost()


func deactivate() -> void:
	_dragging = false
	_ghost.visible = false
	_label.visible = false


func press(_tile: Vector2i) -> void:
	var pick := mouse_pick()
	if not pick.hit:
		return
	_dragging = true
	_start = BuildGrid.clamp_corner_to_plot(BuildGrid.world_to_corner(pick.position))
	_end = _start


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _dragging:
		return
	_dragging = false
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	var changed: int = terminal_walls.set_run(_start, _end, not _removing, get_floor())
	var counts: Dictionary = terminal_walls.get_piece_counts(get_floor())
	print("BUILD | wall %s: %d pieces from corner %s to %s (total %d walls, %d doors)" % [
		"removed" if _removing else "built", changed, _start, _end, counts.walls, counts.doors])


func cancel_drag() -> void:
	_dragging = false


func get_hint() -> String:
	return "Drag along grid lines: build wall   Shift + drag: remove   Right click / Esc: cancel"


## Keeps the drag on one grid line: whichever axis the mouse moved further along.
func _straighten(corner: Vector2i) -> Vector2i:
	var d := corner - _start
	if absi(d.x) >= absi(d.y):
		return Vector2i(corner.x, _start.y)
	return Vector2i(_start.x, corner.y)


func _update_ghost() -> void:
	var shown := _dragging or _has_hover
	_ghost.visible = shown
	_label.visible = shown and _dragging and _start != _end
	if not shown:
		return
	var a := _start if _dragging else _hover_corner
	var b := _end if _dragging else _hover_corner
	var lo := BuildGrid.tile_corner_to_world(a.min(b), get_floor())
	var hi := BuildGrid.tile_corner_to_world(a.max(b), get_floor())
	var half := TerminalWallsScript.HALF + GHOST_GROW
	var height := TerminalWallsScript.HEIGHT + GHOST_GROW
	var size := Vector3(hi.x - lo.x + half * 2.0, height, hi.z - lo.z + half * 2.0)
	_ghost.global_position = (lo + hi) * 0.5 + Vector3.UP * height * 0.5
	_ghost.scale = size
	_ghost.material_override = ghost_material(not _removing)

	if _label.visible:
		var changes: int = terminal_walls.count_run_changes(_start, _end, not _removing, get_floor())
		var length := maxi(absi(_end.x - _start.x), absi(_end.y - _start.y))
		_label.text = "%d m   %s %d" % [length, "remove" if _removing else "build", changes]
		_label.modulate = Color(1.0, 0.75, 0.75) if _removing else Color.WHITE
		_label.global_position = (lo + hi) * 0.5 + Vector3.UP * (height + 0.8)
