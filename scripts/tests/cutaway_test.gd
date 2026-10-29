extends Node3D
## Automatic test for the roof and wall cutaway (checklist step 13).
## Run this scene on its own (F6). It builds a small walled room with a door and
## an inside wall, checks roofs, wall data and the cutaway rules, then saves
## screenshots with the cutaway off and on from two directions to user://
## (the Output panel shows the folder) and leaves the last view on screen.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const CutawayScript := preload("res://scripts/camera/cutaway.gd")

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _objects: PlacedObjectsScript
var _cutaway: CutawayScript
var _camera: Camera3D


func _ready() -> void:
	print("TEST START | roof and wall cutaway")
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_walls = TerminalWallsScript.new()
	_walls.terminal_floor = _floor
	add_child(_walls)
	_objects = PlacedObjectsScript.new()
	_objects.terminal_floor = _floor
	_objects.terminal_walls = _walls
	add_child(_objects)
	_cutaway = CutawayScript.new()
	_cutaway.terminal_floor = _floor
	_cutaway.terminal_walls = _walls
	add_child(_cutaway)

	# A 12 x 8 room: walls all round, an inside wall at x = 16 with a door, and a front door.
	_walls.set_run(Vector2i(10, 10), Vector2i(22, 10), true)
	_walls.set_run(Vector2i(22, 10), Vector2i(22, 18), true)
	_walls.set_run(Vector2i(22, 18), Vector2i(10, 18), true)
	_walls.set_run(Vector2i(10, 18), Vector2i(10, 10), true)
	_walls.set_run(Vector2i(16, 10), Vector2i(16, 18), true)
	_walls.set_door(Vector2i(16, 13), false, true)
	_walls.set_door(Vector2i(13, 10), true, true)
	_floor.set_rect(Rect2i(10, 10, 12, 8), true)  # floor after walls: walls must update
	_place(&"checkin_desk", Vector2i(12, 15), 0.0)
	_place(&"seat_row", Vector2i(19, 13), 0.0)
	_place(&"gate_desk", Vector2i(19, 16), PI)

	_expect("roof built over the floor", _floor.get_node_or_null("Roofs/Roof_0_0_0") != null)
	# The roof reaches the outer face of the walls: the floor outline grown by half
	# a wall thickness. Its top area is then area + perimeter * h + 4 * h * h exactly,
	# which also proves no roof pieces overlap.
	var h := TerminalWallsScript.HALF
	var roof_box: AABB = _floor.get_node("Roofs/Roof_0_0_0").mesh.get_aabb()
	_expect("roof covers the walls: %.2f x %.2f m" % [roof_box.size.x, roof_box.size.z],
		is_equal_approx(roof_box.size.x, 12.0 + 2.0 * h) and is_equal_approx(roof_box.size.z, 8.0 + 2.0 * h))
	_expect("room roof has no overlaps (top area %.2f)" % _roof_top_area("Roof_0_0_0"),
		is_equal_approx(_roof_top_area("Roof_0_0_0"), 96.0 + 40.0 * h + 4.0 * h * h))
	_floor.set_rect(Rect2i(40, 10, 4, 4), true)  # an L shape, with one inner corner
	_floor.set_rect(Rect2i(40, 14, 2, 3), true)
	_expect("L-shaped roof has no overlaps (top area %.2f)" % _roof_top_area("Roof_1_0_0"),
		is_equal_approx(_roof_top_area("Roof_1_0_0"), 22.0 + 22.0 * h + 4.0 * h * h))
	_floor.set_roof_visible(false)
	_expect("roof can be hidden", not _floor.get_node("Roofs").visible)
	_floor.set_roof_visible(true)

	_expect("wall at z = 10 knows the floor is on its +Z side", _wall_sides_at(Vector2(13.5, 10), true) == Vector2(1, 0))
	_expect("wall at z = 18 knows the floor is on its -Z side", _wall_sides_at(Vector2(13.5, 18), true) == Vector2(0, 1))
	_expect("inside wall has floor on both sides", _wall_sides_at(Vector2(16, 11.5), false) == Vector2(1, 1))
	_expect("wall at x = 10 knows the floor is on its +X side", _wall_sides_at(Vector2(10, 14), false) == Vector2(1, 0))

	_expect("zoomed in: cut", CutawayScript.should_cut(true, false, 50.0, false))
	_expect("zoomed out over grass: no cut", not CutawayScript.should_cut(true, false, 120.0, false))
	_expect("medium distance looking at the terminal: cut", CutawayScript.should_cut(true, false, 120.0, true))
	_expect("far out over the terminal: no cut", not CutawayScript.should_cut(true, false, 250.0, true))
	_expect("cutaway off: never cut", not CutawayScript.should_cut(false, false, 20.0, true))
	_expect("hysteresis keeps it steady near the threshold",
		CutawayScript.should_cut(true, true, 93.0, false) and not CutawayScript.should_cut(true, false, 87.0, false))
	_expect("look direction to axes", CutawayScript.view_direction(Vector3(0.1, -0.7, 0.7)) == Vector2(0, 1)
		and CutawayScript.view_direction(Vector3(-1, -1, -1)) == Vector2(-1, -1))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	var centre := BuildGrid.tile_corner_to_world(Vector2i(16, 14))

	await _shot("south_off", centre, Vector3(0, 14, -14), false)
	await _shot("south_on", centre, Vector3(0, 14, -14), true)
	await _shot("diagonal_off", centre, Vector3(12, 14, 12), false)
	await _shot("diagonal_on", centre, Vector3(12, 14, 12), true)
	print("INFO | screenshots saved in %s" % ProjectSettings.globalize_path("user://"))

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


