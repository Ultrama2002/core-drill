extends Node2D

const PIXELS_PER_METER := 2.0
const CHARACTER_SCREEN_Y := 340.0
const RARE_MISS_MARGIN := 180.0

signal rare_collected(mat_id: String, coin_value: int)

var _rares: Array = []

func setup(layers: Array):
	var sky = ColorRect.new()
	sky.color = Color(0.35, 0.65, 0.95)
	sky.position = Vector2(-20, -50000.0 * PIXELS_PER_METER)
	sky.size = Vector2(680, 50000.0 * PIXELS_PER_METER)
	add_child(sky)

	for i in layers.size():
		var layer = layers[i]
		var band = ColorRect.new()
		var c = layer["bg_color"]
		band.color = Color(c[0], c[1], c[2], 1.0)
		band.position = Vector2(-20, float(layer["min_depth"]) * PIXELS_PER_METER)
		var next_depth = float(layers[i + 1]["min_depth"]) if i + 1 < layers.size() else 999_999_999.0
		band.size = Vector2(680, (next_depth - float(layer["min_depth"])) * PIXELS_PER_METER)
		add_child(band)

func scroll_to(depth: float):
	position.y = -depth * PIXELS_PER_METER + CHARACTER_SCREEN_Y

func spawn_rare_clickable(mat_id: String, symbol: String, rarity: int, coin_value: int, trigger_depth: float):
	var container = Node2D.new()
	container.position = Vector2(randf_range(80, 520), trigger_depth * PIXELS_PER_METER)

	var sz = float(24 + rarity * 5)
	var glow = ColorRect.new()
	glow.size = Vector2(sz, sz)
	glow.position = Vector2(-sz * 0.5, -sz * 0.5)
	glow.color = Color(1.0, 0.85, 0.1, 0.20 + rarity * 0.06)
	container.add_child(glow)

	var lbl = Label.new()
	lbl.text = symbol
	lbl.add_theme_font_size_override("font_size", 20 + rarity * 2)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.position = Vector2(-11, -13)
	container.add_child(lbl)

	var coins_lbl = Label.new()
	coins_lbl.text = "+%d" % coin_value
	coins_lbl.add_theme_font_size_override("font_size", 10)
	coins_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 0.9))
	coins_lbl.position = Vector2(-8, 10)
	container.add_child(coins_lbl)

	var t = container.create_tween().set_loops()
	t.tween_property(container, "scale", Vector2(1.15, 1.15), 0.5)
	t.tween_property(container, "scale", Vector2(1.0, 1.0), 0.5)

	add_child(container)
	_rares.append({"node": container, "mat_id": mat_id, "coin_value": coin_value, "depth": trigger_depth})

func check_rare_click(local_pos: Vector2) -> Dictionary:
	for item in _rares.duplicate():
		if local_pos.distance_to(item["node"].position) < 35:
			_collect_rare(item)
			return {"mat_id": item["mat_id"], "coin_value": item["coin_value"]}
	return {}

func _collect_rare(item: Dictionary):
	var node = item["node"]
	_rares.erase(item)
	var t = node.create_tween()
	t.tween_property(node, "scale", Vector2(2.2, 2.2), 0.14)
	t.parallel().tween_property(node, "modulate:a", 0.0, 0.22)
	t.tween_callback(node.queue_free)

func tick_drops(current_depth: float):
	for item in _rares.duplicate():
		if current_depth > item["depth"] + RARE_MISS_MARGIN:
			item["node"].queue_free()
			_rares.erase(item)
