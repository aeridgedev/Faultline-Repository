extends Node
## Faultline — top-level game state & match flow (autoload singleton).
##
## Owns the loaded balance data and the high-level match state machine.
## Systems read tunable values through here (GameManager.data) so there is a
## single source of truth at runtime.

signal match_state_changed(new_state: MatchState)

enum MatchState { BOOT, LOBBY, IN_MATCH, POST_MATCH }

var state: MatchState = MatchState.BOOT
var data: Dictionary = {}          # loaded from data/*.json via DataLoader
var match_elapsed: float = 0.0     # seconds since match start

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
