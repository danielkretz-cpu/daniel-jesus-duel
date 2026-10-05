extends RefCounted
## Shared, physical-pixel menu styling. Game-world scaling never shrinks touch targets.
const INK := Color("111724")
const PANEL := Color("202a3b")
const CREAM := Color("f5f5ee")
const MUTED := Color("b7c5d5")
const GOLD := Color("ffd16d")
const MINT := Color("98e5c0")

static func style(color: Color, radius: int = 16, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = load("res://assets/Regular.ttf")
	result.default_font_size = 17
	result.set_color("font_color", "Label", CREAM)
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", CREAM)
	result.set_color("font_disabled_color", "Button", Color("8894a8"))
	result.set_stylebox("normal", "Button", style(Color("354760"), 12))
	result.set_stylebox("hover", "Button", style(Color("415b7b"), 12))
	result.set_stylebox("pressed", "Button", style(Color("273953"), 12))
	result.set_stylebox("disabled", "Button", style(Color("293445"), 12))
	result.set_stylebox("focus", "Button", style(Color.TRANSPARENT, 12, GOLD))
	result.set_stylebox("normal", "LineEdit", style(INK, 10, Color("52647b")))
	result.set_stylebox("read_only", "LineEdit", style(INK, 10, Color("52647b")))
	result.set_stylebox("focus", "LineEdit", style(Color.TRANSPARENT, 10, GOLD))
	result.set_color("font_color", "LineEdit", CREAM)
	result.set_color("font_uneditable_color", "LineEdit", CREAM)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("caret_color", "LineEdit", GOLD)
	return result

static func label(parent: Node, text: String, font_size: int = 17, color: Color = CREAM) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

static func button(parent: Node, text: String, primary: bool = false) -> Button:
	var result := Button.new()
	result.text = text
	result.clip_text = true
	result.tooltip_text = text
	result.custom_minimum_size.y = 48
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_size_override("font_size", 17)
	if primary:
		result.add_theme_stylebox_override("normal", style(GOLD, 12))
		result.add_theme_stylebox_override("hover", style(GOLD.lightened(0.12), 12))
		result.add_theme_stylebox_override("pressed", style(GOLD.darkened(0.13), 12))
		for property in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.add_theme_color_override(property, INK)
	parent.add_child(result)
	return result

static func field(parent: Node, placeholder: String, max_chars: int = 0) -> LineEdit:
	var result := LineEdit.new()
	result.placeholder_text = placeholder
	result.max_length = max_chars
	result.custom_minimum_size = Vector2(0, 48)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.expand_to_text_length = false
	result.virtual_keyboard_enabled = true
	parent.add_child(result)
	return result
