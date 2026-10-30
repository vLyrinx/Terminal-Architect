extends Node
## Route graph (checklist step 17): the network aircraft move on, rebuilt
## automatically whenever runways, ramps, taxi lines or stands change.
##
## Aircraft follow painted lines, not paving (as in Airport CEO): taxiway
## paving on its own adds nothing. The graph is made of straight segments:
##   - runway centrelines, from threshold to threshold
##   - each runway ramp's taxi line, which starts on its runway's centreline
##     (the only way a runway joins the rest of the network)
##   - the player's taxi lines (taxi_lines.gd), if they are on paving
##   - each stand's lead-in, from the stop bar out through the entry edge;
##     it may reach up to STAND_REACH past the edge to meet a taxi line
## Segments are joined where they cross, where one ends on another (within
## MERGE_DISTANCE), and where they overlap in line. Runways join only ramps,
## and stand lead-ins join only taxi lines. Nodes closer than MERGE_DISTANCE
## are merged. Runway thresholds are marked with their designator and each
## stand's stop bar with the stand ID.
##
## Node: {id, position (Vector3), runway_end ("09" or ""), on_runway, on_taxiway,
##        on_stand, stand_id (0 if none), edges (edge IDs)}
## Edge: {id, a, b (node IDs), length, kind ("runway", "ramp", "taxiway" or
##        "stand"), source_id (runway, ramp, taxi line or stand ID), size_class}
## find_path() gives the shortest route between two nodes. Node and edge IDs
## are renumbered on every rebuild, so keep positions or runway designators,
## not IDs, across graph_changed.

signal graph_changed

## Nodes nearer than this, in metres, become one node; segments that come this
## close to meeting are joined.
const MERGE_DISTANCE := 1.0
## A stand's lead-in may reach this far past its entry edge to meet a taxi line.
const STAND_REACH := 20.0
## Which segment kinds join each other.
const JOINS := {
	"runway": ["ramp"],
	"ramp": ["runway", "ramp", "taxiway"],
	"taxiway": ["ramp", "taxiway", "stand"],
	"stand": ["taxiway"],
}

## The Runways node (runways.gd).
@export var runways: Node3D
## The Ramps node (ramps.gd).
@export var ramps: Node3D
## The TaxiLines node (taxi_lines.gd).
@export var taxi_lines: Node3D
## The Stands node (stands.gd).
@export var stands: Node3D

## Node ID -> node Dictionary
var nodes := {}
## Edge ID -> edge Dictionary
var edges := {}

var _astar := AStar3D.new()
var _rebuild_queued := false
## Spatial hash for merging nodes: Vector2i cell -> Array of node IDs.
var _cells := {}


func _ready() -> void:
	if runways:
		runways.runway_added.connect(_on_changed.unbind(1))
		runways.runway_removed.connect(_on_changed.unbind(1))
	if ramps:
		ramps.ramp_added.connect(_on_changed.unbind(1))
		ramps.ramp_removed.connect(_on_changed.unbind(1))
	if taxi_lines:
		taxi_lines.lines_changed.connect(_on_changed)
	if stands:
		stands.stand_added.connect(_on_changed.unbind(1))
		stands.stand_removed.connect(_on_changed.unbind(1))
	rebuild()


# --- Queries --------------------------------------------------------------------

func get_node_count() -> int:
	return nodes.size()


func get_edge_count() -> int:
	return edges.size()


## IDs of the nodes joined to a node by one edge.
func get_neighbours(node_id: int) -> Array[int]:
	var result: Array[int] = []
	for edge_id: int in nodes[node_id].edges:
		var edge: Dictionary = edges[edge_id]
		result.append(edge.b if edge.a == node_id else edge.a)
	return result


## The node nearest a world position, or -1 if there are none.
func nearest_node(position: Vector3) -> int:
	if nodes.is_empty():
		return -1
	return _astar.get_closest_point(position)


## The node at a runway threshold with this designator ("09"), or -1.
func find_runway_end(designator: String) -> int:
	for node: Dictionary in nodes.values():
		if node.runway_end == designator:
			return node.id
	return -1


