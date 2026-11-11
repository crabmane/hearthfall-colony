class_name HFUI
extends RefCounted

const INK := Color("#101713")
const BACKDROP := Color("#0c120f")
const PANEL := Color("#18241d")
const PANEL_LIGHT := Color("#213127")
const PANEL_WARM := Color("#2b241a")
const BORDER := Color("#50634c")
const BORDER_SOFT := Color("#33443a")
const PARCHMENT := Color("#f1e4c8")
const MUTED := Color("#a9b5a1")
const SUBTLE := Color("#748372")
const MOSS := Color("#a8c56f")
const AMBER := Color("#efb35a")
const AMBER_LIGHT := Color("#ffd48a")
const RUST := Color("#d47152")
const RED := Color("#e06955")
const BLUE := Color("#7fa9b8")
const VIOLET := Color("#b59ac8")
const GREEN := Color("#82b76b")
const SHADOW := Color(0.0, 0.0, 0.0, 0.42)

const FONT_BODY_PATH := "res://assets/template/fonts/ui_regular.tres"
const FONT_MEDIUM_PATH := "res://assets/template/fonts/ui_medium.tres"
const FONT_BOLD_PATH := "res://assets/template/fonts/ui_bold.tres"
const FONT_DISPLAY_PATH := "res://assets/template/fonts/display/generic_heading.tres"
const FONT_TITLE_PATH := "res://assets/template/fonts/display/generic_title.tres"

static var _body_font: Font
static var _medium_font: Font
static var _bold_font: Font
static var _display_font: Font
static var _title_font: Font

static func body_font() -> Font:
	if _body_font == null:
		_body_font = load(FONT_BODY_PATH) as Font
	return _body_font

static func medium_font() -> Font:
	if _medium_font == null:
		_medium_font = load(FONT_MEDIUM_PATH) as Font
	return _medium_font

static func bold_font() -> Font:
	if _bold_font == null:
		_bold_font = load(FONT_BOLD_PATH) as Font
	return _bold_font

static func display_font() -> Font:
	if _display_font == null:
		_display_font = load(FONT_DISPLAY_PATH) as Font
	return _display_font

static func title_font() -> Font:
	if _title_font == null:
		_title_font = load(FONT_TITLE_PATH) as Font
	return _title_font

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.25))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_stylebox("normal", "Button", style_box(PANEL_LIGHT, BORDER, 10.0, 2, 2))
	theme.set_stylebox("hover", "Button", style_box(Color("#2c4031"), AMBER, 10.0, 2, 2))
	theme.set_stylebox("pressed", "Button", style_box(Color("#4a3721"), AMBER_LIGHT, 10.0, 2, 2))
	theme.set_stylebox("focus", "Button", focus_box(AMBER))
	theme.set_stylebox("disabled", "Button", style_box(Color("#141c17"), BORDER_SOFT, 10.0, 1, 1))
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", AMBER_LIGHT)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", AMBER_LIGHT)
	theme.set_color("font_disabled_color", "Button", SUBTLE)
	theme.set_font("font", "Button", medium_font())
	theme.set_font_size("font_size", "Button", 14)
	theme.set_color("font_color", "TooltipLabel", PARCHMENT)
	theme.set_stylebox("panel", "TooltipPanel", style_box(PANEL_WARM, AMBER, 8.0, 1, 1))
	return theme

static func style_box(bg: Color, border: Color, pad: float = 10.0, border_width: int = 2, shadow: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_content_margin_all(pad)
	box.corner_radius_top_left = 0
	box.corner_radius_top_right = 0
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	box.shadow_color = SHADOW
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, maxf(0.0, float(shadow)))
	box.anti_aliasing = false
	return box

static func focus_box(color: Color) -> StyleBoxFlat:
	var box := style_box(Color(0.0, 0.0, 0.0, 0.0), color, 10.0, 2, 0)
	box.expand_margin_left = 2.0
	box.expand_margin_right = 2.0
	box.expand_margin_top = 2.0
	box.expand_margin_bottom = 2.0
	return box

static func panel(bg: Color = PANEL, border: Color = BORDER, pad: float = 12.0, border_width: int = 2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style_box(bg, border, pad, border_width, 2))
	return p

