## Faultline — home / title screen. This is the project's BOOT scene
## (`run/main_scene` in project.godot): the game no longer loads straight into a
## match. `src/core/Main.tscn` is entered only when the player presses PLAY,
## which calls GameManager.start_new_match() — the same scene load that used to
## happen at launch, so no match-init logic is duplicated here.
##
## Stats-forward, like the death screen: if a match has ended this run, the
## previous result (placement / kills / layer reached / survived) is shown.
## The data is GameManager.last_match_summary — in memory only, never saved to
## disk, so a fresh launch always shows the "no matches played yet" state.
##
## STYLED 2026-08-01 (menu visual pass). Everything visual comes from UIStyle —
## the modal panel recipe, the small-panel recipe for the last-match block, the
## MATCH SUMMARY key/value stat rows, and the button recipe — so this screen is
## the same visual family as the death and win screens rather than a lookalike.
## No logic changed in that pass: show_summary()'s contract, the GameManager read
## and the button wiring are exactly as they were.
##
## Deviation from the "menu screens read data through HUD" rule, and why: that
## rule exists because DeathScreen/WinScreen live *inside* HUD, which is their
## integration layer. The home screen runs outside any match — there is no HUD
## (or anything else) above it — so it does its own single GameManager read in
## _ready() and hands the plain dict to show_summary(). Everything that renders
## below that read is GameManager-free, and show_summary() is public, so a
## future host (the planned esc menu) can push values in the same way HUD does.
class_name HomeScreen
extends Control

const _PANEL_MIN_WIDTH := 320.0
const _BUTTON_WIDTH := 220.0

@onready var _background: ColorRect = $Background
@onready var _panel: PanelContainer = $CenterContainer/Panel
@onready var _title_label: Label = $CenterContainer/Panel/VBoxContainer/TitleLabel
@onready var _subtitle_label: Label = $CenterContainer/Panel/VBoxContainer/SubtitleLabel
@onready var _stats_panel: PanelContainer = $CenterContainer/Panel/VBoxContainer/StatsPanel
@onready var _stats_box: VBoxContainer = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox
@onready var _last_match_header: Label = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox/LastMatchHeader
@onready var _empty_label: Label = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox/EmptyLabel
@onready var _stats_grid: GridContainer = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox/StatsGrid
@onready var _placement_note: Label = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox/PlacementNote
@onready var _play_btn: Button = $CenterContainer/Panel/VBoxContainer/PlayButton
@onready var _settings_btn: Button = $CenterContainer/Panel/VBoxContainer/SettingsButton
@onready var _quit_btn: Button = $CenterContainer/Panel/VBoxContainer/QuitButton


func _ready() -> void:
	_style_screen()
	_play_btn.pressed.connect(func(): GameManager.start_new_match())
	# Same quit pattern as WinScreen's Quit button (which HUD wires to the same call).
	_quit_btn.pressed.connect(func(): get_tree().quit())
	# Placeholder only — a settings pass is out of scope, so the button is present
	# but inert rather than wired to a screen that does not exist yet.
	_settings_btn.disabled = true

	show_summary(GameManager.last_match_summary)


## Renders the previous match's result. `summary` uses the same keys HUD builds
## for DeathScreen (kills / layer_name / placement / total_players /
## survival_seconds / outcome); every key is optional and falls back, so a
## partial dict renders rather than crashes. An EMPTY dict is the first-launch
## "no matches played yet" state.
func show_summary(summary: Dictionary) -> void:
	UIStyle.clear_children(_stats_grid)

	# The empty state and the populated state are two different shapes, so they
	# swap whole blocks rather than sharing a row list: an empty dict has no
	# key/value pairs and no placement caveat to qualify.
	var has_summary := not summary.is_empty()
	_empty_label.visible = not has_summary
	_stats_grid.visible = has_summary
	_placement_note.visible = has_summary

	if not has_summary:
		_last_match_header.text = "LAST MATCH"
		return

	_last_match_header.text = "LAST MATCH — %s" % _outcome_text(summary)
	# Placement first and as the hero row, mirroring the death screen exactly —
	# same order, same gold, same key/value columns.
	UIStyle.add_stat_row(_stats_grid, "PLACEMENT", _placement_text(summary), true)
	UIStyle.add_stat_row(_stats_grid, "KILLS", "%d" % int(summary.get("kills", 0)), false)
	UIStyle.add_stat_row(_stats_grid, "LAYER REACHED", str(summary.get("layer_name", "Unknown")), false)
	UIStyle.add_stat_row(_stats_grid, "SURVIVED",
		_format_time(float(summary.get("survival_seconds", 0.0))), false)


