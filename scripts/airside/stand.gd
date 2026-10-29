extends RefCounted
## One aircraft stand (checklist step 18), stored by the Stands node.
##
## A stand is a rectangle of apron with one entry edge that opens onto a
## taxiway. Aircraft taxi in nose first along the lead-in line, stop at the
## stop bar near the back, and are pushed back out through the entry edge.
## anchor is the grid corner in the middle of the entry edge and facing says
## which way the entry edge looks (an index into Stands.FACINGS).

## Stable unique ID, used in saves and commands. Shown as the stand number.
var id := 0
var def_id: StringName
var anchor := Vector2i.ZERO
var facing := 0
## Tiles the stand covers.
var rect := Rect2i()
## World position of the middle of the entry edge, where the lead-in meets the taxiway paving.
var entry := Vector3.ZERO
## World position of the stop bar on the lead-in line, where a parked aircraft's nose wheel stops.
var stop := Vector3.ZERO
## ID of the taxiway the stand opens onto, or 0 if it isn't connected.
var taxiway_id := 0
## Scene node with the stand's mesh and label.
var node: Node3D
var label: Label3D


## Direction out of the entry edge, in tiles.
func get_facing_vector() -> Vector2i:
	return [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)][facing]


## Direction a parked aircraft's nose points (away from the taxiway).
func get_nose_direction() -> Vector3:
	var f := get_facing_vector()
	return -Vector3(f.x, 0.0, f.y)


## True if the stand opens onto a taxiway big enough for it.
func has_taxiway() -> bool:
	return taxiway_id != 0
