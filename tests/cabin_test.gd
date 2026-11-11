extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sim := ColonySim.new()
	sim.new_colony(0)
	sim.set_process(false)
	sim.set_speed(4)
	var err := sim.place_building("cabin", Vector2i(26, 12))
	print("place=", err)
	for b in sim.buildings:
		print("building ", b["id"], " ", b["key"], " origin=", b["origin"], " built=", b["built"])
	print("can_place_after=", sim.can_place_building("cabin", Vector2i(26, 12)))
	for i in range(300):
		sim._process(0.2)
	print("after2days")
	for b in sim.buildings:
		print("building ", b["id"], " ", b["key"], " origin=", b["origin"], " built=", b["built"], " hp=", b["hp"])
	print("can_place_after2=", sim.can_place_building("cabin", Vector2i(26, 12)))
	for o in sim.objectives:
		print("OBJ ", o["id"], " done=", o["done"], " label=", o["label"])
	quit()
