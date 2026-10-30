extends "res://scripts/building/build_tool.gd"
## Runway tool (checklist step 16): place a runway as a fixed-size item.
##
##   Left click    place the runway (as a PlaceRunwayCommand)
##   R             turn it 90 degrees (Shift + R: the other way)
## Each size in data/runways/ has one length (RunwayDef.length). The runway is
## centred on the mouse, snapped to the 10 m airside grid
## (BuildGrid.AIRSIDE_SNAP, the major grid lines), and runs along X or Z. The
## heading decides which end is which, so turning it also swaps the
## designators. The ghost is green when it can be built and red when not; the
## label shows the designators, length, width and price, or why it can't be
## built (off the plot, over floor or walls, overlapping, not enough money).
## One build menu entry per runway size.

const PlaceRunwayCommandScript := preload("res://scripts/core/commands/place_runway_command.gd")
const RunwayScript := preload("res://scripts/airside/runway.gd")
const GHOST_HEIGHT := 0.5
## Directions from end A to end B, in the order R steps through them: east, south, west, north.
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## The Runways node (runways.gd).
@export var runways: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _def_id: StringName
var _facing := 0
var _centre := Vector2i.ZERO
var _has_hover := false
var _ghost: MeshInstance3D
var _label: Label3D


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
	_ghost.visible = false
	_label.visible = false


func _process(_delta: float) -> void:
	if not is_active():
		return
	var def := RunwayCatalog.get_def(_def_id)
	var pick := mouse_pick()
	_has_hover = def != null and pick.hit and pick.in_plot
	if _has_hover:
		_centre = BuildGrid.snap_to_airside(BuildGrid.world_to_corner(pick.position))
	_update_ghost(def)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		_facing = posmod(_facing + (-1 if event.shift_pressed else 1), DIRECTIONS.size())
		get_viewport().set_input_as_handled()


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _has_hover:
		return
	var ends := _ends(RunwayCatalog.get_def(_def_id))
	var command := PlaceRunwayCommandScript.new(_def_id, ends[0], ends[1])
	if command_runner.submit(command):
		var runway: RefCounted = runways.get_runway(command.runway_id)
		print("BUILD | %s runway %s/%s, %d m x %d m, ends at %s and %s" % [_def_id,
			runway.ends[0].designator, runway.ends[1].designator, runway.length, runway.width,
			runway.ends[0].position, runway.ends[1].position])


func get_hint() -> String:
	if RunwayCatalog.get_def(_def_id) == null:
		return "No runway sizes in data/runways/"
	return "Click: place runway   R / Shift+R: rotate   Right click / Esc: cancel"


# --- Build menu -------------------------------------------------------------------

## One build menu entry per runway size.
func get_menu_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for def: Resource in RunwayCatalog.get_all():
		var tooltip := "%s: %s m x %d m\n%s" % [def.display_name, _number(def.length), def.width,
			def.aircraft]
		items.append(make_menu_item("runway:" + String(def.id), def.display_name, def.icon,
			Money.format(def.get_cost(def.length)), def.menu_category, tooltip))
	return items


func select_item(item_id: String) -> void:
	if item_id.begins_with("runway:"):
		_def_id = StringName(item_id.trim_prefix("runway:"))


func get_active_item_id() -> String:
	return "runway:" + String(_def_id)


func get_title() -> String:
	var def := RunwayCatalog.get_def(_def_id)
	return "%s (%s m x %d m)" % [def.display_name, _number(def.length), def.width] if def else tool_name


func get_cost_text() -> String:
	var def := RunwayCatalog.get_def(_def_id)
	return Money.format(def.get_cost(def.length)) if def else ""


# --- Preview ----------------------------------------------------------------------

## End A and end B on the centreline for a runway centred on _centre.
func _ends(def: Resource) -> Array[Vector2i]:
	var half: Vector2i = DIRECTIONS[_facing] * (def.length / 2)
	return [_centre - half, _centre + half]


func _update_ghost(def: Resource) -> void:
	_ghost.visible = _has_hover
	_label.visible = _has_hover
	if not _has_hover:
		return

	var ends := _ends(def)
	var rect: Rect2i = runways.footprint(def, ends[0], ends[1])
	var lo := BuildGrid.tile_corner_to_world(rect.position, get_floor())
	var hi := BuildGrid.tile_corner_to_world(rect.end, get_floor())
	_ghost.global_position = (lo + hi) * 0.5 + Vector3.UP * GHOST_HEIGHT * 0.5
	_ghost.scale = Vector3(hi.x - lo.x, GHOST_HEIGHT, hi.z - lo.z)

	var p := PlaceRunwayCommandScript.new(_def_id, ends[0], ends[1]).preview(command_runner)
	var reason: String = p.error
	if reason == "" and not Money.can_afford(p.cost):
		reason = price_text(-p.cost)
	_ghost.material_override = ghost_material(reason == "")
	var axis := DIRECTIONS[_facing]
	var heading := RunwayScript.heading_of(Vector3(axis.x, 0.0, axis.y))
	var names := "%s/%s" % [RunwayScript.designator_of(heading), RunwayScript.designator_of(heading + 180.0)]
	var size := "%s m x %d m" % [_number(def.length), def.width]
	if reason == "":
		_label.text = "%s   %s   %s   %s" % [def.display_name, names, size, Money.format(p.cost)]
		_label.modulate = Color.WHITE
	else:
		_label.text = "%s   %s\n%s" % [def.display_name, size, reason]
		_label.modulate = Color(1.0, 0.75, 0.75)
	_label.global_position = (lo + hi) * 0.5 + Vector3.UP * 12.0


static func _number(n: int) -> String:
	return Money.format(n).trim_prefix("$")
