extends "res://scripts/building/build_tool.gd"
## Stand tool (checklist step 18): place aircraft stands, connected to a
## taxiway or not yet (for planning terminals; they take aircraft once paving
## reaches their entry).
##
##   Left click    place the stand (as a PlaceStandCommand)
##   R             turn the entry edge 90 degrees (Shift + R: the other way)
## The ghost is the stand's apron with a yellow strip along its lead-in line,
## which runs from the entry edge to the stop bar. Near a taxiway the entry
## edge snaps flush against the taxiway's paving; across the lead-in the stand
## stays on the 10 m grid. The label shows the size class, the aircraft that
## fit, the price and whether it will be connected, or why it can't be built.
## The route graph overlay is shown while this tool is in use. One build menu
## entry per size in data/stands/.

const PlaceStandCommandScript := preload("res://scripts/core/commands/place_stand_command.gd")
const StandsScript := preload("res://scripts/airside/stands.gd")
const GHOST_HEIGHT := 0.3
const LEAD_IN_GHOST_WIDTH := 2.0

## The Stands node (stands.gd).
@export var stands: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node
## Optional RouteGraphOverlay node (route_graph_overlay.gd), shown while building.
@export var graph_overlay: Node3D

var _def_id: StringName
var _facing := 0
var _anchor := Vector2i.ZERO
var _has_hover := false
var _ghost: MeshInstance3D
var _lead_in: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = make_ghost(box)
	_lead_in = make_ghost(box)
	var lead_material := StandardMaterial3D.new()
	lead_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lead_material.albedo_color = StandsScript.LEAD_IN_COLOR
	_lead_in.material_override = lead_material

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
	if _def_id == &"" or StandCatalog.get_def(_def_id) == null:
		var all := StandCatalog.get_all()
		_def_id = all[0].id if not all.is_empty() else &""
	if graph_overlay:
		graph_overlay.set_forced(true)


func deactivate() -> void:
	if graph_overlay:
		graph_overlay.set_forced(false)
	_ghost.visible = false
	_lead_in.visible = false
	_label.visible = false


func _process(_delta: float) -> void:
	if not is_active():
		return
	var def := StandCatalog.get_def(_def_id)
	var pick := mouse_pick()
	_has_hover = def != null and pick.hit and pick.in_plot
	if _has_hover:
		_anchor = stands.snap_anchor(def, pick.position, _facing)
	_update_ghost(def)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		_facing = posmod(_facing + (-1 if event.shift_pressed else 1), StandsScript.FACINGS.size())
		get_viewport().set_input_as_handled()


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _has_hover:
		return
	var command := PlaceStandCommandScript.new(_def_id, _anchor, _facing)
	if command_runner.submit(command):
		var stand: RefCounted = stands.get_stand(command.stand_id)
		print("BUILD | %s stand #%d at %s, %d x %d m, %s" % [_def_id, stand.id, stand.anchor,
			stand.rect.size.x, stand.rect.size.y, stands.describe(stand)[1].to_lower()])


func get_hint() -> String:
	return "Click: place stand   R / Shift+R: turn   Entry edge (yellow line) on a taxiway connects it   " + \
		"F4: route graph   Right click / Esc: cancel"


# --- Build menu -------------------------------------------------------------------

## One build menu entry per stand size.
func get_menu_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for def: Resource in StandCatalog.get_all():
		var size: Vector2i = def.get_size()
		var tooltip := "%s: %s, %d x %d m\nFits %s" % [def.display_name, def.get_size_class().display_name.to_lower(),
			size.x, size.y, _fits_text(def)]
		items.append(make_menu_item("stand:" + String(def.id), def.display_name, def.icon,
			Money.format(def.cost), def.menu_category, tooltip))
	return items


func select_item(item_id: String) -> void:
	if item_id.begins_with("stand:"):
		_def_id = StringName(item_id.trim_prefix("stand:"))


func get_active_item_id() -> String:
	return "stand:" + String(_def_id)


func get_title() -> String:
	var def := StandCatalog.get_def(_def_id)
	return "%s (%s)" % [def.display_name, def.get_size_class().display_name.to_lower()] if def else tool_name


func get_cost_text() -> String:
	var def := StandCatalog.get_def(_def_id)
	return Money.format(def.cost) if def else ""


# --- Preview ----------------------------------------------------------------------

func _fits_text(def: Resource) -> String:
	return ", ".join(def.get_fitting_types().map(func(t: Resource) -> String: return t.display_name))


func _update_ghost(def: Resource) -> void:
	_ghost.visible = _has_hover
	_lead_in.visible = _has_hover
	_label.visible = _has_hover
	if not _has_hover:
		return

	var rect: Rect2i = stands.footprint(def, _anchor, _facing)
	var lo := BuildGrid.tile_corner_to_world(rect.position, get_floor())
	var hi := BuildGrid.tile_corner_to_world(rect.end, get_floor())
	_ghost.global_position = (lo + hi) * 0.5 + Vector3.UP * GHOST_HEIGHT * 0.5
	_ghost.scale = Vector3(hi.x - lo.x, GHOST_HEIGHT, hi.z - lo.z)

	# Lead-in strip from the entry edge to the stop bar.
	var f: Vector2i = StandsScript.FACINGS[_facing]
	var entry := BuildGrid.tile_corner_to_world(_anchor, get_floor())
	var depth: int = def.get_size().y
	var stop := entry - Vector3(f.x, 0.0, f.y) * (depth - StandsScript.STOP_FROM_BACK)
	_lead_in.global_position = (entry + stop) * 0.5 + Vector3.UP * (GHOST_HEIGHT + 0.05)
	var length := entry.distance_to(stop)
	_lead_in.scale = Vector3(length if f.x != 0 else LEAD_IN_GHOST_WIDTH, 0.1, length if f.y != 0 else LEAD_IN_GHOST_WIDTH)

	var p := PlaceStandCommandScript.new(_def_id, _anchor, _facing).preview(command_runner)
	var reason: String = p.error
	if reason == "" and not Money.can_afford(p.cost):
		reason = price_text(-p.cost)
	_ghost.material_override = ghost_material(reason == "")
	var heading := "%s: %s   %d x %d m" % [def.display_name, def.get_size_class().display_name.to_lower(),
		rect.size.x, rect.size.y]
	if reason == "":
		var problem: String = stands.connection_problem(def, _anchor, _facing)
		var link := "Opens onto the taxiway" if problem == "" else "Not connected: %s" % problem.to_lower()
		_label.text = "%s   %s\nFits %s\n%s" % [heading, Money.format(p.cost), _fits_text(def), link]
		_label.modulate = Color.WHITE if problem == "" else StandsScript.NOT_CONNECTED_COLOR
	else:
		_label.text = "%s\n%s" % [heading, reason]
		_label.modulate = Color(1.0, 0.75, 0.75)
	_label.global_position = (lo + hi) * 0.5 + Vector3.UP * 10.0
