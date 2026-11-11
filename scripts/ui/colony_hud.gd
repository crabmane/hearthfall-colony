class_name ColonyHUD
extends Control

signal build_requested(key: String)
signal order_requested(tool: String)
signal herb_order_requested
signal cancel_requested
signal load_requested
signal new_colony_requested
signal continue_requested
signal title_requested
signal inspector_closed
signal colonist_selected(id: int)
signal priority_changed(colonist_id: int, job_id: String, value: int)
signal center_on_building_requested(building_id: int)
signal cloud_load_ready(data: String)

var sim: ColonySim
var _refresh_accum: float = 0.0
var _connected_sims: Array = []

# Title
var title_screen: Control
var title_continue: Button
var title_new: Button
var title_help: Button

# Game interface
var game_ui: Control
var top_bar: PanelContainer
var resource_values: Dictionary = {}
var date_label: Label
var clock_label: Label
var weather_label: Label
var speed_buttons: Dictionary = {}
var menu_button: Button
var left_rail: PanelContainer
var rail_buttons: Dictionary = {}
var objectives_panel: PanelContainer
var objective_rows: Dictionary = {}
var objectives_body: VBoxContainer
var objectives_collapsed: bool = false
var alerts_box: VBoxContainer
var alert_signature: String = ""
var hover_bar: PanelContainer
var hover_label: Label
var toast_box: VBoxContainer
var log_panel: PanelContainer
var log_scroll: ScrollContainer
var log_box: VBoxContainer
var log_signature: String = ""

# Build menu
var build_panel: PanelContainer
var build_category: String = "shelter"
var build_category_buttons: Dictionary = {}
var build_cards_box: HBoxContainer
var build_cards: Dictionary = {}
var build_info_label: Label
var selected_build_key: String = ""
var tool_mode: String = ""
var tool_key: String = ""
var hover_text: String = ""

# Orders
var orders_panel: PanelContainer
var order_buttons: Dictionary = {}
var orders_active_box: VBoxContainer
var orders_signature: String = ""

# Inspector
var inspector_panel: PanelContainer
var inspector_scroll: ScrollContainer
var inspector_body: VBoxContainer
var inspector_mode: String = ""
var inspector_colonist_id: int = -1
var inspector_building_id: int = -1
var inspector_refs: Dictionary = {}
var people_signature: String = ""

# Modals
var work_overlay: Control
var work_body: VBoxContainer
var help_overlay: Control
var pause_overlay: Control
var confirm_overlay: Control
var confirm_text: Label
var confirm_yes: Button
var confirm_callback: Callable
var game_over_overlay: Control
var game_over_body: VBoxContainer
var _speed_before_pause: int = 1
var _help_return_to_pause: bool = false
var cloud_overlay: Control
var cloud_body: VBoxContainer
var cloud_scroll_box: VBoxContainer
var cloud_status_label: Label
var cloud_slots: Dictionary = {}
var cloud_saves_loaded: bool = false
var cloud_board_id: String = "survival-days-v1"
var cloud_board_data: Dictionary = {}
var cloud_board_loading: bool = false
var cloud_message: String = ""
var _cloud_return_to_pause: bool = false
var advisor_overlay: Control
var advisor_body: VBoxContainer

