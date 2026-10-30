extends Node3D
## Test for terminal pathfinding (checklist step 28).
## Run this scene on its own (F6). It builds a small terminal, 40 x 20 m:
## landside on the west (entrance door in the south wall), a security strip,
## and airside on the east, each split from the next by a wall with a door,
## with a check-in desk standing in landside. Then it checks that paths go
## around walls and objects and only through doors, that landside people
## can't reach airside and airside people can't reach landside, and that
## paths change when a door closes or opens, zones are repainted, objects are
## placed or the floor grows. Prints PASS or FAIL for each check.
## Afterwards 200 passengers walk to random places they are allowed to go
## (blue shirts landside, purple airside); a few show their path as a line.
##   B      close / open the door between landside and security
##   Z      zone overlay
##   Camera as in the game (right drag rotate, WASD pan, wheel zoom)

const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")
const Zone := TerminalZonesScript.Zone
const Piece := TerminalWallsScript.Piece
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE

## North-west corner of the terminal, in tiles (near the middle of the plot).
const B := Vector2i(2240, 990)
const SIZE := Vector2i(40, 20)
## Corner tile x where the security strip starts and where airside starts.
const SECURITY_X := 16
const AIRSIDE_X := 20
const ENTRANCE := Vector2i(5, 20)
const SECURITY_DOOR := Vector2i(SECURITY_X, 10)
const AIRSIDE_DOOR := Vector2i(AIRSIDE_X, 4)
const WALKERS := 200
const SPEED := 1.3

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _zones: TerminalZonesScript
var _objects: PlacedObjectsScript
var _paths: TerminalPathsScript
var _changed := 0

var _crowd: PassengerCrowdScript
var _walkers: Array[Dictionary] = []
var _open_tiles := {}
var _lines: MeshInstance3D
var _label: Label
var _rng := RandomNumberGenerator.new()
var _security_door_open := true


func _ready() -> void:
	print("TEST START | terminal pathfinding")
	_rng.seed = 28
	_build_terminal()
	_paths = TerminalPathsScript.new()
	_paths.terminal_floor = _floor
	_paths.terminal_walls = _walls
	_paths.terminal_zones = _zones
	_paths.placed_objects = _objects
	add_child(_paths)
	_paths.paths_changed.connect(func() -> void: _changed += 1)

	_check_basic_paths()
	_check_zones_block()
	await _check_layout_changes()
	_check_speed()
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_start_demo()


# --- Layout -----------------------------------------------------------------------

func _build_terminal() -> void:
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_walls = TerminalWallsScript.new()
	_walls.terminal_floor = _floor
	add_child(_walls)
	_zones = TerminalZonesScript.new()
	_zones.terminal_floor = _floor
	add_child(_zones)
	_objects = PlacedObjectsScript.new()
	_objects.terminal_floor = _floor
	_objects.terminal_walls = _walls
	add_child(_objects)
	_floor.placed_objects = _objects
	_walls.placed_objects = _objects
	_floor.set_roof_visible(false)

	_floor.set_rect(Rect2i(B, SIZE), true)
	_zones.paint_rect(Rect2i(B, Vector2i(SECURITY_X, SIZE.y)), Zone.LANDSIDE)
	_zones.paint_rect(Rect2i(B + Vector2i(SECURITY_X, 0), Vector2i(AIRSIDE_X - SECURITY_X, SIZE.y)), Zone.SECURITY)
	_zones.paint_rect(Rect2i(B + Vector2i(AIRSIDE_X, 0), Vector2i(SIZE.x - AIRSIDE_X, SIZE.y)), Zone.AIRSIDE)
	var c0 := B
	var c1 := B + SIZE
	_walls.set_run(c0, Vector2i(c1.x, c0.y), true)
	_walls.set_run(Vector2i(c0.x, c1.y), c1, true)
	_walls.set_run(c0, Vector2i(c0.x, c1.y), true)
	_walls.set_run(Vector2i(c1.x, c0.y), c1, true)
	_walls.set_run(B + Vector2i(SECURITY_X, 0), B + Vector2i(SECURITY_X, SIZE.y), true)
	_walls.set_run(B + Vector2i(AIRSIDE_X, 0), B + Vector2i(AIRSIDE_X, SIZE.y), true)
	_walls.set_door(B + ENTRANCE, true, true)
	_walls.set_door(B + SECURITY_DOOR, false, true)
	_walls.set_door(B + AIRSIDE_DOOR, false, true)
	# An airside room with its door facing away from the airside entrance.
	_walls.set_run(B + Vector2i(26, 8), B + Vector2i(34, 8), true)
	_walls.set_run(B + Vector2i(26, 8), B + Vector2i(26, 14), true)
	_walls.set_run(B + Vector2i(34, 8), B + Vector2i(34, 14), true)
	_walls.set_run(B + Vector2i(26, 14), B + Vector2i(34, 14), true)
	_walls.set_door(B + Vector2i(33, 14), true, true)
	# A check-in desk in the middle of landside.
	var def: Resource = ObjectCatalog.get_def(&"checkin_desk")
	var pos: Vector3 = _objects.snap_position(def, _tile_world(Vector2i(8, 10)), 0.0)
	_objects.add_object(&"checkin_desk", pos, 0.0)


