## Faultline — player combat and progression state for one match.
class_name PlayerStats
extends Node

const _DamageNumberScene := preload("res://src/ui/DamageNumber.tscn")

signal health_changed(new_hp: float, max_hp: float)
signal player_died
signal layer_changed(new_layer: int)

var max_health: float  # TBD: loaded from GameManager.data at _ready; null-safe sentinel if missing
var current_health: float

var is_dead: bool = false
var damage_reduction: float = 0.0   # 0.0–1.0; set by ToughnessRelic
var life_capsule_active: bool = false  # set by LifeCapsule; consumed on first lethal hit

var _current_layer: int = Constants.Layer.CRUST
var _storm: StormSystem = null

var equipped_armor: Node = null


func _ready() -> void:
	var data_hp = GameManager.data.get("player_max_health", null) if GameManager.data else null
	max_health = float(data_hp) if data_hp != null else 100.0  # TBD: 100.0 dev fallback until balance pass
	current_health = max_health


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


func set_layer(new_layer: int) -> void:
	if new_layer <= _current_layer:
		return
	_current_layer = new_layer
	layer_changed.emit(_current_layer)


func get_layer() -> int:
	return _current_layer
