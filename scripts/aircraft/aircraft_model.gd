@tool
class_name AircraftModel
extends Node3D
## Low-poly aircraft model built in code (checklist step 19): fuselage with
## windows, cockpit and cheatline, swept wings with winglets, tailplane, fin,
## engines on pylons and landing gear, at real-world scale (1 unit = 1 m).
##
## The shape comes from the exported numbers, so one script draws every type;
## each type is a scene in models/aircraft/ that sets them.
## Origin: on the ground, centred between the main gear wheels. Nose points
## along -Z (Node3D forward), so the model turns about its main gear.
##
## All parts share one livery material; apply_livery() sets the airline's
## colours as per-instance shader parameters (see aircraft_livery.gdshader).

const LiveryShader := preload("res://materials/aircraft_livery.gdshader")
const AircraftLiveryScript := preload("res://scripts/aircraft/aircraft_livery.gd")

## Livery slots, stored in UV.x (see aircraft_livery.gdshader).
enum Slot { FIXED, BODY, BELLY, TAIL, ENGINE, ACCENT }

const FUSELAGE_SIDES := 16
const NACELLE_SIDES := 12
const WHEEL_SIDES := 8
const WING_GREY := Color(0.78, 0.80, 0.83)
const PYLON_GREY := Color(0.70, 0.72, 0.75)
const WINDOW_DARK := Color(0.12, 0.15, 0.20)
const FAN_DARK := Color(0.16, 0.17, 0.19)
const GEAR_GREY := Color(0.62, 0.64, 0.67)
const TYRE_DARK := Color(0.10, 0.10, 0.11)

## Matches the AircraftTypeDef that uses this model.
@export var type_id: StringName

@export_group("Size")
## Nose tip to tail cone, in metres.
@export var length := 37.57
## Ground to fin tip, in metres.
@export var height := 11.76
## Z of the nose tip (negative: ahead of the main gear).
@export var nose_z := -17.65

@export_group("Fuselage")
@export var fuselage_width := 3.95
@export var fuselage_height := 4.14
## Ground to the bottom of the fuselage, in metres.
@export var fuselage_bottom := 1.95
## Cross-sections from nose to tail: x = position along the length (0 to 1),
## y = width and z = height as fractions of the full section, w = centre
## offset in half-heights (positive raises it, for the tail upsweep).
@export var profile := PackedVector4Array()
## The cockpit windows sit between this section and the next one.
@export var cockpit_section := 3
## Windows run between these fractions of the length.
@export var window_range := Vector2(0.15, 0.78)
@export var window_pitch := 0.53

@export_group("Wing")
## Wing sections from the centreline to the tip: x = distance from the
## centreline, y = leading edge Z, z = chord. All in metres.
@export var wing := PackedVector3Array()
## Height of the wing root above the ground, at the centreline.
@export var wing_root_y := 2.57
@export var wing_dihedral_deg := 5.1
## Thickness at root (x) and tip (y).
@export var wing_thickness := Vector2(0.75, 0.18)
## Winglet: x = height, y = outward cant from vertical in degrees,
## z = root chord, w = tip chord.
@export var winglet := Vector4(2.43, 20.0, 1.5, 0.6)
## How far back the winglet tip's leading edge sits behind its root's.
@export var winglet_sweep := 1.2

@export_group("Tail")
## Tailplane sections, like the wing.
@export var stabiliser := PackedVector3Array()
@export var stabiliser_y := 4.7
@export var stabiliser_dihedral_deg := 6.0
## Fin sections from root to tip: x = fraction of the fin height (root at
## fin_root_y, tip at the aircraft height), y = leading edge Z, z = chord.
@export var fin := PackedVector3Array()
@export var fin_root_y := 5.6

@export_group("Engines")
## Distance of each engine from the centreline.
@export var engine_x := 5.75
## Height of the nacelle centre above the ground.
@export var engine_y := 1.6
## Z of the inlet.
@export var engine_front_z := -4.1
@export var nacelle_length := 4.4
@export var nacelle_radius := 1.08
## Height of the lower half as a fraction of the radius (below 1 flattens it).
@export var nacelle_bottom := 1.0

@export_group("Landing gear")
## Z of the nose gear (the main gear is at Z = 0).
@export var nose_gear_z := -12.64
## Distance between the two main gear legs.
@export var main_gear_track := 7.59
@export var main_wheel_radius := 0.585
@export var nose_wheel_radius := 0.38
## Show the gear (hidden in flight).
@export var gear_down := true:
	set(value):
		gear_down = value
		if _gear_mesh != null:
			_gear_mesh.visible = value

