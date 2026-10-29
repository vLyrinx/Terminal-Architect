extends Node
## Route graph (checklist step 17): the network aircraft move on, built
## automatically from the runways and taxiways whenever either changes.
##
## Every runway and taxiway is a straight centreline. Nodes go at both ends of
## each one and wherever two centrelines meet:
##   - Crossing or T: two perpendicular centrelines cross, or one ends inside
##     the other's paving (so a taxiway that stops at a runway's edge still
##     joins the runway centreline). A taxiway's centreline is extended to the
##     meeting point; a runway's never goes past its thresholds.
##   - In line: two parallel centrelines on (nearly) the same line that touch
##     or overlap share their end points.
## Nodes closer than MERGE_DISTANCE are merged, which absorbs the half metre
## between centrelines of odd and even widths. Edges join neighbouring nodes
## along each centreline. Runway thresholds are marked with their designator.
## Each stand (checklist step 18) adds its lead-in line, from the stop bar out
## through the entry edge, which joins only taxiways: it is extended to the
## centreline of the taxiway in front. The stop bar node carries the stand ID.
##
## Node: {id, position (Vector3), runway_end ("09" or ""), on_runway, on_taxiway,
##        on_stand, stand_id (0 if none), edges (edge IDs)}
## Edge: {id, a, b (node IDs), length, kind ("runway", "taxiway" or "stand"),
##        source_id (runway, taxiway or stand ID), size_class}
## find_path() gives the shortest route between two nodes. Node and edge IDs
## are renumbered on every rebuild, so keep positions or runway designators,
## not IDs, across graph_changed.

signal graph_changed

## Nodes nearer than this, in metres, become one node.
const MERGE_DISTANCE := 1.0
## Station positions along one centreline closer than this are the same point.
const SAME_POINT := 0.01

## The Runways node (runways.gd).
@export var runways: Node3D
## The Taxiways node (taxiways.gd).
@export var taxiways: Node3D
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
	if taxiways:
		taxiways.taxiway_added.connect(_on_changed.unbind(1))
		taxiways.taxiway_removed.connect(_on_changed.unbind(1))
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


## Rebuilds the whole graph from the current runways and taxiways.
func rebuild() -> void:
	_rebuild_queued = false
	nodes.clear()
	edges.clear()
	_cells.clear()
	_astar.clear()

	var lines := _collect_lines()
	# Points along each line where it meets another, as distances along its axis.
	var stations: Array = []
	for line: Dictionary in lines:
		stations.append([line.u0, line.u1])
	for i in lines.size():
		for j in range(i + 1, lines.size()):
			_join(lines[i], lines[j], stations[i], stations[j])

	for i in lines.size():
		var line: Dictionary = lines[i]
		var points: Array = stations[i]
		points.sort()
		var previous := -1
		var previous_u := 0.0
		for u: float in points:
			if previous >= 0 and u - previous_u < SAME_POINT:
				continue
			var node_id := _node_at(_point(line, u))
			if line.kind == "runway":
				nodes[node_id].on_runway = true
			elif line.kind == "taxiway":
				nodes[node_id].on_taxiway = true
			else:
				nodes[node_id].on_stand = true
			if previous >= 0 and previous != node_id:
				_add_edge(previous, node_id, line)
			previous = node_id
			previous_u = u

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
	print("ROUTE GRAPH | %d nodes, %d edges from %d runways, %d taxiways and %d stands" % [nodes.size(), edges.size(),
		runways.get_count() if runways else 0, taxiways.get_count() if taxiways else 0,
		stands.get_count() if stands else 0])
	graph_changed.emit()


