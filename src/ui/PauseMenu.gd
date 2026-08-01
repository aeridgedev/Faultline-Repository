## Faultline — in-match esc/pause menu (menu pass, screen 2 of 3: death → esc → home).
##
## Owns the actual pause: Esc toggles `get_tree().paused`, which freezes every
## other node in the tree (terrain streaming, TestDummies, storm/depth/pressure
## ticks, GameManager.match_elapsed, drill + combat input) because they all run
## on the engine default PROCESS_MODE_PAUSABLE. Nothing is gated by hand — this
## node simply opts ITSELF out of the pause with PROCESS_MODE_ALWAYS so Esc and
## the buttons keep working while everything else is stopped.
##
## This file NEVER talks to GameManager. HUD is the integration layer for every
## in-match menu screen (the same split DeathScreen and WinScreen already use):
## this screen only emits `home_requested` / `quit_requested`, and HUD makes the
## actual GameManager.return_to_home() / get_tree().quit() calls. RESUME needs
## nothing outside this file, so it is handled here and emits no signal.
##
## STYLED 2026-08-01 (menu visual pass): the modal panel recipe and the button
## recipe both come from UIStyle, so this screen matches the death/win/home
## screens instead of being a plain default-control lookalike. No logic changed —
## the pause semantics, availability gating and signal split below are untouched.
##
## The `Background` ColorRect stays functional as well as visual: it blocks mouse
## input from reaching the screens underneath (this menu sits on CanvasLayer 30,
## above the HUD's layer 1 and the inventory panel's layer 20).
class_name PauseMenu
extends CanvasLayer

## Emitted when the player chooses to abandon the in-progress match. The menu has
## already closed (and unpaused) itself by the time this fires.
signal home_requested
signal quit_requested

const _BUTTON_WIDTH := 220.0

@onready var _background: ColorRect = $Background
@onready var _panel: PanelContainer = $CenterContainer/Panel
@onready var _title_label: Label = $CenterContainer/Panel/VBoxContainer/TitleLabel
@onready var _hint_label: Label = $CenterContainer/Panel/VBoxContainer/HintLabel
@onready var _resume_btn: Button = $CenterContainer/Panel/VBoxContainer/ResumeButton
@onready var _settings_btn: Button = $CenterContainer/Panel/VBoxContainer/SettingsButton
@onready var _home_btn: Button = $CenterContainer/Panel/VBoxContainer/HomeButton
@onready var _quit_btn: Button = $CenterContainer/Panel/VBoxContainer/QuitButton

## Whether Esc may open the menu at all. Driven entirely by HUD via
## set_available() — this screen deliberately does not read match state itself.
var _available: bool = false
var _is_open: bool = false


func _ready() -> void:
	# THE invariant that makes this screen work. Every other node in the match
	# resolves to PROCESS_MODE_PAUSABLE (they are all PROCESS_MODE_INHERIT with no
	# non-inherit ancestor, which Godot resolves to PAUSABLE — this is also why
	# the GameManager autoload's match_elapsed stops ticking while paused), so
	# get_tree().paused freezes them and leaves this subtree running. Set in code
	# rather than in the .tscn so there is a single source of truth, same as
	# HomeScreen's disabled SETTINGS button.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_style_screen()

	_resume_btn.pressed.connect(_close)
	_home_btn.pressed.connect(_on_home_pressed)
	# Same quit call HUD wires WinScreen's and HomeScreen's Quit buttons to.
	_quit_btn.pressed.connect(func(): quit_requested.emit())
	# Placeholder only, exactly like HomeScreen's: a settings pass is out of
	# scope, so the button exists but is inert rather than wired to a screen that
	# does not exist yet. Disabled here (not in the .tscn) for one source of truth.
	_settings_btn.disabled = true


## Menu visual pass (2026-08-01). Applied in code from UIStyle rather than
## authored in the .tscn, matching how the disabled SETTINGS button is set — one
## source of truth, and every menu screen moves together.
func _style_screen() -> void:
	_background.color = UIStyle.BACKDROP

	var panel_style := UIStyle.modal_panel_style()
	panel_style.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", panel_style)

	UIStyle.style_title(_title_label, 26)

	# RESUME is the primary (and safe) action, so it takes the gold; the two ways
	# out of the match stay neutral, matching WinScreen's QUIT/HOME.
	UIStyle.style_button(_resume_btn, UIStyle.ACCENT_GOLD, _BUTTON_WIDTH)
	UIStyle.style_button(_settings_btn, UIStyle.ACCENT_NEUTRAL, _BUTTON_WIDTH)
	UIStyle.style_button(_home_btn, UIStyle.ACCENT_NEUTRAL, _BUTTON_WIDTH)
	UIStyle.style_button(_quit_btn, UIStyle.ACCENT_NEUTRAL, _BUTTON_WIDTH)

	_hint_label.add_theme_font_size_override("font_size", 9)
	_hint_label.add_theme_color_override("font_color", UIStyle.TEXT_FAINT)


## Esc is read in _input(), NOT _unhandled_input(), deliberately: _input() runs
## before the GUI pass, so no Control can swallow the key first. The project has
## already been bitten once by an input handler that a full-rect HUD Control
## silently ate (the chest `interact` rebind — see CLAUDE.md 2026-07-31), and
## while that failure mode is mouse-specific, this menu must be reachable from
## *any* game state including one where a modal has keyboard focus. The event is
## consumed only when it actually toggles the menu, so a blocked Esc still falls
## through to anything else that wants it.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _is_open:
		_close()
	elif _available:
		open()
	else:
		return
	get_viewport().set_input_as_handled()


## HUD gates when pausing is legal: true while the local player is playing or
## spectating, false while the DeathScreen is up (a modal decision point of its
## own) and once the match has ended (WinScreen). Turning availability off while
## the menu happens to be open force-closes it, so the tree can never be left
## paused with no menu on screen to unpause it.
func set_available(available: bool) -> void:
	_available = available
	if not available:
		_close()


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open or not _available:
		return
	_is_open = true
	visible = true
	get_tree().paused = true
	# Keyboard/gamepad users land on the safe option rather than nothing.
	_resume_btn.grab_focus()


func _close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	get_tree().paused = false


## RETURN TO HOME is a mid-run abandonment, not a death or a win. Close (and so
## unpause) first, then let HUD drive the actual exit — nothing here writes any
## match result; GameManager.last_match_summary is deliberately untouched on this
## path so the home screen keeps showing the last COMPLETED match.
func _on_home_pressed() -> void:
	_close()
	home_requested.emit()
