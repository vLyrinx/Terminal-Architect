extends Control
## Pause menu (step 41): Esc in the game opens Resume, Settings and Quit to Menu.
##
## Esc only opens it when nothing else wants Esc: an active build tool cancels
## first (build_manager.gd), and an open flight list or inspector selection
## closes first (they sit later in the scene tree, so they see Esc before this).
## While open the game clock is paused and the camera stops; Resume (or Esc)
## puts the clock back the way it was.

signal toggled(open: bool)

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
## Keys still passed on while the menu is open, so buttons work from the keyboard.
const UI_ACTIONS := ["ui_accept", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]

## Build mode (build_manager.gd); while a tool is active Esc is left to it.
@export var build_manager: Node
## The orbit camera, stopped while the menu is open.
@export var camera: Node

var _buttons: VBoxContainer
var _settings: Control
var _resume: Button
var _clock_was_paused := false
var _camera_mode := Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build_menu()
	visible = false

	# Dims the airport and keeps clicks and the mouse wheel off it.
	var shade := ColorRect.new()
	shade.color = Color(UITheme.BAR, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.RADIUS, 28, 20))
	stack.add_child(panel)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	panel.add_child(_buttons)
	var title := UITheme.label("Paused", UITheme.MENU_FONT_SIZE + 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buttons.add_child(title)
	_resume = _add_button("Resume", close)
	_add_button("Settings", _show_settings.bind(true))
	_add_button("Quit to Menu", _quit_to_menu)

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.back_pressed.connect(_show_settings.bind(false))
	stack.add_child(_settings)


func _unhandled_input(event: InputEvent) -> void:
	if visible or not _is_escape(event):
		return
	if build_manager != null and build_manager.is_building():
		return  # Esc cancels the build tool instead
	open()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	if _is_escape(event):
		if _settings.visible:
			_show_settings(false)
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	# Other game keys (Space, 1/2/3, B, G, tool shortcuts) do nothing while paused.
	for action: String in UI_ACTIONS:
		if event.is_action(action):
			return
	get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	_clock_was_paused = GameClock.paused
	GameClock.set_paused(true)
	if camera != null:
		_camera_mode = camera.process_mode
		camera.process_mode = Node.PROCESS_MODE_DISABLED
	_show_settings(false)
	visible = true
	_resume.grab_focus()
	print("PAUSE MENU | open")
	toggled.emit(true)


## Resume: hides the menu and puts the clock back the way it was.
func close() -> void:
	if not visible:
		return
	visible = false
	_restore()
	print("PAUSE MENU | closed")
	toggled.emit(false)


func _restore() -> void:
	GameClock.set_paused(_clock_was_paused)
	if camera != null:
		camera.process_mode = _camera_mode


func _add_button(text: String, action: Callable) -> Button:
	var button := UITheme.menu_button(text)
	button.pressed.connect(action)
	_buttons.add_child(button)
	return button


func _show_settings(show_settings: bool) -> void:
	_buttons.get_parent().visible = not show_settings
	_settings.visible = show_settings


func _quit_to_menu() -> void:
	print("PAUSE MENU | quit to menu")
	visible = false
	_restore()
	get_tree().change_scene_to_file(MENU_SCENE)


static func _is_escape(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and event.physical_keycode == KEY_ESCAPE
