class_name HearthfallRenderer
extends Node2D

var sim: ColonySim
var camera: Camera2D
var hover_tile := Vector2i(-1, -1)
var selected_colonist_id: int = -1
var selected_building_id: int = -1
var tool_mode: String = ""
var build_key: String = ""
var anim_time: float = 0.0

const T := 32.0
const GRASS_A := Color("#405b3d")
const GRASS_B := Color("#476442")
const GRASS_C := Color("#385235")
const PATH_A := Color("#65563e")
const PATH_B := Color("#726149")
const WATER_A := Color("#274b58")
const WATER_B := Color("#315e6c")
const SOIL_A := Color("#4d3b2b")
const SOIL_B := Color("#584431")
const SNOW := Color("#dbe3d4")

func setup(colony_sim: ColonySim, game_camera: Camera2D) -> void:
	sim = colony_sim
	camera = game_camera
	var map_h := float(sim.map_h if sim != null else HFDefs.MAP_H)
	# Keep simulation coordinates Cartesian; project only the rendered canvas.
	# The basis vectors make each logical tile a 32x16 diamond.
	transform = Transform2D(Vector2(T * 0.5, T * 0.25), Vector2(-T * 0.5, T * 0.25), Vector2(map_h * T * 0.5, 0.0))

func world_to_iso(world: Vector2) -> Vector2:
	var map_h := float(sim.map_h if sim != null else HFDefs.MAP_H)
	return Vector2((world.x - world.y) * T * 0.5 + map_h * T * 0.5, (world.x + world.y) * T * 0.25)

func iso_to_world(projected: Vector2) -> Vector2:
	var map_h := float(sim.map_h if sim != null else HFDefs.MAP_H)
	var u := (projected.x - map_h * T * 0.5) / (T * 0.5)
	var v := projected.y / (T * 0.25)
	return Vector2((u + v) * 0.5, (v - u) * 0.5)

func set_hover(tile: Vector2i) -> void:
	hover_tile = tile

func set_tool(mode: String, key: String = "") -> void:
	tool_mode = mode
	build_key = key

func select_colonist(id: int) -> void:
	selected_colonist_id = id
	selected_building_id = -1

func select_building(id: int) -> void:
	selected_building_id = id
	selected_colonist_id = -1

func clear_selection() -> void:
	selected_colonist_id = -1
	selected_building_id = -1

func _process(delta: float) -> void:
	anim_time += delta
	queue_redraw()

func _visible_rect() -> Rect2:
	# Culling in projected space is more expensive than this small colony map;
	# keeping the full logical map visible also prevents edge pops while panning.
	return Rect2(-100000.0, -100000.0, 200000.0, 200000.0)

func _draw() -> void:
	if sim == null or sim.tiles.is_empty():
		return
	var view := _visible_rect().grow(96.0)
	_draw_ground(view)
	var drawables: Array = []
	_collect_nature(view, drawables)
	_collect_buildings(view, drawables)
	_collect_piles(view, drawables)
	_collect_colonists(drawables)
	_collect_animals(drawables)
	drawables.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("y", 0.0)) < float(b.get("y", 0.0))
	)
	for entry in drawables:
		match str(entry.get("kind", "")):
			"nature":
				_draw_nature(entry["tile"], entry["key"])
			"building":
				_draw_building(entry["building"])
			"pile":
				_draw_pile(entry["pile"])
			"colonist":
				_draw_colonist(entry["colonist"])
			"animal":
				_draw_animal(entry["animal"])
	_draw_night(view)
	_draw_selection()
	_draw_tool_ghost()

# -----------------------------------------------------------------------------
# Ground
# -----------------------------------------------------------------------------

