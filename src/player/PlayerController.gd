## Faultline — player input and physics controller.
class_name PlayerController
extends CharacterBody2D

@export var player_id: int = 0

@onready var stats: PlayerStats = $PlayerStats
@onready var stamina: Stamina = $Stamina

var _move_speed: float = 0.0    # TBD: loaded from GameManager.data["player_move_speed"]
var _gravity: float = 0.0       # TBD: loaded from GameManager.data["player_gravity"]
var _jump_velocity: float = 0.0 # TBD: loaded from GameManager.data["player_jump_velocity"]


func _ready() -> void:
	var d: Dictionary = GameManager.data
	_move_speed = float(d.get("player_move_speed", 0.0))       # TBD: balance pass
	_gravity = float(d.get("player_gravity", 0.0))             # TBD: balance pass
	_jump_velocity = float(d.get("player_jump_velocity", 0.0)) # TBD: balance pass


func _physics_process(delta: float) -> void:
	if stats.is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_apply_gravity(delta)
	_handle_jump()
	_handle_movement()
	_handle_drill_input()
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


func _handle_drill_input() -> void:
	if Input.is_action_pressed("drill"):
		_try_drill()


func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		_try_attack()


func _try_drill() -> void:
	pass # TODO(step 2): implement drill system


func _try_attack() -> void:
	pass # TODO(step 5): implement weapon/combat system
