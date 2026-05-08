extends Control

const PIXELS_PER_METER := 2.0
const CHARACTER_SCREEN_Y := 340.0

var _depth: float = 0.0
var _font: Font

func _ready():
	_font = ThemeDB.fallback_font

func update(depth: float):
	_depth = depth
	queue_redraw()

func _draw():
	var h = size.y
	var w = size.x
	draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, 0.20))
	var tick := _tick_interval()
	var top_depth  = _depth - CHARACTER_SCREEN_Y / PIXELS_PER_METER
	var bot_depth  = _depth + (h - CHARACTER_SCREEN_Y) / PIXELS_PER_METER
	var d = floor(top_depth / tick) * tick
	while d <= bot_depth + tick:
		var sy = (d - top_depth) * PIXELS_PER_METER
		if sy >= 0 and sy <= h:
			var is_major = int(d) % int(tick * 5) == 0
			var alpha = 0.45 if is_major else 0.18
			draw_line(Vector2(0, sy), Vector2(w, sy), Color(1, 1, 1, alpha), 1.0)
			if is_major and d >= 0:
				draw_string(_font, Vector2(2, sy - 1), _fmt(d),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.38))
		d += tick
	draw_rect(Rect2(0, CHARACTER_SCREEN_Y - 1, w, 2), Color(1.0, 0.88, 0.25, 0.75))

func _tick_interval() -> float:
	var visible = size.y / PIXELS_PER_METER
	for t in [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000]:
		if float(t) >= visible / 10.0:
			return float(t)
	return 100000.0

func _fmt(d: float) -> String:
	if d < 0: return ""
	if d >= 1_000_000: return "%.1fM" % (d / 1_000_000)
	if d >= 1_000:     return "%.0fK" % (d / 1_000)
	return "%d" % int(d)
