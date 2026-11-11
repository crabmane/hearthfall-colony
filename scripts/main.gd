extends Control

const TILE := 32.0
const CAMERA_MIN_ZOOM := 0.72
const CAMERA_MAX_ZOOM := 1.75
const CAMERA_START_ZOOM := 1.12

var sim: ColonySim
var renderer: HearthfallRenderer
var camera: Camera2D
var weather: WeatherOverlay
var hud: ColonyHUD
var world_layer: CanvasLayer
var hud_layer: CanvasLayer
var background: ColorRect
var tool_mode: String = ""
var build_key: String = ""
var game_active: bool = false
var hover_tile := Vector2i(-1, -1)
var middle_dragging: bool = false
var previous_speed: int = 1

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#0a100d"))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_build_layers()
	_connect_hud()
	hud.show_title(FileAccess.file_exists(ColonySim.SAVE_PATH))
	camera.position = renderer.world_to_iso(Vector2(HFDefs.MAP_W, HFDefs.MAP_H) * 0.5)
	_clamp_camera()
	set_process(true)

func _build_layers() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	background = ColorRect.new()
	HFUI.full_rect(background)
	background.color = Color("#142219")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(background)
	world_layer = CanvasLayer.new()
	world_layer.layer = 0
	add_child(world_layer)
	var world_root := Node2D.new()
	world_root.name = "World"
	world_layer.add_child(world_root)
	renderer = HearthfallRenderer.new()
	renderer.name = "WorldRenderer"
	world_root.add_child(renderer)
	camera = Camera2D.new()
	camera.name = "WorldCamera"
	camera.enabled = true
	camera.zoom = Vector2(CAMERA_START_ZOOM, CAMERA_START_ZOOM)
	camera.position = renderer.world_to_iso(Vector2(HFDefs.MAP_W, HFDefs.MAP_H) * 0.5)
	# The renderer owns projected map bounds; use manual clamping below.
	camera.limit_left = -100000
	camera.limit_top = -100000
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	camera.limit_smoothed = false
	world_root.add_child(camera)
	camera.make_current()
	renderer.setup(null, camera)
	var weather_layer := CanvasLayer.new()
	weather_layer.layer = 5
	add_child(weather_layer)
	weather = WeatherOverlay.new()
	weather.name = "Weather"
	weather_layer.add_child(weather)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = ColonyHUD.new()
	hud.name = "ColonyHUD"
	hud_layer.add_child(hud)

func _connect_hud() -> void:
	hud.build_requested.connect(_on_build_requested)
	hud.order_requested.connect(_on_order_requested)
	hud.herb_order_requested.connect(_on_herb_order_requested)
	hud.cancel_requested.connect(_cancel_tool)
	hud.load_requested.connect(_load_colony)
	hud.new_colony_requested.connect(_start_new_colony)
	hud.continue_requested.connect(_continue_colony)
	hud.title_requested.connect(_return_to_title)
	hud.inspector_closed.connect(_on_inspector_closed)
	hud.colonist_selected.connect(_on_colonist_selected)
	hud.center_on_building_requested.connect(_center_on_building)
	hud.cloud_load_ready.connect(_on_cloud_load_ready)

# -----------------------------------------------------------------------------
# Game lifecycle
# -----------------------------------------------------------------------------

func _start_new_colony() -> void:
	var new_sim := ColonySim.new()
	new_sim.name = "ColonySimulation"
	add_child(new_sim)
	new_sim.new_colony(0)
	_activate_sim(new_sim)
	hud.toast("Six survivors light the first hearth. Keep them alive.")
	_center_camera()

func _continue_colony() -> void:
	var new_sim := ColonySim.new()
	new_sim.name = "ColonySimulation"
	add_child(new_sim)
	if new_sim.load_game(new_sim.latest_save_path()):
		_activate_sim(new_sim)
		hud.toast("Colony restored from the last save.")
		_center_camera()
	else:
		new_sim.queue_free()
		hud.show_title(new_sim.save_exists())

