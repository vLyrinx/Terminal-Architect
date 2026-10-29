extends Node
## Roof and wall cutaway (checklist step 13): lets the camera see inside the terminal.
##
## While the cutaway is on (V toggles it), roofs hide when the camera zooms in
## or is looking at the terminal from a medium distance, and walls between the
## camera and the inside lower to a short height (see terminal_walls.gdshader).
## Zoomed far out, the whole building shows with its roof. With the cutaway off,
## the building always shows in full.
##
## Turning the camera only changes two shader settings, so it costs nothing.

signal cutaway_changed(enabled: bool)

const ACTION_TOGGLE := "toggle_cutaway"
## Closer than this (camera distance to its focus, in metres) roofs always hide.
const ZOOM_DISTANCE := 90.0
## Closer than this, roofs hide when the camera is looking at terminal floor.
const LOOK_INSIDE_DISTANCE := 170.0
## Stops the roof flickering when the camera sits right at a threshold.
const HYSTERESIS := 6.0
## How far the camera must look along an axis (0 to 1) before walls across it count as facing it.
const FACING_THRESHOLD := 0.2

## The orbit camera (orbit_camera.gd).
@export var camera: Camera3D
## The TerminalFloor node (terminal_floor.gd), which draws the roofs.
@export var terminal_floor: Node3D
## The TerminalWalls node (terminal_walls.gd).
@export var terminal_walls: Node3D

## Cutaway switched on (V key).
var enabled := true
## True while roofs are hidden and walls lowered.
var active := false
var _view_dir := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused
	if not InputMap.has_action(ACTION_TOGGLE):
		InputMap.add_action(ACTION_TOGGLE)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V
		InputMap.action_add_event(ACTION_TOGGLE, key)
	apply(false, Vector2.ZERO, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	print("CUTAWAY | %s" % ("on" if enabled else "off"))
	cutaway_changed.emit(enabled)


func _process(_delta: float) -> void:
	if camera == null:
		return
	var distance: float = camera.get_distance()
	var focus_tile := BuildGrid.world_to_tile(camera.get_focus())
	var looking_inside: bool = terminal_floor.has_floor(focus_tile)
	apply(should_cut(enabled, active, distance, looking_inside), view_direction(-camera.global_basis.z))


## Whether the cutaway should be active. Already active, it stays on until the
## camera moves a little past the threshold (and the other way round).
static func should_cut(is_enabled: bool, is_active: bool, distance: float, looking_inside: bool) -> bool:
	if not is_enabled:
		return false
	var limit := LOOK_INSIDE_DISTANCE if looking_inside else ZOOM_DISTANCE
	return distance < limit + (HYSTERESIS if is_active else -HYSTERESIS)


## A look direction flattened to the ground as -1, 0 or 1 for world X and Z.
static func view_direction(forward: Vector3) -> Vector2:
	var flat := Vector2(forward.x, forward.z).normalized()
	return Vector2(
		0.0 if absf(flat.x) < FACING_THRESHOLD else signf(flat.x),
		0.0 if absf(flat.y) < FACING_THRESHOLD else signf(flat.y))


## Shows or hides roofs and lowers walls. Does nothing if nothing changed.
func apply(cut: bool, view_dir: Vector2, force := false) -> void:
	if not force and cut == active and view_dir == _view_dir:
		return
	active = cut
	_view_dir = view_dir
	terminal_floor.set_roof_visible(not cut)
	terminal_walls.set_cutaway(cut, view_dir)
