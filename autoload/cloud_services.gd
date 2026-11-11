extends Node
## Authenticated cloud saves and account leaderboards. Local play never depends on it.

signal session_changed(session: Dictionary)
signal request_finished(request_id: int, result: Dictionary)
signal publish_finished(result: Dictionary)

var session: Dictionary = {"status": "unavailable", "user": null}
var last_error: String = ""
var _pending: Dictionary = {}
var _publish_state: Dictionary = {}
var _owner_event_times: Dictionary = {}

const BOARDS := [
	{"id": "survival-days-v1", "rules": "v1", "label": "Days Survived"},
	{"id": "population-v1", "rules": "v1", "label": "Population"},
	{"id": "mood-v1", "rules": "v1", "label": "Colony Mood"},
]

func _ready() -> void:
	ManusAuth.auth_state_changed.connect(_on_auth_changed)
	ManusAuth.auth_error.connect(_on_auth_error)
	ManusAuth.rpc_completed.connect(_on_rpc_completed)
	refresh_session()

func refresh_session() -> void:
	session = ManusAuth.get_session()
	session_changed.emit(session)

func is_online() -> bool:
	var status := str(session.get("status", ""))
	return status == "authenticated" or status == "logged_out"

func is_signed_in() -> bool:
	return str(session.get("status", "")) == "authenticated" and session.get("user") != null

func user_name() -> String:
	var user = session.get("user")
	if typeof(user) == TYPE_DICTIONARY:
		return str(user.get("name", "Survivor"))
	return "Survivor"

func sign_in() -> void:
	ManusAuth.login()

func sign_out() -> void:
	ManusAuth.logout()

func open_standalone() -> void:
	ManusAuth.open_standalone()

func _on_auth_changed(state: Dictionary) -> void:
	session = state
	session_changed.emit(session)
	if str(state.get("status", "")) == "authenticated":
		_maybe_notify_new_account(state)

func _on_auth_error(code: String) -> void:
	last_error = code
	session_changed.emit(session)

func _maybe_notify_new_account(state: Dictionary) -> void:
	var user = state.get("user")
	if typeof(user) != TYPE_DICTIONARY:
		return
	var account_key := str(user.get("id", user.get("openId", "")))
	if account_key.is_empty():
		return
	var seen := ConfigFile.new()
	seen.load("user://hearthfall_owner_accounts.cfg")
	if bool(seen.get_value("accounts", account_key, false)):
		return
	seen.set_value("accounts", account_key, true)
	seen.save("user://hearthfall_owner_accounts.cfg")
	send_owner_event("new_player_account", "info", "New player account connected", "A player signed in to Hearthfall Colony for the first time on this browser.", {"account_id": account_key})

func request(procedure: String, input: Dictionary, kind: String, callback: Callable = Callable()) -> int:
	if not is_online():
		var offline := {"ok": false, "error": "online_preview_required"}
		if callback.is_valid():
			callback.call(offline)
		request_finished.emit(-1, offline)
		return -1
	var request_id := ManusAuth.call_rpc(kind, procedure, input)
	if request_id < 0:
		var unavailable := {"ok": false, "error": "auth_bootstrap_missing"}
		if callback.is_valid():
			callback.call(unavailable)
		request_finished.emit(-1, unavailable)
		return -1
	if callback.is_valid():
		_pending[request_id] = callback
	return request_id

func _on_rpc_completed(request_id: int, result: Dictionary) -> void:
	request_finished.emit(request_id, result)
	var callback = _pending.get(request_id)
	if callback != null and callback is Callable and callback.is_valid():
		_pending.erase(request_id)
		callback.call(result)

func list_saves(callback: Callable = Callable()) -> int:
	return request("saves.list", {}, "query", callback)

func save_current(sim, slot: String, label: String, callback: Callable = Callable()) -> int:
	if sim == null or not sim.has_method("serialize_state"):
		if callback.is_valid():
			callback.call({"ok": false, "error": "colony_not_ready"})
		return -1
	var meta: Dictionary = sim.cloud_meta()
	var input := {
		"slot": slot,
		"label": label,
		"data": sim.serialize_state(),
		"day": int(meta.get("day", 1)),
		"population": int(meta.get("population", 0)),
		"mood": int(meta.get("mood", 50)),
	}
	return request("saves.put", input, "mutation", func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			send_owner_event("cloud_save_failed", "warning", "Cloud save failed", "A player cloud save request failed.", {"slot": slot, "error": str(result.get("error", "unknown"))})
		if callback.is_valid():
			callback.call(result)
	)

