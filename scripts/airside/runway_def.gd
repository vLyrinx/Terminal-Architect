class_name RunwayDef
extends Resource
## Definition of a runway size (checklist step 16), stored as a .tres file in
## data/runways/ and loaded by the RunwayCatalog autoload. Each size suits an
## aircraft size class: a runway handles its own class and every smaller one.
## Lengths and widths are real-world metres (1 tile = 1 m).

const SIZE_CLASSES := ["small", "medium", "large"]

## Unique ID used in saves and commands. Never change it once runways exist.
@export var id: StringName
@export var display_name := ""
## Largest aircraft size class this runway handles (stands use the same classes).
@export_enum("small", "medium", "large") var size_class := "small"
## Paved width in metres.
@export var width := 30
## Shortest and longest length the player can build, in metres.
@export var min_length := 1200
@export var max_length := 1800
## Price per metre of length.
@export var cost_per_metre := 60
## Aircraft it is meant for, shown in the build menu tooltip.
@export_multiline var aircraft := ""
## Build menu category (checklist step 15): an ID from build_categories.gd.
@export var menu_category := "airside"
## Icon shown on the runway's build menu button.
@export var icon: Texture2D


## Construction price of a runway of this size and length.
func get_cost(length: int) -> int:
	return length * cost_per_metre


## True if this runway can handle aircraft of size_class (or any smaller class).
func handles(aircraft_class: String) -> bool:
	return SIZE_CLASSES.find(aircraft_class) <= SIZE_CLASSES.find(size_class)
