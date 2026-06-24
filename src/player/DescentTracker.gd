## Faultline — monitors player Y to detect layer transitions and notifies PlayerStats.
class_name DescentTracker
extends Node

signal layer_changed(new_layer: int)

@onready var _stats: PlayerStats = $"../PlayerStats"

var _layer_manager: LayerManager


func _ready() -> void:
	_stats.layer_changed.connect(_on_layer_changed)


func init(lm: LayerManager) -> void:
	_layer_manager = lm


func _physics_process(_delta: float) -> void:
	if _layer_manager == null or _stats.is_dead:
		return

	var y: float = (get_parent() as Node2D).global_position.y
	# Cast to int explicitly — layer_at_y returns a Constants.Layer enum value.
	var new_layer: int = int(_layer_manager.layer_at_y(y))

	if new_layer != _stats.get_layer():
		_stats.set_layer(new_layer)


func _on_layer_changed(new_layer: int) -> void:
	layer_changed.emit(new_layer)
