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
	var base: Color = Constants.TIER_COLORS.get(tier, Color(0.7, 0.7, 0.7))
	# Diamond gem shape (12×12, rotated square). Tier-colored with inner shading.
	const S := 12; const MID := int(S / 2) - 1
	var K  := Color(0.04, 0.05, 0.08)
	var lit := base.lightened(0.28)
	var shd := base.darkened(0.32)
	var wh  := Color(0.94, 0.98, 1.00)     # specular
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in S:
		for x in S:
			# Diamond mask: |x - MID| + |y - MID| <= MID
			var dx: int = abs(x - MID); var dy: int = abs(y - MID)
			if dx + dy > MID:
				continue
			var on_edge: bool = (dx + dy == MID)
			if on_edge:
				img.set_pixel(x, y, K)
			elif dx + dy <= 1:
				img.set_pixel(x, y, lit)    # bright inner center
			elif y < MID:
				img.set_pixel(x, y, lit if x <= MID else base)
			else:
				img.set_pixel(x, y, shd)
	# Specular highlight — top-left corner of gem
	img.set_pixel(MID, 1, wh)
	img.set_pixel(MID - 1, 2, lit)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	add_child(sprite)


## Called by AutoCollect when within pickup radius.
func request_pickup() -> void:
	pickup_requested.emit(self)


## Remove this drop from the world after it has been collected.
func consume() -> void:
	queue_free()
