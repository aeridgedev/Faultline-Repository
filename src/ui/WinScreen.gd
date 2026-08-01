## Faultline — full-screen match-end leaderboard overlay.
## The integration layer (HUD/Main) listens for GameManager.match_won, fetches
## GameManager.get_leaderboard(), and calls show_results() with that data — this
## file never talks to GameManager directly. PlayAgain/Quit buttons here only
## ever emit their own signal; the caller is the one that actually calls
## GameManager.restart_match() / get_tree().quit().
class_name WinScreen
extends Control

signal play_again_requested
## Emitted by the HOME button. Same split as every other button here: this file
## only announces the intent — HUD is what calls GameManager.return_to_home().
signal home_requested
signal quit_requested

@onready var _panel: PanelContainer = $CenterContainer/Panel
@onready var _title_label: Label = $CenterContainer/Panel/VBoxContainer/TitleLabel
@onready var _rows_container: VBoxContainer = $CenterContainer/Panel/VBoxContainer/ScrollContainer/RowsContainer
@onready var _button_row: HBoxContainer = $CenterContainer/Panel/VBoxContainer/ButtonRow
@onready var _play_again_btn: Button = $CenterContainer/Panel/VBoxContainer/ButtonRow/PlayAgainButton
@onready var _home_btn: Button = $CenterContainer/Panel/VBoxContainer/ButtonRow/HomeButton
@onready var _quit_btn: Button = $CenterContainer/Panel/VBoxContainer/ButtonRow/QuitButton

# The game's existing "top tier" gold (Constants.TIER_COLORS[LEGENDARY]) as the
# winner-row accent, now sourced from UIStyle so all four menu screens share one
# definition of it rather than four copies of the same literal.
const _COLOR_WINNER := UIStyle.ACCENT_GOLD
const _COLOR_ROW_BG := Color(0.10, 0.12, 0.17, 0.92)
const _COLOR_ROW_BORDER := Color(0.55, 0.58, 0.65, 0.60)

# Every row of a given kind (winner / non-winner) uses identical styling, so
# build each StyleBoxFlat once and share the instance across every row rather
# than allocating a fresh one per leaderboard entry.
var _row_style_winner: StyleBoxFlat
var _row_style_normal: StyleBoxFlat


func _ready() -> void:
	visible = false
	_style_static()
	# Play Again hides the win screen immediately, THEN asks the caller to restart
	# (spec: "Play Again calls restart_match() and hides the win screen"). Hiding
	# here makes the hide independent of the caller's restart path (which reloads
	# the scene) so the overlay never lingers over the fresh match for a frame.
	_play_again_btn.pressed.connect(_on_play_again_pressed)
	# HOME hides the screen for the same reason Play Again does: the scene change
	# behind it is deferred to end-of-frame, so the overlay would otherwise linger
	# over the home screen's first frame.
	_home_btn.pressed.connect(_on_home_pressed)
	_quit_btn.pressed.connect(func(): quit_requested.emit())


func _on_play_again_pressed() -> void:
	visible = false
	play_again_requested.emit()


func _on_home_pressed() -> void:
	visible = false
	home_requested.emit()


## leaderboard: Array of Dictionary shaped {id, name, node, kills,
## deepest_layer, alive, is_dummy}, already sorted by kills descending — do
## NOT re-sort it here. The entry matching winner_id is pulled out and pinned
## at rank 1; everyone else follows in the given (kills-descending) order.
func show_results(leaderboard: Array, winner_id: int) -> void:
	UIStyle.clear_children(_rows_container)

	var winner: Dictionary = {}
	var rest: Array = []
	for entry: Dictionary in leaderboard:
		if entry.get("id", -1) == winner_id:
			winner = entry
		else:
			rest.append(entry)

	# Rank numbering starts after however many rows the winner actually occupied.
	# Previously it hardcoded `i + 2`, so if winner_id was not present in the
	# leaderboard (a freed/unregistered participant) the list silently started at
	# #2 with no #1 at all. Now the ranks stay contiguous from 1 either way.
	var next_rank := 1
	if not winner.is_empty():
		_rows_container.add_child(_build_row(next_rank, winner, true))
		next_rank += 1
	for i in rest.size():
		_rows_container.add_child(_build_row(next_rank + i, rest[i], false))

	visible = true


