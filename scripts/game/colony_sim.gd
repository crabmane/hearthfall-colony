class_name ColonySim
extends Node

signal changed
signal event_logged(entry: Dictionary)
signal alert_raised(alert: Dictionary)
signal colonist_died(colonist: Dictionary)
signal colony_fallen
signal objectives_changed
signal autosaved

const SAVE_PATH := "user://hearthfall_colony.json"
const AUTOSAVE_PATH := "user://hearthfall_autosave.json"
const GAME_MIN_PER_SECOND := 6.0
const BASE_STORAGE := 90.0
const COLONY_CENTER := Vector2(23.0, 16.0)

var rng := RandomNumberGenerator.new()
var world_seed: int = 1
var map_w: int = HFDefs.MAP_W
var map_h: int = HFDefs.MAP_H
var tiles: Array = []
var buildings: Array = []
var colonists: Array = []
var animals: Array = []
var piles: Array = []
var jobs: Array = []
var resources: Dictionary = {}
var speed: int = 1
var active: bool = false
var game_over: bool = false
var time_min: float = 420.0
var day: int = 1
var absolute_day: int = 1
var hour: int = 7
var minute: int = 0
var season_index: int = 0
var year: int = 1
var weather: String = "clear"
var weather_timer: float = 240.0
var temperature: float = 14.0
var temp_modifier: float = 0.0
var temp_modifier_until: float = 0.0
var research_index: int = 0
var research_progress: float = 0.0
var event_log: Array = []
var alerts: Array = []
var objectives: Array = []
var stats: Dictionary = {}
var next_building_id: int = 1
var next_colonist_id: int = 1
var next_job_id: int = 1
var next_pile_id: int = 1
var next_animal_id: int = 1
var next_alert_id: int = 1
var spoilage_buffer: Dictionary = {}
var job_scan_timer: float = 0.0
var flavor_timer: float = 240.0
var last_daily_event_day: int = 0
var last_autosave_day: int = 0
var auto_save_enabled: bool = true
var pending_fire_check: float = 0.0
var pending_crop_check: float = 0.0
var pending_spoil_check: float = 0.0
var pending_regrow_check: float = 0.0
var game_elapsed_seconds: float = 0.0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func new_colony(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_ticks_usec() & 0x7fffffff)
	world_seed = seed_value
	rng.seed = world_seed
	map_w = HFDefs.MAP_W
	map_h = HFDefs.MAP_H
	tiles.clear()
	buildings.clear()
	colonists.clear()
	animals.clear()
	piles.clear()
	jobs.clear()
	resources.clear()
	alerts.clear()
	event_log.clear()
	spoilage_buffer.clear()
	next_building_id = 1
	next_colonist_id = 1
	next_job_id = 1
	next_pile_id = 1
	next_animal_id = 1
	next_alert_id = 1
	time_min = 420.0
	speed = 1
	active = true
	game_over = false
	game_elapsed_seconds = 0.0
	research_index = 0
	research_progress = 0.0
	temp_modifier = 0.0
	temp_modifier_until = 0.0
	last_daily_event_day = 0
	last_autosave_day = 1
	job_scan_timer = 0.0
	flavor_timer = 260.0
	pending_fire_check = 0.0
	pending_crop_check = 0.0
	pending_spoil_check = 0.0
	pending_regrow_check = 0.0
	stats = {
		"days": 1, "built": 0, "gathered": 0, "meals": 0, "deaths": 0,
		"hunts": 0, "treated": 0, "research": 0, "started": int(Time.get_unix_time_from_system()),
	}
	_sync_calendar()
	_generate_world()
	_setup_starting_colony()
	_setup_relationships()
	_spawn_initial_wildlife()
	_ensure_objectives()
	_choose_weather(true)
	_log("The first hearth is lit at the edge of the pines.", "story")
	_alert("The colony is founded", "Six survivors have claimed this clearing. Keep them fed, warm, and hopeful.", "info", 360.0)
	_scan_jobs()
	changed.emit()
	objectives_changed.emit(objectives.duplicate(true))

func _process(delta: float) -> void:
	if not active or game_over or speed <= 0:
		return
	var scaled_delta := delta * float(speed)
	var game_minutes := delta * float(speed) * GAME_MIN_PER_SECOND
	game_elapsed_seconds += scaled_delta
	time_min += game_minutes
	_sync_calendar()
	_update_environment(game_minutes)
	_update_colonists(scaled_delta, game_minutes)
	_update_animals(scaled_delta, game_minutes)
	job_scan_timer -= scaled_delta
	if job_scan_timer <= 0.0:
		job_scan_timer = 1.0
		_scan_jobs()
	_update_ambient_events(game_minutes)
	_autosave_check()

func set_speed(value: int) -> void:
	speed = clampi(value, 0, 4)
	if speed != 2 and speed != 4 and speed != 1:
		speed = 0 if speed == 0 else speed
	changed.emit()

func _sync_calendar() -> void:
	var total := maxf(0.0, time_min)
	absolute_day = int(floor(total / 1440.0)) + 1
	day = ((absolute_day - 1) % HFDefs.DAYS_PER_SEASON) + 1
	season_index = int(floor(float(absolute_day - 1) / float(HFDefs.DAYS_PER_SEASON))) % 4
	year = int(floor(float(absolute_day - 1) / float(HFDefs.DAYS_PER_SEASON * 4.0))) + 1
	var within_day := fmod(total, 1440.0)
	hour = int(floor(within_day / 60.0)) % 24
	minute = int(floor(fmod(within_day, 60.0)))
	temperature = current_temperature()
	stats["days"] = absolute_day

func current_temperature() -> float:
	var hour_float := float(hour) + float(minute) / 60.0
	var daily_swing := sin((hour_float - 8.0) / 24.0 * TAU) * 6.0
	var weather_def: Dictionary = HFDefs.WEATHER.get(weather, {})
	var weather_temp := float(weather_def.get("temp", 0.0))
	var modifier := temp_modifier if time_min < temp_modifier_until else 0.0
	return HFDefs.SEASON_BASE_TEMP[season_index] + daily_swing + weather_temp + modifier

func time_string() -> String:
	return "%02d:%02d" % [hour, minute]

func date_string() -> String:
	return "%s · Day %d" % [HFDefs.SEASONS[season_index], day]

func day_phase() -> String:
	if hour < 5:
		return "Night"
	if hour < 8:
		return "Dawn"
	if hour < 12:
		return "Morning"
	if hour < 17:
		return "Afternoon"
	if hour < 20:
		return "Dusk"
	return "Night"

func is_night() -> bool:
	return hour >= 20 or hour < 6

func weather_name() -> String:
	return str(HFDefs.WEATHER.get(weather, {}).get("name", weather.capitalize()))

func weather_description() -> String:
	return str(HFDefs.WEATHER.get(weather, {}).get("desc", ""))

func temperature_text() -> String:
	return "%d°C" % int(round(temperature))

func average_mood() -> float:
	if colonists.is_empty():
		return 0.0
	var total := 0.0
	for c in colonists:
		total += float(c.get("mood", 50.0))
	return total / float(colonists.size())

func living_count() -> int:
	return colonists.size()

# -----------------------------------------------------------------------------
# World generation and queries
# -----------------------------------------------------------------------------

func _generate_world() -> void:
	for y in range(map_h):
		var row: Array = []
		for x in range(map_w):
			row.append({
				"terrain": "grass",
				"object": "",
				"building_id": -1,
				"variant": rng.randi_range(0, 4),
				"regrow_at": 0.0,
				"regrow_key": "",
			})
		tiles.append(row)
	# A cold pond in the northwest corner.
	var pond_center := Vector2(8.0, 7.0)
	for y in range(3, 13):
		for x in range(3, 15):
			var d := Vector2(x, y).distance_to(pond_center)
			if d < 3.0:
				tiles[y][x]["terrain"] = "water"
				tiles[y][x]["object"] = ""
			elif d < 4.4 and rng.randf() < 0.28:
				tiles[y][x]["object"] = "reeds"
	# A worn trail through the clearing.
	for x in range(13, 35):
		var trail_y := 19 + int(round(sin(float(x) * 0.3) * 1.2))
		if trail_y >= 0 and trail_y < map_h:
			tiles[trail_y][x]["terrain"] = "path"
	# Forest, scattered stone, and forage.
	for y in range(map_h):
		for x in range(map_w):
			var tile: Dictionary = tiles[y][x]
			if tile["terrain"] == "water":
				continue
			var pos := Vector2(x, y)
			var dist := pos.distance_to(COLONY_CENTER)
			if dist < 8.0:
				if rng.randf() < 0.035:
					tile["object"] = ["dead_shrub", "mushrooms"][rng.randi_range(0, 1)]
				continue
			if dist < 11.0:
				if rng.randf() < 0.13:
					tile["object"] = ["berry_bush", "dead_shrub", "mushrooms", "boulder"][rng.randi_range(0, 3)]
				continue
			if rng.randf() < 0.38:
				var roll := rng.randf()
				if roll < 0.53:
					tile["object"] = "pine"
				elif roll < 0.72:
					tile["object"] = "oak"
				elif roll < 0.85:
					tile["object"] = "birch"
				elif roll < 0.94:
					tile["object"] = "berry_bush"
				else:
					tile["object"] = "dead_shrub"
			elif rng.randf() < 0.045:
				tile["object"] = ["boulder", "stone_outcrop", "mushrooms"][rng.randi_range(0, 2)]
	# Guaranteed nearby forage and stone for a readable opening.
	for entry in [
		[COLONY_CENTER.x - 6, COLONY_CENTER.y - 2, "berry_bush"],
		[COLONY_CENTER.x + 7, COLONY_CENTER.y - 4, "berry_bush"],
		[COLONY_CENTER.x - 4, COLONY_CENTER.y + 5, "berry_bush"],
		[COLONY_CENTER.x + 5, COLONY_CENTER.y + 5, "mushrooms"],
		[COLONY_CENTER.x + 10, COLONY_CENTER.y - 2, "stone_outcrop"],
		[COLONY_CENTER.x + 11, COLONY_CENTER.y + 2, "boulder"],
		[COLONY_CENTER.x - 10, COLONY_CENTER.y - 5, "pine"],
		[COLONY_CENTER.x - 11, COLONY_CENTER.y + 3, "oak"],
	]:
		var ix := clampi(int(entry[0]), 0, map_w - 1)
		var iy := clampi(int(entry[1]), 0, map_h - 1)
		if tiles[iy][ix]["terrain"] != "water":
			tiles[iy][ix]["object"] = str(entry[2])
	# Ore and coal live farther out, but remain reachable.
	for i in range(5):
		var ox := clampi(35 + i, 0, map_w - 1)
		var oy := clampi(10 + i * 2, 0, map_h - 1)
		tiles[oy][ox]["object"] = "iron_vein" if i < 3 else "coal_seam"
	# Dense border forest frames the clearing and keeps the map legible.
	for x in range(map_w):
		for y in [0, 1, map_h - 2, map_h - 1]:
			if tiles[y][x]["terrain"] != "water" and rng.randf() < 0.8:
				tiles[y][x]["object"] = "pine"
	for y in range(map_h):
		for x in [0, 1, map_w - 2, map_w - 1]:
			if tiles[y][x]["terrain"] != "water" and rng.randf() < 0.8:
				tiles[y][x]["object"] = "pine"
	_clear_area(Rect2i(19, 12, 9, 8))

func _clear_area(rect: Rect2i) -> void:
	for y in range(maxi(0, rect.position.y), mini(map_h, rect.position.y + rect.size.y)):
		for x in range(maxi(0, rect.position.x), mini(map_w, rect.position.x + rect.size.x)):
			tiles[y][x]["object"] = ""
			tiles[y][x]["building_id"] = -1
			if tiles[y][x]["terrain"] == "water":
				tiles[y][x]["terrain"] = "grass"

func _setup_starting_colony() -> void:
	_add_building("stockpile", Vector2i(22, 16), true, false)
	_add_building("campfire", Vector2i(23, 14), true, false)
	resources = {
		"wood": 70, "stone": 40, "ore": 0, "coal": 0, "clay": 0,
		"grain": 24, "pumpkin": 0, "berries": 48, "fish": 0, "meat": 0,
		"meal": 6, "bread": 0, "herbs": 10, "medicine": 1, "tools": 2, "cloth": 2,
	}
	for c in [
		Vector2i(21, 18), Vector2i(24, 18), Vector2i(20, 17),
		Vector2i(25, 17), Vector2i(21, 15), Vector2i(25, 15),
	]:
		_add_colonist(c)

func _setup_relationships() -> void:
	for a in colonists:
		a["relationships"] = {}
	for a in colonists:
		for b in colonists:
			if a["id"] != b["id"]:
				var value := rng.randi_range(-8, 22)
				a["relationships"][str(b["id"])] = value
	_recompute_all_moods()

func _spawn_initial_wildlife() -> void:
	for entry in [["deer_doe", Vector2i(37, 7)], ["rabbit", Vector2i(14, 25)], ["fox", Vector2i(36, 26)]]:
		_spawn_animal(str(entry[0]), entry[1])

func _tile_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < map_w and tile.y < map_h

func tile_at(tile: Vector2i) -> Dictionary:
	if not _tile_in_bounds(tile):
		return {}
	return tiles[tile.y][tile.x]

func tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))

func object_def(tile: Dictionary) -> Dictionary:
	var key := str(tile.get("object", ""))
	return HFDefs.OBJECTS.get(key, {})

func is_walkable(tile: Vector2i) -> bool:
	if not _tile_in_bounds(tile):
		return false
	var t: Dictionary = tiles[tile.y][tile.x]
	if str(t["terrain"]) == "water":
		return false
	var object: Dictionary = object_def(t)
	if bool(object.get("blocking", false)):
		return false
	var bid := int(t.get("building_id", -1))
	if bid != -1:
		var b := get_building(bid)
		if not b.is_empty():
			var bdef: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
			return bool(bdef.get("walkable", false)) and bool(b.get("built", false))
		return false
	return true

func get_building(id: int) -> Dictionary:
	for b in buildings:
		if int(b["id"]) == id:
			return b
	return {}

func building_at(tile: Vector2i) -> Dictionary:
	var t := tile_at(tile)
	if t.is_empty():
		return {}
	return get_building(int(t.get("building_id", -1)))

func building_footprint(building: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(building["origin"]), Vector2i(building["size"]))

func built_buildings_of_type(key: String) -> Array:
	var result: Array = []
	for b in buildings:
		if bool(b.get("built", false)) and str(b.get("key", "")) == key:
			result.append(b)
	return result

func count_built(key: String) -> int:
	return built_buildings_of_type(key).size()

func has_built(key: String) -> bool:
	return count_built(key) > 0

func colony_defense() -> float:
	var total := 0.0
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b.get("key", "")), {})
		total += float(def.get("defense", 0.0))
	return total

func watchtower_vision() -> float:
	var vision := 0.0
	for b in built_buildings_of_type("watchtower"):
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b.get("key", "")), {})
		vision = maxf(vision, float(def.get("vision", 0.0)))
	return vision

func _near_built(key: String, world_tile_pos: Vector2, radius: float) -> bool:
	for b in built_buildings_of_type(key):
		if world_tile_pos.distance_to(building_center(b)) <= radius:
			return true
	return false

func building_center(building: Dictionary) -> Vector2:
	var footprint := building_footprint(building)
	return Vector2(footprint.position) + Vector2(footprint.size) * 0.5

func _adjacent_tiles(rect: Rect2i) -> Array:
	var result: Array = []
	for x in range(rect.position.x - 1, rect.position.x + rect.size.x + 1):
		for y in range(rect.position.y - 1, rect.position.y + rect.size.y + 1):
			var t := Vector2i(x, y)
			if rect.has_point(t):
				continue
			if _tile_in_bounds(t):
				result.append(t)
	return result

