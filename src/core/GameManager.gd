extends Node
## Faultline — top-level game state & match flow (autoload singleton).
##
## Owns the loaded balance data and the high-level match state machine.
## Systems read tunable values through here (GameManager.data) so there is a
## single source of truth at runtime.

signal match_state_changed(new_state: MatchState)
signal roster_changed()
signal match_won(winner_id: int)

enum MatchState { BOOT, LOBBY, IN_MATCH, POST_MATCH }

var state: MatchState = MatchState.BOOT
var data: Dictionary = {}          # loaded from data/*.json via DataLoader
var match_elapsed: float = 0.0     # seconds since match start

# --- Match roster (step 8) ---
# Every match participant (the local player AND, per a deliberate DEV-scope
# decision, the DEV-ONLY TestDummy combat targets) gets a roster entry so the
# leaderboard/win-condition flow has real multi-entry data to exercise before
# step 9 (networking) exists. Real networked players will register here the
# same way. id:int -> {id, name, node, kills, deepest_layer, alive, is_dummy}.
var _players: Dictionary = {}
var _next_player_id: int = 1


func _ready() -> void:
	data = DataLoader.load_all()
	_set_state(MatchState.LOBBY)
	print("[Faultline] GameManager ready. Loaded %d balance keys." % data.size())

func _process(delta: float) -> void:
	if state == MatchState.IN_MATCH:
		match_elapsed += delta

func _set_state(new_state: MatchState) -> void:
	state = new_state
	match_state_changed.emit(new_state)

func start_match() -> void:
	match_elapsed = 0.0
	_set_state(MatchState.IN_MATCH)

func end_match() -> void:
	_set_state(MatchState.POST_MATCH)

## Convenience: which storm phase region is active at the current match time.
func current_storm_region() -> String:
	for phase in Constants.STORM_PHASES:
		var ends: bool = phase["end"] == -1 or match_elapsed < phase["end"]
		if match_elapsed >= phase["start"] and ends:
			return phase["region"]
	return ""


# --- Roster API ---

## Registers one match participant (local player or TestDummy) and returns its
## roster id. `node` is the live scene node (PlayerController/TestDummy) so the
## spectator system can camera-follow it directly; guarded with
## is_instance_valid() everywhere it's read back since dummies queue_free().
func register_player(player_name: String, node: Node, is_dummy: bool = false) -> int:
	var id := _next_player_id
	_next_player_id += 1
	_players[id] = {
		"id": id, "name": player_name, "node": node,
		"kills": 0, "deepest_layer": Constants.Layer.CRUST,
		"alive": true, "is_dummy": is_dummy,
	}
	roster_changed.emit()
	return id


func record_kill(id: int) -> void:
	if not _players.has(id):
		return
	_players[id]["kills"] += 1
	roster_changed.emit()


func record_layer_reached(id: int, layer: int) -> void:
	if not _players.has(id):
		return
	_players[id]["deepest_layer"] = maxi(_players[id]["deepest_layer"], layer)


## Marks a participant dead and checks the win condition. Idempotent — a
## second call for the same id (shouldn't happen; PlayerStats.is_dead guards
## against re-firing player_died) is a no-op rather than double-counting.
func mark_player_dead(id: int) -> void:
	if not _players.has(id) or not _players[id]["alive"]:
		return
	_players[id]["alive"] = false
	roster_changed.emit()
	_check_win_condition()


func get_player(id: int) -> Dictionary:
	return _players.get(id, {})


## Guards against dummies/players that have already been freed.
func get_player_node(id: int) -> Node:
	var node = _players.get(id, {}).get("node", null)
	if node != null and is_instance_valid(node):
		return node
	return null


func get_living_player_ids() -> Array:
	var result: Array = []
	for id in _players:
		if _players[id]["alive"] and get_player_node(id) != null:
			result.append(id)
	return result


## Every roster entry (dead + alive), sorted by kills descending, for the
## leaderboard. Callers (WinScreen) only read it once and discard it, so this
## returns the live entries directly rather than duplicating each one.
func get_leaderboard() -> Array:
	var list: Array = []
	for id in _players:
		list.append(_players[id])
	list.sort_custom(func(a, b): return a["kills"] > b["kills"])
	return list


func _check_win_condition() -> void:
	if state != MatchState.IN_MATCH:
		return
	var alive := get_living_player_ids()
	if alive.size() == 1:
		end_match()
		# TEMP DEBUG (remove after win-screen testing): confirms the signal fires.
		print("[Faultline][DEBUG] match_won FIRING — sole survivor id=%d, name=%s" % [
			alive[0], _players[alive[0]].get("name", "?")])
		match_won.emit(alive[0])
	elif alive.size() == 0 and not _players.is_empty():
		# Simultaneous final wipe (e.g. the 17:30 storm deadline or a Seismic
		# charge kills the last remaining participants on the SAME frame, so we
		# jump straight from 2-alive to 0-alive without ever passing through
		# exactly 1). Without this branch the win screen would be silently
		# skipped when the very last participant dies. Credit the top-of-
		# leaderboard participant (most kills) as the nominal winner so results
		# still show meaningfully.
		end_match()
		var winner_id: int = get_leaderboard()[0]["id"]
		print("[Faultline][DEBUG] match_won FIRING (wipe) — no survivors; crediting id=%d" % winner_id)
		match_won.emit(winner_id)


## Resets the roster and reloads the match scene fresh (Play Again). Main.gd's
## _ready() re-registers every participant and calls start_match() again, so
## match_elapsed/state come back clean without any extra bookkeeping here.
func restart_match() -> void:
	_players.clear()
	_next_player_id = 1
	_set_state(MatchState.LOBBY)
	get_tree().reload_current_scene()
