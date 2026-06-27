## Faultline — world-space overlay for the Resonance drill class.
## Draws a pulsing tinted rectangle on every SOIL and ROCK tile within
## SCAN_RADIUS cells of the player. Visible only while a Resonance drill
## is equipped and not broken; toggled by PlayerController.
##
## Node setup: top_level = true so it doesn't inherit the player's transform.
## global_position stays at (0,0), making _draw() local-space == world-space.
class_name ResonanceOverlay
extends Node2D

const SCAN_RADIUS   := 9     # tile radius around player
const PULSE_SPEED   := 1.8   # radians per second for the alpha oscillation
const SCAN_INTERVAL := 0.10  # seconds between full tile scans (~10 refreshes/sec)

const COLOR_DIM  := Color(0.35, 0.95, 0.50, 0.15)
const COLOR_PEAK := Color(0.35, 0.95, 0.50, 0.40)

var _terrain_manager: TerrainManager = null
var _player: Node2D = null
var _weak_cells: Array[Vector2i] = []
var _pulse_time: float = 0.0
var _scan_cooldown: float = 0.0


func setup(player: Node2D, terrain: TerrainManager) -> void:
	_player = player
	_terrain_manager = terrain
	global_position = Vector2.ZERO


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_time += delta * PULSE_SPEED
	_scan_cooldown -= delta
	if _scan_cooldown <= 0.0:
		_scan_weak_tiles()
		_scan_cooldown = SCAN_INTERVAL
	queue_redraw()


func _scan_weak_tiles() -> void:
	_weak_cells.clear()
	if _player == null or _terrain_manager == null:
		return
	var center := _terrain_manager.world_to_cell(_player.global_position)
	for dy in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for dx in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			var cell := center + Vector2i(dx, dy)
			var type: Variant = _terrain_manager.get_tile_type(cell)
			if type != null and TerrainTypes.is_structurally_weak(type):
				_weak_cells.append(cell)


func _draw() -> void:
	if _terrain_manager == null or _weak_cells.is_empty():
		return
	var t := (sin(_pulse_time) + 1.0) * 0.5
	var color := COLOR_DIM.lerp(COLOR_PEAK, t)
	var sz    := float(Constants.TILE_SIZE)
	for cell in _weak_cells:
		var wp := _terrain_manager.cell_to_world(cell)
		draw_rect(Rect2(wp, Vector2(sz, sz)), color, true)
