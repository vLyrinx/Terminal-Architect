class_name BuildTool
extends Node3D
## Base class for build tools (checklist step 7).
##
## A tool is a child node of the BuildManager. The manager tells the active
## tool what the mouse is doing, in tiles; the tool draws its own preview
## (ghost) and decides what to build. Single-click tools build on release();
## drag tools (floors, walls, runways) use press() to start, drag() to update
## the preview and release() to build the whole area.
##
## Override the methods below in a tool; all of them are optional.

## Name shown in the build menu.
@export var tool_name := "Tool"
## Key that selects this tool (KEY_NONE for no shortcut).
@export var shortcut: Key = KEY_NONE

## Set by the BuildManager when the tool is registered (build_manager.gd).
var manager: Node3D

static var _ghost_materials := {}


## Called when the tool becomes the active tool.
func activate() -> void:
	pass


## Called when another tool is picked or building is cancelled. Hide the ghost here.
func deactivate() -> void:
	pass


## Called whenever the hovered tile changes. in_plot is false when the cursor
## is off the plot or over the UI: hide the ghost then.
func hover(_tile: Vector2i, _in_plot: bool) -> void:
	pass


## Left mouse button pressed on the plot.
func press(_tile: Vector2i) -> void:
	pass


## Mouse moved to another tile while the left button is held.
func drag(_tile: Vector2i, _in_plot: bool) -> void:
	pass


## Left mouse button released. Build here.
func release(_tile: Vector2i, _in_plot: bool) -> void:
	pass


## A drag was cancelled (right click or Esc while dragging). Reset the preview.
func cancel_drag() -> void:
	pass


## Short help text for the build bar, such as "Left click: place".
func get_hint() -> String:
	return "Left click: build"


# --- Helpers for tools ---------------------------------------------------------

## Shared see-through material for ghosts: green when valid, red when not.
static func ghost_material(valid: bool) -> StandardMaterial3D:
	if not _ghost_materials.has(valid):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.35, 0.9, 0.45, 0.45) if valid else Color(0.95, 0.3, 0.3, 0.45)
		_ghost_materials[valid] = m
	return _ghost_materials[valid]


## Makes a ghost mesh instance as a child of this tool, hidden until used.
func make_ghost(ghost_mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ghost_mesh
	mi.material_override = ghost_material(true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## Floor the manager is building on.
func get_floor() -> int:
	return manager.floor_index if manager else 0
