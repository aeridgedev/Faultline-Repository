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

## The match scene. Loading it IS the match-start path: Main._ready() generates
## the world, registers the local player and calls start_match(). Held here so
## the home screen's PLAY button enters a match exactly the way launching the
## game used to, without duplicating any of that setup.
const MATCH_SCENE_PATH := "res://src/core/Main.tscn"

## The home/title screen — the project's boot scene (run/main_scene) and, since
## the esc menu exists, also the mid-run exit target. Named here so the two ways
## into it agree.
const HOME_SCENE_PATH := "res://src/ui/HomeScreen.tscn"

var state: MatchState = MatchState.BOOT
var data: Dictionary = {}          # loaded from data/*.json via DataLoader
var match_elapsed: float = 0.0     # seconds since match start

## Result of the most recent COMPLETED match, for the home screen's "last match"
## block. IN-MEMORY ONLY — never written to disk, so it is gone the moment the
## process exits; empty until the first match of this run ends. Written by HUD
## (the integration layer) on death and on a win; deliberately NOT cleared by
## _reset_roster(), so it survives Play Again / returning to the home screen.
## Keys mirror DeathScreen.show_death()'s: kills / layer_name / placement /
## total_players / survival_seconds, plus "outcome".
var last_match_summary: Dictionary = {}

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


# --- Last-match summary (home screen) ---

## Stores the local player's end-of-match stats. Called by HUD when the local
## player's match ends — once on death, once on a win — with the same values it
## already computed for DeathScreen, so the home screen can never disagree with
## the death screen. Stores a copy so a later mutation by the caller can't reach
## back into it. Purely a record: no roster or match state is touched.
func record_match_summary(summary: Dictionary) -> void:
	last_match_summary = summary.duplicate(true)


## Home-screen PLAY. Match initialisation is NOT duplicated here — loading
## MATCH_SCENE_PATH runs Main._ready(), which is the same and only match-start
## path the game used when it booted straight into a match.
func start_new_match() -> void:
	_reset_roster()
	get_tree().change_scene_to_file(MATCH_SCENE_PATH)


## Esc menu's RETURN TO HOME: abandons the in-progress match and goes back to the
## home screen. Called by HUD (the integration layer) when PauseMenu emits
## home_requested.
##
## This is an ABANDONMENT, not a result. last_match_summary is deliberately NOT
## written here — whatever the last COMPLETED match left there (or the empty
## first-launch state) must survive untouched, so the home screen never reports a
## run the player walked out of as if it had finished. The only writers stay
## HUD's two end-of-match points.
##
## Uses the same _reset_roster() that start_new_match()/restart_match() use, so
## no participant, kill count or match state leaks into the next match.
func return_to_home() -> void:
	# PauseMenu already unpaused itself before emitting, but clear the flag here
	# too: get_tree().paused survives a scene change, and a paused tree would
	# leave the home screen frozen (it is PROCESS_MODE_PAUSABLE like everything
	# else). Any future caller of this method gets that guarantee for free.
	get_tree().paused = false
	_reset_roster()
	get_tree().change_scene_to_file(HOME_SCENE_PATH)


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
	# Credit the kill BEFORE the win check: the 0-alive wipe branch picks the
	# top-of-leaderboard participant, so the killing blow that ended the match
	# has to be counted before that decision is made.
	_credit_killer_of(id)
	roster_changed.emit()
	_check_win_condition()


## Credits a kill to whoever landed the killing blow on `victim_id`, read from
## the victim's own PlayerStats.last_killer_id (set in take_damage() at the
## instant health reached 0).
##
## Centralised here because mark_player_dead() is the ONE point every participant
## type funnels through on death. Crediting at the attacker's hit site instead
## only ever worked for the local player (PlayerController was the sole caller of
## record_kill()), so a TestDummy that killed the player scored 0 on the
## leaderboard and could never be credited as the nominal winner by the 0-alive
## wipe branch. Any future participant type (step 9's networked players) gets
## correct kill attribution here for free, as long as its damage passes a real
## source_id into take_damage() — which is already a locked rule.
##
## Environmental deaths (storm/depth/pressure) pass source_id = -1 and credit
## nobody, which is correct; a self-inflicted id is guarded out for the same
## reason.
func _credit_killer_of(victim_id: int) -> void:
	var node := get_player_node(victim_id)
	if node == null or not node.has_method("get_stats"):
		return
	var victim_stats: PlayerStats = node.get_stats()
	if victim_stats == null:
		return
	var killer_id: int = victim_stats.last_killer_id
	if killer_id == -1 or killer_id == victim_id:
		return
	record_kill(killer_id)


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
	list.sort_custom(_compare_leaderboard)
	return list


## Kills descending is the primary key and the only one the UI advertises. The
## remaining keys exist to make the ordering TOTAL and deterministic: a bare
## `a["kills"] > b["kills"]` leaves every equal-kill group in an arbitrary order,
## so tied participants could swap ranks between two calls — and the 0-alive wipe
## branch picks `[0]` from this list as the credited winner, which must not be a
## coin flip. Tiebreaks: survivors outrank the dead, then deeper outranks
## shallower, then lowest roster id (registration order, stable for the match).
func _compare_leaderboard(a: Dictionary, b: Dictionary) -> bool:
	var a_kills := int(a["kills"])
	var b_kills := int(b["kills"])
	if a_kills != b_kills:
		return a_kills > b_kills
	var a_alive := bool(a["alive"])
	var b_alive := bool(b["alive"])
	if a_alive != b_alive:
		return a_alive
	var a_layer := int(a["deepest_layer"])
	var b_layer := int(b["deepest_layer"])
	if a_layer != b_layer:
		return a_layer > b_layer
	return int(a["id"]) < int(b["id"])


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
## Behaviour is unchanged from before the home screen existed — the three reset
## statements simply moved into _reset_roster(), which start_new_match() shares.
func restart_match() -> void:
	_reset_roster()
	get_tree().reload_current_scene()


## Clears the participant roster and drops back to LOBBY, ready for a fresh
## Main._ready(). Does NOT clear last_match_summary — that is a record of a
## finished match and must outlive the roster it was derived from.
func _reset_roster() -> void:
	_players.clear()
	_next_player_id = 1
	_set_state(MatchState.LOBBY)
