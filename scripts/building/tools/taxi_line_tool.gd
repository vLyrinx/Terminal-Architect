extends "res://scripts/building/build_tool.gd"
## Taxi line tool: paint the yellow lines aircraft follow onto taxiway and
## ramp paving.
##
##   Left drag            paint a straight line along X, along Z or at 45 degrees
##   Shift + left drag    remove the part of the lines the drag runs over
##   Shift + left click   remove a 2 m piece of line under the mouse
## Lines snap to the 1 m grid, and to the end of another line or the outer
## end of a ramp within SNAP_REACH, so joins are easy to hit. While the tool
## is in use those join points show as white dots on the paving. Start a line
## at a ramp's outer end, or on another line, to join it. The preview lies flat
## on the paving, like the line it paints. The label shows the length, how wide
## the paving is around it, the largest aircraft size that takes and the price,
## or why it can't be painted. F4 still shows the route graph overlay.

const PlaceTaxiLineCommandScript := preload("res://scripts/core/commands/place_taxi_line_command.gd")
const CutTaxiLinesCommandScript := preload("res://scripts/core/commands/cut_taxi_lines_command.gd")
const TaxiLinesScript := preload("res://scripts/airside/taxi_lines.gd")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")
## The preview strip is this wide and sits just above the painted lines.
const GHOST_WIDTH := 1.0
const GHOST_THICKNESS := 0.02
const GHOST_LIFT := 0.01
## Shift-drag starts on a line this close to the mouse, in metres.
const REMOVE_REACH := 3.0
## Shift-drag removes the line steps whose middles are this close to the drag.
const CUT_REACH := 0.75
## Line ends snap to other line ends and ramp ends this close, in metres.
const SNAP_REACH := 4.0
const JOIN_DOT_RADIUS := 0.9
const JOIN_DOT_COLOR := Color(1, 1, 1)

## The TaxiLines node (taxi_lines.gd).
@export var taxi_lines: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _ghost: MeshInstance3D
var _label: Label3D
var _join_dots: MeshInstance3D
var _dots_dirty := true
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

	_join_dots = MeshInstance3D.new()
	_join_dots.top_level = true
	_join_dots.visible = false
	_join_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot_material := StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.vertex_color_use_as_albedo = true
	dot_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_join_dots.material_override = dot_material
	add_child(_join_dots)
	if taxi_lines:
		taxi_lines.lines_changed.connect(_on_joins_changed)
		if taxi_lines.ramps:
			taxi_lines.ramps.ramp_added.connect(_on_joins_changed.unbind(1))
			taxi_lines.ramps.ramp_removed.connect(_on_joins_changed.unbind(1))


func activate() -> void:
	_join_dots.visible = true
	if _dots_dirty:
		_rebuild_join_dots()


func deactivate() -> void:
	_dragging = false
	_ghost.visible = false
	_label.visible = false
	_join_dots.visible = false


func _process(_delta: float) -> void:
	if not is_active():
		return
	var pick := mouse_pick()
	_has_hover = pick.hit and pick.in_plot
	if pick.hit and (_has_hover or _dragging):
		_hover_corner = BuildGrid.clamp_corner_to_plot(BuildGrid.world_to_corner(pick.position))
		if _dragging and _removing:
			_end = _direct(_hover_corner)
		elif _dragging:
			_end = taxi_lines.snap_end(_direct(_hover_corner), SNAP_REACH, _start)
		elif Input.is_physical_key_pressed(KEY_SHIFT):
			_hover_corner = taxi_lines.snap_to_line(_hover_corner, REMOVE_REACH)
		else:
			_hover_corner = taxi_lines.snap_end(_hover_corner, SNAP_REACH)
	_update_ghost()


func press(_tile: Vector2i) -> void:
	var pick := mouse_pick()
	if not pick.hit:
		return
	_dragging = true
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	var corner := BuildGrid.clamp_corner_to_plot(BuildGrid.world_to_corner(pick.position))
	_start = taxi_lines.snap_to_line(corner, REMOVE_REACH) if _removing else taxi_lines.snap_end(corner, SNAP_REACH)
	_end = _start


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _dragging:
		return
	_dragging = false
	if _removing:
		var cut := CutTaxiLinesCommandScript.new(_start, _end, CUT_REACH)
		if cut.preview(command_runner).lines > 0 and command_runner.submit(cut):
			print("BUILD | removed taxi line from %s to %s" % [_start, _end])
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
	return "Drag on taxiway paving: paint taxi line   Shift + drag / click: remove part of a line   " + \
		"F4: route graph   Right click / Esc: cancel"