func _draw_ground(view: Rect2) -> void:
	var min_x := maxi(0, int(floor(view.position.x / T)) - 1)
	var min_y := maxi(0, int(floor(view.position.y / T)) - 1)
	var max_x := mini(sim.map_w - 1, int(ceil(view.end.x / T)) + 1)
	var max_y := mini(sim.map_h - 1, int(ceil(view.end.y / T)) + 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var tile: Dictionary = sim.tiles[y][x]
			var rect := Rect2(Vector2(x, y) * T, Vector2(T + 1.0, T + 1.0))
			var terrain := str(tile.get("terrain", "grass"))
			var variant := int(tile.get("variant", 0))
			if terrain == "water":
				var water := WATER_A.lerp(WATER_B, 0.25 + 0.2 * sin(anim_time * 1.3 + float(x) * 0.5 + float(y) * 0.3))
				draw_rect(rect, water)
				if variant == 1:
					draw_line(Vector2(x * T + 6, y * T + 10), Vector2(x * T + 19, y * T + 10), Color(0.65, 0.8, 0.78, 0.18), 1.0)
				elif variant == 3:
					draw_line(Vector2(x * T + 13, y * T + 23), Vector2(x * T + 27, y * T + 23), Color(0.65, 0.8, 0.78, 0.15), 1.0)
			elif terrain == "path":
				draw_rect(rect, PATH_A if variant % 2 == 0 else PATH_B)
				if variant == 2:
					draw_rect(Rect2(Vector2(x * T + 8, y * T + 18), Vector2(3, 2)), Color(0.24, 0.2, 0.15, 0.5))
					draw_rect(Rect2(Vector2(x * T + 22, y * T + 7), Vector2(2, 2)), Color(0.8, 0.72, 0.56, 0.25))
			elif terrain == "soil":
				draw_rect(rect, SOIL_A if variant % 2 == 0 else SOIL_B)
				draw_line(Vector2(x * T + 3, y * T + 9), Vector2(x * T + 28, y * T + 9), Color(0.18, 0.12, 0.08, 0.22), 1.0)
				draw_line(Vector2(x * T + 4, y * T + 22), Vector2(x * T + 27, y * T + 22), Color(0.18, 0.12, 0.08, 0.18), 1.0)
			else:
				var grass := GRASS_A
				if variant == 1:
					grass = GRASS_B
				elif variant == 2:
					grass = GRASS_C
				draw_rect(rect, grass)
				if variant == 1:
					draw_line(Vector2(x * T + 8, y * T + 23), Vector2(x * T + 10, y * T + 19), Color(0.62, 0.72, 0.46, 0.28), 1.0)
					draw_line(Vector2(x * T + 10, y * T + 23), Vector2(x * T + 13, y * T + 18), Color(0.62, 0.72, 0.46, 0.24), 1.0)
				elif variant == 3:
					draw_rect(Rect2(Vector2(x * T + 20, y * T + 11), Vector2(2, 2)), Color(0.18, 0.25, 0.17, 0.35))
			if sim.temperature < 2.5 and terrain != "water":
				var snow_alpha := clampf((3.0 - sim.temperature) / 15.0, 0.0, 0.45)
				draw_rect(rect, Color(0.86, 0.9, 0.86, snow_alpha * 0.55))
	# Subtle map edge vignette.
	draw_rect(Rect2(Vector2.ZERO, Vector2(sim.map_w * T, 3.0)), Color(0.0, 0.0, 0.0, 0.5))
	draw_rect(Rect2(Vector2(0, sim.map_h * T - 3), Vector2(sim.map_w * T, 3.0)), Color(0.0, 0.0, 0.0, 0.5))

# -----------------------------------------------------------------------------
# Drawable collection
# -----------------------------------------------------------------------------

func _collect_nature(view: Rect2, drawables: Array) -> void:
	var min_x := maxi(0, int(floor(view.position.x / T)) - 1)
	var min_y := maxi(0, int(floor(view.position.y / T)) - 1)
	var max_x := mini(sim.map_w - 1, int(ceil(view.end.x / T)) + 1)
	var max_y := mini(sim.map_h - 1, int(ceil(view.end.y / T)) + 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var tile: Dictionary = sim.tiles[y][x]
			var key := str(tile.get("object", ""))
			if key.is_empty() or int(tile.get("building_id", -1)) != -1:
				continue
			drawables.append({"kind": "nature", "key": key, "tile": Vector2i(x, y), "y": float(x + y + 1) * T})

func _collect_buildings(view: Rect2, drawables: Array) -> void:
	for b in sim.buildings:
		var origin: Vector2i = b["origin"]
		var size: Vector2i = b["size"]
		var bottom := float(origin.x + origin.y + size.x + size.y) * T
		var center_x := (float(origin.x) - float(origin.y)) * T * 0.5
		if center_x < view.position.x - 120.0 or center_x > view.end.x + 120.0 or bottom < view.position.y - 180.0 or bottom > view.end.y + 120.0:
			continue
		drawables.append({"kind": "building", "building": b, "y": bottom})

func _collect_piles(view: Rect2, drawables: Array) -> void:
	for pile in sim.piles:
		var tile: Vector2i = pile["tile"]
		var pos := (Vector2(tile) + Vector2(0.5, 0.72)) * T
		if not view.has_point(pos):
			continue
		drawables.append({"kind": "pile", "pile": pile, "y": float(tile.x + tile.y + 1) * T - 3.0})

func _collect_colonists(drawables: Array) -> void:
	for c in sim.colonists:
		var pos := Vector2(c["pos"])
		drawables.append({"kind": "colonist", "colonist": c, "y": (pos.x + pos.y) * T})

func _collect_animals(drawables: Array) -> void:
	for animal in sim.animals:
		var pos := Vector2(animal["pos"])
		drawables.append({"kind": "animal", "animal": animal, "y": (pos.x + pos.y) * T + 5.0})

# -----------------------------------------------------------------------------
# World objects
# -----------------------------------------------------------------------------

func _draw_tex_rect(texture: Texture2D, center: Vector2, max_size: Vector2, modulate: Color = Color.WHITE) -> void:
	if texture == null:
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var scale_factor := minf(max_size.x / source_size.x, max_size.y / source_size.y)
	var drawn_size := source_size * scale_factor
	var rect := Rect2(center - drawn_size * 0.5, drawn_size)
	draw_texture_rect(texture, rect, false, modulate)

func _draw_nature(tile: Vector2i, key: String) -> void:
	var od: Dictionary = HFDefs.OBJECTS.get(key, {})
	var sprite := str(od.get("sprite", key))
	var texture := HFAssets.tex(sprite)
	var center := Vector2(tile.x + 0.5, tile.y + 0.92) * T
	var max_size := Vector2(44.0, 56.0)
	match key:
		"pine", "oak", "birch":
			max_size = Vector2(64.0, 92.0)
		"berry_bush":
			max_size = Vector2(42.0, 38.0)
		"boulder":
			max_size = Vector2(38.0, 30.0)
		"stone_outcrop", "iron_vein", "coal_seam", "clay":
			max_size = Vector2(46.0, 40.0)
		"mushrooms":
			max_size = Vector2(28.0, 22.0)
		"reeds":
			max_size = Vector2(32.0, 38.0)
		"wheat":
			max_size = Vector2(32.0, 36.0)
		"pumpkin":
			max_size = Vector2(30.0, 24.0)
		"stump", "dead_shrub":
			max_size = Vector2(27.0, 22.0)
	# Ground shadow.
	var shadow_width := max_size.x * 0.45
	draw_rect(Rect2(center.x - shadow_width * 0.5, center.y - 3.0, shadow_width, 5.0), Color(0.0, 0.0, 0.0, 0.22))
	_draw_tex_rect(texture, center - Vector2(0.0, max_size.y * 0.5 - 5.0), max_size)

func _draw_building(b: Dictionary) -> void:
	var origin: Vector2i = b["origin"]
	var size: Vector2i = b["size"]
	var footprint := Rect2(Vector2(origin) * T, Vector2(size) * T)
	var bottom_center := Vector2(footprint.position.x + footprint.size.x * 0.5, footprint.end.y)
	var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
	var built := bool(b.get("built", false))
	if str(b.get("key", "")) == "campfire":
		_draw_campfire(bottom_center - Vector2(0.0, 4.0), b)
		return
	var texture := HFAssets.tex(str(b["key"]))
	var max_size := Vector2(size.x * T * 1.58, size.y * T * 1.9)
	if str(b["key"]) == "farm_plot":
		max_size = Vector2(size.x * T * 0.98, size.y * T * 0.88)
	elif str(b["key"]) == "stockpile":
		max_size = Vector2(size.x * T * 0.98, size.y * T * 0.85)
	elif str(b["key"]) in ["wall", "gate"]:
		max_size = Vector2(T * 1.05, T * 1.4)
	elif str(b["key"]) == "well":
		max_size = Vector2(T * 1.45, T * 1.55)
	elif str(b["key"]) == "watchtower":
		max_size = Vector2(T * 1.5, T * 2.05)
	var modulate := Color.WHITE if built else Color(1.0, 1.0, 1.0, 0.3)
	if float(b.get("burning", 0.0)) > 0.0:
		modulate = Color(1.0, 0.58 + 0.12 * sin(anim_time * 9.0), 0.42, 1.0)
	var shadow_width := footprint.size.x * 0.7
	draw_rect(Rect2(bottom_center.x - shadow_width * 0.5, bottom_center.y - 5.0, shadow_width, 7.0), Color(0.0, 0.0, 0.0, 0.3))
	_draw_tex_rect(texture, bottom_center - Vector2(0.0, max_size.y * 0.5 - 5.0), max_size, modulate)
	if str(b["key"]) == "farm_plot":
		_draw_crop_overlay(b, bottom_center)
	if not built:
		var progress := 0.0
		for job in sim.jobs:
			if int(job.get("building_id", -1)) == int(b["id"]) and str(job.get("type", "")) == "build":
				progress = clampf(float(job.get("progress", 0.0)) / maxf(0.01, float(job.get("work_required", 1.0))), 0.0, 1.0)
		draw_rect(Rect2(footprint.position + Vector2(3, 3), footprint.size - Vector2(6, 6)), Color(0.1, 0.14, 0.11, 0.24))
		draw_line(footprint.position, Vector2(footprint.end.x, footprint.position.y), Color(0.94, 0.71, 0.35, 0.7), 1.0)
		draw_line(Vector2(footprint.end.x, footprint.position.y), footprint.end, Color(0.94, 0.71, 0.35, 0.7), 1.0)
		draw_line(footprint.end, Vector2(footprint.position.x, footprint.end.y), Color(0.94, 0.71, 0.35, 0.7), 1.0)
		draw_line(Vector2(footprint.position.x, footprint.end.y), footprint.position, Color(0.94, 0.71, 0.35, 0.7), 1.0)
		draw_rect(Rect2(footprint.position.x + 6, footprint.end.y - 7, footprint.size.x - 12, 4), Color(0.08, 0.1, 0.08, 0.8))
		draw_rect(Rect2(footprint.position.x + 6, footprint.end.y - 7, (footprint.size.x - 12) * progress, 4), Color("#efb35a"))
	if float(b.get("burning", 0.0)) > 0.0:
		_draw_fire(bottom_center, float(b["burning"]))

func _draw_crop_overlay(b: Dictionary, bottom_center: Vector2) -> void:
	var crop := str(b.get("crop", "grain"))
	var growth := float(b.get("growth", 0.0))
	var texture := HFAssets.tex("wheat" if crop == "grain" else "pumpkin")
	if texture == null:
		return
	var scale_factor := 0.25 + clampf(growth / 100.0, 0.0, 1.0) * 0.75
	var max_size := Vector2(44.0, 44.0) * scale_factor
	for offset in [Vector2(-16, -14), Vector2(12, -17), Vector2(-9, 1), Vector2(16, 0)]:
		_draw_tex_rect(texture, bottom_center + offset + Vector2(0, -5), max_size, Color(1.0, 1.0, 1.0, 0.92))

func _draw_campfire(center: Vector2, b: Dictionary) -> void:
	draw_circle(center + Vector2(0, 6), 11.0, Color(0.08, 0.07, 0.05, 0.5))
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var stone := center + Vector2(cos(angle), sin(angle)) * 13.0 + Vector2(0, 3)
		draw_rect(Rect2(stone - Vector2(3, 2), Vector2(6, 4)), Color("#7d7a68"))
		draw_rect(Rect2(stone - Vector2(2, 1), Vector2(3, 2)), Color("#a39e85"))
	draw_line(center + Vector2(-9, 4), center + Vector2(8, -3), Color("#513726"), 4.0)
	draw_line(center + Vector2(-8, -3), center + Vector2(9, 5), Color("#68472e"), 4.0)
	var flicker := sin(anim_time * 8.0) * 2.0
	draw_circle(center + Vector2(0, -7 + flicker * 0.3), 8.0 + flicker * 0.2, Color(0.93, 0.45, 0.17, 0.75))
	draw_circle(center + Vector2(1, -11), 5.0 + absf(flicker) * 0.25, Color(0.98, 0.75, 0.29, 0.9))
	draw_rect(Rect2(center + Vector2(-2, -9), Vector2(4, 8)), Color("#f7c765"))

func _draw_fire(center: Vector2, intensity: float) -> void:
	var flicker := absf(sin(anim_time * 10.0))
	for i in range(3):
		var offset := Vector2((i - 1) * 11.0, -18.0 - i * 3.0)
		var h := 12.0 + intensity * 0.25 + flicker * 5.0
		draw_rect(Rect2(center + offset + Vector2(-4, -h), Vector2(8, h)), Color(0.94, 0.39, 0.12, 0.8))
		draw_rect(Rect2(center + offset + Vector2(-2, -h * 0.7), Vector2(4, h * 0.7)), Color(1.0, 0.78, 0.31, 0.9))

func _draw_pile(pile: Dictionary) -> void:
	var tile: Vector2i = pile["tile"]
	var center := (Vector2(tile) + Vector2(0.5, 0.72)) * T
	var texture := HFAssets.resource_icon(str(pile.get("resource", "wood")))
	draw_rect(Rect2(center.x - 10, center.y + 1, 20, 4), Color(0, 0, 0, 0.2))
	_draw_tex_rect(texture, center + Vector2(0, -4), Vector2(25, 21))
	var label := str(int(pile.get("qty", 0)))
	draw_string(HFUI.body_font(), center + Vector2(-18, 15), label, HORIZONTAL_ALIGNMENT_CENTER, 36, 10, Color("#f1e4c8"))

func _draw_colonist(c: Dictionary) -> void:
	var pos := Vector2(c["pos"]) * T
	var index := int(c.get("sprite_index", 0))
	var texture := HFAssets.tex("colonist_%02d" % index)
	var selected := int(c["id"]) == selected_colonist_id
	if selected:
		draw_circle(pos + Vector2(0, -9), 17.0, Color(0.94, 0.71, 0.35, 0.16))
		draw_arc(pos + Vector2(0, -9), 17.0, 0.0, TAU, 24, Color("#efb35a"), 1.5)
	draw_rect(Rect2(pos.x - 9, pos.y - 1, 18, 4), Color(0.0, 0.0, 0.0, 0.24))
	_draw_tex_rect(texture, pos - Vector2(0, 16), Vector2(27.0, 37.0))
	_draw_colonist_status(c, pos)
	if selected:
		var plate_width := 132.0
		var plate := Rect2(pos.x - plate_width * 0.5, pos.y - 62, plate_width, 22)
		draw_rect(plate, Color(0.06, 0.09, 0.07, 0.92))
		draw_rect(plate, Color("#efb35a"), false, 1.0)
		draw_string(HFUI.body_font(), plate.position + Vector2(0, 15), str(c["name"]), HORIZONTAL_ALIGNMENT_CENTER, plate_width, 11, Color("#f1e4c8"))
		var mood_width := 58.0
		var mood_rect := Rect2(pos.x - mood_width * 0.5, pos.y + 5, mood_width, 3)
		draw_rect(mood_rect, Color(0.08, 0.1, 0.08, 0.9))
		draw_rect(Rect2(mood_rect.position, Vector2(mood_width * float(c["mood"]) / 100.0, 3)), HFUI.mood_color(float(c["mood"])))

func _draw_colonist_status(c: Dictionary, pos: Vector2) -> void:
	var needs: Dictionary = c["needs"]
	var icon := ""
	var color := Color.WHITE
	if str(c.get("state", "")) == "sleeping":
		icon = "z"
		color = Color("#a9c2d0")
	elif float(needs.get("hunger", 100.0)) < 25.0:
		icon = "!"
		color = Color("#e06955")
	elif float(c.get("illness", 0.0)) > 20.0 or float(c.get("injury", 0.0)) > 25.0:
		icon = "+"
		color = Color("#d98b9d")
	elif float(c.get("mood", 50.0)) < 28.0:
		icon = "…"
		color = Color("#b59ac8")
	elif str(c.get("state", "")) == "working":
		var job := sim.get_job(int(c.get("job_id", -1)))
		if not job.is_empty():
			icon = "•"
			color = HFUI.job_color(str(job.get("category", "haul")))
	if not icon.is_empty():
		draw_string(HFUI.body_font(), pos + Vector2(-10, -38), icon, HORIZONTAL_ALIGNMENT_CENTER, 20, 13, color)
	if str(c.get("state", "")) == "moving" and int(c.get("job_id", -1)) != -1:
		var job := sim.get_job(int(c["job_id"]))
		if not job.is_empty():
			draw_circle(pos + Vector2(9, -34), 3.0, HFUI.job_color(str(job.get("category", "haul"))))

func _draw_animal(animal: Dictionary) -> void:
	var pos := Vector2(animal["pos"]) * T
	var texture := HFAssets.tex(str(animal.get("sprite", animal.get("key", "rabbit"))))
	var max_size := Vector2(38.0, 30.0)
	if str(animal.get("key", "")) in ["bear", "boar"]:
		max_size = Vector2(44.0, 34.0)
	elif str(animal.get("key", "")) in ["deer_stag", "deer_doe"]:
		max_size = Vector2(42.0, 40.0)
	elif str(animal.get("key", "")) == "owl":
		max_size = Vector2(24.0, 24.0)
	draw_rect(Rect2(pos.x - max_size.x * 0.3, pos.y + 1, max_size.x * 0.6, 3), Color(0, 0, 0, 0.2))
	_draw_tex_rect(texture, pos - Vector2(0, max_size.y * 0.35), max_size)
	if bool(animal.get("hostile", false)):
		draw_circle(pos + Vector2(0, -max_size.y * 0.9), 6.0, Color(0.72, 0.22, 0.16, 0.82))
		draw_string(HFUI.body_font(), pos + Vector2(-7, -max_size.y * 0.9 + 5), "!", HORIZONTAL_ALIGNMENT_CENTER, 14, 11, Color("#fff0d0"))

# -----------------------------------------------------------------------------
# Night, selection, and build ghost
# -----------------------------------------------------------------------------

func _draw_night(view: Rect2) -> void:
	var darkness := 0.0
	var hour_float := float(sim.hour) + float(sim.minute) / 60.0
	if hour_float >= 20.0 or hour_float < 5.0:
		darkness = 0.54
	elif hour_float >= 18.0:
		darkness = lerpf(0.0, 0.54, (hour_float - 18.0) / 2.0)
	elif hour_float < 7.0:
		darkness = lerpf(0.54, 0.0, (hour_float - 5.0) / 2.0)
	if sim.weather == "storm":
		darkness += 0.1
	elif sim.weather == "fog":
		darkness += 0.06
	if darkness > 0.01:
		draw_rect(view, Color(0.03, 0.06, 0.09, darkness))
		for b in sim.buildings:
			if not bool(b.get("built", false)):
				continue
			var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
			if float(def.get("warmth", 0.0)) <= 0.0 and not bool(def.get("light", false)):
				continue
			var center := Vector2(sim.building_center(b)) * T
			var flicker := 0.88 + 0.12 * sin(anim_time * 5.0 + float(b["id"]))
			var radius := (45.0 + float(def.get("warmth", 0.0)) * 5.5) * flicker
			draw_circle(center, radius, Color(0.98, 0.64, 0.26, 0.065))
			draw_circle(center, radius * 0.62, Color(1.0, 0.72, 0.32, 0.07))
			draw_circle(center, radius * 0.3, Color(1.0, 0.8, 0.44, 0.06))
		if sim.weather == "fog":
			draw_rect(view, Color(0.6, 0.68, 0.62, 0.08))

func _draw_selection() -> void:
	if selected_building_id != -1:
		var b := sim.get_building(selected_building_id)
		if not b.is_empty():
			var rect := Rect2(Vector2(b["origin"]) * T, Vector2(b["size"]) * T)
			draw_rect(rect, Color(0.94, 0.71, 0.35, 0.05))
			draw_rect(rect, Color("#efb35a"), false, 2.0)
			_draw_corner_marks(rect, Color("#ffd48a"))
			if not bool(b.get("built", false)):
				var progress := 0.0
				for job in sim.jobs:
					if int(job.get("building_id", -1)) == int(b["id"]) and str(job.get("type", "")) == "build":
						progress = clampf(float(job.get("progress", 0.0)) / maxf(0.01, float(job.get("work_required", 1.0))), 0.0, 1.0)
				draw_rect(Rect2(rect.position.x + 5, rect.end.y + 4, rect.size.x - 10, 5), Color(0.06, 0.09, 0.07, 0.9))
				draw_rect(Rect2(rect.position.x + 5, rect.end.y + 4, (rect.size.x - 10) * progress, 5), Color("#efb35a"))
			if float(b.get("burning", 0.0)) > 0.0:
				draw_string(HFUI.body_font(), rect.position + Vector2(4, -6), "BURNING", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e06955"))
	if selected_colonist_id != -1:
		var c := sim.colonist_by_id(selected_colonist_id)
		if not c.is_empty():
			for tile in c.get("path", []):
				draw_circle((Vector2(tile) + Vector2(0.5, 0.5)) * T, 2.0, Color(0.94, 0.71, 0.35, 0.28))

func _draw_corner_marks(rect: Rect2, color: Color) -> void:
	var length := 8.0
	draw_line(rect.position, rect.position + Vector2(length, 0), color, 2.0)
	draw_line(rect.position, rect.position + Vector2(0, length), color, 2.0)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - length, rect.position.y), color, 2.0)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + length), color, 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x + length, rect.end.y), color, 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, rect.end.y - length), color, 2.0)
	draw_line(rect.end, rect.end - Vector2(length, 0), color, 2.0)
	draw_line(rect.end, rect.end - Vector2(0, length), color, 2.0)