# --- Styling (menu visual pass, 2026-08-01) ---

## Everything here is applied in code from UIStyle rather than authored in the
## .tscn, for the same reason the disabled SETTINGS button is set in code: one
## source of truth, and the four menu screens stay in step because they all read
## the same helpers.
func _style_screen() -> void:
	# Unlike the in-match overlays, the home screen has no game world behind it —
	# it needs an opaque fill of its own rather than a translucent backdrop.
	_background.color = UIStyle.SCREEN_BG

	var panel_style := UIStyle.modal_panel_style()
	panel_style.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", panel_style)
	# A floor on the width so the panel does not visibly resize between the
	# narrow first-launch empty state and a populated summary.
	_panel.custom_minimum_size = Vector2(_PANEL_MIN_WIDTH, 0)

	UIStyle.style_title(_title_label, 34)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", UIStyle.TEXT_FAINT)

	# The last-match block reuses the in-match HUD panel recipe, the same one the
	# death screen's MATCH SUMMARY uses.
	var stats_style := UIStyle.small_panel_style()
	stats_style.set_content_margin_all(10)
	_stats_panel.add_theme_stylebox_override("panel", stats_style)
	_stats_box.add_theme_constant_override("separation", 6)
	_stats_grid.add_theme_constant_override("h_separation", 12)
	_stats_grid.add_theme_constant_override("v_separation", 5)

	_last_match_header.add_theme_font_size_override("font_size", 10)
	_last_match_header.add_theme_color_override("font_color", UIStyle.ACCENT_GOLD)

	_empty_label.add_theme_font_size_override("font_size", 12)
	_empty_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)

	# Same caveat the death screen carries, in the same faint footnote voice:
	# placement is a rank at the moment the player's match ended, not a recorded
	# finishing order.
	_placement_note.text = "placement is approximate — your rank when your match ended"
	_placement_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_note.add_theme_font_size_override("font_size", 9)
	_placement_note.add_theme_color_override("font_color", UIStyle.TEXT_FAINT)

	# PLAY is the screen's primary action and the only gold control here.
	UIStyle.style_button(_play_btn, UIStyle.ACCENT_GOLD, _BUTTON_WIDTH)
	UIStyle.style_button(_settings_btn, UIStyle.ACCENT_NEUTRAL, _BUTTON_WIDTH)
	UIStyle.style_button(_quit_btn, UIStyle.ACCENT_NEUTRAL, _BUTTON_WIDTH)


func _outcome_text(summary: Dictionary) -> String:
	return "VICTORY" if str(summary.get("outcome", "")) == "won" else "DEFEAT"


## "#3 / 33" when the roster size is known, "#3" otherwise, "—" if unset.
func _placement_text(summary: Dictionary) -> String:
	var placement := int(summary.get("placement", 0))
	if placement <= 0:
		return "—"
	var total := int(summary.get("total_players", 0))
	if total > 0:
		return "#%d / %d" % [placement, total]
	return "#%d" % placement


## MM:SS, matching DeathScreen/StormTimer so every match clock reads the same way.
func _format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	# Floor division to whole minutes for MM:SS display is intended.
	@warning_ignore("integer_division")
	var minutes := total / 60
	return "%d:%02d" % [minutes, total % 60]
