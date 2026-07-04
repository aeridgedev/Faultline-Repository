## Faultline — player combat and progression state for one match.
class_name PlayerStats
extends Node

const _DamageNumberScene := preload("res://src/ui/DamageNumber.tscn")

signal health_changed(new_hp: float, max_hp: float)
signal player_died
signal layer_changed(new_layer: int)
signal active_effects_changed(effects: Array)

var max_health: float  # TBD: loaded from GameManager.data at _ready; null-safe sentinel if missing
var current_health: float

var is_dead: bool = false
var damage_reduction: float = 0.0   # 0.0–1.0; set by ToughnessRelic
var life_capsule_active: bool = false  # set by LifeCapsule; consumed on first lethal hit
var kill_count: int = 0

# Set on every take_damage() call; read by PlayerDeath/HUD on player_died to
# populate the DeathScreen ("killed by ...") and by SpectatorView to know
# which roster id the camera should jump to. source_id is -1 for environmental
# damage (storm/hazard/DoT) — there's no player to spectate-follow for those.
var last_killer_name: String = "Unknown"
var last_killer_id: int = -1
var last_killing_damage: float = 0.0

var _current_layer: int = Constants.Layer.CRUST
var _storm: StormSystem = null

var equipped_armor: ArmorBase = null   # single sidebar slot; null = unarmored

# { effect_name: { "remaining": float, "is_buff": bool, "params": Dictionary, "dot_accum": float } }
# params carries the effect's MECHANICAL payload (all optional):
#   "move_speed_mult":    float — multiplies movement speed (PlayerController reads it)
#   "damage_output_mult": float — multiplies outgoing melee damage (PlayerController)
#   "frozen":             bool  — blocks all movement and actions (Paralysis Bomb)
#   "dot_dps":            float — damage per second, ticked here every dot_interval
#   "dot_interval":       float — seconds between DoT ticks (default 1.0)
#   "hazard_resist":      float — 0.0–1.0 reduction of depth/pressure hazard damage
#   "revealed":           bool  — position exposed (Echo Charge); marker rendered separately
var _active_effects: Dictionary = {}
var _effects_tick: float = 0.0


func _ready() -> void:
	var data_hp = GameManager.data.get("player_max_health", null) if GameManager.data else null
	max_health = float(data_hp) if data_hp != null else 100.0  # TBD: 100.0 dev fallback until balance pass
	current_health = max_health


func _process(delta: float) -> void:
	if _active_effects.is_empty():
		_effects_tick = 0.0
		return
	_effects_tick += delta
	var tick_fired := _effects_tick >= 1.0
	if tick_fired:
		_effects_tick -= 1.0
	var any_expired := false
	var to_remove: Array[String] = []
	for effect_name: String in _active_effects:
		var entry: Dictionary = _active_effects[effect_name]
		entry["remaining"] -= delta
		_tick_dot(effect_name, entry, delta)
		if entry["remaining"] <= 0.0:
			to_remove.append(effect_name)
			any_expired = true
	for effect_name: String in to_remove:
		_active_effects.erase(effect_name)
	if any_expired or tick_fired:
		active_effects_changed.emit(_build_effects_array())


# Damage-over-time payload (Heat Charge burn): applies dot_dps in dot_interval chunks.
func _tick_dot(effect_name: String, entry: Dictionary, delta: float) -> void:
	var params: Dictionary = entry["params"]
	var dps: float = float(params.get("dot_dps", 0.0))
	if dps <= 0.0 or is_dead:
		return
	var interval: float = maxf(float(params.get("dot_interval", 1.0)), 0.05)
	entry["dot_accum"] += delta
	while entry["dot_accum"] >= interval:
		entry["dot_accum"] -= interval
		take_damage(dps * interval, effect_name)
		if is_dead:
			return


## Display-only effect (no mechanical payload) — kept for existing callers.
func apply_effect(effect_name: String, duration: float, is_buff: bool) -> void:
	apply_status(effect_name, duration, is_buff, {})


## Effect with a mechanical payload (see params doc above _active_effects).
## Re-applying the same name overwrites the entry (refreshes duration + payload).
func apply_status(effect_name: String, duration: float, is_buff: bool, params: Dictionary = {}) -> void:
	var final_duration := duration
	var final_params := params
	if equipped_armor != null and not equipped_armor.is_broken and not is_buff:
		# Echo armor shortens incoming debuffs (mult < 1); neutral 1.0 otherwise.
		final_duration *= equipped_armor.debuff_duration_mult()
		# Hellforge armor resists burn DoT: scale dot_dps by (1 - burn_resist). With a
		# null/0 passive this is a no-op. Duplicate the dict so we never mutate the caller's.
		if params.has("dot_dps") and equipped_armor.burn_resist() > 0.0:
			final_params = params.duplicate()
			final_params["dot_dps"] = float(params["dot_dps"]) * (1.0 - equipped_armor.burn_resist())
	_active_effects[effect_name] = {
		"remaining": final_duration, "is_buff": is_buff, "params": final_params, "dot_accum": 0.0,
	}
	active_effects_changed.emit(_build_effects_array())


