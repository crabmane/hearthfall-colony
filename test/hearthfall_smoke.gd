extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene must load")
	if packed == null:
		_finish()
		return
	var main = packed.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main.hud != null, "HUD must initialize")
	_check(main.hud.title_screen != null and main.hud.title_screen.visible, "title screen must be visible on boot")
	main._start_new_colony()
	await get_tree().process_frame
	var sim: ColonySim = main.sim
	_check(sim != null, "simulation must start")
	if sim != null:
		_check(sim.colonists.size() == 6, "new colony must start with six survivors")
		_check(sim.buildings.size() >= 2, "new colony must have starter structures")
		_check(sim.resources.has("wood") and sim.resources.has("meal") and sim.resources.has("berries"), "resource ledger must initialize")
		var placed := sim.place_building("cabin", Vector2i(26, 13))
		_check(placed.is_empty(), "valid cabin placement must succeed")
		var saved := sim.save_game("user://hearthfall_verification.json")
		_check(saved, "local save must succeed")
		var loaded := ColonySim.new()
		_check(loaded.load_game("user://hearthfall_verification.json"), "local save must reload")
		_check(loaded.colonists.size() == sim.colonists.size(), "save/load must preserve population")
		loaded.queue_free()
	main._return_to_title()
	await get_tree().process_frame
	_check(main.hud.title_screen.visible, "return to title must restore title screen")
	if main != null and is_instance_valid(main):
		main.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("[hearthfall-smoke] PASS: boot, colony start, simulation state, build, save/load, title navigation")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[hearthfall-smoke] " + failure)
	get_tree().quit(1)
