class_name UIUtil
extends RefCounted
## Small shared helpers for building touch-friendly UI purely from code.

static func make_button(text: String, min_h: int = 56, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	return b

static func make_label(text: String, font_size: int = 22, color: Color = Color("#FFF6E3")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_title(text: String, font_size: int = 40) -> Label:
	var l := make_label(text, font_size, Color("#D9A441"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.16, 0.22, 0.92)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(18)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color("#D9A441")
	p.add_theme_stylebox_override("panel", style)
	return p

static func make_bg(texture_path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(texture_path)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

static func apply_rtl(control: Control) -> void:
	control.layout_direction = Control.LAYOUT_DIRECTION_LOCALE
