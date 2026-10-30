extends RefCounted
## One painted taxi line, stored by the TaxiLines node.
##
## A straight line between two grid corners on the 10 m airside grid, along X,
## along Z or at 45 degrees. It has to lie on taxiway or ramp paving; the
## smallest paving under it sets the largest aircraft size class it takes. If
## paving under it is removed the line stays, drawn red, and aircraft can't use
## it until the paving is back.

## Stable unique ID, used in saves and commands.
var id := 0
var a := Vector2i.ZERO
var b := Vector2i.ZERO
## Metres from a to b.
var length := 0.0
## Taxiway size class it takes ("small", "medium" or "large"), or "" if it
## isn't all on paving any more.
var size_class := ""
## Scene node with the line's mesh.
var node: Node3D


func is_usable() -> bool:
	return size_class != ""