static func label(text: String, font_size: int = 15, color: Color = PARCHMENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.28))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

static func medium_label(text: String, font_size: int = 15, color: Color = PARCHMENT) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_font_override("font", medium_font())
	return l

static func display_label(text: String, font_size: int = 26, color: Color = PARCHMENT) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_font_override("font", display_font())
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

static func title_label(text: String, font_size: int = 48, color: Color = PARCHMENT) -> Label:
	var l := display_label(text, font_size, color)
	l.add_theme_font_override("font", title_font())
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l

static func eyebrow(text: String, color: Color = AMBER) -> Label:
	var l := medium_label(text.to_upper(), 11, color)
	l.add_theme_constant_override("letter_spacing", 2)
	return l

static func button(text: String, width: float = 0.0, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 36.0)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", medium_font())
	b.add_theme_stylebox_override("normal", style_box(PANEL_LIGHT, BORDER, 10.0, 2, 2))
	b.add_theme_stylebox_override("hover", style_box(Color("#2c4031"), AMBER, 10.0, 2, 2))
	b.add_theme_stylebox_override("pressed", style_box(Color("#4a3721"), AMBER_LIGHT, 10.0, 2, 2))
	b.add_theme_stylebox_override("focus", focus_box(AMBER))
	b.add_theme_color_override("font_color", PARCHMENT)
	b.add_theme_color_override("font_hover_color", AMBER_LIGHT)
	b.add_theme_color_override("font_pressed_color", INK)
	return b

static func primary_button(text: String, width: float = 0.0) -> Button:
	var b := button(text, width)
	b.add_theme_stylebox_override("normal", style_box(Color("#6f5b32"), AMBER, 11.0, 2, 2))
	b.add_theme_stylebox_override("hover", style_box(Color("#8b713c"), AMBER_LIGHT, 11.0, 2, 3))
	b.add_theme_stylebox_override("pressed", style_box(AMBER_LIGHT, PARCHMENT, 11.0, 2, 1))
	b.add_theme_color_override("font_color", PARCHMENT)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	return b

static func danger_button(text: String, width: float = 0.0) -> Button:
	var b := button(text, width)
	b.add_theme_stylebox_override("normal", style_box(Color("#40251f"), RUST, 10.0, 2, 2))
	b.add_theme_stylebox_override("hover", style_box(Color("#5b3026"), RED, 10.0, 2, 2))
	b.add_theme_color_override("font_color", Color("#f4c4b8"))
	return b

static func icon_button(texture: Texture2D, text: String, width: float = 0.0) -> Button:
	var b := button(text, width)
	b.icon = texture
	b.add_theme_constant_override("h_separation", 8)
	b.add_theme_color_override("icon_normal_color", PARCHMENT)
	b.add_theme_color_override("icon_hover_color", AMBER_LIGHT)
	b.expand_icon = true
	b.custom_minimum_size.y = 38.0
	return b

static func full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func vbox(separation: int = 6) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

static func hbox(separation: int = 6) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func h_spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func texture_rect(texture: Texture2D, min_size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.custom_minimum_size = min_size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func bar(value: float, max_value: float, color: Color, width: float = 160.0, height: float = 10.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(0.001, max_value)
	bar.value = clampf(value, 0.0, max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#0d1511")
	bg.border_color = Color("#2e3d32")
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 0
	fill.corner_radius_top_right = 0
	fill.corner_radius_bottom_left = 0
	fill.corner_radius_bottom_right = 0
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

static func mood_color(mood: float) -> Color:
	if mood >= 70.0:
		return GREEN
	if mood >= 45.0:
		return AMBER
	if mood >= 25.0:
		return RUST
	return RED

static func need_color(value: float) -> Color:
	if value >= 65.0:
		return GREEN
	if value >= 35.0:
		return AMBER
	return RED

static func job_color(job_id: String) -> Color:
	match job_id:
		"fire":
			return RED
		"care":
			return Color("#d98b9d")
		"build":
			return AMBER
		"farm":
			return GREEN
		"cook":
			return Color("#e6a46d")
		"gather":
			return MOSS
		"craft":
			return BLUE
		"haul":
			return Color("#c0a77b")
		"hunt":
			return RUST
		"study":
			return VIOLET
	return PARCHMENT