func _best_adjacent_tile(building: Dictionary, from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 1e20
	for tile in _adjacent_tiles(building_footprint(building)):
		if not is_walkable(tile):
			continue
		var dist := Vector2(tile).distance_squared_to(from)
		if dist < best_dist:
			best_dist = dist
			best = tile
	return best

func _nearest_walkable(tile: Vector2i) -> Vector2i:
	if is_walkable(tile):
		return tile
	for radius in range(1, 5):
		for y in range(tile.y - radius, tile.y + radius + 1):
			for x in range(tile.x - radius, tile.x + radius + 1):
				var candidate := Vector2i(x, y)
				if _tile_in_bounds(candidate) and is_walkable(candidate):
					return candidate
	return Vector2i(-1, -1)

func _find_path(start: Vector2i, goal: Vector2i, max_nodes: int = 2600) -> Array:
	if not _tile_in_bounds(start) or not _tile_in_bounds(goal):
		return []
	if start == goal:
		return [goal]
	if not is_walkable(goal):
		return []
	var open: Array[Vector2i] = [start]
	var in_open: Dictionary = {start: true}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _path_heuristic(start, goal)}
	var visited := 0
	while not open.is_empty() and visited < max_nodes:
		visited += 1
		var current_i := 0
		for i in range(1, open.size()):
			if float(f_score.get(open[i], 1e20)) < float(f_score.get(open[current_i], 1e20)):
				current_i = i
		var current: Vector2i = open[current_i]
		if current == goal:
			return _reconstruct_path(came_from, current)
		open.remove_at(current_i)
		in_open.erase(current)
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var neighbor: Vector2i = current + dir
			if not is_walkable(neighbor):
				continue
			if dir.x != 0 and dir.y != 0:
				if not is_walkable(current + Vector2i(dir.x, 0)) or not is_walkable(current + Vector2i(0, dir.y)):
					continue
			var step := 1.41421356 if dir.x != 0 and dir.y != 0 else 1.0
			var tentative := float(g_score.get(current, 1e20)) + step
			if tentative >= float(g_score.get(neighbor, 1e20)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _path_heuristic(neighbor, goal)
			if not in_open.has(neighbor):
				open.append(neighbor)
				in_open[neighbor] = true
	return []

func _path_heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(dx + dy) - 0.585786 * float(mini(dx, dy))

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array:
	var path: Array = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	if path.size() > 1:
		path.remove_at(0)
	return path

# -----------------------------------------------------------------------------
# Resources and construction
# -----------------------------------------------------------------------------

func storage_capacity() -> float:
	var total := BASE_STORAGE
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		total += float(def.get("storage", 0.0))
	return total

func storage_used() -> float:
	var total := 0.0
	for key in resources.keys():
		total += maxf(0.0, float(resources[key]))
	return total

func storage_free() -> float:
	return maxf(0.0, storage_capacity() - storage_used())

func resource_qty(resource_id: String) -> int:
	return maxi(0, int(resources.get(resource_id, 0)))

func add_resource(resource_id: String, amount: int, respect_capacity: bool = true) -> int:
	if amount <= 0:
		return 0
	var accepted := amount
	if respect_capacity:
		accepted = mini(amount, int(floor(storage_free())))
	if accepted <= 0:
		return 0
	resources[resource_id] = resource_qty(resource_id) + accepted
	return accepted

func remove_resource(resource_id: String, amount: int) -> int:
	var available := resource_qty(resource_id)
	var removed := mini(available, maxi(0, amount))
	resources[resource_id] = available - removed
	return removed

func has_resources(cost: Dictionary) -> bool:
	for key in cost.keys():
		if resource_qty(str(key)) < int(cost[key]):
			return false
	return true

func _pay_resources(cost: Dictionary) -> void:
	for key in cost.keys():
		remove_resource(str(key), int(cost[key]))

func _refund_resources(cost: Dictionary, multiplier: float = 1.0) -> void:
	for key in cost.keys():
		var amount := int(floor(float(cost[key]) * multiplier))
		if amount > 0:
			add_resource(str(key), amount, false)

func food_total() -> float:
	var total := 0.0
	for key in resources.keys():
		var def: Dictionary = HFDefs.RESOURCES.get(str(key), {})
		total += float(resources[key]) * float(def.get("food", 0.0))
	return total

func food_units() -> int:
	var total := 0
	for key in resources.keys():
		var def: Dictionary = HFDefs.RESOURCES.get(str(key), {})
		if float(def.get("food", 0.0)) > 0.0:
			total += resource_qty(str(key))
	return total

func best_food() -> String:
	for key in HFDefs.FOOD_PREFERENCE:
		if resource_qty(key) > 0:
			return key
	return ""

func _spoil_modifier() -> float:
	var modifier := 1.0
	for b in built_buildings_of_type("food_shed"):
		modifier = minf(modifier, float(HFDefs.BUILDINGS["food_shed"].get("spoil", 1.0)))
	if research_index > 3:
		modifier *= 0.80
	return modifier

func can_place_building(key: String, origin: Vector2i) -> String:
	var def: Dictionary = HFDefs.BUILDINGS.get(key, {})
	if def.is_empty():
		return "Unknown building."
	var size := HFDefs.building_size(key)
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var tile := Vector2i(x, y)
			if not _tile_in_bounds(tile):
				return "That footprint leaves the map."
			var t: Dictionary = tiles[y][x]
			if str(t["terrain"]) == "water":
				return "You cannot build on water."
			if int(t.get("building_id", -1)) != -1:
				return "Something is already built here."
			if not str(t.get("object", "")).is_empty():
				return "Clear the trees and stone first."
	if not has_resources(def.get("cost", {})):
		return "Not enough materials."
	return ""

func place_building(key: String, origin: Vector2i) -> String:
	var error := can_place_building(key, origin)
	if not error.is_empty():
		return error
	var def: Dictionary = HFDefs.BUILDINGS[key]
	_pay_resources(def.get("cost", {}))
	var building := _add_building(key, origin, false, false)
	if building.is_empty():
		return "The blueprint could not be laid."
	_add_job("build", {"building_id": int(building["id"]), "priority": 2})
	_log("Blueprint laid: %s." % str(def["name"]), "build")
	changed.emit()
	return ""

func _add_building(key: String, origin: Vector2i, instant: bool, pay: bool) -> Dictionary:
	var def: Dictionary = HFDefs.BUILDINGS.get(key, {})
	if def.is_empty():
		return {}
	var size := HFDefs.building_size(key)
	if pay:
		if not has_resources(def.get("cost", {})):
			return {}
		_pay_resources(def.get("cost", {}))
	var building := {
		"id": next_building_id,
		"key": key,
		"origin": origin,
		"size": size,
		"built": instant,
		"hp": float(def.get("hp", 100)) if instant else 0.0,
		"max_hp": float(def.get("hp", 100)),
		"burning": 0.0,
		"occupants": [],
		"station_busy": false,
		"growth": 0.0,
		"planted": false,
		"crop": "grain",
		"cooldown": 0.0,
		"quality": 1.0,
	}
	next_building_id += 1
	buildings.append(building)
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			tiles[y][x]["building_id"] = int(building["id"])
			if bool(def.get("farm", false)):
				tiles[y][x]["terrain"] = "soil"
	if instant:
		stats["built"] = int(stats.get("built", 0)) + 1
	return building

func demolish_building(id: int) -> String:
	var b := get_building(id)
	if b.is_empty():
		return "No building selected."
	var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
	var refund := 1.0 if not bool(b.get("built", false)) else 0.5
	_refund_resources(def.get("cost", {}), refund)
	for occ in b.get("occupants", []):
		var c := colonist_by_id(int(occ))
		if not c.is_empty():
			c["bed_id"] = -1
			c["state"] = "idle"
			c["action_text"] = "Idle"
	for job in jobs.duplicate():
		if int(job.get("building_id", -1)) == id:
			_remove_job(job)
	var rect := building_footprint(b)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if _tile_in_bounds(Vector2i(x, y)):
				tiles[y][x]["building_id"] = -1
				if str(tiles[y][x]["terrain"]) == "soil":
					tiles[y][x]["terrain"] = "grass"
	buildings.erase(b)
	_log("Dismantled %s. Some materials were recovered." % str(def.get("name", "building")), "build")
	changed.emit()
	return ""

func _burn_building(b: Dictionary) -> void:
	var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
	for y in range(int(b["origin"].y), int(b["origin"].y) + int(b["size"].y)):
		for x in range(int(b["origin"].x), int(b["origin"].x) + int(b["size"].x)):
			if _tile_in_bounds(Vector2i(x, y)):
				tiles[y][x]["building_id"] = -1
	for job in jobs.duplicate():
		if int(job.get("building_id", -1)) == int(b["id"]):
			_remove_job(job)
	buildings.erase(b)
	_log("The %s collapsed in the fire." % str(def.get("name", "building")), "danger")
	_alert("Building lost", "The %s burned to the ground." % str(def.get("name", "building")), "danger", 300.0)
	changed.emit()

# -----------------------------------------------------------------------------
# Colonists
# -----------------------------------------------------------------------------

func _add_colonist(spawn_tile: Vector2i) -> Dictionary:
	if colonists.size() >= HFDefs.COLONIST_CAP:
		return {}
	var used_sprites: Array = []
	for c in colonists:
		used_sprites.append(int(c["sprite_index"]))
	var sprite_index := 0
	for i in range(16):
		if not used_sprites.has(i):
			sprite_index = i
			break
	var first := str(HFDefs.NAMES[rng.randi_range(0, HFDefs.NAMES.size() - 1)])
	var surname := str(HFDefs.SURNAMES[rng.randi_range(0, HFDefs.SURNAMES.size() - 1)])
	var trait_ids: Array[String] = []
	var available_traits: Array = HFDefs.TRAITS.keys()
	for i in range(2):
		var pick := rng.randi_range(0, available_traits.size() - 1)
		var trait_id := str(available_traits[pick])
		available_traits.remove_at(pick)
		trait_ids.append(trait_id)
	var skills := {}
	for skill_id in HFDefs.SKILLS.keys():
		skills[str(skill_id)] = float(rng.randi_range(1, 5))
	var focus_skill := str(HFDefs.SKILLS.keys()[rng.randi_range(0, HFDefs.SKILLS.size() - 1)])
	skills[focus_skill] = float(rng.randi_range(6, 9))
	var priorities := {}
	for job_id in HFDefs.JOB_ORDER:
		priorities[job_id] = 2
	priorities["haul"] = 3
	priorities["fire"] = 4
	var labor := float(skills.get("labor", 2.0))
	var farming := float(skills.get("farming", 2.0))
	var cooking := float(skills.get("cooking", 2.0))
	var crafting := float(skills.get("crafting", 2.0))
	var medicine := float(skills.get("medicine", 2.0))
	var combat := float(skills.get("combat", 2.0))
	if labor >= 6.0:
		priorities["gather"] = 3
		priorities["build"] = 3
	if farming >= 6.0:
		priorities["farm"] = 3
	if cooking >= 6.0:
		priorities["cook"] = 3
	if crafting >= 6.0:
		priorities["craft"] = 3
	if medicine >= 6.0:
		priorities["care"] = 3
	if combat >= 6.0:
		priorities["hunt"] = 3
	var spawn := _nearest_walkable(spawn_tile)
	if spawn.x < 0:
		spawn = Vector2i(int(COLONY_CENTER.x), int(COLONY_CENTER.y))
	var colonist := {
		"id": next_colonist_id,
		"name": "%s %s" % [first, surname],
		"first_name": first,
		"age": rng.randi_range(19, 57),
		"sprite_index": sprite_index,
		"pos": Vector2(spawn) + Vector2(0.5, 0.5),
		"path": [],
		"path_goal": spawn,
		"state": "idle",
		"job_id": -1,
		"job_phase": "to_work",
		"action_text": "Getting their bearings",
		"action_timer": 0.0,
		"action_data": {},
		"needs": {
			"hunger": float(rng.randi_range(62, 92)),
			"fatigue": float(rng.randi_range(65, 95)),
			"warmth": float(rng.randi_range(68, 90)),
			"hygiene": float(rng.randi_range(60, 90)),
		},
		"health": 100.0,
		"illness": 0.0,
		"injury": 0.0,
		"mood": 55.0,
		"mood_reasons": {},
		"mood_events": [],
		"traits": trait_ids,
		"skills": skills,
		"skill_xp": {},
		"relationships": {},
		"priorities": priorities,
		"carry": {},
		"bed_id": -1,
		"social_target": -1,
		"social_cooldown": 0.0,
		"decision_timer": rng.randf_range(0.0, 0.8),
		"mood_timer": rng.randf_range(0.0, 3.0),
		"idle_timer": 0.0,
		"thought_timer": rng.randf_range(180.0, 480.0),
		"patient_reserved": false,
		"waiting_for_care": false,
		"last_eat_log_day": -1,
		"last_no_food_alert": -1000.0,
		"last_illness_alert": 0.0,
		"dead": false,
	}
	next_colonist_id += 1
	for existing in colonists:
		existing["relationships"][str(colonist["id"])] = rng.randi_range(-6, 18)
		colonist["relationships"][str(existing["id"])] = existing["relationships"][str(colonist["id"])]
	colonists.append(colonist)
	_recompute_mood(colonist)
	return colonist

func colonist_by_id(id: int) -> Dictionary:
	for c in colonists:
		if int(c["id"]) == id:
			return c
	return {}

func colonist_tile(c: Dictionary) -> Vector2i:
	return tile_of(Vector2(c["pos"]))

func has_trait(c: Dictionary, trait_id: String) -> bool:
	return trait_id in c.get("traits", [])

func trait_mod(c: Dictionary, stat: String, default_value: float = 1.0) -> float:
	var value := default_value
	for trait_id in c.get("traits", []):
		var trait_def: Dictionary = HFDefs.TRAITS.get(str(trait_id), {})
		if trait_def.has(stat):
			value *= float(trait_def[stat])
	return value

func skill_value(c: Dictionary, skill_id: String) -> float:
	return float(c.get("skills", {}).get(skill_id, 1.0))

func _gain_skill(c: Dictionary, skill_id: String, amount: float) -> void:
	var current := skill_value(c, skill_id)
	var xp_gain := amount * trait_mod(c, "xp", 1.0)
	var xp := float(c.get("skill_xp", {}).get(skill_id, 0.0)) + xp_gain
	c["skill_xp"][skill_id] = xp
	if xp >= 10.0 and current < 20.0:
		c["skill_xp"][skill_id] = xp - 10.0
		c["skills"][skill_id] = current + 1.0
		_log("%s is getting better at %s." % [str(c["first_name"]), HFDefs.skill_name(skill_id)], "skill")

func _update_colonists(sim_dt: float, game_minutes: float) -> void:
	for c in colonists.duplicate():
		if not colonists.has(c) or bool(c.get("dead", false)):
			continue
		_update_colonist(c, sim_dt, game_minutes)

func _update_colonist(c: Dictionary, sim_dt: float, game_minutes: float) -> void:
	_tick_needs(c, game_minutes / 60.0, game_minutes)
	if bool(c.get("dead", false)) or not colonists.has(c):
		return
	if c["state"] != "sleeping" and not _is_need_action(c):
		_try_need_interrupt(c)
	match str(c["state"]):
		"moving":
			if _advance_path(c, sim_dt):
				_on_arrive(c)
		"working":
			_tick_work(c, sim_dt)
		"sleeping":
			_tick_sleep(c, game_minutes)
		"eating", "washing", "warming", "resting", "socializing":
			_tick_action(c, game_minutes)
		_:
			c["idle_timer"] = maxf(0.0, float(c.get("idle_timer", 0.0)) - sim_dt)
			c["decision_timer"] = float(c.get("decision_timer", 0.0)) - sim_dt
			if float(c["decision_timer"]) <= 0.0:
				_choose_action(c)

func _is_need_action(c: Dictionary) -> bool:
	var action_type := str(c.get("action_data", {}).get("type", ""))
	return action_type in ["eat", "wash", "warm", "rest", "sleep"]

func _try_need_interrupt(c: Dictionary) -> void:
	if c["state"] == "working" or c["state"] == "moving":
		var needs: Dictionary = c["needs"]
		if float(needs["hunger"]) < 18.0:
			_release_job(c, true)
			_choose_action(c)
		elif float(needs["fatigue"]) < 9.0:
			_release_job(c, true)
			_choose_action(c)
		elif float(c["health"]) < 20.0:
			_release_job(c, true)
			_choose_action(c)
		elif float(needs["warmth"]) < 15.0:
			_release_job(c, true)
			_choose_action(c)

func _tick_needs(c: Dictionary, hours: float, game_minutes: float) -> void:
	var needs: Dictionary = c["needs"]
	var sleeping := str(c["state"]) == "sleeping"
	var hunger_rate := 3.7 * trait_mod(c, "hunger", 1.0)
	needs["hunger"] = clampf(float(needs["hunger"]) - hunger_rate * hours * (0.45 if sleeping else 1.0), 0.0, 100.0)
	if not sleeping:
		needs["fatigue"] = clampf(float(needs["fatigue"]) - 5.4 * trait_mod(c, "fatigue", 1.0) * hours, 0.0, 100.0)
	needs["hygiene"] = clampf(float(needs["hygiene"]) - 2.1 * trait_mod(c, "hygiene", 1.0) * hours, 0.0, 100.0)
	var warmth_target := _warmth_target(c)
	var warmth_rate := 17.0 if warmth_target > float(needs["warmth"]) else 9.0
	needs["warmth"] = move_toward(float(needs["warmth"]), warmth_target, warmth_rate * hours)
	var health := float(c["health"])
	if float(needs["hunger"]) <= 0.0:
		health -= 5.2 * hours
	if float(needs["warmth"]) <= 8.0:
		health -= 3.4 * hours
	if float(c["illness"]) > 0.0:
		health -= float(c["illness"]) * 0.012 * hours
	if float(c["injury"]) > 0.0:
		health -= float(c["injury"]) * 0.008 * hours
	if float(needs["hunger"]) > 40.0 and float(needs["warmth"]) > 30.0:
		var recovery := 1.4 if c["state"] == "resting" else 0.65
		health += recovery * hours
	c["health"] = clampf(health, 0.0, 100.0)
	c["injury"] = maxf(0.0, float(c["injury"]) - (1.0 if c["state"] == "resting" else 0.18) * hours)
	if float(c["illness"]) > 0.0 and float(c["health"]) > 55.0:
		c["illness"] = maxf(0.0, float(c["illness"]) - 0.55 * hours)
	# Sickness spreads through cold, poor hygiene, and bad luck.
	var illness_chance := 0.000012 * game_minutes
	illness_chance *= 1.0 + maxf(0.0, 30.0 - float(needs["warmth"])) * 0.055
	illness_chance *= 1.0 + maxf(0.0, 30.0 - float(needs["hygiene"])) * 0.025
	illness_chance *= trait_mod(c, "illness", 1.0)
	if absolute_day >= 3 and rng.randf() < illness_chance and float(c["illness"]) < 5.0:
		c["illness"] = rng.randf_range(12.0, 32.0)
		_add_mood(c, "Feeling ill", -9.0, 12.0)
		_log("%s has fallen ill." % str(c["first_name"]), "danger")
		if time_min - float(c.get("last_illness_alert", 0.0)) > 360.0:
			c["last_illness_alert"] = time_min
			_alert("Illness in the colony", "%s needs rest, warmth, and medicine." % str(c["first_name"]), "warning", 300.0)
	c["mood_timer"] = float(c["mood_timer"]) - game_minutes
	if float(c["mood_timer"]) <= 0.0:
		c["mood_timer"] = 5.0
		_recompute_mood(c)
	c["thought_timer"] = float(c.get("thought_timer", 300.0)) - game_minutes
	if float(c["thought_timer"]) <= 0.0:
		c["thought_timer"] = rng.randf_range(260.0, 620.0)
		_maybe_thought(c)
	if float(c["health"]) <= 0.0:
		_kill_colonist(c, "poor health")
		return
	for event in c.get("mood_events", []).duplicate():
		if float(event.get("until", 0.0)) <= time_min:
			c["mood_events"].erase(event)

func _warmth_target(c: Dictionary) -> float:
	var target := 42.0 + temperature * 1.35
	if weather in ["rain", "storm"]:
		target -= 4.0
	if weather == "snow":
		target -= 4.0
	var cpos := Vector2(c["pos"])
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		var warmth := float(def.get("warmth", 0.0))
		if warmth <= 0.0:
			continue
		var dist := cpos.distance_to(building_center(b))
		if dist < 5.2:
			target += warmth * 3.6 * (1.0 - dist / 7.0)
	if str(c["state"]) == "sleeping" and int(c.get("bed_id", -1)) != -1:
		target += 18.0
	return clampf(target, 5.0, 100.0)

func _recompute_all_moods() -> void:
	for c in colonists:
		_recompute_mood(c)

func _recompute_mood(c: Dictionary) -> void:
	var reasons: Dictionary = {}
	var mood := 50.0
	var needs: Dictionary = c["needs"]
	mood += (float(needs["hunger"]) - 55.0) * 0.22
	reasons["Hunger"] = (float(needs["hunger"]) - 55.0) * 0.22
	mood += (float(needs["fatigue"]) - 50.0) * 0.10
	reasons["Rest"] = (float(needs["fatigue"]) - 50.0) * 0.10
	mood += (float(needs["warmth"]) - 50.0) * 0.16
	reasons["Warmth"] = (float(needs["warmth"]) - 50.0) * 0.16
	mood += (float(needs["hygiene"]) - 50.0) * 0.07
	reasons["Cleanliness"] = (float(needs["hygiene"]) - 50.0) * 0.07
	mood += (float(c["health"]) - 70.0) * 0.16
	reasons["Health"] = (float(c["health"]) - 70.0) * 0.16
	if float(c["illness"]) > 0.0:
		mood -= float(c["illness"]) * 0.18
		reasons["Illness"] = -float(c["illness"]) * 0.18
	if float(c["injury"]) > 0.0:
		mood -= float(c["injury"]) * 0.16
		reasons["Injury"] = -float(c["injury"]) * 0.16
	var trait_total := 0.0
	for trait_id in c.get("traits", []):
		var trait_def: Dictionary = HFDefs.TRAITS.get(str(trait_id), {})
		trait_total += float(trait_def.get("mood", 0.0))
	mood += trait_total
	if absf(trait_total) > 0.1:
		reasons["Temperament"] = trait_total
	var has_bed := false
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b.get("key", "")), {})
		if int(def.get("beds", 0)) > 0:
			has_bed = true
			break
	if has_bed:
		mood += 3.0
		reasons["A warm bed"] = 3.0
	else:
		mood -= 3.0
		reasons["No bed"] = -3.0
	var affinity_total := 0.0
	var affinity_count := 0
	for other_id in c.get("relationships", {}).keys():
		affinity_total += float(c["relationships"][other_id])
		affinity_count += 1
	if affinity_count > 0:
		var avg := affinity_total / float(affinity_count)
		var social_value := avg * 0.20
		mood += social_value
		if absf(social_value) > 0.8:
			reasons["Good company" if social_value > 0.0 else "Tense company"] = social_value
	for event in c.get("mood_events", []):
		if float(event.get("until", 0.0)) > time_min:
			var value := float(event.get("value", 0.0))
			mood += value
			var label := str(event.get("label", "A recent moment"))
			reasons[label] = float(reasons.get(label, 0.0)) + value
	if is_night():
		var near_light := false
		for b in buildings:
			if not bool(b.get("built", false)):
				continue
			var light_def: Dictionary = HFDefs.BUILDINGS.get(str(b.get("key", "")), {})
			if not bool(light_def.get("light", false)):
				continue
			if Vector2(c["pos"]).distance_to(building_center(b)) < 7.0:
				near_light = true
				break
		if near_light:
			mood += 2.0
			reasons["Firelight"] = 2.0
		else:
			mood -= 2.0
			reasons["Darkness"] = -2.0
	if weather == "storm":
		mood -= 3.0
		reasons["Storm nerves"] = -3.0
	elif weather in ["clear", "snow"]:
		mood += 1.0
		reasons["The sky"] = 1.0
	c["mood"] = clampf(mood, 0.0, 100.0)
	c["mood_reasons"] = reasons