static var _material: ShaderMaterial

var _livery: AircraftLiveryScript
var _body_mesh: MeshInstance3D
var _gear_mesh: MeshInstance3D


func _ready() -> void:
	rebuild()


## Rebuilds the meshes from the exported numbers.
func rebuild() -> void:
	if _body_mesh != null:
		_body_mesh.queue_free()
	if _gear_mesh != null:
		_gear_mesh.queue_free()
	var b := _Builder.new()
	_build_fuselage(b)
	_build_wings(b)
	_build_tail(b)
	_build_engines(b)
	_body_mesh = _make_instance("Body", b.commit())
	var g := _Builder.new()
	_build_gear(g)
	_gear_mesh = _make_instance("Gear", g.commit())
	_gear_mesh.visible = gear_down
	if _livery != null:
		apply_livery(_livery)


## Paints the model in this livery. Null goes back to the default colours.
func apply_livery(livery: AircraftLiveryScript) -> void:
	_livery = livery
	var colours := livery if livery != null else AircraftLiveryScript.new()
	for mi: MeshInstance3D in [_body_mesh, _gear_mesh]:
		if mi == null:
			continue
		mi.set_instance_shader_parameter(&"body_colour", colours.body)
		mi.set_instance_shader_parameter(&"belly_colour", colours.belly)
		mi.set_instance_shader_parameter(&"tail_colour", colours.tail)
		mi.set_instance_shader_parameter(&"engine_colour", colours.engines)
		mi.set_instance_shader_parameter(&"accent_colour", colours.accent)


func get_livery() -> AircraftLiveryScript:
	return _livery


## The model's bounds in its own space (body and gear).
func get_bounds() -> AABB:
	var box := _body_mesh.get_aabb() if _body_mesh != null and _body_mesh.mesh != null else AABB()
	if _gear_mesh != null and _gear_mesh.mesh != null:
		box = box.merge(_gear_mesh.get_aabb())
	return box


func get_body_mesh() -> MeshInstance3D:
	return _body_mesh


func get_gear_mesh() -> MeshInstance3D:
	return _gear_mesh


func _make_instance(node_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = LiveryShader
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _material
	# Not owned by the scene, so the generated meshes are never saved into it.
	add_child(mi)
	return mi


# --- Fuselage ---------------------------------------------------------------

func _centre_y() -> float:
	return fuselage_bottom + fuselage_height * 0.5


## The profile at t (0 = nose, 1 = tail) as Vector3(width fraction,
## height fraction, centre offset), interpolated between sections.
func _profile_at(t: float) -> Vector3:
	if profile.is_empty():
		return Vector3(1, 1, 0)
	for i in range(1, profile.size()):
		var a := profile[i - 1]
		var c := profile[i]
		if t <= c.x:
			var f := clampf((t - a.x) / maxf(c.x - a.x, 1e-4), 0.0, 1.0)
			return Vector3(lerpf(a.y, c.y, f), lerpf(a.z, c.z, f), lerpf(a.w, c.w, f))
	var last := profile[profile.size() - 1]
	return Vector3(last.y, last.z, last.w)


func _build_fuselage(b: _Builder) -> void:
	var hw := fuselage_width * 0.5
	var hh := fuselage_height * 0.5
	var cy := _centre_y()
	var rings: Array = []
	var centres: Array = []
	for s in profile:
		var z := nose_z + s.x * length
		var centre := Vector3(0, cy + s.w * hh, z)
		centres.append(centre)
		rings.append(_ellipse_ring(centre, hw * s.y, hh * s.z, FUSELAGE_SIDES, 1.0))
	# How fast each section's radius changes along the length, so normals
	# lean forward on the nose and back on the tail cone.
	var slopes: Array = []
	for i in rings.size():
		var lo := maxi(i - 1, 0)
		var hi := mini(i + 1, rings.size() - 1)
		var dz: float = centres[hi].z - centres[lo].z
		slopes.append((profile[hi].y - profile[lo].y) * hw / maxf(dz, 1e-3))
	for i in range(rings.size() - 1):
		var axis: Vector3 = (centres[i] + centres[i + 1]) * 0.5
		for k in FUSELAGE_SIDES:
			var k2 := (k + 1) % FUSELAGE_SIDES
			var mid_angle := TAU * (k + 0.5) / FUSELAGE_SIDES
			var up := sin(mid_angle)
			var slot := Slot.BELLY if up < -0.4 else Slot.BODY
			var color := Color.WHITE
			if i == cockpit_section and up > 0.4 and up < 0.7:
				slot = Slot.FIXED
				color = WINDOW_DARK
			var p: Array = [rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]]
			var n: Array = [_loft_normal(k, hw, hh, slopes[i]), _loft_normal(k2, hw, hh, slopes[i]),
				_loft_normal(k2, hw, hh, slopes[i + 1]), _loft_normal(k, hw, hh, slopes[i + 1])]
			b.add_quad(p, n, color, slot, axis)
	# Nose and tail caps.
	b.add_fan(rings[0], centres[0] + Vector3(0, 0, -0.05), Color.WHITE, Slot.BODY, Vector3.FORWARD)
	b.add_fan(rings[rings.size() - 1], centres[centres.size() - 1] + Vector3(0, 0, 0.05),
		Color.WHITE, Slot.BODY, Vector3.BACK)
	_build_windows(b, hw, hh, cy)


