extends RefCounted
## Build menu categories (checklist step 15), in the order they appear on the
## bottom bar. Build tools and object data files name one of these IDs in
## their menu_category; the menu fills each category from them, so new tools
## (runways, taxiways, stands, belts) show up without menu changes.
## A category with no items is greyed out.

const LIST := [
	{"id": "structures", "name": "Structures", "icon": preload("res://ui/icons/cat_structures.svg")},
	{"id": "zones", "name": "Zones", "icon": preload("res://ui/icons/cat_zones.svg")},
	{"id": "terminal", "name": "Terminal", "icon": preload("res://ui/icons/cat_terminal.svg")},
	{"id": "airside", "name": "Airside", "icon": preload("res://ui/icons/cat_airside.svg")},
	{"id": "demolish", "name": "Demolish", "icon": preload("res://ui/icons/cat_demolish.svg")},
]


static func has(id: String) -> bool:
	return LIST.any(func(c: Dictionary) -> bool: return c.id == id)
