extends Node
## ObjectCatalog (autoload, checklist step 11). Loads every object definition
## (ObjectDef .tres file) from data/objects/ at startup and looks them up by ID.

const ObjectDefScript := preload("res://scripts/objects/object_def.gd")
const OBJECTS_DIR := "res://data/objects/"

## StringName ID -> ObjectDef
var _defs := {}
## Definitions in build menu order (by category, then name).
var _ordered: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_defs.clear()
	_ordered.clear()
	# list_directory also works in exported builds, where files are remapped.
	for file in ResourceLoader.list_directory(OBJECTS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(OBJECTS_DIR + file) as ObjectDefScript
		if def == null:
			push_warning("ObjectCatalog: %s is not an ObjectDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		if _defs.has(def.id):
			push_warning("ObjectCatalog: duplicate object ID %s in %s" % [def.id, file])
			continue
		if def.footprint.x < 1 or def.footprint.y < 1 or def.model == null:
			push_warning("ObjectCatalog: %s needs a footprint of at least 1 x 1 and a model" % file)
			continue
		_defs[def.id] = def
		_ordered.append(def)
	_ordered.sort_custom(_menu_order)
	print("OBJECTS | %d object types loaded: %s" % [_ordered.size(),
		", ".join(_ordered.map(func(d: ObjectDefScript) -> String: return String(d.id)))])


## The definition with this ID, or null.
func get_def(id: StringName) -> ObjectDefScript:
	return _defs.get(id)


## Every definition, in build menu order.
func get_all() -> Array:
	return _ordered.duplicate()


func _menu_order(a: ObjectDefScript, b: ObjectDefScript) -> bool:
	var ca := ObjectDefScript.CATEGORIES.find(a.category)
	var cb := ObjectDefScript.CATEGORIES.find(b.category)
	if ca != cb:
		return ca < cb
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0