## The node at a stand's stop bar, or -1.
func find_stand(stand_id: int) -> int:
	for node: Dictionary in nodes.values():
		if node.stand_id == stand_id:
			return node.id
	return -1


## Shortest route between two nodes as node IDs, from first to last, or empty
## if they aren't connected.
func find_path(from_id: int, to_id: int) -> Array[int]:
	var result: Array[int] = []
	if not _astar.has_point(from_id) or not _astar.has_point(to_id):
		return result
	for id in _astar.get_id_path(from_id, to_id):
		result.append(int(id))
	return result


## Total length of a route of node IDs, in metres.
func path_length(path: Array[int]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += (nodes[path[i]].position as Vector3).distance_to(nodes[path[i - 1]].position)
	return total


# --- Building ---------------------------------------------------------------------

func _on_changed() -> void:
	# Several changes in one frame (such as a demolish) give one rebuild.
	if not _rebuild_queued:
		_rebuild_queued = true
		rebuild.call_deferred()


## Rebuilds the whole graph from the current runways, ramps, taxi lines and stands.
func rebuild() -> void:
	_rebuild_queued = false
	nodes.clear()
	edges.clear()
	_cells.clear()
	_astar.clear()

	var segments := _collect_segments()
	# Points along each segment where it meets another, as distances from its start.
	var stations: Array = []
	for segment: Dictionary in segments:
		stations.append([0.0, segment.length])
	for i in segments.size():
		for j in range(i + 1, segments.size()):
			if JOINS[segments[i].kind].has(segments[j].kind):
				_join(segments[i], segments[j], stations[i], stations[j])

	for i in segments.size():
		var segment: Dictionary = segments[i]
		var points: Array = stations[i]
		points.sort()
		var previous := -1
		for s: float in points:
			var node_id := _node_at(_point(segment, s))
			match segment.kind:
				"runway":
					nodes[node_id].on_runway = true
				"stand":
					nodes[node_id].on_stand = true
				_:
					nodes[node_id].on_taxiway = true
			if previous >= 0 and previous != node_id:
				_add_edge(previous, node_id, segment)
			previous = node_id

	if runways:
		for runway: RefCounted in runways.get_all():
			for runway_end: Dictionary in runway.ends:
				var node_id := _find_node_near(runway_end.position)
				if node_id >= 0:
					nodes[node_id].runway_end = runway_end.designator
	if stands:
		for stand: RefCounted in stands.get_all():
			var node_id := _find_node_near(stand.stop)
			if node_id >= 0:
				nodes[node_id].stand_id = stand.id

	for node: Dictionary in nodes.values():
		_astar.add_point(node.id, node.position)
	for edge: Dictionary in edges.values():
		_astar.connect_points(edge.a, edge.b)
	print("ROUTE GRAPH | %d nodes, %d edges from %d runways, %d ramps, %d taxi lines and %d stands" % [
		nodes.size(), edges.size(), runways.get_count() if runways else 0, ramps.get_count() if ramps else 0,
		taxi_lines.get_count() if taxi_lines else 0, stands.get_count() if stands else 0])
	graph_changed.emit()


## Every segment as {kind, source_id, size_class, a, b (Vector2 world X/Z),
## dir (unit), length, reach (how far it may extend past b)}.
func _collect_segments() -> Array:
	var segments := []
	if runways:
		for runway: RefCounted in runways.get_all():
			var def := RunwayCatalog.get_def(runway.def_id)
			segments.append(_make_segment("runway", runway.id, def.size_class if def else "",
				runway.ends[0].position, runway.ends[1].position))
	if ramps:
		for ramp: RefCounted in ramps.get_all():
			var def := RampCatalog.get_def(ramp.def_id)
			var points: PackedVector2Array = ramp.get_corner_points()
			for i in range(1, points.size()):
				segments.append(_make_segment("ramp", ramp.id, def.size_class if def else "",
					_corner_to_world(points[i - 1]), _corner_to_world(points[i])))
	if taxi_lines:
		for line: RefCounted in taxi_lines.get_all():
			if line.is_usable():
				segments.append(_make_segment("taxiway", line.id, line.size_class,
					BuildGrid.tile_corner_to_world(line.a), BuildGrid.tile_corner_to_world(line.b)))
	if stands:
		for stand: RefCounted in stands.get_all():
			var def := StandCatalog.get_def(stand.def_id)
			segments.append(_make_segment("stand", stand.id, def.get_taxiway_class() if def else "",
				stand.stop, stand.entry, STAND_REACH))
	return segments


func _make_segment(kind: String, source_id: int, size_class: String, a: Vector3, b: Vector3,
		reach := 0.0) -> Dictionary:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	return {
		"kind": kind, "source_id": source_id, "size_class": size_class, "a": a2, "b": b2,
		"dir": (b2 - a2).normalized(), "length": a2.distance_to(b2), "reach": reach,
	}


## Adds the stations where two segments meet, if they do.
func _join(s: Dictionary, t: Dictionary, s_stations: Array, t_stations: Array) -> void:
	var cross: float = s.dir.cross(t.dir)
	if absf(cross) > 0.001:
		# They cross where the two lines meet, if that's on (or within reach of) both.
		var offset: Vector2 = t.a - s.a
		var along_s := offset.cross(t.dir) / cross
		var along_t := offset.cross(s.dir) / cross
		if _within(s, along_s) and _within(t, along_t):
			s_stations.append(clampf(along_s, 0.0, s.length + s.reach))
			t_stations.append(clampf(along_t, 0.0, t.length + t.reach))
		return
	# Parallel: if on the same line, each gets the other's end points that lie on it.
	if absf((t.a - s.a).cross(s.dir)) > MERGE_DISTANCE:
		return
	for p: Vector2 in [t.a, t.b]:
		var along: float = (p - s.a).dot(s.dir)
		if _within(s, along):
			s_stations.append(clampf(along, 0.0, s.length))
	for p: Vector2 in [s.a, s.b]:
		var along: float = (p - t.a).dot(t.dir)
		if _within(t, along):
			t_stations.append(clampf(along, 0.0, t.length))


## True if a distance from a segment's start is on it, allowing MERGE_DISTANCE
## at each end and its reach past the end.
func _within(segment: Dictionary, along: float) -> bool:
	return along >= -MERGE_DISTANCE and along <= segment.length + segment.reach + MERGE_DISTANCE


func _point(segment: Dictionary, along: float) -> Vector3:
	var p: Vector2 = segment.a + segment.dir * along
	return Vector3(p.x, 0.0, p.y)


func _corner_to_world(corner: Vector2) -> Vector3:
	return BuildGrid.origin + Vector3(corner.x, 0.0, corner.y) * BuildGrid.TILE_SIZE


## The node at a position, merging with any node within MERGE_DISTANCE.
func _node_at(position: Vector3) -> int:
	var existing := _find_node_near(position)
	if existing >= 0:
		return existing
	var id := nodes.size() + 1
	nodes[id] = {"id": id, "position": position, "runway_end": "", "on_runway": false, "on_taxiway": false,
		"on_stand": false, "stand_id": 0, "edges": []}
	var cell := _cell(position)
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append(id)
	return id


func _find_node_near(position: Vector3) -> int:
	var cell := _cell(position)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for id: int in _cells.get(cell + Vector2i(dx, dy), []):
				if (nodes[id].position as Vector3).distance_to(position) <= MERGE_DISTANCE:
					return id
	return -1


func _cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / (MERGE_DISTANCE * 2.0)), floori(position.z / (MERGE_DISTANCE * 2.0)))


## Joins two nodes, unless they already are (overlapping lines give the same edge twice).
func _add_edge(a: int, b: int, segment: Dictionary) -> void:
	for edge_id: int in nodes[a].edges:
		var edge: Dictionary = edges[edge_id]
		if edge.a == b or edge.b == b:
			return
	var id := edges.size() + 1
	edges[id] = {
		"id": id, "a": a, "b": b,
		"length": (nodes[a].position as Vector3).distance_to(nodes[b].position),
		"kind": segment.kind, "source_id": segment.source_id, "size_class": segment.size_class,
	}
	nodes[a].edges.append(id)
	nodes[b].edges.append(id)
