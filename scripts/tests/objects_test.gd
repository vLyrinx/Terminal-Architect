extends Node3D
## Automatic test for the object placement system (checklist step 11).
## Run this scene on its own (F6). It places, rotates and deletes the test bench
## through commands, checks footprints, walls, IDs, undo and command data,
## prints PASS or FAIL for each check, then leaves the result on screen.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const PlaceCmd := preload("res://scripts/core/commands/place_object_command.gd")
const RotateCmd := preload("res://scripts/core/commands/rotate_object_command.gd")
const DeleteCmd := preload("res://scripts/core/commands/delete_object_command.gd")
const QUARTER := PI * 0.5

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _objects: PlacedObjectsScript
var _runner: CommandRunnerScript
var _bench: Resource
## Last command the runner refused.
var _last_failed: RefCounted


func _ready() -> void:
	print("TEST START | object placement")
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_objects = PlacedObjectsScript.new()
	_floor.placed_objects = _objects
	_walls = TerminalWallsScript.new()
	_walls.placed_objects = _objects
	add_child(_walls)
	_objects.terminal_floor = _floor
	_objects.terminal_walls = _walls
	add_child(_objects)
	_runner = CommandRunnerScript.new()
	_runner.placed_objects = _objects
	add_child(_runner)
	_runner.command_failed.connect(func(command: RefCounted) -> void: _last_failed = command)

	_bench = ObjectCatalog.get_def(&"test_bench")
	_expect("test bench loaded from data/objects", _bench != null)
	if _bench == null:
		print("TEST DONE | 1 FAILED")
		return
	_expect("bench data: 2 x 1, cost 500, has a model",
		_bench.footprint == Vector2i(2, 1) and _bench.cost == 500 and _bench.model != null)

	_expect("refused on grass", not _place(_corner(50, 50) + Vector3(0, 0, 0.5), 0.0)
		and _last_error() == "Needs terminal floor")

	_floor.set_rect(Rect2i(10, 10, 10, 10), true)
	_expect("bench placed on floor gets ID 1", _place(_corner(12, 12) + Vector3(0, 0, 0.5), 0.0) and _last_id() == 1)
	_expect("it blocks tiles (11,12) and (12,12)", _tiles(1) == [Vector2i(11, 12), Vector2i(12, 12)])
	_expect("it stands on the floor surface", is_equal_approx(_objects.get_object(1).position.y, TerminalFloorScript.THICKNESS))
	_expect("overlapping bench is refused", not _place(_corner(13, 12) + Vector3(0, 0, 0.5), 0.0)
		and _last_error() == "Blocked by another object")

	_expect("bench rotated 90 degrees gets ID 2", _place(_corner(15, 12) + Vector3(0.5, 0, 0), QUARTER) and _last_id() == 2)
	_expect("it blocks (15,11) and (15,12)", _tiles(2) == [Vector2i(15, 11), Vector2i(15, 12)])

	_expect("edge between its tiles counts as inside it", _objects.is_edge_inside_object(Vector2i(15, 12), true))
	_expect("wall drag across it skips that edge (2 of 3 built)", _walls.set_run(Vector2i(14, 12), Vector2i(17, 12), true) == 2)
	_expect("bench across a wall is refused", not _place(_corner(16, 12) + Vector3(0.5, 0, 0), QUARTER)
		and _last_error() == "Blocked by a wall")
	_expect("bench against the wall is fine (ID 3)", _place(_corner(17, 12) + Vector3(0, 0, 0.5), 0.0) and _last_id() == 3)

	var start_tiles := _tiles(1)
	var start_position: Vector3 = _objects.get_object(1).position
	_expect("rotate bench 1 in place", _rotate(1))
	_expect("it now blocks (11,11) and (11,12)", _tiles(1) == [Vector2i(11, 11), Vector2i(11, 12)])
	for i in 3:
		_rotate(1)
	_expect("four quarter turns bring it back", _tiles(1) == start_tiles
		and _objects.get_object(1).position.is_equal_approx(start_position))
	_expect("turning bench 3 across the wall is refused", not _rotate(3) and _last_error() == "Blocked by a wall"
		and _tiles(3) == [Vector2i(16, 12), Vector2i(17, 12)])

	_expect("delete bench 1", _runner.submit(DeleteCmd.new(1)) and _objects.get_object(1) == null)
	_expect("its tiles are free", _objects.get_object_at(Vector2i(11, 12)) == 0)
	_expect("undo brings it back with ID 1", _runner.undo_last() and _objects.get_object(1) != null
		and _objects.get_object_at(Vector2i(11, 12)) == 1)
	_runner.submit(DeleteCmd.new(1))
	_expect("IDs are never reused (next is 4)", _place(_corner(12, 16) + Vector3(0, 0, 0.5), 0.0) and _last_id() == 4)

	var data: Dictionary = JSON.parse_string(JSON.stringify(_runner.history[-1].to_dict()))
	var copy: RefCounted = CommandRunnerScript.command_from_dict(data)
	_expect("place command survives JSON and back", copy != null and copy.get_type() == "place_object"
		and copy.def_id == &"test_bench" and copy.object_id == 4 and copy.position.is_equal_approx(_runner.history[-1].position))
	_expect("rotate and delete commands too",
		CommandRunnerScript.command_from_dict(RotateCmd.new(2, Vector3.ONE, 1.0).to_dict()).new_rotation == 1.0
		and CommandRunnerScript.command_from_dict(DeleteCmd.new(2).to_dict()).object_id == 2)

	var free_tiles: Array[Vector2i] = _objects.footprint_tiles(_bench, BuildGrid.tile_to_world(Vector2i(5, 5)), deg_to_rad(45.0))
	_expect("free rotation footprint works (45 degrees covers %d tiles)" % free_tiles.size(),
		free_tiles.has(Vector2i(5, 5)) and free_tiles.size() >= 1)

	_expect("floor under an object can't be removed",
		_floor.set_rect(Rect2i(11, 16, 2, 1), false) == 0 and _floor.has_floor(Vector2i(12, 16)))
	_expect("floor next to it still can", _floor.set_rect(Rect2i(13, 16, 1, 1), false) == 1)

	# Core terminal objects (checklist step 12): each loads and places on the floor.
	var ids := ObjectCatalog.get_all().map(func(d: Resource) -> String: return String(d.id))
	_expect("catalog in menu order: %s" % ", ".join(ids), ids == ["checkin_desk", "security_scanner",
		"seat_row", "toilet_block", "gate_desk", "test_bench"])
	_floor.set_rect(Rect2i(30, 10, 30, 10), true)
	var x := 31
	for def: Resource in ObjectCatalog.get_all():
		if def.id == &"test_bench":
			continue
		var pos: Vector3 = _objects.snap_position(def, _corner(x, 14) + Vector3(def.footprint.x * 0.5, 0, 0), 0.0)
		var placed := _runner.submit(PlaceCmd.new(def.id, pos, 0.0))
		var area: int = def.footprint.x * def.footprint.y
		_expect("%s (%s) places with a %d x %d footprint" % [def.display_name, def.category,
			def.footprint.x, def.footprint.y], placed and _objects.get_object(_last_id()).tiles.size() == area)
		x += def.footprint.x + 2

	_add_view(_corner(43, 14), 16.0)
	for i in 3:
		await RenderingServer.frame_post_draw
	# Screenshot of the result, for checking the models without the editor.
	var shot := get_viewport().get_texture().get_image()
	shot.save_png("user://objects_test.png")
	print("INFO | screenshot saved to %s" % ProjectSettings.globalize_path("user://objects_test.png"))
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


