extends "res://scripts/building/build_tool.gd"
## Edit tool (checklist step 11): select, rotate and delete placed objects.
##
##   Left click            select the object under the mouse (click empty floor to deselect)
##   R                     rotate the selected object 90 degrees in place
##   Delete / Backspace    delete the selected object
## Rotating and deleting go through commands. The object under the mouse is
## lightly highlighted and the selected one is highlighted in yellow.

const RotateObjectCommandScript := preload("res://scripts/core/commands/rotate_object_command.gd")
const DeleteObjectCommandScript := preload("res://scripts/core/commands/delete_object_command.gd")
## Objects are picked a little above the floor, roughly where their tops are.
const PICK_HEIGHT := 0.5

## The PlacedObjects node (placed_objects.gd).
@export var placed_objects: Node3D
## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

static var _hover_material: StandardMaterial3D
static var _select_material: StandardMaterial3D

var _hovered := 0
var _selected := 0


func _ready() -> void:
	if _hover_material == null:
		_hover_material = _make_highlight(Color(1.0, 1.0, 1.0, 0.25))
		_select_material = _make_highlight(Color(1.0, 0.85, 0.25, 0.45))
	placed_objects.object_removed.connect(_on_object_removed)


func deactivate() -> void:
	_set_hovered(0)
	_set_selected(0)


func _process(_delta: float) -> void:
	if not is_active():
		return
	var pick := mouse_pick(PICK_HEIGHT)
	var id := 0
	if pick.hit and pick.in_plot:
		id = placed_objects.get_object_at(pick.tile, get_floor())
	_set_hovered(id)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		_rotate_selected()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_DELETE or event.physical_keycode == KEY_BACKSPACE:
		if _selected != 0:
			command_runner.submit(DeleteObjectCommandScript.new(_selected))
		get_viewport().set_input_as_handled()


func release(_tile: Vector2i, _in_plot: bool) -> void:
	_set_selected(_hovered)


func get_hint() -> String:
	return "Click: select object   R: rotate   Delete: remove   Right click / Esc: done"


func _rotate_selected() -> void:
	var obj: RefCounted = placed_objects.get_object(_selected)
	if obj == null:
		return
	var def := ObjectCatalog.get_def(obj.def_id)
	var new_rotation := wrapf(obj.rotation + PI * 0.5, 0.0, TAU)
	var new_position: Vector3 = placed_objects.rotate_in_place(def, obj.position, obj.rotation, new_rotation)
	command_runner.submit(RotateObjectCommandScript.new(_selected, new_position, new_rotation))


func _set_hovered(id: int) -> void:
	if id == _hovered:
		return
	var old := _hovered
	_hovered = id
	_refresh_highlight(old)
	_refresh_highlight(id)


func _set_selected(id: int) -> void:
	if id == _selected:
		return
	var old := _selected
	_selected = id
	_refresh_highlight(old)
	_refresh_highlight(id)
	if id != 0:
		var obj: RefCounted = placed_objects.get_object(id)
		print("EDIT | selected #%d (%s)" % [id, obj.def_id])


func _refresh_highlight(id: int) -> void:
	if id == 0:
		return
	var material: Material = null
	if id == _selected:
		material = _select_material
	elif id == _hovered:
		material = _hover_material
	placed_objects.set_highlight(id, material)


func _on_object_removed(id: int) -> void:
	if id == _selected:
		_selected = 0
	if id == _hovered:
		_hovered = 0


static func _make_highlight(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m
