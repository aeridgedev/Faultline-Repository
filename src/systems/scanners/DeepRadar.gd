## Faultline — DeepRadar: longer-range scanner; same 8s duration (LOCKED) as
## BasicScanner but with a larger detection radius. Range TBD
## (world_config.json deep_radar_range). All logic lives in ScannerBase.
class_name DeepRadar
extends ScannerBase


func _range_key() -> String:
	return "deep_radar_range"
