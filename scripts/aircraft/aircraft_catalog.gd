extends Node
## AircraftCatalog (autoload, checklist step 20). Loads every aircraft size
## class (SizeClassDef) from data/size_classes/ and every aircraft type
## (AircraftTypeDef) from data/aircraft/ at startup, and lets other systems
## look them up.

const SizeClassDefScript := preload("res://scripts/aircraft/size_class_def.gd")
const AircraftTypeDefScript := preload("res://scripts/aircraft/aircraft_type_def.gd")
const SIZE_CLASSES_DIR := "res://data/size_classes/"
const AIRCRAFT_DIR := "res://data/aircraft/"

## StringName ID -> SizeClassDef
var _classes := {}
## Size classes from smallest to largest.
var _ordered_classes: Array = []
## StringName ID -> AircraftTypeDef
var _types := {}
## Types ordered by size class, then name.
var _ordered_types: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_load_size_classes()
	_load_types()


func _load_size_classes() -> void:
	_classes.clear()
	_ordered_classes.clear()
	# list_directory also works in exported builds, where files are remapped.
	for file in ResourceLoader.list_directory(SIZE_CLASSES_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(SIZE_CLASSES_DIR + file) as SizeClassDefScript
		if def == null:
			push_warning("AircraftCatalog: %s is not a SizeClassDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		if def.get_rank() == -1:
			push_warning("AircraftCatalog: %s has unknown size class ID '%s'" % [file, def.id])
			continue
		_classes[def.id] = def
		_ordered_classes.append(def)
	_ordered_classes.sort_custom(func(a: SizeClassDefScript, b: SizeClassDefScript) -> bool:
		return a.get_rank() < b.get_rank())
	if _ordered_classes.size() != SizeClassDefScript.IDS.size():
		push_warning("AircraftCatalog: expected %d size classes, found %d"
			% [SizeClassDefScript.IDS.size(), _ordered_classes.size()])
	print("SIZE CLASSES | %d loaded: %s" % [_ordered_classes.size(),
		", ".join(_ordered_classes.map(func(c: SizeClassDefScript) -> String:
			return "%s (%s stand %dx%d tiles, wingspan <= %.0f m, runway %d m, %s)" % [c.id,
				c.stand_class, c.stand_size_tiles.x, c.stand_size_tiles.y, c.max_wingspan,
				c.runway_length_needed, c.unlock_stage]))])


func _load_types() -> void:
	_types.clear()
	_ordered_types.clear()
	for file in ResourceLoader.list_directory(AIRCRAFT_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(AIRCRAFT_DIR + file) as AircraftTypeDefScript
		if def == null:
			push_warning("AircraftCatalog: %s is not an AircraftTypeDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		var size_class := get_size_class(StringName(def.size_class))
		if size_class == null:
			push_warning("AircraftCatalog: %s uses unknown size class '%s'" % [file, def.size_class])
			continue
		if def.wingspan > size_class.max_wingspan:
			push_warning("AircraftCatalog: %s wingspan %.1f m is wider than %s allows (%.0f m)"
				% [file, def.wingspan, size_class.id, size_class.max_wingspan])
		if def.runway_length_needed > size_class.runway_length_needed:
			push_warning("AircraftCatalog: %s needs %d m of runway, more than %s (%d m)"
				% [file, def.runway_length_needed, size_class.id, size_class.runway_length_needed])
		_types[def.id] = def
		_ordered_types.append(def)
	_ordered_types.sort_custom(func(a: AircraftTypeDefScript, b: AircraftTypeDefScript) -> bool:
		var ra := SizeClassDefScript.IDS.find(a.size_class)
		var rb := SizeClassDefScript.IDS.find(b.size_class)
		return ra < rb if ra != rb else a.display_name < b.display_name)
	print("AIRCRAFT | %d types loaded: %s" % [_ordered_types.size(),
		", ".join(_ordered_types.map(func(t: AircraftTypeDefScript) -> String:
			return "%s (%s, %d seats, %.1f m span, %d min turnaround)" % [t.id, t.size_class,
				t.seats, t.wingspan, t.turnaround_minutes]))])


## The aircraft type with this ID, or null.
func get_type(id: StringName) -> AircraftTypeDefScript:
	return _types.get(id)


## Every aircraft type, smallest size class first.
func get_all_types() -> Array:
	return _ordered_types.duplicate()


## Every aircraft type in the size class with this ID.
func get_types_in_class(class_id: StringName) -> Array:
	return _ordered_types.filter(func(t: AircraftTypeDefScript) -> bool:
		return StringName(t.size_class) == class_id)


## The size class with this ID, or null.
func get_size_class(id: StringName) -> SizeClassDefScript:
	return _classes.get(id)


## Every size class, smallest first.
func get_all_size_classes() -> Array:
	return _ordered_classes.duplicate()


## The size class of the aircraft type with this ID, or null.
func get_class_of(type_id: StringName) -> SizeClassDefScript:
	var def := get_type(type_id)
	return get_size_class(StringName(def.size_class)) if def != null else null
