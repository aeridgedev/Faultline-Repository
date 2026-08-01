## Faultline — full-screen overlay shown when the local player dies.
## Shown by HUD on PlayerDeath.died. Emits spectate_requested when the player
## clicks SPECTATE, at which point HUD hands off to SpectatorView.
##
## Stats-forward: the screen leads with a MATCH SUMMARY block (placement, kills,
## layer reached, survival time) so the run reads as a result before the player
## moves on to spectating. The transition itself is unchanged — this file only
## renders; SPECTATE still just emits spectate_requested.
##
## This file NEVER talks to GameManager. HUD is the integration layer: it reads
## the roster / match clock and hands every value in through show_death(), the
## same split WinScreen already uses for the leaderboard.
class_name DeathScreen
extends Control

signal spectate_requested
## Emitted by the HOME button — the "I'm done with this match" exit, alongside
## SPECTATE's "watch the rest of it". Same split as spectate_requested: this file
## only announces the intent, HUD calls GameManager.return_to_home().
signal home_requested

# Gold accent — the same value as WinScreen's winner row and
# Constants.TIER_COLORS[LEGENDARY], so "your result" reads in one colour
# game-wide. Matches the gold used by the HUD's kill-progress panel. Sourced from
# UIStyle since the 2026-08-01 menu visual pass so all four menu screens share
# one definition of the palette.
const _COLOR_ACCENT := UIStyle.ACCENT_GOLD
const _COLOR_FOOTNOTE := UIStyle.TEXT_FAINT

# Fixed column widths keep the key/value columns aligned no matter how long a
# layer name or player name is, and give the stat block a stable width so the
# modal does not resize between deaths.
const _STAT_KEY_WIDTH := 148.0
const _STAT_VALUE_WIDTH := 132.0

@onready var _panel: PanelContainer = $CenterContainer/Panel
@onready var _title_label: Label = $CenterContainer/Panel/VBoxContainer/TitleLabel
@onready var _killer_label: Label = $CenterContainer/Panel/VBoxContainer/KillerLabel
@onready var _damage_label: Label = $CenterContainer/Panel/VBoxContainer/DamageLabel
@onready var _stats_panel: PanelContainer = $CenterContainer/Panel/VBoxContainer/StatsPanel
@onready var _stats_box: VBoxContainer = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox
@onready var _stats_header: Label = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox/StatsHeader
@onready var _stats_grid: GridContainer = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox/StatsGrid
@onready var _placement_note: Label = $CenterContainer/Panel/VBoxContainer/StatsPanel/StatsBox/PlacementNote
@onready var _button_row: HBoxContainer = $CenterContainer/Panel/VBoxContainer/ButtonRow
@onready var _spectate_btn: Button = $CenterContainer/Panel/VBoxContainer/ButtonRow/SpectateButton
@onready var _home_btn: Button = $CenterContainer/Panel/VBoxContainer/ButtonRow/HomeButton


func _ready() -> void:
	visible = false
	_style_panel()
	_style_labels()
	_spectate_btn.pressed.connect(func(): spectate_requested.emit())
	# HOME hides the screen before announcing, because the scene change behind it
	# is deferred to end-of-frame and the overlay would otherwise be drawn over
	# the home screen's first frame.
	_home_btn.pressed.connect(_on_home_pressed)


func _on_home_pressed() -> void:
	visible = false
	home_requested.emit()


## data keys (all optional — missing ones fall back to placeholder text so this
## never crashes when called with a partial dict during testing):
##   "killer_name": String      — PlayerStats.last_killer_name
##   "damage": float            — PlayerStats.last_killing_damage
##   "layer_name": String       — deepest layer reached, resolved by HUD
##   "kills": int               — this player's kills this match
##   "survival_seconds": float  — GameManager.match_elapsed at time of death
##   "placement": int           — approximate rank (see _build_stats)
##   "total_players": int       — roster size, for the "#N / TOTAL" suffix
func show_death(data: Dictionary) -> void:
	visible = true
	var killer_name: String = data.get("killer_name", "Unknown")
	var damage: float = data.get("damage", 0.0)

	_killer_label.text = "Killed by %s" % killer_name
	_damage_label.text = "Killing blow: %d dmg" % roundi(damage)
	_build_stats(data)


# --- Stat block ---

