extends Control
## Main menu (step 41): the game's first screen. Title, then Play (loads the
## airport), Settings (settings_menu.gd) and Quit. A plain flat background,
## no 3D, so it opens instantly on low-end PCs.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")
const GAME_SCENE := "res://scenes/main.tscn"
const TITLE := "Terminal Architect"

var _buttons: VBoxContainer
var _settings: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build_menu()
	# Nothing to simulate on the menu; Play starts the clock again.
	GameClock.set_paused(true)

	var background := ColorRect.new()
	background.color = UITheme.MENU_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)

	_buttons = VBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	stack.add_child(_buttons)

	var title := UITheme.label(TITLE, UITheme.MENU_TITLE_SIZE, UITheme.BAR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buttons.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	_buttons.add_child(spacer)

	var play := _add_button("Play", _play)
	_add_button("Settings", _show_settings.bind(true))
	_add_button("Quit", func() -> void: get_tree().quit())

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.back_pressed.connect(_show_settings.bind(false))
	stack.add_child(_settings)

	play.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _settings.visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		_show_settings(false)
		get_viewport().set_input_as_handled()


func _add_button(text: String, action: Callable) -> Button:
	var button := UITheme.menu_button(text)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	_buttons.add_child(button)
	return button


func _show_settings(open: bool) -> void:
	_buttons.visible = not open
	_settings.visible = open
	print("MAIN MENU | %s" % ("settings" if open else "menu"))


func _play() -> void:
	print("MAIN MENU | play")
	GameClock.set_paused(false)
	get_tree().change_scene_to_file(GAME_SCENE)
