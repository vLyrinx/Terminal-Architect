extends Node3D
## Automatic test for zones (checklist step 10).
## Run this scene on its own (F6). It lays floor and paints zones through the
## same calls the tools use, checks the stored zones and the overlay texture,
## prints PASS or FAIL for each check, then waits for you to close the window.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const LANDSIDE := TerminalZonesScript.Zone.LANDSIDE
const SECURITY := TerminalZonesScript.Zone.SECURITY
const AIRSIDE := TerminalZonesScript.Zone.AIRSIDE
const NONE := TerminalZonesScript.Zone.NONE

var _failures := 0
var _floor: TerminalFloorScript
var _zones: TerminalZonesScript


func _ready() -> void:
	print("TEST START | zones")
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_zones = TerminalZonesScript.new()
	_zones.terminal_floor = _floor
	add_child(_zones)

	_expect("overlay starts hidden", not _zones.is_overlay_shown())
	_expect("no zones without floor", _zones.paint_rect(Rect2i(10, 10, 3, 3), LANDSIDE) == 0)

	_floor.set_rect(Rect2i(10, 10, 10, 6), true)
	_expect("paint 3 x 3 landside on floor", _zones.paint_rect(Rect2i(10, 10, 3, 3), LANDSIDE) == 9)
	_expect("tile is landside", _zones.get_zone(Vector2i(11, 11)) == LANDSIDE)
	_expect("painting the same again changes nothing", _zones.paint_rect(Rect2i(10, 10, 3, 3), LANDSIDE) == 0)
	_expect("count for a rectangle half off the floor is 4 of 9",
		_zones.count_paint_changes(Rect2i(18, 14, 3, 3), AIRSIDE) == 4)
	_expect("rectangle half off the floor paints only floor tiles (4 of 9)",
		_zones.paint_rect(Rect2i(18, 14, 3, 3), AIRSIDE) == 4)
	_expect("security over part of landside changes 3", _zones.paint_rect(Rect2i(12, 10, 1, 3), SECURITY) == 3)
	_expect("counts: 6 landside, 3 security, 4 airside",
		_zones.count_zone(LANDSIDE) == 6 and _zones.count_zone(SECURITY) == 3 and _zones.count_zone(AIRSIDE) == 4)
	_expect("overlay texture matches the zones", _texture_zone(Vector2i(12, 11)) == SECURITY
		and _texture_zone(Vector2i(10, 10)) == LANDSIDE and _texture_zone(Vector2i(15, 12)) == NONE)

	_expect("erase 2 x 2", _zones.paint_rect(Rect2i(10, 10, 2, 2), NONE) == 4)
	_expect("erased tile has no zone", _zones.get_zone(Vector2i(10, 10)) == NONE)

	_floor.set_rect(Rect2i(18, 14, 2, 2), false)
	_expect("removing floor clears its zones", _zones.count_zone(AIRSIDE) == 0)
	_expect("and the overlay texture", _texture_zone(Vector2i(19, 15)) == NONE)

	_expect("outside the plot is no zone", _zones.get_zone(Vector2i(-1, 5)) == NONE)

	_zones.set_overlay_visible(true)
	_expect("Z toggle shows the overlay", _zones.is_overlay_shown())
	_zones.set_overlay_visible(false)
	_zones.set_overlay_forced(true)
	_expect("an active zone brush shows it too", _zones.is_overlay_shown())
	_zones.set_overlay_forced(false)
	_expect("and hides it again when done", not _zones.is_overlay_shown())

	# Leave a small sample on screen: one strip of each zone, overlay on.
	_floor.set_rect(Rect2i(10, 10, 10, 6), true)
	_zones.paint_rect(Rect2i(10, 10, 4, 6), LANDSIDE)
	_zones.paint_rect(Rect2i(14, 10, 2, 6), SECURITY)
	_zones.paint_rect(Rect2i(16, 10, 4, 6), AIRSIDE)
	_zones.set_overlay_visible(true)
	_add_view(BuildGrid.tile_corner_to_world(Vector2i(15, 13)))
	await get_tree().process_frame
	await get_tree().process_frame  # the overlay shader compiles when first drawn

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


## Camera and sun looking down at a point, so the sample can be seen.
func _add_view(target: Vector3) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = target + Vector3(0, 12, 10)
	camera.look_at(target)
	camera.current = true


func _texture_zone(tile: Vector2i) -> int:
	var image := _zones.get_overlay_texture().get_image()
	return roundi(image.get_pixel(tile.x, tile.y).r * 255.0)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])
