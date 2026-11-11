class_name WeatherOverlay
extends Control

var sim: ColonySim
var time: float = 0.0
var drops: Array = []
var flakes: Array = []
var flash: float = 0.0
var flash_cooldown: float = 5.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rng.randomize()
	for i in range(90):
		drops.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"speed": rng.randf_range(0.55, 1.1),
			"length": rng.randf_range(7.0, 16.0),
		})
	for i in range(70):
		flakes.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"speed": rng.randf_range(0.08, 0.22),
			"size": rng.randf_range(1.0, 2.6),
			"drift": rng.randf_range(0.0, TAU),
		})

func setup(colony_sim: ColonySim) -> void:
	sim = colony_sim

func _process(delta: float) -> void:
	time += delta
	flash_cooldown -= delta
	if sim != null and sim.weather == "storm" and flash_cooldown <= 0.0:
		flash_cooldown = rng.randf_range(7.0, 16.0)
		flash = 1.0
	flash = maxf(0.0, flash - delta * 4.5)
	queue_redraw()

func _draw() -> void:
	if sim == null:
		return
	var weather := sim.weather
	var viewport := size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	if weather in ["rain", "storm"]:
		var count := drops.size() if weather == "rain" else int(drops.size() * 1.35)
		for i in range(mini(count, drops.size())):
			var drop: Dictionary = drops[i]
			drop["y"] = fmod(float(drop["y"]) + float(drop["speed"]) * 0.42 * get_process_delta_time(), 1.08)
			var p := Vector2(float(drop["x"]) * viewport.x, (float(drop["y"]) - 0.08) * viewport.y)
			var length := float(drop["length"])
			var alpha := 0.23 if weather == "rain" else 0.32
			draw_line(p, p + Vector2(-2.0, length), Color(0.62, 0.75, 0.82, alpha), 1.0)
	if weather == "snow":
		for flake in flakes:
			flake["y"] = fmod(float(flake["y"]) + float(flake["speed"]) * get_process_delta_time(), 1.06)
			var x := float(flake["x"]) + sin(time * 0.55 + float(flake["drift"])) * 0.004
			var p := Vector2(fmod(x + 1.0, 1.0) * viewport.x, float(flake["y"]) * viewport.y)
			draw_circle(p, float(flake["size"]), Color(0.9, 0.94, 0.9, 0.58))
	if weather == "fog":
		for i in range(3):
			var y := viewport.y * (0.22 + i * 0.22) + sin(time * 0.08 + i) * 18.0
			draw_rect(Rect2(0, y, viewport.x, viewport.y * 0.18), Color(0.72, 0.78, 0.72, 0.035))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, viewport), Color(0.85, 0.9, 1.0, flash * 0.22))
