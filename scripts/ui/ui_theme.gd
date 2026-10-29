extends RefCounted
## Game UI theme (checklist step 15): flat colours, no textures or shaders, so
## it stays cheap on low-end PCs. Sizes are for the 1152 x 648 base window; the
## canvas_items stretch mode scales them up on bigger screens.

const BAR := Color("1f2937")
const PANEL := Color("273445")
const BUTTON := Color("344256")
const BUTTON_HOVER := Color("41536b")
const ACCENT := Color("3d8bfd")
const ACCENT_HOVER := Color("5b9dff")
const TEXT := Color("eef2f7")
const TEXT_DIM := Color("9fb0c3")
const TEXT_DISABLED := Color("5f6f83")
const MONEY := Color("6ee7a0")
const WARNING := Color("fbbf24")
const DANGER := Color("f87171")
const DANGER_BG := Color("b83a3a")

const FONT_SIZE := 14
const FONT_SIZE_SMALL := 12
const FONT_SIZE_LARGE := 18
const RADIUS := 6


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE

	theme.set_color("font_color", "Label", TEXT)

	theme.set_stylebox("panel", "PanelContainer", panel_style(PANEL))
	theme.set_stylebox("panel", "TooltipPanel", panel_style(BAR, 4, 8, 5))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", FONT_SIZE_SMALL)

	theme.set_stylebox("normal", "Button", flat(BUTTON))
	theme.set_stylebox("hover", "Button", flat(BUTTON_HOVER))
	theme.set_stylebox("pressed", "Button", flat(ACCENT))
	theme.set_stylebox("hover_pressed", "Button", flat(ACCENT_HOVER))
	theme.set_stylebox("disabled", "Button", flat(Color(BUTTON, 0.45)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	theme.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.3))
	return theme


static func flat(color: Color, radius := RADIUS, margin_h := 10, margin_v := 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	return style


static func panel_style(color: Color, radius := RADIUS, margin_h := 10, margin_v := 8) -> StyleBoxFlat:
	return flat(color, radius, margin_h, margin_v)


## A label with the given size and colour that never takes the mouse.
static func label(text := "", font_size := FONT_SIZE, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
