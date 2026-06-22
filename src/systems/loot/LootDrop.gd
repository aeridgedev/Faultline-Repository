## Faultline — a loot item lying on the ground after spawning from a chest.
## Holds the roll result from LootTable and emits pickup_requested when
## a player enters range. AutoCollect is the consumer.
class_name LootDrop
extends Node2D

signal pickup_requested(drop: LootDrop)

## The roll data produced by LootTable.roll(): {type, item_class, tier}
var item_data: Dictionary = {}

## Set by ChestSpawner after instantiation.
var source_layer: Constants.Layer = Constants.Layer.CRUST


func _ready() -> void:
	# TBD(art): add Sprite2D child with tier-colored icon once assets exist.
	pass


## Called by AutoCollect when within pickup radius.
func request_pickup() -> void:
	pickup_requested.emit(self)


## Remove this drop from the world after it has been collected.
func consume() -> void:
	queue_free()
