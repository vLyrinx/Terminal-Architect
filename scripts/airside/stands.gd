extends Node3D
## Stands (checklist step 18): stores every aircraft stand and draws it.
##
## A stand is a rectangle of concrete apron sized by its aircraft size class
## (StandDef.get_size()), with its entry edge flush against taxiway paving.
## Straight out from the middle of the entry edge there must be at least as
## much paving as the stand's taxiway size needs (TaxiwayDef.width);
## otherwise the stand can't be built. If that paving is later removed the
## stand stays but shows as not connected. Stands may not overlap runways,
## taxiway paving, ramps, other stands or terminal floor. Each stand has a yellow lead-in line and stop bar, a red
## boundary line, and a label with its number, size class and connection.
## The RouteGraph adds a lead-in edge from each stand's stop bar out to a taxi
## line painted on the taxiway in front. Changes come from PlaceStandCommand
## and DeleteStandCommand.
##
## Keep this node at the world origin.

signal stand_added(id: int)
signal stand_removed(id: int)
## A stand was connected to or cut off from its taxiway.
signal stand_changed(id: int)

const StandScript := preload("res://scripts/airside/stand.gd")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")

## Ways the entry edge can face, in tiles: +Z, -X, -Z, +X. R in the stand tool steps through them.
const FACINGS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]
## Same height as taxiway paving (taxiways.gd); the two never overlap.
const PAVING_HEIGHT := 0.025
const MARKING_LIFT := 0.01
const PAVING_COLOR := Color(0.6, 0.61, 0.62)
const PAVING_SIDE_COLOR := Color(0.47, 0.48, 0.5)
const LEAD_IN_COLOR := Color(0.95, 0.76, 0.19)
const BOUNDARY_COLOR := Color(0.82, 0.22, 0.2)
const LINE_WIDTH := 0.5
## The stop bar is this far from the back of the stand, and this long and wide.
const STOP_FROM_BACK := 8.0
const STOP_BAR_LENGTH := 6.0
const STOP_BAR_WIDTH := 1.0
## Boundary lines sit this far in from the edge of the apron.
const BOUNDARY_INSET := 0.75
## The stand tool snaps a stand flush against a taxiway this many metres away.
const SNAP_REACH := 40
const LABEL_HEIGHT := 6.0
const CONNECTED_COLOR := Color(0.7, 1.0, 0.7)
const NOT_CONNECTED_COLOR := Color(1.0, 0.7, 0.4)

## The TerminalFloor node (terminal_floor.gd). Stands can't go over floor.
@export var terminal_floor: Node3D
## The Runways node (runways.gd). Stands can't overlap runways.
@export var runways: Node3D
## The Taxiways node (taxiways.gd). Stands open onto taxiways.
@export var taxiways: Node3D
## Optional Ramps node (ramps.gd). Stands can't overlap runway ramps.
@export var ramps: Node3D

var _stands := {}
var _next_id := 1
static var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95
	if taxiways:
		taxiways.paving_changed.connect(_on_taxiways_changed.unbind(1))


# --- Queries --------------------------------------------------------------------

func get_stand(id: int) -> StandScript:
	return _stands.get(id)


func get_ids() -> Array:
	return _stands.keys()


func get_count() -> int:
	return _stands.size()


func get_all() -> Array:
	return _stands.values()


## ID of the stand covering a tile, or 0.
func get_stand_at(tile: Vector2i) -> int:
	for stand: StandScript in _stands.values():
		if stand.rect.has_point(tile):
			return stand.id
	return 0


## IDs of stands that cover any tile of rect.
func get_stands_in(rect: Rect2i) -> Array[int]:
	var ids: Array[int] = []
	for stand: StandScript in _stands.values():
		if stand.rect.intersects(rect):
			ids.append(stand.id)
	return ids


## Apron rectangles overlapping rect.
func get_rects_in(rect: Rect2i) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for stand: StandScript in _stands.values():
		if stand.rect.intersects(rect):
			rects.append(stand.rect)
	return rects


## Tiles a stand of this size covers, from the corner in the middle of its
## entry edge and the way the entry edge faces (an index into FACINGS).
static func footprint(def: Resource, anchor: Vector2i, facing: int) -> Rect2i:
	var size: Vector2i = def.get_size()
	var half := floori(size.x * 0.5)
	var f := FACINGS[facing]
	if f.x == 0:
		return Rect2i(anchor.x - half, anchor.y - size.y if f.y > 0 else anchor.y, size.x, size.y)
	return Rect2i(anchor.x - size.y if f.x > 0 else anchor.x, anchor.y - half, size.y, size.x)