func _activate_sim(new_sim: ColonySim) -> void:
	if sim != null and is_instance_valid(sim) and sim != new_sim:
		sim.queue_free()
	sim = new_sim
	sim.active = true
	if not sim.colony_fallen.is_connected(_on_colony_fallen):
		sim.colony_fallen.connect(_on_colony_fallen)
	if not sim.alert_raised.is_connected(_on_sim_alert):
		sim.alert_raised.connect(_on_sim_alert)
	if not sim.autosaved.is_connected(_on_cloud_autosave):
		sim.autosaved.connect(_on_cloud_autosave)
	renderer.setup(sim, camera)
	weather.setup(sim)
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	game_active = not sim.game_over
	hud.show_game(sim)
	if sim.game_over:
		game_active = false
		hud.show_game_over(sim.game_summary())
	_cancel_tool()
	_clamp_camera()

func _return_to_title() -> void:
	if sim != null:
		sim.set_speed(0)
		sim.active = false
	game_active = false
	_cancel_tool()
	renderer.clear_selection()
	hud.show_title(sim != null and sim.save_exists())

func _load_colony() -> void:
	if sim == null:
		return
	if not FileAccess.file_exists(ColonySim.AUTOSAVE_PATH):
		hud.toast("There is no dawn autosave yet.", true)
		return
	_cancel_tool()
	if sim.load_game(ColonySim.AUTOSAVE_PATH):
		renderer.setup(sim, camera)
		weather.setup(sim)
		camera.limit_right = 100000
		camera.limit_bottom = 100000
		renderer.clear_selection()
		hud.after_load()
		game_active = not sim.game_over
		if sim.game_over:
			hud.show_game_over(sim.game_summary())
		else:
			hud.toast("Colony loaded from the last autosave.")
		_center_camera()
	else:
		hud.toast("No valid colony save was found.", true)

func _on_colony_fallen() -> void:
	game_active = false
	if sim != null:
		sim.set_speed(0)
		hud.show_game_over(sim.game_summary())
		var summary := sim.game_summary()
		CloudServices.send_owner_event(
			"colony_game_over",
			"critical",
			"Colony lost",
			"A Hearthfall Colony settlement has entered game over.",
			{"day": int(summary.get("days", 0)), "population": int(summary.get("population", 0)), "deaths": int(summary.get("deaths", 0))}
		)

func _on_sim_alert(alert: Dictionary) -> void:
	var title := str(alert.get("title", "Colony alert"))
	var text := str(alert.get("text", ""))
	var haystack := (title + " " + text).to_lower()
	var severe_terms := ["fire", "predator", "wolf", "bear", "illness", "sick", "starvation", "starving", "frostbite"]
	var is_severe := str(alert.get("severity", "warning")) == "critical"
	for term in severe_terms:
		if haystack.contains(term):
			is_severe = true
			break
	if not is_severe:
		return
	CloudServices.send_owner_event(
		"severe_colony_alert",
		str(alert.get("severity", "warning")),
		title,
		text,
		{"day": sim.absolute_day, "clock": sim.time_string()}
	)

func _on_cloud_autosave() -> void:
	if sim != null and CloudServices.is_signed_in():
		CloudServices.save_current(sim, "auto", "Dawn autosave")

func _on_cloud_load_ready(data: String) -> void:
	var target := sim
	var created := false
	if target == null or not is_instance_valid(target):
		target = ColonySim.new()
		target.name = "ColonySimulation"
		add_child(target)
		created = true
	if target.deserialize_state(data):
		_activate_sim(target)
		hud.toast("Cloud colony restored.")
	else:
		if created:
			target.queue_free()
		hud.toast("That cloud save could not be restored.", true)

func _on_inspector_closed() -> void:
	renderer.clear_selection()

func _on_colonist_selected(id: int) -> void:
	renderer.select_colonist(id)

func _center_on_building(building_id: int) -> void:
	if sim == null:
		return
	var building := sim.get_building(building_id)
	if building.is_empty():
		return
	camera.position = renderer.world_to_iso(sim.building_center(building))
	_clamp_camera()
	renderer.select_building(building_id)