## Rebuilt from scratch each call rather than mutating cached rows: show_death()
## runs at most once per match, and rebuilding keeps the row list a single
## readable definition instead of a set of node references to keep in sync.
func _build_stats(data: Dictionary) -> void:
	UIStyle.clear_children(_stats_grid)

	# PLACEMENT is deliberately the hero stat (gold, oversized) — it is the one
	# number that summarises the whole run.
	#
	# APPROXIMATE BY DESIGN: it is derived from how many participants were still
	# alive at the instant of death (living + 1), not from a recorded historical
	# placement table. Two participants dying on the same frame can therefore
	# both read the same rank, and it says nothing about how the survivors
	# eventually finish. The UI flags this with the footnote below; a real
	# placement would need GameManager to stamp a finish order on death, which
	# is out of scope for a display-only screen.
	_add_stat_row("PLACEMENT", _placement_text(data), true)
	_add_stat_row("KILLS", "%d" % int(data.get("kills", 0)), false)
	_add_stat_row("LAYER REACHED", str(data.get("layer_name", "Unknown")), false)
	_add_stat_row("SURVIVED", _format_time(float(data.get("survival_seconds", 0.0))), false)


func _placement_text(data: Dictionary) -> String:
	var placement := int(data.get("placement", 0))
	if placement <= 0:
		return "—"
	var total := int(data.get("total_players", 0))
	if total > 0:
		return "#%d / %d" % [placement, total]
	return "#%d" % placement


## Delegates to UIStyle so this screen and the home screen's last-match block are
## literally the same row builder — they render the same four stats and must not
## be able to drift apart.
func _add_stat_row(key: String, value: String, is_hero: bool) -> void:
	UIStyle.add_stat_row(_stats_grid, key, value, is_hero, _STAT_KEY_WIDTH, _STAT_VALUE_WIDTH)


## MM:SS, matching StormTimer's countdown format so both match clocks read the
## same way. Guards against a negative/garbage elapsed value.
func _format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	# Floor division to whole minutes for MM:SS display is intended.
	@warning_ignore("integer_division")
	var minutes := total / 60
	return "%d:%02d" % [minutes, total % 60]


# --- Styling ---

func _style_panel() -> void:
	var s := UIStyle.modal_panel_style()
	s.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", s)

	# The stat block reuses the in-match HUD panel recipe (dark navy fill, thin
	# light border) so it reads as the same family as the Layer/Storm/Kills
	# panels the player was looking at a second ago.
	var stats_style := UIStyle.small_panel_style()
	stats_style.set_content_margin_all(10)
	_stats_panel.add_theme_stylebox_override("panel", stats_style)
	_stats_box.add_theme_constant_override("separation", 6)
	_stats_grid.add_theme_constant_override("h_separation", 12)
	_stats_grid.add_theme_constant_override("v_separation", 5)

	# Match WinScreen's ButtonRow spacing so the two end-of-match screens' action
	# rows sit identically.
	_button_row.add_theme_constant_override("separation", 14)

	# SPECTATE is this screen's primary action and takes the gold; HOME is the
	# neutral secondary, exactly as on the win screen. Added in the 2026-08-01
	# menu visual pass — both were plain default Buttons before it.
	UIStyle.style_button(_spectate_btn, UIStyle.ACCENT_GOLD, 140.0)
	UIStyle.style_button(_home_btn, UIStyle.ACCENT_NEUTRAL, 140.0)


func _style_labels() -> void:
	# The one title in the game that is NOT the neutral title colour: death is the
	# screen's whole message, so it keeps its red + heavy outline rather than
	# going through UIStyle.style_title().
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.90, 0.20, 0.16))
	_title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.9))
	_title_label.add_theme_constant_override("outline_size", 4)

	_killer_label.add_theme_font_size_override("font_size", 14)
	_killer_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.24))

	_damage_label.add_theme_font_size_override("font_size", 12)
	_damage_label.add_theme_color_override("font_color", UIStyle.TEXT_BODY)

	_stats_header.add_theme_font_size_override("font_size", 10)
	_stats_header.add_theme_color_override("font_color", _COLOR_ACCENT)

	# Flags the placement stat as an at-time-of-death approximation rather than
	# a final standing (see _build_stats).
	_placement_note.text = "placement is your rank at the moment of death"
	_placement_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_note.add_theme_font_size_override("font_size", 9)
	_placement_note.add_theme_color_override("font_color", _COLOR_FOOTNOTE)
