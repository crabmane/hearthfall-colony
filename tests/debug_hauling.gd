extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sim := ColonySim.new()
	sim.new_colony(0)
	sim.set_process(false)
	sim.set_speed(4)
	for c in sim.colonists:
		sim.set_priority(int(c["id"]), "build", 3)
		sim.set_priority(int(c["id"]), "gather", 3)
		sim.set_priority(int(c["id"]), "farm", 3)
		sim.set_priority(int(c["id"]), "cook", 3)
		sim.set_priority(int(c["id"]), "haul", 3)
	sim.place_building("cabin", Vector2i(26, 13))
	sim.place_building("farm_plot", Vector2i(26, 18))
	sim.place_building("cookhouse", Vector2i(19, 14))
	for i in range(200):
		sim._process(0.2)
		if i in [20, 50, 80, 100, 120, 150, 180]:
			print("\nTICK ", i, " ", sim.time_string(), " storage=", int(sim.storage_used()), "/", int(sim.storage_capacity()))
			var res := {}
			for k in ["wood", "stone", "grain", "berries", "meal", "fish", "meat", "herbs"]:
				res[k] = sim.resource_qty(k)
			print("RES ", res, " food_total=", int(sim.food_total()), " piles=", sim.piles.size())
			for p in sim.piles:
				print("  PILE ", p["resource"], p["qty"], p["tile"])
			for j in sim.jobs:
				print("  JOB ", j["type"], " phase=", j.get("phase", ""), " worker=", j.get("worker_id", -1), " target=", j.get("target", j.get("pile_id", j.get("building_id", -1))), " prog=", snapped(float(j.get("progress", 0)), 0.1))
				if i == 80:
					var idle_c: Dictionary = sim.colonists[0]
					var wt: Vector2i = sim._job_work_tile(j, idle_c)
					var path: Array = sim._find_path(sim.colonist_tile(idle_c), wt) if wt.x >= 0 else []
					print("    WORKTILE ", wt, " path=", path.size(), " blocked=", j.get("blocked_until", 0.0), " priority=", j.get("priority", 0))
			for c in sim.colonists:
				print("  C ", c["first_name"], " state=", c["state"], " action=", c["action_text"], " hunger=", int(c["needs"]["hunger"]), " job=", c["job_id"], " carry=", c.get("carry", {}), " pos=", Vector2(c["pos"]).snapped(Vector2(0.5,0.5)), " dt=", c.get("decision_timer", -1.0), " priorities=", c.get("priorities", {}), " care=", c.get("waiting_for_care", false))
			if i == 80:
				var probe: Dictionary = sim.colonists[0]
				var picked: bool = sim._pick_job(probe)
				print("PROBE picked=", picked, " job=", probe["job_id"], " state=", probe["state"], " action=", probe["action_text"], " path=", probe["path"].size())
	quit()