func _build_windows(b: _Builder, hw: float, hh: float, cy: float) -> void:
	const WINDOW_Y := 0.30
	const WINDOW_W := 0.26
	const WINDOW_H := 0.36
	var start_z := nose_z + window_range.x * length
	var end_z := nose_z + window_range.y * length
	var z := start_z
	while z <= end_z:
		var t := (z - nose_z) / length
		var p := _profile_at(t)
		var y := cy + (p.z + WINDOW_Y * p.y) * hh
		var x := hw * p.x * sqrt(1.0 - WINDOW_Y * WINDOW_Y) + 0.03
		for side in [-1.0, 1.0]:
			var n := Vector3(side, WINDOW_Y, 0).normalized()
			b.add_rect(Vector3(side * x, y, z), Vector3(0, 0, WINDOW_W * 0.5),
				Vector3(0, WINDOW_H * 0.5, 0), n, WINDOW_DARK, Slot.FIXED)
		z += window_pitch
	# Cheatline under the windows, along the straight part of the fuselage.
	const LINE_Y := 0.02
	const LINE_H := 0.32
	var straight := _straight_range()
	var line_x := hw * sqrt(1.0 - LINE_Y * LINE_Y) + 0.02
	for side in [-1.0, 1.0]:
		var centre := Vector3(side * line_x, cy + hh * LINE_Y, (straight.x + straight.y) * 0.5)
		b.add_rect(centre, Vector3(0, 0, (straight.y - straight.x) * 0.5),
			Vector3(0, LINE_H * 0.5, 0), Vector3(side, 0, 0), Color.WHITE, Slot.ACCENT)


## Z range where the fuselage is at full width.
func _straight_range() -> Vector2:
	var lo := INF
	var hi := -INF
	for s in profile:
		if s.y >= 0.999:
			lo = minf(lo, nose_z + s.x * length)
			hi = maxf(hi, nose_z + s.x * length)
	return Vector2(lo, hi) if lo < hi else Vector2(nose_z, nose_z + length)


## Points round an ellipse in the XY plane. bottom scales the lower half.
func _ellipse_ring(centre: Vector3, rx: float, ry: float, sides: int, bottom: float) -> Array:
	var ring := []
	for k in sides:
		var a := TAU * k / sides
		var s := sin(a)
		ring.append(centre + Vector3(cos(a) * rx, s * ry * (bottom if s < 0.0 else 1.0), 0))
	return ring


## Normal of a lofted surface whose radius grows by `slope` per metre along +Z.
func _loft_normal(k: int, rx: float, ry: float, slope: float) -> Vector3:
	var n := _ellipse_normal(k, rx, ry)
	return Vector3(n.x, n.y, -slope).normalized()


func _ellipse_normal(k: int, rx: float, ry: float, sides := FUSELAGE_SIDES) -> Vector3:
	var a := TAU * k / sides
	return Vector3(cos(a) / maxf(rx, 1e-3), sin(a) / maxf(ry, 1e-3), 0).normalized()


# --- Wings and tail -----------------------------------------------------------

func _wing_y_at(x: float) -> float:
	return wing_root_y + absf(x) * tan(deg_to_rad(wing_dihedral_deg))