func _ready() -> void:
	theme = HFUI.make_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	HFUI.full_rect(self)
	_build_title_screen()
	_build_game_ui()
	_build_overlays()
	if not CloudServices.session_changed.is_connected(_on_cloud_session_changed):
		CloudServices.session_changed.connect(_on_cloud_session_changed)
	if not CloudServices.publish_finished.is_connected(_on_cloud_publish_finished):
		CloudServices.publish_finished.connect(_on_cloud_publish_finished)
	show_title(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_hud()

func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= 0.2:
		_refresh_accum = 0.0
		if game_ui != null and game_ui.visible and sim != null:
			_refresh_game()
	if hover_bar != null:
		_update_hover_bar()

# -----------------------------------------------------------------------------
# Public interface
# -----------------------------------------------------------------------------

func bind_sim(colony_sim: ColonySim) -> void:
	sim = colony_sim
	if sim != null and not _connected_sims.has(sim):
		_connected_sims.append(sim)
		sim.autosaved.connect(_on_autosaved)
		sim.colonist_died.connect(_on_colonist_died)
		sim.objectives_changed.connect(func(_objectives): _refresh_objectives())
	_refresh_game()

func show_title(has_save: bool = false) -> void:
	if sim != null:
		sim.set_speed(0)
	game_ui.visible = false
	title_screen.visible = true
	_close_all_overlays()
	title_continue.disabled = not has_save
	title_continue.text = "CONTINUE COLONY" if has_save else "NO SAVED COLONY"
	title_continue.tooltip_text = "Load the colony saved at the last dawn." if has_save else "Start a new colony first."
	title_screen.move_to_front()

func show_game(colony_sim: ColonySim) -> void:
	bind_sim(colony_sim)
	title_screen.visible = false
	game_ui.visible = true
	_close_all_overlays()
	_close_panels()
	inspector_panel.visible = false
	inspector_mode = ""
	inspector_colonist_id = -1
	inspector_building_id = -1
	_set_rail_active("")
	_refresh_game()
	game_ui.move_to_front()

func show_game_over(summary: Dictionary) -> void:
	if sim != null:
		sim.set_speed(0)
	_close_all_overlays()
	_populate_game_over(summary)
	game_over_overlay.visible = true
	game_over_overlay.move_to_front()

func show_building(id: int) -> void:
	inspector_mode = "building"
	inspector_building_id = id
	inspector_colonist_id = -1
	inspector_panel.visible = true
	_set_rail_active("people")
	_rebuild_inspector()

func show_colonist(id: int) -> void:
	inspector_mode = "colonist"
	inspector_colonist_id = id
	inspector_building_id = -1
	inspector_panel.visible = true
	_set_rail_active("people")
	_rebuild_inspector()
	colonist_selected.emit(id)

func show_people_list() -> void:
	inspector_mode = "list"
	inspector_colonist_id = -1
	inspector_building_id = -1
	inspector_panel.visible = true
	_set_rail_active("people")
	_rebuild_inspector()

func close_inspector() -> void:
	inspector_panel.visible = false
	inspector_mode = ""
	inspector_colonist_id = -1
	inspector_building_id = -1
	_set_rail_active("")
	inspector_closed.emit()

func set_tool_state(mode: String, key: String = "") -> void:
	tool_mode = mode
	tool_key = key
	selected_build_key = key if mode.begins_with("build:") else ""
	_update_build_card_selection()
	_update_hover_bar()

func set_hover_info(text: String) -> void:
	hover_text = text
	_update_hover_bar()

func confirm_action(text: String, callback: Callable) -> void:
	_show_confirm(text, callback)

func toast(text: String, is_error: bool = false) -> void:
	if toast_box == null:
		return
	var panel := HFUI.panel(Color("#1c2a21"), HFUI.RED if is_error else HFUI.AMBER, 10.0, 2)
	panel.custom_minimum_size = Vector2(420, 0)
	var label := HFUI.label(text, 13, Color("#f4c4b8") if is_error else HFUI.PARCHMENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	toast_box.add_child(panel)
	var tween := create_tween()
	tween.tween_interval(3.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.45)
	tween.tween_callback(panel.queue_free)

func handle_escape() -> bool:
	if confirm_overlay.visible:
		_close_confirm()
		return true
	if cloud_overlay.visible:
		_close_cloud()
		return true
	if advisor_overlay.visible:
		_close_advisor()
		return true
	if help_overlay.visible:
		_close_help()
		return true
	if work_overlay.visible:
		work_overlay.visible = false
		return true
	if pause_overlay.visible:
		_resume_game()
		return true
	if not tool_mode.is_empty():
		cancel_requested.emit()
		set_tool_state("", "")
		return true
	if build_panel.visible or orders_panel.visible or log_panel.visible:
		_close_panels()
		return true
	if inspector_panel.visible:
		close_inspector()
		return true
	_open_pause()
	return true

func after_load() -> void:
	_close_all_overlays()
	_close_panels()
	inspector_panel.visible = false
	inspector_mode = ""
	_set_rail_active("")
	set_tool_state("", "")
	_refresh_game()

func current_build_category() -> String:
	return build_category

# -----------------------------------------------------------------------------
# Title screen
# -----------------------------------------------------------------------------

func _build_title_screen() -> void:
	title_screen = Control.new()
	HFUI.full_rect(title_screen)
	title_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(title_screen)
	var art := TextureRect.new()
	HFUI.full_rect(art)
	art.texture = HFAssets.title_art()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(art)
	var shade := TextureRect.new()
	HFUI.full_rect(shade)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.02, 0.04, 0.03, 0.96), Color(0.02, 0.04, 0.03, 0.75), Color(0.02, 0.04, 0.03, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 800
	gradient_texture.height = 720
	gradient_texture.fill_from = Vector2(0.0, 0.0)
	gradient_texture.fill_to = Vector2(1.0, 0.0)
	shade.texture = gradient_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(shade)
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	content.position = Vector2(74, 84)
	content.size = Vector2(500, 620)
	content.add_theme_constant_override("separation", 10)
	title_screen.add_child(content)
	var eyebrow := HFUI.eyebrow("A living colony simulation", HFUI.AMBER)
	content.add_child(eyebrow)
	var title := HFUI.title_label("HEARTHFALL", 74, HFUI.PARCHMENT)
	title.add_theme_constant_override("letter_spacing", 2)
	content.add_child(title)
	var subtitle := HFUI.display_label("COLONY", 34, HFUI.AMBER)
	subtitle.add_theme_constant_override("letter_spacing", 9)
	content.add_child(subtitle)
	var rule := ColorRect.new()
	rule.color = Color("#efb35a")
	rule.custom_minimum_size = Vector2(96, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(rule)
	var blurb := HFUI.label("Lead a handful of survivors into an untamed clearing.\nEvery need, mood, meal, storm, and relationship is simulated.", 16, Color("#d7cfb9"))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(440, 58)
	content.add_child(blurb)
	content.add_child(HFUI.spacer(12))
	title_new = HFUI.primary_button("BEGIN A NEW COLONY", 310)
	title_new.custom_minimum_size.y = 46
	title_new.pressed.connect(func(): new_colony_requested.emit())
	content.add_child(title_new)
	title_continue = HFUI.button("CONTINUE COLONY", 310)
	title_continue.custom_minimum_size.y = 42
	title_continue.pressed.connect(func(): continue_requested.emit())
	content.add_child(title_continue)
	title_help = HFUI.button("HOW TO PLAY", 310)
	title_help.custom_minimum_size.y = 42
	title_help.pressed.connect(func(): _open_help(true))
	content.add_child(title_help)
	var title_cloud := HFUI.button("CLOUD SAVES & RANKS", 310)
	title_cloud.custom_minimum_size.y = 36
	title_cloud.pressed.connect(func(): _open_cloud(true))
	content.add_child(title_cloud)
	content.add_child(HFUI.spacer(8))
	var note := HFUI.label("Build. Forage. Keep the fire alive.\nThe colony remembers what you do.", 12, HFUI.MUTED)
	content.add_child(note)
	var footer := HFUI.label("Hearthfall Colony · v1.0  |  Pixel art and UI made for this settlement  |  Fonts: SIL OFL", 10, Color("#8c9b88"))
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(74, -34)
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_top = -34
	footer.offset_bottom = -14
	title_screen.add_child(footer)

# -----------------------------------------------------------------------------
# Main game interface
# -----------------------------------------------------------------------------

func _build_game_ui() -> void:
	game_ui = Control.new()
	HFUI.full_rect(game_ui)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.visible = false
	add_child(game_ui)
	_build_top_bar()
	_build_left_rail()
	_build_objectives_panel()
	_build_alerts()
	_build_hover_bar()
	_build_toasts()
	_build_build_panel()
	_build_orders_panel()
	_build_log_panel()
	_build_inspector()

func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 64
	top_bar.add_theme_stylebox_override("panel", HFUI.style_box(Color("#111b16"), Color("#3e5140"), 8.0, 2, 2))
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(top_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	top_bar.add_child(row)
	var mark := VBoxContainer.new()
	mark.custom_minimum_size = Vector2(126, 0)
	mark.add_theme_constant_override("separation", -2)
	row.add_child(mark)
	var mark_title := HFUI.display_label("HEARTHFALL", 17, HFUI.AMBER)
	mark.add_child(mark_title)
	var mark_sub := HFUI.eyebrow("COLONY", HFUI.MUTED)
	mark_sub.add_theme_font_size_override("font_size", 9)
	mark.add_child(mark_sub)
	row.add_child(HFUI.h_spacer(3))
	_add_resource_chip(row, "wood", "Wood", "wood")
	_add_resource_chip(row, "stone", "Stone", "stone")
	_add_resource_chip(row, "food", "Food", "meal")
	_add_resource_chip(row, "herbs", "Herbs", "herbs")
	_add_resource_chip(row, "ore", "Ore", "ore")
	_add_resource_chip(row, "tools", "Tools", "tools")
	row.add_child(HFUI.h_spacer(6))
	var time_box := VBoxContainer.new()
	time_box.custom_minimum_size = Vector2(230, 0)
	time_box.add_theme_constant_override("separation", -1)
	row.add_child(time_box)
	date_label = HFUI.medium_label("SPRING · DAY 1 · YEAR 1", 11, HFUI.AMBER)
	time_box.add_child(date_label)
	clock_label = HFUI.label("07:00 · Dawn", 15, HFUI.PARCHMENT)
	time_box.add_child(clock_label)
	weather_label = HFUI.label("14°C · Clear", 11, HFUI.MUTED)
	time_box.add_child(weather_label)
	row.add_child(HFUI.h_spacer(4))
	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 3)
	row.add_child(speed_box)
	for entry in [[0, "II"], [1, "1×"], [2, "2×"], [4, "4×"]]:
		var b := HFUI.button(str(entry[1]), 34, 12)
		b.custom_minimum_size = Vector2(34, 30)
		b.tooltip_text = "Pause time" if int(entry[0]) == 0 else "Set game speed to %d×" % int(entry[0])
		b.pressed.connect(_on_speed_pressed.bind(int(entry[0])))
		speed_box.add_child(b)
		speed_buttons[int(entry[0])] = b
	row.add_child(HFUI.h_spacer(3))
	menu_button = HFUI.button("MENU", 54, 12)
	menu_button.custom_minimum_size = Vector2(54, 30)
	menu_button.pressed.connect(_open_pause)
	row.add_child(menu_button)

func _add_resource_chip(row: HBoxContainer, key: String, title: String, icon_name: String) -> void:
	var chip := HBoxContainer.new()
	chip.custom_minimum_size = Vector2(82, 0)
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := HFUI.texture_rect(HFAssets.tex(icon_name), Vector2(24, 24))
	chip.add_child(icon)
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", -4)
	chip.add_child(labels)
	var title_label := HFUI.eyebrow(title, HFUI.SUBTLE)
	title_label.add_theme_font_size_override("font_size", 8)
	labels.add_child(title_label)
	var value := HFUI.medium_label("0", 14, HFUI.PARCHMENT)
	labels.add_child(value)
	resource_values[key] = value
	chip.tooltip_text = _resource_tooltip(key)
	row.add_child(chip)

func _resource_tooltip(key: String) -> String:
	match key:
		"food":
			return "Total nutrition in storage. Colonists need roughly 110–150 nutrition per day."
		"herbs":
			return "Used by doctors to treat injuries and illness."
		"tools":
			return "Good tools speed up gathering, building, hauling, and crafting."
		"ore":
			return "Smelted into better tools at a forge."
	return "Stored %s. Haulers carry loose piles into stockpiles." % key.capitalize()

func _build_left_rail() -> void:
	left_rail = HFUI.panel(Color("#131f19"), Color("#465a46"), 7.0, 2)
	left_rail.position = Vector2(14, 78)
	left_rail.custom_minimum_size = Vector2(122, 0)
	left_rail.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(left_rail)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	left_rail.add_child(box)
	for entry in [
		["build", "cabin", "BUILD"],
		["orders", "axe", "ORDERS"],
		["people", "colonist_00", "PEOPLE"],
		["work", "tools", "WORK"],
		["advisor", "seeds", "ADVISOR"],
		["log", "cloth", "LOG"],
		["help", "seeds", "HELP"],
	]:
		var button := HFUI.icon_button(HFAssets.tex(str(entry[1])), str(entry[2]), 106)
		button.custom_minimum_size = Vector2(106, 37)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.pressed.connect(_on_rail_pressed.bind(str(entry[0])))
		box.add_child(button)
		rail_buttons[str(entry[0])] = button

func _build_objectives_panel() -> void:
	objectives_panel = HFUI.panel(Color("#17231c"), Color("#4a604a"), 10.0, 2)
	objectives_panel.position = Vector2(150, 78)
	objectives_panel.custom_minimum_size = Vector2(300, 0)
	objectives_panel.size = Vector2(300, 150)
	objectives_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(objectives_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	objectives_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var heading := HFUI.eyebrow("First steps", HFUI.AMBER)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var collapse := HFUI.button("–", 26, 13)
	collapse.custom_minimum_size = Vector2(26, 22)
	collapse.pressed.connect(_toggle_objectives)
	header.add_child(collapse)
	objectives_body = VBoxContainer.new()
	objectives_body.add_theme_constant_override("separation", 3)
	box.add_child(objectives_body)
	for entry in [
		["cabin", "Raise a cabin"],
		["farm", "Break ground with a farm"],
		["cookhouse", "Build a cookhouse"],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		objectives_body.add_child(row)
		var check := HFUI.medium_label("[ ]", 12, HFUI.MUTED)
		check.custom_minimum_size = Vector2(24, 0)
		row.add_child(check)
		var label := HFUI.label(str(entry[1]), 12, HFUI.PARCHMENT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		objective_rows[str(entry[0])] = {"check": check, "label": label}
	var research := HFUI.label("Research: —", 10, HFUI.SUBTLE)
	research.name = "ResearchLine"
	objectives_body.add_child(research)

func _toggle_objectives() -> void:
	objectives_collapsed = not objectives_collapsed
	objectives_body.visible = not objectives_collapsed
	objectives_panel.size = Vector2(300, 40) if objectives_collapsed else Vector2(300, 150)

func _build_alerts() -> void:
	alerts_box = VBoxContainer.new()
	alerts_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	alerts_box.offset_left = -180
	alerts_box.offset_right = 180
	alerts_box.offset_top = 76
	alerts_box.add_theme_constant_override("separation", 5)
	alerts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(alerts_box)

func _build_hover_bar() -> void:
	hover_bar = HFUI.panel(Color("#101813"), Color("#5b6c55"), 7.0, 1)
	hover_bar.custom_minimum_size = Vector2(560, 0)
	hover_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(hover_bar)
	hover_label = HFUI.label("", 11, HFUI.MUTED)
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_bar.add_child(hover_label)

func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(410, 560)
	toast_box.size = Vector2(460, 50)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.add_theme_constant_override("separation", 5)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(toast_box)

func _layout_hud() -> void:
	if hover_bar == null:
		return
	var bottom_margin := 52.0
	if build_panel != null and build_panel.visible:
		bottom_margin = 212.0
	hover_bar.position = Vector2((size.x - 560.0) * 0.5, size.y - bottom_margin - 28.0)
	hover_bar.size = Vector2(560.0, 28.0)
	if toast_box != null:
		toast_box.position = Vector2((size.x - 460.0) * 0.5, size.y - bottom_margin - 108.0)
		toast_box.size = Vector2(460.0, 50.0)
	if log_panel != null:
		log_panel.position = Vector2(150, size.y - 262)
	if orders_panel != null:
		orders_panel.position = Vector2(150, 242)
		orders_panel.size = Vector2(260, clampf(size.y - 300.0, 380.0, 560.0))

func _update_hover_bar() -> void:
	if hover_label == null:
		return
	var hint := ""
	if tool_mode.begins_with("build:"):
		var def: Dictionary = HFDefs.BUILDINGS.get(tool_key, {})
		hint = "Placing %s · click to build · right-click to cancel" % str(def.get("name", "structure"))
	elif tool_mode == "gather":
		hint = "Click a tree, rock, bush, or other resource to gather · right-click to cancel"
	elif tool_mode == "hunt":
		hint = "Click an animal to mark it for the hunt · right-click to cancel"
	elif tool_mode == "demolish":
		hint = "Click a building to dismantle it · right-click to cancel"
	if not hint.is_empty() and not hover_text.is_empty():
		hover_label.text = hint + "   |   " + hover_text
	elif not hint.is_empty():
		hover_label.text = hint
	else:
		hover_label.text = hover_text if not hover_text.is_empty() else "WASD / arrows to move · mouse wheel to zoom · right-click to cancel"

# -----------------------------------------------------------------------------
# Build panel
# -----------------------------------------------------------------------------

func _build_build_panel() -> void:
	build_panel = HFUI.panel(Color("#141f19"), Color("#55684f"), 10.0, 2)
	build_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build_panel.offset_left = 14
	build_panel.offset_right = -14
	build_panel.offset_top = -196
	build_panel.offset_bottom = -12
	build_panel.visible = false
	build_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(build_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	build_panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var heading := HFUI.eyebrow("Build", HFUI.AMBER)
	header.add_child(heading)
	build_info_label = HFUI.label("Choose a structure, then click the map to place it.", 11, HFUI.MUTED)
	build_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(build_info_label)
	var close := HFUI.button("CLOSE", 62, 11)
	close.custom_minimum_size = Vector2(62, 24)
	close.pressed.connect(_close_build_panel)
	header.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	box.add_child(tabs)
	var categories: Array = HFDefs.BUILD_CATEGORIES.keys()
	categories.sort_custom(func(a, b): return int(HFDefs.BUILD_CATEGORIES[a]["order"]) < int(HFDefs.BUILD_CATEGORIES[b]["order"]))
	for category in categories:
		var button := HFUI.button(str(HFDefs.BUILD_CATEGORIES[category]["name"]), 0, 11)
		button.custom_minimum_size = Vector2(0, 27)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_build_category.bind(str(category)))
		tabs.add_child(button)
		build_category_buttons[str(category)] = button
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 102)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(scroll)
	build_cards_box = HBoxContainer.new()
	build_cards_box.add_theme_constant_override("separation", 6)
	build_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(build_cards_box)
	_rebuild_build_cards()
	_update_build_category_styles()

func _on_build_category(category: String) -> void:
	build_category = category
	_rebuild_build_cards()
	_update_build_category_styles()

func _rebuild_build_cards() -> void:
	if build_cards_box == null:
		return
	for child in build_cards_box.get_children():
		child.queue_free()
	build_cards.clear()
	for key in HFDefs.BUILDINGS.keys():
		var def: Dictionary = HFDefs.BUILDINGS[key]
		if bool(def.get("hidden", false)) or str(def.get("category", "")) != build_category:
			continue
		var card := Button.new()
		card.custom_minimum_size = Vector2(112, 98)
		card.focus_mode = Control.FOCUS_NONE
		card.tooltip_text = "%s\n%s\nCost: %s" % [str(def.get("name", key)), str(def.get("desc", "")), _cost_text(def.get("cost", {}))]
		card.add_theme_stylebox_override("normal", HFUI.style_box(Color("#1b2820"), Color("#405441"), 6.0, 2, 1))
		card.add_theme_stylebox_override("hover", HFUI.style_box(Color("#2a3b2c"), HFUI.AMBER, 6.0, 2, 2))
		card.add_theme_stylebox_override("pressed", HFUI.style_box(Color("#49371f"), HFUI.AMBER_LIGHT, 6.0, 2, 1))
		card.pressed.connect(_on_build_card_pressed.bind(str(key)))
		build_cards_box.add_child(card)
		var content := VBoxContainer.new()
		HFUI.full_rect(content)
		content.offset_left = 5
		content.offset_right = -5
		content.offset_top = 4
		content.offset_bottom = -4
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 1)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		var icon := HFUI.texture_rect(HFAssets.building_icon(str(key)), Vector2(42, 42))
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.add_child(icon)
		var name_label := HFUI.medium_label(str(def.get("name", key)), 10, HFUI.PARCHMENT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		content.add_child(name_label)
		var cost_label := HFUI.label(_cost_short(def.get("cost", {})), 9, HFUI.MUTED)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(cost_label)
		build_cards[str(key)] = card
	_update_build_card_selection()

func _on_build_card_pressed(key: String) -> void:
	if selected_build_key == key:
		cancel_requested.emit()
		set_tool_state("", "")
		build_info_label.text = "Choose a structure, then click the map to place it."
		return
	selected_build_key = key
	var def: Dictionary = HFDefs.BUILDINGS.get(key, {})
	build_info_label.text = "%s · %s · %s" % [str(def.get("name", key)), _cost_text(def.get("cost", {})), str(def.get("desc", ""))]
	build_requested.emit(key)
	_update_build_card_selection()

func _update_build_card_selection() -> void:
	for key in build_cards.keys():
		var card: Button = build_cards[key]
		if key == selected_build_key:
			card.add_theme_stylebox_override("normal", HFUI.style_box(Color("#4b3a22"), HFUI.AMBER_LIGHT, 6.0, 2, 2))
		else:
			card.add_theme_stylebox_override("normal", HFUI.style_box(Color("#1b2820"), Color("#405441"), 6.0, 2, 1))

func _update_build_category_styles() -> void:
	for category in build_category_buttons.keys():
		var button: Button = build_category_buttons[category]
		if category == build_category:
			button.add_theme_stylebox_override("normal", HFUI.style_box(Color("#3d3020"), HFUI.AMBER, 7.0, 2, 1))
			button.add_theme_color_override("font_color", HFUI.AMBER_LIGHT)
		else:
			button.add_theme_stylebox_override("normal", HFUI.style_box(Color("#18241d"), Color("#38493c"), 7.0, 1, 1))
			button.add_theme_color_override("font_color", HFUI.MUTED)

func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for key in cost.keys():
		parts.append("%d %s" % [int(cost[key]), HFDefs.resource_name(str(key))])
	return ", ".join(parts) if not parts.is_empty() else "Free"

func _cost_short(cost: Dictionary) -> String:
	var parts: Array = []
	for key in cost.keys():
		var short := str(key).substr(0, 1).to_upper()
		if str(key) == "stone":
			short = "St"
		elif str(key) == "wood":
			short = "W"
		elif str(key) == "ore":
			short = "O"
		elif str(key) == "herbs":
			short = "H"
		elif str(key) == "cloth":
			short = "C"
		parts.append("%d%s" % [int(cost[key]), short])
	return " ".join(parts)

func _close_build_panel() -> void:
	build_panel.visible = false
	cancel_requested.emit()
	set_tool_state("", "")
	_set_rail_active("")
	_layout_hud()

# -----------------------------------------------------------------------------
# Orders and log
# -----------------------------------------------------------------------------

func _build_orders_panel() -> void:
	orders_panel = HFUI.panel(Color("#17231c"), Color("#4a604a"), 10.0, 2)
	orders_panel.custom_minimum_size = Vector2(260, 380)
	orders_panel.size = Vector2(260, 520)
	orders_panel.visible = false
	orders_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(orders_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	orders_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := HFUI.eyebrow("Orders", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("×", 24, 13)
	close.custom_minimum_size = Vector2(24, 22)
	close.pressed.connect(_close_orders_panel)
	header.add_child(close)
	var description := HFUI.label("Point at the land and give the order.", 11, HFUI.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	for entry in [
		["gather", "axe", "Forage & chop", "Gather wood, stone, ore, berries, herbs, and other wild resources."],
		["herbs", "herbs", "Gather herbs", "Send foragers to the nearest wild herb patch. Useful when illness takes hold."],
		["hunt", "meat", "Hunt wildlife", "Mark an animal for hunters. Predators will defend themselves."],
		["demolish", "wall", "Demolish", "Dismantle a building and recover some materials."],
	]:
		var button := HFUI.icon_button(HFAssets.tex(str(entry[1])), str(entry[2]), 228)
		button.custom_minimum_size = Vector2(228, 32)
		button.tooltip_text = str(entry[3])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_order_pressed.bind(str(entry[0])))
		box.add_child(button)
		order_buttons[str(entry[0])] = button
	var hint := HFUI.label("Right-click anywhere to cancel the order.", 10, HFUI.SUBTLE)
	box.add_child(hint)
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	box.add_child(separator)
	var active_header := HFUI.eyebrow("Standing orders", HFUI.MUTED)
	box.add_child(active_header)
	var active_scroll := ScrollContainer.new()
	active_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	active_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	active_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	active_scroll.custom_minimum_size = Vector2(228, 120)
	box.add_child(active_scroll)
	orders_active_box = VBoxContainer.new()
	orders_active_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orders_active_box.add_theme_constant_override("separation", 4)
	active_scroll.add_child(orders_active_box)

func _on_order_pressed(tool: String) -> void:
	if tool == "herbs":
		herb_order_requested.emit()
		return
	if tool_mode == tool:
		cancel_requested.emit()
		set_tool_state("", "")
		_style_order_buttons()
		return
	build_panel.visible = false
	order_requested.emit(tool)
	set_tool_state(tool, "")
	_style_order_buttons()
	_layout_hud()

func _style_order_buttons() -> void:
	for tool in order_buttons.keys():
		var button: Button = order_buttons[tool]
		if tool_mode == tool:
			button.add_theme_stylebox_override("normal", HFUI.style_box(Color("#49371f"), HFUI.AMBER_LIGHT, 8.0, 2, 2))
		else:
			button.add_theme_stylebox_override("normal", HFUI.style_box(HFUI.PANEL_LIGHT, HFUI.BORDER, 8.0, 2, 2))

func _close_orders_panel() -> void:
	orders_panel.visible = false
	cancel_requested.emit()
	set_tool_state("", "")
	_set_rail_active("")

func _build_log_panel() -> void:
	log_panel = HFUI.panel(Color("#101813"), Color("#3f5042"), 8.0, 2)
	log_panel.size = Vector2(380, 210)
	log_panel.custom_minimum_size = Vector2(380, 210)
	log_panel.visible = false
	log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(log_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	log_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := HFUI.eyebrow("Colony log", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("×", 24, 13)
	close.custom_minimum_size = Vector2(24, 22)
	close.pressed.connect(_close_log_panel)
	header.add_child(close)
	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(360, 168)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(log_scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 5)
	log_scroll.add_child(log_box)

func _close_log_panel() -> void:
	log_panel.visible = false
	_set_rail_active("")

func _refresh_log() -> void:
	if log_panel == null or not log_panel.visible or sim == null:
		return
	var entries: Array = sim.event_log.slice(maxi(0, sim.event_log.size() - 14), sim.event_log.size())
	var signature := ""
	for entry in entries:
		signature += str(entry.get("time", 0.0)) + str(entry.get("text", ""))
	if signature == log_signature:
		return
	log_signature = signature
	for child in log_box.get_children():
		child.queue_free()
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		log_box.add_child(row)
		var time := HFUI.label("%02d:%02d" % [int(entry.get("time", 0.0)) % 1440 / 60, int(entry.get("time", 0.0)) % 60], 9, HFUI.SUBTLE)
		time.custom_minimum_size = Vector2(34, 0)
		row.add_child(time)
		var color := HFUI.PARCHMENT
		match str(entry.get("type", "")):
			"danger":
				color = Color("#e8a094")
			"warning":
				color = HFUI.AMBER
			"story":
				color = Color("#d9cba9")
			"build":
				color = HFUI.MOSS
			"work":
				color = Color("#b9c6b0")
			"weather":
				color = HFUI.BLUE
		var label := HFUI.label(str(entry.get("text", "")), 11, color)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
	log_scroll.set_deferred("scroll_vertical", 999999)

# -----------------------------------------------------------------------------
# Inspector
# -----------------------------------------------------------------------------

func _build_inspector() -> void:
	inspector_panel = HFUI.panel(Color("#121d17"), Color("#52664e"), 8.0, 2)
	inspector_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	inspector_panel.offset_left = -366
	inspector_panel.offset_right = -14
	inspector_panel.offset_top = 78
	inspector_panel.offset_bottom = -14
	inspector_panel.visible = false
	inspector_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(inspector_panel)
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inspector_panel.add_child(inspector_scroll)
	inspector_body = VBoxContainer.new()
	inspector_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_body.add_theme_constant_override("separation", 6)
	inspector_scroll.add_child(inspector_body)

func _clear_inspector() -> void:
	for child in inspector_body.get_children():
		child.queue_free()
	inspector_refs.clear()

func _rebuild_inspector() -> void:
	if not inspector_panel.visible:
		return
	_clear_inspector()
	match inspector_mode:
		"list":
			_build_people_list()
		"colonist":
			_build_colonist_detail()
		"building":
			_build_building_detail()
		_:
			inspector_panel.visible = false

func _build_people_list() -> void:
	var header := HBoxContainer.new()
	inspector_body.add_child(header)
	var title := HFUI.eyebrow("Colonists · %d" % sim.colonists.size(), HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("×", 26, 14)
	close.custom_minimum_size = Vector2(26, 24)
	close.pressed.connect(close_inspector)
	header.add_child(close)
	var note := HFUI.label("Every settler has their own needs, mood, history, and way of seeing the world.", 11, HFUI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_body.add_child(note)
	people_signature = str(sim.colonists.size())
	for c in sim.colonists:
		people_signature += "|" + str(c["id"])
		var button := Button.new()
		button.custom_minimum_size = Vector2(330, 62)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", HFUI.style_box(Color("#1a2820"), Color("#3e5140"), 6.0, 1, 1))
		button.add_theme_stylebox_override("hover", HFUI.style_box(Color("#26382b"), HFUI.AMBER, 6.0, 2, 2))
		button.pressed.connect(show_colonist.bind(int(c["id"])))
		inspector_body.add_child(button)
		var row := HBoxContainer.new()
		HFUI.full_rect(row)
		row.offset_left = 6
		row.offset_right = -6
		row.offset_top = 4
		row.offset_bottom = -4
		row.add_theme_constant_override("separation", 7)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(row)
		var portrait_panel := HFUI.panel(Color("#0e1712"), Color("#3f5042"), 3.0, 1)
		portrait_panel.custom_minimum_size = Vector2(46, 46)
		portrait_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait_panel)
		var portrait := HFUI.texture_rect(HFAssets.tex("colonist_%02d" % int(c.get("sprite_index", 0))), Vector2(40, 40))
		portrait_panel.add_child(portrait)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", -2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)
		var name := HFUI.medium_label(str(c["name"]), 12, HFUI.PARCHMENT)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(name)
		var status := HFUI.label(sim.colonist_status_text(c), 10, HFUI.MUTED)
		status.clip_text = true
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(status)
		var mood_row := HBoxContainer.new()
		mood_row.add_theme_constant_override("separation", 5)
		mood_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(mood_row)
		var mood_bar := HFUI.bar(float(c["mood"]), 100.0, HFUI.mood_color(float(c["mood"])), 100.0, 6.0)
		mood_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mood_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mood_row.add_child(mood_bar)
		var mood_value := HFUI.label("%d" % int(c["mood"]), 9, HFUI.mood_color(float(c["mood"])))
		mood_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mood_row.add_child(mood_value)
		inspector_refs[int(c["id"])] = {"status": status, "mood": mood_bar, "mood_value": mood_value}

func _build_colonist_detail() -> void:
	var c := sim.colonist_by_id(inspector_colonist_id)
	if c.is_empty():
		inspector_panel.visible = false
		return
	var header := HBoxContainer.new()
	inspector_body.add_child(header)
	var back := HFUI.button("← ALL", 56, 11)
	back.custom_minimum_size = Vector2(56, 24)
	back.pressed.connect(show_people_list)
	header.add_child(back)
	var title := HFUI.eyebrow("Colonist record", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("×", 26, 14)
	close.custom_minimum_size = Vector2(26, 24)
	close.pressed.connect(close_inspector)
	header.add_child(close)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 9)
	inspector_body.add_child(identity)
	var portrait_panel := HFUI.panel(Color("#0e1712"), Color("#51634c"), 4.0, 2)
	portrait_panel.custom_minimum_size = Vector2(82, 82)
	identity.add_child(portrait_panel)
	portrait_panel.add_child(HFUI.texture_rect(HFAssets.tex("colonist_%02d" % int(c.get("sprite_index", 0))), Vector2(74, 74)))
	var identity_text := VBoxContainer.new()
	identity_text.add_theme_constant_override("separation", -1)
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(identity_text)
	var name := HFUI.display_label(str(c["name"]), 21, HFUI.PARCHMENT)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_text.add_child(name)
	var status := HFUI.label(sim.colonist_status_text(c), 11, HFUI.AMBER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_text.add_child(status)
	var age := HFUI.label("Age %d · %s" % [int(c["age"]), _trait_names(c)], 10, HFUI.MUTED)
	age.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_text.add_child(age)
	inspector_refs["identity_status"] = status
	# Mood
	var mood_section := _inspector_section("Mood")
	var mood_top := HBoxContainer.new()
	mood_section.add_child(mood_top)
	var mood_value := HFUI.display_label("%d" % int(c["mood"]), 28, HFUI.mood_color(float(c["mood"])))
	mood_top.add_child(mood_value)
	var mood_text_box := VBoxContainer.new()
	mood_text_box.add_theme_constant_override("separation", -3)
	mood_top.add_child(mood_text_box)
	var mood_label := HFUI.medium_label(_mood_description(float(c["mood"])), 12, HFUI.mood_color(float(c["mood"])))
	mood_text_box.add_child(mood_label)
	var mood_note := HFUI.label("How the last few days feel.", 9, HFUI.SUBTLE)
	mood_text_box.add_child(mood_note)
	var mood_bar := HFUI.bar(float(c["mood"]), 100.0, HFUI.mood_color(float(c["mood"])), 0.0, 8.0)
	mood_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mood_section.add_child(mood_bar)
	var reasons_box := VBoxContainer.new()
	reasons_box.add_theme_constant_override("separation", 2)
	mood_section.add_child(reasons_box)
	inspector_refs["mood_value"] = mood_value
	inspector_refs["mood_label"] = mood_label
	inspector_refs["mood_bar"] = mood_bar
	inspector_refs["mood_reasons"] = reasons_box
	# Needs
	var needs_section := _inspector_section("Needs")
	_add_inspector_need(needs_section, c, "hunger", "Hunger", "Food in the belly", Color("#d7a15d"))
	_add_inspector_need(needs_section, c, "fatigue", "Energy", "Rest and sleep", Color("#8aa9b7"))
	_add_inspector_need(needs_section, c, "warmth", "Warmth", "Shelter and fire", Color("#d87955"))
	_add_inspector_need(needs_section, c, "hygiene", "Hygiene", "Washing and clean water", Color("#a7b989"))
	# Health
	var health_section := _inspector_section("Health")
	var health_top := HBoxContainer.new()
	health_section.add_child(health_top)
	var health_bar := HFUI.bar(float(c["health"]), 100.0, HFUI.need_color(float(c["health"])), 0.0, 8.0)
	health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_top.add_child(health_bar)
	var health_value := HFUI.label("%d" % int(c["health"]), 10, HFUI.need_color(float(c["health"])))
	health_top.add_child(health_value)
	var health_note := HFUI.label("", 10, HFUI.MUTED)
	health_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	health_section.add_child(health_note)
	inspector_refs["health_bar"] = health_bar
	inspector_refs["health_value"] = health_value
	inspector_refs["health_note"] = health_note
	# Work
	var work_section := _inspector_section("Work")
	var work_status := HFUI.label(sim.colonist_status_text(c), 11, HFUI.PARCHMENT)
	work_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	work_section.add_child(work_status)
	var work_hint := HFUI.label(_work_summary(c), 10, HFUI.MUTED)
	work_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	work_section.add_child(work_hint)
	var work_button := HFUI.button("OPEN WORK ROTA", 0, 10)
	work_button.custom_minimum_size.y = 28
	work_button.pressed.connect(_open_work)
	work_section.add_child(work_button)
	inspector_refs["work_status"] = work_status
	# Skills
	var skills_section := _inspector_section("Skills")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	skills_section.add_child(grid)
	for skill_id in HFDefs.SKILLS.keys():
		var skill_row := HBoxContainer.new()
		skill_row.add_theme_constant_override("separation", 4)
		skill_row.custom_minimum_size = Vector2(150, 0)
		grid.add_child(skill_row)
		var label := HFUI.label(str(HFDefs.SKILLS[skill_id]["name"]), 9, HFUI.MUTED)
		label.custom_minimum_size = Vector2(56, 0)
		skill_row.add_child(label)
		var value := int(round(sim.skill_value(c, str(skill_id))))
		var bar := HFUI.bar(float(value), 20.0, HFUI.MOSS, 0.0, 5.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_row.add_child(bar)
		var number := HFUI.label(str(value), 9, HFUI.PARCHMENT)
		number.custom_minimum_size = Vector2(16, 0)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		skill_row.add_child(number)
		inspector_refs["skill_" + str(skill_id)] = {"bar": bar, "number": number}
	# Relationships
	var relationship_section := _inspector_section("Relationships")
	var relationship_box := VBoxContainer.new()
	relationship_box.add_theme_constant_override("separation", 3)
	relationship_section.add_child(relationship_box)
	inspector_refs["relationships"] = relationship_box
	# Traits
	var traits_section := _inspector_section("Temperament")
	for trait_id in c.get("traits", []):
		var trait_def: Dictionary = HFDefs.TRAITS.get(str(trait_id), {})
		var trait_name := HFUI.medium_label(str(trait_def.get("name", trait_id)), 11, HFUI.AMBER)
		traits_section.add_child(trait_name)
		var trait_desc := HFUI.label(str(trait_def.get("desc", "")), 10, HFUI.MUTED)
		trait_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		traits_section.add_child(trait_desc)

func _inspector_section(title: String) -> VBoxContainer:
	var panel := HFUI.panel(Color("#1b2820"), Color("#3d5040"), 8.0, 1)
	inspector_body.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(HFUI.eyebrow(title, HFUI.AMBER))
	return box

func _add_inspector_need(parent: VBoxContainer, c: Dictionary, key: String, title: String, tip: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	var label := HFUI.label(title, 10, HFUI.MUTED)
	label.custom_minimum_size = Vector2(52, 0)
	label.tooltip_text = tip
	row.add_child(label)
	var bar := HFUI.bar(float(c["needs"].get(key, 0.0)), 100.0, color, 0.0, 7.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var value := HFUI.label("%d" % int(c["needs"].get(key, 0.0)), 9, color)
	value.custom_minimum_size = Vector2(24, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	inspector_refs["need_" + key] = {"bar": bar, "value": value, "color": color}

func _build_building_detail() -> void:
	var b := sim.get_building(inspector_building_id)
	if b.is_empty():
		inspector_panel.visible = false
		return
	var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
	var header := HBoxContainer.new()
	inspector_body.add_child(header)
	var title := HFUI.eyebrow("Structure record", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("×", 26, 14)
	close.custom_minimum_size = Vector2(26, 24)
	close.pressed.connect(close_inspector)
	header.add_child(close)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 8)
	inspector_body.add_child(identity)
	var icon_panel := HFUI.panel(Color("#0e1712"), Color("#51634c"), 4.0, 2)
	icon_panel.custom_minimum_size = Vector2(76, 76)
	identity.add_child(icon_panel)
	icon_panel.add_child(HFUI.texture_rect(HFAssets.building_icon(str(b["key"])), Vector2(66, 66)))
	var identity_text := VBoxContainer.new()
	identity_text.add_theme_constant_override("separation", -1)
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(identity_text)
	identity_text.add_child(HFUI.display_label(str(def.get("name", "Structure")), 21, HFUI.PARCHMENT))
	var status := HFUI.label(_building_status(b), 11, HFUI.AMBER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_text.add_child(status)
	identity_text.add_child(HFUI.label("Footprint %d×%d" % [int(b["size"].x), int(b["size"].y)], 10, HFUI.MUTED))
	inspector_refs["building_status"] = status
	var description := HFUI.label(str(def.get("desc", "")), 11, HFUI.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_body.add_child(description)
	var health_section := _inspector_section("Condition")
	var hp_top := HBoxContainer.new()
	health_section.add_child(hp_top)
	var hp_bar := HFUI.bar(float(b.get("hp", 0.0)), float(b.get("max_hp", 100.0)), HFUI.need_color(float(b.get("hp", 0.0)) / maxf(1.0, float(b.get("max_hp", 100.0))) * 100.0), 0.0, 8.0)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_top.add_child(hp_bar)
	var hp_label := HFUI.label("", 10, HFUI.MUTED)
	hp_top.add_child(hp_label)
	inspector_refs["building_hp"] = hp_bar
	inspector_refs["building_hp_label"] = hp_label
	if not bool(b.get("built", false)):
		var progress := 0.0
		for job in sim.jobs:
			if int(job.get("building_id", -1)) == int(b["id"]) and str(job.get("type", "")) == "build":
				progress = clampf(float(job.get("progress", 0.0)) / maxf(0.01, float(job.get("work_required", 1.0))), 0.0, 1.0)
		var build_bar := HFUI.bar(progress * 100.0, 100.0, HFUI.AMBER, 0.0, 7.0)
		build_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		health_section.add_child(HFUI.label("Construction progress", 9, HFUI.SUBTLE))
		health_section.add_child(build_bar)
		inspector_refs["build_progress"] = build_bar
	if bool(def.get("farm", false)):
		var farm_section := _inspector_section("Fields")
		var crop_row := HBoxContainer.new()
		crop_row.add_theme_constant_override("separation", 5)
		farm_section.add_child(crop_row)
		for crop in [["grain", "Grain"], ["pumpkin", "Pumpkin"]]:
			var crop_button := HFUI.button(str(crop[1]), 0, 10)
			crop_button.custom_minimum_size = Vector2(100, 27)
			crop_button.disabled = bool(b.get("planted", false)) or str(b.get("crop", "grain")) == str(crop[0])
			crop_button.pressed.connect(_on_crop_pressed.bind(int(b["id"]), str(crop[0])))
			crop_row.add_child(crop_button)
		var growth_bar := HFUI.bar(float(b.get("growth", 0.0)), 100.0, HFUI.GREEN, 0.0, 7.0)
		growth_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		farm_section.add_child(growth_bar)
		var farm_label := HFUI.label(sim.farm_status(b), 10, HFUI.MUTED)
		farm_section.add_child(farm_label)
		inspector_refs["farm_growth"] = growth_bar
		inspector_refs["farm_status"] = farm_label
	if int(def.get("beds", 0)) > 0:
		var bed_section := _inspector_section("Beds")
		var bed_label := HFUI.label("%d of %d beds occupied" % [b.get("occupants", []).size(), int(def.get("beds", 0))], 11, HFUI.PARCHMENT)
		bed_section.add_child(bed_label)
		var names := []
		for id in b.get("occupants", []):
			var c := sim.colonist_by_id(int(id))
			if not c.is_empty():
				names.append(str(c["first_name"]))
		if not names.is_empty():
			bed_section.add_child(HFUI.label("Sleeping: " + ", ".join(names), 10, HFUI.MUTED))
		inspector_refs["beds"] = bed_label
	if float(def.get("storage", 0.0)) > 0.0:
		var storage_section := _inspector_section("Storage")
		var storage_label := HFUI.label("%d / %d total colony storage" % [int(sim.storage_used()), int(sim.storage_capacity())], 11, HFUI.PARCHMENT)
		storage_section.add_child(storage_label)
		if float(def.get("spoil", 1.0)) < 1.0:
			storage_section.add_child(HFUI.label("Cool, raised storage slows food spoilage.", 10, HFUI.MUTED))
		inspector_refs["storage"] = storage_label
	var station := str(def.get("station", ""))
	if not station.is_empty():
		var station_section := _inspector_section("Workshop")
		var station_label := HFUI.label(_station_description(str(b["key"])), 10, HFUI.MUTED)
		station_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		station_section.add_child(station_label)
	if float(b.get("burning", 0.0)) > 0.0:
		var fire_section := _inspector_section("Fire")
		var fire_label := HFUI.label("The structure is burning. Firefighters are responding.", 10, Color("#e8a094"))
		fire_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fire_section.add_child(fire_label)
		inspector_refs["fire"] = fire_label
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	inspector_body.add_child(actions)
	var demolish := HFUI.danger_button("DISMANTLE", 0)
	demolish.custom_minimum_size.y = 30
	demolish.pressed.connect(_confirm_demolish.bind(int(b["id"])))
	actions.add_child(demolish)
	var focus := HFUI.button("CENTER", 82, 10)
	focus.custom_minimum_size.y = 30
	focus.pressed.connect(func(): center_on_building_requested.emit(int(b["id"])))
	actions.add_child(focus)

func _on_crop_pressed(building_id: int, crop: String) -> void:
	sim.set_crop(building_id, crop)
	_rebuild_inspector()

func _confirm_demolish(building_id: int) -> void:
	_show_confirm("Dismantle this structure? Some materials will be recovered, but any crops inside will be lost.", func():
		var error := sim.demolish_building(building_id)
		if error.is_empty():
			toast("Structure dismantled.")
			close_inspector()
		else:
			toast(error, true)
	)

func _building_status(b: Dictionary) -> String:
	if not bool(b.get("built", false)):
		return "Blueprint · waiting for a builder"
	if float(b.get("burning", 0.0)) > 0.0:
		return "Burning · %d%% intensity" % int(b.get("burning", 0.0))
	if bool(HFDefs.BUILDINGS.get(str(b["key"]), {}).get("farm", false)):
		return sim.farm_status(b)
	return "Standing · condition %d%%" % int(float(b.get("hp", 0.0)) / maxf(1.0, float(b.get("max_hp", 100.0))) * 100.0)

func _station_description(key: String) -> String:
	match key:
		"cookhouse":
			return "Cooks automatically when raw ingredients are available and the colony needs meals."
		"workshop":
			return "Crafts tools automatically when wood, stone, and labor are available."
		"forge":
			return "Uses iron ore and wood to make better tools. Crafting is faster and safer."
		"research_desk":
			return "Colonists study here to unlock better tools, crop rotation, remedies, and storage."
	return "A place for skilled work."

func _trait_names(c: Dictionary) -> String:
	var names: Array = []
	for trait_id in c.get("traits", []):
		names.append(str(HFDefs.TRAITS.get(str(trait_id), {}).get("name", trait_id)))
	return " · ".join(names)

func _work_summary(c: Dictionary) -> String:
	var top: Array = []
	for job_id in HFDefs.JOB_ORDER:
		var priority := int(c.get("priorities", {}).get(job_id, 0))
		if priority >= 3:
			top.append("%s %s" % [str(HFDefs.JOBS[job_id]["name"]), "High" if priority == 3 else "Urgent"])
	if top.is_empty():
		return "No strong preferences. Open the work rota to assign priorities."
	return "Leans toward: " + ", ".join(top) + "."

func _mood_description(mood: float) -> String:
	if mood >= 78.0:
		return "Buoyant"
	if mood >= 58.0:
		return "Content"
	if mood >= 38.0:
		return "Strained"
	if mood >= 20.0:
		return "Miserable"
	return "Broken"

func _refresh_inspector() -> void:
	if not inspector_panel.visible or sim == null:
		return
	match inspector_mode:
		"list":
			var sig := str(sim.colonists.size())
			for c in sim.colonists:
				sig += "|" + str(c["id"])
			if sig != people_signature:
				_rebuild_inspector()
				return
			for c in sim.colonists:
				var refs: Dictionary = inspector_refs.get(int(c["id"]), {})
				if refs.is_empty():
					continue
				refs["status"].text = sim.colonist_status_text(c)
				refs["mood"].value = float(c["mood"])
				refs["mood"].add_theme_stylebox_override("fill", _bar_fill(HFUI.mood_color(float(c["mood"]))))
				refs["mood_value"].text = "%d" % int(c["mood"])
				refs["mood_value"].add_theme_color_override("font_color", HFUI.mood_color(float(c["mood"])))
		"colonist":
			var c := sim.colonist_by_id(inspector_colonist_id)
			if c.is_empty():
				close_inspector()
				return
			if inspector_refs.has("identity_status"):
				inspector_refs["identity_status"].text = sim.colonist_status_text(c)
			if inspector_refs.has("mood_value"):
				var mood_color := HFUI.mood_color(float(c["mood"]))
				inspector_refs["mood_value"].text = "%d" % int(c["mood"])
				inspector_refs["mood_value"].add_theme_color_override("font_color", mood_color)
				inspector_refs["mood_label"].text = _mood_description(float(c["mood"]))
				inspector_refs["mood_label"].add_theme_color_override("font_color", mood_color)
				inspector_refs["mood_bar"].value = float(c["mood"])
				inspector_refs["mood_bar"].add_theme_stylebox_override("fill", _bar_fill(mood_color))
			for key in ["hunger", "fatigue", "warmth", "hygiene"]:
				var refs: Dictionary = inspector_refs.get("need_" + key, {})
				if refs.is_empty():
					continue
				var value := float(c["needs"].get(key, 0.0))
				refs["bar"].value = value
				refs["value"].text = "%d" % int(value)
			if inspector_refs.has("health_bar"):
				inspector_refs["health_bar"].value = float(c["health"])
				inspector_refs["health_value"].text = "%d" % int(c["health"])
				var notes: Array = []
				if float(c["illness"]) > 0.0:
					notes.append("Illness %d%%" % int(c["illness"]))
				if float(c["injury"]) > 0.0:
					notes.append("Injury %d%%" % int(c["injury"]))
				inspector_refs["health_note"].text = " · ".join(notes) if not notes.is_empty() else "No active injury or illness."
			if inspector_refs.has("work_status"):
				inspector_refs["work_status"].text = sim.colonist_status_text(c)
			for skill_id in HFDefs.SKILLS.keys():
				var refs: Dictionary = inspector_refs.get("skill_" + str(skill_id), {})
				if refs.is_empty():
					continue
				var value := int(round(sim.skill_value(c, str(skill_id))))
				refs["bar"].value = float(value)
				refs["number"].text = str(value)
			_refresh_mood_reasons(c)
			_refresh_relationships(c)
		"building":
			var b := sim.get_building(inspector_building_id)
			if b.is_empty():
				close_inspector()
				return
			if inspector_refs.has("building_status"):
				inspector_refs["building_status"].text = _building_status(b)
			if inspector_refs.has("building_hp"):
				inspector_refs["building_hp"].value = float(b.get("hp", 0.0))
				inspector_refs["building_hp"].add_theme_stylebox_override("fill", _bar_fill(HFUI.need_color(float(b.get("hp", 0.0)) / maxf(1.0, float(b.get("max_hp", 100.0))) * 100.0)))
				inspector_refs["building_hp_label"].text = "%d / %d" % [int(b.get("hp", 0.0)), int(b.get("max_hp", 100.0))]
			if inspector_refs.has("build_progress"):
				for job in sim.jobs:
					if int(job.get("building_id", -1)) == int(b["id"]) and str(job.get("type", "")) == "build":
						inspector_refs["build_progress"].value = clampf(float(job.get("progress", 0.0)) / maxf(0.01, float(job.get("work_required", 1.0))) * 100.0, 0.0, 100.0)
			if inspector_refs.has("farm_growth"):
				inspector_refs["farm_growth"].value = float(b.get("growth", 0.0))
				inspector_refs["farm_status"].text = sim.farm_status(b)
			if inspector_refs.has("beds"):
				var beds := int(HFDefs.BUILDINGS.get(str(b["key"]), {}).get("beds", 0))
				inspector_refs["beds"].text = "%d of %d beds occupied" % [b.get("occupants", []).size(), beds]
			if inspector_refs.has("storage"):
				inspector_refs["storage"].text = "%d / %d total colony storage" % [int(sim.storage_used()), int(sim.storage_capacity())]

func _bar_fill(color: Color) -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 0
	fill.corner_radius_top_right = 0
	fill.corner_radius_bottom_left = 0
	fill.corner_radius_bottom_right = 0
	return fill

func _refresh_mood_reasons(c: Dictionary) -> void:
	var box: VBoxContainer = inspector_refs.get("mood_reasons")
	if box == null:
		return
	var signature := ""
	var reasons := sim.mood_reason_list(c)
	for reason in reasons:
		signature += str(reason["label"]) + str(int(reason["value"]))
	if box.get_meta("signature", "") == signature:
		return
	box.set_meta("signature", signature)
	for child in box.get_children():
		child.queue_free()
	if reasons.is_empty():
		box.add_child(HFUI.label("No strong feelings either way.", 10, HFUI.SUBTLE))
		return
	for i in range(mini(5, reasons.size())):
		var reason: Dictionary = reasons[i]
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := HFUI.label(str(reason["label"]), 10, HFUI.MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var value := float(reason["value"])
		var number := HFUI.medium_label("%s%d" % ["+" if value > 0.0 else "", int(round(value))], 10, HFUI.GREEN if value > 0.0 else HFUI.RED)
		row.add_child(number)

func _refresh_relationships(c: Dictionary) -> void:
	var box: VBoxContainer = inspector_refs.get("relationships")
	if box == null:
		return
	var signature := ""
	for relationship in sim.relationship_list(c):
		signature += str(relationship["name"]) + str(relationship["value"])
	if box.get_meta("signature", "") == signature:
		return
	box.set_meta("signature", signature)
	for child in box.get_children():
		child.queue_free()
	var relationships := sim.relationship_list(c)
	if relationships.is_empty():
		box.add_child(HFUI.label("Has not formed close bonds yet.", 10, HFUI.SUBTLE))
		return
	for i in range(mini(6, relationships.size())):
		var relationship: Dictionary = relationships[i]
		var row := HBoxContainer.new()
		box.add_child(row)
		var name := HFUI.label(str(relationship["name"]), 10, HFUI.PARCHMENT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var value := int(relationship["value"])
		var color := HFUI.GREEN if value >= 15 else (HFUI.RED if value <= -15 else HFUI.MUTED)
		var number := HFUI.medium_label("%s%d" % ["+" if value > 0 else "", value], 10, color)
		row.add_child(number)

# -----------------------------------------------------------------------------
# Overlays
# -----------------------------------------------------------------------------

func _build_overlays() -> void:
	_build_work_overlay()
	_build_help_overlay()
	_build_pause_overlay()
	_build_cloud_overlay()
	_build_advisor_overlay()
	_build_confirm_overlay()
	_build_game_over_overlay()

func _make_overlay(width: float, height: float, dim_alpha: float = 0.72) -> Dictionary:
	var root := Control.new()
	HFUI.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	HFUI.full_rect(dim)
	dim.color = Color(0.015, 0.025, 0.02, dim_alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	HFUI.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := HFUI.panel(Color("#141f19"), Color("#5a6d53"), 14.0, 2)
	panel.custom_minimum_size = Vector2(width, height)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	return {"root": root, "panel": panel, "body": body}

func _build_work_overlay() -> void:
	var shell := _make_overlay(1120, 620, 0.72)
	work_overlay = shell["root"]
	work_body = shell["body"]
	work_overlay.visible = false

func _open_work() -> void:
	_rebuild_work_matrix()
	work_overlay.visible = true
	work_overlay.move_to_front()
	_set_rail_active("work")

func _rebuild_work_matrix() -> void:
	for child in work_body.get_children():
		child.queue_free()
	var header := HBoxContainer.new()
	work_body.add_child(header)
	var title := HFUI.eyebrow("Work rota", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("CLOSE", 64, 11)
	close.custom_minimum_size = Vector2(64, 25)
	close.pressed.connect(_close_work)
	header.add_child(close)
	var subtitle := HFUI.label("Colonists choose work autonomously. Higher priorities are picked first; 0 means never. Emergencies always rise to the top.", 11, HFUI.MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	work_body.add_child(subtitle)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 7)
	work_body.add_child(legend)
	for entry in [[0, "Never"], [1, "Low"], [2, "Normal"], [3, "High"], [4, "Urgent"]]:
		var chip := HFUI.label("%d  %s" % [int(entry[0]), str(entry[1])], 10, _priority_text_color(int(entry[0])))
		chip.add_theme_stylebox_override("normal", HFUI.style_box(_priority_bg(int(entry[0])), _priority_border(int(entry[0])), 5.0, 1, 0))
		legend.add_child(chip)
	legend.add_child(HFUI.h_spacer(8))
	legend.add_child(HFUI.label("Click a cell to cycle its priority.", 10, HFUI.SUBTLE))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	work_body.add_child(scroll)
	var table := VBoxContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 2)
	scroll.add_child(table)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 2)
	table.add_child(header_row)
	var name_head := HFUI.eyebrow("Colonist", HFUI.MUTED)
	name_head.custom_minimum_size = Vector2(172, 0)
	header_row.add_child(name_head)
	for job_id in HFDefs.JOB_ORDER:
		var label := HFUI.eyebrow(str(HFDefs.JOBS[job_id]["short"]), HFUI.SUBTLE)
		label.custom_minimum_size = Vector2(86, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.tooltip_text = str(HFDefs.JOBS[job_id]["desc"])
		header_row.add_child(label)
	for c in sim.colonists:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		table.add_child(row)
		var name_label := HFUI.medium_label(str(c["first_name"]), 11, HFUI.PARCHMENT)
		name_label.custom_minimum_size = Vector2(172, 0)
		name_label.tooltip_text = str(c["name"]) + " · " + sim.colonist_status_text(c)
		row.add_child(name_label)
		for job_id in HFDefs.JOB_ORDER:
			var value := int(c.get("priorities", {}).get(job_id, 0))
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(86, 28)
			cell.text = str(value)
			cell.focus_mode = Control.FOCUS_NONE
			cell.tooltip_text = "%s · %s" % [str(HFDefs.JOBS[job_id]["name"]), _priority_name(value)]
			cell.add_theme_font_override("font", HFUI.medium_font())
			cell.add_theme_font_size_override("font_size", 12)
			cell.add_theme_color_override("font_color", _priority_text_color(value))
			cell.add_theme_stylebox_override("normal", HFUI.style_box(_priority_bg(value), _priority_border(value), 4.0, 1, 0))
			cell.add_theme_stylebox_override("hover", HFUI.style_box(_priority_bg(value).lightened(0.08), HFUI.AMBER, 4.0, 2, 0))
			cell.add_theme_stylebox_override("pressed", HFUI.style_box(_priority_bg(value).darkened(0.08), HFUI.AMBER_LIGHT, 4.0, 1, 0))
			cell.pressed.connect(_on_priority_cell_pressed.bind(cell, int(c["id"]), str(job_id)))
			row.add_child(cell)

func _on_priority_cell_pressed(cell: Button, colonist_id: int, job_id: String) -> void:
	var current := sim.get_priority(colonist_id, job_id)
	var value := (current + 1) % 5
	sim.set_priority(colonist_id, job_id, value)
	cell.text = str(value)
	cell.tooltip_text = "%s · %s" % [str(HFDefs.JOBS[job_id]["name"]), _priority_name(value)]
	cell.add_theme_color_override("font_color", _priority_text_color(value))
	cell.add_theme_stylebox_override("normal", HFUI.style_box(_priority_bg(value), _priority_border(value), 4.0, 1, 0))
	priority_changed.emit(colonist_id, job_id, value)

func _priority_name(value: int) -> String:
	return ["Never", "Low", "Normal", "High", "Urgent"][clampi(value, 0, 4)]

func _priority_bg(value: int) -> Color:
	return [Color("#1c241e"), Color("#1c2b31"), Color("#203126"), Color("#342b1d"), Color("#3c221c")][clampi(value, 0, 4)]

func _priority_border(value: int) -> Color:
	return [Color("#3d4b3f"), Color("#43606b"), Color("#4d6d4b"), Color("#876834"), Color("#8b4939")][clampi(value, 0, 4)]

func _priority_text_color(value: int) -> Color:
	return [HFUI.SUBTLE, Color("#8fb4c1"), HFUI.GREEN, HFUI.AMBER, Color("#e39a86")][clampi(value, 0, 4)]

func _close_work() -> void:
	work_overlay.visible = false
	_set_rail_active("")
	if inspector_panel.visible:
		_set_rail_active("people")

func _build_help_overlay() -> void:
	var shell := _make_overlay(980, 620, 0.78)
	help_overlay = shell["root"]
	var body: VBoxContainer = shell["body"]
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := HFUI.eyebrow("How to play", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("CLOSE", 64, 11)
	close.custom_minimum_size = Vector2(64, 25)
	close.pressed.connect(_close_help)
	header.add_child(close)
	body.add_child(HFUI.label("A colony is a hundred small decisions. These are the ones that keep the hearth burning.", 12, HFUI.MUTED))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	_add_help_card(columns, "THE FIRST DAYS", [
		["Build a cabin", "Beds restore energy and warmth. Sleeping on the ground leaves colonists cold and unhappy."],
		["Break ground", "Farm plots grow grain or pumpkins when the weather cooperates. Sowing and harvesting happen automatically."],
		["Build a cookhouse", "Raw food fills bellies, but warm meals restore more and lift moods. Cooks work automatically when ingredients are available."],
		["Watch the stores", "Food spoils faster in heat. A food shed preserves it. Use the top bar to see total nutrition."],
	])
	_add_help_card(columns, "THE WORK ROTA", [
		["Set priorities", "Open Work and click a cell to cycle 0–4. Higher priorities are chosen first. 0 means never."],
		["They act for themselves", "Colonists eat, sleep, wash, warm up, socialize, and seek care without being told."],
		["Emergencies come first", "Fire, injury, hunger, and predators interrupt ordinary work. Give firefighters and doctors high priorities."],
		["Inspect everyone", "Click a settler or use People to see needs, mood reasons, skills, health, and relationships."],
	])
	_add_help_card(columns, "A LIVING WORLD", [
		["Time and weather", "Seasons change every eight days. Temperature, rain, snow, storms, and heat affect crops, travel, mood, and fire."],
		["Injury and illness", "Cold, poor hygiene, raw food, accidents, and predators cause harm. Clinics turn herbs and medicine into recovery."],
		["Wildlife", "Deer and rabbits can be hunted. Wolves and bears fight back. Hunters with combat skill are safer."],
		["Stories write themselves", "Relationships grow or sour. Deaths are remembered. The log records the small moments that make a colony."],
	])
	var controls_panel := HFUI.panel(Color("#1a2820"), Color("#405441"), 8.0, 1)
	body.add_child(controls_panel)
	var controls := VBoxContainer.new()
	controls_panel.add_child(controls)
	controls.add_child(HFUI.eyebrow("Controls", HFUI.AMBER))
	controls.add_child(HFUI.label("WASD / arrows: move   ·   Q / E: smooth rotate   ·   R / F: tilt   ·   0: reset view   ·   Wheel: zoom   ·   Middle-drag: pan   ·   Right-click: cancel", 10, HFUI.MUTED))
	controls.add_child(HFUI.label("Space: pause / resume   ·   F6: save   ·   F10: load autosave   ·   Esc: close menus or pause", 10, HFUI.MUTED))
	controls.add_child(HFUI.label("The colony autosaves every dawn. New colonies overwrite the previous save at the next autosave.", 10, HFUI.SUBTLE))

func _add_help_card(parent: HBoxContainer, title: String, entries: Array) -> void:
	var panel := HFUI.panel(Color("#18251d"), Color("#405441"), 10.0, 1)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	box.add_child(HFUI.eyebrow(title, HFUI.AMBER))
	for entry in entries:
		var heading := HFUI.medium_label(str(entry[0]), 11, HFUI.PARCHMENT)
		box.add_child(heading)
		var desc := HFUI.label(str(entry[1]), 10, HFUI.MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)

func _open_help(from_title: bool = false) -> void:
	_help_return_to_pause = pause_overlay.visible and not from_title
	pause_overlay.visible = false
	help_overlay.visible = true
	help_overlay.move_to_front()

func _close_help() -> void:
	help_overlay.visible = false
	if _help_return_to_pause:
		_help_return_to_pause = false
		pause_overlay.visible = true
		pause_overlay.move_to_front()

func _build_pause_overlay() -> void:
	var shell := _make_overlay(540, 575, 0.74)
	pause_overlay = shell["root"]
	var body: VBoxContainer = shell["body"]
	body.add_child(HFUI.eyebrow("Colony paused", HFUI.AMBER))
	var title := HFUI.display_label("The hearth waits.", 30, HFUI.PARCHMENT)
	body.add_child(title)
	var pause_date := HFUI.label("", 12, HFUI.MUTED)
	pause_date.name = "PauseDate"
	body.add_child(pause_date)
	body.add_child(HFUI.spacer(4))
	var stats_panel := HFUI.panel(Color("#1a2820"), Color("#405441"), 10.0, 1)
	body.add_child(stats_panel)
	var stats := VBoxContainer.new()
	stats.name = "PauseStats"
	stats_panel.add_child(stats)
	body.add_child(HFUI.spacer(4))
	var resume := HFUI.primary_button("RESUME COLONY", 420)
	resume.custom_minimum_size.y = 42
	resume.pressed.connect(_resume_game)
	body.add_child(resume)
	var save := HFUI.button("SAVE COLONY", 420)
	save.custom_minimum_size.y = 36
	save.pressed.connect(_save_from_pause)
	body.add_child(save)
	var load_button := HFUI.button("LOAD LAST AUTOSAVE", 420)
	load_button.custom_minimum_size.y = 36
	load_button.pressed.connect(_confirm_load_from_pause)
	body.add_child(load_button)
	var help := HFUI.button("HOW TO PLAY", 420)
	help.custom_minimum_size.y = 36
	help.pressed.connect(func(): _open_help(false))
	body.add_child(help)
	var cloud := HFUI.button("CLOUD SAVES & RANKS", 420)
	cloud.custom_minimum_size.y = 36
	cloud.pressed.connect(func(): _open_cloud(false))
	body.add_child(cloud)
	var title_button := HFUI.button("RETURN TO TITLE", 420)
	title_button.custom_minimum_size.y = 36
	title_button.pressed.connect(_confirm_return_title)
	body.add_child(title_button)
	var note := HFUI.label("Progress is saved automatically at dawn.", 10, HFUI.SUBTLE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(note)

func _build_cloud_overlay() -> void:
	var shell := _make_overlay(940, 660, 0.82)
	cloud_overlay = shell["root"]
	cloud_body = shell["body"]
	cloud_overlay.visible = false

func _open_cloud(from_title: bool = false) -> void:
	_cloud_return_to_pause = pause_overlay.visible and not from_title
	pause_overlay.visible = false
	help_overlay.visible = false
	cloud_overlay.visible = true
	cloud_overlay.move_to_front()
	CloudServices.refresh_session()
	cloud_saves_loaded = false
	cloud_board_data = {}
	_rebuild_cloud_overlay()
	if CloudServices.is_online():
		_cloud_list_saves()
		_cloud_list_board()

func _close_cloud() -> void:
	cloud_overlay.visible = false
	if _cloud_return_to_pause and game_ui.visible:
		pause_overlay.visible = true
		pause_overlay.move_to_front()
	_cloud_return_to_pause = false

func _on_cloud_session_changed(_state: Dictionary) -> void:
	if cloud_overlay != null and cloud_overlay.visible:
		_rebuild_cloud_overlay()
		if CloudServices.is_online() and CloudServices.is_signed_in():
			_cloud_list_saves()

func _rebuild_cloud_overlay() -> void:
	if cloud_body == null:
		return
	for child in cloud_body.get_children():
		child.queue_free()
	var header := HBoxContainer.new()
	cloud_body.add_child(header)
	var title := HFUI.eyebrow("Cloud saves & survival ranks", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("CLOSE", 64, 11)
	close.custom_minimum_size = Vector2(64, 25)
	close.pressed.connect(_close_cloud)
	header.add_child(close)
	var subtitle := HFUI.label("Signed-in colonies can travel between devices. Rankings are casual, client-reported records of what your settlement endured.", 11, HFUI.MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cloud_body.add_child(subtitle)
	cloud_body.add_child(_build_cloud_status())
	if not cloud_message.is_empty():
		var message := HFUI.label(cloud_message, 11, HFUI.PARCHMENT)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.add_theme_stylebox_override("normal", HFUI.style_box(Color("#1b2921"), Color("#536650"), 6.0, 1, 0))
		cloud_body.add_child(message)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cloud_body.add_child(scroll)
	cloud_scroll_box = VBoxContainer.new()
	cloud_scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cloud_scroll_box.add_theme_constant_override("separation", 9)
	scroll.add_child(cloud_scroll_box)
	_build_cloud_saves_section()
	_build_cloud_leaderboard_section()

func _build_cloud_status() -> Control:
	var panel := HFUI.panel(Color("#18251d"), Color("#405441"), 9.0, 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var status_box := VBoxContainer.new()
	status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status_box)
	cloud_status_label = HFUI.medium_label("", 12, HFUI.PARCHMENT)
	status_box.add_child(cloud_status_label)
	var detail := HFUI.label("", 10, HFUI.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(detail)
	if CloudServices.is_signed_in():
		cloud_status_label.text = "Signed in as %s" % CloudServices.user_name()
		detail.text = "Cloud slots and personal rank are available on this account."
		var sign_out := HFUI.button("SIGN OUT", 86, 10)
		sign_out.custom_minimum_size = Vector2(86, 30)
		sign_out.pressed.connect(func(): CloudServices.sign_out())
		row.add_child(sign_out)
	elif CloudServices.is_online():
		cloud_status_label.text = "Not signed in"
		detail.text = "Sign in with Manus to sync saves and claim a personal rank."
		var sign_in := HFUI.primary_button("SIGN IN WITH MANUS", 164)
		sign_in.custom_minimum_size = Vector2(164, 32)
		sign_in.pressed.connect(func(): CloudServices.sign_in())
		row.add_child(sign_in)
		var standalone := HFUI.button("OPEN STANDALONE", 130, 10)
		standalone.custom_minimum_size = Vector2(130, 32)
		standalone.tooltip_text = "Open the standalone game if sign-in is blocked in this embedded view."
		standalone.pressed.connect(func(): CloudServices.open_standalone())
		row.add_child(standalone)
	else:
		cloud_status_label.text = "Online features are offline here"
		detail.text = "The resident preview cannot reach the managed backend. Open a saved checkpoint or published build for cloud saves and rankings. Local play and local saves still work."
		var retry := HFUI.button("RETRY CONNECTION", 138, 10)
		retry.custom_minimum_size = Vector2(138, 32)
		retry.pressed.connect(func():
			CloudServices.refresh_session()
			_rebuild_cloud_overlay()
		)
		row.add_child(retry)
		var standalone_offline := HFUI.button("OPEN STANDALONE", 130, 10)
		standalone_offline.custom_minimum_size = Vector2(130, 32)
		standalone_offline.pressed.connect(func(): CloudServices.open_standalone())
		row.add_child(standalone_offline)
	return panel

func _build_cloud_saves_section() -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 5)
	cloud_scroll_box.add_child(section)
	var header := HBoxContainer.new()
	section.add_child(header)
	var label := HFUI.eyebrow("Cloud save slots", HFUI.AMBER)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var refresh := HFUI.button("REFRESH", 70, 10)
	refresh.custom_minimum_size = Vector2(70, 26)
	refresh.pressed.connect(func(): _cloud_list_saves())
	header.add_child(refresh)
	if not CloudServices.is_signed_in():
		section.add_child(HFUI.label("Sign in to store up to four colony snapshots in the cloud.", 10, HFUI.MUTED))
		return
	if not cloud_saves_loaded:
		section.add_child(HFUI.label("Loading cloud saves...", 10, HFUI.MUTED))
		return
	for entry in [["auto", "Dawn autosave"], ["manual-1", "Cloud Slot 1"], ["manual-2", "Cloud Slot 2"], ["manual-3", "Cloud Slot 3"]]:
		var slot_id := str(entry[0])
		var fallback := str(entry[1])
		var meta = cloud_slots.get(slot_id)
		section.add_child(_build_cloud_slot_row(slot_id, fallback, meta))

func _build_cloud_slot_row(slot_id: String, fallback: String, meta) -> Control:
	var panel := HFUI.panel(Color("#17231c"), Color("#3e5140"), 8.0, 1)
	panel.custom_minimum_size.y = 52
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var has_meta := meta is Dictionary
	var label := HFUI.medium_label(str(meta.get("label", fallback)) if has_meta else fallback, 11, HFUI.PARCHMENT)
	info.add_child(label)
	var detail := "Empty slot"
	if has_meta:
		detail = "Day %d · %d survivors · Mood %d · %s" % [int(meta.get("day", 1)), int(meta.get("population", 0)), int(meta.get("mood", 50)), _short_cloud_time(meta.get("updatedAt", ""))]
	info.add_child(HFUI.label(detail, 9, HFUI.MUTED))
	var save_button := HFUI.button("SAVE", 56, 10)
	save_button.custom_minimum_size = Vector2(56, 28)
	save_button.tooltip_text = "Upload the current colony into this slot."
	save_button.pressed.connect(func(): _cloud_save_slot(slot_id, fallback))
	row.add_child(save_button)
	if has_meta:
		var load_button := HFUI.button("LOAD", 56, 10)
		load_button.custom_minimum_size = Vector2(56, 28)
		load_button.pressed.connect(func(): _cloud_confirm_load(slot_id))
		row.add_child(load_button)
		var delete_button := HFUI.button("DELETE", 62, 10)
		delete_button.custom_minimum_size = Vector2(62, 28)
		delete_button.pressed.connect(func(): _cloud_confirm_delete(slot_id))
		row.add_child(delete_button)
	return panel

func _build_cloud_leaderboard_section() -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 5)
	cloud_scroll_box.add_child(section)
	var header := HBoxContainer.new()
	section.add_child(header)
	var label := HFUI.eyebrow("Global survival leaderboard", HFUI.AMBER)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var refresh := HFUI.button("REFRESH", 70, 10)
	refresh.custom_minimum_size = Vector2(70, 26)
	refresh.pressed.connect(func(): _cloud_list_board())
	header.add_child(refresh)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	section.add_child(tabs)
	for board in CloudServices.BOARDS:
		var board_id := str(board.get("id", ""))
		var tab := HFUI.button(str(board.get("label", board_id)), 142, 10)
		tab.custom_minimum_size = Vector2(142, 28)
		if board_id == cloud_board_id:
			tab.add_theme_stylebox_override("normal", HFUI.style_box(Color("#6f5b32"), HFUI.AMBER, 7.0, 2, 0))
			tab.add_theme_color_override("font_color", HFUI.PARCHMENT)
		tab.pressed.connect(func(): _select_cloud_board(board_id))
		tabs.add_child(tab)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	section.add_child(body)
	if cloud_board_loading:
		body.add_child(HFUI.label("Reading the global board...", 10, HFUI.MUTED))
	elif cloud_board_data.is_empty():
		body.add_child(HFUI.label("No ranking data loaded yet. Sign in and refresh, or publish a colony to begin.", 10, HFUI.MUTED))
	else:
		var entries: Array = cloud_board_data.get("entries", [])
		if entries.is_empty():
			body.add_child(HFUI.label("No survivors have claimed this record yet. Yours could be first.", 10, HFUI.MUTED))
		else:
			for entry in entries:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 7)
				body.add_child(row)
				var rank := HFUI.medium_label("#%d" % int(entry.get("rank", 0)), 10, HFUI.AMBER)
				rank.custom_minimum_size = Vector2(34, 0)
				row.add_child(rank)
				var name := HFUI.label(str(entry.get("displayName", "Survivor")), 10, HFUI.PARCHMENT)
				name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(name)
				row.add_child(HFUI.medium_label(_format_cloud_score(cloud_board_id, int(entry.get("score", 0))), 10, HFUI.GREEN))
		var my_rank = cloud_board_data.get("myRank")
		if my_rank is Dictionary:
			body.add_child(HFUI.label("Your best: #%d · %s" % [int(my_rank.get("rank", 0)), _format_cloud_score(cloud_board_id, int(my_rank.get("score", 0)))], 10, HFUI.AMBER))
	var publish := HFUI.primary_button("PUBLISH CURRENT COLONY", 240)
	publish.custom_minimum_size = Vector2(240, 32)
	publish.disabled = sim == null or not CloudServices.is_signed_in()
	publish.tooltip_text = "Submit the current days survived, population, and average mood as casual records." if sim != null else "Start a colony before publishing a record."
	publish.pressed.connect(func(): _publish_cloud_colony())
	section.add_child(publish)
	section.add_child(HFUI.label("Rankings use days survived, current population, and average mood. Scores are client-reported and not verified competitive results.", 9, HFUI.SUBTLE))

func _cloud_list_saves() -> void:
	if not CloudServices.is_signed_in():
		cloud_slots = {}
		cloud_saves_loaded = true
		_rebuild_cloud_overlay()
		return
	cloud_saves_loaded = false
	cloud_message = "Loading cloud saves..."
	_rebuild_cloud_overlay()
	CloudServices.list_saves(func(result: Dictionary) -> void: _on_cloud_saves(result))

func _on_cloud_saves(result: Dictionary) -> void:
	cloud_saves_loaded = true
	if bool(result.get("ok", false)):
		cloud_slots = {}
		for item in result.get("data", {}).get("slots", []):
			if item is Dictionary:
				cloud_slots[str(item.get("slot", ""))] = item
		cloud_message = ""
	else:
		cloud_message = _friendly_cloud_error(str(result.get("error", "cloud_unavailable")))
	_rebuild_cloud_overlay()

func _cloud_save_slot(slot_id: String, label: String) -> void:
	if sim == null:
		cloud_message = "Start or load a colony before saving to the cloud."
		_rebuild_cloud_overlay()
		return
	if not CloudServices.is_signed_in():
		cloud_message = "Sign in with Manus to use cloud saves."
		_rebuild_cloud_overlay()
		return
	cloud_message = "Uploading the colony..."
	_rebuild_cloud_overlay()
	var save_label := label if slot_id != "auto" else "Dawn autosave"
	CloudServices.save_current(sim, slot_id, save_label, func(result: Dictionary) -> void: _on_cloud_save(result, label))

func _on_cloud_save(result: Dictionary, label: String) -> void:
	if bool(result.get("ok", false)):
		cloud_message = "%s uploaded." % label
		toast("Cloud save uploaded.")
		_cloud_list_saves()
	else:
		cloud_message = _friendly_cloud_error(str(result.get("error", "cloud_unavailable")))
		toast(cloud_message, true)
		_rebuild_cloud_overlay()

func _cloud_confirm_load(slot_id: String) -> void:
	_show_confirm("Load this cloud save? Progress since your last local save will be replaced.", func():
		cloud_message = "Downloading the colony..."
		_rebuild_cloud_overlay()
		CloudServices.load_slot(slot_id, func(result: Dictionary) -> void: _on_cloud_load(result))
	)

func _on_cloud_load(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		var data := str(result.get("data", {}).get("data", ""))
		if data.is_empty():
			cloud_message = "That cloud save is empty."
			_rebuild_cloud_overlay()
			return
		cloud_overlay.visible = false
		cloud_load_ready.emit(data)
		toast("Cloud colony downloaded.")
	else:
		cloud_message = _friendly_cloud_error(str(result.get("error", "cloud_unavailable")))
		toast(cloud_message, true)
		_rebuild_cloud_overlay()

func _cloud_confirm_delete(slot_id: String) -> void:
	_show_confirm("Delete this cloud save permanently?", func():
		cloud_message = "Deleting cloud save..."
		_rebuild_cloud_overlay()
		CloudServices.delete_slot(slot_id, func(result: Dictionary) -> void: _on_cloud_delete(result))
	)

func _on_cloud_delete(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		cloud_message = "Cloud save deleted."
		_cloud_list_saves()
	else:
		cloud_message = _friendly_cloud_error(str(result.get("error", "cloud_unavailable")))
		_rebuild_cloud_overlay()

func _cloud_list_board() -> void:
	if not CloudServices.is_online():
		return
	cloud_board_loading = true
	_rebuild_cloud_overlay()
	CloudServices.list_board(cloud_board_id, func(result: Dictionary) -> void: _on_cloud_board(result))

func _on_cloud_board(result: Dictionary) -> void:
	cloud_board_loading = false
	if bool(result.get("ok", false)):
		cloud_board_data = result.get("data", {})
		cloud_message = ""
	else:
		cloud_message = _friendly_cloud_error(str(result.get("error", "leaderboard_unavailable")))
	_rebuild_cloud_overlay()

func _select_cloud_board(board_id: String) -> void:
	cloud_board_id = board_id
	cloud_board_data = {}
	_cloud_list_board()

func _publish_cloud_colony() -> void:
	if sim == null:
		cloud_message = "Start a colony before publishing a record."
		_rebuild_cloud_overlay()
		return
	if not CloudServices.is_signed_in():
		cloud_message = "Sign in with Manus to publish a survival record."
		_rebuild_cloud_overlay()
		return
	cloud_message = "Publishing the colony's record..."
	_rebuild_cloud_overlay()
	CloudServices.publish_colony(sim)

func _on_cloud_publish_finished(result: Dictionary) -> void:
	var results: Array = result.get("results", [])
	var accepted := 0
	for entry in results:
		if bool(entry.get("ok", false)):
			accepted += 1
	if accepted > 0:
		cloud_message = "Published to %d of %d boards." % [accepted, results.size()]
		toast("Survival record published.")
	else:
		cloud_message = "The record could not be published. Check your connection and sign-in."
		toast(cloud_message, true)
	_cloud_list_board()

func _format_cloud_score(board_id: String, score: int) -> String:
	match board_id:
		"survival-days-v1":
			return "%d days" % score
		"population-v1":
			return "%d survivors" % score
		"mood-v1":
			return "%.2f mood" % (float(score) / 100.0)
	return str(score)

func _short_cloud_time(value) -> String:
	var text := str(value)
	if text.length() >= 16:
		return text.substr(0, 16).replace("T", " ")
	return text

func _friendly_cloud_error(code: String) -> String:
	match code:
		"online_preview_required":
			return "Online features need a saved checkpoint or published build."
		"sign_in_required", "account_session_required":
			return "Sign in with Manus to use this feature."
		"auth_bootstrap_missing":
			return "The online bridge did not load. Local play is still available."
		"cloud_save_not_found":
			return "That cloud save no longer exists."
		"invalid_save_payload":
			return "The colony save was rejected by the server."
		"leaderboard_unavailable":
			return "The leaderboard is unavailable right now."
		"board_not_found":
			return "That leaderboard is not configured yet."
	return code.replace("_", " ").capitalize()

func _build_advisor_overlay() -> void:
	var shell := _make_overlay(760, 590, 0.78)
	advisor_overlay = shell["root"]
	advisor_body = shell["body"]
	advisor_overlay.visible = false

func _open_advisor() -> void:
	_close_panels(false)
	_rebuild_advisor()
	advisor_overlay.visible = true
	advisor_overlay.move_to_front()
	_set_rail_active("advisor")

func _close_advisor() -> void:
	advisor_overlay.visible = false
	_set_rail_active("")

func _rebuild_advisor() -> void:
	if advisor_body == null:
		return
	for child in advisor_body.get_children():
		child.queue_free()
	var header := HBoxContainer.new()
	advisor_body.add_child(header)
	var title := HFUI.eyebrow("Hearthmind colony advisor", HFUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := HFUI.button("CLOSE", 64, 11)
	close.custom_minimum_size = Vector2(64, 25)
	close.pressed.connect(_close_advisor)
	header.add_child(close)
	var intro := HFUI.label("A local decision system reads the settlement state and turns it into plain-language priorities. It never pauses the simulation or sends your colony data anywhere.", 11, HFUI.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advisor_body.add_child(intro)
	if sim == null:
		advisor_body.add_child(HFUI.label("Start a colony to receive live recommendations.", 13, HFUI.PARCHMENT))
		return
	var snapshot := HFUI.panel(Color("#18251d"), Color("#405441"), 9.0, 1)
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 3)
	snapshot.add_child(summary)
	summary.add_child(HFUI.eyebrow("SETTLEMENT READOUT", HFUI.AMBER))
	summary.add_child(HFUI.label("Day %d · %d survivors · Mood %d/100 · %s · %s" % [sim.absolute_day, sim.living_count(), int(sim.average_mood()), sim.weather_name(), sim.temperature_text()], 11, HFUI.PARCHMENT))
	summary.add_child(HFUI.label("Stores: %d food nutrition · %d wood · %d stone · %d herbs · %d/%d storage" % [int(sim.food_total()), sim.resource_qty("wood"), sim.resource_qty("stone"), sim.resource_qty("herbs"), int(sim.storage_used()), int(sim.storage_capacity())], 10, HFUI.MUTED))
	advisor_body.add_child(snapshot)
	var recommendations := _advisor_recommendations()
	var rec_header := HBoxContainer.new()
	advisor_body.add_child(rec_header)
	var rec_title := HFUI.eyebrow("PRIORITIZED RECOMMENDATIONS", HFUI.AMBER)
	rec_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_header.add_child(rec_title)
	var refresh := HFUI.button("REFRESH", 72, 10)
	refresh.custom_minimum_size = Vector2(72, 25)
	refresh.pressed.connect(_rebuild_advisor)
	rec_header.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	advisor_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if recommendations.is_empty():
		list.add_child(HFUI.label("No urgent risks detected. Let the colony breathe, then use the Work rota to shape its next season.", 12, HFUI.GREEN))
	else:
		for rec in recommendations:
			var card := HFUI.panel(Color("#17231c"), Color(str(rec.get("border", "#405441"))), 8.0, 1)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			card.add_child(row)
			var badge := HFUI.medium_label(str(rec.get("priority", "NEXT")), 10, HFUI.AMBER)
			badge.custom_minimum_size = Vector2(58, 0)
			row.add_child(badge)
			var copy := VBoxContainer.new()
			copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(copy)
			copy.add_child(HFUI.medium_label(str(rec.get("title", "Recommendation")), 12, HFUI.PARCHMENT))
			var detail := HFUI.label(str(rec.get("detail", "")), 10, HFUI.MUTED)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			copy.add_child(detail)
	var footer := HFUI.label("Advisor mode: deterministic local AI · refreshes whenever this panel opens", 9, HFUI.SUBTLE)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	advisor_body.add_child(footer)

func _advisor_recommendations() -> Array:
	var result: Array = []
	var alerts: Array = sim.active_alerts()
	for alert in alerts:
		var severity := str(alert.get("severity", "warning"))
		var priority := "WATCH"
		var border := "#536650"
		if severity == "danger":
			priority = "NOW"
			border = "#8b4939"
		elif severity == "warning":
			priority = "SOON"
			border = "#876834"
		result.append({"priority": priority, "title": str(alert.get("title", "Colony alert")), "detail": str(alert.get("text", "Review the alert and respond.")), "border": border})
		if result.size() >= 3:
			break
	if sim.food_total() < float(maxi(24, sim.living_count() * 10)):
		result.append({"priority": "SOON", "title": "Protect the food chain", "detail": "Food is below a comfortable reserve. Raise farming, foraging, cooking, and hauling priorities, then consider a food shed before heat or spoilage takes the margin.", "border": "#876834"})
	if sim.resource_qty("wood") < 18:
		result.append({"priority": "NEXT", "title": "Replenish the timber pile", "detail": "Wood is the settlement's flexible buffer for cabins, fuel, tools, and repairs. Keep one gatherer assigned even when the build queue looks quiet.", "border": "#405e49"})
	if sim.storage_capacity() > 0.0 and sim.storage_used() / sim.storage_capacity() > 0.86:
		result.append({"priority": "SOON", "title": "Storage is nearly full", "detail": "Build another stockpile or food shed so haulers can keep supplies under cover and production jobs do not stall at the doorstep.", "border": "#876834"})
	var lowest_name := ""
	var lowest_value := 101.0
	for colonist in sim.colonists:
		var mood := float(colonist.get("mood", 50.0))
		if mood < lowest_value:
			lowest_value = mood
			lowest_name = str(colonist.get("first_name", "A colonist"))
	if lowest_value < 42.0:
		result.append({"priority": "CARE", "title": "%s needs attention" % lowest_name, "detail": "Inspect their mood breakdown and needs. Warmth, sleep, hygiene, social time, and a private bed are usually the fastest recovery levers.", "border": "#6b4f62"})
	if sim.current_temperature() < 3.0 and not sim.has_built("hearth"):
		result.append({"priority": "NOW", "title": "Prepare for cold", "detail": "Temperatures are low and no built hearth was found. Heat keeps colonists alive, improves rest, and protects crops from a bad night.", "border": "#8b4939"})
	if result.size() > 6:
		result.resize(6)
	return result

func _open_pause() -> void:
	if sim == null or game_ui == null or not game_ui.visible or game_over_overlay.visible:
		return
	_speed_before_pause = sim.speed if sim.speed > 0 else 1
	sim.set_speed(0)
	_update_pause_stats()
	pause_overlay.visible = true
	pause_overlay.move_to_front()
	_refresh_speed_buttons()

func _resume_game() -> void:
	pause_overlay.visible = false
	help_overlay.visible = false
	if sim != null:
		sim.set_speed(maxi(1, _speed_before_pause))
	_refresh_speed_buttons()

func _update_pause_stats() -> void:
	if sim == null:
		return
	var date := pause_overlay.find_child("PauseDate", true, false) as Label
	if date != null:
		date.text = "%s · %s · %s · %s" % [sim.date_string(), sim.time_string(), sim.temperature_text(), sim.weather_name()]
	var stats := pause_overlay.find_child("PauseStats", true, false) as VBoxContainer
	if stats != null:
		for child in stats.get_children():
			child.queue_free()
		var rows := [
			["Survivors", "%d / %d" % [sim.colonists.size(), HFDefs.COLONIST_CAP]],
			["Average mood", "%d / 100" % int(sim.average_mood())],
			["Food nutrition", "%d" % int(sim.food_total())],
			["Storage", "%d / %d" % [int(sim.storage_used()), int(sim.storage_capacity())]],
			["Research", sim.get_research_status()],
		]
		for row in rows:
			var h := HBoxContainer.new()
			stats.add_child(h)
			var key := HFUI.label(str(row[0]), 11, HFUI.MUTED)
			key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(key)
			h.add_child(HFUI.medium_label(str(row[1]), 11, HFUI.PARCHMENT))

func _save_from_pause() -> void:
	if sim == null:
		return
	if sim.save_game():
		toast("Colony saved. The hearth is remembered.")
	else:
		toast("The colony could not be saved.", true)

func _confirm_load_from_pause() -> void:
	_show_confirm("Load the last autosave? Progress since that dawn will be lost.", func():
		pause_overlay.visible = false
		load_requested.emit()
	)

func _confirm_return_title() -> void:
	_show_confirm("Return to the title screen? Progress since the last autosave will be lost.", func():
		_close_all_overlays()
		title_requested.emit()
	)

func _build_confirm_overlay() -> void:
	var shell := _make_overlay(520, 250, 0.58)
	confirm_overlay = shell["root"]
	var body: VBoxContainer = shell["body"]
	body.add_child(HFUI.eyebrow("Confirm", HFUI.AMBER))
	confirm_text = HFUI.label("", 14, HFUI.PARCHMENT)
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_text.custom_minimum_size = Vector2(460, 80)
	body.add_child(confirm_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	confirm_yes = HFUI.danger_button("CONFIRM", 220)
	confirm_yes.custom_minimum_size.y = 36
	confirm_yes.pressed.connect(_run_confirm)
	row.add_child(confirm_yes)
	var cancel := HFUI.button("CANCEL", 220)
	cancel.custom_minimum_size.y = 36
	cancel.pressed.connect(_close_confirm)
	row.add_child(cancel)

func _show_confirm(text: String, callback: Callable) -> void:
	confirm_text.text = text
	confirm_callback = callback
	confirm_overlay.visible = true
	confirm_overlay.move_to_front()

func _run_confirm() -> void:
	var callback := confirm_callback
	_close_confirm()
	if callback.is_valid():
		callback.call()

func _close_confirm() -> void:
	confirm_overlay.visible = false
	confirm_callback = Callable()

func _build_game_over_overlay() -> void:
	var shell := _make_overlay(660, 470, 0.84)
	game_over_overlay = shell["root"]
	game_over_body = shell["body"]

func _populate_game_over(summary: Dictionary) -> void:
	for child in game_over_body.get_children():
		child.queue_free()
	game_over_body.add_child(HFUI.eyebrow("The settlement falls silent", HFUI.RED))
	var title := HFUI.title_label("THE LAST HEARTH\nGOES COLD", 38, Color("#e8c1ae"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_body.add_child(title)
	var text := HFUI.label("No colonists remain. The pines will close over the clearing, but the story of what was built here is still yours.", 13, HFUI.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_body.add_child(text)
	var stats_panel := HFUI.panel(Color("#1a2820"), Color("#405441"), 10.0, 1)
	game_over_body.add_child(stats_panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	stats_panel.add_child(grid)
	for entry in [
		["DAYS SURVIVED", str(summary.get("days", 1))],
		["STRUCTURES RAISED", str(summary.get("built", 0))],
		["MEALS COOKED", str(summary.get("meals", 0))],
		["RESOURCES GATHERED", str(summary.get("gathered", 0))],
		["LIVES LOST", str(summary.get("deaths", 0))],
		["FINAL POPULATION", str(summary.get("population", 0))],
	]:
		var box := VBoxContainer.new()
		grid.add_child(box)
		var label := HFUI.eyebrow(str(entry[0]), HFUI.SUBTLE)
		label.add_theme_font_size_override("font_size", 8)
		box.add_child(label)
		box.add_child(HFUI.medium_label(str(entry[1]), 19, HFUI.PARCHMENT))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	game_over_body.add_child(buttons)
	var new_button := HFUI.primary_button("BEGIN AGAIN", 250)
	new_button.custom_minimum_size.y = 42
	new_button.pressed.connect(func(): new_colony_requested.emit())
	buttons.add_child(new_button)
	var load_button := HFUI.button("LOAD LAST AUTOSAVE", 250)
	load_button.custom_minimum_size.y = 42
	load_button.disabled = sim == null or not sim.save_exists()
	load_button.pressed.connect(func(): load_requested.emit())
	buttons.add_child(load_button)
	var title_button := HFUI.button("TITLE SCREEN", 0, 11)
	title_button.custom_minimum_size.y = 42
	title_button.pressed.connect(func(): title_requested.emit())
	buttons.add_child(title_button)

func _close_all_overlays() -> void:
	for overlay in [work_overlay, help_overlay, pause_overlay, confirm_overlay, game_over_overlay, cloud_overlay, advisor_overlay]:
		if overlay != null:
			overlay.visible = false
	_help_return_to_pause = false
	_cloud_return_to_pause = false
	confirm_callback = Callable()

# -----------------------------------------------------------------------------
# Rail, panels, and refresh
# -----------------------------------------------------------------------------

func _on_rail_pressed(name: String) -> void:
	match name:
		"build":
			var opening := not build_panel.visible
			_close_panels(false)
			if opening:
				build_panel.visible = true
				cancel_requested.emit()
				set_tool_state("", "")
				_set_rail_active("build")
			else:
				_set_rail_active("")
			_layout_hud()
		"orders":
			var opening := not orders_panel.visible
			_close_panels(false)
			if opening:
				orders_panel.visible = true
				cancel_requested.emit()
				set_tool_state("", "")
				_set_rail_active("orders")
			else:
				_set_rail_active("")
		"people":
			if inspector_panel.visible and inspector_mode == "list":
				close_inspector()
			else:
				_close_panels(false)
				show_people_list()
		"work":
			if work_overlay.visible:
				_close_work()
			else:
				_open_work()
		"advisor":
			if advisor_overlay.visible:
				_close_advisor()
			else:
				_open_advisor()
		"log":
			var opening := not log_panel.visible
			_close_panels(false)
			if opening:
				log_panel.visible = true
				log_signature = ""
				_refresh_log()
				_set_rail_active("log")
			else:
				_set_rail_active("")
		"help":
			_open_help(false)

func _close_panels(cancel_tool: bool = true) -> void:
	if build_panel != null:
		build_panel.visible = false
	if orders_panel != null:
		orders_panel.visible = false
	if log_panel != null:
		log_panel.visible = false
	if cancel_tool and not tool_mode.is_empty():
		cancel_requested.emit()
		set_tool_state("", "")
	_set_rail_active("")
	_layout_hud()

func _set_rail_active(name: String) -> void:
	for key in rail_buttons.keys():
		var button: Button = rail_buttons[key]
		button.set_pressed_no_signal(key == name)

func _on_speed_pressed(value: int) -> void:
	if sim == null:
		return
	sim.set_speed(value)
	_refresh_speed_buttons()

func _refresh_speed_buttons() -> void:
	if sim == null:
		return
	for value in speed_buttons.keys():
		var button: Button = speed_buttons[value]
		if int(value) == sim.speed:
			button.add_theme_stylebox_override("normal", HFUI.style_box(Color("#4b3a22"), HFUI.AMBER_LIGHT, 6.0, 2, 1))
			button.add_theme_color_override("font_color", HFUI.AMBER_LIGHT)
		else:
			button.add_theme_stylebox_override("normal", HFUI.style_box(Color("#1a2820"), Color("#3e5140"), 6.0, 1, 1))
			button.add_theme_color_override("font_color", HFUI.MUTED)

func _refresh_game() -> void:
	if sim == null or game_ui == null or not game_ui.visible:
		return
	resource_values["wood"].text = str(sim.resource_qty("wood"))
	resource_values["stone"].text = str(sim.resource_qty("stone"))
	resource_values["food"].text = str(int(sim.food_total()))
	resource_values["herbs"].text = str(sim.resource_qty("herbs"))
	resource_values["ore"].text = str(sim.resource_qty("ore"))
	resource_values["tools"].text = str(sim.resource_qty("tools"))
	date_label.text = "%s · DAY %d · YEAR %d" % [HFDefs.SEASONS[sim.season_index].to_upper(), sim.day, sim.year]
	clock_label.text = "%s · %s" % [sim.time_string(), sim.day_phase()]
	weather_label.text = "%s · %s" % [sim.temperature_text(), sim.weather_name()]
	weather_label.add_theme_color_override("font_color", Color("#9ec2d0") if sim.temperature < 4.0 else HFUI.MUTED)
	_refresh_speed_buttons()
	_refresh_objectives()
	_refresh_orders()
	_refresh_alerts()
	_refresh_log()
	_refresh_inspector()
	if pause_overlay.visible:
		_update_pause_stats()
	_update_hover_bar()

func _refresh_objectives() -> void:
	if sim == null or objective_rows.is_empty():
		return
	for objective in sim.objectives:
		var key := str(objective.get("id", ""))
		var refs: Dictionary = objective_rows.get(key, {})
		if refs.is_empty():
			continue
		var done := bool(objective.get("done", false))
		refs["check"].text = "[x]" if done else "[ ]"
		refs["check"].add_theme_color_override("font_color", HFUI.GREEN if done else HFUI.MUTED)
		refs["label"].add_theme_color_override("font_color", HFUI.SUBTLE if done else HFUI.PARCHMENT)
		refs["label"].text = str(objective.get("label", key))
	var research_line := objectives_body.find_child("ResearchLine", true, false) as Label
	if research_line != null:
		research_line.text = "Research: " + sim.get_research_status()

func _refresh_orders() -> void:
	if sim == null or orders_active_box == null or orders_panel == null or not orders_panel.visible:
		return
	var standing: Array = []
	for job in sim.jobs:
		if bool(job.get("player", false)) and str(job.get("type", "")) in ["gather", "hunt", "defend"]:
			standing.append(job)
	var signature := ""
	for job in standing:
		signature += "%d:%d:%s|" % [int(job["id"]), int(job.get("worker_id", -1)), str(job.get("type", ""))]
	if signature == orders_signature:
		return
	orders_signature = signature
	for child in orders_active_box.get_children():
		child.queue_free()
	if standing.is_empty():
		var empty := HFUI.label("No standing orders. Choose a tool and mark the land.", 10, HFUI.SUBTLE)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		orders_active_box.add_child(empty)
		return
	for job in standing:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		orders_active_box.add_child(row)
		var icon_name := "axe"
		var label_text := "Work order"
		if str(job["type"]) == "gather":
			var od: Dictionary = HFDefs.OBJECTS.get(str(job.get("object_key", "")), {})
			icon_name = str(od.get("resource", "wood"))
			label_text = "Gather %s" % str(od.get("name", "wild resource"))
		else:
			var animal := sim._get_animal(int(job.get("animal_id", -1)))
			icon_name = "meat"
			label_text = "%s %s" % ["Defend against" if str(job["type"]) == "defend" else "Hunt", str(animal.get("name", "wildlife"))]
		var icon := TextureRect.new()
		icon.texture = HFAssets.tex(icon_name)
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var name_label := HFUI.label(label_text, 10, HFUI.PARCHMENT)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(name_label)
		var worker_id := int(job.get("worker_id", -1))
		var worker := sim.colonist_by_id(worker_id)
		var status_text := "Unassigned"
		if not worker.is_empty():
			status_text = str(worker["first_name"]) + " · " + ("travelling" if str(worker.get("state", "")) == "moving" else "working")
		info.add_child(HFUI.label(status_text, 9, HFUI.SUBTLE))
		var cancel := HFUI.button("×", 20, 10)
		cancel.custom_minimum_size = Vector2(20, 20)
		cancel.tooltip_text = "Cancel this order"
		cancel.pressed.connect(_cancel_order.bind(int(job["id"])))
		row.add_child(cancel)

func _cancel_order(job_id: int) -> void:
	if sim == null:
		return
	sim.cancel_job(job_id)
	orders_signature = ""
	toast("Standing order cancelled.")

func _refresh_alerts() -> void:
	if sim == null:
		return
	var alerts := sim.active_alerts()
	var signature := ""
	for alert in alerts:
		signature += str(alert.get("id", -1)) + "|"
	if signature == alert_signature:
		return
	alert_signature = signature
	for child in alerts_box.get_children():
		child.queue_free()
	alerts_box.visible = not alerts.is_empty()
	for alert in alerts:
		var severity := str(alert.get("severity", "warning"))
		var border := HFUI.AMBER
		if severity == "danger":
			border = HFUI.RED
		elif severity == "info":
			border = HFUI.BLUE
		var panel := HFUI.panel(Color("#1a241d"), border, 8.0, 2)
		panel.custom_minimum_size = Vector2(360, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		alerts_box.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
		var header := HBoxContainer.new()
		box.add_child(header)
		var title := HFUI.medium_label(str(alert.get("title", "Alert")), 11, border)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var dismiss := HFUI.button("×", 22, 12)
		dismiss.custom_minimum_size = Vector2(22, 20)
		dismiss.pressed.connect(_dismiss_alert.bind(int(alert.get("id", -1))))
		header.add_child(dismiss)
		var text := HFUI.label(str(alert.get("text", "")), 10, HFUI.PARCHMENT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(text)

func _dismiss_alert(id: int) -> void:
	if sim != null:
		sim.dismiss_alert(id)
		alert_signature = ""
		_refresh_alerts()

func _on_autosaved() -> void:
	# The pause screen and save flow communicate this quietly; no toast every dawn.
	pass

func _on_colonist_died(c: Dictionary) -> void:
	toast("%s has died." % str(c.get("name", "A colonist")), true)
	if inspector_mode == "colonist" and inspector_colonist_id == int(c.get("id", -1)):
		close_inspector()
	elif inspector_mode == "list":
		_rebuild_inspector()
