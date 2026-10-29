extends RefCounted
## One straight taxiway piece (checklist step 17), stored by the Taxiways node.
##
## Like a runway it runs along world X or world Z between two grid corners on
## its centreline (start and end), and rect is every tile its paving covers.
## Taxiways may cross or touch each other and runways; the RouteGraph joins
## them where they meet.

## Stable unique ID, used in saves and commands.
var id := 0
var def_id: StringName
var start := Vector2i.ZERO
var end := Vector2i.ZERO
## Tiles the taxiway covers.
var rect := Rect2i()
var length := 0
var width := 0
## World positions of the two ends of the centreline.
var a := Vector3.ZERO
var b := Vector3.ZERO
## Scene node with the taxiway's mesh.
var node: Node3D


## Direction along the taxiway from start to end, in tiles (one axis only).
func get_axis() -> Vector2i:
	return (end - start).sign()
