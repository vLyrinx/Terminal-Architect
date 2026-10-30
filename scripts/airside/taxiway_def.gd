class_name TaxiwayDef
extends Resource
## A taxiway size class (checklist step 17), stored as a .tres file in
## data/taxiways/ and loaded by the TaxiwayCatalog autoload. Paving is laid
## tile by tile (taxiways.gd), so a size is not something the player builds:
## it says how wide the paving around a taxi line must be for the line to take
## that class of aircraft. Like runways, each size suits an aircraft size
## class and every smaller one. Widths are real-world metres (1 tile = 1 m).

const SIZE_CLASSES := ["small", "medium", "large"]

## Unique ID. Never change it once games are saved.
@export var id: StringName
@export var display_name := ""
## Largest aircraft size class a taxi line on paving this wide handles.
@export_enum("small", "medium", "large") var size_class := "small"
## Paved width, in metres, a taxi line needs around it for this size.
@export var width := 5
## Aircraft it is meant for, shown in tooltips.
@export_multiline var aircraft := ""


## True if this taxiway can handle aircraft of size_class (or any smaller class).
func handles(aircraft_class: String) -> bool:
	return SIZE_CLASSES.find(aircraft_class) <= SIZE_CLASSES.find(size_class)