## Metres of taxiway paving straight out from the middle of the entry edge,
## counted up to SNAP_REACH.
func paving_depth(anchor: Vector2i, facing: int) -> int:
	if taxiways == null:
		return 0
	var f := FACINGS[facing]
	var outside := anchor + Vector2i(mini(f.x, 0), mini(f.y, 0))
	var depth := 0
	while depth < SNAP_REACH and taxiways.is_paved(outside + f * depth):
		depth += 1
	return depth


## Paved width in front of the entry that a stand of this size needs (the
## width of its taxiway size, TaxiwayDef.width).
func needed_depth(def: Resource) -> int:
	for taxiway_def: Resource in TaxiwayCatalog.get_all():
		if taxiway_def.size_class == def.get_taxiway_class():
			return taxiway_def.width
	return 1


## True if there is enough paving in front of the entry for this stand size.
func find_connection(def: Resource, anchor: Vector2i, facing: int) -> bool:
	return paving_depth(anchor, facing) >= needed_depth(def)


## Where a stand centred near world_pos goes: the middle of its entry edge,
## on the 10 m grid across the lead-in, and flush against the edge of
## taxiway paving in front of it (within SNAP_REACH) along the lead-in.
func snap_anchor(def: Resource, world_pos: Vector3, facing: int) -> Vector2i:
	var f := FACINGS[facing]
	var depth: int = def.get_size().y
	@warning_ignore("integer_division")
	var raw := BuildGrid.world_to_corner(world_pos) + f * (depth / 2)
	var anchor := BuildGrid.snap_to_airside(raw)
	if taxiways == null:
		return anchor
	# Along the lead-in, from the raw position: the nearest corner with paving
	# just outside the entry and none just inside it.
	var start := anchor
	if f.x != 0:
		start.x = raw.x
	else:
		start.y = raw.y
	var lean := Vector2i(mini(f.x, 0), mini(f.y, 0))
	for k in SNAP_REACH + 1:
		for sign_ in [1, -1]:
			var c: Vector2i = start + f * k * sign_
			var outside := c + lean
			if taxiways.is_paved(outside) and not taxiways.is_paved(outside - f):
				return c
	return anchor


## Why a stand can't be built here, or "" if it can.
## (Walls in the way are checked by PlaceStandCommand, which knows the walls.)
func check_placement(def: Resource, anchor: Vector2i, facing: int) -> String:
	if def == null or def.get_size_class() == null:
		return "Unknown stand size"
	if facing < 0 or facing >= FACINGS.size():
		return "Unknown stand direction"
	var rect := footprint(def, anchor, facing)
	if not Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES).encloses(rect):
		return "Doesn't fit on the plot"
	if runways and not runways.get_runways_in(rect).is_empty():
		return "Overlaps a runway"
	if taxiways and taxiways.count_paved_in(rect) > 0:
		return "Overlaps a taxiway"
	if ramps and not ramps.get_ramps_in(rect).is_empty():
		return "Overlaps a runway ramp"
	if not get_stands_in(rect).is_empty():
		return "Overlaps another stand"
	if terminal_floor and terminal_floor.count_floor_tiles(rect) > 0:
		return "Blocked by terminal floor"
	var paved := paving_depth(anchor, facing)
	if paved == 0:
		return "Entry must open onto a taxiway"
	if paved < needed_depth(def):
		return "Needs %d m of taxiway in front (%d m here)" % [needed_depth(def), paved]
	return ""


# --- Editing --------------------------------------------------------------------

## Adds a stand (no checks: use check_placement() first). id 0 picks a new ID.
## Returns the stand's ID.
func add_stand(def_id: StringName, anchor: Vector2i, facing: int, id := 0) -> int:
	var def := StandCatalog.get_def(def_id)
	if def == null:
		push_warning("Stands: unknown stand size %s" % def_id)
		return 0
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)

	var stand := StandScript.new()
	stand.id = id
	stand.def_id = def_id
	stand.anchor = anchor
	stand.facing = facing
	stand.rect = footprint(def, anchor, facing)
	var f := stand.get_facing_vector()
	stand.entry = BuildGrid.tile_corner_to_world(anchor)
	stand.stop = stand.entry - Vector3(f.x, 0.0, f.y) * (def.get_size().y - STOP_FROM_BACK)
	stand.connected = find_connection(def, anchor, facing)
	stand.node = _build_node(stand)
	add_child(stand.node)
	_stands[id] = stand
	_update_label(stand)
	stand_added.emit(id)
	return id


