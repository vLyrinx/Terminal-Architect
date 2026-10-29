extends Node3D
## Automatic test for walls and doors (checklist step 9).
## Run this scene on its own (F6). It builds walls and doors through the same
## calls the tools use, checks the pieces and the merged chunk meshes, prints
## PASS or FAIL for each check, then waits for you to close the window.

const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const WALL := TerminalWallsScript.Piece.WALL
const DOOR := TerminalWallsScript.Piece.DOOR
## A wall box has 5 faces (no bottom), a door lintel 6; 4 vertices per face.
const WALL_BOX_VERTS := 20
const LINTEL_VERTS := 24

var _failures := 0
var _walls: TerminalWallsScript


func _ready() -> void:
	print("TEST START | walls and doors")
	_walls = TerminalWallsScript.new()
	add_child(_walls)

	_expect("count before building is 5", _walls.count_run_changes(Vector2i(10, 10), Vector2i(15, 10), true) == 5)
	_expect("5 m wall builds 5 pieces", _walls.set_run(Vector2i(10, 10), Vector2i(15, 10), true) == 5)
	_expect("building again changes nothing", _walls.set_run(Vector2i(15, 10), Vector2i(10, 10), true) == 0)
	_expect("diagonal drag builds nothing", _walls.set_run(Vector2i(0, 0), Vector2i(3, 2), true) == 0)
	_expect("straight wall merges to one box", _verts("Chunk_0_0_0") == WALL_BOX_VERTS)

	_expect("4 m wall down from the end builds 4", _walls.set_run(Vector2i(15, 10), Vector2i(15, 14), true) == 4)
	_expect("L corner is two boxes", _verts("Chunk_0_0_0") == WALL_BOX_VERTS * 2)
	_expect("vertical wall stops against the horizontal one", _check_corner_join())

	# Doors right beside the corner: jambs keep the corner square solid.
	_walls.set_door(Vector2i(14, 10), true, true)
	_expect("door in the horizontal wall beside the corner: wall + lintel + corner post + vertical wall",
		_verts("Chunk_0_0_0") == WALL_BOX_VERTS * 3 + LINTEL_VERTS)
	_expect("corner post fills the corner square", _has_corner_post(Vector2i(15, 10)))
	_walls.set_door(Vector2i(14, 10), true, false)
	_walls.set_door(Vector2i(15, 10), false, true)
	_expect("door in the vertical wall beside the corner: opening starts at the wall side",
		_verts("Chunk_0_0_0") == WALL_BOX_VERTS * 2 + LINTEL_VERTS)
	_walls.set_door(Vector2i(15, 10), false, false)

	_expect("door replaces a wall piece", _walls.set_door(Vector2i(12, 10), true, true))
	_expect("edge is now a door", _walls.get_edge(Vector2i(12, 10), true) == DOOR)
	_expect("wall with a door is wall + lintel + wall",
		_verts("Chunk_0_0_0") == WALL_BOX_VERTS * 3 + LINTEL_VERTS)
	_expect("door on an empty edge is refused", not _walls.set_door(Vector2i(12, 11), true, true))
	_expect("door on a door is refused", not _walls.set_door(Vector2i(12, 10), true, true))
	_expect("building walls over a door keeps the door",
		_walls.set_run(Vector2i(10, 10), Vector2i(15, 10), true) == 0 and _walls.get_edge(Vector2i(12, 10), true) == DOOR)
	_expect("door count is 1", _walls.get_piece_counts().doors == 1)
	_expect("door back to wall", _walls.set_door(Vector2i(12, 10), true, false) and _verts("Chunk_0_0_0") == WALL_BOX_VERTS * 2)

	_walls.set_door(Vector2i(13, 10), true, true)
	_expect("removing a run removes walls and doors", _walls.set_run(Vector2i(10, 10), Vector2i(15, 10), false) == 5)
	_expect("4 wall pieces left", _walls.get_piece_counts().walls == 4 and _walls.get_piece_counts().doors == 0)

	_expect("wall across a chunk edge builds 4", _walls.set_run(Vector2i(30, 40), Vector2i(34, 40), true) == 4)
	_expect("it is split into two chunk meshes",
		_verts("Chunk_0_1_0") == WALL_BOX_VERTS and _verts("Chunk_1_1_0") == WALL_BOX_VERTS)
	_expect("wall past the plot edge is clipped (2 pieces)",
		_walls.set_run(Vector2i(4498, 2000), Vector2i(4502, 2000), true) == 2)

	var c := BuildGrid.tile_corner_to_world(Vector2i(5, 5))
	_expect("nearest corner", BuildGrid.world_to_corner(c + Vector3(0.3, 0, -0.4)) == Vector2i(5, 5))
	var e := BuildGrid.world_to_edge(c + Vector3(0.5, 0, 0.1))
	_expect("nearest edge (horizontal)", e.corner == Vector2i(5, 5) and e.horizontal)
	e = BuildGrid.world_to_edge(c + Vector3(0.9, 0, 0.5))
	_expect("nearest edge (vertical)", e.corner == Vector2i(6, 5) and not e.horizontal)

	_walls.set_run(Vector2i(15, 10), Vector2i(15, 14), false)
	_walls.set_run(Vector2i(30, 40), Vector2i(34, 40), false)
	_walls.set_run(Vector2i(4498, 2000), Vector2i(4500, 2000), false)
	await get_tree().process_frame  # emptied chunk nodes are freed at the end of the frame
	_expect("removing everything leaves no pieces and no meshes",
		_walls.get_piece_counts().walls == 0 and _walls.get_child_count() == 0)

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


## Vertices in a chunk mesh, or -1 if the chunk has none.
func _verts(chunk_name: String) -> int:
	var mi := _walls.get_node_or_null(chunk_name) as MeshInstance3D
	if mi == null or mi.is_queued_for_deletion() or mi.mesh == null:
		return -1
	return mi.mesh.surface_get_array_len(0)


## In the L corner at corner (15, 10), the vertical wall should start exactly at
## the horizontal wall's side (half a thickness past the grid line), so nothing
## overlaps. Only the vertical box has vertices on its inner side, x = line - HALF.
func _check_corner_join() -> bool:
	var mi := _walls.get_node("Chunk_0_0_0") as MeshInstance3D
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var corner := BuildGrid.tile_corner_to_world(Vector2i(15, 10))
	var inner_x := corner.x - TerminalWallsScript.HALF
	var min_z := INF
	for v in verts:
		if is_equal_approx(v.x, inner_x):
			min_z = minf(min_z, v.z)
	return is_equal_approx(min_z, corner.z + TerminalWallsScript.HALF)


## True if a full-height box covers the whole corner square: a box with bottom
## vertices at both outer X sides of the square (corner.x ± HALF) on the floor.
func _has_corner_post(corner_index: Vector2i) -> bool:
	var mi := _walls.get_node("Chunk_0_0_0") as MeshInstance3D
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var corner := BuildGrid.tile_corner_to_world(corner_index)
	var h := TerminalWallsScript.HALF
	var found_lo := false
	var found_hi := false
	for v in verts:
		if not is_zero_approx(v.y) or not is_equal_approx(v.z, corner.z - h):
			continue
		found_lo = found_lo or is_equal_approx(v.x, corner.x - h)
		found_hi = found_hi or is_equal_approx(v.x, corner.x + h)
	return found_lo and found_hi


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
