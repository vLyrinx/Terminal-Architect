class_name AircraftLivery
extends Resource
## Livery colours for an aircraft model (checklist step 19). Airlines (step 21)
## hold one of these; AircraftModel.apply_livery() paints a model with it.

## Upper fuselage.
@export var body := Color(0.96, 0.96, 0.95)
## Lower fuselage.
@export var belly := Color(0.80, 0.82, 0.85)
## Fin.
@export var tail := Color(0.15, 0.62, 0.60)
## Engine nacelles.
@export var engines := Color(0.90, 0.91, 0.92)
## Cheatline along the windows and the winglets.
@export var accent := Color(0.15, 0.62, 0.60)


static func make(body_c: Color, belly_c: Color, tail_c: Color, engines_c: Color, accent_c: Color) -> AircraftLivery:
	var l := AircraftLivery.new()
	l.body = body_c
	l.belly = belly_c
	l.tail = tail_c
	l.engines = engines_c
	l.accent = accent_c
	return l
