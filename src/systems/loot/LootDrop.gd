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
	# TBD(art): replace with a real tier-colored chest/icon once assets exist.
	# Dev placeholder: a tier-colored gem with a dark outline so loot is visible
	# on the terrain and you can watch AutoCollect pick it up.
	_build_dev_marker()


func _build_dev_marker() -> void:
	var tier: int = item_data.get("tier", Constants.Tier.COMMON)
	var color: Color = Constants.TIER_COLORS.get(tier, Color(0.7, 0.7, 0.7))
	var size := 10
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var outline := Color(0.04, 0.05, 0.08)
	for y in range(size):
		for x in range(size):
			var edge: bool = x == 0 or y == 0 or x == size - 1 or y == size - 1
			img.set_pixel(x, y, outline if edge else color)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	add_child(sprite)


## Called by AutoCollect when within pickup radius.
func request_pickup() -> void:
	pickup_requested.emit(self)


## Remove this drop from the world after it has been collected.
func consume() -> void:
	queue_free()
