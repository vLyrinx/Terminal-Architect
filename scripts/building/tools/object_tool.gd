extends "res://scripts/building/build_tool.gd"
## Object tool (checklist step 11): places objects from the ObjectCatalog.
##
##   Left click    place the object (as a PlaceObjectCommand)
##   R             rotate 90 degrees
##   Tab           next object type
## The ghost is the object's own model, centred on the mouse and snapped to
## the grid: green where it fits, red where it doesn't, with the reason above it.

const PlaceObjectCommandScript := preload("res://scripts/core/commands/place_object_command.gd")

## The PlacedObjects node (placed_objects.gd).
@export var placed_objects: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _defs: Array = []
var _def_index := 0
var _rotation := 0.0
var _ghost: Node3D
var _ghost_valid := true
var _label: Label3D
var _position := Vector3.ZERO
var _has_position := false
var _reason := ""


func _ready() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 24
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.75, 0.75)
	_label.visible = false
	add_child(_label)


func activate() -> void:
	_defs = ObjectCatalog.get_all()
	_def_index = clampi(_def_index, 0, maxi(_defs.size() - 1, 0))
	_rebuild_ghost()


func deactivate() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_label.visible = false


func _process(_delta: float) -> void:
	if not is_active() or _ghost == null:
		return
	var pick := mouse_pick()
	_has_position = pick.hit and pick.in_plot
	_ghost.visible = _has_position
	if not _has_position:
		_label.visible = false
		return
	var def: Resource = _defs[_def_index]
	_position = placed_objects.snap_position(def, pick.position, _rotation, get_floor())
	_reason = placed_objects.check_placement(def, _position, _rotation, get_floor())
	_ghost.global_position = _position
	_ghost.rotation = Vector3(0.0, _rotation, 0.0)
	_set_ghost_valid(_reason == "")
	_label.visible = _reason != ""
	_label.text = _reason
	_label.global_position = _position + Vector3.UP * 1.6


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		_rotation = wrapf(_rotation + PI * 0.5, 0.0, TAU)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_TAB and _defs.size() > 1:
		_def_index = (_def_index + 1) % _defs.size()
		_rebuild_ghost()
		manager.tool_changed.emit(self)  # refreshes the hint with the new object's name
		get_viewport().set_input_as_handled()


func release(_tile: Vector2i, _in_plot: bool) -> void:
	if not _has_position or _defs.is_empty():
		return
	var def: Resource = _defs[_def_index]
	command_runner.submit(PlaceObjectCommandScript.new(def.id, _position, _rotation, get_floor()))


func get_hint() -> String:
	if _defs.is_empty():
		return "No objects in data/objects/"
	var def: Resource = _defs[_def_index]
	return "Click: place %s ($%d)   R: rotate   Tab: next object   Right click / Esc: cancel" % [
		def.display_name, def.cost]


func _rebuild_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _defs.is_empty():
		return
	_ghost = _defs[_def_index].model.instantiate()
	_ghost.visible = false
	add_child(_ghost)
	_ghost_valid = false  # so the next line sets the materials
	_set_ghost_valid(true)


func _set_ghost_valid(valid: bool) -> void:
	if valid == _ghost_valid:
		return
	_ghost_valid = valid
	_apply_ghost_material(_ghost, ghost_material(valid))


func _apply_ghost_material(node: Node, material: Material) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.material_override = material
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_ghost_material(child, material)