func _center_camera() -> void:
	if sim == null:
		return
	camera.position = renderer.world_to_iso(Vector2(sim.map_w, sim.map_h) * 0.5)
	_clamp_camera()

# -----------------------------------------------------------------------------
# Input and tools
# -----------------------------------------------------------------------------

func _on_build_requested(key: String) -> void:
	build_key = key
	tool_mode = "build:" + key
	renderer.set_tool(tool_mode, key)
	hud.set_tool_state(tool_mode, key)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func _on_order_requested(tool: String) -> void:
	tool_mode = tool
	build_key = ""
	renderer.set_tool(tool, "")
	hud.set_tool_state(tool, "")
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func _on_herb_order_requested() -> void:
	if sim == null:
		return
	var result := sim.queue_herb_order()
	hud.toast(result, not result.begins_with("Marked"))
	hud.orders_signature = ""

func _cancel_tool() -> void:
	tool_mode = ""
	build_key = ""
	renderer.set_tool("", "")
	if hud != null:
		hud.set_tool_state("", "")
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			_handle_key(event as InputEventKey)
		return
	if not game_active:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_dragging = mouse_event.pressed
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.1, mouse_event.position)
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / 1.1, mouse_event.position)
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_handle_world_click(_screen_to_tile(mouse_event.position))
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if not tool_mode.is_empty():
				_cancel_tool()
			else:
				renderer.clear_selection()
				if hud.inspector_panel.visible:
					hud.close_inspector()
			return
func _input(event: InputEvent) -> void:
	if middle_dragging and event is InputEventMouseMotion:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
		_clamp_camera()
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE and not (event as InputEventMouseButton).pressed:
		middle_dragging = false

func _handle_key(event: InputEventKey) -> void:
	if not game_active:
		return
	match event.keycode:
		KEY_ESCAPE:
			hud.handle_escape()
		KEY_SPACE:
			if _modal_open():
				return
			if sim.speed > 0:
				previous_speed = sim.speed
				sim.set_speed(0)
			else:
				sim.set_speed(maxi(1, previous_speed))
		KEY_F6:
			if sim.save_game():
				hud.toast("Colony saved.")
			else:
				hud.toast("The colony could not be saved.", true)
		KEY_F10:
			_load_colony()
		KEY_1:
			if not _modal_open():
				sim.set_speed(1)
		KEY_2:
			if not _modal_open():
				sim.set_speed(2)
		KEY_3:
			if not _modal_open():
				sim.set_speed(4)
		KEY_4:
			if not _modal_open():
				sim.set_speed(0)
		KEY_Q:
			if not _modal_open():
				renderer.rotate_view(-PI * 0.5)
		KEY_E:
			if not _modal_open():
				renderer.rotate_view(PI * 0.5)
		KEY_R:
			if not _modal_open():
				renderer.adjust_tilt(0.035)
		KEY_F:
			if not _modal_open():
				renderer.adjust_tilt(-0.035)
		KEY_0:
			if not _modal_open():
				renderer.reset_view()

func _modal_open() -> bool:
	return hud.pause_overlay.visible or hud.help_overlay.visible or hud.work_overlay.visible or hud.game_over_overlay.visible or hud.confirm_overlay.visible or hud.cloud_overlay.visible or hud.advisor_overlay.visible

