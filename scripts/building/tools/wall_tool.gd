extends "res://scripts/building/build_tool.gd"
## Wall tool (checklist step 9): builds walls along tile edges, in two modes.
##
##   Tab                  switch between Line and Room mode
## Line mode:
##   Left drag            build a straight wall between two grid corners
##   Shift + left drag    remove walls and doors along the line
## Room mode:
##   Left drag            drag a rectangle: lays floor inside and builds walls all round
##   Shift + left drag    remove the walls (and doors) around the rectangle; floor stays
##
## In Line mode the wall snaps to whichever axis the mouse has moved further
## along. The ghost is a post on the nearest corner while hovering, then the
## walls while dragging: green when building, red when removing. Shift is read
## when the mouse button is released, so it can be pressed or let go mid-drag.

enum Mode { LINE, ROOM }

const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
## Ghost is a little bigger than the wall so it shows over existing walls.
const GHOST_GROW := 0.06
const MODE_NAMES := ["Line", "Room"]

## The TerminalWalls node (terminal_walls.gd).
@export var terminal_walls: Node3D
## The TerminalFloor node (terminal_floor.gd), for laying room floors.
@export var terminal_floor: Node3D

var mode := Mode.LINE

## One ghost per side of a room; Line mode uses the first.
var _ghosts: Array[MeshInstance3D] = []
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
	for i in 4:
		_ghosts.append(make_ghost(box))

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
			_end = _straighten(_hover_corner) if mode == Mode.LINE else _hover_corner
	_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_TAB:
		mode = Mode.ROOM if mode == Mode.LINE else Mode.LINE
		if _dragging:
			_end = _straighten(_end) if mode == Mode.LINE else _hover_corner
		print("BUILD | walls: %s mode" % MODE_NAMES[mode])
		manager.tool_changed.emit(self)  # refreshes the hint
		get_viewport().set_input_as_handled()


func deactivate() -> void:
	_dragging = false
	for ghost in _ghosts:
		ghost.visible = false
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
	var changed := 0
	var floor_laid := 0
	if mode == Mode.LINE:
		changed = terminal_walls.set_run(_start, _end, not _removing, get_floor())
	else:
		var rect := _room_rect()
		if not _removing and rect.size.x > 0 and rect.size.y > 0:
			# Floor first, so the new walls know which side is inside.
			floor_laid = terminal_floor.set_rect(rect, true, get_floor())
		for side: Array in _room_sides():
			changed += terminal_walls.set_run(side[0], side[1], not _removing, get_floor())
	var counts: Dictionary = terminal_walls.get_piece_counts(get_floor())
	print("BUILD | %s %s: %d wall pieces%s from corner %s to %s (total %d walls, %d doors)" % [
		MODE_NAMES[mode].to_lower(), "removed" if _removing else "built", changed,
		", %d floor tiles" % floor_laid if floor_laid > 0 else "", _start, _end, counts.walls, counts.doors])


func cancel_drag() -> void:
	_dragging = false


func get_hint() -> String:
	if mode == Mode.LINE:
		return "Walls: Line mode (Tab: Room)   Drag along grid lines: build wall   Shift + drag: remove   Esc: cancel"
	return "Walls: Room mode (Tab: Line)   Drag a rectangle: floor + walls   Shift + drag: remove walls   Esc: cancel"


## Keeps the drag on one grid line: whichever axis the mouse moved further along.
func _straighten(corner: Vector2i) -> Vector2i:
	var d := corner - _start
	if absi(d.x) >= absi(d.y):
		return Vector2i(corner.x, _start.y)
	return Vector2i(_start.x, corner.y)


## Tiles inside the room being dragged.
func _room_rect() -> Rect2i:
	var lo := _start.min(_end)
	return Rect2i(lo, (_end - _start).abs())


## The four sides of the room as [from corner, to corner] pairs.
func _room_sides() -> Array:
	var lo := _start.min(_end)
	var hi := _start.max(_end)
	return [
		[lo, Vector2i(hi.x, lo.y)],
		[Vector2i(hi.x, lo.y), hi],
		[hi, Vector2i(lo.x, hi.y)],
		[Vector2i(lo.x, hi.y), lo],
	]


func _update_ghost() -> void:
	var shown := _dragging or _has_hover
	for ghost in _ghosts:
		ghost.visible = false
	_label.visible = shown and _dragging and _start != _end
	if not shown:
		return
	var material := ghost_material(not _removing)
	if not _dragging:
		_place_ghost(_ghosts[0], _hover_corner, _hover_corner, material)
		return

	var changes := 0
	if mode == Mode.LINE:
		_place_ghost(_ghosts[0], _start, _end, material)
		changes = terminal_walls.count_run_changes(_start, _end, not _removing, get_floor())
	else:
		var sides := _room_sides()
		for i in 4:
			_place_ghost(_ghosts[i], sides[i][0], sides[i][1], material)
			changes += terminal_walls.count_run_changes(sides[i][0], sides[i][1], not _removing, get_floor())

	if _label.visible:
		var size := (_end - _start).abs()
		var lo := BuildGrid.tile_corner_to_world(_start.min(_end), get_floor())
		var hi := BuildGrid.tile_corner_to_world(_start.max(_end), get_floor())
		var what := "%d m" % maxi(size.x, size.y) if mode == Mode.LINE else "%d x %d room" % [size.x, size.y]
		_label.text = "%s   %s %d" % [what, "remove" if _removing else "build", changes]
		_label.modulate = Color(1.0, 0.75, 0.75) if _removing else Color.WHITE
		_label.global_position = (lo + hi) * 0.5 + Vector3.UP * (TerminalWallsScript.HEIGHT + 0.8)


## Shows a ghost as a wall between two corners (a post if they are the same).
func _place_ghost(ghost: MeshInstance3D, a: Vector2i, b: Vector2i, material: Material) -> void:
	var lo := BuildGrid.tile_corner_to_world(a.min(b), get_floor())
	var hi := BuildGrid.tile_corner_to_world(a.max(b), get_floor())
	var half := TerminalWallsScript.HALF + GHOST_GROW
	var height := TerminalWallsScript.HEIGHT + GHOST_GROW
	ghost.global_position = (lo + hi) * 0.5 + Vector3.UP * height * 0.5
	ghost.scale = Vector3(hi.x - lo.x + half * 2.0, height, hi.z - lo.z + half * 2.0)
	ghost.material_override = material
	ghost.visible = true
