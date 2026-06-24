## Faultline — storm phase display: current region name and countdown to next advance.
## Call init(storm) from HUD after StormSystem is started.
class_name StormTimer
extends PanelContainer

@onready var _region_label: Label = $VBoxContainer/RegionLabel
@onready var _countdown_label: Label = $VBoxContainer/CountdownLabel

var _storm: StormSystem = null


func init(storm: StormSystem) -> void:
	_storm = storm
	storm.storm_advanced.connect(_on_storm_advanced)
	_refresh()


func _process(_delta: float) -> void:
	if _storm == null:
		return
	_refresh_countdown()


func _refresh() -> void:
	_region_label.text = "STORM  " + _storm.get_current_region().to_upper()
	_refresh_countdown()


func _refresh_countdown() -> void:
	var phase_end := _storm.get_phase_end_seconds()
	if phase_end < 0.0:
		_countdown_label.text = "FINAL"
		return
	var remaining := maxf(phase_end - _storm.get_elapsed(), 0.0)
	_countdown_label.text = "%d:%02d" % [int(remaining) / 60, int(remaining) % 60]


func _on_storm_advanced(region_name: String) -> void:
	_region_label.text = "STORM  " + region_name.to_upper()
