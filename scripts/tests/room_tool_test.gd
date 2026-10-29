extends Node3D
## Automatic test for the wall tool's Line and Room modes.
## Run this scene on its own (F6). It drives the real wall tool (as if the mouse
## had been dragged), checks walls and floor, prints PASS or FAIL for each check,
## and saves a screenshot to user://room_tool_test.png.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const WallToolScript := preload("res://scripts/building/tools/wall_tool.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _tool: WallToolScript


func _ready() -> void:
	print("TEST START | wall tool line and room modes")
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_walls = TerminalWallsScript.new()
	_walls.terminal_floor = _floor
	add_child(_walls)
	var runner := CommandRunnerScript.new()
	runner.terminal_floor = _floor
	runner.terminal_walls = _walls
	add_child(runner)
	_tool = WallToolScript.new()
	_tool.terminal_walls = _walls
	_tool.command_runner = runner
	add_child(_tool)

	_tool.mode = WallToolScript.Mode.ROOM
	_drag(Vector2i(10, 10), Vector2i(16, 14))
	_expect("6 x 4 room lays 24 floor tiles", _floor.get_floor_tile_count() == 24)
	_expect("and builds 20 wall pieces all round", _walls.get_piece_counts().walls == 20)
	_expect("corners join cleanly: 2 long + 2 short wall boxes", _verts() == 4 * 20)

	_drag(Vector2i(20, 14), Vector2i(16, 10))  # dragged the other way, sharing the x = 16 wall
	_expect("room next door adds 16 floor tiles", _floor.get_floor_tile_count() == 40)
	_expect("and only 12 walls (the shared side is already there)", _walls.get_piece_counts().walls == 32)

	_drag(Vector2i(10, 10), Vector2i(10, 10))
	_expect("a zero-size room builds nothing", _walls.get_piece_counts().walls == 32 and _floor.get_floor_tile_count() == 40)

	_tool.mode = WallToolScript.Mode.LINE
	_drag(Vector2i(10, 20), Vector2i(15, 20))
	_expect("line mode still builds one straight wall (5 pieces, no floor)",
		_walls.get_piece_counts().walls == 37 and _floor.get_floor_tile_count() == 40)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	var centre := BuildGrid.tile_corner_to_world(Vector2i(15, 14))
	camera.position = centre + Vector3(-6, 12, 12)
	camera.look_at(centre)
	camera.current = true
	_floor.set_roof_visible(false)
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://room_tool_test.png")
	print("INFO | screenshot saved to %s" % ProjectSettings.globalize_path("user://room_tool_test.png"))

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


## Does what a mouse drag from one grid corner to another does in the tool.
func _drag(from: Vector2i, to: Vector2i) -> void:
	_tool._dragging = true
	_tool._start = from
	_tool._end = _tool._straighten(to) if _tool.mode == WallToolScript.Mode.LINE else to
	_tool.release(Vector2i.ZERO, true)


func _verts() -> int:
	var mi := _walls.get_node("Chunk_0_0_0") as MeshInstance3D
	return mi.mesh.surface_get_array_len(0)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