# --- Checks -----------------------------------------------------------------------

func _check_basic_paths() -> void:
	var outside := Vector2i(5, 24)
	var path := _path(outside, Vector2i(10, 3), LANDSIDE)
	_expect("outside to landside: path found", not path.is_empty())
	_expect("outside to landside: enters by the door, no wall crossed", _path_ok(path, LANDSIDE))
	_expect("outside to landside: passes the entrance doorway", _passes_edge(path, B + ENTRANCE, true))

	var desk_tiles := _desk_tiles()
	path = _path(Vector2i(2, 10), Vector2i(14, 10), LANDSIDE)
	_expect("landside path across the desk goes around it", not path.is_empty() and _path_ok(path, LANDSIDE)
		and not _visits_any(path, desk_tiles))

	path = _path(Vector2i(10, 3), Vector2i(18, 15), LANDSIDE)
	_expect("landside to security: through the security door", _path_ok(path, LANDSIDE)
		and _passes_edge(path, B + SECURITY_DOOR, false))
	_expect("landside can't reach airside", _path(Vector2i(10, 3), Vector2i(30, 3), LANDSIDE).is_empty())
	_expect("landside can't stand on airside", not _paths.is_walkable(B + Vector2i(30, 3), LANDSIDE))

	path = _path(Vector2i(18, 15), Vector2i(30, 11), AIRSIDE)
	_expect("security to the airside room: path found", not path.is_empty())
	_expect("security to the airside room: through both doors, no wall crossed", _path_ok(path, AIRSIDE)
		and _passes_edge(path, B + AIRSIDE_DOOR, false) and _passes_edge(path, B + Vector2i(33, 14), true))
	_expect("airside can't go back landside", _path(Vector2i(30, 3), Vector2i(10, 3), AIRSIDE).is_empty())
	_expect("airside can't leave the building", _path(Vector2i(30, 3), Vector2i(5, 24), AIRSIDE).is_empty())

	path = _paths.find_path(_tile_world(Vector2i(2, 10)), _tile_world(Vector2i(8, 10)), LANDSIDE, true)
	_expect("partial path stops beside the desk", not path.is_empty()
		and not desk_tiles.has(BuildGrid.world_to_tile(path[path.size() - 1])))
	print("INFO | grid covers %s tiles" % _paths.get_region())


func _check_zones_block() -> void:
	# A strip of airside right across landside cuts it in two for landside people.
	var strip := Rect2i(B + Vector2i(12, 0), Vector2i(1, SIZE.y))
	_zones.paint_rect(strip, Zone.AIRSIDE)
	_expect("repainted zone blocks landside people", _path(Vector2i(10, 3), Vector2i(14, 3), LANDSIDE).is_empty())
	_zones.paint_rect(strip, Zone.LANDSIDE)
	_expect("and painting it back opens it again", not _path(Vector2i(10, 3), Vector2i(14, 3), LANDSIDE).is_empty())


