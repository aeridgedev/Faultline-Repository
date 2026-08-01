## Faultline — all 10 weapon passives (5 classes x 2 passive tiers), implemented 2026-07-31.
##
## Before this, `minor_passive` / `unique_passive` in weapon_stats.json were display strings
## with no code behind them, and WeaponTier.has_passive() / WeaponClass.passive_name() were
## never called by anything. An Epic and a Legendary differed only by stat multipliers.
##
## TIER RULE (from the LOCKED Constants.WEAPON_TIER_SCALING, which stores ONE "passive"
## string per tier): Common/Rare have none, Epic gets its class's MINOR passive, Legendary
## gets its class's UNIQUE passive INSTEAD — they do not stack. A Legendary Dagger has
## Assassin's Mark but not Serrated Edge.
##
## All magnitudes live in data/weapon_stats.json -> "passives" and are first-pass TBD.
## Every lookup has a fallback, so a missing/null value makes that passive a no-op.
##
## Hook points, all called from PlayerController's melee path:
##   on_swing()      - when a swing starts        (Riposte, Impaling Lunge: act on the attacker)
##   damage_mult()   - before take_damage()       (Assassin's Mark, Executioner)
##   armor_pierce()  - passed into take_damage()  (Piercing Thrust)
##   on_hit()        - right after damage lands   (Serrated Edge, Concussive Blow,
##                                                 Seismic Shockwave, Rend)
##   on_kill()       - when the hit was lethal    (Bloodthirst)
class_name WeaponPassives
extends RefCounted


## "" (none) / "minor" (Epic) / "unique" (Legendary) for this weapon's tier.
static func _kind(w: WeaponBase) -> String:
	if w == null:
		return ""
	return str(Constants.WEAPON_TIER_SCALING[w.tier]["passive"])


## Reads data["weapons"]["passives"][block][key], or `def` when absent/null.
static func _val(block: String, key: String, def: float) -> float:
	var weapons := GameManager.data.get("weapons", {}) as Dictionary
	var passives := weapons.get("passives", {}) as Dictionary
	var entry := passives.get(block, {}) as Dictionary
	var v: Variant = entry.get(key, null)
	return float(v) if v != null else def


## Identifies which passive is live: returns its data-block name, or "" for none.
## Keeping the class->block mapping in ONE place means the hook functions below never
## repeat the tier/class match.
static func _block(w: WeaponBase) -> String:
	var kind := _kind(w)
	if kind == "":
		return ""
	var minor := kind == "minor"
	match w.weapon_class:
		Constants.WeaponClass.DAGGERS: return "serrated_edge" if minor else "assassins_mark"
		Constants.WeaponClass.SWORDS:  return "riposte" if minor else "bloodthirst"
		Constants.WeaponClass.HAMMERS: return "concussive_blow" if minor else "seismic_shockwave"
		Constants.WeaponClass.SPEARS:  return "piercing_thrust" if minor else "impaling_lunge"
		Constants.WeaponClass.AXES:    return "rend" if minor else "executioner"
	return ""


# --- Hook: swing start -----------------------------------------------------

## Riposte (Swords Epic) — a brief parry window on the attacker, applied as a self status
## so it flows through the existing effect system and shows on the HUD buff panel.
## Impaling Lunge (Spears Legendary) — dash the attacker along the aim direction.
static func on_swing(w: WeaponBase, attacker: CharacterBody2D, attacker_stats: PlayerStats, aim: Vector2) -> void:
	match _block(w):
		"riposte":
			if attacker_stats == null:
				return
			attacker_stats.apply_status("Riposte", _val("riposte", "window", 0.45), true, {
				"parry_reduction": _val("riposte", "damage_reduction", 0.6),
			})
		"impaling_lunge":
			if attacker == null or aim.length_squared() < 0.0001:
				return
			# Added to velocity rather than assigned, so the lunge composes with current
			# motion instead of cancelling it. move_and_slide() still resolves terrain, so
			# this can never push the player through a wall or past a locked layer gate.
			attacker.velocity += aim.normalized() * _val("impaling_lunge", "lunge_speed", 260.0)


# --- Hook: outgoing damage -------------------------------------------------

