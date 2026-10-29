extends RefCounted
## One built runway (checklist step 16), stored by the Runways node.
##
## A runway runs along world X or world Z. start and end are the grid corners
## the player dragged between, on the centreline; rect is every tile the
## paving covers. The two ends are what aircraft use: each has the threshold
## position, the direction an aircraft lands or takes off in from that end,
## its compass heading and its designator ("09", "27").
## World -Z is north, so a runway along X is 09/27 and one along Z is 18/36.

## Stable unique ID, used in saves and commands.
var id := 0
var def_id: StringName
var start := Vector2i.ZERO
var end := Vector2i.ZERO
## Tiles the runway covers.
var rect := Rect2i()
var length := 0
var width := 0
## Two Dictionaries, one per end (see make_end()). ends[0] is at start.
var ends: Array[Dictionary] = []
## Scene node with the runway's mesh and markings.
var node: Node3D


## Direction along the runway from start to end, in tiles (one axis only).
func get_axis() -> Vector2i:
	return (end - start).sign()


## World position of the middle of the runway.
func get_center() -> Vector3:
	return (ends[0].position + ends[1].position) * 0.5


## Compass heading in degrees (0 = north = world -Z) of travel along direction.
static func heading_of(direction: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)


## Runway designator for a heading: the heading in tens of degrees, 01 to 36.
static func designator_of(heading: float) -> String:
	var number := roundi(heading / 10.0) % 36
	return "%02d" % (36 if number == 0 else number)


## One runway end: the threshold (centreline at the edge of the paving) and
## the direction from there into the runway, which is the way an aircraft
## faces when it lands or lines up there.
static func make_end(threshold: Vector3, direction: Vector3) -> Dictionary:
	var heading := heading_of(direction)
	return {
		"position": threshold,
		"direction": direction,
		"heading": heading,
		"designator": designator_of(heading),
	}