func _draw_tool_ghost() -> void:
	if not _tile_in_bounds(hover_tile):
		return
	if tool_mode.begins_with("build:"):
		var key := build_key
		var size := HFDefs.building_size(key)
		var origin := hover_tile - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
		var error := sim.can_place_building(key, origin)
		var valid := error.is_empty()
		var footprint := Rect2(Vector2(origin) * T, Vector2(size) * T)
		draw_rect(footprint, Color(0.45, 0.8, 0.4, 0.18) if valid else Color(0.85, 0.25, 0.2, 0.22))
		draw_rect(footprint, Color("#a8c56f") if valid else Color("#e06955"), false, 2.0)
		_draw_corner_marks(footprint, Color("#ffd48a") if valid else Color("#ff9a86"))
		var texture := HFAssets.tex(key)
		if texture != null and key != "campfire":
			var max_size := Vector2(size.x * T * 1.58, size.y * T * 1.9)
			_draw_tex_rect(texture, Vector2(footprint.position.x + footprint.size.x * 0.5, footprint.end.y - max_size.y * 0.5 + 5), max_size, Color(1, 1, 1, 0.5))
		elif key == "campfire":
			draw_circle(footprint.get_center(), 12.0, Color(0.95, 0.6, 0.25, 0.35))
	elif tool_mode == "gather":
		var tile: Dictionary = sim.tile_at(hover_tile)
		var od: Dictionary = sim.object_def(tile)
		var valid := not od.is_empty()
		var color := Color("#a8c56f") if valid else Color("#e06955")
		draw_rect(Rect2(Vector2(hover_tile) * T, Vector2(T, T)), Color(color.r, color.g, color.b, 0.12))
		draw_rect(Rect2(Vector2(hover_tile) * T, Vector2(T, T)), color, false, 1.0)
	elif tool_mode == "hunt":
		var animal := sim.animal_at_tile(hover_tile)
		var color := Color("#e06955") if not animal.is_empty() else Color("#8b8a7a")
		draw_rect(Rect2(Vector2(hover_tile) * T, Vector2(T, T)), Color(color.r, color.g, color.b, 0.12))
		draw_rect(Rect2(Vector2(hover_tile) * T, Vector2(T, T)), color, false, 1.0)
	elif tool_mode == "demolish":
		var b := sim.building_at(hover_tile)
		if not b.is_empty():
			var footprint := Rect2(Vector2(b["origin"]) * T, Vector2(b["size"]) * T)
			draw_rect(footprint, Color(0.8, 0.2, 0.16, 0.2))
			draw_rect(footprint, Color("#e06955"), false, 2.0)
		else:
			draw_rect(Rect2(Vector2(hover_tile) * T, Vector2(T, T)), Color(0.8, 0.2, 0.16, 0.3), false, 1.0)
	elif tool_mode.is_empty():
		draw_rect(Rect2(Vector2(hover_tile) * T, Vector2(T, T)), Color(0.9, 0.85, 0.7, 0.18), false, 1.0)

func _tile_in_bounds(tile: Vector2i) -> bool:
	return sim != null and tile.x >= 0 and tile.y >= 0 and tile.x < sim.map_w and tile.y < sim.map_h
