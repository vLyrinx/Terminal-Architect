extends "res://scripts/building/build_tool.gd"
## Taxiway tool (checklist step 17): drag straight pieces of taxiway paving along the grid.
##
##   Left drag    lay taxiway paving from the start corner along X or Z
## Pieces start and end on the 10 m airside grid (BuildGrid.AIRSIDE_SNAP, the
## major grid lines) and follow whichever axis the mouse has moved further
## along. Paving is only the ground: paint taxi lines on it with the taxi line
## tool for aircraft to use, and join it to a runway with a runway ramp
## (start a piece at the ramp's outer end). The label shows the length, width
## and price, and which ramps and taxiways the piece touches, or why it can't
## be built. The route graph overlay is shown while this tool is in use. One
## build menu entry per size in data/taxiways/.

const PlaceTaxiwayCommandScript := preload("res://scripts/core/commands/place_taxiway_command.gd")
const GHOST_HEIGHT := 0.3

## The Taxiways node (taxiways.gd).
@export var taxiways: Node3D
## The Runways node (runways.gd).
@export var runways: Node3D
## Optional Ramps node (ramps.gd), to say which ramps a piece touches.
@export var ramps: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node
## Optional RouteGraphOverlay node (route_graph_overlay.gd), shown while building.
@export var graph_overlay: Node3D

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
	if _def_id == &"" or TaxiwayCatalog.get_def(_def_id) == null:
		var all := TaxiwayCatalog.get_all()
		_def_id = all[0].id if not all.is_empty() else &""
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
			_end = _straighten(_hover_corner)
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
	var command := PlaceTaxiwayCommandScript.new(_def_id, _start, _end)
	if command_runner.submit(command):
		var taxiway: RefCounted = taxiways.get_taxiway(command.taxiway_id)
		print("BUILD | %s taxiway #%d, %d m x %d m from %s to %s" % [_def_id, taxiway.id, taxiway.length,
			taxiway.width, _start, _end])


func cancel_drag() -> void:
	_dragging = false


func get_hint() -> String:
	return "Drag along the grid: lay taxiway paving   Then paint taxi lines on it   " + \
		"F4: route graph   Right click / Esc: cancel"


# --- Build menu -------------------------------------------------------------------

## One build menu entry per taxiway size.
func get_menu_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for def: Resource in TaxiwayCatalog.get_all():
		var tooltip := "%s: %d m wide\n%s" % [def.display_name, def.width, def.aircraft]
		items.append(make_menu_item("taxiway:" + String(def.id), def.display_name, def.icon,
			"%s / m" % Money.format(def.cost_per_metre), def.menu_category, tooltip))
	return items


func select_item(item_id: String) -> void:
	if item_id.begins_with("taxiway:"):
		_def_id = StringName(item_id.trim_prefix("taxiway:"))


func get_active_item_id() -> String:
	return "taxiway:" + String(_def_id)


func get_title() -> String:
	var def := TaxiwayCatalog.get_def(_def_id)
	return "%s (%d m wide)" % [def.display_name, def.width] if def else tool_name


func get_cost_text() -> String:
	var def := TaxiwayCatalog.get_def(_def_id)
	return "%s / m" % Money.format(def.cost_per_metre) if def else ""


# --- Preview ----------------------------------------------------------------------

## Keeps the drag on whichever axis the mouse has moved further along.
func _straighten(corner: Vector2i) -> Vector2i:
	var d := corner - _start
	if absi(d.x) >= absi(d.y):
		return Vector2i(corner.x, _start.y)
	return Vector2i(_start.x, corner.y)


## What a piece covering rect would touch, such as "touches 1 ramp and 2 taxiways".
func _joins_text(rect: Rect2i) -> String:
	var touch := rect.grow(1)
	var parts: Array[String] = []
	var ramp_count: int = ramps.get_ramps_in(touch).size() if ramps else 0
	if ramp_count > 0:
		parts.append("%d ramp%s" % [ramp_count, "s" if ramp_count > 1 else ""])
	var count: int = taxiways.get_taxiways_in(touch).size()
	if count > 0:
		parts.append("%d taxiway%s" % [count, "s" if count > 1 else ""])
	return "touches " + " and ".join(parts) if not parts.is_empty() else "not touching other paving"


func _update_ghost() -> void:
	var def := TaxiwayCatalog.get_def(_def_id)
	var shown := def != null and (_dragging or _has_hover)
	_ghost.visible = shown
	_label.visible = shown and _dragging
	if not shown:
		return

	var a := _start if _dragging else _hover_corner
	var b := _end if _dragging else _hover_corner
	var rect: Rect2i = taxiways.footprint(def, a, b)
	if a == b:
		rect = Rect2i(a - Vector2i.ONE * floori(def.width * 0.5), Vector2i.ONE * def.width)  # a square marks the start point
	var lo := BuildGrid.tile_corner_to_world(rect.position, get_floor())
	var hi := BuildGrid.tile_corner_to_world(rect.end, get_floor())
	_ghost.global_position = (lo + hi) * 0.5 + Vector3.UP * GHOST_HEIGHT * 0.5
	_ghost.scale = Vector3(hi.x - lo.x, GHOST_HEIGHT, hi.z - lo.z)

	if not _dragging or a == b:
		_ghost.material_override = ghost_material(true)
		_label.visible = false
		return
	var p := PlaceTaxiwayCommandScript.new(_def_id, _start, _end).preview(command_runner)
	var reason: String = p.error
	if reason == "" and not Money.can_afford(p.cost):
		reason = price_text(-p.cost)
	_ghost.material_override = ghost_material(reason == "")
	var size := "%d m x %d m" % [p.length, def.width]
	if reason == "":
		_label.text = "%s   %s   %s\n%s" % [def.display_name, size, Money.format(p.cost), _joins_text(rect)]
		_label.modulate = Color.WHITE
	else:
		_label.text = "%s   %s\n%s" % [def.display_name, size, reason]
		_label.modulate = Color(1.0, 0.75, 0.75)
	_label.global_position = (lo + hi) * 0.5 + Vector3.UP * 8.0
