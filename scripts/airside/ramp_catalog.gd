extends Node
## RampCatalog (autoload). Loads every runway ramp (RampDef .tres file) from
## data/ramps/ at startup, smallest first, straight before angled.

const RampDefScript := preload("res://scripts/airside/ramp_def.gd")
const TaxiwayDefScript := preload("res://scripts/airside/taxiway_def.gd")
const RAMPS_DIR := "res://data/ramps/"

## StringName ID -> RampDef
var _defs := {}
var _ordered: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_defs.clear()
	_ordered.clear()
	# list_directory also works in exported builds, where files are remapped.
	for file in ResourceLoader.list_directory(RAMPS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(RAMPS_DIR + file) as RampDefScript
		if def == null:
			push_warning("RampCatalog: %s is not a RampDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		if def.width < 2 or def.width % 2 != 0 or def.depth < def.width:
			push_warning("RampCatalog: %s needs an even width and a depth of at least its width" % file)
			continue
		_defs[def.id] = def
		_ordered.append(def)
	_ordered.sort_custom(func(a: RampDefScript, b: RampDefScript) -> bool:
		var ca := TaxiwayDefScript.SIZE_CLASSES.find(a.size_class)
		var cb := TaxiwayDefScript.SIZE_CLASSES.find(b.size_class)
		return ca < cb or (ca == cb and RampDefScript.SHAPES.find(a.shape) < RampDefScript.SHAPES.find(b.shape)))
	print("RAMPS | %d runway ramps loaded: %s" % [_ordered.size(),
		", ".join(_ordered.map(func(d: RampDefScript) -> String: return String(d.id)))])


## The definition with this ID, or null.
func get_def(id: StringName) -> RampDefScript:
	return _defs.get(id)


## Every definition, smallest first.
func get_all() -> Array:
	return _ordered.duplicate()
