extends Node2D

const COLOR_FILL := Color(0.02, 0.01, 0.01, 0.93)
const COLOR_ROCK := Color(0.32, 0.22, 0.12, 0.92)
const COLOR_DARK := Color(0.10, 0.06, 0.02, 0.75)
const SEG_H      := 8.0
const ROUGHNESS  := 10.0
const V_DEPTH    := 48.0   # how deep the V-tip goes below the floor
const V_SEGS     := 12     # smoothness of the V curve

var _w:    float = 90.0
var _h:    float = 0.0
var _top_y: float = 0.0    # shaft_top in screen coords — used to offset jag pattern
var _jags: Array = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	for _i in 512:
		_jags.append(rng.randf_range(0.0, 1.0))

# Hash-based jag: world_seg changes as tunnel grows, side differentiates L/R
func _jag(world_seg: int, side: int) -> float:
	var idx: int = ((world_seg * 73) + (side * 137)) & 511
	return _jags[idx] * ROUGHNESS

func set_shaft(pos: Vector2, w: float, h: float) -> void:
	_top_y = pos.y
	position = pos
	_w = w
	_h = h
	queue_redraw()

func _draw() -> void:
	if _h <= 1.0:
		return

	# Segment offset tied to screen position → shifts as you drill deeper
	var top_seg: int = int(_top_y / SEG_H)
	var segs: int    = int(ceil(_h / SEG_H)) + 1

	# ── Build closed polygon ──────────────────────────────────────────
	var pts := PackedVector2Array()

	# 1. Left wall: top → bottom
	for i in segs:
		var y: float = minf(float(i) * SEG_H, _h)
		pts.append(Vector2(_jag(top_seg + i, 0), y))

	# 2. V-shaped floor: left corner → deepest center → right corner
	var lx: float = _jag(top_seg + segs - 1, 0)
	var rx: float = _w - _jag(top_seg + segs - 1, 1)
	for i in V_SEGS + 1:
		var t: float     = float(i) / float(V_SEGS)
		# Tent-power curve: linear V shape with softened tip
		# tent = 1 at center, 0 at edges → true V; power < 1 softens the very tip
		var tent: float  = 1.0 - abs(2.0 * t - 1.0)
		var curve: float = pow(tent, 0.75)
		pts.append(Vector2(
			lx + t * (rx - lx),
			_h + curve * V_DEPTH
		))

	# 3. Right wall: bottom → top
	for i in range(segs - 1, -1, -1):
		var y: float = minf(float(i) * SEG_H, _h)
		pts.append(Vector2(_w - _jag(top_seg + i, 1), y))

	draw_colored_polygon(pts, COLOR_FILL)

	# ── Wall edge lines for rocky look ────────────────────────────────
	for i in range(segs - 1):
		var y0: float  = float(i) * SEG_H
		var y1: float  = minf(float(i + 1) * SEG_H, _h)
		if y0 >= _h: break
		var lx0: float = _jag(top_seg + i,     0)
		var lx1: float = _jag(top_seg + i + 1, 0)
		var rx0: float = _w - _jag(top_seg + i,     1)
		var rx1: float = _w - _jag(top_seg + i + 1, 1)
		draw_line(Vector2(lx0, y0),     Vector2(lx1, y1),     COLOR_ROCK, 3.0)
		draw_line(Vector2(lx0 + 3, y0), Vector2(lx1 + 3, y1), COLOR_DARK, 1.5)
		draw_line(Vector2(rx0, y0),     Vector2(rx1, y1),     COLOR_ROCK, 3.0)
		draw_line(Vector2(rx0 - 3, y0), Vector2(rx1 - 3, y1), COLOR_DARK, 1.5)

	# ── V-floor edge line ─────────────────────────────────────────────
	var prev := Vector2(lx, _h)
	for i in V_SEGS + 1:
		var t: float     = float(i) / float(V_SEGS)
		var tent: float  = 1.0 - abs(2.0 * t - 1.0)
		var curve: float = pow(tent, 0.75)
		var cur          := Vector2(lx + t * (rx - lx), _h + curve * V_DEPTH)
		draw_line(prev, cur, COLOR_ROCK, 3.0)
		prev = cur