func _build_effects_array() -> Array:
	var result: Array = []
	for effect_name: String in _active_effects:
		result.append({
			"name": effect_name,
			"remaining": _active_effects[effect_name]["remaining"],
			"is_buff": _active_effects[effect_name]["is_buff"],
		})
	return result


# --- Status queries (read by PlayerController, DepthHazard, PressureSystem) ---

## Product of every active move_speed_mult (slows < 1.0, boosts > 1.0).
func status_move_speed_mult() -> float:
	var mult := 1.0
	for effect_name: String in _active_effects:
		mult *= float(_active_effects[effect_name]["params"].get("move_speed_mult", 1.0))
	return mult


## Product of every active damage_output_mult (Weakness < 1.0, Bloodstim > 1.0).
func status_damage_output_mult() -> float:
	var mult := 1.0
	for effect_name: String in _active_effects:
		mult *= float(_active_effects[effect_name]["params"].get("damage_output_mult", 1.0))
	return mult


## True while any active effect freezes the player (Paralysis Bomb).
func is_frozen() -> bool:
	for effect_name: String in _active_effects:
		if _active_effects[effect_name]["params"].get("frozen", false):
			return true
	return false


## Tempest armor passive — movement multiplier while worn (1.0 neutral / broken / no armor).
## PlayerController multiplies its move speed by this alongside the status/relic mults.
func armor_move_speed_mult() -> float:
	if equipped_armor != null and not equipped_armor.is_broken:
		return equipped_armor.move_speed_mult()
	return 1.0


## Equip (or, with null, clear) the armor sidebar piece. Called by InventoryManager.
func equip_armor(armor: ArmorBase) -> void:
	equipped_armor = armor


## Strongest active hazard resistance, 0.0–1.0 (Thermal Capsule).
func hazard_resist() -> float:
	var best := 0.0
	for effect_name: String in _active_effects:
		best = maxf(best, float(_active_effects[effect_name]["params"].get("hazard_resist", 0.0)))
	return clampf(best, 0.0, 1.0)


## True while an Echo Charge reveal is active on this player.
func is_revealed() -> bool:
	for effect_name: String in _active_effects:
		if _active_effects[effect_name]["params"].get("revealed", false):
			return true
	return false


## source_name/source_id identify the killing blow for the DeathScreen/SpectatorView
## (step 8): source_id is the attacking PlayerController/TestDummy's GameManager
## roster id, or -1 for environmental damage (storm/hazard/DoT) which has no
## player to credit or spectate-follow.
func take_damage(amount: float, source_name: String = "Unknown", source_id: int = -1) -> void:
	if is_dead:
		return
	# Damage order: armor first (flat subtracted, then percent of the remainder), THEN
	# the Toughness relic's flat multiplier on what armor let through. Armor takes one
	# durability point per take_damage() call — note a burn (DoT) applies once per tick,
	# so each burn tick counts as a hit; accepted as-is for now (balance pass may revisit).
	var effective := amount
	if equipped_armor != null and not equipped_armor.is_broken:
		effective = maxf(effective - equipped_armor.flat_reduction(), 0.0)
		effective *= (1.0 - equipped_armor.percent_reduction())
		equipped_armor.register_hit()
	effective *= (1.0 - clampf(damage_reduction, 0.0, 1.0))
	current_health = clampf(current_health - effective, 0.0, max_health)
	if current_health == 0.0 and life_capsule_active:
		life_capsule_active = false
		current_health = 1.0
	if effective > 0.0:
		_spawn_damage_number(effective)
	health_changed.emit(current_health, max_health)
	if current_health == 0.0:
		last_killer_name = source_name
		last_killer_id = source_id
		last_killing_damage = effective
		is_dead = true
		player_died.emit()


func _spawn_damage_number(amount: float) -> void:
	var player := get_parent()
	var dn: DamageNumber = _DamageNumberScene.instantiate()
	player.add_child(dn)
	dn.global_position = player.global_position + Vector2(0.0, -Constants.TILE_SIZE * 1.5)
	dn.setup(amount)


func init_storm(storm: StormSystem) -> void:
	_storm = storm


func heal(amount: float) -> void:
	if is_dead:
		return
	var effective := amount
	if _storm != null:
		effective *= _storm.get_heal_mult()
	current_health = clampf(current_health + effective, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func add_kill() -> void:
	kill_count += 1


func set_layer(new_layer: int) -> void:
	if new_layer <= _current_layer:
		return
	_current_layer = new_layer
	layer_changed.emit(_current_layer)


func get_layer() -> int:
	return _current_layer
