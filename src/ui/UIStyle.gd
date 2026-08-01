## Faultline — shared style/utility helpers for hand-built UI (HUD, DeathScreen,
## SpectatorView, WinScreen, HomeScreen, PauseMenu). Static-only; nothing here
## holds state.
##
## This is the single definition of the menu visual language. Every menu screen
## pulls its palette and its button/panel recipes from here rather than declaring
## its own, so the four screens cannot drift apart. The values below are not new
## — they are the ones DeathScreen and WinScreen already established, promoted to
## one place during the 2026-08-01 menu visual pass.
class_name UIStyle
extends RefCounted

# --- Palette ---

## The one accent colour of the menu system: Constants.TIER_COLORS[LEGENDARY],
## also WinScreen's winner row, DeathScreen's PLACEMENT stat, and the HUD's
## kill-progress panel. Reserved for the primary action on a screen and for the
## single number that summarises a run. Do not introduce a second accent.
const ACCENT_GOLD := Color("e6a817")
## Secondary/neutral action (QUIT, HOME, RETURN TO HOME).
const ACCENT_NEUTRAL := Color(0.60, 0.63, 0.70)

const TEXT_PRIMARY := Color(0.90, 0.92, 0.96)   # titles
const TEXT_BODY := Color(0.88, 0.91, 0.96)      # stat values, normal copy
const TEXT_DIM := Color(0.55, 0.60, 0.70)       # stat keys, secondary labels
const TEXT_FAINT := Color(0.45, 0.49, 0.57)     # footnotes / caveats

## Shared modal backdrop. Functional as well as visual: it blocks mouse input
## from reaching whatever is underneath. Same value on every full-screen overlay.
const BACKDROP := Color(0, 0, 0, 0.65)
## Opaque fill behind the home screen, which (unlike the in-match overlays) has
## no game world to sit on top of.
const SCREEN_BG := Color(0.04, 0.05, 0.07, 1.0)


## The small HUD panel recipe (LayerPanel/StormPanel/KillCounter/EffectsPanel/
## SpectatorView's TopBar). Returns a fresh instance — safe to mutate further.
static func small_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.10, 0.88)
	s.set_corner_radius_all(4)
	s.set_border_width_all(1)
	s.border_color = Color(0.55, 0.58, 0.65, 0.80)
	return s


## The full-screen modal recipe (DeathScreen/WinScreen). Content margin differs
## per caller, so that's left for the caller to set afterward.
static func modal_panel_style(bg_alpha: float = 0.94, border_alpha: float = 0.80) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.10, bg_alpha)
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = Color(0.55, 0.58, 0.65, border_alpha)
	return s


## The menu button recipe, promoted out of WinScreen so every screen's buttons
## match. `accent` should be ACCENT_GOLD for a screen's primary action and
## ACCENT_NEUTRAL for everything else.
##
## Styles all five states deliberately, not just `normal`: a Button with only a
## `normal` override falls back to Godot's DEFAULT theme for hover/pressed/
## disabled/focus, which reads as a completely different (light grey) control the
## moment the mouse touches it or a disabled placeholder is drawn. `focus` is
## styled because PauseMenu calls grab_focus() on RESUME when it opens.
static func style_button(btn: Button, accent: Color, width: float = 130.0, height: float = 40.0) -> void:
	btn.custom_minimum_size = Vector2(width, height)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color(0.97, 0.97, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0))
	# A disabled placeholder must read as unavailable rather than merely dark.
	btn.add_theme_color_override("font_disabled_color", Color(0.42, 0.45, 0.52))

	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(8)
	normal.bg_color = accent.darkened(0.55)
	normal.set_border_width_all(2)
	normal.border_color = accent

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.darkened(0.35)

	# Focus differs from hover by its border only, so keyboard focus is legible
	# without looking like the mouse is over the button.
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = accent.lightened(0.35)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.10, 0.11, 0.14, 0.85)
	disabled.border_color = Color(0.28, 0.30, 0.35, 0.85)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)


## Screen title (FAULTLINE / PAUSED / MATCH COMPLETE). `color` defaults to the
## neutral title colour; DeathScreen passes its own red and adds an outline.
static func style_title(lbl: Label, size: int, color: Color = TEXT_PRIMARY) -> void:
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)


## One key/value row of a stat block, in the DeathScreen MATCH SUMMARY language:
## dim 11px key on the left, right-aligned value on the right, with the hero row
## (the one number that summarises the run) oversized and gold. Appends two
## children to a 2-column GridContainer.
static func add_stat_row(grid: GridContainer, key: String, value: String, is_hero: bool,
		key_width: float = 148.0, value_width: float = 132.0) -> void:
	var key_lbl := Label.new()
	key_lbl.text = key
	key_lbl.custom_minimum_size = Vector2(key_width, 0)
	key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_lbl.add_theme_font_size_override("font_size", 11)
	key_lbl.add_theme_color_override("font_color", TEXT_DIM)

	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.custom_minimum_size = Vector2(value_width, 0)
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lbl.clip_text = true
	val_lbl.add_theme_font_size_override("font_size", 18 if is_hero else 13)
	val_lbl.add_theme_color_override("font_color", ACCENT_GOLD if is_hero else TEXT_BODY)

	grid.add_child(key_lbl)
	grid.add_child(val_lbl)


static func clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
