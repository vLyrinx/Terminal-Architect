extends MeshInstance3D
## Debug overlay for the route graph (checklist step 17), toggled with F4 and
## shown while a taxiway tool is in use. Draws every edge as a line (cyan for
## taxiways, orange for runways) and every node as a cross: red at runway
## thresholds, yellow where a taxiway joins a runway, white elsewhere. Lines
## are drawn on top of everything and stay one pixel wide at any zoom.
## Redrawn only when the graph changes and the overlay is shown.

const ACTION_TOGGLE := "toggle_route_graph"
## Lines float this far above the ground.
const LIFT := 0.6
const CROSS_SIZE := 3.0
const TAXIWAY_COLOR := Color(0.25, 0.9, 1.0)
const RUNWAY_COLOR := Color(1.0, 0.6, 0.2)
const NODE_COLOR := Color(1, 1, 1)
const RUNWAY_END_COLOR := Color(1.0, 0.25, 0.25)
const RUNWAY_JOIN_COLOR := Color(1.0, 0.9, 0.2)

## The RouteGraph node (route_graph.gd).
@export var route_graph: Node

## Switched on with F4.
var overlay_visible := false
var _forced := 0
var _dirty := true
var _immediate := ImmediateMesh.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action(ACTION_TOGGLE):
		InputMap.add_action(ACTION_TOGGLE)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F4
		InputMap.action_add_event(ACTION_TOGGLE, key)
	mesh = _immediate
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.render_priority = 10
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	route_graph.graph_changed.connect(_on_graph_changed)
	_update_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		overlay_visible = not overlay_visible
		_update_visibility()
		print("ROUTE GRAPH | overlay %s" % ("shown" if overlay_visible else "hidden"))
		get_viewport().set_input_as_handled()


## Tools call this with true while active and false when done (like the zone overlay).
func set_forced(forced: bool) -> void:
	_forced = maxi(_forced + (1 if forced else -1), 0)
	_update_visibility()


func _update_visibility() -> void:
	visible = overlay_visible or _forced > 0
	if visible and _dirty:
		_redraw()


func _on_graph_changed() -> void:
	_dirty = true
	if visible:
		_redraw()


func _redraw() -> void:
	_dirty = false
	_immediate.clear_surfaces()
	if route_graph.edges.is_empty() and route_graph.nodes.is_empty():
		return
	var up := Vector3.UP * LIFT
	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge: Dictionary in route_graph.edges.values():
		var color := RUNWAY_COLOR if edge.kind == "runway" else TAXIWAY_COLOR
		_line(route_graph.nodes[edge.a].position + up, route_graph.nodes[edge.b].position + up, color)
	for node: Dictionary in route_graph.nodes.values():
		var color := NODE_COLOR
		if node.runway_end != "":
			color = RUNWAY_END_COLOR
		elif node.on_runway and node.on_taxiway:
			color = RUNWAY_JOIN_COLOR
		var p: Vector3 = node.position + up
		_line(p + Vector3(-CROSS_SIZE, 0, -CROSS_SIZE), p + Vector3(CROSS_SIZE, 0, CROSS_SIZE), color)
		_line(p + Vector3(-CROSS_SIZE, 0, CROSS_SIZE), p + Vector3(CROSS_SIZE, 0, -CROSS_SIZE), color)
	_immediate.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(a)
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(b)
