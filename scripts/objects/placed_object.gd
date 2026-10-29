extends RefCounted
## One placed object (checklist step 11). Owned by PlacedObjects.

## Stable unique ID. Never reused, even after the object is deleted.
var id := 0
## ID of its ObjectDef in the ObjectCatalog.
var def_id: StringName
## Exact world position of the footprint centre, on the floor surface.
var position := Vector3.ZERO
## Exact rotation around the vertical axis, in radians.
var rotation := 0.0
var floor_index := 0
## Tiles the object blocks, worked out from its footprint at this position and rotation.
var tiles: Array[Vector2i] = []
## The object's model in the scene.
var node: Node3D


## Plain data for saving or sending over the network.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"def": String(def_id),
		"position": [position.x, position.y, position.z],
		"rotation": rotation,
		"floor": floor_index,
	}
