extends Node3D
## Test for the A320 and 737-800 models (checklist step 19).
## Run this scene on its own (F6). It loads each aircraft type's model scene,
## checks its size against the type data (length, wingspan, height), that it
## stands on its gear with the nose along -Z, its triangle budget, and that a
## livery can be applied, then prints PASS or FAIL for each check.
## The two aircraft stay on screen side by side to look at:
##   L      cycle sample liveries
##   G      raise / lower the landing gear
##   Camera as in the game (right drag rotate, WASD pan, wheel zoom)

const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const AircraftModelScript := preload("res://scripts/aircraft/aircraft_model.gd")
const AircraftLiveryScript := preload("res://scripts/aircraft/aircraft_livery.gd")
## Size checks allow this much difference from the type data.
const TOLERANCE := 0.02
const MAX_TRIANGLES := 6000

var _failures := 0
var _models: Array = []
var _liveries: Array = []
var _livery_index := 0
var _label: Label


func _ready() -> void:
	print("TEST START | aircraft models")
	_add_view()
	_liveries = [
		AircraftLiveryScript.new(),
		AircraftLiveryScript.make(Color(0.97, 0.97, 0.96), Color(0.10, 0.20, 0.45),
			Color(0.10, 0.20, 0.45), Color(0.85, 0.15, 0.20), Color(0.85, 0.15, 0.20)),
		AircraftLiveryScript.make(Color(1.0, 0.55, 0.10), Color(1.0, 0.55, 0.10),
			Color(0.98, 0.98, 0.97), Color(0.98, 0.98, 0.97), Color(0.98, 0.98, 0.97)),
	]
	var x := -25.0
	for type_id in [&"a320", &"b738"]:
		var model := _check_type(type_id)
		if model != null:
			model.position = Vector3(x, 0, 0)
			_models.append(model)
		x += 50.0
	_check_livery()
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the models can be looked at. Close the window when done.


func _check_type(type_id: StringName) -> AircraftModelScript:
	var def: Resource = AircraftCatalog.get_type(type_id)
	_expect("%s type data exists" % type_id, def != null)
	if def == null:
		return null
	_expect("%s has a model scene" % type_id, def.model_scene != null)
	if def.model_scene == null:
		return null
	var model := def.model_scene.instantiate() as AircraftModelScript
	_expect("%s model is an AircraftModel" % type_id, model != null)
	if model == null:
		return null
	add_child(model)
	_expect("%s model type_id matches" % type_id, model.type_id == type_id)
	var box := model.get_bounds()
	print("INFO | %s model %.2f m long, %.2f m span, %.2f m high (data %.2f, %.2f, %.2f)"
		% [type_id, box.size.z, box.size.x, box.size.y, def.length, def.wingspan, def.height])
	_expect("%s length matches data" % type_id, _close(box.size.z, def.length))
	_expect("%s wingspan matches data" % type_id, _close(box.size.x, def.wingspan))
	_expect("%s height matches data" % type_id, _close(box.end.y, def.height))
	_expect("%s stands on its wheels at ground level" % type_id, absf(box.position.y) < 0.05)
	_expect("%s nose points along -Z" % type_id, absf(box.position.z - model.nose_z) < 0.05)
	_expect("%s is symmetric" % type_id, absf(box.position.x + box.end.x) < 0.05)
	var tris := _triangles(model)
	print("INFO | %s model has %d triangles" % [type_id, tris])
	_expect("%s stays under %d triangles" % [type_id, MAX_TRIANGLES], tris > 0 and tris < MAX_TRIANGLES)
	model.gear_down = false
	_expect("%s gear can be raised" % type_id, not model.get_gear_mesh().visible)
	model.gear_down = true
	return model


func _check_livery() -> void:
	if _models.is_empty():
		return
	var model: AircraftModelScript = _models[0]
	var livery: AircraftLiveryScript = _liveries[1]
	model.apply_livery(livery)
	var body := model.get_body_mesh()
	_expect("livery sets body colour", body.get_instance_shader_parameter(&"body_colour") == livery.body)
	_expect("livery sets tail colour", body.get_instance_shader_parameter(&"tail_colour") == livery.tail)
	_expect("livery sets engine colour", body.get_instance_shader_parameter(&"engine_colour") == livery.engines)
	_expect("both aircraft share one material",
		_models.size() < 2 or body.material_override == (_models[1] as AircraftModelScript).get_body_mesh().material_override)
	model.apply_livery(_liveries[0])
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_L:
		_livery_index = (_livery_index + 1) % _liveries.size()
		for model: AircraftModelScript in _models:
			model.apply_livery(_liveries[_livery_index])
		_update_label()
	elif key.keycode == KEY_G:
		for model: AircraftModelScript in _models:
			model.gear_down = not model.gear_down
		_update_label()


func _update_label() -> void:
	var gear := "down" if _models.is_empty() or _models[0].gear_down else "up"
	_label.text = "A320 (left)   737-800 (right)\nL: livery %d of %d    G: gear (%s)\n%s" % [
		_livery_index + 1, _liveries.size(), gear,
		"ALL PASSED" if _failures == 0 else "%d FAILED" % _failures]


func _triangles(model: AircraftModelScript) -> int:
	var count := 0
	for mi: MeshInstance3D in [model.get_body_mesh(), model.get_gear_mesh()]:
		var arrays := mi.mesh.surface_get_arrays(0)
		count += floori((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3.0)
	return count


func _close(value: float, expected: float) -> bool:
	return absf(value - expected) <= expected * TOLERANCE


func _add_view() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.78, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.80, 0.88)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.57, 0.6)
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	var camera := OrbitCameraScript.new()
	camera.start_distance = 90.0
	camera.start_pitch_deg = 30.0
	add_child(camera)
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_color", Color(0.1, 0.12, 0.15))
	ui.add_child(_label)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