func _build_row(rank: int, entry: Dictionary, is_winner: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style(is_winner))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var rank_lbl := Label.new()
	rank_lbl.text = "#%d" % rank
	rank_lbl.custom_minimum_size = Vector2(32, 0)

	var name_lbl := Label.new()
	name_lbl.text = str(entry.get("name", "?"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true

	var kills_lbl := Label.new()
	kills_lbl.text = "%d kills" % int(entry.get("kills", 0))
	kills_lbl.custom_minimum_size = Vector2(72, 0)

	var layer_lbl := Label.new()
	var layer_name: String = Constants.LAYER_NAMES.get(entry.get("deepest_layer", -1), "?")
	layer_lbl.text = layer_name
	layer_lbl.custom_minimum_size = Vector2(100, 0)
	layer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var text_color := Color(1.0, 0.94, 0.78) if is_winner else Color(0.85, 0.88, 0.92)
	for lbl in [rank_lbl, name_lbl, kills_lbl, layer_lbl]:
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", text_color)

	row.add_child(rank_lbl)
	row.add_child(name_lbl)
	row.add_child(kills_lbl)
	row.add_child(layer_lbl)

	if is_winner:
		var winner_tag := Label.new()
		winner_tag.text = "WINNER"
		winner_tag.add_theme_font_size_override("font_size", 13)
		winner_tag.add_theme_color_override("font_color", _COLOR_WINNER)
		row.add_child(winner_tag)
		row.move_child(winner_tag, 1)

	panel.add_child(row)
	return panel


func _row_style(is_winner: bool) -> StyleBoxFlat:
	if is_winner:
		if _row_style_winner == null:
			_row_style_winner = StyleBoxFlat.new()
			_row_style_winner.set_corner_radius_all(4)
			_row_style_winner.set_content_margin_all(6)
			_row_style_winner.bg_color = _COLOR_WINNER.darkened(0.78)
			_row_style_winner.set_border_width_all(3)
			_row_style_winner.border_color = _COLOR_WINNER
		return _row_style_winner
	if _row_style_normal == null:
		_row_style_normal = StyleBoxFlat.new()
		_row_style_normal.set_corner_radius_all(4)
		_row_style_normal.set_content_margin_all(6)
		_row_style_normal.bg_color = _COLOR_ROW_BG
		_row_style_normal.set_border_width_all(1)
		_row_style_normal.border_color = _COLOR_ROW_BORDER
	return _row_style_normal


func _style_static() -> void:
	var panel_style := UIStyle.modal_panel_style(0.95, 0.85)
	panel_style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", panel_style)

	UIStyle.style_title(_title_label, 22)

	_panel.get_node("VBoxContainer").add_theme_constant_override("separation", 12)
	_rows_container.add_theme_constant_override("separation", 5)
	_button_row.add_theme_constant_override("separation", 14)

	# Make the match-end actions unmistakably visible below the leaderboard. They
	# already sit in a ButtonRow stacked under the ScrollContainer inside the VBox
	# (so they can never overlap the leaderboard rows), but Godot's default button
	# theme is easy to miss on the dark modal. Play Again is the primary action and
	# takes the winner gold; HOME and QUIT are neutral.
	#
	# 130 wide (was 150) so three buttons + separations fit inside the panel's
	# authored 460px width instead of forcing it wider.
	UIStyle.style_button(_play_again_btn, _COLOR_WINNER, 130.0)
	UIStyle.style_button(_home_btn, UIStyle.ACCENT_NEUTRAL, 130.0)
	UIStyle.style_button(_quit_btn, UIStyle.ACCENT_NEUTRAL, 130.0)
