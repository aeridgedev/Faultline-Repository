extends Node2D
## Faultline — bootstrap: generates world, spawns local player, starts match.

const PlayerScene: PackedScene = preload("res://src/player/Player.tscn")
const HUDScene: PackedScene = preload("res://src/ui/HUD.tscn")

@onready var _world: Node2D = $World


func _ready() -> void:
	var layer_manager: LayerManager = _world.get_node("LayerManager")
	var terrain_manager: TerrainManager = _world.get_node("TerrainManager")

	var generator := WorldGenerator.new()
	generator.generate(terrain_manager, layer_manager, randi())

	_build_background(layer_manager)

	var player: PlayerController = PlayerScene.instantiate() as PlayerController
	add_child(player)
	player.global_position = _spawn_position(layer_manager)
	player.init_world(terrain_manager)
	player.equip_starter_drill()
	player.equip_starter_weapon()
	player.get_node("DescentTracker").init(layer_manager)

	var storm := _init_hazards(player.stats)
	ChestSpawner.spawn(terrain_manager, layer_manager, _world)

	var hud: HUD = HUDScene.instantiate() as HUD
	add_child(hud)
	hud.init(player, storm)

	GameManager.start_match()


func _init_hazards(stats: PlayerStats) -> StormSystem:
	var depth := DepthHazard.new()
	depth.name = "DepthHazard"
	add_child(depth)
	depth.init(stats)

	var pressure := PressureSystem.new()
	pressure.name = "PressureSystem"
	add_child(pressure)
	pressure.init(stats)

	var storm := StormSystem.new()
	storm.name = "StormSystem"
	add_child(storm)
	storm.init(stats)
	storm.start()
	return storm


# Builds a vertical gradient backdrop behind the terrain: sky at the atmosphere,
# darkening through warm crust tones into the molten core. Dev placeholder until
# real parallax art exists, but it kills the flat gray void.
func _build_background(layer_manager: LayerManager) -> void:
	var world_h: Variant = layer_manager.world_height_px()
	if world_h == null:
		return  # layer heights TBD — skip backdrop rather than guess dimensions
	var atmosphere_px := Constants.TILE_SIZE * 8
	var width_px := _world_width_px()
	var total_h := float(world_h) + atmosphere_px

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.05, 0.10, 0.32, 0.55, 0.74, 0.88, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.30, 0.52, 0.74),  # atmosphere — sky blue
		Color(0.52, 0.62, 0.70),  # hazy horizon
		Color(0.28, 0.22, 0.17),  # crust top
		Color(0.20, 0.15, 0.12),  # deep crust
		Color(0.16, 0.12, 0.13),  # mantle
		Color(0.22, 0.10, 0.09),  # outer core — warming
		Color(0.40, 0.13, 0.06),  # inner core — molten
		Color(0.05, 0.03, 0.04),  # core hollow — dark
	])

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)  # vertical
	tex.width = 8
	tex.height = 256

	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = tex
	bg.centered = false
	bg.z_index = -100
	bg.z_as_relative = false
	bg.position = Vector2(-64.0, float(-atmosphere_px))
	bg.scale = Vector2((width_px + 128.0) / tex.width, total_h / tex.height)
	add_child(bg)


func _spawn_position(layer_manager: LayerManager) -> Vector2:
	# Spawn in the atmosphere above the Crust surface so the player drops onto the
	# terrain (parachute landing) instead of starting embedded inside solid soil.
	# TBD: scatter spawn x across the Crust top once 100-player drops are wired.
	var top_y: Variant = layer_manager.get_layer_top_y(Constants.Layer.CRUST)
	var surface_y: float = float(top_y) if top_y != null else 0.0
	var spawn_y: float = surface_y - Constants.TILE_SIZE * 5.0  # 5 tiles of air above
	var world_center_x: float = _world_center_x()
	return Vector2(world_center_x, spawn_y)


func _world_width_px() -> float:
	var width_tiles: int = GameManager.data.get("world_width_tiles", 0) if GameManager.data else 0
	if width_tiles <= 0:
		return 1280.0  # TBD: world_width_tiles not set; fall back to viewport width
	return float(width_tiles) * Constants.TILE_SIZE


func _world_center_x() -> float:
	return _world_width_px() / 2.0
