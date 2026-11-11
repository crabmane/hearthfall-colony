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
	assert(sim != null, "Simulation did not start")
	assert(sim.colonists.size() == 6, "Expected six starting colonists")
	assert(sim.buildings.size() == 2, "Expected stockpile and campfire")
	print("START ", sim.date_string(), " ", sim.time_string(), " pop=", sim.colonists.size())
	# Take manual control of simulation time so this test does not depend on real-time frames.
	sim.set_process(false)
	sim.set_speed(4)
	for c in sim.colonists:
		sim.set_priority(int(c["id"]), "build", 3)
		sim.set_priority(int(c["id"]), "gather", 3)
		sim.set_priority(int(c["id"]), "farm", 3)
		sim.set_priority(int(c["id"]), "cook", 3)
		sim.set_priority(int(c["id"]), "haul", 3)
	# Place one of each early structure in the cleared opening.
	print("PLACE cabin: ", sim.place_building("cabin", Vector2i(26, 13)))
	print("PLACE farm: ", sim.place_building("farm_plot", Vector2i(26, 18)))
	print("PLACE cookhouse: ", sim.place_building("cookhouse", Vector2i(19, 14)))
	# Mark a nearby resource for a deliberate gathering order.
	var marked := false
	for y in range(sim.map_h):
		for x in range(sim.map_w):
			var tile: Dictionary = sim.tiles[y][x]
			if str(tile.get("object", "")) in ["pine", "oak", "birch", "berry_bush", "boulder"]:
				var msg := sim.mark_gather(Vector2i(x, y))
				if msg.begins_with("Marked"):
					print("MARK ", msg)
					marked = true
					break
		if marked:
			break
	for i in range(900):
		sim._process(0.2)
		if i % 150 == 0:
			print("TICK ", i, " ", sim.date_string(), " ", sim.time_string(), " pop=", sim.colonists.size(), " food=", int(sim.food_total()), " wood=", sim.resource_qty("wood"), " jobs=", sim.jobs.size(), " alerts=", sim.active_alerts().size())
	print("END ", sim.date_string(), " ", sim.time_string(), " pop=", sim.colonists.size(), " mood=", int(sim.average_mood()), " food=", int(sim.food_total()))
	print("BUILDINGS ", sim.buildings.size(), " JOBS ", sim.jobs.size(), " ANIMALS ", sim.animals.size(), " PILES ", sim.piles.size())
	print("STATS ", sim.game_summary())
	var save_ok := sim.save_game("user://smoke_test.json")
	print("SAVE ", save_ok, " exists=", FileAccess.file_exists("user://smoke_test.json"))
	var loaded := ColonySim.new()
	var load_ok := loaded.load_game("user://smoke_test.json")
	print("LOAD ", load_ok, " pop=", loaded.colonists.size(), " day=", loaded.absolute_day, " time=", loaded.time_string())
	assert(save_ok and load_ok, "Save/load smoke test failed")
	assert(loaded.colonists.size() == sim.colonists.size(), "Loaded population mismatch")
	# Check that the interface built its major panels without crashing.
	assert(main.hud != null, "HUD missing")
	assert(main.hud.build_cards.size() > 0, "Build menu has no cards")
	main.hud.show_people_list()
	main.hud.show_building(int(sim.buildings[0]["id"]))
	main.hud._open_work()
	main.hud._open_help(false)
	main.hud._open_pause()
	main.hud._resume_game()
	print("UI_SMOKE_OK")
	quit()
