## Faultline — trauma-based screen shake driver for one local Camera2D.
##
## PURELY CLIENT-LOCAL COSMETIC STATE. Trauma is never replicated and never
## authoritative — see the header of VFXManager.gd.
##
## Standard decaying-trauma model (Squirrel Eiserloh's): callers add impulses via
## add_trauma(); trauma is clamped to 1.0 and decays LINEARLY every frame; the
## displacement applied is trauma^TRAUMA_EXPONENT * MAX_OFFSET, so the response is
## super-linear — a single dug tile is a barely-there nudge while a stacked impulse
## (Burst drill hitting 2 tiles, a Seismic Charge levelling a radius, a broken
## drill) is a real jolt. Offsets are sampled from smooth Simplex noise rather than
## per-frame randf so the motion reads as a shake, not as static.
##
## HOW IT TOUCHES THE CAMERA — this is the load-bearing part:
## it writes ONLY `Camera2D.offset`, and never `position` / `global_position`, and
## never reparents anything. Player.tscn's Camera2D is a child of the player body
## with position_smoothing_enabled = true; `offset` is applied on top of the
## smoothed follow position, so shake is instant and camera-following is untouched.
## Writing `position` instead would fight the smoothing AND break the follow.
## When trauma reaches zero the offset is snapped back to Vector2.ZERO exactly once,
## so the camera can never be left permanently displaced.
##
## NO ROTATION TERM — deliberate. Godot 4's Camera2D.ignore_rotation defaults to
## true, so a rotational shake would first require flipping that property on
## Player.tscn's camera; and rotating a 16px-grid pixel-art view resamples every
## tile off-axis, which produces exactly the shimmering edges the locked pixel-art
## direction is trying to avoid. Two-axis translation is the correct tool here.
##
## All numbers below are pure VFX-FEEL constants (offset amplitude, decay rate,
## noise frequency). They are not balance values and deliberately do NOT live in
## data/*.json — same rule TestDummy's dev constants follow.
class_name CameraShake
extends Node

## Every CameraShake adds itself here so world-side systems (VFXManager) can drive
## the local camera without holding a reference to the player at all.
const GROUP := "camera_shake"

# --- Trauma magnitudes for the three impact triggers -------------------------
# Kept together so the relative feel is readable at a glance. Resulting peak
# displacement = trauma^2 * MAX_OFFSET.x, at the 1280x720 / zoom 2.5 default
# (1 world px = 2.5 screen px):
#   tile destroyed  0.28 -> ~1.1 world px (~2.7 screen px) — a tick of impact
#   melee hit       0.45 -> ~2.8 world px (~7.1 screen px) — a solid thud
#   drill broken    0.85 -> ~10.1 world px (~25 screen px) — the loudest event
#                                                            a player can hit
# Tile destroy is the smallest because it fires constantly while drilling; drill
# break is the largest because it happens once and ends the player's ability to dig.
const TRAUMA_TILE_DESTROY := 0.28
const TRAUMA_MELEE_HIT := 0.45
const TRAUMA_DRILL_BREAK := 0.85

const MAX_OFFSET := Vector2(14.0, 11.0)  # world px of displacement at trauma 1.0
const TRAUMA_DECAY := 1.5                # trauma units shed per second
const TRAUMA_EXPONENT := 2.0             # squared: keeps small hits genuinely small
const SHAKE_FREQUENCY := 26.0            # noise samples traversed per second
const _NOISE_ROW_X := 0.0                # two separate rows of the noise field, so
const _NOISE_ROW_Y := 128.0              # X and Y shake independently

var _camera: Camera2D = null
var _trauma: float = 0.0
var _time: float = 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	add_to_group(GROUP)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_noise.seed = randi()
	# Idle until something adds trauma — a resting camera costs zero frames.
	set_process(false)


## Points this driver at the camera it should shake. The reference is to the NODE,
## not a path, so it survives SpectatorView reparenting the camera onto the
## spectated player (that flow moves the same Camera2D; it never replaces it).
func setup(camera: Camera2D) -> void:
	_camera = camera


## Adds an impulse. Trauma accumulates and clamps at 1.0, so several impacts in one
## frame (a multi-target swing, a Burst drill's two tiles) stack into a bigger jolt.
func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	set_process(true)


## Adds an impulse attenuated by how far the event happened from this camera:
## full strength at the camera, zero at/beyond falloff_radius, on a smooth
## 1 - (d/r)^2 curve so anything on screen keeps most of its punch.
##
## This is what stops a Seismic Charge two layers down — or, once step 9 lands,
## another player's drilling anywhere in a 100-player match — from shaking a
## camera that cannot even see it. `tile_destroyed` fires for the whole world,
## not just for the local player's digging.
func add_trauma_at(world_pos: Vector2, amount: float, falloff_radius: float) -> void:
	if falloff_radius <= 0.0 or _camera == null or not is_instance_valid(_camera):
		return
	var dist := _camera.global_position.distance_to(world_pos)
	if dist >= falloff_radius:
		return
	var ratio := dist / falloff_radius
	add_trauma(amount * (1.0 - ratio * ratio))


func get_trauma() -> float:
	return _trauma


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_trauma = 0.0
		set_process(false)
		return

	_time += delta
	_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * delta)

	if _trauma <= 0.0:
		# Neutral rest state. Snapping the offset back exactly once (rather than
		# leaving whatever the last shaken frame wrote) is what guarantees the
		# camera is never left permanently displaced.
		_camera.offset = Vector2.ZERO
		set_process(false)
		return

	var shake := pow(_trauma, TRAUMA_EXPONENT)
	var sample := _time * SHAKE_FREQUENCY
	_camera.offset = Vector2(
		MAX_OFFSET.x * shake * _noise.get_noise_2d(_NOISE_ROW_X, sample),
		MAX_OFFSET.y * shake * _noise.get_noise_2d(_NOISE_ROW_Y, sample))
