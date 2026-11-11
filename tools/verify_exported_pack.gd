extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "Hearthfall Colony", "exported identity")
	for path: String in [
		"assets/game/art/title_hearthfall.png",
		"assets/game/art/nature_sheet.png",
		"assets/game/art/resources_sheet.png",
		"assets/game/art/colonists_sheet.png",
		"assets/game/art/buildings_sheet.png",
		"assets/game/sprites/cabin.png",
		"assets/game/sprites/colonist_00.png",
		"assets/game/sprites/farm_plot.png",
		"assets/game/art/wildlife_sheet.png",
	]:
		_check(ResourceLoader.exists("res://" + path), "pack resource: " + path)
	_check(not ResourceLoader.exists("res://test/hearthfall_smoke.tscn"), "source smoke test excluded")
	_check(not ResourceLoader.exists("res://tools/verify_exported_pack.gd"), "pack verifier excluded")
	_check(not DirAccess.dir_exists_absolute("res://captures"), "development captures excluded")
	for locale: String in ["en", "zh-CN"]:
		_check(FileAccess.file_exists("res://localization/%s.json" % locale), "exported locale: " + locale)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "exported main scene")
	if packed != null:
		var main = packed.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		_check(main.hud != null and main.hud.title_screen.visible, "pack boots to title")
		main._start_new_colony()
		await process_frame
		_check(main.sim != null and main.sim.colonists.size() == 6, "pack starts six survivors")
		_check(not main.has_method("_maybe_capture"), "capture routing removed from runtime")
		_check(not main.has_method("_open_tuning"), "release tuning entry point excluded")
		main.queue_free()
		await process_frame
	if _failures.is_empty():
		print("[exported-pack] PASS: Hearthfall identity, art, locales, exclusions, boot, gameplay")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[exported-pack] " + failure)
		quit(1)

func _check(condition: bool, context: String) -> void:
	if not condition and context not in _failures:
		_failures.append(context)
