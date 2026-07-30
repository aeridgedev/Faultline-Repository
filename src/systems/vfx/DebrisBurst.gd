## Faultline — one pooled debris burst: the chips that fly out of a destroyed tile.
##
## PURELY CLIENT-LOCAL COSMETIC STATE. Nothing in this file is replicated, RPC'd,
## or authoritative — see the header of VFXManager.gd for the full rationale.
##
## ONE NODE DRAWS THE WHOLE BURST. Every particle lives in flat Packed* arrays and
## is rendered by a single _draw() pass. Deliberately NOT one Node2D per particle:
## a Burst-class drill destroys 2 tiles per dig and a Seismic Charge destroys a
## whole radius in a single frame, so per-particle nodes would spike the node count
## and allocate hard exactly when the frame is already busy.
##
## LIFECYCLE — retire, don't free. The naive version of this effect is a self-freeing
## one-shot, but VFXManager POOLS these (a fixed set is built once at startup and
## reused forever), and recycling is the entire point of the pool: allocating a node
## per destroyed tile is the cost this system exists to avoid. So a finished burst
## hides itself, stops processing and fires `finished` — it never calls queue_free().
## The pool owns the node for the whole match.
##
## All numbers below are pure VFX-FEEL constants (particle lifetime, drag, spin,
## chip size). They are not balance values and deliberately do NOT live in
## data/*.json — same rule TestDummy's dev constants follow.
class_name DebrisBurst
extends Node2D

## Emitted once when every particle in this burst has expired. Carries itself so
## VFXManager can return it to the free list without a per-frame scan.
signal finished(burst)

# Hard cap on particles per burst. The Packed* arrays are sized to this ONCE, in
# _init(), and never resized again — emit() only overwrites the first _count entries.
const MAX_PARTICLES := 10

const _COUNT_MIN := 5
const _COUNT_MAX := 8

const _LIFE_MIN := 0.26        # seconds a chip survives
const _LIFE_MAX := 0.48
const _SPEED_MIN := 45.0       # px/sec initial outward speed
const _SPEED_MAX := 135.0
const _UPWARD_BIAS := 55.0     # px/sec added upward: a struck tile spits chips up
const _SPAWN_JITTER := 3.5     # px of scatter around the impact point
const _GRAVITY := 430.0        # px/sec^2 pulling chips back down
const _DRAG_PER_SEC := 0.35    # fraction of velocity retained after one second
const _SIZE_MIN := 1.6         # px edge length of a chip (16px tile grid)
const _SIZE_MAX := 3.4
const _SPIN_MIN := 2.0         # rad/sec
const _SPIN_MAX := 9.0
const _END_SCALE := 0.30       # chips shrink to this fraction before vanishing
const _FADE_POWER := 2.2       # alpha = 1 - t^power: holds bright, then drops fast
const _SHADE_MIN := 0.80       # per-chip brightness jitter off the terrain colour
const _SHADE_MAX := 1.22

# Per-particle state. Flat parallel arrays, allocated once — no per-burst churn.
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _shade := PackedFloat32Array()

var _count: int = 0          # particles in use this burst (<= MAX_PARTICLES)
var _elapsed: float = 0.0
var _longest_life: float = 0.0
var _base_color: Color = Color(0.55, 0.55, 0.58)
var _running: bool = false

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_pos.resize(MAX_PARTICLES)
	_vel.resize(MAX_PARTICLES)
	_rot.resize(MAX_PARTICLES)
	_spin.resize(MAX_PARTICLES)
	_life.resize(MAX_PARTICLES)
	_size.resize(MAX_PARTICLES)
	_shade.resize(MAX_PARTICLES)
	_rng.randomize()


func _ready() -> void:
	# Pooled bursts sit idle until emit() wakes them, so they cost nothing at rest.
	visible = false
	set_process(false)


func is_active() -> bool:
	return _running


## (Re)starts this burst at a world position with the destroyed tile's colour.
## Safe to call on a burst that is still mid-flight — that is exactly what the
## pool's recycle-oldest path does; the previous particles are simply overwritten.
## Deliberately does NOT fire `finished` on a recycle: `finished` fires once per
## play(), only when the burst runs to completion, so the pool's bookkeeping can
## never double-count a node.
## (Named play(), not emit(), so it can never be misread as a signal emission.)
func play(world_pos: Vector2, color: Color) -> void:
	global_position = world_pos
	_base_color = color
	_elapsed = 0.0
	_longest_life = 0.0
	_count = _rng.randi_range(_COUNT_MIN, _COUNT_MAX)
	for i in _count:
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(_SPEED_MIN, _SPEED_MAX)
		_pos[i] = Vector2(
			_rng.randf_range(-_SPAWN_JITTER, _SPAWN_JITTER),
			_rng.randf_range(-_SPAWN_JITTER, _SPAWN_JITTER))
		# Radial fan with an upward bias (screen-space -Y is up).
		_vel[i] = Vector2(cos(angle), sin(angle)) * speed - Vector2(0.0, _UPWARD_BIAS)
		_rot[i] = _rng.randf_range(0.0, TAU)
		_spin[i] = _rng.randf_range(_SPIN_MIN, _SPIN_MAX) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_life[i] = _rng.randf_range(_LIFE_MIN, _LIFE_MAX)
		_size[i] = _rng.randf_range(_SIZE_MIN, _SIZE_MAX)
		_shade[i] = _rng.randf_range(_SHADE_MIN, _SHADE_MAX)
		_longest_life = maxf(_longest_life, _life[i])
	_running = true
	visible = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if _elapsed >= _longest_life:
		_retire()
		return
	# Exponential drag, resolved once per frame rather than once per particle.
	var damp := pow(_DRAG_PER_SEC, delta)
	var fall := _GRAVITY * delta
	for i in _count:
		if _elapsed >= _life[i]:
			continue
		var v: Vector2 = _vel[i]
		v.y += fall
		v *= damp
		_vel[i] = v
		_pos[i] = _pos[i] + v * delta
		_rot[i] = _rot[i] + _spin[i] * delta
	queue_redraw()


func _draw() -> void:
	if not _running:
		return
	for i in _count:
		var life: float = _life[i]
		if _elapsed >= life:
			continue
		var t: float = _elapsed / life
		var edge: float = _size[i] * lerpf(1.0, _END_SCALE, t)
		var shade: float = _shade[i]
		var col := Color(
			clampf(_base_color.r * shade, 0.0, 1.0),
			clampf(_base_color.g * shade, 0.0, 1.0),
			clampf(_base_color.b * shade, 0.0, 1.0),
			clampf(1.0 - pow(t, _FADE_POWER), 0.0, 1.0))
		# draw_set_transform gives each chip its own rotation without needing a node.
		draw_set_transform(_pos[i], _rot[i], Vector2.ONE)
		draw_rect(Rect2(-edge * 0.5, -edge * 0.5, edge, edge), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Back to the pool: invisible, not processing, not drawing — but still allocated.
func _retire() -> void:
	_running = false
	_count = 0
	visible = false
	set_process(false)
	queue_redraw()
	finished.emit(self)