func load_slot(slot: String, callback: Callable = Callable()) -> int:
	return request("saves.get", {"slot": slot}, "query", callback)

func delete_slot(slot: String, callback: Callable = Callable()) -> int:
	return request("saves.delete", {"slot": slot}, "mutation", callback)

func send_owner_event(event_type: String, severity: String, title: String, message: String, context: Dictionary = {}) -> void:
	if not is_signed_in():
		return
	var key := "%s:%s" % [event_type, title]
	var now := Time.get_ticks_msec()
	if now - int(_owner_event_times.get(key, 0)) < 30000:
		return
	_owner_event_times[key] = now
	request("ownerEvent", {
		"eventType": event_type,
		"severity": severity,
		"title": title,
		"message": message,
		"context": context,
	}, "mutation")

func list_board(board_id: String, callback: Callable = Callable()) -> int:
	return request("leaderboard.list", {"boardId": board_id, "limit": 10}, "query", callback)

func publish_colony(sim, callback: Callable = Callable()) -> void:
	if not is_signed_in():
		if callback.is_valid():
			callback.call({"ok": false, "error": "sign_in_required"})
		return
	if sim == null:
		if callback.is_valid():
			callback.call({"ok": false, "error": "colony_not_ready"})
		return
	_publish_state = {
		"sim": sim,
		"boards": BOARDS.duplicate(true),
		"index": 0,
		"results": [],
		"callback": callback,
	}
	_publish_next()

func _publish_next() -> void:
	if _publish_state.is_empty():
		return
	var index := int(_publish_state.get("index", 0))
	var boards: Array = _publish_state.get("boards", [])
	if index >= boards.size():
		var final_result := {"ok": true, "results": _publish_state.get("results", [])}
		var callback = _publish_state.get("callback")
		_publish_state = {}
		if callback != null and callback is Callable and callback.is_valid():
			callback.call(final_result)
		publish_finished.emit(final_result)
		return
	var board: Dictionary = boards[index]
	request("leaderboard.beginRun", {
		"boardId": str(board.get("id", "")),
		"protocolVersion": 1,
		"rulesVersion": str(board.get("rules", "v1")),
	}, "mutation", func(result: Dictionary) -> void: _on_begin_run(result))

func _on_begin_run(result: Dictionary) -> void:
	if _publish_state.is_empty():
		return
	var index := int(_publish_state.get("index", 0))
	var boards: Array = _publish_state.get("boards", [])
	if index >= boards.size():
		return
	var board: Dictionary = boards[index]
	if not bool(result.get("ok", false)):
		var failed: Array = _publish_state.get("results", [])
		failed.append({"board": str(board.get("id", "")), "label": str(board.get("label", "")), "ok": false, "error": str(result.get("error", "leaderboard_unavailable"))})
		_publish_state["results"] = failed
		_publish_state["index"] = index + 1
		_publish_next()
		return
	var run_id := str(result.get("data", {}).get("runId", ""))
	var sim = _publish_state.get("sim")
	var duration_ms := clampi(int(float(sim.game_elapsed_seconds) * 1000.0), 60000, 1800000)
	request("leaderboard.submitRun", {
		"runId": run_id,
		"score": _score_for(str(board.get("id", "")), sim),
		"durationMs": duration_ms,
	}, "mutation", func(submit_result: Dictionary) -> void: _on_submit_run(submit_result))

func _on_submit_run(result: Dictionary) -> void:
	if _publish_state.is_empty():
		return
	var index := int(_publish_state.get("index", 0))
	var boards: Array = _publish_state.get("boards", [])
	var board: Dictionary = boards[index]
	var results: Array = _publish_state.get("results", [])
	results.append({
		"board": str(board.get("id", "")),
		"label": str(board.get("label", "")),
		"ok": bool(result.get("ok", false)),
		"error": str(result.get("error", "")) if not bool(result.get("ok", false)) else "",
	})
	_publish_state["results"] = results
	_publish_state["index"] = index + 1
	_publish_next()

func _score_for(board_id: String, sim) -> int:
	match board_id:
		"survival-days-v1":
			return clampi(int(sim.absolute_day), 0, 36500)
		"population-v1":
			return clampi(sim.colonists.size(), 0, 1000)
		"mood-v1":
			return clampi(int(round(sim.average_mood() * 100.0)), 0, 10000)
	return 0
