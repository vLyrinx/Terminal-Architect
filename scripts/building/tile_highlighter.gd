extends MeshInstance3D
## Highlights the tile under the mouse cursor (checklist step 6).
## Hidden when the cursor is over UI or outside the plot.
## Other systems can read hovered_tile / has_hovered_tile, or listen to hovered_tile_changed.

signal hovered_tile_changed(tile: Vector2i, in_plot: bool)

const HIGHLIGHT_SHADER := preload("res://materials/tile_highlight.gdshader")
## Height above the floor, so the highlight doesn't flicker into the ground.
const LIFT := 0.02

## Optional label that shows the hovered tile (temporary debug readout).
@export var debug_label: Label
## Floor being pointed at (only floor 0 for now).
@export var floor_index := 0
## Optional TerminalFloor node (terminal_floor.gd), so the highlight sits on top of floor tiles.
@export var terminal_floor: Node3D

var hovered_tile := Vector2i(-1, -1)
var has_hovered_tile := false


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * BuildGrid.TILE_SIZE
	mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = HIGHLIGHT_SHADER
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	var over_ui := viewport.gui_get_hovered_control() != null
	var pick := {} if over_ui else BuildGrid.screen_to_tile(
		viewport.get_camera_3d(), viewport.get_mouse_position(), floor_index)
	var valid: bool = not over_ui and pick.hit and pick.in_plot

	if valid:
		position = BuildGrid.tile_to_world(pick.tile, floor_index) + Vector3.UP * LIFT
		if terminal_floor:
			position.y = terminal_floor.get_surface_height(pick.tile, floor_index) + LIFT
	visible = valid

	var tile: Vector2i = pick.tile if valid else Vector2i(-1, -1)
	if tile != hovered_tile or valid != has_hovered_tile:
		hovered_tile = tile
		has_hovered_tile = valid
		hovered_tile_changed.emit(tile, valid)
		if debug_label:
			debug_label.text = "Tile %d, %d" % [tile.x, tile.y] if valid else "Tile: none"
