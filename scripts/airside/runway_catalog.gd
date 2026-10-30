extends Node
## RunwayCatalog (autoload, checklist step 16). Loads every runway size
## (RunwayDef .tres file) from data/runways/ at startup, smallest first.

const RunwayDefScript := preload("res://scripts/airside/runway_def.gd")
const RUNWAYS_DIR := "res://data/runways/"

## StringName ID -> RunwayDef
var _defs := {}
## Definitions from smallest to largest size class.
var _ordered: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_defs.clear()
	_ordered.clear()
	# list_directory also works in exported builds, where files are remapped.
	for file in ResourceLoader.list_directory(RUNWAYS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(RUNWAYS_DIR + file) as RunwayDefScript
		if def == null:
			push_warning("RunwayCatalog: %s is not a RunwayDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		if def.width < 2 or def.width % 2 != 0 or def.min_length < 1 or def.max_length < def.min_length:
			push_warning("RunwayCatalog: %s needs an even width and a valid length range" % file)
			continue
		if def.length < def.min_length or def.length > def.max_length \
				or def.length % (2 * BuildGrid.AIRSIDE_SNAP) != 0:
			push_warning("RunwayCatalog: %s needs a length inside its range, in steps of %d m" % [
				file, 2 * BuildGrid.AIRSIDE_SNAP])
			continue
		_defs[def.id] = def
		_ordered.append(def)
	_ordered.sort_custom(func(a: RunwayDefScript, b: RunwayDefScript) -> bool:
		return RunwayDefScript.SIZE_CLASSES.find(a.size_class) < RunwayDefScript.SIZE_CLASSES.find(b.size_class))
	print("RUNWAYS | %d runway sizes loaded: %s" % [_ordered.size(),
		", ".join(_ordered.map(func(d: RunwayDefScript) -> String:
			return "%s (%d m x %d m)" % [d.id, d.length, d.width]))])


## The definition with this ID, or null.
func get_def(id: StringName) -> RunwayDefScript:
	return _defs.get(id)


## Every definition, smallest first.
func get_all() -> Array:
	return _ordered.duplicate()
