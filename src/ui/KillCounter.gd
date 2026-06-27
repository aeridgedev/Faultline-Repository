## Faultline — tracks and displays the local player's kill count during a match.
## Call init(local_stats) from HUD.init() once the scene tree is populated.
class_name KillCounter
extends PanelContainer

var kill_count: int = 0
var _label: Label = null
var _local_stats: PlayerStats = null


func _ready() -> void:
	_label = Label.new()
	_label.text = "Kills: 0"
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	add_child(_label)


func init(local_stats: PlayerStats) -> void:
	_local_stats = local_stats
	# Scan nodes already in the scene (TestDummy is spawned before HUD in Main.gd).
	for node in get_tree().root.find_children("*", "PlayerStats", true, false):
		if node != _local_stats:
			(node as PlayerStats).player_died.connect(_on_kill)
	# Watch for future additions (additional dummies, future networked players).
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is PlayerStats and node != _local_stats:
		(node as PlayerStats).player_died.connect(_on_kill)


func _on_kill() -> void:
	kill_count += 1
	_label.text = "Kills: %d" % kill_count
