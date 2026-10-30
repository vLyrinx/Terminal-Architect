extends RefCounted
## One runway ramp, stored by the Ramps node.
##
## A ramp is laid out in its own frame: u runs along the runway, v runs out
## from the runway centreline (0) past the runway's edge (half_runway) to the
## ramp's outer end (outer_v), which is anchor, a grid corner on the 10 m
## airside grid. points is the ramp's taxi line in that frame, from the runway
## centreline to the outer end, with its bends already rounded; it doubles as
## the middle of the paving, which is width wide.

## Stable unique ID, used in saves and commands.
var id := 0
var def_id: StringName
var runway_id := 0
## Grid corner in the middle of the outer end, where taxiways join.
var anchor := Vector2i.ZERO
## Angled ramps only: +1 or -1, which way along the runway they lean.
var lean := 1
## Frame: centre is the point on the runway centreline opposite the anchor,
## in grid-corner units; along and out are unit vectors.
var centre := Vector2.ZERO
var along := Vector2.RIGHT
var out := Vector2.DOWN
var half_runway := 0.0
var outer_v := 0.0
var width := 0
## Taxi line in the ramp's frame, as (u, v) points.
var points := PackedVector2Array()
## Tiles covered by the paving beside the runway (a bounding box).
var rect := Rect2i()
## Scene node with the ramp's mesh and sign.
var node: Node3D


## A point of the ramp's frame in grid-corner units.
func to_corner(local: Vector2) -> Vector2:
	return centre + along * local.x + out * local.y


## A grid-corner position in the ramp's frame.
func to_local(corner: Vector2) -> Vector2:
	var d := corner - centre
	return Vector2(d.dot(along), d.dot(out))


## The taxi line in grid-corner units.
func get_corner_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		result.append(to_corner(p))
	return result


## True if a grid-corner position is on the ramp's paving beside the runway.
func covers(corner: Vector2, margin := 0.05) -> bool:
	var p := to_local(corner)
	if p.y < half_runway - margin or p.y > outer_v + margin:
		return false
	for i in range(1, points.size()):
		var closest := Geometry2D.get_closest_point_to_segment(p, points[i - 1], points[i])
		if closest.distance_to(p) <= width * 0.5 + margin:
			return true
	return false