func _add_mood(c: Dictionary, label: String, value: float, hours: float = 6.0) -> void:
	c["mood_events"].append({"label": label, "value": value, "until": time_min + hours * 60.0})
	_recompute_mood(c)

func _maybe_thought(c: Dictionary) -> void:
	if event_log.size() > 0 and str(event_log[-1].get("type", "")) == "story" and time_min - float(event_log[-1].get("time", 0.0)) < 90.0:
		return
	var thought := str(HFDefs.THOUGHTS[rng.randi_range(0, HFDefs.THOUGHTS.size() - 1)])
	_log("%s %s" % [str(c["first_name"]), thought], "story")

func _kill_colonist(c: Dictionary, cause: String) -> void:
	if bool(c.get("dead", false)):
		return
	c["dead"] = true
	var dead_id := int(c["id"])
	_release_job(c, true)
	for b in buildings:
		b["occupants"].erase(dead_id)
	for other in colonists:
		if int(other["id"]) == dead_id:
			continue
		var affinity := float(other.get("relationships", {}).get(str(dead_id), 0.0))
		other["relationships"].erase(str(dead_id))
		if affinity > 8.0:
			_add_mood(other, "Lost a friend", -14.0, 24.0)
		else:
			_add_mood(other, "A death in the colony", -7.0, 18.0)
		if int(other.get("social_target", -1)) == dead_id:
			other["social_target"] = -1
	colonists.erase(c)
	stats["deaths"] = int(stats.get("deaths", 0)) + 1
	_log("%s has died from %s." % [str(c["name"]), cause], "danger")
	_alert("A life ended", "%s died from %s. The colony is smaller tonight." % [str(c["name"]), cause], "danger", 600.0)
	colonist_died.emit(c)
	if colonists.is_empty():
		game_over = true
		speed = 0
		_log("The last hearth has gone cold.", "danger")
		colony_fallen.emit()
	changed.emit()

# -----------------------------------------------------------------------------
# Colonist decisions and need actions
# -----------------------------------------------------------------------------

func _choose_action(c: Dictionary) -> void:
	if bool(c.get("waiting_for_care", false)):
		c["state"] = "idle"
		c["action_text"] = "Waiting for care"
		c["decision_timer"] = 1.0
		return
	c["decision_timer"] = 0.7
	var needs: Dictionary = c["needs"]
	if float(c["health"]) < 24.0:
		if _start_rest(c):
			return
	if float(needs["hunger"]) < 32.0:
		if _start_eat(c):
			return
	var night_sleep := is_night() and float(needs["fatigue"]) < 66.0
	if float(needs["fatigue"]) < 24.0 or night_sleep:
		if _start_sleep(c):
			return
	if float(needs["warmth"]) < 32.0:
		if _start_warm(c):
			return
	if float(needs["hygiene"]) < 22.0:
		if _start_wash(c):
			return
	if _pick_job(c):
		return
	_idle_behavior(c)

func _start_eat(c: Dictionary) -> bool:
	var food := best_food()
	if food.is_empty():
		c["action_text"] = "No food"
		c["state"] = "idle"
		if time_min - float(c.get("last_no_food_alert", -1000.0)) > 240.0:
			c["last_no_food_alert"] = time_min
			_alert("The stores are empty", "There is nothing left to eat. Forage or harvest before hunger turns dangerous.", "danger", 300.0)
			_log("%s searches the empty stores for something to eat." % str(c["first_name"]), "danger")
		c["decision_timer"] = 3.0
		return false
	var goal := _nearest_food_store_tile(c)
	var path := _find_path(colonist_tile(c), goal)
	if path.is_empty():
		c["action_text"] = "Cannot reach the stores"
		c["decision_timer"] = 3.0
		return false
	c["action_data"] = {"type": "eat", "food": food}
	c["path"] = path
	c["path_goal"] = goal
	c["state"] = "moving"
	c["action_text"] = "Going to eat"
	return true

