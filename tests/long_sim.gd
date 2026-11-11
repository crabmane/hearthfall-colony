extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sim := ColonySim.new()
	sim.new_colony(1)
	sim.set_process(false)
	sim.set_speed(4)
	sim.place_building("cabin", Vector2i(26, 12))
	sim.place_building("farm_plot", Vector2i(19, 12))
	sim.place_building("farm_plot", Vector2i(19, 14))
	sim.place_building("cookhouse", Vector2i(18, 17))
	sim.place_building("workshop", Vector2i(20, 20))
	sim.place_building("food_shed", Vector2i(26, 16))
	print("HERB: ", sim.queue_herb_order())
	for i in range(3600):
		sim._process(0.2)
		if i % 500 == 0:
			print("DAY ", sim.day, " season=", sim.season_index, " weather=", sim.weather, " temp=", snapped(sim.temperature, 0.1), " pop=", sim.colonists.size(), " food=", int(sim.food_total()), " wood=", sim.resource_qty("wood"), " stone=", sim.resource_qty("stone"), " jobs=", sim.jobs.size(), " animals=", sim.animals.size(), " alerts=", sim.active_alerts().size())
	print("FINAL ", sim.date_string(), " pop=", sim.colonists.size(), " mood=", snapped(sim.average_mood(), 0.1), " food=", int(sim.food_total()), " built=", sim.stats.get("built", 0), " gathered=", sim.stats.get("gathered", 0), " meals=", sim.stats.get("meals", 0), " deaths=", sim.stats.get("deaths", 0))
	print("LOG TAIL")
	for entry in sim.event_log.slice(maxi(0, sim.event_log.size() - 12), sim.event_log.size()):
		print("  ", entry.get("time", 0.0), " ", entry.get("type", ""), " ", entry.get("text", ""))
	quit()
