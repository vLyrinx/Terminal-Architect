extends Node
## TaxiwayCatalog (autoload, checklist step 17). Loads every taxiway size
## (TaxiwayDef .tres file) from data/taxiways/ at startup, smallest first.

const TaxiwayDefScript := preload("res://scripts/airside/taxiway_def.gd")
const TAXIWAYS_DIR := "res://data/taxiways/"

## StringName ID -> TaxiwayDef
var _defs := {}
## Definitions from smallest to largest size class.
var _ordered: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_defs.clear()
	_ordered.clear()
	# list_directory also works in exported builds, where files are remapped.
	for file in ResourceLoader.list_directory(TAXIWAYS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(TAXIWAYS_DIR + file) as TaxiwayDefScript
		if def == null:
			push_warning("TaxiwayCatalog: %s is not a TaxiwayDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		if def.width < 2 or def.width % 2 != 0 or def.min_length < 1:
			push_warning("TaxiwayCatalog: %s needs an even width and a minimum length" % file)
			continue
		_defs[def.id] = def
		_ordered.append(def)
	_ordered.sort_custom(func(a: TaxiwayDefScript, b: TaxiwayDefScript) -> bool:
		return TaxiwayDefScript.SIZE_CLASSES.find(a.size_class) < TaxiwayDefScript.SIZE_CLASSES.find(b.size_class))
	print("TAXIWAYS | %d taxiway sizes loaded: %s" % [_ordered.size(),
		", ".join(_ordered.map(func(d: TaxiwayDefScript) -> String: return "%s (%d m wide)" % [d.id, d.width]))])


## The definition with this ID, or null.
func get_def(id: StringName) -> TaxiwayDefScript:
	return _defs.get(id)


## Every definition, smallest first.
func get_all() -> Array:
	return _ordered.duplicate()