func get_cost_text() -> String:
	return "%s / m" % Money.format(Money.settings.taxi_line_cost_per_metre)


# --- Preview ----------------------------------------------------------------------

## Keeps the drag along X, along Z or at 45 degrees, whichever is nearest the mouse.
func _direct(corner: Vector2i) -> Vector2i:
	var d := corner - _start
	if absi(d.x) >= 2 * absi(d.y):
		return Vector2i(corner.x, _start.y)
	if absi(d.y) >= 2 * absi(d.x):
		return Vector2i(_start.x, corner.y)
	var m := roundi((absi(d.x) + absi(d.y)) * 0.5)
	return BuildGrid.clamp_corner_to_plot(_start + Vector2i(signi(d.x) * m, signi(d.y) * m))


func _update_ghost() -> void:
	var shown := _dragging or _has_hover
	_ghost.visible = shown
	_label.visible = shown and _dragging
	if not shown:
		return

	var lift := Vector3.UP * (TaxiLinesScript.HEIGHT + GHOST_LIFT + GHOST_THICKNESS * 0.5)
	var a := BuildGrid.tile_corner_to_world(_start if _dragging else _hover_corner, get_floor())
	var b := BuildGrid.tile_corner_to_world(_end if _dragging else _hover_corner, get_floor())
	var d := b - a
	var length := d.length()
	var ghost_basis := Basis(Vector3.UP, atan2(-d.z, d.x)) * Basis.from_scale(
		Vector3(length + GHOST_WIDTH, GHOST_THICKNESS, GHOST_WIDTH))
	_ghost.global_transform = Transform3D(ghost_basis, (a + b) * 0.5 + lift)

	var shift := Input.is_physical_key_pressed(KEY_SHIFT)
	if not _dragging or (_start == _end and not _removing):
		_ghost.material_override = ghost_material(not (shift and not _dragging))
		_label.visible = false
		return
	if _removing:
		var p: Dictionary = CutTaxiLinesCommandScript.new(_start, _end, CUT_REACH).preview(command_runner)
		_ghost.material_override = ghost_material(false)
		_label.text = "Remove %d m of taxi line   %s" % [roundi(p.metres), price_text(p.refund)] \
			if p.lines > 0 else "No taxi lines here"
		_label.modulate = Color(1.0, 0.75, 0.75)
	else:
		var p: Dictionary = PlaceTaxiLineCommandScript.new(_start, _end).preview(command_runner)
		var reason: String = p.error
		if reason == "" and not Money.can_afford(p.cost):
			reason = price_text(-p.cost)
		_ghost.material_override = ghost_material(reason == "")
		if reason == "":
			_label.text = "Taxi line   %d m   %d m paving: %s aircraft   %s" % [roundi(p.length), p.width,
				p.size_class, Money.format(p.cost)]
			_label.modulate = Color.WHITE
		else:
			_label.text = "Taxi line   %d m\n%s" % [roundi(p.length), reason]
			_label.modulate = Color(1.0, 0.75, 0.75)
	_label.global_position = (a + b) * 0.5 + Vector3.UP * 8.0


# --- Join dots ----------------------------------------------------------------------

func _on_joins_changed() -> void:
	_dots_dirty = true
	if _join_dots.visible:
		_rebuild_join_dots()


## White dots at every line end and ramp outer end: the points new lines snap to.
func _rebuild_join_dots() -> void:
	_dots_dirty = false
	var points := {}
	for line: RefCounted in taxi_lines.get_all():
		points[line.a] = true
		points[line.b] = true
	if taxi_lines.ramps:
		for ramp: RefCounted in taxi_lines.ramps.get_all():
			points[ramp.anchor] = true
	if points.is_empty():
		_join_dots.mesh = null
		return
	var builder := MeshBuilderScript.new()
	var lift := Vector3.UP * (TaxiLinesScript.HEIGHT + GHOST_LIFT * 0.5)
	for p: Vector2i in points:
		TaxiLinesScript.add_dot(builder, BuildGrid.tile_corner_to_world(p) + lift, JOIN_DOT_RADIUS, JOIN_DOT_COLOR)
	_join_dots.mesh = builder.commit()