## Leading edge Z and chord of the wing at distance x from the centreline.
func _wing_at(x: float) -> Vector2:
	for i in range(1, wing.size()):
		var a := wing[i - 1]
		var c := wing[i]
		if x <= c.x:
			var f := clampf((x - a.x) / maxf(c.x - a.x, 1e-4), 0.0, 1.0)
			return Vector2(lerpf(a.y, c.y, f), lerpf(a.z, c.z, f))
	var last := wing[wing.size() - 1]
	return Vector2(last.y, last.z)


func _build_wings(b: _Builder) -> void:
	if wing.size() < 2:
		return
	var tip_x := wing[wing.size() - 1].x
	var cant := deg_to_rad(winglet.y)
	for side in [-1.0, 1.0]:
		var stations := []
		for s in wing:
			var f := s.x / tip_x
			stations.append([Vector3(side * s.x, _wing_y_at(s.x), s.y), s.z,
				lerpf(wing_thickness.x, wing_thickness.y, f)])
		b.add_panel(stations, Vector3.UP, WING_GREY, Slot.FIXED)
		# Winglet, rising from the tip.
		var tip: Array = stations[stations.size() - 1]
		var root_le: Vector3 = tip[0] + Vector3(0, 0, (tip[1] - winglet.z) * 0.5)
		var tip_le := root_le + Vector3(side * sin(cant) * winglet.x, cos(cant) * winglet.x, winglet_sweep)
		var across := Vector3(side * cos(cant), -sin(cant), 0)
		b.add_panel([[root_le, winglet.z, wing_thickness.y], [tip_le, winglet.w, 0.08]],
			across, Color.WHITE, Slot.ACCENT)


func _build_tail(b: _Builder) -> void:
	if stabiliser.size() >= 2:
		var tip_x := stabiliser[stabiliser.size() - 1].x
		var dihedral := tan(deg_to_rad(stabiliser_dihedral_deg))
		for side in [-1.0, 1.0]:
			var stations := []
			for s in stabiliser:
				stations.append([Vector3(side * s.x, stabiliser_y + s.x * dihedral, s.y), s.z,
					lerpf(0.4, 0.12, s.x / tip_x)])
			b.add_panel(stations, Vector3.UP, Color.WHITE, Slot.BODY)
	if fin.size() >= 2:
		var fin_height := height - fin_root_y
		var stations := []
		for s in fin:
			stations.append([Vector3(0, fin_root_y + s.x * fin_height, s.y), s.z, lerpf(0.45, 0.15, s.x)])
		b.add_panel(stations, Vector3.RIGHT, Color.WHITE, Slot.TAIL)


# --- Engines ------------------------------------------------------------------

func _build_engines(b: _Builder) -> void:
	# x = position along the nacelle, y = radius fraction.
	var shape := [Vector2(0.0, 0.86), Vector2(0.06, 1.0), Vector2(0.45, 0.98),
		Vector2(0.8, 0.8), Vector2(1.0, 0.55)]
	for side in [-1.0, 1.0]:
		var x: float = side * engine_x
		var rings: Array = []
		var centres: Array = []
		for s: Vector2 in shape:
			var centre := Vector3(x, engine_y, engine_front_z + s.x * nacelle_length)
			centres.append(centre)
			rings.append(_ellipse_ring(centre, nacelle_radius * s.y, nacelle_radius * s.y,
				NACELLE_SIDES, nacelle_bottom))
		for i in range(rings.size() - 1):
			var axis: Vector3 = (centres[i] + centres[i + 1]) * 0.5
			for k in NACELLE_SIDES:
				var k2 := (k + 1) % NACELLE_SIDES
				var nk := _ellipse_normal(k, 1.0, nacelle_bottom if sin(TAU * k / NACELLE_SIDES) < 0 else 1.0, NACELLE_SIDES)
				var nk2 := _ellipse_normal(k2, 1.0, nacelle_bottom if sin(TAU * k2 / NACELLE_SIDES) < 0 else 1.0, NACELLE_SIDES)
				b.add_quad([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]],
					[nk, nk2, nk2, nk], Color.WHITE, Slot.ENGINE, axis)
		# Fan face, set back into the inlet, and the exhaust.
		b.add_fan(rings[0], centres[0] + Vector3(0, 0, 0.5), FAN_DARK, Slot.FIXED, Vector3.FORWARD)
		b.add_fan(rings[rings.size() - 1], centres[centres.size() - 1] + Vector3(0, 0, 0.6),
			FAN_DARK, Slot.FIXED, Vector3.BACK)
		# Pylon from the top of the nacelle up into the wing.
		var wing_here := _wing_at(engine_x)
		var top := engine_y + nacelle_radius * 0.9
		var pylon_le_z := engine_front_z + nacelle_length * 0.25
		var pylon_te_z := maxf(engine_front_z + nacelle_length, wing_here.x + wing_here.y * 0.6)
		var wing_bottom := _wing_y_at(engine_x)
		b.add_panel([[Vector3(x, top, pylon_le_z), pylon_te_z - pylon_le_z, 0.35],
			[Vector3(x, wing_bottom, wing_here.x), wing_here.y * 0.6, 0.3]],
			Vector3.RIGHT, PYLON_GREY, Slot.FIXED)


