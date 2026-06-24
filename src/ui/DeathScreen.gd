## Faultline — full-screen overlay shown when the local player dies.
## Shown by HUD on PlayerStats.player_died. Emits spectate_requested when
## the player clicks SPECTATE, at which point HUD hands off to SpectatorView.
class_name DeathScreen
extends Control

signal spectate_requested

@onready var _spectate_btn: Button = $CenterContainer/VBoxContainer/SpectateButton


func _ready() -> void:
	visible = false
	_spectate_btn.pressed.connect(func(): spectate_requested.emit())


func show_death() -> void:
	visible = true