func remove_stand(id: int) -> StandScript:
	var stand: StandScript = _stands.get(id)
	if stand == null:
		return null
	_stands.erase(id)
	stand.node.queue_free()
	stand.node = null
	stand.label = null
	stand_removed.emit(id)
	return stand


## Rechecks every stand's connection when taxiway paving is laid or removed.
func _on_taxiways_changed() -> void:
	for stand: StandScript in _stands.values():
		var def := StandCatalog.get_def(stand.def_id)
		var connected := find_connection(def, stand.anchor, stand.facing) if def else false
		if connected == stand.connected:
			continue
		stand.connected = connected
		_update_label(stand)
		print("STAND | stand %d %s" % [stand.id, "connected to a taxiway" if connected else "not connected"])
		stand_changed.emit(stand.id)


## Text for a stand's size class and connection, such as
## "Medium stand: narrow-body" and "Connected to a taxiway".
func describe(stand: StandScript) -> PackedStringArray:
	var def := StandCatalog.get_def(stand.def_id)
	var size_class: Resource = def.get_size_class() if def else null
	var size_text := "%s: %s" % [def.display_name if def else String(stand.def_id),
		size_class.display_name.to_lower() if size_class else "?"]
	var link := "Connected to a taxiway" if stand.has_taxiway() else "Not connected to a taxiway"
	return PackedStringArray([size_text, link])


## Sets an extra line on the stand's label, such as its next reservation
## (stand allocation, step 23). Empty removes it.
func set_note(id: int, text: String) -> void:
	var stand: StandScript = _stands.get(id)
	if stand == null:
		return
	stand.note = text
	_update_label(stand)


func _update_label(stand: StandScript) -> void:
	if stand.label == null:
		return
	var lines := describe(stand)
	stand.label.text = "Stand %d\n%s\n%s" % [stand.id, lines[0], lines[1]]
	if stand.note != "":
		stand.label.text += "\n" + stand.note
	stand.label.modulate = CONNECTED_COLOR if stand.has_taxiway() else NOT_CONNECTED_COLOR


# --- Mesh -----------------------------------------------------------------------

func _build_node(stand: StandScript) -> Node3D:
	var root := Node3D.new()
	root.name = "Stand_%d" % stand.id
	var builder := MeshBuilderScript.new()
	var lo := BuildGrid.tile_corner_to_world(stand.rect.position)
	var hi := BuildGrid.tile_corner_to_world(stand.rect.end)
	builder.add_box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, PAVING_HEIGHT, hi.z), PAVING_SIDE_COLOR, PAVING_COLOR)

	var y := Vector3.UP * (PAVING_HEIGHT + MARKING_LIFT)
	# Red boundary line round the apron.
	var i := BOUNDARY_INSET
	var corners := [Vector3(lo.x + i, 0, lo.z + i), Vector3(hi.x - i, 0, lo.z + i),
		Vector3(hi.x - i, 0, hi.z - i), Vector3(lo.x + i, 0, hi.z - i)]
	for k in 4:
		_add_line(builder, corners[k] + y, corners[(k + 1) % 4] + y, LINE_WIDTH, BOUNDARY_COLOR)
	# Yellow lead-in line from the entry edge to the stop bar, and the stop bar across it.
	_add_line(builder, stand.entry + y, stand.stop + y, LINE_WIDTH, LEAD_IN_COLOR)
	var nose := stand.get_nose_direction()
	var across := nose.cross(Vector3.UP) * STOP_BAR_LENGTH * 0.5
	_add_line(builder, stand.stop - across + y, stand.stop + across + y, STOP_BAR_WIDTH, LEAD_IN_COLOR)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = builder.commit()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 24
	label.outline_size = 8
	label.position = (lo + hi) * 0.5 + Vector3.UP * LABEL_HEIGHT
	root.add_child(label)
	stand.label = label
	return root


## A flat painted line of this width from a to b.
static func _add_line(builder: RefCounted, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var side := (b - a).normalized().cross(Vector3.UP) * width * 0.5
	builder.add_quad([a - side, b - side, b + side, a + side], Vector3.UP, color)
