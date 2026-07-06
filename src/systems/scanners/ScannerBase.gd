## Faultline — shared scanner logic for BasicScanner / DeepRadar.
##
## OFFLINE PLACEHOLDER (documented deviation, same spirit as TestDummy roster
## registration — see GAME_STATE.md Known Issues #7): detection queries the
## LOCAL GameManager roster directly. Once step 9 (networking) exists, the
## authoritative server must run this query and send results ONLY to the
## scanning player. Scanned players are NOT notified (LOCKED) — which is why
## activate() never applies a "Revealed" status to targets (a status would
## render on the victim's HUD debuff panel = a notification). The caller
## (PlayerController) spawns the through-terrain markers on the scanner
## user's side only.
class_name ScannerBase
extends Resource

signal scan_started(scanner_pos: Vector2, radius: float)
signal scan_ended

const DURATION := 8.0  # Constants.SCANNER_DURATION_SECONDS (LOCKED; kept literal — autoload consts can't be used in const expressions)

var _active: bool = false
var _time_remaining: float = 0.0


## Subclasses return their world_config.json range key.
func _range_key() -> String:
	return ""


## Detection radius from data. TBD-null-safe: null/missing → 0.0 (scan
## "succeeds" but detects nothing) — never invent a fallback range here.
func get_radius() -> float:
	var r: Variant = GameManager.data.get(_range_key(), null)
	return float(r) if r != null else 0.0


## Runs the scan from world_pos. Returns the living roster participants
## (Node2D, excluding exclude_id — the scanning player) within radius.
## Returns [] if a scan is already running. Emits scan_started either way a
## scan begins; visuals are the caller's job (Resources can't touch the tree).
func activate(world_pos: Vector2, exclude_id: int = -1) -> Array:
	if _active:
		return []
	var radius := get_radius()
	_active = true
	_time_remaining = DURATION
	scan_started.emit(world_pos, radius)
	var found: Array = []
	if radius > 0.0:
		for id in GameManager.get_living_player_ids():
			if id == exclude_id:
				continue
			var node := GameManager.get_player_node(id)
			if node is Node2D and (node as Node2D).global_position.distance_to(world_pos) <= radius:
				found.append(node)
	return found


func tick(delta: float) -> void:
	if not _active:
		return
	_time_remaining -= delta
	if _time_remaining <= 0.0:
		_active = false
		scan_ended.emit()


func is_active() -> bool:
	return _active
