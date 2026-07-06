## Faultline — BasicScanner: reveals all players within range for 8s (LOCKED).
## Scanned players are NOT notified (LOCKED). Range TBD (world_config.json
## basic_scanner_range). All logic lives in ScannerBase.
class_name BasicScanner
extends ScannerBase


func _range_key() -> String:
	return "basic_scanner_range"
