extends PanelContainer
## Settings screen (step 41), used by the main menu and the pause menu.
##
## Every control writes straight to the Settings autoload, which applies and
## saves the value. Below them is a read-only list of the current controls.
## Back emits back_pressed; the screen that opened it decides what to show next.

signal back_pressed

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const DISPLAY_MODES := ["Windowed", "Fullscreen"]
const CONTROLS := [
	["Right drag", "Rotate camera"],
	["Middle drag", "Pan camera"],
	["WASD / Arrows", "Pan camera"],
	["Q / E", "Rotate camera"],
	["Mouse wheel", "Zoom"],
	["Space", "Pause"],
	["1 / 2 / 3", "Game speed"],
	["B", "Build mode"],
	["G", "Toggle grid"],
	["Esc", "Cancel / pause menu"],
]

var _display_mode: OptionButton
var _resolution: OptionButton
var _fps_cap: OptionButton
var _vsync: CheckButton
var _volume: HSlider
var _volume_label: Label
var _sensitivity: HSlider
var _sensitivity_label: Label


func _ready() -> void:
	theme = UITheme.build_menu()
	add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.RADIUS, 28, 20))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	column.add_child(UITheme.label("Settings", UITheme.MENU_FONT_SIZE + 10))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)

	_display_mode = _option(grid, "Display mode", DISPLAY_MODES)
	_display_mode.item_selected.connect(func(i: int) -> void: Settings.set_value("fullscreen", i == 1))

	var resolutions: Array = []
	for r in Settings.RESOLUTIONS:
		resolutions.append("%d x %d" % [r.x, r.y])
	_resolution = _option(grid, "Resolution", resolutions)
	_resolution.item_selected.connect(func(i: int) -> void:
		Settings.set_value("resolution", Settings.RESOLUTIONS[i]))

	var caps: Array = []
	for cap in Settings.FPS_CAPS:
		caps.append(str(cap) if cap > 0 else "Unlimited")
	_fps_cap = _option(grid, "Frame rate cap", caps)
	_fps_cap.item_selected.connect(func(i: int) -> void: Settings.set_value("fps_cap", Settings.FPS_CAPS[i]))

	grid.add_child(UITheme.label("VSync", UITheme.MENU_FONT_SIZE))
	_vsync = CheckButton.new()
	_vsync.toggled.connect(func(on: bool) -> void: Settings.set_value("vsync", on))
	grid.add_child(_vsync)

	_volume = _slider(grid, "Master volume", 0.0, 100.0, 1.0)
	_volume_label = _volume.get_parent().get_child(1)
	_volume.value_changed.connect(func(v: float) -> void: Settings.set_value("master_volume", int(v)))

	_sensitivity = _slider(grid, "Camera mouse sensitivity",
		Settings.SENSITIVITY_MIN, Settings.SENSITIVITY_MAX, 0.05)
	_sensitivity_label = _sensitivity.get_parent().get_child(1)
	_sensitivity.value_changed.connect(func(v: float) -> void: Settings.set_value("mouse_sensitivity", v))

	column.add_child(_controls_panel())

	var back := UITheme.menu_button("Back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: back_pressed.emit())
	column.add_child(back)

	Settings.changed.connect(func(_key: String, _value: Variant) -> void: _refresh())
	_refresh()


## Shows the saved values (without emitting the controls' own signals).
func _refresh() -> void:
	_display_mode.select(1 if Settings.get_value("fullscreen") else 0)
	_resolution.select(maxi(Settings.RESOLUTIONS.find(Settings.get_value("resolution")), 0))
	_resolution.disabled = Settings.get_value("fullscreen")
	_fps_cap.select(maxi(Settings.FPS_CAPS.find(Settings.get_value("fps_cap")), 0))
	_vsync.set_pressed_no_signal(Settings.get_value("vsync"))
	_volume.set_value_no_signal(Settings.get_value("master_volume"))
	_volume_label.text = "%d%%" % Settings.get_value("master_volume")
	_sensitivity.set_value_no_signal(Settings.get_value("mouse_sensitivity"))
	_sensitivity_label.text = "%.2fx" % Settings.get_value("mouse_sensitivity")


func _option(grid: GridContainer, text: String, items: Array) -> OptionButton:
	grid.add_child(UITheme.label(text, UITheme.MENU_FONT_SIZE))
	var option := OptionButton.new()
	option.custom_minimum_size.x = UITheme.MENU_BUTTON_SIZE.x
	for item: String in items:
		option.add_item(item)
	grid.add_child(option)
	return option


## A slider with its value shown to the right (the label is the row's second child).
func _slider(grid: GridContainer, text: String, low: float, high: float, step: float) -> HSlider:
	grid.add_child(UITheme.label(text, UITheme.MENU_FONT_SIZE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size.x = UITheme.MENU_BUTTON_SIZE.x - 70
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := UITheme.label("", UITheme.MENU_FONT_SIZE)
	value.custom_minimum_size.x = 60
	row.add_child(value)
	grid.add_child(row)
	return slider


func _controls_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BAR, UITheme.RADIUS, 16, 10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(UITheme.label("Controls", UITheme.MENU_FONT_SIZE, UITheme.TEXT_DIM))

	# Two key / action pairs per row so the list stays short.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for entry: Array in CONTROLS:
		grid.add_child(UITheme.label(entry[0], UITheme.MENU_FONT_SIZE, UITheme.ACCENT_HOVER))
		grid.add_child(UITheme.label(entry[1], UITheme.MENU_FONT_SIZE))
	return panel