## Multiplier applied to this hit's damage before take_damage().
## Assassin's Mark (Daggers Legendary) — crit when striking a target from behind.
## Executioner (Axes Legendary) — bonus damage against low-HP targets.
static func damage_mult(w: WeaponBase, attacker: Node2D, target: Node2D, target_stats: PlayerStats) -> float:
	match _block(w):
		"assassins_mark":
			if _is_behind(attacker, target):
				return _val("assassins_mark", "crit_mult", 2.0)
		"executioner":
			if target_stats != null and target_stats.max_health > 0.0:
				var frac := target_stats.current_health / target_stats.max_health
				if frac <= _val("executioner", "hp_threshold", 0.30):
					return _val("executioner", "damage_mult", 1.6)
	return 1.0


## True when the attacker stands on the side the target is NOT facing.
## Both PlayerController and TestDummy expose get_facing_sign() (-1 left / +1 right);
## anything else returns false rather than guessing, so a backstab is never awarded
## against a target whose orientation is unknown.
static func _is_behind(attacker: Node2D, target: Node2D) -> bool:
	if attacker == null or target == null or not target.has_method("get_facing_sign"):
		return false
	var facing: float = target.get_facing_sign()
	if facing == 0.0:
		return false
	var to_attacker := attacker.global_position.x - target.global_position.x
	if absf(to_attacker) < 0.001:
		return false
	return signf(to_attacker) != signf(facing)


## Armor-pierce fraction for this hit — Piercing Thrust (Spears Epic).
static func armor_pierce(w: WeaponBase) -> float:
	if _block(w) == "piercing_thrust":
		return clampf(_val("piercing_thrust", "armor_pierce", 0.35), 0.0, 1.0)
	return 0.0


# --- Hook: on hit ----------------------------------------------------------

## Effects applied to the target immediately after damage lands.
static func on_hit(w: WeaponBase, attacker: Node2D, target: Node2D, target_stats: PlayerStats) -> void:
	if target_stats == null or target_stats.is_dead:
		return
	match _block(w):
		"serrated_edge":
			# Bleed rides the existing dot_dps/dot_interval payload, so PlayerStats ticks it
			# and Hellforge armor's burn_resist scales it, exactly like a Heat Charge burn.
			target_stats.apply_status("Bleed", _val("serrated_edge", "bleed_duration", 3.0), false, {
				"dot_dps": _val("serrated_edge", "bleed_dps", 3.0),
				"dot_interval": _val("serrated_edge", "bleed_interval", 0.5),
			})
		"concussive_blow":
			# Reuses the Paralysis "frozen" payload; deliberately very short (a stagger,
			# not a stun) because frozen blocks all movement AND actions.
			target_stats.apply_status("Staggered", _val("concussive_blow", "stagger_duration", 0.4), false, {
				"frozen": true,
			})
		"seismic_shockwave":
			_knockback(attacker, target, _val("seismic_shockwave", "knockback_force", 320.0))
		"rend":
			# Stacking: read the shred already on the target, add one stack, cap it, and
			# re-apply (apply_status overwrites by name, which also refreshes the duration).
			var cur := target_stats.get_status_param("Rend", "armor_shred", 0.0)
			var next := minf(cur + _val("rend", "shred_per_stack", 0.10), _val("rend", "max_shred", 0.40))
			target_stats.apply_status("Rend", _val("rend", "duration", 4.0), false, {
				"armor_shred": next,
			})


## Pushes the target away from the attacker. Only CharacterBody2D targets have a velocity
## to modify; anything else is skipped rather than special-cased.
static func _knockback(attacker: Node2D, target: Node2D, force: float) -> void:
	var body := target as CharacterBody2D
	if body == null or attacker == null:
		return
	var dir := target.global_position - attacker.global_position
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	body.velocity += dir.normalized() * force


# --- Hook: on kill ---------------------------------------------------------

## Bloodthirst (Swords Legendary) — heal the attacker when the hit was lethal.
static func on_kill(w: WeaponBase, attacker_stats: PlayerStats) -> void:
	if _block(w) != "bloodthirst" or attacker_stats == null:
		return
	# heal() already applies the storm heal-reduction multiplier and clamps to max_health.
	attacker_stats.heal(_val("bloodthirst", "heal_on_kill", 25.0))
