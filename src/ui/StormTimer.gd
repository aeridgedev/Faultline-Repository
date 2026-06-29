## Faultline — storm phase display: current region name and countdown to next advance.
## Call init(storm) from HUD after StormSystem is started.
## Updates both labels once per second via a tick accumulator.
class_name StormTimer
extends PanelContainer

@onready var _region_label: Label = $VBoxContainer/RegionLabel
@onready var _countdown_label: Label = $VBoxContainer/CountdownLabel

var _storm: StormSystem = null
var _tick_accum: float = 0.0


func init(storm: StormSystem) -> void:
	_storm = storm
	_tick_accum = 0.0
	storm.storm_advanced.connect(_on_storm_advanced)
	_refresh()


func _process(delta: float) -> void:
	if _storm == null:
		return
	_tick_accum += delta
	if _tick_accum >= 1.0:
		_tick_accum -= 1.0
		_refresh()


func _refresh() -> void:
	_region_label.text = "STORM  " + _storm.get_current_region().to_upper()
	_refresh_countdown()


func _refresh_countdown() -> void:
	var phase_end := _storm.get_phase_end_seconds()
	if phase_end < 0.0:
		_countdown_label.text = "FINAL"
		return
	var remaining := maxf(phase_end - _storm.get_elapsed(), 0.0)
	var remaining_secs := int(remaining)
	var minutes := remaining_secs / 60
	var seconds := remaining_secs % 60
	_countdown_label.text = "%d:%02d" % [minutes, seconds]


func _on_storm_advanced(_region_name: String) -> void:
	# Reset the tick accumulator so the display updates immediately on phase change
	# rather than waiting up to 1 second for the next scheduled tick.
	_tick_accum = 1.0
