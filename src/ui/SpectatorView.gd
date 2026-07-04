## Faultline — spectator overlay shown after the player clicks SPECTATE.
## Follows a living roster participant (real player or TestDummy — see
## GameManager's roster API) by reparenting the handed-off Camera2D onto its
## node. Left/Right arrows cycle targets; the spectated target's death
## auto-advances to another living target.
class_name SpectatorView
extends Control

@onready var _spectating_label: Label = $TopBar/VBoxContainer/Label
@onready var _name_label: Label = $TopBar/VBoxContainer/NameLabel
@onready var _hp_bar: ProgressBar = $TopBar/VBoxContainer/HPBar

var _camera: Camera2D = null
var _target_id: int = -1
var _target_stats: PlayerStats = null


func _ready() -> void:
	visible = false
	_style_top_bar()


func start_spectating(camera: Camera2D, preferred_target_id: int) -> void:
	visible = true
	_camera = camera
	var living := GameManager.get_living_player_ids()
	if living.is_empty():
		_disconnect_current()
		_target_id = -1
		_show_empty_state()
		return
	var target_id: int = preferred_target_id if living.has(preferred_target_id) else living[0]
	_switch_to(target_id)


func stop_spectating() -> void:
	visible = false
	_disconnect_current()
	_target_id = -1
	_camera = null


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_left"):
		_cycle(-1)
	elif event.is_action_pressed("ui_right"):
		_cycle(1)


func _cycle(delta: int) -> void:
	var living := GameManager.get_living_player_ids()
	if living.is_empty():
		return
	var idx: int = living.find(_target_id)
	if idx == -1:
		_switch_to(living[0])
		return
	_switch_to(living[posmod(idx + delta, living.size())])


func _switch_to(id: int) -> void:
	_disconnect_current()
	_target_id = id
	var node := GameManager.get_player_node(id)
	if node == null or not is_instance_valid(node) or not node.has_method("get_stats"):
		_show_empty_state()
		return
	var stats: PlayerStats = node.get_stats()
	if stats == null:
		_show_empty_state()
		return
	_reparent_camera(node)
	_target_stats = stats
	_target_stats.health_changed.connect(_on_target_health_changed)
	_target_stats.player_died.connect(_on_target_died)
	_refresh_display(id, _target_stats.current_health, _target_stats.max_health)


# Camera2D is a Node2D, so once reparented its transform follows the new
# parent automatically — no per-frame position-copy code needed.
func _reparent_camera(target_node: Node) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var old_parent := _camera.get_parent()
	if old_parent == target_node:
		return
	if old_parent != null:
		old_parent.remove_child(_camera)
	target_node.add_child(_camera)
	_camera.position = Vector2.ZERO
	_camera.reset_smoothing()
	_camera.current = true


func _disconnect_current() -> void:
	if _target_stats != null and is_instance_valid(_target_stats):
		if _target_stats.health_changed.is_connected(_on_target_health_changed):
			_target_stats.health_changed.disconnect(_on_target_health_changed)
		if _target_stats.player_died.is_connected(_on_target_died):
			_target_stats.player_died.disconnect(_on_target_died)
	_target_stats = null


func _on_target_health_changed(new_hp: float, max_hp: float) -> void:
	_set_hp_bar(new_hp, max_hp)


# The dead target may still briefly appear in get_living_player_ids() depending
# on signal ordering, so explicitly drop it rather than trusting the list to
# already exclude it.
func _on_target_died() -> void:
	var living := GameManager.get_living_player_ids()
	living.erase(_target_id)
	if living.is_empty():
		_disconnect_current()
		return
	_switch_to(living[0])


func _refresh_display(id: int, hp: float, max_hp: float) -> void:
	var info := GameManager.get_player(id)
	_name_label.text = info.get("name", "Unknown")
	_set_hp_bar(hp, max_hp)


func _set_hp_bar(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp if max_hp > 0.0 else 1.0
	_hp_bar.value = hp


func _show_empty_state() -> void:
	_name_label.text = "No one left to spectate"
	_hp_bar.max_value = 1.0
	_hp_bar.value = 0.0


func _style_top_bar() -> void:
	$TopBar.add_theme_stylebox_override("panel", UIStyle.small_panel_style())

	_spectating_label.add_theme_font_size_override("font_size", 9)
	_spectating_label.add_theme_color_override("font_color", Color(0.60, 0.66, 0.76))

	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96))

	_hp_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.22, 0.82, 0.32)
	fill.set_corner_radius_all(2)
	_hp_bar.add_theme_stylebox_override("fill", fill)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.06, 0.90)
	bg.set_corner_radius_all(2)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.20, 0.20, 0.22, 0.60)
	_hp_bar.add_theme_stylebox_override("background", bg)
