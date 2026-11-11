extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._start_new_colony()
	await process_frame
	var sim: ColonySim = main.sim
	sim.set_process(false)
	print("BEFORE sim=", sim.resource_qty("wood"), " hud=", main.hud.resource_values["wood"].text)
	var err := sim.place_building("cabin", Vector2i(26, 13))
	print("PLACE err=", err, " sim=", sim.resource_qty("wood"), " hud_before_refresh=", main.hud.resource_values["wood"].text)
	main.hud._refresh_game()
	print("AFTER_REFRESH sim=", sim.resource_qty("wood"), " hud=", main.hud.resource_values["wood"].text)
	await process_frame
	print("AFTER_FRAME sim=", sim.resource_qty("wood"), " hud=", main.hud.resource_values["wood"].text)
	quit()