func _handle_world_click(tile: Vector2i) -> void:
	if not game_active or sim == null or not _tile_in_bounds(tile):
		return
	if tool_mode.begins_with("build:"):
		var key := build_key
		var size := HFDefs.building_size(key)
		var origin := tile - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
		var error := sim.place_building(key, origin)
		if error.is_empty():
			var def: Dictionary = HFDefs.BUILDINGS.get(key, {})
			hud.toast("%s blueprint laid." % str(def.get("name", "Structure")))
		else:
			hud.toast(error, true)
		return
	if tool_mode == "gather":
		var message := sim.mark_gather(tile)
		if message.begins_with("Marked") or message.begins_with("Gathering"):
			hud.toast(message)
		else:
			hud.toast(message, true)
		return
	if tool_mode == "hunt":
		var animal := sim.animal_at_tile(tile)
		if animal.is_empty():
			hud.toast("No animal there.", true)
		else:
			hud.toast(sim.mark_hunt(int(animal["id"])))
		return
	if tool_mode == "demolish":
		var building := sim.building_at(tile)
		if building.is_empty():
			hud.toast("No building there.", true)
			return
		var def: Dictionary = HFDefs.BUILDINGS.get(str(building["key"]), {})
		var building_id := int(building["id"])
		hud.confirm_action("Dismantle the %s? Some materials will be recovered, but crops and stored work will be lost." % str(def.get("name", "structure")), func():
			var error := sim.demolish_building(building_id)
			if error.is_empty():
				renderer.clear_selection()
				if hud.inspector_panel.visible:
					hud.close_inspector()
				hud.toast("%s dismantled." % str(def.get("name", "Structure")))
			else:
				hud.toast(error, true)
		)
		return
	# No active order: inspect a colonist, then a building, then the ground.
	var colonist := sim.colonist_at_tile(tile)
	if not colonist.is_empty():
		renderer.select_colonist(int(colonist["id"]))
		hud.show_colonist(int(colonist["id"]))
		return
	var structure := sim.building_at(tile)
	if not structure.is_empty():
		renderer.select_building(int(structure["id"]))
		hud.show_building(int(structure["id"]))
		return
	renderer.clear_selection()
	if hud.inspector_panel.visible:
		hud.close_inspector()

func _mouse_tile() -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	return _screen_to_tile(get_viewport().get_mouse_position())

func _screen_to_tile(screen_position: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var viewport_size := get_viewport_rect().size
	var projected_pos := camera.position + (screen_position - viewport_size * 0.5) / camera.zoom
	var logical_pos := renderer.iso_to_world(projected_pos)
	return Vector2i(floori(logical_pos.x), floori(logical_pos.y))

func _tile_in_bounds(tile: Vector2i) -> bool:
	return sim != null and tile.x >= 0 and tile.y >= 0 and tile.x < sim.map_w and tile.y < sim.map_h

func _mouse_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	var node: Node = hovered
	while node != null:
		if node == hud:
			return true
		node = node.get_parent()
	return false

# -----------------------------------------------------------------------------
# Camera and world hover
# -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if camera == null:
		return
	if game_active:
		var pan := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pan.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pan.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			pan.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pan.y += 1.0
		if pan != Vector2.ZERO and not _modal_open():
			camera.position += pan.normalized() * 580.0 * delta / camera.zoom.x
			_clamp_camera()
		var over_ui := _mouse_over_ui()
		if over_ui:
			hover_tile = Vector2i(-1, -1)
			renderer.set_hover(hover_tile)
			hud.set_hover_info("")
		else:
			hover_tile = _mouse_tile()
			renderer.set_hover(hover_tile)
			if _tile_in_bounds(hover_tile):
				hud.set_hover_info(sim.tile_hover_text(hover_tile))
			else:
				hud.set_hover_info("")
	_clamp_camera()

func _zoom_camera(factor: float, screen_position: Vector2) -> void:
	if camera == null:
		return
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(old_zoom * factor, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var viewport_size := get_viewport_rect().size
	var mouse_offset := screen_position - viewport_size * 0.5
	var before := camera.position + mouse_offset / old_zoom
	camera.zoom = Vector2(new_zoom, new_zoom)
	var after := camera.position + mouse_offset / new_zoom
	camera.position += before - after
	_clamp_camera()

func _clamp_camera() -> void:
	if camera == null:
		return
	var viewport_size := get_viewport_rect().size
	var half := viewport_size * 0.5 / camera.zoom
	var bounds := renderer.projected_bounds()
	if half.x * 2.0 >= bounds.size.x:
		camera.position.x = bounds.position.x + bounds.size.x * 0.5
	else:
		camera.position.x = clampf(camera.position.x, bounds.position.x + half.x, bounds.end.x - half.x)
	if half.y * 2.0 >= bounds.size.y:
		camera.position.y = bounds.position.y + bounds.size.y * 0.5
	else:
		camera.position.y = clampf(camera.position.y, bounds.position.y + half.y, bounds.end.y - half.y)