func _check_layout_changes() -> void:
	# process_frame fires before nodes process, so two frames let earlier changes be announced.
	await get_tree().process_frame
	await get_tree().process_frame
	_changed = 0
	_walls.set_door(B + SECURITY_DOOR, false, false)
	_expect("closing the security door cuts landside off from security",
		_path(Vector2i(10, 3), Vector2i(18, 15), LANDSIDE).is_empty())
	await get_tree().process_frame
	await get_tree().process_frame
	_expect("paths_changed is emitted after the change", _changed == 1)
	var new_door := Vector2i(SECURITY_X, 16)
	_walls.set_door(B + new_door, false, true)
	var path := _path(Vector2i(10, 3), Vector2i(18, 15), LANDSIDE)
	_expect("a new door gives a new path through it", _path_ok(path, LANDSIDE) and _passes_edge(path, B + new_door, false))
	_walls.set_door(B + new_door, false, false)
	_walls.set_door(B + SECURITY_DOOR, false, true)

	# Removing the desk lets a straight path through.
	var id: int = _objects.get_ids()[0]
	var obj = _objects.get_object(id)
	var desk_def: StringName = obj.def_id
	var desk_pos: Vector3 = obj.position
	_objects.remove_object(id)
	path = _path(Vector2i(2, 10), Vector2i(14, 10), LANDSIDE)
	_expect("removing the desk frees its tiles (straight path)", path.size() == 2)
	_objects.add_object(desk_def, desk_pos, 0.0)
	path = _path(Vector2i(2, 10), Vector2i(14, 10), LANDSIDE)
	_expect("placing it again blocks them", path.size() > 2 and not _visits_any(path, _desk_tiles()))

	# An annex beyond the grid: the region grows and a door through the east wall reaches it.
	var old_region := _paths.get_region()
	var annex := Rect2i(B + Vector2i(SIZE.x, 0), Vector2i(20, SIZE.y))
	_floor.set_rect(annex, true)
	_zones.paint_rect(annex, Zone.AIRSIDE)
	_walls.set_door(B + Vector2i(SIZE.x, 10), false, true)
	path = _path(Vector2i(30, 3), Vector2i(55, 10), AIRSIDE)
	_expect("new floor grows the grid", _paths.get_region().end.x > old_region.end.x)
	_expect("and the annex can be reached through its door", _path_ok(path, AIRSIDE)
		and _passes_edge(path, B + Vector2i(SIZE.x, 10), false))


func _check_speed() -> void:
	var landside := _open_list(LANDSIDE)
	var airside := _open_list(AIRSIDE)
	var count := 500
	var found := 0
	var started := Time.get_ticks_usec()
	for n in count:
		var tiles: Array = landside if n % 2 == 0 else airside
		var access := LANDSIDE if n % 2 == 0 else AIRSIDE
		var a: Vector2i = tiles[_rng.randi() % tiles.size()]
		var b: Vector2i = tiles[_rng.randi() % tiles.size()]
		if not _paths.find_path(_tile_world(a, true), _tile_world(b, true), access).is_empty():
			found += 1
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	print("INFO | %d random paths in %.1f ms (%.3f ms each), %d found" % [count, ms, ms / count, found])
	_expect("every random path between open tiles is found", found == count)


# --- Helpers ----------------------------------------------------------------------

## Path between two tiles given relative to the terminal's corner.
func _path(from: Vector2i, to: Vector2i, access: int) -> PackedVector3Array:
	return _paths.find_path(_tile_world(from), _tile_world(to), access)


func _tile_world(tile: Vector2i, absolute := false) -> Vector3:
	return BuildGrid.tile_to_world(tile if absolute else B + tile)


## Every point along the path, every 5 cm, is on a tile the access allows,
## and each step from one tile to the next crosses no wall.
func _path_ok(path: PackedVector3Array, access: int) -> bool:
	if path.size() < 2:
		return false
	var prev := BuildGrid.world_to_tile(path[0])
	for tile in _sample_tiles(path):
		if not _paths.is_walkable(tile, access):
			return false
		if tile != prev and not _step_clear(prev, tile):
			return false
		prev = tile
	return true