## Every runway and taxiway centreline as {kind, source_id, size_class, along_x,
## u0, u1 (span along the axis), f (the fixed coordinate), half_width, extendable}.
func _collect_lines() -> Array:
	var lines := []
	if runways:
		for runway: RefCounted in runways.get_all():
			var def := RunwayCatalog.get_def(runway.def_id)
			lines.append(_make_line("runway", runway.id, def.size_class if def else "",
				runway.ends[0].position, runway.ends[1].position, runway.width, false))
	if taxiways:
		for taxiway: RefCounted in taxiways.get_all():
			var def := TaxiwayCatalog.get_def(taxiway.def_id)
			lines.append(_make_line("taxiway", taxiway.id, def.size_class if def else "",
				taxiway.a, taxiway.b, taxiway.width, true))
	if stands:
		# No width, so a taxiway has to pass in front of the lead-in to join it.
		for stand: RefCounted in stands.get_all():
			var def := StandCatalog.get_def(stand.def_id)
			lines.append(_make_line("stand", stand.id, def.get_taxiway_class() if def else "",
				stand.stop, stand.entry, 0.0, true))
	return lines


func _make_line(kind: String, source_id: int, size_class: String, a: Vector3, b: Vector3,
		width: float, extendable: bool) -> Dictionary:
	var along_x := absf(b.x - a.x) >= absf(b.z - a.z)
	var ua := a.x if along_x else a.z
	var ub := b.x if along_x else b.z
	return {
		"kind": kind, "source_id": source_id, "size_class": size_class, "along_x": along_x,
		"u0": minf(ua, ub), "u1": maxf(ua, ub), "f": a.z if along_x else a.x,
		"half_width": width * 0.5, "extendable": extendable,
	}


## Adds the stations where two lines meet, if they do.
func _join(s: Dictionary, t: Dictionary, s_stations: Array, t_stations: Array) -> void:
	# A stand's lead-in only joins taxiways, never a runway or another stand.
	if (s.kind == "stand" and t.kind != "taxiway") or (t.kind == "stand" and s.kind != "taxiway"):
		return
	if s.along_x != t.along_x:
		# Perpendicular: they meet at (t.f along s, s.f along t). Each may reach
		# the other through the other's paving, but only taxiways are extended.
		if _reaches(s, t.f, t.half_width) and _reaches(t, s.f, s.half_width):
			s_stations.append(t.f)
			t_stations.append(s.f)
	elif absf(s.f - t.f) <= MERGE_DISTANCE:
		# In line: each gets the other's end points that lie on it.
		for u: float in [t.u0, t.u1]:
			if u >= s.u0 - MERGE_DISTANCE and u <= s.u1 + MERGE_DISTANCE:
				s_stations.append(clampf(u, s.u0, s.u1))
		for u: float in [s.u0, s.u1]:
			if u >= t.u0 - MERGE_DISTANCE and u <= t.u1 + MERGE_DISTANCE:
				t_stations.append(clampf(u, t.u0, t.u1))


## True if line reaches position u along its axis: inside its span, or (for a
## taxiway) beyond an end by no more than reach (the other's half width).
func _reaches(line: Dictionary, u: float, reach: float) -> bool:
	var slack: float = reach if line.extendable else 0.0
	return u >= line.u0 - slack - SAME_POINT and u <= line.u1 + slack + SAME_POINT


func _point(line: Dictionary, u: float) -> Vector3:
	return Vector3(u, 0.0, line.f) if line.along_x else Vector3(line.f, 0.0, u)


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


## Joins two nodes, unless they already are (overlapping taxiways give the same edge twice).
func _add_edge(a: int, b: int, line: Dictionary) -> void:
	for edge_id: int in nodes[a].edges:
		var edge: Dictionary = edges[edge_id]
		if edge.a == b or edge.b == b:
			return
	var id := edges.size() + 1
	edges[id] = {
		"id": id, "a": a, "b": b,
		"length": (nodes[a].position as Vector3).distance_to(nodes[b].position),
		"kind": line.kind, "source_id": line.source_id, "size_class": line.size_class,
	}
	nodes[a].edges.append(id)
	nodes[b].edges.append(id)