func _place(id: StringName, tile: Vector2i, yaw: float) -> void:
	var def := ObjectCatalog.get_def(id)
	var pos: Vector3 = _objects.snap_position(def, BuildGrid.tile_to_world(tile), yaw)
	_objects.add_object(id, pos, yaw)


## CUSTOM0 sides flags (y, z) of the nearest wall vertex running the given way
## to a grid point (in tile units), as Vector2(+side has floor, -side has floor).
func _wall_sides_at(point: Vector2, horizontal: bool) -> Vector2:
	var mi := _walls.get_node("Chunk_0_0_0") as MeshInstance3D
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var target := BuildGrid.origin + Vector3(point.x, 0, point.y)
	var axis := 0.0 if horizontal else 1.0
	var best := -1
	var best_distance := INF
	for i in verts.size():
		if custom[i * 4] != axis:
			continue
		var d := Vector2(verts[i].x - target.x, verts[i].z - target.z).length()
		if d < best_distance:
			best_distance = d
			best = i
	return Vector2(custom[best * 4 + 1], custom[best * 4 + 2])


## Total area of the upward faces at the top of a roof chunk, in square metres.
func _roof_top_area(chunk_name: String) -> float:
	var mesh: Mesh = _floor.get_node("Roofs/" + chunk_name).mesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var top := mesh.get_aabb().end.y
	var area := 0.0
	for q in range(0, verts.size(), 4):  # the mesh builder adds four vertices per quad
		# Godot stores normals compressed, so they come back only roughly (0, 1, 0).
		if normals[q].y < 0.99 or not is_equal_approx(verts[q].y, top):
			continue
		var lo := verts[q]
		var hi := verts[q]
		for i in 4:
			lo = lo.min(verts[q + i])
			hi = hi.max(verts[q + i])
		area += (hi.x - lo.x) * (hi.z - lo.z)
	return area


func _shot(shot_name: String, target: Vector3, offset: Vector3, cut: bool) -> void:
	_camera.position = target + offset
	_camera.look_at(target)
	_cutaway.apply(cut, CutawayScript.view_direction(-_camera.global_basis.z))
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://cutaway_%s.png" % shot_name)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
