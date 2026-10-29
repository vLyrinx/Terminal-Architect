extends Node3D
## Automatic test for terminal floor tiles (checklist step 8).
## Run this scene on its own (F6). It lays and removes floor through the same
## calls the floor tool uses, checks tile counts and the merged chunk meshes,
## prints PASS or FAIL for each check, then waits for you to close the window.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")

var _failures := 0
var _floor: TerminalFloorScript


func _ready() -> void:
	print("TEST START | floor tiles")
	_floor = TerminalFloorScript.new()
	add_child(_floor)

	var hall := Rect2i(10, 10, 10, 6)
	_expect("count before laying is the full area", _floor.count_changes(hall, true) == 60)
	_expect("laying 10 x 6 changes 60 tiles", _floor.set_rect(hall, true) == 60)
	_expect("laying again changes nothing", _floor.set_rect(hall, true) == 0)
	_expect("tile inside has floor", _floor.has_floor(Vector2i(15, 12)))
	_expect("tile outside has no floor", not _floor.has_floor(Vector2i(20, 12)))
	_expect("surface is on top of the slab",
		is_equal_approx(_floor.get_surface_height(Vector2i(15, 12)), TerminalFloorScript.THICKNESS))
	_expect("one chunk mesh", _chunk_count() == 1)
	# A solid rectangle merges to 1 top quad and 4 side quads: 5 quads, 20 vertices.
	_expect("solid rectangle merges to 5 quads (%d vertices)" % _vertex_count(), _vertex_count() == 20)

	_expect("removing a 2 x 2 hole changes 4 tiles", _floor.set_rect(Rect2i(14, 12, 2, 2), false) == 4)
	_expect("hole tile has no floor", not _floor.has_floor(Vector2i(14, 12)))
	_expect("total is 56 tiles", _floor.get_floor_tile_count() == 56)
	_expect("count of removable tiles over the hole edge", _floor.count_changes(Rect2i(13, 12, 2, 1), false) == 1)

	_floor.set_rect(Rect2i(28, 0, 8, 4), true)
	_expect("floor across a chunk edge adds a second chunk", _chunk_count() == 2)
	_expect("removing the part in chunk 1 frees that chunk",
		_floor.set_rect(Rect2i(32, 0, 4, 4), false) == 16 and _chunk_count() == 1)

	var edge := Rect2i(BuildGrid.PLOT_TILES - Vector2i(5, 5), Vector2i(20, 20))
	_expect("rect past the plot edge is clipped (25 tiles)", _floor.set_rect(edge, true) == 25)

	_floor.set_rect(Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES), false)
	_expect("removing everything leaves no tiles", _floor.get_floor_tile_count() == 0)
	await get_tree().process_frame  # emptied chunk nodes are freed at the end of the frame
	_expect("removing everything leaves no chunk meshes", _chunk_count() == 0)

	# A big terminal (400 x 400 m); the whole 4.5 x 2 km plot would never be floored.
	var start_ms := Time.get_ticks_msec()
	_floor.set_rect(Rect2i(0, 0, 400, 400), true)
	var ms := Time.get_ticks_msec() - start_ms
	print("INFO | laying a 400 x 400 area took %d ms, %d chunks" % [ms, _chunk_count()])
	_expect("a 400 x 400 area is 160000 tiles", _floor.get_floor_tile_count() == 160000)

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


func _chunk_count() -> int:
	var count := 0
	for child in _floor.get_children():
		if child is MeshInstance3D and not child.is_queued_for_deletion():
			count += 1
	return count


## Vertices in the chunk containing tile (10, 10).
func _vertex_count() -> int:
	for child in _floor.get_children():
		if child is MeshInstance3D and child.name == "Chunk_0_0_0":
			return child.mesh.surface_get_array_len(0)
	return -1


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
