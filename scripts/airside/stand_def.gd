class_name StandDef
extends Resource
## Definition of a stand size (checklist step 18), stored as a .tres file in
## data/stands/ and loaded by the StandCatalog autoload. Its footprint and the
## taxiway it needs come from its aircraft size class (data/size_classes/,
## checklist step 20), so a stand takes every aircraft type of that class and
## every smaller one.

## Unique ID used in saves and commands. Never change it once stands exist.
@export var id: StringName
@export var display_name := ""
## Largest aircraft size class the stand takes (SizeClassDef.IDS).
@export_enum("regional_turboprop", "regional_jet", "narrow_body", "wide_body", "very_large") var size_class := "narrow_body"
## Construction price.
@export var cost := 60000
## Build menu category (checklist step 15): an ID from build_categories.gd.
@export var menu_category := "airside"
## Icon shown on the stand's build menu button.
@export var icon: Texture2D


func get_size_class() -> Resource:
	return AircraftCatalog.get_size_class(StringName(size_class))


## Footprint in tiles: x across the wingspan (along the entry edge), y deep
## (along the lead-in line).
func get_size() -> Vector2i:
	var c := get_size_class()
	return c.stand_size_tiles if c else Vector2i(50, 70)


## Smallest taxiway size class (TaxiwayDef.SIZE_CLASSES) the stand can open onto.
func get_taxiway_class() -> String:
	var c := get_size_class()
	return c.taxiway_class if c else "small"


## True if aircraft of the type with this ID fit on the stand.
func takes(type_id: StringName) -> bool:
	var type := AircraftCatalog.get_type(type_id)
	var c := get_size_class()
	return type != null and c != null and c.takes(StringName(type.size_class))


## Every aircraft type that fits, smallest first.
func get_fitting_types() -> Array:
	return AircraftCatalog.get_all_types().filter(func(t: Resource) -> bool: return takes(t.id))