func _nearest_food_store_tile(c: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 1e20
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		if float(def.get("storage", 0.0)) <= 0.0:
			continue
		var rect := building_footprint(b)
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var tile := Vector2i(x, y)
				if not is_walkable(tile):
					continue
				var dist := Vector2(tile).distance_squared_to(Vector2(c["pos"]))
				if dist < best_dist:
					best_dist = dist
					best = tile
	if best.x < 0:
		var camp := _nearest_warm_building(c, true)
		if not camp.is_empty():
			best = _best_adjacent_tile(camp, Vector2(c["pos"]))
	if best.x < 0:
		best = _nearest_walkable(colonist_tile(c))
	return best

func _start_sleep(c: Dictionary) -> bool:
	var bed := _free_bed(c)
	var goal := Vector2i(-1, -1)
	var bed_id := -1
	if not bed.is_empty():
		bed_id = int(bed["id"])
		goal = _best_adjacent_tile(bed, Vector2(c["pos"]))
	else:
		var fire := _nearest_warm_building(c, true)
		if not fire.is_empty():
			goal = _best_adjacent_tile(fire, Vector2(c["pos"]))
		if goal.x < 0:
			goal = _nearest_walkable(colonist_tile(c))
	var path := _find_path(colonist_tile(c), goal)
	if path.is_empty():
		c["action_text"] = "Too tired to find a bed"
		c["decision_timer"] = 4.0
		return false
	c["action_data"] = {"type": "sleep", "bed_id": bed_id}
	c["path"] = path
	c["path_goal"] = goal
	c["state"] = "moving"
	c["action_text"] = "Looking for a place to sleep"
	return true

func _free_bed(c: Dictionary) -> Dictionary:
	var best := {}
	var best_dist := 1e20
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		var beds := int(def.get("beds", 0))
		if beds <= 0 or b.get("occupants", []).size() >= beds:
			continue
		var dist := building_center(b).distance_squared_to(Vector2(c["pos"]))
		if dist < best_dist:
			best_dist = dist
			best = b
	return best

func _nearest_warm_building(c: Dictionary, require_heat: bool = false) -> Dictionary:
	var best := {}
	var best_dist := 1e20
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		if require_heat and float(def.get("warmth", 0.0)) <= 0.0:
			continue
		var dist := building_center(b).distance_squared_to(Vector2(c["pos"]))
		if dist < best_dist:
			best_dist = dist
			best = b
	return best

func _start_warm(c: Dictionary) -> bool:
	var fire := _nearest_warm_building(c, true)
	if fire.is_empty():
		c["action_text"] = "No fire to warm by"
		c["decision_timer"] = 5.0
		return false
	var goal := _best_adjacent_tile(fire, Vector2(c["pos"]))
	if goal.x < 0:
		goal = building_footprint(fire).position
	if Vector2(colonist_tile(c)).distance_to(Vector2(goal)) < 2.0:
		c["state"] = "warming"
		c["action_data"] = {"type": "warm", "building_id": int(fire["id"])}
		c["action_timer"] = 32.0
		c["action_text"] = "Warming by the fire"
		c["path"].clear()
		return true
	var path := _find_path(colonist_tile(c), goal)
	if path.is_empty():
		c["decision_timer"] = 3.0
		return false
	c["action_data"] = {"type": "warm", "building_id": int(fire["id"])}
	c["path"] = path
	c["path_goal"] = goal
	c["state"] = "moving"
	c["action_text"] = "Seeking warmth"
	return true

func _start_wash(c: Dictionary) -> bool:
	var well := {}
	var best_dist := 1e20
	for b in built_buildings_of_type("well"):
		var dist := building_center(b).distance_squared_to(Vector2(c["pos"]))
		if dist < best_dist:
			best_dist = dist
			well = b
	var goal := Vector2i(-1, -1)
	if not well.is_empty():
		goal = _best_adjacent_tile(well, Vector2(c["pos"]))
	else:
		goal = _nearest_water_edge(colonist_tile(c))
	if goal.x < 0:
		c["action_text"] = "Could use a wash"
		c["decision_timer"] = 8.0
		return false
	var path := _find_path(colonist_tile(c), goal)
	if path.is_empty():
		c["decision_timer"] = 3.0
		return false
	c["action_data"] = {"type": "wash", "well": not well.is_empty()}
	c["path"] = path
	c["path_goal"] = goal
	c["state"] = "moving"
	c["action_text"] = "Going to wash up"
	return true

func _nearest_water_edge(from_tile: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 1e20
	for y in range(map_h):
		for x in range(map_w):
			if str(tiles[y][x]["terrain"]) != "water":
				continue
			var tile := Vector2i(x, y)
			for neighbor in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var candidate: Vector2i = tile + neighbor
				if is_walkable(candidate):
					var dist := Vector2(candidate).distance_squared_to(Vector2(from_tile))
					if dist < best_dist:
						best_dist = dist
						best = candidate
	return best

func _start_rest(c: Dictionary) -> bool:
	var bed := _free_bed(c)
	var goal := Vector2i(-1, -1)
	if not bed.is_empty():
		goal = _best_adjacent_tile(bed, Vector2(c["pos"]))
	else:
		var fire := _nearest_warm_building(c, true)
		if not fire.is_empty():
			goal = _best_adjacent_tile(fire, Vector2(c["pos"]))
	if goal.x < 0:
		goal = _nearest_walkable(colonist_tile(c))
	if colonist_tile(c) == goal:
		c["state"] = "resting"
		c["action_data"] = {"type": "rest"}
		c["action_timer"] = 90.0
		c["action_text"] = "Resting and recovering"
		return true
	var path := _find_path(colonist_tile(c), goal)
	if path.is_empty():
		c["decision_timer"] = 4.0
		return false
	c["action_data"] = {"type": "rest"}
	c["path"] = path
	c["path_goal"] = goal
	c["state"] = "moving"
	c["action_text"] = "Looking for a place to rest"
	return true

func _idle_behavior(c: Dictionary) -> void:
	c["social_cooldown"] = maxf(0.0, float(c.get("social_cooldown", 0.0)) - 1.0)
	if not is_night() and float(c.get("social_cooldown", 0.0)) <= 0.0 and rng.randf() < 0.32:
		if _start_social(c):
			return
	var target := _random_walkable_near(COLONY_CENTER, 7.0)
	if target.x < 0:
		target = _nearest_walkable(colonist_tile(c))
	if target == colonist_tile(c):
		c["state"] = "idle"
		c["action_text"] = "Taking a breath"
		c["decision_timer"] = rng.randf_range(1.5, 4.0)
		return
	var path := _find_path(colonist_tile(c), target)
	if path.is_empty():
		c["state"] = "idle"
		c["action_text"] = "Taking a breath"
		c["decision_timer"] = 2.0
		return
	c["state"] = "moving"
	c["action_data"] = {"type": "wander"}
	c["path"] = path
	c["path_goal"] = target
	c["action_text"] = "Wandering the clearing"

func _start_social(c: Dictionary) -> bool:
	var best := {}
	var best_score := -1e20
	for other in colonists:
		if int(other["id"]) == int(c["id"]) or str(other["state"]) != "idle":
			continue
		if is_night():
			continue
		var dist := Vector2(c["pos"]).distance_to(Vector2(other["pos"]))
		if dist > 8.0:
			continue
		var affinity := float(c.get("relationships", {}).get(str(other["id"]), 0.0))
		var score := -dist + affinity * 0.1
		if score > best_score:
			best_score = score
			best = other
	if best.is_empty():
		return false
	var goal := _nearest_walkable(colonist_tile(best))
	var path := _find_path(colonist_tile(c), goal)
	if path.is_empty():
		return false
	c["action_data"] = {"type": "social", "target_id": int(best["id"])}
	c["path"] = path
	c["path_goal"] = goal
	c["state"] = "moving"
	c["action_text"] = "Going to talk with %s" % str(best["first_name"])
	return true

func _random_walkable_near(center: Vector2, radius: float) -> Vector2i:
	for attempt in range(30):
		var x := int(round(center.x + rng.randf_range(-radius, radius)))
		var y := int(round(center.y + rng.randf_range(-radius, radius)))
		var tile := Vector2i(x, y)
		if _tile_in_bounds(tile) and is_walkable(tile):
			return tile
	return Vector2i(-1, -1)

func _advance_path(c: Dictionary, sim_dt: float) -> bool:
	var path: Array = c.get("path", [])
	if path.is_empty():
		return true
	var injury_penalty := 1.0 - minf(0.45, float(c["injury"]) / 150.0)
	var fatigue_penalty := 0.78 + minf(0.22, float(c["needs"]["fatigue"]) / 450.0)
	var weather_move := float(HFDefs.WEATHER.get(weather, {}).get("move", 1.0))
	var speed_tiles := 2.35 * injury_penalty * fatigue_penalty * weather_move
	var budget := speed_tiles * sim_dt
	while budget > 0.0 and not path.is_empty():
		var next_tile: Vector2i = path[0]
		if not is_walkable(next_tile):
			path.clear()
			break
		var target := Vector2(next_tile) + Vector2(0.5, 0.5)
		var current := Vector2(c["pos"])
		var dist := current.distance_to(target)
		if dist <= budget:
			c["pos"] = target
			path.pop_front()
			budget -= dist
		else:
			c["pos"] = current + (target - current).normalized() * budget
			budget = 0.0
	c["path"] = path
	return path.is_empty()

func _on_arrive(c: Dictionary) -> void:
	var job_id := int(c.get("job_id", -1))
	if job_id != -1:
		_begin_job(c, get_job(job_id))
		return
	var data: Dictionary = c.get("action_data", {})
	match str(data.get("type", "")):
		"eat":
			var food := str(data.get("food", ""))
			if resource_qty(food) <= 0:
				c["state"] = "idle"
				c["action_data"] = {}
				c["action_text"] = "The meal was gone"
				c["decision_timer"] = 2.0
				return
			remove_resource(food, 1)
			var food_def: Dictionary = HFDefs.RESOURCES.get(food, {})
			data["nutrition"] = float(food_def.get("food", 10.0))
			data["raw"] = bool(food_def.get("raw", false))
			data["food_name"] = str(food_def.get("name", food))
			c["action_data"] = data
			c["state"] = "eating"
			c["action_timer"] = 22.0
			c["action_text"] = "Eating %s" % str(food_def.get("name", food))
		"wash":
			c["state"] = "washing"
			c["action_timer"] = 16.0
			c["action_text"] = "Washing up"
		"warm":
			c["state"] = "warming"
			c["action_timer"] = 32.0
			c["action_text"] = "Warming by the fire"
		"rest":
			c["state"] = "resting"
			c["action_timer"] = 90.0
			c["action_text"] = "Resting and recovering"
		"sleep":
			var bed_id := int(data.get("bed_id", -1))
			var bed := get_building(bed_id)
			if not bed.is_empty() and not bed["occupants"].has(int(c["id"])):
				bed["occupants"].append(int(c["id"]))
			c["bed_id"] = bed_id
			c["state"] = "sleeping"
			c["action_timer"] = _sleep_minutes_remaining()
			c["action_text"] = "Sleeping in a bed" if bed_id != -1 else "Sleeping on the ground"
			c["path"].clear()
		"social":
			var target := colonist_by_id(int(data.get("target_id", -1)))
			if target.is_empty() or str(target["state"]) != "idle":
				c["state"] = "idle"
				c["action_data"] = {}
				c["action_text"] = "Idle"
				c["decision_timer"] = 2.0
				return
			if Vector2(c["pos"]).distance_to(Vector2(target["pos"])) > 3.0:
				c["state"] = "idle"
				c["action_data"] = {}
				c["decision_timer"] = 2.0
				return
			c["state"] = "socializing"
			c["action_timer"] = rng.randf_range(22.0, 42.0)
			c["action_text"] = "Talking with %s" % str(target["first_name"])
			target["social_target"] = int(c["id"])
			target["state"] = "socializing"
			target["action_timer"] = float(c["action_timer"])
			target["action_text"] = "Talking with %s" % str(c["first_name"])
			target["action_data"] = {"type": "social", "target_id": int(c["id"])}
			target["path"].clear()
		"wander", "":
			c["state"] = "idle"
			c["action_data"] = {}
			c["action_text"] = "Idle"
			c["decision_timer"] = rng.randf_range(1.0, 3.0)

func _sleep_minutes_remaining() -> float:
	var minutes_left := 0.0
	if hour >= 21:
		minutes_left = float((24 - hour) * 60 - minute) + 7.0 * 60.0
	elif hour < 7:
		minutes_left = float((7 - hour) * 60 - minute)
	else:
		minutes_left = 8.0 * 60.0
	return clampf(minutes_left, 180.0, 620.0)

func _tick_sleep(c: Dictionary, game_minutes: float) -> void:
	var bed_id := int(c.get("bed_id", -1))
	var bed_quality := 1.0
	if bed_id != -1:
		var bed := get_building(bed_id)
		if bed.is_empty() or not bool(bed.get("built", false)):
			bed_quality = 0.58
			c["bed_id"] = -1
	else:
		bed_quality = 0.58
	var rest_rate := 8.8 * bed_quality * trait_mod(c, "sleep", 1.0)
	c["needs"]["fatigue"] = clampf(float(c["needs"]["fatigue"]) + rest_rate * (game_minutes / 60.0), 0.0, 100.0)
	c["action_timer"] = float(c["action_timer"]) - game_minutes
	var dangerous := _danger_near(c, 4.5)
	if dangerous and rng.randf() < 0.005 * game_minutes:
		c["action_timer"] = 0.0
	if float(c["action_timer"]) <= 0.0 or float(c["needs"]["fatigue"]) >= 96.0:
		_end_sleep(c)

func _danger_near(c: Dictionary, radius: float) -> bool:
	for animal in animals:
		if bool(animal.get("hostile", false)) and Vector2(c["pos"]).distance_to(Vector2(animal["pos"])) < radius:
			return true
	return false

func _end_sleep(c: Dictionary) -> void:
	var bed_id := int(c.get("bed_id", -1))
	if bed_id != -1:
		var bed := get_building(bed_id)
		if not bed.is_empty():
			bed["occupants"].erase(int(c["id"]))
		_add_mood(c, "Slept in a bed", 5.0, 5.0)
		if rng.randf() < 0.18:
			_log("%s wakes rested under a proper roof." % str(c["first_name"]), "story")
	else:
		_add_mood(c, "Slept on the cold ground", -6.0, 5.0)
		if rng.randf() < 0.2:
			_log("%s wakes stiff and cold on the bare ground." % str(c["first_name"]), "story")
	c["bed_id"] = -1
	c["state"] = "idle"
	c["action_data"] = {}
	c["action_text"] = "Waking up"
	c["decision_timer"] = rng.randf_range(0.4, 1.4)

func _tick_action(c: Dictionary, game_minutes: float) -> void:
	if str(c["state"]) == "socializing":
		var target := colonist_by_id(int(c.get("social_target", -1)))
		if target.is_empty() or str(target["state"]) != "socializing":
			_finish_action(c)
			return
		target["action_timer"] = float(target["action_timer"]) - game_minutes
	c["action_timer"] = float(c["action_timer"]) - game_minutes
	if float(c["action_timer"]) <= 0.0:
		_finish_action(c)

func _finish_action(c: Dictionary) -> void:
	var data: Dictionary = c.get("action_data", {})
	match str(data.get("type", "")):
		"eat":
			var nutrition := float(data.get("nutrition", 12.0))
			c["needs"]["hunger"] = clampf(float(c["needs"]["hunger"]) + nutrition, 0.0, 100.0)
			if bool(data.get("raw", false)):
				_add_mood(c, "A raw, hurried meal", -2.0, 3.0)
				if rng.randf() < 0.045:
					c["illness"] = maxf(float(c["illness"]), rng.randf_range(8.0, 18.0))
			else:
				_add_mood(c, "A warm meal", 5.0, 4.0)
			if int(c.get("last_eat_log_day", -1)) != absolute_day and not bool(data.get("raw", false)):
				c["last_eat_log_day"] = absolute_day
				_log("%s eats %s and looks a little more themselves." % [str(c["first_name"]), str(data.get("food_name", "a meal"))], "story")
		"wash":
			c["needs"]["hygiene"] = clampf(float(c["needs"]["hygiene"]) + (65.0 if bool(data.get("well", false)) else 38.0), 0.0, 100.0)
			_add_mood(c, "Clean and refreshed", 3.0, 3.0)
		"warm":
			c["needs"]["warmth"] = clampf(float(c["needs"]["warmth"]) + 34.0, 0.0, 100.0)
			_add_mood(c, "Warm by the fire", 3.0, 3.0)
		"rest":
			c["health"] = clampf(float(c["health"]) + 4.0, 0.0, 100.0)
			c["action_text"] = "Resting"
		"social":
			_complete_social(c, data)
	c["state"] = "idle"
	c["action_data"] = {}
	c["action_text"] = "Idle"
	c["decision_timer"] = rng.randf_range(0.3, 1.2)
	c["social_target"] = -1

func _complete_social(c: Dictionary, data: Dictionary) -> void:
	var target := colonist_by_id(int(data.get("target_id", -1)))
	if target.is_empty():
		return
	var c_social := skill_value(c, "social")
	var t_social := skill_value(target, "social")
	var compatibility := (c_social + t_social) * 0.8
	var c_mood := float(c["mood"])
	var t_mood := float(target["mood"])
	var change := rng.randi_range(-3, 7) + int(round(compatibility * 0.4))
	if c_mood < 25.0 or t_mood < 25.0:
		change -= 5
	change = clampi(change, -10, 12)
	var old_value := float(c.get("relationships", {}).get(str(target["id"]), 0.0))
	var new_value := clampi(int(round(old_value + change * trait_mod(c, "social", 1.0))), -100, 100)
	c["relationships"][str(target["id"])] = new_value
	target["relationships"][str(c["id"])] = new_value
	if change > 5:
		_add_mood(c, "Good conversation", 3.0, 4.0)
		_add_mood(target, "Good conversation", 3.0, 4.0)
		if old_value < 15.0 and new_value >= 15.0:
			_log("%s and %s are becoming friends." % [str(c["first_name"]), str(target["first_name"])], "story")
	elif change < -2:
		_add_mood(c, "A tense exchange", -3.0, 3.0)
		_add_mood(target, "A tense exchange", -3.0, 3.0)
		if new_value < -35.0 and old_value >= -35.0:
			_log("An argument leaves %s and %s avoiding each other." % [str(c["first_name"]), str(target["first_name"])], "story")
	c["social_cooldown"] = 180.0
	target["social_cooldown"] = 180.0
	target["state"] = "idle"
	target["action_data"] = {}
	target["action_text"] = "Idle"
	target["decision_timer"] = rng.randf_range(0.3, 1.2)
	target["social_target"] = -1
	_gain_skill(c, "social", 0.7)
	_gain_skill(target, "social", 0.3)

# -----------------------------------------------------------------------------
# Jobs and autonomous work
# -----------------------------------------------------------------------------

func get_job(id: int) -> Dictionary:
	for job in jobs:
		if int(job.get("id", -1)) == id:
			return job
	return {}

func _job_category(type: String) -> String:
	match type:
		"build":
			return "build"
		"gather":
			return "gather"
		"farm_sow", "farm_harvest":
			return "farm"
		"cook":
			return "cook"
		"craft":
			return "craft"
		"haul":
			return "haul"
		"heal":
			return "care"
		"hunt", "defend":
			return "hunt"
		"study":
			return "study"
		"firefight":
			return "fire"
	return "haul"

func _job_skill(type: String) -> String:
	match type:
		"gather", "build", "haul":
			return "labor"
		"farm_sow", "farm_harvest":
			return "farming"
		"cook":
			return "cooking"
		"craft", "study":
			return "crafting"
		"heal":
			return "medicine"
		"hunt", "defend":
			return "combat"
	return "labor"

func _add_job(type: String, data: Dictionary = {}) -> int:
	var category := _job_category(type)
	var work_required := float(data.get("work_required", 4.0))
	if type == "build":
		var building := get_building(int(data.get("building_id", -1)))
		var bdef: Dictionary = HFDefs.BUILDINGS.get(str(building.get("key", "")), {})
		work_required = float(bdef.get("build_time", 8.0))
	elif type == "cook":
		work_required = 5.0
	elif type == "craft":
		work_required = 5.5
	elif type == "study":
		work_required = 8.0
	elif type == "heal":
		work_required = 7.0
	elif type in ["hunt", "defend"]:
		work_required = 1.35
	elif type == "firefight":
		work_required = 9999.0
	var job := {
		"id": next_job_id,
		"type": type,
		"category": category,
		"worker_id": -1,
		"progress": 0.0,
		"work_required": work_required,
		"priority": int(data.get("priority", 1)),
		"target": data.get("target", Vector2i(-1, -1)),
		"building_id": int(data.get("building_id", -1)),
		"pile_id": int(data.get("pile_id", -1)),
		"animal_id": int(data.get("animal_id", -1)),
		"patient_id": int(data.get("patient_id", -1)),
		"farm_action": str(data.get("farm_action", "")),
		"object_key": str(data.get("object_key", "")),
		"resource": str(data.get("resource", "")),
		"recipe": data.get("recipe", {}),
		"output_resource": str(data.get("output_resource", "")),
		"output_amount": int(data.get("output_amount", 0)),
		"phase": "to_pile" if type == "haul" else "to_work",
		"consumed": false,
		"auto": bool(data.get("auto", false)),
		"auto_resource": str(data.get("auto_resource", "")),
		"player": bool(data.get("player", false)),
		"blocked_until": 0.0,
		"failed_claims": 0,
		"created": time_min,
	}
	next_job_id += 1
	jobs.append(job)
	return int(job["id"])

func _remove_job(job: Dictionary) -> void:
	if job.is_empty():
		return
	var worker_id := int(job.get("worker_id", -1))
	if worker_id != -1:
		var worker := colonist_by_id(worker_id)
		if not worker.is_empty() and int(worker.get("job_id", -1)) == int(job["id"]):
			worker["job_id"] = -1
			worker["state"] = "idle"
			worker["action_text"] = "Idle"
			worker["decision_timer"] = 0.4
	if int(job.get("patient_id", -1)) != -1:
		var patient := colonist_by_id(int(job["patient_id"]))
		if not patient.is_empty():
			patient["waiting_for_care"] = false
			if str(patient.get("action_text", "")) == "Waiting for care":
				patient["action_text"] = "Idle"
	if int(job.get("building_id", -1)) != -1 and str(job.get("type", "")) in ["cook", "craft", "study"]:
		var b := get_building(int(job["building_id"]))
		if not b.is_empty():
			b["station_busy"] = false
	jobs.erase(job)

func cancel_job(job_id: int) -> void:
	var job := get_job(job_id)
	if job.is_empty():
		return
	_remove_job(job)
	changed.emit()

func queue_herb_order() -> String:
	if storage_free() < 4.0:
		return "Storage is too full for another harvest."
	var tile := _find_resource_object(["herbs"], 28.0)
	if tile.x < 0:
		return "No wild herbs are close enough to gather."
	var job_id := _create_gather_job(tile, 3, false, "")
	if job_id < 0:
		return "Those herbs are already marked for gathering."
	var job := get_job(job_id)
	if not job.is_empty():
		job["player"] = true
	var t := tile_at(tile)
	var od: Dictionary = HFDefs.OBJECTS.get(str(t.get("object", "")), {})
	_log("Herbs marked for gathering: %s." % str(od.get("name", "wild herbs")), "work")
	changed.emit()
	return "Marked %s for gathering." % str(od.get("name", "wild herbs"))

func _release_job(c: Dictionary, drop_carry: bool = true) -> void:
	var job := get_job(int(c.get("job_id", -1)))
	if not job.is_empty():
		job["worker_id"] = -1
		if str(job.get("type", "")) == "haul":
			if not c.get("carry", {}).is_empty():
				_spawn_pile(str(c["carry"].get("resource", "wood")), int(c["carry"].get("amount", 0)), colonist_tile(c))
				c["carry"] = {}
			_remove_job(job)
		elif str(job.get("type", "")) == "heal":
			var patient := colonist_by_id(int(job.get("patient_id", -1)))
			if not patient.is_empty():
				patient["waiting_for_care"] = false
	if drop_carry and not c.get("carry", {}).is_empty():
		_spawn_pile(str(c["carry"].get("resource", "wood")), int(c["carry"].get("amount", 0)), colonist_tile(c))
		c["carry"] = {}
	c["job_id"] = -1
	c["job_phase"] = "to_work"
	c["state"] = "idle"
	c["action_text"] = "Idle"
	c["action_data"] = {}
	c["path"].clear()
	c["decision_timer"] = 0.35

func _pick_job(c: Dictionary) -> bool:
	var candidates: Array = []
	for job in jobs:
		if int(job.get("worker_id", -1)) != -1:
			continue
		if float(job.get("blocked_until", 0.0)) > time_min:
			continue
		var category := str(job.get("category", "haul"))
		var priority := int(c.get("priorities", {}).get(category, 0))
		if priority <= 0:
			continue
		var work_tile := _job_work_tile(job, c)
		if work_tile.x < 0:
			continue
		var dist := Vector2(work_tile).distance_to(Vector2(c["pos"]))
		var skill_bonus := skill_value(c, _job_skill(str(job["type"]))) * 2.4
		var urgency := int(job.get("priority", 1)) * 18.0
		var score := float(priority) * 100.0 + urgency + skill_bonus - dist * 1.7
		if str(job.get("type", "")) == "firefight":
			score += 300.0
		candidates.append({"job": job, "score": score, "tile": work_tile, "distance": dist})
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	for entry in candidates.slice(0, mini(8, candidates.size())):
		var job: Dictionary = entry["job"]
		if int(job.get("worker_id", -1)) != -1:
			continue
		var work_tile: Vector2i = _job_work_tile(job, c)
		if work_tile.x < 0:
			continue
		var path := _find_path(colonist_tile(c), work_tile)
		if path.is_empty():
			job["failed_claims"] = int(job.get("failed_claims", 0)) + 1
			if int(job["failed_claims"]) >= 3:
				job["blocked_until"] = time_min + 12.0
			continue
		job["worker_id"] = int(c["id"])
		if str(job["type"]) == "haul":
			if str(job.get("phase", "to_pile")) == "to_work":
				job["phase"] = "to_pile"
		else:
			job["phase"] = "to_work"
		c["job_id"] = int(job["id"])
		c["job_phase"] = "to_work"
		c["path"] = path
		c["path_goal"] = work_tile
		c["state"] = "moving"
		c["action_text"] = _job_action_label(c, job)
		c["decision_timer"] = 1.0
		return true
	return false

func _best_adjacent_to_tile(tile: Vector2i, from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 1e20
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var candidate: Vector2i = tile + dir
		if is_walkable(candidate):
			var dist := Vector2(candidate).distance_squared_to(from)
			if dist < best_dist:
				best_dist = dist
				best = candidate
	return best

func _job_work_tile(job: Dictionary, c: Dictionary) -> Vector2i:
	match str(job.get("type", "")):
		"build", "cook", "craft", "study", "firefight":
			var b := get_building(int(job.get("building_id", -1)))
			if b.is_empty():
				return Vector2i(-1, -1)
			var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
			if bool(def.get("walkable", false)) and bool(b.get("built", false)):
				return _nearest_walkable(Vector2i(floori(building_center(b).x), floori(building_center(b).y)))
			return _best_adjacent_tile(b, Vector2(c["pos"]))
		"farm_sow", "farm_harvest":
			var farm := get_building(int(job.get("building_id", -1)))
			if farm.is_empty():
				return Vector2i(-1, -1)
			return _nearest_walkable(Vector2i(floori(building_center(farm).x), floori(building_center(farm).y)))
		"gather":
			var target: Vector2i = job.get("target", Vector2i(-1, -1))
			var tile := tile_at(target)
			if tile.is_empty():
				return Vector2i(-1, -1)
			var od: Dictionary = object_def(tile)
			if bool(od.get("blocking", false)):
				return _best_adjacent_to_tile(target, Vector2(c["pos"]))
			return target
		"haul":
			if str(job.get("phase", "to_pile")) == "to_store":
				return _nearest_storage_tile(c)
			var pile := _get_pile(int(job.get("pile_id", -1)))
			if pile.is_empty():
				return Vector2i(-1, -1)
			return _nearest_walkable(pile["tile"])
		"heal":
			var patient := colonist_by_id(int(job.get("patient_id", -1)))
			if patient.is_empty():
				return Vector2i(-1, -1)
			return _best_adjacent_to_tile(colonist_tile(patient), Vector2(c["pos"]))
		"hunt", "defend":
			var animal := _get_animal(int(job.get("animal_id", -1)))
			if animal.is_empty():
				return Vector2i(-1, -1)
			return _best_adjacent_to_tile(tile_of(Vector2(animal["pos"])), Vector2(c["pos"]))
	return Vector2i(-1, -1)

func _job_action_label(c: Dictionary, job: Dictionary) -> String:
	match str(job.get("type", "")):
		"build":
			var b := get_building(int(job.get("building_id", -1)))
			var name := str(HFDefs.BUILDINGS.get(str(b.get("key", "")), {}).get("name", "building"))
			return "Building %s" % name
		"gather":
			var tile := tile_at(job.get("target", Vector2i(-1, -1)))
			var od: Dictionary = object_def(tile)
			var resource := str(od.get("resource", "materials"))
			return "Gathering %s" % HFDefs.resource_name(resource)
		"farm_sow":
			return "Sowing the fields"
		"farm_harvest":
			return "Harvesting crops"
		"cook":
			return "Cooking a meal"
		"craft":
			return "Crafting tools"
		"haul":
			return "Hauling supplies"
		"heal":
			var patient := colonist_by_id(int(job.get("patient_id", -1)))
			return "Treating %s" % str(patient.get("first_name", "a patient"))
		"hunt":
			var animal := _get_animal(int(job.get("animal_id", -1)))
			return "Hunting %s" % str(animal.get("name", "game"))
		"defend":
			return "Driving off a predator"
		"study":
			return "Studying old ledgers"
		"firefight":
			return "Fighting a fire"
	return "Working"

func _begin_job(c: Dictionary, job: Dictionary) -> void:
	if job.is_empty() or int(job.get("worker_id", -1)) != int(c["id"]):
		c["job_id"] = -1
		c["state"] = "idle"
		c["action_text"] = "Idle"
		return
	if str(job["type"]) == "haul":
		if str(job.get("phase", "to_pile")) != "to_store":
			if not _pickup_pile(c, job):
				_release_job(c, true)
			return
		_deposit_carry(c)
		_finish_job(c, job)
		return
	if str(job["type"]) in ["heal", "hunt", "defend"]:
		var target_tile := _job_work_tile(job, c)
		if target_tile.x < 0:
			_fail_job(c, job, "")
			return
		if Vector2(colonist_tile(c)).distance_to(Vector2(target_tile)) > 1.8:
			var path := _find_path(colonist_tile(c), target_tile)
			if path.is_empty():
				job["blocked_until"] = time_min + 8.0
				_release_job(c, false)
				return
			c["path"] = path
			c["path_goal"] = target_tile
			c["state"] = "moving"
			return
	if str(job["type"]) == "heal":
		var patient := colonist_by_id(int(job.get("patient_id", -1)))
		if not patient.is_empty():
			_release_job(patient, true)
			patient["waiting_for_care"] = true
			patient["state"] = "idle"
			patient["action_text"] = "Waiting for care"
			patient["decision_timer"] = 1.0
			patient["path"].clear()
	if str(job["type"]) in ["cook", "craft"] and not bool(job.get("consumed", false)):
		if not has_resources(job.get("recipe", {})):
			_fail_job(c, job, "The ingredients were gone.")
			return
		_pay_resources(job.get("recipe", {}))
		job["consumed"] = true
	c["state"] = "working"
	c["action_text"] = _job_action_label(c, job)
	c["path"].clear()

func _tick_work(c: Dictionary, sim_dt: float) -> void:
	var job := get_job(int(c.get("job_id", -1)))
	if job.is_empty():
		c["job_id"] = -1
		c["state"] = "idle"
		c["action_text"] = "Idle"
		return
	if str(job["type"]) == "firefight":
		var b := get_building(int(job.get("building_id", -1)))
		if b.is_empty() or float(b.get("burning", 0.0)) <= 0.0:
			_finish_job(c, job)
			return
		var water_bonus := 1.2 if _near_built("well", building_center(b), 8.0) else 0.0
		var fighting := 2.4 + skill_value(c, "labor") * 0.35 + water_bonus
		b["burning"] = maxf(0.0, float(b["burning"]) - fighting * sim_dt)
		c["action_text"] = "Fighting the fire"
		if rng.randf() < 0.0018 * sim_dt * 60.0:
			c["injury"] = clampf(float(c["injury"]) + rng.randf_range(5.0, 15.0), 0.0, 100.0)
			c["health"] = maxf(1.0, float(c["health"]) - 8.0)
			_add_mood(c, "Burned while fighting fire", -8.0, 8.0)
			_log("%s is burned fighting the fire." % str(c["first_name"]), "danger")
		if float(b["burning"]) <= 0.0:
			_finish_job(c, job)
		return
	if str(job["type"]) in ["hunt", "defend"]:
		var animal := _get_animal(int(job.get("animal_id", -1)))
		if animal.is_empty():
			_finish_job(c, job)
			return
		var distance := Vector2(c["pos"]).distance_to(Vector2(animal["pos"]))
		if distance > 2.2:
			var new_tile := _job_work_tile(job, c)
			var path := _find_path(colonist_tile(c), new_tile)
			if path.is_empty():
				_release_job(c, false)
				return
			c["path"] = path
			c["path_goal"] = new_tile
			c["state"] = "moving"
			return
		var attack_speed := _work_speed(c, job)
		job["progress"] = float(job["progress"]) + sim_dt * attack_speed
		c["action_text"] = _job_action_label(c, job)
		if float(job["progress"]) >= float(job["work_required"]):
			job["progress"] = 0.0
			_attack_animal(c, job, animal)
		return
	if str(job["type"]) == "heal":
		var patient := colonist_by_id(int(job.get("patient_id", -1)))
		if patient.is_empty():
			_finish_job(c, job)
			return
		if Vector2(c["pos"]).distance_to(Vector2(patient["pos"])) > 2.2:
			var new_tile := _job_work_tile(job, c)
			var path := _find_path(colonist_tile(c), new_tile)
			if path.is_empty():
				_release_job(c, false)
				return
			c["path"] = path
			c["path_goal"] = new_tile
			c["state"] = "moving"
			return
	job["progress"] = float(job["progress"]) + sim_dt * _work_speed(c, job)
	var total := maxf(0.01, float(job["work_required"]))
	var percent := int(clampf(float(job["progress"]) / total, 0.0, 1.0) * 100.0)
	c["action_text"] = "%s %d%%" % [_job_action_label(c, job), percent]
	if float(job["progress"]) >= total:
		_finish_job(c, job)

func _work_speed(c: Dictionary, job: Dictionary) -> float:
	var skill := skill_value(c, _job_skill(str(job["type"])))
	var speed := 0.72 + skill * 0.035
	speed *= 0.78 + float(c["mood"]) / 220.0
	speed *= trait_mod(c, "work", 1.0)
	if is_night() and has_trait(c, "night_owl"):
		speed *= float(HFDefs.TRAITS["night_owl"].get("night_work", 1.18))
	if research_index > 0:
		speed *= float(HFDefs.TECH[0].get("value", 1.12))
	if resource_qty("tools") > 0 and str(job["type"]) in ["gather", "build", "craft", "haul"]:
		speed *= 1.08
	if weather in ["rain", "storm"]:
		speed *= 0.88
	elif weather == "snow":
		speed *= 0.78
	if str(job["type"]) == "gather":
		var gather_tile := Vector2(job.get("target", Vector2i(-1, -1)))
		if str(job.get("resource", "")) == "wood" and _near_built("lumber_camp", gather_tile, 10.0):
			speed *= 1.12
		if str(job.get("resource", "")) in ["stone", "ore", "coal"] and _near_built("mine", gather_tile, 10.0):
			speed *= 1.12
	if str(job["type"]) == "craft":
		var craft_b := get_building(int(job.get("building_id", -1)))
		if not craft_b.is_empty() and _near_built("forge", building_center(craft_b), 10.0):
			speed *= 1.18
	return maxf(0.25, speed)

func _finish_job(c: Dictionary, job: Dictionary) -> void:
	if job.is_empty():
		return
	match str(job["type"]):
		"build":
			_complete_build(c, job)
		"gather":
			_complete_gather(c, job)
		"farm_sow":
			_complete_farm_sow(c, job)
		"farm_harvest":
			_complete_farm_harvest(c, job)
		"cook", "craft":
			_complete_station(c, job)
		"study":
			_complete_study(c, job)
		"heal":
			_complete_heal(c, job)
		"hunt", "defend":
			_complete_hunt(c, job)
		"firefight":
			_complete_fire(c, job)
		"haul":
			pass
	if int(job.get("building_id", -1)) != -1 and str(job["type"]) in ["cook", "craft", "study"]:
		var b := get_building(int(job["building_id"]))
		if not b.is_empty():
			b["station_busy"] = false
	if int(job.get("patient_id", -1)) != -1:
		var patient := colonist_by_id(int(job["patient_id"]))
		if not patient.is_empty():
			patient["waiting_for_care"] = false
			if str(patient.get("action_text", "")) == "Waiting for care":
				patient["action_text"] = "Idle"
	jobs.erase(job)
	c["job_id"] = -1
	c["job_phase"] = "to_work"
	c["state"] = "idle"
	c["action_text"] = "Idle"
	c["path"].clear()
	c["action_data"] = {}
	c["decision_timer"] = 0.35
	changed.emit()

func _fail_job(c: Dictionary, job: Dictionary, reason: String) -> void:
	if not reason.is_empty():
		_log(reason, "warning")
	_remove_job(job)
	c["job_id"] = -1
	c["state"] = "idle"
	c["action_text"] = "Idle"
	c["decision_timer"] = 1.0

func _complete_build(c: Dictionary, job: Dictionary) -> void:
	var b := get_building(int(job.get("building_id", -1)))
	if b.is_empty() or bool(b.get("built", false)):
		return
	b["built"] = true
	b["hp"] = float(b.get("max_hp", 100.0))
	stats["built"] = int(stats.get("built", 0)) + 1
	var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
	_log("%s finished the %s." % [str(c["first_name"]), str(def.get("name", "building"))], "build")
	_apply_work_hazard(c, "build")
	_gain_skill(c, "labor", 1.2)
	_check_objectives()
	changed.emit()

func _complete_gather(c: Dictionary, job: Dictionary) -> void:
	var target: Vector2i = job.get("target", Vector2i(-1, -1))
	var tile := tile_at(target)
	if tile.is_empty():
		return
	var key := str(tile.get("object", ""))
	if key != str(job.get("object_key", "")):
		return
	var od: Dictionary = HFDefs.OBJECTS.get(key, {})
	if od.is_empty():
		return
	var resource := str(od.get("resource", "wood"))
	var qty_range: Array = od.get("qty", [1, 2])
	var amount := rng.randi_range(int(qty_range[0]), int(qty_range[1]))
	amount = int(round(float(amount) * (1.0 + skill_value(c, "labor") * 0.02)))
	var becomes := str(od.get("becomes", ""))
	if becomes == key:
		becomes = ""
	tile["object"] = becomes
	var regrow_days := float(od.get("regrow", 0.0))
	if regrow_days > 0.0:
		tile["regrow_at"] = time_min + regrow_days * 1440.0
		tile["regrow_key"] = key
	_spawn_pile(resource, amount, target)
	stats["gathered"] = int(stats.get("gathered", 0)) + amount
	_gain_skill(c, "labor" if resource != "berries" and resource != "grain" and resource != "pumpkin" else "farming", 0.7)
	_apply_work_hazard(c, "gather")
	if key in ["pine", "oak", "birch"]:
		_log("%s fells a %s and stacks the logs." % [str(c["first_name"]), str(od.get("name", "tree")).to_lower()], "work")
	elif key in ["iron_vein", "coal_seam", "stone_outcrop", "boulder"]:
		_log("%s breaks loose %d %s." % [str(c["first_name"]), amount, HFDefs.resource_name(resource).to_lower()], "work")
	else:
		_log("%s gathers %d %s." % [str(c["first_name"]), amount, HFDefs.resource_name(resource).to_lower()], "work")

func _complete_farm_sow(c: Dictionary, job: Dictionary) -> void:
	var b := get_building(int(job.get("building_id", -1)))
	if b.is_empty():
		return
	b["planted"] = true
	b["growth"] = 0.0
	c["action_text"] = "Sowing the fields"
	_gain_skill(c, "farming", 0.8)
	_apply_work_hazard(c, "farm")
	if rng.randf() < 0.25:
		_log("%s presses seeds into the dark soil." % str(c["first_name"]), "work")

func _complete_farm_harvest(c: Dictionary, job: Dictionary) -> void:
	var b := get_building(int(job.get("building_id", -1)))
	if b.is_empty():
		return
	var crop := str(b.get("crop", "grain"))
	var resource := "grain" if crop == "grain" else "pumpkin"
	var amount := rng.randi_range(26, 38) + int(round(skill_value(c, "farming") * 0.6))
	amount = int(round(float(amount) * (1.0 + skill_value(c, "farming") * 0.018)))
	var target := Vector2i(floori(building_center(b).x), floori(building_center(b).y))
	_spawn_pile(resource, amount, target)
	b["planted"] = false
	b["growth"] = 0.0
	stats["gathered"] = int(stats.get("gathered", 0)) + amount
	_gain_skill(c, "farming", 1.4)
	_apply_work_hazard(c, "farm")
	_log("%s brings in %d %s from the fields." % [str(c["first_name"]), amount, HFDefs.resource_name(resource).to_lower()], "work")

func _complete_station(c: Dictionary, job: Dictionary) -> void:
	var b := get_building(int(job.get("building_id", -1)))
	if b.is_empty():
		return
	var output := str(job.get("output_resource", ""))
	var amount := int(job.get("output_amount", 1))
	if output.is_empty() or amount <= 0:
		return
	if str(job["type"]) == "cook":
		var accepted := add_resource(output, amount, true)
		if accepted < amount:
			var target := _best_adjacent_tile(b, Vector2(c["pos"]))
			if target.x < 0:
				target = Vector2i(floori(building_center(b).x), floori(building_center(b).y))
			_spawn_pile(output, amount - accepted, target)
		stats["meals"] = int(stats.get("meals", 0)) + amount
		_gain_skill(c, "cooking", 1.1)
		_add_mood(c, "Cooked something good", 2.0, 3.0)
		if rng.randf() < 0.45:
			_log("%s pulls %d warm meals from the cookhouse." % [str(c["first_name"]), amount], "work")
	else:
		var target := _best_adjacent_tile(b, Vector2(c["pos"]))
		if target.x < 0:
			target = Vector2i(floori(building_center(b).x), floori(building_center(b).y))
		_spawn_pile(output, amount, target)
		_gain_skill(c, "crafting", 1.1)
		if rng.randf() < 0.5:
			_log("%s finishes %d new tools at the bench." % [str(c["first_name"]), amount], "work")
	_apply_work_hazard(c, str(job["type"]))

func _complete_study(c: Dictionary, job: Dictionary) -> void:
	_gain_skill(c, "crafting", 1.0)
	_add_mood(c, "A useful idea", 2.0, 3.0)
	research_progress += 14.0 + skill_value(c, "crafting") * 1.6
	stats["research"] = int(stats.get("research", 0)) + 1
	if research_progress >= 100.0:
		if research_index < HFDefs.TECH.size():
			var tech: Dictionary = HFDefs.TECH[research_index]
			research_index += 1
			research_progress = 0.0
			_log("The colony masters %s." % str(tech.get("name", "a new craft")), "story")
			_alert("New knowledge", str(tech.get("name", "A discovery")) + ": " + str(tech.get("desc", "")), "info", 420.0)
		else:
			research_progress = 100.0
	elif rng.randf() < 0.25:
		_log("%s sketches a better tool by lantern light." % str(c["first_name"]), "work")

func _complete_heal(c: Dictionary, job: Dictionary) -> void:
	var patient := colonist_by_id(int(job.get("patient_id", -1)))
	if patient.is_empty():
		return
	var severe := float(patient["illness"]) > 30.0 or float(patient["injury"]) > 30.0
	var medicine := resource_qty("medicine") > 0
	if medicine and (severe or resource_qty("herbs") <= 0):
		remove_resource("medicine", 1)
	else:
		if resource_qty("herbs") <= 0:
			_log("%s has no herbs left for %s." % [str(c["first_name"]), str(patient["first_name"])], "warning")
			return
		remove_resource("herbs", 1)
	var bonus := 1.0
	if research_index > 2:
		bonus = float(HFDefs.TECH[2].get("value", 1.25))
	patient["health"] = clampf(float(patient["health"]) + (12.0 + skill_value(c, "medicine") * 2.0) * bonus, 0.0, 100.0)
	patient["injury"] = maxf(0.0, float(patient["injury"]) - (18.0 + skill_value(c, "medicine") * 2.5) * bonus)
	patient["illness"] = maxf(0.0, float(patient["illness"]) - (20.0 + skill_value(c, "medicine") * 3.0) * bonus)
	patient["waiting_for_care"] = false
	patient["action_text"] = "Recovering"
	_add_mood(patient, "Treated with care", 4.0, 6.0)
	stats["treated"] = int(stats.get("treated", 0)) + 1
	_gain_skill(c, "medicine", 1.5)
	_log("%s treats %s's injuries." % [str(c["first_name"]), str(patient["first_name"])], "story")

func _attack_animal(c: Dictionary, job: Dictionary, animal: Dictionary) -> void:
	var combat := skill_value(c, "combat")
	var damage := rng.randf_range(5.0, 9.0) + combat * 1.4
	if resource_qty("tools") > 0:
		damage += 1.5
	animal["hp"] = float(animal["hp"]) - damage
	animal["hostile"] = true
	animal["defensive"] = true
	animal["target_id"] = int(c["id"])
	_gain_skill(c, "combat", 0.6)
	if float(animal["hp"]) <= 0.0:
		_complete_hunt(c, job, animal)
		return
	if rng.randf() < 0.5:
		var retaliation := float(animal.get("damage", 3.0)) * rng.randf_range(0.55, 1.0)
		c["health"] = maxf(1.0, float(c["health"]) - retaliation)
		c["injury"] = clampf(float(c["injury"]) + retaliation * 0.65, 0.0, 100.0)
		_add_mood(c, "Hurt while hunting", -7.0, 6.0)
		_log("%s is wounded fighting %s." % [str(c["first_name"]), str(animal.get("name", "an animal"))], "danger")

func _complete_hunt(c: Dictionary, job: Dictionary, animal_override: Dictionary = {}) -> void:
	var animal := animal_override if not animal_override.is_empty() else _get_animal(int(job.get("animal_id", -1)))
	if animal.is_empty():
		return
	var meat_range: Array = animal.get("meat", [4, 8])
	var amount := rng.randi_range(int(meat_range[0]), int(meat_range[1]))
	_spawn_pile("meat", amount, tile_of(Vector2(animal["pos"])))
	stats["hunts"] = int(stats.get("hunts", 0)) + 1
	_log("%s brings down %s. The colony will eat well." % [str(c["first_name"]), str(animal.get("name", "game"))], "story")
	_gain_skill(c, "combat", 1.4)
	_apply_work_hazard(c, "hunt")
	animals.erase(animal)
	# Finishing a kill may happen from inside a work tick; clean up the job now.
	if not job.is_empty():
		jobs.erase(job)
		c["job_id"] = -1
		c["state"] = "idle"
		c["action_text"] = "Idle"
		c["path"].clear()
		c["decision_timer"] = 0.5

func _complete_fire(c: Dictionary, job: Dictionary) -> void:
	var b := get_building(int(job.get("building_id", -1)))
	if not b.is_empty():
		b["burning"] = 0.0
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		_log("%s puts out the fire at the %s." % [str(c["first_name"]), str(def.get("name", "building"))], "story")
		_add_mood(c, "Saved a building from fire", 5.0, 4.0)
		_gain_skill(c, "labor", 1.0)

func _apply_work_hazard(c: Dictionary, job_type: String) -> void:
	var base := 0.010
	if job_type in ["gather", "build"]:
		base = 0.013
	elif job_type in ["cook", "craft"]:
		base = 0.007
	elif job_type == "hunt":
		base = 0.018
	base *= trait_mod(c, "accident", 1.0)
	if has_built("forge"):
		base *= 0.82
	if rng.randf() < base:
		var injury := rng.randf_range(5.0, 18.0)
		c["injury"] = clampf(float(c["injury"]) + injury, 0.0, 100.0)
		c["health"] = maxf(2.0, float(c["health"]) - injury * 0.45)
		_add_mood(c, "Hurt on the job", -9.0, 10.0)
		_log("%s is hurt while working." % str(c["first_name"]), "danger")
		if injury > 12.0:
			_alert("Injury in the colony", "%s was hurt and needs care." % str(c["first_name"]), "warning", 240.0)

func _spawn_pile(resource: String, amount: int, tile: Vector2i) -> Dictionary:
	if amount <= 0 or resource.is_empty():
		return {}
	var spot := _nearest_walkable(tile)
	if spot.x < 0:
		return {}
	for pile in piles:
		if pile.get("tile", Vector2i(-1, -1)) == spot and str(pile.get("resource", "")) == resource:
			pile["qty"] = int(pile["qty"]) + amount
			return pile
	var pile := {
		"id": next_pile_id,
		"resource": resource,
		"qty": amount,
		"tile": spot,
	}
	next_pile_id += 1
	piles.append(pile)
	return pile

func _get_pile(id: int) -> Dictionary:
	for pile in piles:
		if int(pile.get("id", -1)) == id:
			return pile
	return {}

func _nearest_storage_tile(c: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 1e20
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		if float(def.get("storage", 0.0)) <= 0.0:
			continue
		var rect := building_footprint(b)
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var tile := Vector2i(x, y)
				if not is_walkable(tile):
					continue
				var dist := Vector2(tile).distance_squared_to(Vector2(c["pos"]))
				if dist < best_dist:
					best_dist = dist
					best = tile
	if best.x < 0:
		return _nearest_walkable(Vector2i(int(COLONY_CENTER.x), int(COLONY_CENTER.y)))
	return best

func _pickup_pile(c: Dictionary, job: Dictionary) -> bool:
	var pile := _get_pile(int(job.get("pile_id", -1)))
	if pile.is_empty():
		_release_job(c, false)
		return false
	var capacity := 8 + int(round(skill_value(c, "labor") * 1.5))
	var amount := mini(int(pile["qty"]), capacity)
	if amount <= 0:
		_release_job(c, false)
		return false
	c["carry"] = {"resource": str(pile["resource"]), "amount": amount}
	pile["qty"] = int(pile["qty"]) - amount
	if int(pile["qty"]) <= 0:
		piles.erase(pile)
	job["phase"] = "to_store"
	var store := _nearest_storage_tile(c)
	var path := _find_path(colonist_tile(c), store)
	if path.is_empty():
		_spawn_pile(str(c["carry"]["resource"]), int(c["carry"]["amount"]), colonist_tile(c))
		c["carry"] = {}
		_release_job(c, false)
		return false
	c["path"] = path
	c["path_goal"] = store
	c["state"] = "moving"
	c["action_text"] = "Hauling %s" % HFDefs.resource_name(str(c["carry"]["resource"]))
	return true

func _deposit_carry(c: Dictionary) -> void:
	if c.get("carry", {}).is_empty():
		return
	var resource := str(c["carry"].get("resource", "wood"))
	var amount := int(c["carry"].get("amount", 0))
	var accepted := add_resource(resource, amount, true)
	if accepted < amount:
		var leftover := amount - accepted
		_spawn_pile(resource, leftover, colonist_tile(c))
		if time_min - float(c.get("last_storage_alert", -1000.0)) > 240.0:
			c["last_storage_alert"] = time_min
			_alert("Storage is full", "Supplies are piling up outside. Build another stockpile or food shed.", "warning", 240.0)
	c["carry"] = {}
	_gain_skill(c, "labor", 0.25)

func _get_animal(id: int) -> Dictionary:
	for animal in animals:
		if int(animal.get("id", -1)) == id:
			return animal
	return {}

func _scan_jobs() -> void:
	_clean_jobs()
	for b in buildings:
		if bool(b.get("station_busy", false)):
			var has_job := false
			for job in jobs:
				if int(job.get("building_id", -1)) == int(b["id"]) and str(job.get("type", "")) in ["cook", "craft", "study"]:
					has_job = true
					break
			if not has_job:
				b["station_busy"] = false
	_ensure_haul_jobs()
	_ensure_farm_jobs()
	_ensure_fire_jobs()
	_ensure_heal_jobs()
	_ensure_station_jobs()
	_ensure_hunt_jobs()
	_ensure_auto_gather_jobs()

func _clean_jobs() -> void:
	for job in jobs.duplicate():
		var valid := true
		match str(job.get("type", "")):
			"build":
				var b := get_building(int(job.get("building_id", -1)))
				valid = not b.is_empty() and not bool(b.get("built", false))
			"gather":
				var tile := tile_at(job.get("target", Vector2i(-1, -1)))
				valid = not tile.is_empty() and str(tile.get("object", "")) == str(job.get("object_key", ""))
			"farm_sow", "farm_harvest":
				var b := get_building(int(job.get("building_id", -1)))
				valid = not b.is_empty() and bool(b.get("built", false))
			"cook", "craft", "study":
				var b := get_building(int(job.get("building_id", -1)))
				valid = not b.is_empty() and bool(b.get("built", false))
			"firefight":
				var b := get_building(int(job.get("building_id", -1)))
				valid = not b.is_empty() and float(b.get("burning", 0.0)) > 0.0
			"heal":
				valid = not colonist_by_id(int(job.get("patient_id", -1))).is_empty()
			"hunt", "defend":
				valid = not _get_animal(int(job.get("animal_id", -1))).is_empty()
			"haul":
				if str(job.get("phase", "to_pile")) != "to_store":
					valid = not _get_pile(int(job.get("pile_id", -1))).is_empty()
		if not valid:
			_remove_job(job)

func _ensure_haul_jobs() -> void:
	for pile in piles:
		var exists := false
		for job in jobs:
			if str(job.get("type", "")) == "haul" and int(job.get("pile_id", -1)) == int(pile["id"]):
				exists = true
				break
		if not exists and storage_free() > 0.0:
			_add_job("haul", {"pile_id": int(pile["id"]), "priority": 3, "work_required": 0.0})

func _ensure_farm_jobs() -> void:
	for b in buildings:
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		if not bool(def.get("farm", false)):
			continue
		var action := ""
		if not bool(b.get("planted", false)):
			action = "farm_sow"
		elif float(b.get("growth", 0.0)) >= 100.0:
			action = "farm_harvest"
		if action.is_empty():
			continue
		var exists := false
		for job in jobs:
			if int(job.get("building_id", -1)) == int(b["id"]) and str(job.get("type", "")) == action:
				exists = true
				break
		if not exists:
			_add_job(action, {"building_id": int(b["id"]), "priority": 1})

func _ensure_fire_jobs() -> void:
	for b in buildings:
		if float(b.get("burning", 0.0)) <= 0.0:
			continue
		var exists := false
		for job in jobs:
			if str(job.get("type", "")) == "firefight" and int(job.get("building_id", -1)) == int(b["id"]):
				exists = true
				break
		if not exists:
			_add_job("firefight", {"building_id": int(b["id"]), "priority": 5})

func _ensure_heal_jobs() -> void:
	if not has_built("clinic") or (resource_qty("herbs") <= 0 and resource_qty("medicine") <= 0):
		return
	for patient in colonists:
		var needs_care := float(patient["health"]) < 72.0 or float(patient["illness"]) > 12.0 or float(patient["injury"]) > 16.0
		if not needs_care or bool(patient.get("waiting_for_care", false)):
			continue
		var exists := false
		for job in jobs:
			if str(job.get("type", "")) == "heal" and int(job.get("patient_id", -1)) == int(patient["id"]):
				exists = true
				break
		if not exists:
			_add_job("heal", {"patient_id": int(patient["id"]), "priority": 2})

func _ensure_station_jobs() -> void:
	for b in buildings:
		if not bool(b.get("built", false)) or bool(b.get("station_busy", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		var station := str(def.get("station", ""))
		match station:
			"cook":
				var recipe := _best_cook_recipe()
				if recipe.is_empty():
					continue
				if resource_qty("meal") + resource_qty("bread") < colonists.size() * 2:
					b["station_busy"] = true
					_add_job("cook", {
						"building_id": int(b["id"]), "priority": 2,
						"recipe": recipe["recipe"], "output_resource": "meal",
						"output_amount": int(recipe["amount"]),
					})
			"craft", "forge":
				if resource_qty("tools") >= 14:
					continue
				var craft_recipe := {}
				var amount := 1
				if has_built("forge") and resource_qty("ore") >= 2:
					craft_recipe = {"wood": 2, "ore": 2}
					amount = 2
				elif resource_qty("wood") >= 6 and resource_qty("stone") >= 3:
					craft_recipe = {"wood": 6, "stone": 3}
					amount = 1
				if craft_recipe.is_empty():
					continue
				b["station_busy"] = true
				_add_job("craft", {
					"building_id": int(b["id"]), "priority": 1,
					"recipe": craft_recipe, "output_resource": "tools", "output_amount": amount,
				})
			"study":
				if research_index >= HFDefs.TECH.size():
					continue
				b["station_busy"] = true
				_add_job("study", {"building_id": int(b["id"]), "priority": 1})

func _best_cook_recipe() -> Dictionary:
	if resource_qty("meat") >= 2:
		return {"recipe": {"meat": 2}, "amount": 2}
	if resource_qty("fish") >= 2:
		return {"recipe": {"fish": 2}, "amount": 2}
	if resource_qty("grain") >= 2 and resource_qty("berries") >= 1:
		return {"recipe": {"grain": 2, "berries": 1}, "amount": 3}
	if resource_qty("pumpkin") >= 2:
		return {"recipe": {"pumpkin": 2}, "amount": 2}
	if resource_qty("berries") >= 4:
		return {"recipe": {"berries": 4}, "amount": 2}
	if resource_qty("grain") >= 3:
		return {"recipe": {"grain": 3}, "amount": 2}
	return {}

func _ensure_hunt_jobs() -> void:
	var detection_range := 11.0 + watchtower_vision() * 0.75
	for animal in animals:
		if not bool(animal.get("hostile", false)):
			continue
		if Vector2(animal["pos"]).distance_to(COLONY_CENTER) > detection_range:
			continue
		var exists := false
		for job in jobs:
			if str(job.get("type", "")) in ["hunt", "defend"] and int(job.get("animal_id", -1)) == int(animal["id"]):
				exists = true
				break
		if not exists:
			_add_job("defend", {"animal_id": int(animal["id"]), "priority": 4})

func _ensure_auto_gather_jobs() -> void:
	if storage_free() < 10.0:
		return
	var counts := {}
	for job in jobs:
		if str(job.get("type", "")) == "gather" and str(job.get("auto_resource", "")) != "":
			var resource := str(job["auto_resource"])
			counts[resource] = int(counts.get(resource, 0)) + 1
	var thresholds := {
		"wood": 44, "stone": 26, "food": 260, "ore": 7, "herbs": 6,
	}
	var wood_limit := 2 if resource_qty("wood") < 24 else 1
	var food_limit := 2 if food_total() < 150.0 else 1
	if resource_qty("wood") < thresholds["wood"] and int(counts.get("wood", 0)) < wood_limit:
		var tile := _find_resource_object(["wood"], 24.0)
		if tile.x >= 0:
			_create_gather_job(tile, 1, true, "wood")
	if resource_qty("stone") < thresholds["stone"] and int(counts.get("stone", 0)) < 1:
		var tile := _find_resource_object(["stone"], 24.0)
		if tile.x >= 0:
			_create_gather_job(tile, 1, true, "stone")
	if food_total() < thresholds["food"] and int(counts.get("food", 0)) < food_limit:
		var tile := _find_resource_object(["berries", "pumpkin", "grain"], 24.0)
		if tile.x >= 0:
			_create_gather_job(tile, 1, true, "food")
	if resource_qty("herbs") < thresholds["herbs"] and int(counts.get("herbs", 0)) < 1:
		var tile := _find_resource_object(["herbs"], 24.0)
		if tile.x >= 0:
			_create_gather_job(tile, 1, true, "herbs")
	if resource_qty("ore") < thresholds["ore"] and has_built("forge") and int(counts.get("ore", 0)) < 1:
		var tile := _find_resource_object(["ore"], 28.0)
		if tile.x >= 0:
			_create_gather_job(tile, 1, true, "ore")

func _find_resource_object(resources_wanted: Array, max_distance: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 1e20
	for y in range(map_h):
		for x in range(map_w):
			var tile := Vector2i(x, y)
			var t: Dictionary = tiles[y][x]
			var key := str(t.get("object", ""))
			if key.is_empty():
				continue
			var od: Dictionary = HFDefs.OBJECTS.get(key, {})
			var resource := str(od.get("resource", ""))
			if resource not in resources_wanted:
				continue
			var dist := Vector2(tile).distance_to(COLONY_CENTER)
			if dist > max_distance or dist >= best_dist:
				continue
			var claimed := false
			for job in jobs:
				if str(job.get("type", "")) == "gather" and job.get("target", Vector2i(-1, -1)) == tile:
					claimed = true
					break
			if claimed:
				continue
			best_dist = dist
			best = tile
	return best

func _create_gather_job(tile: Vector2i, priority: int, auto: bool, auto_resource: String = "") -> int:
	var t := tile_at(tile)
	if t.is_empty():
		return -1
	var key := str(t.get("object", ""))
	var od: Dictionary = HFDefs.OBJECTS.get(key, {})
	if od.is_empty():
		return -1
	for job in jobs:
		if str(job.get("type", "")) == "gather" and job.get("target", Vector2i(-1, -1)) == tile:
			return -1
	return _add_job("gather", {
		"target": tile, "object_key": key, "resource": str(od.get("resource", "")),
		"priority": priority, "work_required": float(od.get("work", 4.0)),
		"auto": auto, "auto_resource": auto_resource,
	})

func mark_gather(tile: Vector2i) -> String:
	var t := tile_at(tile)
	if t.is_empty():
		return "Nothing to gather here."
	var key := str(t.get("object", ""))
	var od: Dictionary = HFDefs.OBJECTS.get(key, {})
	if od.is_empty():
		return "Nothing to gather here."
	var job_id := _create_gather_job(tile, 2, false, str(od.get("resource", "")))
	if job_id < 0:
		return "Someone is already working here."
	var job := get_job(job_id)
	job["player"] = true
	job["auto"] = false
	_log("Gathering marked: %s." % str(od.get("name", key)), "order")
	return "Marked %s for gathering." % str(od.get("name", key))

func mark_hunt(animal_id: int) -> String:
	var animal := _get_animal(animal_id)
	if animal.is_empty():
		return "That animal is gone."
	for job in jobs:
		if str(job.get("type", "")) in ["hunt", "defend"] and int(job.get("animal_id", -1)) == animal_id:
			return "Someone is already after that animal."
	var job_id := _add_job("hunt", {"animal_id": animal_id, "priority": 3})
	var hunt_job := get_job(job_id)
	if not hunt_job.is_empty():
		hunt_job["player"] = true
		hunt_job["auto"] = false
	_log("Hunt marked: %s." % str(animal.get("name", "animal")), "order")
	return "Marked %s for the hunt." % str(animal.get("name", "animal"))

func set_priority(colonist_id: int, job_id: String, value: int) -> void:
	var c := colonist_by_id(colonist_id)
	if c.is_empty():
		return
	c["priorities"][job_id] = clampi(value, 0, 4)
	changed.emit()

func get_priority(colonist_id: int, job_id: String) -> int:
	var c := colonist_by_id(colonist_id)
	if c.is_empty():
		return 0
	return int(c.get("priorities", {}).get(job_id, 0))

# -----------------------------------------------------------------------------
# Living environment
# -----------------------------------------------------------------------------

func _update_environment(game_minutes: float) -> void:
	if time_min >= temp_modifier_until:
		temp_modifier = 0.0
	weather_timer -= game_minutes
	if weather_timer <= 0.0:
		_choose_weather(false)
	pending_crop_check += game_minutes
	if pending_crop_check >= 10.0:
		pending_crop_check = 0.0
		_update_crops()
	pending_spoil_check += game_minutes
	if pending_spoil_check >= 30.0:
		pending_spoil_check = 0.0
		_update_spoilage(0.5)
	pending_fire_check += game_minutes
	if pending_fire_check >= 5.0:
		pending_fire_check = 0.0
		_update_fires()
	pending_regrow_check += game_minutes
	if pending_regrow_check >= 60.0:
		pending_regrow_check = 0.0
		_update_regrowth()
	if hour >= 8 and last_daily_event_day < absolute_day:
		last_daily_event_day = absolute_day
		_roll_daily_event()

func _choose_weather(initial: bool) -> void:
	var pool: Array = HFDefs.WEATHER_BY_SEASON.get(season_index, ["clear"]).duplicate()
	var choices: Array = []
	for entry in pool:
		if str(entry) != weather or initial:
			choices.append(entry)
	if choices.is_empty():
		choices = pool
	weather = str(choices[rng.randi_range(0, choices.size() - 1)])
	weather_timer = rng.randf_range(220.0, 520.0)
	if initial:
		return
	_log("The weather turns to %s." % weather_name().to_lower(), "weather")
	if weather in ["storm", "snow", "heatwave"]:
		_alert(weather_name(), weather_description() + " Settle in and mind the stores.", "warning" if weather != "heatwave" else "info", 300.0)
	if weather == "storm" and rng.randf() < 0.35:
		var candidates: Array = []
		for b in buildings:
			if bool(b.get("built", false)):
				candidates.append(b)
		if not candidates.is_empty():
			_ignite_building(candidates[rng.randi_range(0, candidates.size() - 1)], "lightning")

func _update_crops() -> void:
	var temp_factor := clampf((temperature + 7.0) / 25.0, 0.0, 1.35)
	var weather_factor := float(HFDefs.WEATHER.get(weather, {}).get("crop", 1.0))
	var farm_bonus := 1.0
	if research_index > 1:
		farm_bonus *= float(HFDefs.TECH[1].get("value", 1.2))
	for c in colonists:
		if int(c.get("priorities", {}).get("farm", 0)) >= 2 and has_trait(c, "green_thumb"):
			farm_bonus *= 1.08
			break
	for b in built_buildings_of_type("farm_plot"):
		if not bool(b.get("planted", false)):
			continue
		var growth := float(b.get("growth", 0.0))
		if temperature < 2.0:
			growth -= rng.randf_range(0.15, 0.55)
			if growth <= 0.0 and rng.randf() < 0.3:
				b["planted"] = false
				b["growth"] = 0.0
				_log("Frost kills the seedlings in a farm plot.", "warning")
				continue
		else:
			growth += 0.48 * temp_factor * weather_factor * farm_bonus
		if growth >= 100.0 and not bool(b.get("ready_notified", false)):
			b["ready_notified"] = true
			_log("A farm plot is ready to harvest.", "work")
		if growth < 100.0:
			b["ready_notified"] = false
		b["growth"] = clampf(growth, 0.0, 100.0)

func _update_spoilage(hours: float) -> void:
	var temp_factor := clampf((temperature + 6.0) / 24.0, 0.12, 1.9)
	var modifier := _spoil_modifier()
	for key in resources.keys():
		var def: Dictionary = HFDefs.RESOURCES.get(str(key), {})
		var perish := float(def.get("perish", 0.0))
		if perish <= 0.0 or resource_qty(str(key)) <= 0:
			continue
		var loss := float(resources[key]) * perish * 0.08 * temp_factor * modifier * hours
		spoilage_buffer[key] = float(spoilage_buffer.get(key, 0.0)) + loss
		if float(spoilage_buffer[key]) >= 1.0:
			var lost := int(floor(float(spoilage_buffer[key])))
			spoilage_buffer[key] = float(spoilage_buffer[key]) - float(lost)
			var removed := remove_resource(str(key), lost)
			if removed > 0 and lost >= 3 and rng.randf() < 0.3:
				_log("%d %s spoiled in storage." % [removed, HFDefs.resource_name(str(key)).to_lower()], "warning")
	for pile in piles.duplicate():
		var def: Dictionary = HFDefs.RESOURCES.get(str(pile.get("resource", "")), {})
		var perish := float(def.get("perish", 0.0))
		if perish <= 0.0 or int(pile.get("qty", 0)) <= 0:
			continue
		var key := "pile_%d" % int(pile["id"])
		var loss := float(pile["qty"]) * perish * 0.14 * temp_factor * hours
		spoilage_buffer[key] = float(spoilage_buffer.get(key, 0.0)) + loss
		if float(spoilage_buffer[key]) >= 1.0:
			var lost := int(floor(float(spoilage_buffer[key])))
			spoilage_buffer[key] = float(spoilage_buffer[key]) - float(lost)
			pile["qty"] = int(pile["qty"]) - lost
			if int(pile["qty"]) <= 0:
				piles.erase(pile)
				for job in jobs.duplicate():
					if int(job.get("pile_id", -1)) == int(pile["id"]):
						_remove_job(job)

func _update_fires() -> void:
	var wet := float(HFDefs.WEATHER.get(weather, {}).get("wet", 0.0))
	for b in buildings.duplicate():
		if not bool(b.get("built", false)):
			continue
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		if str(b["key"]) in ["cookhouse", "forge"] and float(b.get("burning", 0.0)) <= 0.0:
			var risk := 0.00032
			if weather == "heatwave":
				risk *= 2.5
			elif wet > 0.0:
				risk *= 0.35
			if rng.randf() < risk:
				_ignite_building(b, "a spark from the hearth")
		if float(b.get("burning", 0.0)) <= 0.0:
			continue
		var burning := float(b["burning"])
		if wet > 0.0:
			burning -= (2.5 + wet * 4.0)
		else:
			burning += rng.randf_range(1.2, 2.7)
		b["burning"] = maxf(0.0, burning)
		if burning <= 0.0:
			_log("The fire at the %s burns itself out." % str(def.get("name", "building")).to_lower(), "story")
			continue
		b["hp"] = float(b.get("hp", 1.0)) - burning * 0.09
		if float(b["hp"]) <= 0.0:
			_burn_building(b)
			continue
		# Fire leaps to nearby timber.
		for other in buildings:
			if other == b or not bool(other.get("built", false)) or float(other.get("burning", 0.0)) > 0.0:
				continue
			if building_center(other).distance_to(building_center(b)) < 5.0 and rng.randf() < 0.018:
				_ignite_building(other, "the spreading fire")

func _ignite_building(b: Dictionary, reason: String) -> void:
	if b.is_empty() or float(b.get("burning", 0.0)) > 0.0:
		return
	b["burning"] = rng.randf_range(12.0, 22.0)
	var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
	_log("Fire! The %s caught from %s." % [str(def.get("name", "building")), reason], "danger")
	_alert("Fire in the colony", "The %s is burning. Colonists with Firefight priority will respond." % str(def.get("name", "building")), "danger", 240.0)
	_ensure_fire_jobs()

func _update_regrowth() -> void:
	for y in range(map_h):
		for x in range(map_w):
			var tile: Dictionary = tiles[y][x]
			if float(tile.get("regrow_at", 0.0)) <= 0.0 or time_min < float(tile["regrow_at"]):
				continue
			if int(tile.get("building_id", -1)) != -1:
				tile["regrow_at"] = 0.0
				continue
			var key := str(tile.get("regrow_key", ""))
			if key.is_empty():
				continue
			tile["object"] = key
			tile["regrow_at"] = 0.0
			tile["regrow_key"] = ""

func _update_ambient_events(game_minutes: float) -> void:
	flavor_timer -= game_minutes
	if flavor_timer <= 0.0:
		flavor_timer = rng.randf_range(180.0, 380.0)
		# Ambient wildlife repopulates slowly, but never crowds the map.
		var passive := 0
		var hostile := 0
		for animal in animals:
			if bool(animal.get("hostile", false)):
				hostile += 1
			else:
				passive += 1
		if passive < 4 and rng.randf() < 0.55:
			var spawn := Vector2i(rng.randi_range(3, map_w - 4), rng.randi_range(3, map_h - 4))
			if Vector2(spawn).distance_to(COLONY_CENTER) > 10.0:
				_spawn_animal(["rabbit", "deer_doe", "turkey", "fox"][rng.randi_range(0, 3)], spawn)
		if is_night() and hostile < 3 and absolute_day > 3 and rng.randf() < 0.24:
			var season_pressure := 1.6 if season_index == 3 else 1.0
			if rng.randf() < 0.16 * season_pressure:
				_spawn_wolf_pack(1)
	# Old alerts are pruned so the HUD can stay readable.
	for alert in alerts.duplicate():
		if float(alert.get("expires", 0.0)) < time_min - 600.0:
			alerts.erase(alert)

func _roll_daily_event() -> void:
	if food_total() < 35.0:
		_alert("The stores are thin", "Food is running low. Check the farms, the cookhouse, and the forage in the forest.", "warning", 360.0)
	if average_mood() < 32.0:
		_alert("Morale is fraying", "Too many needs are going unmet. Warm beds, warm food, and good company will help.", "warning", 360.0)
	var roll := rng.randf()
	if roll < 0.07 and colonists.size() < HFDefs.COLONIST_CAP:
		var edge := Vector2i(rng.randi_range(3, 9), rng.randi_range(3, map_h - 4))
		var spawn := _nearest_walkable(edge)
		if spawn.x >= 0:
			var newcomer := _add_colonist(spawn)
			if not newcomer.is_empty():
				_log("%s arrives from the forest road with a pack on their shoulder." % str(newcomer["name"]), "story")
				_alert("A wanderer arrives", "%s has joined the colony. Give them a bed and a place in the work rota." % str(newcomer["name"]), "info", 360.0)
	elif roll < 0.13:
		temp_modifier = -8.0
		temp_modifier_until = time_min + 12.0 * 60.0
		_log("A cold snap settles over the clearing.", "weather")
		_alert("Cold snap", "Temperatures are dropping. Keep fires burning and watch warmth and illness.", "warning", 420.0)
	elif roll < 0.18:
		var found := rng.randi_range(6, 12)
		add_resource("herbs", found, false)
		_log("A foraging party finds a hidden patch of herbs (+%d)." % found, "story")
	elif roll < 0.22:
		_spawn_wolf_pack(2)
		_log("Wolf tracks circle the clearing. The hunters are restless.", "danger")
		_alert("Wolves near the colony", "A pair of wolves has been seen at the tree line. Hunters will try to drive them off.", "danger", 360.0)
	elif roll < 0.255:
		var candidates := []
		for b in buildings:
			if bool(b.get("built", false)) and str(b.get("key", "")) in ["cookhouse", "forge"]:
				candidates.append(b)
		if not candidates.is_empty():
			_ignite_building(candidates[rng.randi_range(0, candidates.size() - 1)], "a gust through the chimney")
	elif roll < 0.305:
		for c in colonists:
			_add_mood(c, "A song by the fire", 8.0, 8.0)
		_log("Someone starts a low song by the fire. The evening softens.", "story")
	elif roll < 0.34:
		_roll_argument()
	elif roll < 0.38:
		for b in built_buildings_of_type("farm_plot"):
			if bool(b.get("planted", false)):
				b["growth"] = clampf(float(b.get("growth", 0.0)) + 18.0, 0.0, 100.0)
		_log("Warm days and gentle rain push the crops along.", "weather")
	elif rng.randf() < 0.16:
		_log("A quiet day settles over the clearing. The work goes on.", "story")

func _roll_argument() -> void:
	if colonists.size() < 2:
		return
	var first: Dictionary = colonists[rng.randi_range(0, colonists.size() - 1)]
	var second: Dictionary = colonists[rng.randi_range(0, colonists.size() - 1)]
	if first == second:
		return
	var value := float(first.get("relationships", {}).get(str(second["id"]), 0.0))
	var change := -rng.randi_range(8, 18)
	first["relationships"][str(second["id"])] = clampi(int(value + change), -100, 100)
	second["relationships"][str(first["id"])] = first["relationships"][str(second["id"])]
	_add_mood(first, "A sharp argument", -5.0, 8.0)
	_add_mood(second, "A sharp argument", -5.0, 8.0)
	_log("%s and %s argue over old grievances." % [str(first["first_name"]), str(second["first_name"])], "story")

func _autosave_check() -> void:
	if not auto_save_enabled or game_over:
		return
	if hour >= 6 and last_autosave_day < absolute_day and game_elapsed_seconds > 20.0:
		last_autosave_day = absolute_day
		if save_game(AUTOSAVE_PATH):
			autosaved.emit()

# -----------------------------------------------------------------------------
# Wildlife
# -----------------------------------------------------------------------------

func _spawn_animal(key: String, tile: Vector2i) -> Dictionary:
	if animals.size() >= 10:
		return {}
	var def: Dictionary = HFDefs.ANIMALS.get(key, {})
	if def.is_empty():
		return {}
	var spawn := _nearest_walkable(tile)
	if spawn.x < 0:
		return {}
	var animal := {
		"id": next_animal_id,
		"key": key,
		"name": str(def.get("name", key.capitalize())),
		"sprite": str(def.get("sprite", key)),
		"pos": Vector2(spawn) + Vector2(0.5, 0.5),
		"hp": float(def.get("hp", 10)),
		"max_hp": float(def.get("hp", 10)),
		"damage": float(def.get("damage", 0)),
		"speed": float(def.get("speed", 1.5)),
		"hostile": bool(def.get("hostile", false)),
		"defensive": bool(def.get("defensive", false)),
		"meat": def.get("meat", [3, 6]),
		"fear": float(def.get("fear", 0.5)),
		"target_id": -1,
		"path": [],
		"path_timer": 0.0,
		"wander_timer": rng.randf_range(2.0, 7.0),
		"attack_cooldown": 0.0,
		"hunted": false,
	}
	next_animal_id += 1
	animals.append(animal)
	return animal

func _spawn_wolf_pack(count: int) -> void:
	var spotted := false
	for i in range(count):
		var edge := Vector2i(rng.randi_range(3, 9), rng.randi_range(3, map_h - 4))
		var spawn := _nearest_walkable(edge)
		if spawn.x >= 0:
			_spawn_animal("wolf_grey" if rng.randf() < 0.7 else "wolf_black", spawn)
			spotted = true
	if spotted and has_built("watchtower"):
		_alert("Watchtower sighting", "A predator has been seen near the tree line. The watch has rung the warning bell.", "warning", 300.0)

func _update_animals(sim_dt: float, game_minutes: float) -> void:
	for animal in animals.duplicate():
		if not animals.has(animal):
			continue
		animal["attack_cooldown"] = maxf(0.0, float(animal["attack_cooldown"]) - sim_dt)
		animal["wander_timer"] = float(animal["wander_timer"]) - sim_dt
		animal["path_timer"] = float(animal["path_timer"]) - sim_dt
		var target := _nearest_colonist_to(Vector2(animal["pos"]), 13.0)
		var is_predator := bool(animal.get("hostile", false)) or bool(animal.get("defensive", false))
		if is_predator and not target.is_empty():
			var distance := Vector2(animal["pos"]).distance_to(Vector2(target["pos"]))
			if distance < 1.4 and float(animal["attack_cooldown"]) <= 0.0:
				_animal_attack(animal, target)
			elif float(animal["path_timer"]) <= 0.0:
				animal["path_timer"] = 0.9
				var goal := _best_adjacent_to_tile(colonist_tile(target), Vector2(animal["pos"]))
				if goal.x >= 0:
					var path := _find_path(tile_of(Vector2(animal["pos"])), goal)
					if not path.is_empty():
						animal["path"] = path
		elif bool(animal.get("hunted", false)):
			var hunter := _nearest_colonist_to(Vector2(animal["pos"]), 6.0)
			if not hunter.is_empty():
				var away := Vector2(animal["pos"]) + (Vector2(animal["pos"]) - Vector2(hunter["pos"])).normalized() * 4.0
				var flee_tile := _nearest_walkable(Vector2i(floori(away.x), floori(away.y)))
				var path := _find_path(tile_of(Vector2(animal["pos"])), flee_tile)
				if not path.is_empty():
					animal["path"] = path
		elif float(animal["wander_timer"]) <= 0.0:
			animal["wander_timer"] = rng.randf_range(4.0, 10.0)
			var wander_target := _random_walkable_near(Vector2(animal["pos"]), 5.0)
			if wander_target.x >= 0:
				var path := _find_path(tile_of(Vector2(animal["pos"])), wander_target)
				if not path.is_empty():
					animal["path"] = path
		_advance_animal(animal, sim_dt)
		if bool(animal.get("hostile", false)) and Vector2(animal["pos"]).distance_to(COLONY_CENTER) > 20.0 and rng.randf() < 0.002:
			animals.erase(animal)

func _advance_animal(animal: Dictionary, sim_dt: float) -> void:
	var path: Array = animal.get("path", [])
	if path.is_empty():
		return
	var budget := float(animal.get("speed", 1.5)) * sim_dt
	while budget > 0.0 and not path.is_empty():
		var next_tile: Vector2i = path[0]
		if not is_walkable(next_tile):
			path.clear()
			break
		var target := Vector2(next_tile) + Vector2(0.5, 0.5)
		var current := Vector2(animal["pos"])
		var dist := current.distance_to(target)
		if dist <= budget:
			animal["pos"] = target
			path.pop_front()
			budget -= dist
		else:
			animal["pos"] = current + (target - current).normalized() * budget
			budget = 0.0
	animal["path"] = path

func _nearest_colonist_to(pos: Vector2, max_distance: float) -> Dictionary:
	var best := {}
	var best_dist := max_distance
	for c in colonists:
		if bool(c.get("dead", false)):
			continue
		var dist := Vector2(c["pos"]).distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = c
	return best

func _animal_attack(animal: Dictionary, c: Dictionary) -> void:
	animal["attack_cooldown"] = 2.2
	var damage := float(animal.get("damage", 3.0)) * rng.randf_range(0.7, 1.15)
	damage *= 1.0 - clampf(colony_defense() * 0.014, 0.0, 0.45)
	c["health"] = maxf(0.0, float(c["health"]) - damage)
	c["injury"] = clampf(float(c["injury"]) + damage * 0.7, 0.0, 100.0)
	_add_mood(c, "Attacked by an animal", -15.0, 12.0)
	_log("%s is attacked by %s!" % [str(c["first_name"]), str(animal.get("name", "an animal"))], "danger")
	if rng.randf() < 0.22:
		_alert("Predator attack", "%s was attacked by %s near the tree line." % [str(c["first_name"]), str(animal.get("name", "an animal"))], "danger", 240.0)
	_release_job(c, true)
	if float(c["health"]) <= 0.0:
		_kill_colonist(c, str(animal.get("name", "an animal")).to_lower() + " wounds")

# -----------------------------------------------------------------------------
# Alerts, log, objectives
# -----------------------------------------------------------------------------

func _log(text: String, type: String = "info") -> void:
	var entry := {
		"day": absolute_day,
		"date": date_string(),
		"clock": time_string(),
		"text": text,
		"type": type,
		"time": time_min,
	}
	event_log.append(entry)
	while event_log.size() > 160:
		event_log.pop_front()
	event_logged.emit(entry)

func _alert(title: String, text: String, severity: String = "warning", duration: float = 300.0) -> void:
	var alert := {
		"id": next_alert_id,
		"title": title,
		"text": text,
		"severity": severity,
		"created": time_min,
		"expires": time_min + duration,
	}
	next_alert_id += 1
	alerts.append(alert)
	while alerts.size() > 30:
		alerts.pop_front()
	alert_raised.emit(alert)

func active_alerts() -> Array:
	var active: Array = []
	for alert in alerts:
		if float(alert.get("expires", 0.0)) > time_min:
			active.append(alert)
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("created", 0.0)) > float(b.get("created", 0.0))
	)
	if active.size() > 4:
		active = active.slice(0, 4)
	return active

func dismiss_alert(alert_id: int) -> void:
	for alert in alerts.duplicate():
		if int(alert.get("id", -1)) == alert_id:
			alerts.erase(alert)
			return

func _ensure_objectives() -> void:
	if not objectives.is_empty():
		return
	objectives = [
		{"id": "cabin", "label": "Raise a cabin", "desc": "Give your people a proper roof and beds.", "building": "cabin", "done": false},
		{"id": "farm", "label": "Break ground", "desc": "Build a farm plot and let the work rota tend it.", "building": "farm_plot", "done": false},
		{"id": "cookhouse", "label": "Build a cookhouse", "desc": "Turn raw food into warm meals before the stores run thin.", "building": "cookhouse", "done": false},
	]

func _check_objectives() -> void:
	var changed_objectives := false
	var all_done := true
	for objective in objectives:
		if bool(objective.get("done", false)):
			continue
		var key := str(objective.get("building", ""))
		if has_built(key):
			objective["done"] = true
			changed_objectives = true
			_log("First steps: %s." % str(objective.get("label", "objective")), "story")
		else:
			all_done = false
	if changed_objectives:
		objectives_changed.emit(objectives.duplicate(true))
	if all_done and not bool(stats.get("objectives_complete", false)):
		stats["objectives_complete"] = true
		_alert("The colony has found its footing", "Roofs, fields, and a working cookhouse. From here, grow the settlement and keep it alive.", "info", 480.0)
		_log("The settlement is no longer a camp. It is a colony.", "story")

# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------

func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(AUTOSAVE_PATH)

func autosave_exists() -> bool:
	return FileAccess.file_exists(AUTOSAVE_PATH)

func latest_save_path() -> String:
	var manual_exists := FileAccess.file_exists(SAVE_PATH)
	var auto_exists := FileAccess.file_exists(AUTOSAVE_PATH)
	if manual_exists and auto_exists:
		return SAVE_PATH if FileAccess.get_modified_time(SAVE_PATH) >= FileAccess.get_modified_time(AUTOSAVE_PATH) else AUTOSAVE_PATH
	if auto_exists:
		return AUTOSAVE_PATH
	return SAVE_PATH

func save_game(path: String = SAVE_PATH) -> bool:
	var data := _save_data()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func serialize_state() -> String:
	return JSON.stringify(_save_data())

func deserialize_state(text: String) -> bool:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return _load_data(parsed)

func cloud_meta() -> Dictionary:
	var total_mood := 0.0
	for c in colonists:
		total_mood += float(c.get("mood", 50.0))
	var mean_mood := total_mood / float(maxi(1, colonists.size()))
	return {
		"day": int(absolute_day),
		"population": int(colonists.size()),
		"mood": int(round(mean_mood)),
		"date": date_string(),
	}

func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return _load_data(parsed)

func _tile_to_array(tile: Vector2i) -> Array:
	return [tile.x, tile.y]

func _array_to_tile(value) -> Vector2i:
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))
	return Vector2i(-1, -1)

func _serialize_path(path: Array) -> Array:
	var result: Array = []
	for tile in path:
		result.append(_tile_to_array(tile))
	return result

func _deserialize_path(data) -> Array:
	var result: Array = []
	if typeof(data) != TYPE_ARRAY:
		return result
	for entry in data:
		result.append(_array_to_tile(entry))
	return result

func _save_data() -> Dictionary:
	var tile_data: Array = []
	for row in tiles:
		var saved_row: Array = []
		for tile in row:
			saved_row.append({
				"terrain": str(tile.get("terrain", "grass")),
				"object": str(tile.get("object", "")),
				"building_id": int(tile.get("building_id", -1)),
				"variant": int(tile.get("variant", 0)),
				"regrow_at": float(tile.get("regrow_at", 0.0)),
				"regrow_key": str(tile.get("regrow_key", "")),
			})
		tile_data.append(saved_row)
	var building_data: Array = []
	for b in buildings:
		var copy: Dictionary = b.duplicate(true)
		copy["origin"] = _tile_to_array(b["origin"])
		copy["size"] = _tile_to_array(b["size"])
		building_data.append(copy)
	var colonist_data: Array = []
	for c in colonists:
		var copy: Dictionary = c.duplicate(true)
		copy["pos"] = [float(c["pos"].x), float(c["pos"].y)]
		copy["path"] = _serialize_path(c.get("path", []))
		copy["path_goal"] = _tile_to_array(c.get("path_goal", Vector2i(-1, -1)))
		colonist_data.append(copy)
	var job_data: Array = []
	for job in jobs:
		var copy: Dictionary = job.duplicate(true)
		copy["target"] = _tile_to_array(job.get("target", Vector2i(-1, -1)))
		job_data.append(copy)
	var animal_data: Array = []
	for animal in animals:
		var copy: Dictionary = animal.duplicate(true)
		copy["pos"] = [float(animal["pos"].x), float(animal["pos"].y)]
		copy["path"] = _serialize_path(animal.get("path", []))
		animal_data.append(copy)
	var pile_data: Array = []
	for pile in piles:
		var copy: Dictionary = pile.duplicate(true)
		copy["tile"] = _tile_to_array(pile["tile"])
		pile_data.append(copy)
	return {
		"version": 1,
		"world_seed": world_seed,
		"map_w": map_w,
		"map_h": map_h,
		"time_min": time_min,
		"weather": weather,
		"weather_timer": weather_timer,
		"temp_modifier": temp_modifier,
		"temp_modifier_until": temp_modifier_until,
		"research_index": research_index,
		"research_progress": research_progress,
		"resources": resources.duplicate(true),
		"tiles": tile_data,
		"buildings": building_data,
		"colonists": colonist_data,
		"jobs": job_data,
		"animals": animal_data,
		"piles": pile_data,
		"event_log": event_log.duplicate(true),
		"alerts": alerts.duplicate(true),
		"objectives": objectives.duplicate(true),
		"stats": stats.duplicate(true),
		"next_building_id": next_building_id,
		"next_colonist_id": next_colonist_id,
		"next_job_id": next_job_id,
		"next_pile_id": next_pile_id,
		"next_animal_id": next_animal_id,
		"next_alert_id": next_alert_id,
		"last_daily_event_day": last_daily_event_day,
		"last_autosave_day": last_autosave_day,
		"game_elapsed_seconds": game_elapsed_seconds,
	}

func _load_data(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	world_seed = int(data.get("world_seed", 1))
	map_w = int(data.get("map_w", HFDefs.MAP_W))
	map_h = int(data.get("map_h", HFDefs.MAP_H))
	time_min = float(data.get("time_min", 420.0))
	weather = str(data.get("weather", "clear"))
	weather_timer = float(data.get("weather_timer", 240.0))
	temp_modifier = float(data.get("temp_modifier", 0.0))
	temp_modifier_until = float(data.get("temp_modifier_until", 0.0))
	research_index = int(data.get("research_index", 0))
	research_progress = float(data.get("research_progress", 0.0))
	resources.clear()
	var saved_resources = data.get("resources", {})
	if typeof(saved_resources) == TYPE_DICTIONARY:
		for key in HFDefs.RESOURCES.keys():
			resources[str(key)] = int(saved_resources.get(str(key), 0))
	tiles.clear()
	var saved_tiles = data.get("tiles", [])
	if typeof(saved_tiles) == TYPE_ARRAY:
		for row in saved_tiles:
			var new_row: Array = []
			if typeof(row) == TYPE_ARRAY:
				for tile in row:
					new_row.append({
						"terrain": str(tile.get("terrain", "grass")),
						"object": str(tile.get("object", "")),
						"building_id": int(tile.get("building_id", -1)),
						"variant": int(tile.get("variant", 0)),
						"regrow_at": float(tile.get("regrow_at", 0.0)),
						"regrow_key": str(tile.get("regrow_key", "")),
					})
			tiles.append(new_row)
	if tiles.size() != map_h or (map_h > 0 and tiles[0].size() != map_w):
		return false
	buildings.clear()
	var saved_buildings = data.get("buildings", [])
	if typeof(saved_buildings) == TYPE_ARRAY:
		for b in saved_buildings:
			var copy: Dictionary = b.duplicate(true)
			copy["origin"] = _array_to_tile(b.get("origin", [0, 0]))
			copy["size"] = _array_to_tile(b.get("size", [1, 1]))
			copy["occupants"] = b.get("occupants", []).duplicate()
			copy["built"] = bool(b.get("built", true))
			copy["hp"] = float(b.get("hp", b.get("max_hp", 100.0)))
			copy["max_hp"] = float(b.get("max_hp", 100.0))
			copy["burning"] = float(b.get("burning", 0.0))
			copy["station_busy"] = bool(b.get("station_busy", false))
			copy["growth"] = float(b.get("growth", 0.0))
			copy["planted"] = bool(b.get("planted", false))
			copy["crop"] = str(b.get("crop", "grain"))
			buildings.append(copy)
	colonists.clear()
	var saved_colonists = data.get("colonists", [])
	if typeof(saved_colonists) == TYPE_ARRAY:
		for c in saved_colonists:
			var copy: Dictionary = c.duplicate(true)
			var p = c.get("pos", [COLONY_CENTER.x, COLONY_CENTER.y])
			if typeof(p) == TYPE_ARRAY and p.size() >= 2:
				copy["pos"] = Vector2(float(p[0]), float(p[1]))
			else:
				copy["pos"] = Vector2(COLONY_CENTER)
			copy["path"] = _deserialize_path(c.get("path", []))
			copy["path_goal"] = _array_to_tile(c.get("path_goal", [-1, -1]))
			copy["relationships"] = c.get("relationships", {}).duplicate(true)
			copy["mood_reasons"] = c.get("mood_reasons", {}).duplicate(true)
			copy["mood_events"] = c.get("mood_events", []).duplicate(true)
			copy["priorities"] = c.get("priorities", {}).duplicate(true)
			copy["carry"] = c.get("carry", {}).duplicate(true)
			copy["action_data"] = c.get("action_data", {}).duplicate(true)
			copy["traits"] = c.get("traits", []).duplicate()
			copy["skills"] = c.get("skills", {}).duplicate(true)
			copy["skill_xp"] = c.get("skill_xp", {}).duplicate(true)
			copy["needs"] = c.get("needs", {"hunger": 75.0, "fatigue": 75.0, "warmth": 75.0, "hygiene": 75.0}).duplicate(true)
			copy["waiting_for_care"] = bool(c.get("waiting_for_care", false))
			copy["job_id"] = int(c.get("job_id", -1))
			colonists.append(copy)
	jobs.clear()
	var saved_jobs = data.get("jobs", [])
	if typeof(saved_jobs) == TYPE_ARRAY:
		for job in saved_jobs:
			var copy: Dictionary = job.duplicate(true)
			copy["target"] = _array_to_tile(job.get("target", [-1, -1]))
			copy["recipe"] = job.get("recipe", {}).duplicate(true)
			jobs.append(copy)
	animals.clear()
	var saved_animals = data.get("animals", [])
	if typeof(saved_animals) == TYPE_ARRAY:
		for animal in saved_animals:
			var copy: Dictionary = animal.duplicate(true)
			var p = animal.get("pos", [COLONY_CENTER.x, COLONY_CENTER.y])
			if typeof(p) == TYPE_ARRAY and p.size() >= 2:
				copy["pos"] = Vector2(float(p[0]), float(p[1]))
			else:
				copy["pos"] = Vector2(COLONY_CENTER)
			copy["path"] = _deserialize_path(animal.get("path", []))
			copy["hostile"] = bool(animal.get("hostile", false))
			animals.append(copy)
	piles.clear()
	var saved_piles = data.get("piles", [])
	if typeof(saved_piles) == TYPE_ARRAY:
		for pile in saved_piles:
			var copy: Dictionary = pile.duplicate(true)
			copy["tile"] = _array_to_tile(pile.get("tile", [-1, -1]))
			copy["qty"] = int(pile.get("qty", 0))
			piles.append(copy)
	event_log = data.get("event_log", []).duplicate(true)
	alerts = data.get("alerts", []).duplicate(true)
	objectives = data.get("objectives", []).duplicate(true)
	stats = data.get("stats", {}).duplicate(true)
	next_building_id = int(data.get("next_building_id", 1))
	next_colonist_id = int(data.get("next_colonist_id", 1))
	next_job_id = int(data.get("next_job_id", 1))
	next_pile_id = int(data.get("next_pile_id", 1))
	next_animal_id = int(data.get("next_animal_id", 1))
	next_alert_id = int(data.get("next_alert_id", 1))
	last_daily_event_day = int(data.get("last_daily_event_day", 0))
	last_autosave_day = int(data.get("last_autosave_day", 0))
	game_elapsed_seconds = float(data.get("game_elapsed_seconds", 0.0))
	speed = 1
	active = true
	game_over = colonists.is_empty()
	_sync_calendar()
	# Jobs must point at real colonists, and colonists must point at real jobs.
	for c in colonists:
		if int(c.get("job_id", -1)) != -1 and get_job(int(c["job_id"])).is_empty():
			c["job_id"] = -1
			c["state"] = "idle"
			c["action_text"] = "Idle"
	for job in jobs:
		if int(job.get("worker_id", -1)) != -1 and colonist_by_id(int(job["worker_id"])).is_empty():
			job["worker_id"] = -1
	_recompute_all_moods()
	_scan_jobs()
	changed.emit()
	objectives_changed.emit(objectives.duplicate(true))
	return true

# -----------------------------------------------------------------------------
# Queries used by the renderer and interface
# -----------------------------------------------------------------------------

func mood_reason_list(c: Dictionary) -> Array:
	var list: Array = []
	for label in c.get("mood_reasons", {}).keys():
		var value := float(c["mood_reasons"][label])
		if absf(value) >= 0.5:
			list.append({"label": str(label), "value": value})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["value"])) > absf(float(b["value"]))
	)
	return list

func relationship_list(c: Dictionary) -> Array:
	var list: Array = []
	for other_id in c.get("relationships", {}).keys():
		var other := colonist_by_id(int(other_id))
		if other.is_empty():
			continue
		list.append({"name": str(other["name"]), "first_name": str(other["first_name"]), "value": int(c["relationships"][other_id])})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["value"]) > int(b["value"])
	)
	return list

