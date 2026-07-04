## Faultline — shared style/utility helpers for hand-built UI (HUD, DeathScreen,
## SpectatorView, WinScreen). Static-only; nothing here holds state.
class_name UIStyle
extends RefCounted


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


static func clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
