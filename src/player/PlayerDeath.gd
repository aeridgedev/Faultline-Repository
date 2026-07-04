## Faultline — reacts to player_died: freezes the controller and reports the
## death to GameManager's roster (which checks the win condition). The actual
## DeathScreen/SpectatorView UI flow is driven by HUD, which listens to the
## same PlayerStats.player_died signal directly (see HUD._on_player_died).
class_name PlayerDeath
extends Node

signal death_processed(player_id: int)
signal died

@onready var _stats: PlayerStats = $"../PlayerStats"
@onready var _controller: PlayerController = $".."


func _ready() -> void:
	_stats.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	_controller.freeze_controls()
	GameManager.mark_player_dead(_controller.player_id)
	death_processed.emit(_controller.player_id)
	died.emit()