func _corner(x: int, y: int) -> Vector3:
	return BuildGrid.tile_corner_to_world(Vector2i(x, y))


## Places a bench centred near a world point, snapped like the object tool does.
func _place(world_pos: Vector3, yaw: float) -> bool:
	var pos: Vector3 = _objects.snap_position(_bench, world_pos, yaw)
	return _runner.submit(PlaceCmd.new(&"test_bench", pos, yaw))


## Rotates an object a quarter turn in place, like the edit tool does.
func _rotate(id: int) -> bool:
	var obj: RefCounted = _objects.get_object(id)
	var new_rotation := wrapf(obj.rotation + QUARTER, 0.0, TAU)
	var pos: Vector3 = _objects.rotate_in_place(_bench, obj.position, obj.rotation, new_rotation)
	return _runner.submit(RotateCmd.new(id, pos, new_rotation))


func _last_id() -> int:
	return _runner.history[-1].object_id


func _last_error() -> String:
	return _last_failed.error if _last_failed else ""


## An object's tiles as a plain sorted array, easy to compare.
func _tiles(id: int) -> Array:
	var tiles: Array = []
	tiles.append_array(_objects.get_object(id).tiles)
	tiles.sort()
	return tiles


## Camera and sun looking down at a point, so the result can be seen.
func _add_view(target: Vector3, distance := 12.0) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = target + Vector3(0, 0.75, 0.66) * distance
	camera.look_at(target)
	camera.current = true


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
