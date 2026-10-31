extends Camera3D
## Free orbit camera (checklist step 5).
##
## Orbits a focus point on the ground:
##   Right mouse drag      rotate (left/right) and tilt (up/down)
##   Middle mouse drag     pan (the ground follows the cursor)
##   WASD / arrow keys     pan (hold Shift for faster)
##   Q / E                 rotate
##   Mouse wheel           zoom in and out
## Input sets target values and the camera eases towards them every frame,
## so movement stays smooth at any frame rate. It keeps working while the
## game clock is paused.

const ACTION_KEYS := {
	"camera_pan_forward": [KEY_W, KEY_UP],
	"camera_pan_back": [KEY_S, KEY_DOWN],
	"camera_pan_left": [KEY_A, KEY_LEFT],
	"camera_pan_right": [KEY_D, KEY_RIGHT],
	"camera_rotate_left": [KEY_Q],
	"camera_rotate_right": [KEY_E],
	"camera_fast": [KEY_SHIFT],
}

@export_group("Zoom")
## Closest distance to the focus point, in metres (a passenger is about 1.8 m tall).
@export var min_distance := 3.5
## Furthest distance, in metres (enough to see the whole 4.5 km plot).
@export var max_distance := 4000.0
## Distance is multiplied or divided by this for each wheel notch.
@export var zoom_step := 1.15
@export var start_distance := 120.0

@export_group("Tilt")
## Lowest tilt above the horizon, in degrees.
@export var min_pitch_deg := 12.0
## Highest tilt, in degrees (90 would be straight down).
@export var max_pitch_deg := 85.0
@export var start_pitch_deg := 45.0
## The camera never goes lower than this height above the ground, in metres.
@export var min_height := 1.0

@export_group("Speed")
## Degrees of rotation per pixel of right mouse drag.
@export var drag_rotate_sensitivity := 0.25
## Degrees per second when rotating with Q / E.
@export var key_rotate_speed := 90.0
## Keyboard pan speed as a fraction of the zoom distance per second.
@export var key_pan_speed := 0.8
## Multiplier while Shift is held.
@export var fast_multiplier := 2.5
## How quickly the camera catches up with its targets (higher is snappier).
@export var smoothing := 12.0

@export_group("Limits")
## The focus point may go this many metres past the plot edge.
@export var plot_margin := 50.0

var _target_focus := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := 0.0
var _target_distance := 0.0

var _focus := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _distance := 0.0

var _rotating := false
var _panning := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input_actions()
	_target_pitch = deg_to_rad(start_pitch_deg)
	_target_distance = clampf(start_distance, min_distance, max_distance)
	_focus = _target_focus
	_yaw = _target_yaw
	_pitch = _target_pitch
	_distance = _target_distance
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	# Presses only start here, so clicks on UI buttons don't move the camera.
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = true
			MOUSE_BUTTON_MIDDLE:
				_panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(-1.0, event.factor)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0, event.factor)


func _input(event: InputEvent) -> void:
	# Releases and drags are read here so a drag keeps working over UI.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
	elif event is InputEventMouseMotion:
		if _rotating:
			_target_yaw -= deg_to_rad(event.relative.x * drag_rotate_sensitivity)
			_target_pitch += deg_to_rad(event.relative.y * drag_rotate_sensitivity)
			_clamp_targets()
		elif _panning:
			_drag_pan(event.relative)


func _notification(what: int) -> void:
	# Stop dragging if the window loses focus mid-drag.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_rotating = false
		_panning = false


func _process(delta: float) -> void:
	_keyboard_input(delta)

	var t := 1.0 - exp(-smoothing * delta)
	_focus = _focus.lerp(_target_focus, t)
	_yaw = lerpf(_yaw, _target_yaw, t)
	_pitch = lerpf(_pitch, _target_pitch, t)
	# Zoom eases in log space so it feels even at every distance.
	_distance = exp(lerpf(log(_distance), log(_target_distance), t))
	_apply_transform()


# --- Input helpers ------------------------------------------------------------

func _keyboard_input(delta: float) -> void:
	var fast := fast_multiplier if Input.is_action_pressed("camera_fast") else 1.0

	var turn := Input.get_axis("camera_rotate_right", "camera_rotate_left")
	if turn != 0.0:
		_target_yaw += deg_to_rad(key_rotate_speed * fast) * turn * delta

	var move := Input.get_vector("camera_pan_left", "camera_pan_right",
		"camera_pan_forward", "camera_pan_back")
	if move != Vector2.ZERO:
		var speed := _target_distance * key_pan_speed * fast
		_target_focus += (_right() * move.x - _forward() * move.y) * speed * delta
		_clamp_targets()


func _drag_pan(relative: Vector2) -> void:
	# Metres of ground per screen pixel at the focus point, so the ground
	# roughly follows the cursor at any zoom level.
	var view_height := float(get_viewport().get_visible_rect().size.y)
	var metres_per_pixel := 2.0 * _distance * tan(deg_to_rad(fov) * 0.5) / maxf(view_height, 1.0)
	# The ground is foreshortened vertically when the camera is tilted low.
	var forward_scale := 1.0 / maxf(sin(_pitch), 0.3)
	_target_focus -= _right() * relative.x * metres_per_pixel
	_target_focus += _forward() * relative.y * metres_per_pixel * forward_scale
	_clamp_targets()


func _zoom(direction: float, factor: float) -> void:
	# factor is 0 for normal mouse wheels and fractional for smooth trackpads.
	var notches := factor if factor > 0.0 else 1.0
	_target_distance *= pow(zoom_step, direction * notches)
	_clamp_targets()


func _clamp_targets() -> void:
	_target_pitch = clampf(_target_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_target_distance = clampf(_target_distance, min_distance, max_distance)
	var plot := BuildGrid.get_plot_rect().grow(plot_margin)
	_target_focus.x = clampf(_target_focus.x, plot.position.x, plot.end.x)
	_target_focus.z = clampf(_target_focus.z, plot.position.y, plot.end.y)
	_target_focus.y = 0.0


# --- Camera placement -----------------------------------------------------------

func _apply_transform() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)) * _distance
	var pos := _focus + offset
	pos.y = maxf(pos.y, min_height)
	global_position = pos
	look_at(_focus, Vector3.UP)


## Direction "into the screen", flat on the ground.
func _forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Direction to the right of the screen, flat on the ground.
func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _register_input_actions() -> void:
	for action: String in ACTION_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in ACTION_KEYS[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)


## Glides the camera over to look at a ground point (keeping its angle and zoom).
func focus_on(point: Vector3) -> void:
	_target_focus = point
	_clamp_targets()


# --- Queries --------------------------------------------------------------------

## The ground point the camera is looking at.
func get_focus() -> Vector3:
	return _focus


## Current distance from the focus point, in metres.
func get_distance() -> float:
	return _distance
