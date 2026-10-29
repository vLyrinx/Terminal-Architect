extends Node
## Automatic test for the game UI (checklist step 15).
## Run this scene on its own (F6). It loads the main scene, then checks the top
## bar, the build menu (categories, items, selecting tools, Esc), the demolish
## tool and the F3 debug overlay, and prints PASS or FAIL for each check.
## It also saves screenshots to user:// (the path is printed) for a visual check.

const MAIN := preload("res://scenes/main.tscn")
const WallsCmd := preload("res://scripts/core/commands/set_walls_command.gd")
const PlaceCmd := preload("res://scripts/core/commands/place_object_command.gd")
const PlaceRunwayCmd := preload("res://scripts/core/commands/place_runway_command.gd")

var _failures := 0
var _main: Node


func _ready() -> void:
	print("TEST START | game UI")
	_main = MAIN.instantiate()
	add_child(_main)
	await _frames(5)

	var ui: Control = _main.get_node("UI/Root")
	var top_bar: Control = ui.get_node("TopBar")
	var menu: Control = ui.get_node("BuildMenu")
	var overlay: Control = ui.get_node("DebugOverlay")
	var manager: Node = _main.get_node("Building")
	var runner: Node = _main.get_node("Commands")

	# Top bar
	_expect("top bar shows the balance", top_bar._balance.text == Money.format(Money.balance))
	_expect("top bar shows date and time", top_bar._date.text == "Fri 1 Jan 2027" and top_bar._time.text == "06:00")
	top_bar._speed_buttons[2].pressed.emit()
	_expect("4x button sets 4x", is_equal_approx(GameClock.speed, 4.0) and not GameClock.paused)
	_key(KEY_SPACE)
	_expect("Space pauses and the pause button shows it", GameClock.paused and top_bar._pause_button.button_pressed)
	top_bar._pause_button.pressed.emit()
	_expect("pause button resumes", not GameClock.paused and top_bar._speed_buttons[2].button_pressed)
	_key(KEY_1)
	_expect("key 1 sets 1x and the 1x button follows", top_bar._speed_buttons[0].button_pressed)

	# Categories
	var counts := {}
	for id: String in menu._items:
		counts[id] = menu._items[id].size()
	print("INFO | menu items per category: %s" % counts)
	_expect("structures has floor, walls, room and doors", counts.structures == 4)
	_expect("zones has three zones", counts.zones == 3)
	_expect("terminal has the five core objects", counts.terminal == 5)
	_expect("airside has the three runway sizes and is enabled",
		counts.airside == 3 and not menu._category_buttons.airside.disabled)
	_expect("demolish has demolish and select", counts.demolish == 2)
	_expect("panel starts closed", not menu._item_panel.visible)

	# Open Terminal, pick the security scanner
	menu._category_buttons.terminal.pressed.emit()
	await _frames(2)
	_expect("Terminal opens its panel with 5 cards", menu._item_panel.visible and menu._cards.size() == 5)
	menu._cards["object:security_scanner"].pressed.emit()
	await _frames(2)
	var tool: Node = manager.active_tool
	_expect("picking a card selects its tool and object",
		tool != null and tool.name == "ObjectTool" and tool.get_active_item_id() == "object:security_scanner")
	_expect("the picked card is highlighted", menu._cards["object:security_scanner"].button_pressed)
	_expect("tool strip shows the name and cost", menu._tool_info.visible
		and menu._tool_title.text.begins_with("Security scanner"))
	await _screenshot("terminal_panel")

	# Esc cancels the tool and closes the panel
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect("Esc cancels the tool", manager.active_tool == null)
	_expect("Esc closes the panel", not menu._item_panel.visible and not menu._tool_info.visible)

	# Shortcut key opens the tool's category
	_key(KEY_L)
	await _frames(2)
	_expect("L picks walls and opens Structures", manager.active_tool != null and menu._open_category == "structures"
		and menu._cards["walls_line"].button_pressed)
	menu._cards["walls_room"].pressed.emit()
	await _frames(1)
	_expect("Room card switches the wall tool to Room mode", manager.active_tool.mode == 1
		and menu._cards["walls_room"].button_pressed and not menu._cards["walls_line"].button_pressed)
	menu._cards["walls_room"].pressed.emit()
	await _frames(1)
	_expect("clicking the selected card puts the tool away and keeps the panel",
		manager.active_tool == null and menu._item_panel.visible)
	_key(KEY_ESCAPE)
	await _frames(1)
	_expect("Esc with no tool closes the panel", not menu._item_panel.visible)

	# Demolish: a 6 x 6 room with a seat row in it
	runner.submit(WallsCmd.new([[Vector2i(100, 100), Vector2i(106, 100)], [Vector2i(106, 100), Vector2i(106, 106)],
		[Vector2i(106, 106), Vector2i(100, 106)], [Vector2i(100, 106), Vector2i(100, 100)]], true, 0,
		Rect2i(100, 100, 6, 6)))
	var objects: Node = _main.get_node("PlacedObjects")
	var seats := ObjectCatalog.get_def(&"seat_row")
	var pos: Vector3 = objects.snap_position(seats, BuildGrid.tile_to_world(Vector2i(103, 103)), 0.0)
	runner.submit(PlaceCmd.new(&"seat_row", pos, 0.0))
	var floor_node: Node = _main.get_node("TerminalFloor")
	var walls_node: Node = _main.get_node("TerminalWalls")
	_expect("room built for demolish", floor_node.get_floor_tile_count() >= 36 and objects.get_count() == 1)
	var before := Money.balance
	var demolish: Node = manager.get_node("DemolishTool")
	demolish.press(Vector2i(100, 100))
	demolish.release(Vector2i(105, 105), true)
	_expect("demolish removes floor, walls and the object", floor_node.get_floor_tile_count() == 0
		and walls_node.get_piece_counts().walls == 0 and objects.get_count() == 0)
	_expect("demolish refunds money", Money.balance > before)

	# Runway from the Airside menu (checklist step 16)
	menu._category_buttons.airside.pressed.emit()
	await _frames(1)
	menu._cards["runway:medium"].pressed.emit()
	await _frames(1)
	_expect("Airside card selects the runway tool at medium size", manager.active_tool != null
		and manager.active_tool.name == "RunwayTool" and manager.active_tool.get_active_item_id() == "runway:medium")
	_expect("tool strip shows the runway width", menu._tool_title.text.begins_with("Medium runway (45 m wide)"))
	_key(KEY_ESCAPE)
	runner.submit(PlaceRunwayCmd.new(&"medium", Vector2i(1500, 1000), Vector2i(3500, 1000)))
	var runways: Node = _main.get_node("Runways")
	_expect("runway built in the main scene", runways.get_count() == 1)
	var camera: Camera3D = _main.get_node("Camera3D")
	camera.set_process(false)
	var threshold: Vector3 = runways.get_ends()[0].position
	camera.global_position = threshold + Vector3(-60, 70, 55)
	camera.look_at(threshold + Vector3(60, 0, 0))
	await _frames(3)
	await _screenshot("runway_threshold")
	camera.global_position = threshold + Vector3(1000, 1400, 1300)
	camera.look_at(threshold + Vector3(1000, 0, 0))
	await _frames(3)
	await _screenshot("runway_whole")
	camera.set_process(true)

	# Debug overlay
	_expect("debug overlay starts hidden", not overlay.visible)
	_key(KEY_F3)
	await _frames(3)
	_expect("F3 shows the debug overlay", overlay.visible and overlay._label.text.contains("ticks"))
	await _screenshot("debug_overlay")
	_key(KEY_F3)
	_expect("F3 hides it again", not overlay.visible)

	await _screenshot("idle")
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures else 0)


func _expect(what: String, ok: bool) -> void:
	print("%s | %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://ui_test_%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	print("INFO | screenshot %s" % ProjectSettings.globalize_path(path))
