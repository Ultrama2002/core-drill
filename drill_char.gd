extends Node2D

var _bounce := 0.0

func tap():
	_bounce = -10.0

func _process(delta):
	if abs(_bounce) > 0.1:
		_bounce = move_toward(_bounce, 0.0, 90.0 * delta)
		queue_redraw()

func _draw():
	var b = _bounce

	# Treads
	draw_rect(Rect2(-18, -22 + b, 4, 22), Color(0.30, 0.30, 0.35))
	draw_rect(Rect2(14, -22 + b, 4, 22), Color(0.30, 0.30, 0.35))

	# Body
	draw_rect(Rect2(-14, -32 + b, 28, 32), Color(0.50, 0.52, 0.65))

	# Cockpit window
	draw_rect(Rect2(-8, -28 + b, 16, 13), Color(0.25, 0.75, 1.0, 0.85))

	# Drill bit
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, b),
		Vector2(9, b),
		Vector2(0, b + 18)
	]), Color(0.90, 0.70, 0.15))

	# Highlight on bit
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2, b),
		Vector2(2, b),
		Vector2(0, b + 8)
	]), Color(1.0, 0.95, 0.60, 0.6))