# --- Landing gear ---------------------------------------------------------------

func _build_gear(b: _Builder) -> void:
	# Nose gear: one leg, two wheels.
	var belly := _belly_y((nose_gear_z - nose_z) / length)
	_add_leg(b, Vector3(0, nose_wheel_radius, nose_gear_z), belly, 0.16)
	for wx in [-0.24, 0.24]:
		_add_wheel(b, Vector3(wx, nose_wheel_radius, nose_gear_z), nose_wheel_radius, 0.22)
	# Main gear: a leg under each wing, two wheels each.
	for side in [-1.0, 1.0]:
		var x: float = side * main_gear_track * 0.5
		_add_leg(b, Vector3(x, main_wheel_radius, 0), _wing_y_at(x), 0.24)
		for wx in [-0.42, 0.42]:
			_add_wheel(b, Vector3(x + wx, main_wheel_radius, 0), main_wheel_radius, 0.34)


## Height of the bottom of the fuselage at t (0 = nose, 1 = tail).
func _belly_y(t: float) -> float:
	var p := _profile_at(t)
	return _centre_y() + fuselage_height * 0.5 * (p.z - p.y)


func _add_leg(b: _Builder, axle: Vector3, top_y: float, thickness: float) -> void:
	var h := thickness * 0.5
	b.add_box(Vector3(axle.x - h, axle.y, axle.z - h), Vector3(axle.x + h, top_y, axle.z + h), GEAR_GREY)
	# Axle across the wheels.
	b.add_box(Vector3(axle.x - 0.5, axle.y - 0.06, axle.z - 0.06),
		Vector3(axle.x + 0.5, axle.y + 0.06, axle.z + 0.06), GEAR_GREY)


func _add_wheel(b: _Builder, centre: Vector3, radius: float, width: float) -> void:
	var left := []
	var right := []
	for k in WHEEL_SIDES:
		var a := TAU * k / WHEEL_SIDES
		var offset := Vector3(0, sin(a) * radius, cos(a) * radius)
		left.append(centre + offset + Vector3(-width * 0.5, 0, 0))
		right.append(centre + offset + Vector3(width * 0.5, 0, 0))
	for k in WHEEL_SIDES:
		var k2 := (k + 1) % WHEEL_SIDES
		var mid_a := TAU * (k + 0.5) / WHEEL_SIDES
		var n := Vector3(0, sin(mid_a), cos(mid_a))
		b.add_quad([left[k], left[k2], right[k2], right[k]], [n, n, n, n], TYRE_DARK, Slot.FIXED, centre)
	b.add_fan(left, centre + Vector3(-width * 0.5, 0, 0), GEAR_GREY, Slot.FIXED, Vector3.LEFT)
	b.add_fan(right, centre + Vector3(width * 0.5, 0, 0), GEAR_GREY, Slot.FIXED, Vector3.RIGHT)


# --- Mesh builder -------------------------------------------------------------

