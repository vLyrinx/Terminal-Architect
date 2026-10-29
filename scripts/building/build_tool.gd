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
## Build menu category (checklist step 15): an ID from build_categories.gd,
## such as "structures" or "airside". Empty keeps the tool out of the menu.
@export var menu_category := ""
## Icon shown on the tool's build menu button.
@export var icon: Texture2D

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


# --- Build menu (checklist step 15) -------------------------------------------

## Entries this tool adds to the build menu. Each is a Dictionary with
## "id", "name", "icon", "cost" (display text), "category" and "tooltip".
## Most tools add one entry from their exports; a tool with several variants
## (objects, wall modes) overrides this and select_item().
func get_menu_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if menu_category != "":
		items.append(make_menu_item(String(name), tool_name, icon, get_cost_text(), menu_category))
	return items


## Switches the tool to one of its menu entries (called before it is activated).
func select_item(_item_id: String) -> void:
	pass


## The menu entry the tool is set to now, so the menu can highlight it.
func get_active_item_id() -> String:
	return String(name)


## Price shown in the build menu, such as "$25 / tile" ("" for none).
func get_cost_text() -> String:
	return ""


## Name of what is being built, shown above the hint.
func get_title() -> String:
	return tool_name


func make_menu_item(id: String, item_name: String, item_icon: Texture2D, cost: String,
		category: String, tooltip := "") -> Dictionary:
	var key := OS.get_keycode_string(shortcut) if shortcut != KEY_NONE else ""
	if tooltip == "":
		tooltip = item_name
	if key != "":
		tooltip += "  (%s)" % key
	return {"id": id, "name": item_name, "icon": item_icon, "cost": cost, "category": category,
		"tooltip": tooltip, "tool": self}


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


## Where the mouse points on the build floor, for tools that snap to corners or
## edges rather than tiles (the manager only reports tile changes). Same result
## as BuildGrid.screen_to_tile(); "hit" is false over the UI.
func mouse_pick(height_offset := 0.0) -> Dictionary:
	var viewport := get_viewport()
	if viewport.gui_get_hovered_control() != null:
		return {"hit": false, "tile": Vector2i.ZERO, "position": Vector3.ZERO, "in_plot": false}
	return BuildGrid.screen_to_tile(viewport.get_camera_3d(), viewport.get_mouse_position(),
		get_floor(), height_offset)


## True while this tool is the active one.
func is_active() -> bool:
	return manager != null and manager.active_tool == self


## Price text for a preview label: "$1,500", "refund $750", or
## "$1,500 - not enough money" when the player can't pay.
static func price_text(amount: int) -> String:
	if amount >= 0:
		return "refund %s" % Money.format(amount) if amount > 0 else ""
	if not Money.can_afford(-amount):
		return "%s - not enough money" % Money.format(-amount)
	return Money.format(-amount)


## Floor the manager is building on.
func get_floor() -> int:
	return manager.floor_index if manager else 0
