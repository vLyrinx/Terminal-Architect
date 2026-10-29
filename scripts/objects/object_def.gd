class_name ObjectDef
extends Resource
## Definition of a placeable object (checklist step 11), stored as a .tres file
## in data/objects/ and loaded by the ObjectCatalog autoload. Add a new object
## by adding a file there; no code changes needed.
##
## Model convention: the model scene's origin is the centre of the footprint at
## floor level. Footprint X runs along the model's local X axis, footprint Y
## along its local Z axis, and the front of the object faces +Z.

## Categories in build menu order. Keep in step with the category list below.
const CATEGORIES := ["Terminal", "Check-in", "Security", "Seating", "Facilities", "Gate", "Test"]

## Unique ID used in saves and commands. Never change it once objects exist.
@export var id: StringName
@export var display_name := ""
@export_enum("Terminal", "Check-in", "Security", "Seating", "Facilities", "Gate", "Test") var category := "Terminal"
## Construction cost (charged once money exists, checklist step 14).
@export var cost := 0
## Size in tiles: X along the model's local X, Y along its local Z.
@export var footprint := Vector2i.ONE
@export var model: PackedScene
## Can be placed off the grid and at any angle (checklist step 93).
## Until then every object snaps to the grid and turns in 90 degree steps.
@export var free_placeable := false
## Must stand on terminal floor.
@export var requires_floor := true