func colonist_status_text(c: Dictionary) -> String:
	var state := str(c.get("state", "idle"))
	if state == "idle":
		return str(c.get("action_text", "Idle"))
	if state == "sleeping":
		return "Sleeping"
	if state == "eating":
		return "Eating"
	if state == "washing":
		return "Washing"
	if state == "warming":
		return "Warming up"
	if state == "resting":
		return "Recovering"
	if state == "socializing":
		return str(c.get("action_text", "Talking"))
	return str(c.get("action_text", state.capitalize()))

func colonist_at_tile(tile: Vector2i) -> Dictionary:
	for c in colonists:
		if colonist_tile(c) == tile:
			return c
	return {}

func animal_at_tile(tile: Vector2i) -> Dictionary:
	for animal in animals:
		if tile_of(Vector2(animal["pos"])) == tile:
			return animal
	return {}

func pile_at_tile(tile: Vector2i) -> Dictionary:
	for pile in piles:
		if pile.get("tile", Vector2i(-1, -1)) == tile:
			return pile
	return {}

func tile_hover_text(tile: Vector2i) -> String:
	if not _tile_in_bounds(tile):
		return ""
	var t: Dictionary = tiles[tile.y][tile.x]
	var b := building_at(tile)
	if not b.is_empty():
		var def: Dictionary = HFDefs.BUILDINGS.get(str(b["key"]), {})
		if not bool(b.get("built", false)):
			return "%s (blueprint) · %d%% complete" % [str(def.get("name", "Building")), int(float(b.get("hp", 0.0)) / maxf(1.0, float(b.get("max_hp", 1.0))) * 100.0)]
		if bool(def.get("farm", false)):
			return "Farm Plot · %s · %d%% grown" % [str(b.get("crop", "grain")).capitalize(), int(float(b.get("growth", 0.0)))]
		return str(def.get("name", "Building"))
	var animal := animal_at_tile(tile)
	if not animal.is_empty():
		return str(animal.get("name", "Animal")) + " · " + str(int(ceil(float(animal.get("hp", 1.0))))) + " hp"
	var c := colonist_at_tile(tile)
	if not c.is_empty():
		return str(c.get("name", "Colonist")) + " · " + colonist_status_text(c)
	var pile := pile_at_tile(tile)
	if not pile.is_empty():
		return "%d %s (loose pile)" % [int(pile.get("qty", 0)), HFDefs.resource_name(str(pile.get("resource", "wood")))]
	var object_key := str(t.get("object", ""))
	if not object_key.is_empty():
		var od: Dictionary = HFDefs.OBJECTS.get(object_key, {})
		return str(od.get("name", object_key.capitalize()))
	if str(t.get("terrain", "")) == "water":
		return "Cold pond water"
	if str(t.get("terrain", "")) == "path":
		return "Worn trail"
	return "Open ground"

