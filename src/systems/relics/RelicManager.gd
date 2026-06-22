## Faultline — orchestrates all 4 relics for one player.
## Buff relics (Haste/Speed/Strength) are timed; Toughness is permanent.
## Relics are activated by calling activate_relic() from outside (inventory use event).
## Drop logic is handled by InventoryManager (same as any other item).
class_name RelicManager
extends Node

signal relic_activated(relic: Constants.Relic)
signal relic_expired(relic: Constants.Relic)

@onready var _stats: PlayerStats = $"../PlayerStats"

var _buffs: Dictionary = {}       # Constants.Relic -> BuffRelic
var _toughness: ToughnessRelic = ToughnessRelic.new()


func _ready() -> void:
	for relic_type in [Constants.Relic.HASTE, Constants.Relic.SPEED, Constants.Relic.STRENGTH]:
		var b := BuffRelic.new()
		b.relic_type = relic_type
		_buffs[relic_type] = b


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for relic_type in _buffs:
		var buff: BuffRelic = _buffs[relic_type]
		if buff.tick(now):
			relic_expired.emit(relic_type)


func activate_relic(relic_type: Constants.Relic) -> void:
	if relic_type == Constants.Relic.TOUGHNESS:
		_toughness.activate(_stats)
	else:
		var buff: BuffRelic = _buffs.get(relic_type)
		if buff != null:
			buff.activate(Time.get_ticks_msec() / 1000.0)
	relic_activated.emit(relic_type)


# --- Multiplier queries (used by PlayerController and WeaponBase at runtime) ---

func move_speed_mult() -> float:
	var s: BuffRelic = _buffs.get(Constants.Relic.SPEED)
	return s.move_speed_mult() if s != null else 1.0


func attack_speed_mult() -> float:
	var h: BuffRelic = _buffs.get(Constants.Relic.HASTE)
	return h.move_speed_mult() if h != null else 1.0  # reuses same mult accessor


func damage_mult() -> float:
	var st: BuffRelic = _buffs.get(Constants.Relic.STRENGTH)
	return st.damage_mult() if st != null else 1.0


func toughness_active() -> bool:
	return _toughness.is_active
