extends Node
## StandCatalog (autoload, checklist step 18). Loads every stand size
## (StandDef .tres file) from data/stands/ at startup, smallest first.
## Comes after AircraftCatalog in the autoload list, since stands read their
## sizes from its size classes.

const StandDefScript := preload("res://scripts/airside/stand_def.gd")
const SizeClassDefScript := preload("res://scripts/aircraft/size_class_def.gd")
const STANDS_DIR := "res://data/stands/"

## StringName ID -> StandDef
var _defs := {}
## Definitions from smallest to largest size class.
var _ordered: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_defs.clear()
	_ordered.clear()
	# list_directory also works in exported builds, where files are remapped.
	for file in ResourceLoader.list_directory(STANDS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(STANDS_DIR + file) as StandDefScript
		if def == null:
			push_warning("StandCatalog: %s is not a StandDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		if def.get_size_class() == null:
			push_warning("StandCatalog: %s uses unknown size class '%s'" % [file, def.size_class])
			continue
		_defs[def.id] = def
		_ordered.append(def)
	_ordered.sort_custom(func(a: StandDefScript, b: StandDefScript) -> bool:
		return SizeClassDefScript.IDS.find(a.size_class) < SizeClassDefScript.IDS.find(b.size_class))
	print("STANDS | %d stand sizes loaded: %s" % [_ordered.size(),
		", ".join(_ordered.map(func(d: StandDefScript) -> String:
			return "%s (%s, %d x %d m, fits %s)" % [d.id, d.size_class, d.get_size().x, d.get_size().y,
				", ".join(d.get_fitting_types().map(func(t: Resource) -> String: return String(t.id)))]))])


## The definition with this ID, or null.
func get_def(id: StringName) -> StandDefScript:
	return _defs.get(id)


## Every definition, smallest first.
func get_all() -> Array:
	return _ordered.duplicate()
