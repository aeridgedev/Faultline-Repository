## Faultline — player input and physics controller.
class_name PlayerController
extends CharacterBody2D

@export var player_id: int = 0

@onready var stats: PlayerStats = $PlayerStats
@onready var stamina: Stamina = $Stamina

var _move_speed: float = 0.0    # TBD: loaded from GameManager.data["player_move_speed"]
var _gravity: float = 0.0       # TBD: loaded from GameManager.data["player_gravity"]
var _jump_velocity: float = 0.0 # TBD: loaded from GameManager.data["player_jump_velocity"]

var _terrain_manager: TerrainManager = null
var _equipped_drill: DrillBase = null

var _dig_target: Vector2i = Vector2i(-1, -1)
var _dig_timer: float = 0.0


func _ready() -> void:
	var d: Dictionary = GameManager.data
	_move_speed = float(d.get("player_move_speed", 0.0))       # TBD: balance pass
	_gravity = float(d.get("player_gravity", 0.0))             # TBD: balance pass
	_jump_velocity = float(d.get("player_jump_velocity", 0.0)) # TBD: balance pass


func init_world(tm: TerrainManager) -> void:
	_terrain_manager = tm


func equip_starter_drill() -> void:
	_equipped_drill = DrillBase.new()
	_equipped_drill.drill_class = Constants.DrillClass.PRECISION
	_equipped_drill.tier = Constants.Tier.COMMON
	_equipped_drill.init_from_data()


func _physics_process(delta: float) -> void:
	if stats.is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_apply_gravity(delta)
	_handle_jump()
	_handle_movement()
	_handle_drill(delta)
	_handle_attack_input()
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _jump_velocity


func _handle_movement() -> void:
	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = direction * _move_speed


func _handle_drill(delta: float) -> void:
	if not Input.is_action_pressed("drill"):
		_reset_dig()
		return
	if _equipped_drill == null or _equipped_drill.is_broken or _terrain_manager == null:
		return

	var target := _get_dig_target()
	if not _terrain_manager.has_tile(target):
		_reset_dig()
		return

	if target != _dig_target:
		_dig_target = target
		_dig_timer = _calc_dig_duration(target)

	_dig_timer -= delta
	if _dig_timer <= 0.0:
		if _terrain_manager.destroy_tile(_dig_target):
			_equipped_drill.consume_durability(1.0)
		_reset_dig()


func _reset_dig() -> void:
	_dig_target = Vector2i(-1, -1)
	_dig_timer = 0.0


func _get_dig_target() -> Vector2i:
	var dir := (get_global_mouse_position() - global_position).normalized()
	return _terrain_manager.world_to_cell(global_position + dir * float(Constants.TILE_SIZE))


func _calc_dig_duration(cell: Vector2i) -> float:
	var terrain_type: Variant = _terrain_manager.get_tile_type(cell)
	if terrain_type == null:
		return 0.0
	var base: Variant = TerrainTypes.base_dig_time(terrain_type)
	var class_mult: Variant = TerrainTypes.class_effectiveness(terrain_type, _equipped_drill.drill_class)
	var tier_mult: Variant = DrillTier.dig_time_mult(_equipped_drill.drill_class, _equipped_drill.tier)
	# TBD: all values null until balance pass; 1.0 keeps the dig system functional in the meantime
	var duration := float(base) if base != null else 1.0
	if class_mult != null:
		duration *= float(class_mult)
	if tier_mult != null:
		duration *= float(tier_mult)
	return duration


func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		_try_attack()


func _try_attack() -> void:
	pass # TODO(step 5): implement weapon/combat system
