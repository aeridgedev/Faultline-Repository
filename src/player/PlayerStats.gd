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

var _current_layer: int = Constants.Layer.CRUST
var _storm: StormSystem = null

var equipped_armor: Node = null

# { effect_name: { "remaining": float, "is_buff": bool } }
var _active_effects: Dictionary = {}
var _effects_tick: float = 0.0


func _ready() -> void:
	var data_hp = GameManager.data.get("player_max_health", null) if GameManager.data else null
	max_health = float(data_hp) if data_hp != null else 100.0  # TBD: 100.0 dev fallback until balance pass
	current_health = max_health
	_start_test_effects()


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
		_active_effects[effect_name]["remaining"] -= delta
		if _active_effects[effect_name]["remaining"] <= 0.0:
			to_remove.append(effect_name)
			any_expired = true
	for effect_name: String in to_remove:
		_active_effects.erase(effect_name)
	if any_expired or tick_fired:
		active_effects_changed.emit(_build_effects_array())


func apply_effect(effect_name: String, duration: float, is_buff: bool) -> void:
	_active_effects[effect_name] = {"remaining": duration, "is_buff": is_buff}
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


func _start_test_effects() -> void:
	var t1 := Timer.new()
	t1.wait_time = 2.0
	t1.one_shot = true
	t1.timeout.connect(func(): apply_effect("Haste", 8.0, true))
	add_child(t1)
	t1.start()
	var t2 := Timer.new()
	t2.wait_time = 5.0
	t2.one_shot = true
	t2.timeout.connect(func(): apply_effect("Weakened", 6.0, false))
	add_child(t2)
	t2.start()


func take_damage(amount: float) -> void:
	if is_dead:
		return
	var effective := amount * (1.0 - clampf(damage_reduction, 0.0, 1.0))
	current_health = clampf(current_health - effective, 0.0, max_health)
	if current_health == 0.0 and life_capsule_active:
		life_capsule_active = false
		current_health = 1.0
	if effective > 0.0:
		_spawn_damage_number(effective)
	health_changed.emit(current_health, max_health)
	if current_health == 0.0:
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