func _sample_tiles(path: PackedVector3Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var steps := maxi(1, ceili(a.distance_to(b) / 0.05))
		for s in steps + 1:
			var tile := BuildGrid.world_to_tile(a.lerp(b, float(s) / steps))
			if out.is_empty() or out[out.size() - 1] != tile:
				out.append(tile)
	return out


## True if moving between neighbouring tiles crosses no wall (diagonal steps
## need one clear way round the corner).
func _step_clear(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if absi(d.x) > 1 or absi(d.y) > 1:
		return false
	if d.y == 0:
		return _walls.get_edge(Vector2i(maxi(a.x, b.x), a.y), false) != Piece.WALL
	if d.x == 0:
		return _walls.get_edge(Vector2i(a.x, maxi(a.y, b.y)), true) != Piece.WALL
	var via_x := Vector2i(b.x, a.y)
	var via_y := Vector2i(a.x, b.y)
	return (_step_clear(a, via_x) and _step_clear(via_x, b)) or (_step_clear(a, via_y) and _step_clear(via_y, b))


## True if the path crosses the given edge (horizontal: between tile rows).
func _passes_edge(path: PackedVector3Array, corner: Vector2i, horizontal: bool) -> bool:
	var tiles := _sample_tiles(path)
	var x := corner.x
	var y := corner.y
	for i in range(1, tiles.size()):
		var a := tiles[i - 1]
		var b := tiles[i]
		if horizontal and a.x == x and b.x == x and mini(a.y, b.y) == y - 1 and maxi(a.y, b.y) == y:
			return true
		if not horizontal and a.y == y and b.y == y and mini(a.x, b.x) == x - 1 and maxi(a.x, b.x) == x:
			return true
	return false


func _visits_any(path: PackedVector3Array, tiles: Dictionary) -> bool:
	for tile in _sample_tiles(path):
		if tiles.has(tile):
			return true
	return false


func _desk_tiles() -> Dictionary:
	var out := {}
	for id in _objects.get_ids():
		for tile in _objects.get_object(id).tiles:
			out[tile] = true
	return out


func _open_list(access: int) -> Array:
	var out := []
	var region := _paths.get_region()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if _paths.is_walkable(Vector2i(x, y), access):
				out.append(Vector2i(x, y))
	return out


# --- Demo -------------------------------------------------------------------------

func _start_demo() -> void:
	_add_view()
	_crowd = PassengerCrowdScript.new()
	add_child(_crowd)
	_lines = MeshInstance3D.new()
	_lines.mesh = ImmediateMesh.new()
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.95, 0.2, 0.2)
	line_mat.no_depth_test = true
	_lines.material_override = line_mat
	add_child(_lines)
	_refresh_open_tiles()
	for n in WALKERS:
		var access := LANDSIDE if n % 2 == 0 else AIRSIDE
		var tiles: Array = _open_tiles[access]
		var start := _tile_world(tiles[_rng.randi() % tiles.size()], true)
		var id := _crowd.add(start, 0.0)
		_crowd.set_shirt_colour(id, Color(0.20, 0.45, 0.85) if access == LANDSIDE else Color(0.60, 0.35, 0.85))
		_walkers.append({"id": id, "access": access, "path": PackedVector3Array(), "next": 0, "target": start})
	_paths.paths_changed.connect(_on_demo_paths_changed)


func _on_demo_paths_changed() -> void:
	_refresh_open_tiles()
	for w in _walkers:
		_repath(w, w.target)


func _refresh_open_tiles() -> void:
	_open_tiles[LANDSIDE] = _open_list(LANDSIDE)
	_open_tiles[AIRSIDE] = _open_list(AIRSIDE)


func _repath(w: Dictionary, target: Vector3) -> void:
	w.target = target
	w.path = _paths.find_path(_crowd.get_passenger_position(w.id), target, w.access)
	w.next = 1


func _process(delta: float) -> void:
	if _crowd == null:
		return
	for w in _walkers:
		var path: PackedVector3Array = w.path
		if w.next >= path.size():
			var tiles: Array = _open_tiles[w.access]
			if not tiles.is_empty():
				_repath(w, _tile_world(tiles[_rng.randi() % tiles.size()], true))
			continue
		var pos := _crowd.get_passenger_position(w.id)
		var goal := path[w.next]
		var to := goal - pos
		var step := SPEED * delta
		if to.length() <= step:
			pos = goal
			w.next += 1
		else:
			pos += to.normalized() * step
		_crowd.set_pose(w.id, pos, PassengerCrowdScript.yaw_towards(to))
	_draw_lines()
	_label.text = "Terminal pathfinding: %d passengers (blue = landside, purple = airside)\nB: %s the security door    Z: zone overlay" % [
		WALKERS, "close" if _security_door_open else "open"]


func _draw_lines() -> void:
	var im := _lines.mesh as ImmediateMesh
	im.clear_surfaces()
	var points := PackedVector3Array()
	for n in 6:
		var w: Dictionary = _walkers[n]
		var path: PackedVector3Array = w.path
		var prev := _crowd.get_passenger_position(w.id)
		for i in range(w.next, path.size()):
			points.append(prev + Vector3.UP * 0.15)
			points.append(path[i] + Vector3.UP * 0.15)
			prev = path[i]
	if points.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in points:
		im.surface_add_vertex(p)
	im.surface_end()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_B:
		_security_door_open = not _security_door_open
		_walls.set_door(B + SECURITY_DOOR, false, _security_door_open)


func _add_view() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.78, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.80, 0.88)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 100)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.45)
	plane.material = mat
	ground.mesh = plane
	ground.position = BuildGrid.tile_corner_to_world(B + SIZE / 2) + Vector3(10, -0.01, 0)
	add_child(ground)
	var camera := OrbitCameraScript.new()
	camera.start_distance = 75.0
	camera.start_pitch_deg = 60.0
	add_child(camera)  # the terminal is near the world origin, where the camera looks
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_color", Color(0.1, 0.12, 0.15))
	ui.add_child(_label)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
