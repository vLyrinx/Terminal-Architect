extends "res://scripts/building/build_tool.gd"
## Runway tool (checklist step 16): click a start point and drag to set the
## runway's direction and length.
##
##   Left drag    lay out the runway from the start corner along X or Z
## The runway starts on the 10 m airside grid (BuildGrid.AIRSIDE_SNAP, the
## major grid lines), follows whichever axis the mouse has moved
## further along in steps of the same 10 m, and stops at the size's
## longest length. The ghost is green when it can be built and red when not;
## the label shows the designators, length, width and price, or why it can't
## be built (too short, over floor or walls, overlapping, not enough money).
## One build menu entry per runway size in data/runways/.

const PlaceRunwayCommandScript := preload("res://scripts/core/commands/place_runway_command.gd")
const RunwayScript := preload("res://scripts/airside/runway.gd")
const BuildGridScript := preload("res://scripts/building/build_grid.gd")
## Runway lengths snap to this many metres, so the far end is on the airside grid too.
const LENGTH_STEP := BuildGridScript.AIRSIDE_SNAP
const GHOST_HEIGHT := 0.5

## The Runways node (runways.gd).
@export var runways: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _def_id: StringName
var _ghost: MeshInstance3D
var _label: Label3D
var _dragging := false
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _hover_corner := Vector2i.ZERO
var _has_hover := false


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


func activate() -> void:
	if _def_id == &"" or RunwayCatalog.get_def(_def_id) == null:
		var all := RunwayCatalog.get_all()
		_def_id = all[0].id if not all.is_empty() else &""


func deactivate() -> void:
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
			_end = _snap_end(_hover_corner)
	_update_ghost()


func press(_tile: Vector2i) -> void:
	var pick := mouse_pick()
	if not pick.hit:
		return
	_dragging = true
	_start = BuildGrid.snap_to_airside(BuildGrid.world_to_corner(pick.position))
	_end = _start


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _dragging:
		return
	_dragging = false
	if _end == _start:
		return
	var command := PlaceRunwayCommandScript.new(_def_id, _start, _end)
	if command_runner.submit(command):
		var runway: RefCounted = runways.get_runway(command.runway_id)
		print("BUILD | %s runway %s/%s, %d m x %d m, ends at %s and %s" % [_def_id,
			runway.ends[0].designator, runway.ends[1].designator, runway.length, runway.width,
			runway.ends[0].position, runway.ends[1].position])


func cancel_drag() -> void:
	_dragging = false


func get_hint() -> String:
	var def := RunwayCatalog.get_def(_def_id)
	if def == null:
		return "No runway sizes in data/runways/"
	return "Drag from the start point: %s-%s m along the grid   Right click / Esc: cancel" % [
		_number(def.min_length), _number(def.max_length)]


# --- Build menu -------------------------------------------------------------------

## One build menu entry per runway size.
func get_menu_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for def: Resource in RunwayCatalog.get_all():
		var tooltip := "%s: %d m wide, %s-%s m long\n%s" % [def.display_name, def.width,
			_number(def.min_length), _number(def.max_length), def.aircraft]
		items.append(make_menu_item("runway:" + String(def.id), def.display_name, def.icon,
			"%s / m" % Money.format(def.cost_per_metre), def.menu_category, tooltip))
	return items


func select_item(item_id: String) -> void:
	if item_id.begins_with("runway:"):
		_def_id = StringName(item_id.trim_prefix("runway:"))


func get_active_item_id() -> String:
	return "runway:" + String(_def_id)


func get_title() -> String:
	var def := RunwayCatalog.get_def(_def_id)
	return "%s (%d m wide)" % [def.display_name, def.width] if def else tool_name


func get_cost_text() -> String:
	var def := RunwayCatalog.get_def(_def_id)
	return "%s / m" % Money.format(def.cost_per_metre) if def else ""


# --- Preview ----------------------------------------------------------------------

## Keeps the drag on one axis, in LENGTH_STEP steps, no longer than the size allows.
func _snap_end(corner: Vector2i) -> Vector2i:
	var def := RunwayCatalog.get_def(_def_id)
	var d := corner - _start
	var along_x := absi(d.x) >= absi(d.y)
	var raw := absi(d.x) if along_x else absi(d.y)
	var length := mini(roundi(float(raw) / LENGTH_STEP) * LENGTH_STEP, def.max_length)
	var sign_ := signi(d.x if along_x else d.y)
	if sign_ == 0:
		sign_ = 1
	var end := _start + (Vector2i(sign_ * length, 0) if along_x else Vector2i(0, sign_ * length))
	return BuildGrid.clamp_corner_to_plot(end)


func _update_ghost() -> void:
	var def := RunwayCatalog.get_def(_def_id)
	var shown := def != null and (_dragging or _has_hover)
	_ghost.visible = shown
	_label.visible = shown and _dragging
	if not shown:
		return

	var a := _start if _dragging else _hover_corner
	var b := _end if _dragging else _hover_corner
	var rect: Rect2i = runways.footprint(def, a, b)
	if a == b:
		rect = Rect2i(a - Vector2i.ONE * floori(def.width * 0.5), Vector2i.ONE * def.width)  # a square marks the start point
	var lo := BuildGrid.tile_corner_to_world(rect.position, get_floor())
	var hi := BuildGrid.tile_corner_to_world(rect.end, get_floor())
	_ghost.global_position = (lo + hi) * 0.5 + Vector3.UP * GHOST_HEIGHT * 0.5
	_ghost.scale = Vector3(hi.x - lo.x, GHOST_HEIGHT, hi.z - lo.z)

	if not _dragging:
		_ghost.material_override = ghost_material(true)
		return
	var p := PlaceRunwayCommandScript.new(_def_id, _start, _end).preview(command_runner)
	var reason: String = p.error
	if reason == "" and not Money.can_afford(p.cost):
		reason = price_text(-p.cost)
	_ghost.material_override = ghost_material(reason == "")
	var axis := (_end - _start).sign()
	var heading := RunwayScript.heading_of(Vector3(axis.x, 0.0, axis.y)) if _end != _start else 90.0
	var names := "%s/%s" % [RunwayScript.designator_of(heading), RunwayScript.designator_of(heading + 180.0)]
	var size := "%s m x %d m" % [_number(p.length), def.width]
	if reason == "":
		_label.text = "%s   %s   %s   %s" % [def.display_name, names, size, Money.format(p.cost)]
		_label.modulate = Color.WHITE
	else:
		_label.text = "%s   %s\n%s" % [def.display_name, size, reason]
		_label.modulate = Color(1.0, 0.75, 0.75)
	_label.global_position = (lo + hi) * 0.5 + Vector3.UP * 12.0


static func _number(n: int) -> String:
	return Money.format(n).trim_prefix("$")
