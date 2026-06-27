## Faultline — short-lived world-space label that floats upward and fades when damage is taken.
## Spawn via DamageNumberScene.instantiate(), add_child(), set global_position, then call setup().
class_name DamageNumber
extends Node2D

const _FLOAT_SPEED := 22.0   # world px/s; appears ~55 px/s on screen at 2.5x camera zoom
const _LIFETIME    := 0.9    # seconds until fully faded and freed

var _elapsed: float = 0.0

@onready var _label: Label = $Label


func _ready() -> void:
	top_level = true   # ignore parent transform; stays in world space after reparenting

	_label.custom_minimum_size = Vector2(60, 20)
	_label.position = Vector2(-30, -20)   # center the box at origin, offset above it
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var s := LabelSettings.new()
	s.font_size = 8           # 8 world-px → ~20 screen-px at 2.5x zoom; readable without dominating
	s.font_color = Color.WHITE
	s.outline_size = 2
	s.outline_color = Color(0.0, 0.0, 0.0, 0.90)
	_label.label_settings = s


func setup(amount: float) -> void:
	_label.text = str(int(amount)) if floorf(amount) == amount else "%.1f" % amount


func _process(delta: float) -> void:
	_elapsed += delta
	position.y -= _FLOAT_SPEED * delta
	modulate.a = maxf(0.0, 1.0 - (_elapsed / _LIFETIME))
	if _elapsed >= _LIFETIME:
		queue_free()
