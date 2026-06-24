## Faultline — spectator overlay shown after the player clicks SPECTATE.
## Offline stub: no other players to follow, so the camera stays put.
## Step 9 (network) will replace show_spectating() with real player-follow logic.
class_name SpectatorView
extends Control


func _ready() -> void:
	visible = false


func show_spectating() -> void:
	visible = true
