## Faultline — reacts to player_died, freezes controller, enters spectator stub.
class_name PlayerDeath
extends Node

# TODO(match controller): connect death_processed to alive-count logic
signal death_processed(player_id: int)

@onready var _stats: PlayerStats = $"../PlayerStats"
@onready var _controller: PlayerController = $".."


func _ready() -> void:
	_stats.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	_controller.set_physics_process(false)
	_controller.set_process_input(false)
	death_processed.emit(_controller.player_id)
	_enter_spectator_mode()


func _enter_spectator_mode() -> void:
	# TODO(step 8): wire up SpectatorView UI
	print("[PlayerDeath] player %d entering spectator mode" % _controller.player_id)
