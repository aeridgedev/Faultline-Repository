## Faultline — full-screen overlay shown when the local player dies.
## Shown by HUD on PlayerStats.player_died. Emits spectate_requested when
## the player clicks SPECTATE, at which point HUD hands off to SpectatorView.
class_name DeathScreen
extends Control

signal spectate_requested

@onready var _panel: PanelContainer = $CenterContainer/Panel
@onready var _title_label: Label = $CenterContainer/Panel/VBoxContainer/TitleLabel
@onready var _killer_label: Label = $CenterContainer/Panel/VBoxContainer/KillerLabel
@onready var _damage_label: Label = $CenterContainer/Panel/VBoxContainer/DamageLabel
@onready var _layer_label: Label = $CenterContainer/Panel/VBoxContainer/LayerLabel
@onready var _kills_label: Label = $CenterContainer/Panel/VBoxContainer/KillsLabel
@onready var _spectate_btn: Button = $CenterContainer/Panel/VBoxContainer/SpectateButton


func _ready() -> void:
	visible = false
	_style_panel()
	_style_labels()
	_spectate_btn.pressed.connect(func(): spectate_requested.emit())


## data keys (all optional — missing ones fall back to placeholder text so this
## never crashes when called with a partial dict during testing):
##   "killer_name": String, "damage": float, "layer_name": String, "kills": int
func show_death(data: Dictionary) -> void:
	visible = true
	var killer_name: String = data.get("killer_name", "Unknown")
	var damage: float = data.get("damage", 0.0)
	var layer_name: String = data.get("layer_name", "Unknown")
	var kills: int = data.get("kills", 0)

	_killer_label.text = "Killed by %s" % killer_name
	_damage_label.text = "Killing blow: %d dmg" % roundi(damage)
	_layer_label.text = "Layer: %s" % layer_name
	_kills_label.text = "Kills: %d" % kills


func _style_panel() -> void:
	var s := UIStyle.modal_panel_style()
	s.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", s)


func _style_labels() -> void:
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.90, 0.20, 0.16))
	_title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.9))
	_title_label.add_theme_constant_override("outline_size", 4)

	_killer_label.add_theme_font_size_override("font_size", 14)
	_killer_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.24))

	for lbl in [_damage_label, _layer_label, _kills_label]:
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
