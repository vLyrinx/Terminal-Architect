extends Node3D
## Test for the first fictional airline (checklist step 21).
## Run this scene on its own (F6). It loads Brightwater Airways from
## data/airlines/, checks its name, code, livery and fleet, builds a model for
## every aircraft in the fleet in the airline's livery, and prints PASS or FAIL
## for each check. The fleet stays parked in a row with registrations above
## it, to look at (camera as in the game).

const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const AircraftModelScript := preload("res://scripts/aircraft/aircraft_model.gd")
const AIRLINE := &"brightwater"
const SPACING := 45.0

var _failures := 0


func _ready() -> void:
	print("TEST START | first airline")
	_add_view()
	var airline: Resource = AirlineCatalog.get_airline(AIRLINE)
	_expect("airline loads from data", airline != null)
	if airline == null:
		_finish()
		return
	_expect("airline has a name", airline.display_name == "Brightwater Airways")
	_expect("airline has a 2-letter short code", airline.short_code.length() == 2)
	_expect("airline has a callsign", airline.callsign != "")
	_expect("airline has a livery", airline.livery != null)
	_expect("fleet has A320s", airline.fleet.get(&"a320", 0) > 0)
	_expect("fleet has 737-800s", airline.fleet.get(&"b738", 0) > 0)
	_expect("fleet has only A320s and 737-800s", airline.fleet.keys().all(func(t: StringName) -> bool:
		return t == &"a320" or t == &"b738"))
	var aircraft: Array[Dictionary] = airline.get_fleet_aircraft()
	_expect("fleet list matches fleet size", aircraft.size() == airline.get_fleet_size())
	var registrations := {}
	for a in aircraft:
		registrations[a.registration] = true
	_expect("registrations are unique", registrations.size() == aircraft.size())
	_expect("registrations start with the short code",
		aircraft.all(func(a: Dictionary) -> bool: return a.registration.begins_with(airline.short_code + "-")))

	var painted := 0
	var x := -(aircraft.size() - 1) * SPACING * 0.5
	for a in aircraft:
		var model := AirlineCatalog.make_aircraft_model(AIRLINE, a.type_id)
		if model == null:
			continue
		model.position = Vector3(x, 0, 0)
		add_child(model)
		if model.get_livery() == airline.livery and _body_colour(model) == airline.livery.body \
				and model.get_body_mesh().get_instance_shader_parameter(&"tail_colour") == airline.livery.tail:
			painted += 1
		var tag := Label3D.new()
		tag.text = "%s\n%s" % [a.registration, AircraftCatalog.get_type(a.type_id).display_name]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 160
		tag.outline_size = 24
		tag.position = Vector3(x, 17, 0)
		add_child(tag)
		x += SPACING
	_expect("a model is built for every aircraft in the fleet", painted > 0 or aircraft.is_empty())
	_expect("every aircraft wears the airline livery", painted == aircraft.size())
	_expect("unknown airline gives no model", AirlineCatalog.make_aircraft_model(&"nope", &"a320") == null)
	_finish()


func _body_colour(model: AircraftModelScript) -> Variant:
	return model.get_body_mesh().get_instance_shader_parameter(&"body_colour")


func _finish() -> void:
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the fleet can be looked at. Close the window when done.


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
	plane.size = Vector2(600, 300)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.57, 0.6)
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	var camera := OrbitCameraScript.new()
	camera.start_distance = 200.0
	camera.start_pitch_deg = 30.0
	add_child(camera)
	camera.current = true


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
