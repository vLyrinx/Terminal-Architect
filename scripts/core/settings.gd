extends Node
## Settings (autoload, step 41).
##
## Player options, loaded from and saved to user://settings.cfg. Saved values
## are applied on startup; every change is applied, saved and announced with
## the `changed` signal straight away. Read values with get_value() and change
## them with set_value(), using the keys in DEFAULTS.

## Emitted after a setting changes (and has been applied and saved).
signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Common PC resolutions (16:9, 16:10, 4:3, 5:4 and ultrawide), smallest first.
## The settings screen only offers the ones that fit the player's monitor.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1024, 576), Vector2i(1024, 768), Vector2i(1152, 648), Vector2i(1280, 720),
	Vector2i(1280, 800), Vector2i(1280, 960), Vector2i(1280, 1024), Vector2i(1360, 768),
	Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1536, 864), Vector2i(1600, 900),
	Vector2i(1600, 1200), Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440),
	Vector2i(3840, 1600), Vector2i(3840, 2160),
]
## Frame rate caps; 0 means unlimited.
const FPS_CAPS: Array[int] = [30, 60, 120, 0]
const SENSITIVITY_MIN := 0.25
const SENSITIVITY_MAX := 2.0

const DEFAULTS := {
	"fullscreen": false,
	"resolution": Vector2i(1280, 720),  # windowed only
	"fps_cap": 60,
	"vsync": true,
	"master_volume": 100,  # percent
	"mouse_sensitivity": 1.0,  # scales the camera's right drag rotation
}

var _values := DEFAULTS.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	for key: String in _values:
		_apply(key)


func get_value(key: String) -> Variant:
	return _values[key]


func set_value(key: String, value: Variant) -> void:
	value = _validated(key, value)
	if _values[key] == value:
		return
	_values[key] = value
	_apply(key)
	_save()
	changed.emit(key, value)


## The resolutions that fit on the screen the window is on (always at least one).
func get_available_resolutions() -> Array[Vector2i]:
	if DisplayServer.get_name() == "headless":
		return RESOLUTIONS.duplicate()
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var fits: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			fits.append(r)
	if fits.is_empty():
		fits.append(RESOLUTIONS[0])
	return fits


## Multiplier for the camera's mouse drag rotation (orbit_camera.gd).
func get_mouse_sensitivity() -> float:
	return _values.mouse_sensitivity


# --- Load and save ------------------------------------------------------------

func _load() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		_values[key] = _validated(key, file.get_value(SECTION, key, DEFAULTS[key]))


func _save() -> void:
	var file := ConfigFile.new()
	for key: String in _values:
		file.set_value(SECTION, key, _values[key])
	var err := file.save(PATH)
	if err != OK:
		push_warning("SETTINGS | could not save %s (error %d)" % [PATH, err])


## Returns the value if it is allowed for the key, or the default if not
## (so a hand-edited or old settings file can't break the game).
func _validated(key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	match key:
		"fullscreen", "vsync":
			return value if value is bool else fallback
		"resolution":
			return value if value is Vector2i and RESOLUTIONS.has(value) else fallback
		"fps_cap":
			return int(value) if (value is int or value is float) and FPS_CAPS.has(int(value)) else fallback
		"master_volume":
			return clampi(int(value), 0, 100) if (value is int or value is float) else fallback
		"mouse_sensitivity":
			return clampf(float(value), SENSITIVITY_MIN, SENSITIVITY_MAX) if (value is int or value is float) else fallback
	return fallback


# --- Applying -------------------------------------------------------------------

func _apply(key: String) -> void:
	match key:
		"fullscreen", "resolution":
			_apply_window()
		"fps_cap":
			Engine.max_fps = _values.fps_cap
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if _values.vsync else DisplayServer.VSYNC_DISABLED)
		"master_volume":
			var volume: float = _values.master_volume / 100.0
			AudioServer.set_bus_mute(0, volume <= 0.0)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _values.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Never open a window bigger than the screen it is on.
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size: Vector2i = _values.resolution
	size = Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
