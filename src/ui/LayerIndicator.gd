## Faultline — shows the player's current layer name as they descend.
## Call init(stats) from HUD after player is spawned.
class_name LayerIndicator
extends PanelContainer

@onready var _label: Label = $Label


func init(stats: PlayerStats) -> void:
	_label.text = Constants.LAYER_NAMES.get(stats.get_layer(), "—")
	stats.layer_changed.connect(_on_layer_changed)


func _on_layer_changed(new_layer: int) -> void:
	_label.text = Constants.LAYER_NAMES.get(new_layer, "—")