func farm_status(b: Dictionary) -> String:
	if not bool(b.get("planted", false)):
		return "Unsown"
	var growth := float(b.get("growth", 0.0))
	if growth >= 100.0:
		return "Ready to harvest"
	if growth < 20.0:
		return "Seedlings"
	if growth < 60.0:
		return "Growing"
	return "Ripening"

func get_research_status() -> String:
	if research_index >= HFDefs.TECH.size():
		return "All known crafts mastered"
	return "%s · %d%%" % [str(HFDefs.TECH[research_index].get("name", "Research")), int(research_progress)]

func set_crop(building_id: int, crop: String) -> void:
	var b := get_building(building_id)
	if b.is_empty() or str(b.get("key", "")) != "farm_plot":
		return
	if bool(b.get("planted", false)):
		return
	b["crop"] = "grain" if crop != "pumpkin" else "pumpkin"
	changed.emit()

func dismiss_all_alerts() -> void:
	alerts.clear()

func game_summary() -> Dictionary:
	return {
		"days": int(stats.get("days", absolute_day)),
		"built": int(stats.get("built", 0)),
		"gathered": int(stats.get("gathered", 0)),
		"meals": int(stats.get("meals", 0)),
		"deaths": int(stats.get("deaths", 0)),
		"population": colonists.size(),
		"mood": average_mood(),
		"date": date_string(),
	}
