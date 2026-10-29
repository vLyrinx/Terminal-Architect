class_name TaxiwayDef
extends Resource
## Definition of a taxiway size (checklist step 17), stored as a .tres file in
## data/taxiways/ and loaded by the TaxiwayCatalog autoload. Like runways, each
## size suits an aircraft size class and every smaller one. Widths are
## real-world metres (1 tile = 1 m).

const SIZE_CLASSES := ["small", "medium", "large"]

## Unique ID used in saves and commands. Never change it once taxiways exist.
@export var id: StringName
@export var display_name := ""
## Largest aircraft size class this taxiway handles.
@export_enum("small", "medium", "large") var size_class := "small"
## Paved width in metres. Must be even, so the centreline is on a grid line.
@export var width := 16
## Shortest piece the player can build, in metres.
@export var min_length := 10
## Price per metre of length.
@export var cost_per_metre := 20
## Aircraft it is meant for, shown in the build menu tooltip.
@export_multiline var aircraft := ""
## Build menu category (checklist step 15): an ID from build_categories.gd.
@export var menu_category := "airside"
## Icon shown on the taxiway's build menu button.
@export var icon: Texture2D


## Construction price of a taxiway of this size and length.
func get_cost(length: int) -> int:
	return length * cost_per_metre


## True if this taxiway can handle aircraft of size_class (or any smaller class).
func handles(aircraft_class: String) -> bool:
	return SIZE_CLASSES.find(aircraft_class) <= SIZE_CLASSES.find(size_class)
