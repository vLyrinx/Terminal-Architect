extends "res://scripts/building/build_tool.gd"
## Taxi line tool: paint the yellow lines aircraft follow onto taxiway and
## ramp paving.
##
##   Left drag            paint a straight line along X, along Z or at 45 degrees
##   Shift + left drag    remove the lines the drag passes over
## Lines start and end on the 10 m airside grid, which is where taxiway
## centrelines and ramp ends are. Start a line at a ramp's outer end, or on
## another line, to join it. The label shows the length, the largest aircraft
## size the paving under it takes and the price, or why it can't be painted.
## The route graph overlay is shown while this tool is in use.

const PlaceTaxiLineCommandScript := preload("res://scripts/core/commands/place_taxi_line_command.gd")
const DeleteTaxiLinesCommandScript := preload("res://scripts/core/commands/delete_taxi_lines_command.gd")
const GHOST_HEIGHT := 0.3
const GHOST_WIDTH := 2.0
## Shift-drag removes lines this close to the drag, in metres.
const REMOVE_REACH := 3.0

## The TaxiLines node (taxi_lines.gd).
@export var taxi_lines: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node
## Optional RouteGraphOverlay node (route_graph_overlay.gd), shown while building.
@export var graph_overlay: Node3D

var _ghost: MeshInstance3D
var _label: Label3D
var _dragging := false
var _removing := false
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _hover_corner := Vector2i.ZERO
var _has_hover := false


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = make_ghost(box)
	_ghost.top_level = true

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	_label.visible = false
	_label.top_level = true
	add_child(_label)


func activate() -> void:
	if graph_overlay:
		graph_overlay.set_forced(true)


func deactivate() -> void:
	if graph_overlay:
		graph_overlay.set_forced(false)
	_dragging = false
	_ghost.visible = false
	_label.visible = false


func _process(_delta: float) -> void:
	if not is_active():
		return
	var pick := mouse_pick()
	_has_hover = pick.hit and pick.in_plot
	if pick.hit and (_has_hover or _dragging):
		_hover_corner = BuildGrid.snap_to_airside(BuildGrid.world_to_corner(pick.position))
		if _dragging:
			_end = _direct(_hover_corner)
	_update_ghost()


func press(_tile: Vector2i) -> void:
	var pick := mouse_pick()
	if not pick.hit:
		return
	_dragging = true
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	_start = BuildGrid.snap_to_airside(BuildGrid.world_to_corner(pick.position))
	_end = _start


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _dragging:
		return
	_dragging = false
	if _removing:
		var ids: Array[int] = taxi_lines.get_lines_near(Vector2(_start), Vector2(_end), REMOVE_REACH)
		if not ids.is_empty():
			command_runner.submit(DeleteTaxiLinesCommandScript.new(ids))
		return
	if _end == _start:
		return
	var command := PlaceTaxiLineCommandScript.new(_start, _end)
	if command_runner.submit(command):
		var line: RefCounted = taxi_lines.get_line(command.line_id)
		print("BUILD | taxi line #%d, %d m from %s to %s, takes %s aircraft" % [line.id, roundi(line.length),
			_start, _end, line.size_class])


func cancel_drag() -> void:
	_dragging = false


func get_hint() -> String:
	return "Drag on taxiway paving: paint taxi line   Shift + drag: remove lines   " + \
		"F4: route graph   Right click / Esc: cancel"


func get_cost_text() -> String:
	return "%s / m" % Money.format(Money.settings.taxi_line_cost_per_metre)


# --- Preview ----------------------------------------------------------------------

## Keeps the drag along X, along Z or at 45 degrees, whichever is nearest the mouse.
func _direct(corner: Vector2i) -> Vector2i:
	var d := corner - _start
	var step := BuildGrid.AIRSIDE_SNAP
	if absi(d.x) >= 2 * absi(d.y):
		return Vector2i(corner.x, _start.y)
	if absi(d.y) >= 2 * absi(d.x):
		return Vector2i(_start.x, corner.y)
	var m := roundi((absi(d.x) + absi(d.y)) * 0.5 / step) * step
	return BuildGrid.clamp_corner_to_plot(_start + Vector2i(signi(d.x) * m, signi(d.y) * m))


func _update_ghost() -> void:
	var shown := _dragging or _has_hover
	_ghost.visible = shown
	_label.visible = shown and _dragging
	if not shown:
		return

	var a := BuildGrid.tile_corner_to_world(_start if _dragging else _hover_corner, get_floor())
	var b := BuildGrid.tile_corner_to_world(_end if _dragging else _hover_corner, get_floor())
	var d := b - a
	var length := d.length()
	var ghost_basis := Basis(Vector3.UP, atan2(-d.z, d.x)) * Basis.from_scale(
		Vector3(maxf(length, GHOST_WIDTH), GHOST_HEIGHT, GHOST_WIDTH))
	_ghost.global_transform = Transform3D(ghost_basis, (a + b) * 0.5 + Vector3.UP * GHOST_HEIGHT * 0.5)

	if not _dragging or (_start == _end and not _removing):
		_ghost.material_override = ghost_material(true)
		_label.visible = false
		return
	if _removing:
		var ids: Array[int] = taxi_lines.get_lines_near(Vector2(_start), Vector2(_end), REMOVE_REACH)
		_ghost.material_override = ghost_material(false)
		var refund: int = DeleteTaxiLinesCommandScript.new(ids).preview(command_runner)
		_label.text = "Remove %d taxi line%s   %s" % [ids.size(), "" if ids.size() == 1 else "s", price_text(refund)] \
			if not ids.is_empty() else "No taxi lines here"
		_label.modulate = Color(1.0, 0.75, 0.75)
	else:
		var p: Dictionary = PlaceTaxiLineCommandScript.new(_start, _end).preview(command_runner)
		var reason: String = p.error
		if reason == "" and not Money.can_afford(p.cost):
			reason = price_text(-p.cost)
		_ghost.material_override = ghost_material(reason == "")
		if reason == "":
			_label.text = "Taxi line   %d m   %s aircraft   %s" % [roundi(p.length), p.size_class, Money.format(p.cost)]
			_label.modulate = Color.WHITE
		else:
			_label.text = "Taxi line   %d m\n%s" % [roundi(p.length), reason]
			_label.modulate = Color(1.0, 0.75, 0.75)
	_label.global_position = (a + b) * 0.5 + Vector3.UP * 8.0
