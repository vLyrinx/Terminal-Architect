extends "res://scripts/building/build_tool.gd"
## Temporary test tool (checklist step 7): places a plain 1 m cube on a tile.
## Shows a green ghost on free tiles and a red ghost on tiles that already
## have a cube. Will be removed once real tools exist.

const CUBE_SIZE := 0.96

var _ghost: MeshInstance3D
var _cube_mesh: BoxMesh
var _cube_material: StandardMaterial3D
## Tiles that already have a cube.
var _occupied := {}


func _ready() -> void:
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3.ONE * CUBE_SIZE
	_cube_material = StandardMaterial3D.new()
	_cube_material.albedo_color = Color(0.93, 0.94, 0.97)
	_cube_material.roughness = 1.0
	_ghost = make_ghost(_cube_mesh)


func deactivate() -> void:
	_ghost.visible = false


func hover(tile: Vector2i, in_plot: bool) -> void:
	_ghost.visible = in_plot
	if in_plot:
		_ghost.global_position = _tile_position(tile)
		_ghost.material_override = ghost_material(not _occupied.has(tile))


func drag(tile: Vector2i, in_plot: bool) -> void:
	hover(tile, in_plot)


func release(tile: Vector2i, in_plot: bool) -> void:
	if not in_plot or _occupied.has(tile):
		return
	var cube := MeshInstance3D.new()
	cube.mesh = _cube_mesh
	cube.material_override = _cube_material
	manager.built_root.add_child(cube)
	cube.global_position = _tile_position(tile)
	_occupied[tile] = cube
	print("BUILD | test cube placed at tile %d, %d" % [tile.x, tile.y])


func get_hint() -> String:
	return "Left click: place cube   Right click / Esc: cancel"


func _tile_position(tile: Vector2i) -> Vector3:
	return BuildGrid.tile_to_world(tile, get_floor()) + Vector3.UP * CUBE_SIZE * 0.5
