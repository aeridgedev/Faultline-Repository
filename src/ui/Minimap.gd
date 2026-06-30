## Faultline — minimap overlay in the bottom-right HUD corner.
## Draws: layer-colored background bands, the descending storm front (red line),
## and the local player's world position (white dot).
## Entirely canvas-drawn; no child nodes required.
class_name Minimap
extends Control

const _LAYER_COLORS := {
	Constants.Layer.CRUST:       Color(0.28, 0.20, 0.12),   # warm earth
	Constants.Layer.MANTLE:      Color(0.16, 0.12, 0.15),   # dark purple-gray
	Constants.Layer.OUTER_CORE:  Color(0.22, 0.08, 0.06),   # deep red heat
	Constants.Layer.INNER_CORE:  Color(0.38, 0.10, 0.04),   # molten
	Constants.Layer.CORE_HOLLOW: Color(0.04, 0.03, 0.06),   # void
}

const _COLOR_BORDER        := Color(0.30, 0.33, 0.40, 0.90)
const _COLOR_BG            := Color(0.05, 0.05, 0.08, 0.88)
const _COLOR_STORM         := Color(0.95, 0.15, 0.10, 0.95)
const _COLOR_PLAYER        := Color(1.00, 1.00, 1.00, 1.00)
const _COLOR_LAYER_DIVIDER := Color(0.00, 0.00, 0.00, 0.35)

var _player: PlayerController = null
var _storm: StormSystem = null
var _layer_manager: LayerManager = null

var _world_w_px: float = 0.0
var _world_h_px: float = 0.0


func init(player: PlayerController, storm: StormSystem, layer_manager: LayerManager) -> void:
	_player = player
	_storm = storm
	_layer_manager = layer_manager
	_cache_world_dims()


func _cache_world_dims() -> void:
	if _layer_manager == null:
		return
	var ww = _layer_manager.world_width_px()
	var wh = _layer_manager.world_height_px()
	_world_w_px = float(ww) if ww != null else 0.0
	_world_h_px = float(wh) if wh != null else 0.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var mw := size.x
	var mh := size.y

	# Dark background
	draw_rect(Rect2(Vector2.ZERO, size), _COLOR_BG)

	# Layer-colored bands
	if _layer_manager != null and _world_h_px > 0.0:
		for layer: int in Constants.Layer.values():
			var top_var = _layer_manager.get_layer_top_y(layer)
			var bot_var = _layer_manager.get_layer_bottom_y(layer)
			if top_var == null or bot_var == null:
				continue
			var py := (float(top_var) / _world_h_px) * mh
			var ph := ((float(bot_var) - float(top_var)) / _world_h_px) * mh
			ph = maxf(ph, 1.0)
			var col: Color = _LAYER_COLORS.get(layer, Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(0.0, py, mw, ph), col)
			# Thin divider between layers so boundaries are readable at any zoom
			if py > 0.0:
				draw_line(Vector2(0.0, py), Vector2(mw, py), _COLOR_LAYER_DIVIDER, 1.0)

	# Storm front — horizontal red line; skip when storm hasn't entered yet
	if _storm != null and _world_h_px > 0.0:
		var front_y := _storm.get_storm_front_y()
		if front_y > -500.0:
			var sy := clampf((front_y / _world_h_px) * mh, 0.0, mh)
			draw_line(Vector2(0.0, sy), Vector2(mw, sy), _COLOR_STORM, 2.0)

	# Player position — white dot
	if _player != null and _world_h_px > 0.0 and _world_w_px > 0.0:
		var dot_x := clampf((_player.global_position.x / _world_w_px) * mw, 2.0, mw - 2.0)
		var dot_y := clampf((_player.global_position.y / _world_h_px) * mh, 2.0, mh - 2.0)
		draw_circle(Vector2(dot_x, dot_y), 2.5, _COLOR_PLAYER)

	# Outer border drawn last so it's always crisp on top
	draw_rect(Rect2(Vector2.ZERO, size), _COLOR_BORDER, false, 1.0)
