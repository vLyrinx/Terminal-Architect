extends "res://scripts/building/build_tool.gd"
## Ramp tool: place runway ramps against the side of a runway.
##
##   Left click    place the ramp (as a PlaceRampCommand)
##   R             angled ramps: lean the other way along the runway
## The ramp goes on whichever side of the nearest runway the mouse is on, at
## the nearest 10 m along it, with its outer end on the airside grid so
## taxiway paving laid from there lines up. The ghost is the ramp itself with
## its taxi line, tinted green when it can be built and red when not; the
## label shows the price, or why it can't be built. The route graph overlay is
## shown while this tool is in use. One build menu entry per ramp in data/ramps/.

const PlaceRampCommandScript := preload("res://scripts/core/commands/place_ramp_command.gd")

## The Ramps node (ramps.gd).
@export var ramps: Node3D
## The Runways node (runways.gd).
@export var runways: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node
## Optional RouteGraphOverlay node (route_graph_overlay.gd), shown while building.
@export var graph_overlay: Node3D

var _def_id: StringName
var _lean := 1
## {"runway_id", "anchor"} from Ramps.snap(), or empty when no runway is near.
var _target := {}
var _ghost: Node3D
var _ghost_key := ""
var _label: Label3D


func _ready() -> void:
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
	if _def_id == &"" or RampCatalog.get_def(_def_id) == null:
		var all := RampCatalog.get_all()
		_def_id = all[0].id if not all.is_empty() else &""
	if graph_overlay:
		graph_overlay.set_forced(true)


func deactivate() -> void:
	if graph_overlay:
		graph_overlay.set_forced(false)
	_clear_ghost()
	_label.visible = false


func _process(_delta: float) -> void:
	if not is_active():
		return
	var def := RampCatalog.get_def(_def_id)
	var pick := mouse_pick()
	_target = {}
	if def and pick.hit:
		var p: Vector3 = (pick.position - BuildGrid.origin) / BuildGrid.TILE_SIZE
		_target = ramps.snap(def, Vector2(p.x, p.z))
	_update_ghost(def)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		_lean = -_lean
		get_viewport().set_input_as_handled()


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if _target.is_empty():
		return
	var command := PlaceRampCommandScript.new(_def_id, _target.runway_id, _target.anchor, _lean)
	if command_runner.submit(command):
		print("BUILD | %s ramp #%d on runway #%d, outer end at %s" % [_def_id, command.ramp_id,
			_target.runway_id, _target.anchor])


func get_hint() -> String:
	var def := RampCatalog.get_def(_def_id)
	if def == null:
		return "No ramps in data/ramps/"
	var turn := "   R: lean the other way" if def.shape == "angled" else ""
	return "Click beside a runway: place ramp%s   F4: route graph   Right click / Esc: cancel" % turn


# --- Build menu -------------------------------------------------------------------

## One build menu entry per ramp.
func get_menu_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for def: Resource in RampCatalog.get_all():
		var tooltip := "%s: %d m wide\n%s" % [def.display_name, def.width, def.description]
		items.append(make_menu_item("ramp:" + String(def.id), def.display_name, def.icon,
			Money.format(def.cost), def.menu_category, tooltip))
	return items


func select_item(item_id: String) -> void:
	if item_id.begins_with("ramp:"):
		_def_id = StringName(item_id.trim_prefix("ramp:"))


func get_active_item_id() -> String:
	return "ramp:" + String(_def_id)


func get_title() -> String:
	var def := RampCatalog.get_def(_def_id)
	return "%s (%d m wide)" % [def.display_name, def.width] if def else tool_name


func get_cost_text() -> String:
	var def := RampCatalog.get_def(_def_id)
	return Money.format(def.cost) if def else ""


# --- Preview ----------------------------------------------------------------------

func _clear_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_ghost_key = ""


func _update_ghost(def: Resource) -> void:
	var runway: RefCounted = runways.get_runway(_target.runway_id) if not _target.is_empty() else null
	if def == null or runway == null:
		_clear_ghost()
		_label.visible = false
		return

	var p: Dictionary = PlaceRampCommandScript.new(_def_id, _target.runway_id, _target.anchor, _lean) \
		.preview(command_runner)
	var reason: String = p.error
	if reason == "" and not Money.can_afford(p.cost):
		reason = price_text(-p.cost)
	var key := "%s|%d|%s|%d|%s" % [_def_id, runway.id, _target.anchor, _lean, reason == ""]
	if key != _ghost_key:
		_clear_ghost()
		_ghost_key = key
		var ramp: RefCounted = ramps.make_ramp(def, runway, _target.anchor, _lean)
		_ghost = ramps.build_node(ramp, def)
		_ghost.top_level = true
		add_child(_ghost)
		var mesh := _ghost.get_node("Mesh") as MeshInstance3D
		mesh.material_override = ghost_material(reason == "")
		_ghost.position = Vector3.UP * 0.05

	_label.visible = true
	if reason == "":
		_label.text = "%s   %s" % [def.display_name, Money.format(p.cost)]
		_label.modulate = Color.WHITE
	else:
		_label.text = "%s\n%s" % [def.display_name, reason]
		_label.modulate = Color(1.0, 0.75, 0.75)
	_label.global_position = BuildGrid.tile_corner_to_world(_target.anchor) + Vector3.UP * 12.0
