## Faultline — Medkit: slow channel that heals a larger amount over use_time.
## Heal is applied in ticks during use rather than at completion.
class_name Medkit
extends ConsumableBase

var _last_tick: float = 0.0
var _tick_interval := 0.5


func _init() -> void:
	use_time = GameManager.data.get("consumables", {}).get("medkit_use_time", null)


func tick_use(delta: float, stats: PlayerStats) -> void:
	# Heal incrementally while channeling.
	_last_tick += delta
	if _last_tick >= _tick_interval:
		_last_tick = 0.0
		var total: Variant = GameManager.data.get("consumables", {}).get("medkit_heal_total", null)
		if total != null:
			var required := float(use_time) if use_time != null else 1.0
			stats.heal(float(total) * (_tick_interval / required))
	super.tick_use(delta, stats)


func _on_use_complete(_stats: PlayerStats) -> void:
	_last_tick = 0.0
