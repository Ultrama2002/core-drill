extends ColorRect

@onready var layer_label: Label = $LayerLabel

var _current_index := -1

func update(depth: float, layers: Array):
	if layers.is_empty():
		return

	var idx := 0
	for i in layers.size():
		if depth >= float(layers[i]["min_depth"]):
			idx = i

	if idx == _current_index:
		return
	_current_index = idx

	var layer = layers[idx]
	var c = layer["bg_color"]
	var target_color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)

	var tween = create_tween()
	tween.tween_property(self, "color", target_color, 0.6)
	layer_label.text = layer["name"]
