extends MeshInstance3D
## Ground plane with the build grid overlay (checklist step 6).
## The plot is grass with a subtle grid; the land around it is a slightly
## darker grass with no grid. G toggles the grid (handled by BuildGrid).

const GROUND_SHADER := preload("res://materials/ground_grid.gdshader")
## How far the ground reaches beyond the plot on each side, in metres.
@export var margin := 400.0

var _material: ShaderMaterial


func _ready() -> void:
	var rect := BuildGrid.get_plot_rect()
	var plane := PlaneMesh.new()
	plane.size = rect.size + Vector2.ONE * margin * 2.0
	mesh = plane
	position = Vector3(rect.get_center().x, BuildGrid.origin.y, rect.get_center().y)

	_material = ShaderMaterial.new()
	_material.shader = GROUND_SHADER
	_material.set_shader_parameter("tile_size", BuildGrid.TILE_SIZE)
	_material.set_shader_parameter("plot_min", rect.position)
	_material.set_shader_parameter("plot_max", rect.end)
	material_override = _material

	BuildGrid.grid_visibility_changed.connect(_on_grid_visibility_changed)
	_on_grid_visibility_changed(BuildGrid.grid_visible)


func _on_grid_visibility_changed(grid_visible: bool) -> void:
	_material.set_shader_parameter("show_grid", 1.0 if grid_visible else 0.0)
	print("GRID | %s" % ("shown" if grid_visible else "hidden"))
