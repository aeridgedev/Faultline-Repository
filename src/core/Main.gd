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
	_spawn_test_dummy(player.global_position)

	var hud: HUD = HUDScene.instantiate() as HUD
	add_child(hud)
	hud.init(player, storm)

	# After the HUD is listening, populate the hotbar so its slot labels update.
	player.setup_hotbar()

	GameManager.start_match()


func _init_hazards(stats: PlayerStats) -> StormSystem:
	var depth := _world.get_node("DepthHazard") as DepthHazard
	depth.init(stats)

	var pressure := _world.get_node("PressureSystem") as PressureSystem
	pressure.init(stats)

	var storm := _world.get_node("StormSystem") as StormSystem
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
	gradient.offsets = PackedFloat32Array([0.0, 0.04, 0.08, 0.14, 0.30, 0.46, 0.58, 0.72, 0.86, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.22, 0.42, 0.68),  # upper atmosphere — dusky sky
		Color(0.36, 0.50, 0.62),  # lower atmosphere — haze
		Color(0.24, 0.19, 0.14),  # crust entry
		Color(0.30, 0.23, 0.15),  # upper crust — warm earth
		Color(0.18, 0.14, 0.11),  # deep crust — compressed earth
		Color(0.14, 0.11, 0.13),  # mantle — dark purple-gray
		Color(0.20, 0.09, 0.09),  # outer core — heat rising
		Color(0.36, 0.12, 0.05),  # inner core — molten red
		Color(0.48, 0.16, 0.04),  # inner core deep — intense
		Color(0.04, 0.03, 0.05),  # core hollow — void black
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


# DEV-ONLY: drop a melee test target a few tiles to the player's right so combat
# can be verified offline. Remove once networked players exist.
func _spawn_test_dummy(near: Vector2) -> void:
	var dummy := TestDummy.new()
	dummy.name = "TestDummy"
	add_child(dummy)
	dummy.global_position = near + Vector2(Constants.TILE_SIZE * 2, -Constants.TILE_SIZE)


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