## Collects triangles with normals, vertex colours and livery slots.
## Every face is wound to face away from a hint point or along a hint
## direction, so shapes can be listed in either order and mirrored freely.
class _Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func _add_vertex(p: Vector3, n: Vector3, color: Color, slot: int) -> int:
		verts.append(p)
		normals.append(n)
		# The shader reads COLOR as linear, like its source_color uniforms.
		colors.append(color.srgb_to_linear())
		uvs.append(Vector2(slot, 0))
		return verts.size() - 1

	## Adds a triangle facing along `facing` (a direction).
	func add_tri(p: Array, n: Array, color: Color, slot: int, facing: Vector3) -> void:
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		var c: Vector3 = p[2]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() < 1e-10:
			return
		var i0 := _add_vertex(p[0], n[0], color, slot)
		var i1 := _add_vertex(p[1], n[1], color, slot)
		var i2 := _add_vertex(p[2], n[2], color, slot)
		# Godot treats clockwise triangles as front faces.
		if cross.dot(facing) < 0.0:
			indices.append_array([i0, i1, i2])
		else:
			indices.append_array([i0, i2, i1])

	## Adds a quad facing away from the point `inside`. Null normals = flat.
	func add_quad(p: Array, n: Array, color: Color, slot: int, inside: Vector3) -> void:
		var centre: Vector3 = (p[0] + p[1] + p[2] + p[3]) * 0.25
		var facing := centre - inside
		if n.is_empty():
			var flat: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
			if flat.length_squared() < 1e-10:
				flat = (p[2] - p[0]).cross(p[3] - p[0])
			flat = flat.normalized()
			if flat.dot(facing) < 0.0:
				flat = -flat
			n = [flat, flat, flat, flat]
		add_tri([p[0], p[1], p[2]], [n[0], n[1], n[2]], color, slot, facing)
		add_tri([p[0], p[2], p[3]], [n[0], n[2], n[3]], color, slot, facing)

	## Closes a ring of points with a fan to `tip`, facing along `facing`.
	func add_fan(ring: Array, tip: Vector3, color: Color, slot: int, facing: Vector3) -> void:
		for k in ring.size():
			var a: Vector3 = ring[k]
			var c: Vector3 = ring[(k + 1) % ring.size()]
			var n := (c - a).cross(tip - a).normalized()
			if n.dot(facing) < 0.0:
				n = -n
			add_tri([a, c, tip], [n, n, n], color, slot, facing)

	## Adds a flat rectangle around `centre` with half-extents `u` and `v`.
	func add_rect(centre: Vector3, u: Vector3, v: Vector3, n: Vector3, color: Color, slot: int) -> void:
		var p := [centre - u - v, centre + u - v, centre + u + v, centre - u + v]
		add_quad(p, [n, n, n, n], color, slot, centre - n)

	func add_box(lo: Vector3, hi: Vector3, color: Color) -> void:
		var c := (lo + hi) * 0.5
		var x0 := lo.x
		var x1 := hi.x
		var y0 := lo.y
		var y1 := hi.y
		var z0 := lo.z
		var z1 := hi.z
		for face in [
				[Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)],
				[Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)],
				[Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)],
				[Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)],
				[Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0)],
				[Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)]]:
			add_quad(face, [], color, 0, c)

	## Adds a wing-like panel through stations [leading edge, chord, thickness],
	## with a diamond section: thickness runs along `thick_axis`, chord along +Z.
	func add_panel(stations: Array, thick_axis: Vector3, color: Color, slot: int) -> void:
		var sections := []
		for s: Array in stations:
			var le: Vector3 = s[0]
			var chord: float = s[1]
			var half: Vector3 = thick_axis * (s[2] as float) * 0.5
			var peak := le + Vector3(0, 0, chord * 0.35)
			sections.append([le, peak + half, le + Vector3(0, 0, chord), peak - half])
		for i in range(sections.size() - 1):
			var a: Array = sections[i]
			var c: Array = sections[i + 1]
			for k in 4:
				var k2 := (k + 1) % 4
				# Inside point: middle of the chord lines at both ends.
				var inside: Vector3 = (a[0] + a[2] + c[0] + c[2]) * 0.25
				add_quad([a[k], a[k2], c[k2], c[k]], [], color, slot, inside)
		# Tip cap.
		var first: Array = sections[0]
		var last: Array = sections[sections.size() - 1]
		var out: Vector3 = (last[0] - first[0]).normalized()
		var chord_line: Vector3 = last[2] - last[0]
		var thickness_line: Vector3 = last[1] - last[3]
		var flat := chord_line.cross(thickness_line).normalized()
		if flat.dot(out) < 0.0:
			flat = -flat
		add_tri([last[0], last[1], last[2]], [flat, flat, flat], color, slot, out)
		add_tri([last[0], last[2], last[3]], [flat, flat, flat], color, slot, out)

	func commit() -> ArrayMesh:
		if verts.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
