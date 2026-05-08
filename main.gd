extends Node2D

var depth: float = 0.0
var drill_power: float = 1.0
var auto_drill: float = 0.0
var coins: int = 0

var MATERIALS: Array = []
var LAYERS: Array = []
var UPGRADES: Array = []
var purchased: Dictionary = {}

const BASE_DROP_INTERVAL := 12.0
const DROP_DEPTH_SCALE   := 0.018  # +0.018m interval per meter of depth
const RARE_THRESHOLD := 3

var _drop_acc: float = 0.0
var _last_depth: float = 0.0
var _notified: Dictionary = {}

@onready var world_view       = $WorldView
@onready var drill_char       = $DrillLayer/DrillChar
@onready var float_container  = $FloatContainer
@onready var coin_label       = $UI/HUD/VBox/CoinLabel
@onready var depth_label      = $UI/HUD/VBox/DepthLabel
@onready var production_label = $UI/HUD/VBox/ProductionLabel
@onready var layer_label      = $UI/HUD/VBox/LayerLabel
@onready var drill_label      = $UI/HUD/VBox/DrillLabel
@onready var upgrade_list     = $UI/UpgradePanel/ScrollContainer/UpgradeList
@onready var tap_button       = $UI/HUD/TapButton
@onready var shop_button      = $UI/HUD/VBox/ShopButton
@onready var upgrade_panel    = $UI/UpgradePanel
@onready var depth_ruler      = $UI/DepthRuler
@onready var notif_label      = $UI/NotifBanner/NotifLabel
@onready var tunnel_shaft     = $UI/TunnelShaft

func _ready():
	_load_data()
	world_view.setup(LAYERS)
	world_view.rare_collected.connect(_on_rare_collected)
	upgrade_panel.position.x = -640.0
	tap_button.text = "DRILL!"
	shop_button.text = "⚙  SHOP"
	tap_button.pressed.connect(_on_tap)
	shop_button.pressed.connect(_toggle_shop)
	$UI/UpgradePanel/Header/CloseBtn.pressed.connect(_close_shop)
	_build_upgrade_ui()

# ── Data ─────────────────────────────────────────────────────────────────────

func _load_data():
	MATERIALS = _load_json("res://data/materials.json")
	LAYERS    = _load_json("res://data/layers.json")
	UPGRADES  = _load_json("res://data/upgrades.json")

func _load_json(path: String) -> Array:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open: " + path)
		return []
	var r = JSON.parse_string(f.get_as_text())
	f.close()
	return r if r is Array else []

# ── Game loop ─────────────────────────────────────────────────────────────────

func _process(delta):
	if auto_drill > 0:
		depth += auto_drill * delta
	_try_drop(depth - _last_depth)
	_last_depth = depth
	world_view.tick_drops(depth)
	_update_ui()

func _on_tap():
	depth += drill_power
	_try_drop(drill_power)
	drill_char.tap()

# ── Input: click rare minerals ────────────────────────────────────────────────

func _input(event):
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true; pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true; pos = event.position
	if not pressed:
		return
	var local_pos = pos - world_view.global_position
	var result = world_view.check_rare_click(local_pos)
	if not result.is_empty():
		_on_rare_collected(result["mat_id"], result["coin_value"])

func _on_rare_collected(mat_id: String, coin_value: int):
	coins += coin_value
	var sym = _symbol_for(mat_id)
	_spawn_float("%s +%d💰" % [sym, coin_value])

# ── Drop system ───────────────────────────────────────────────────────────────

func _drop_interval() -> float:
	return BASE_DROP_INTERVAL + depth * DROP_DEPTH_SCALE

func _try_drop(meters: float):
	_drop_acc += meters
	var interval = _drop_interval()
	while _drop_acc >= interval:
		_drop_acc -= interval
		interval = _drop_interval()
		_give_material()

func _give_material():
	var layer = _current_layer()
	if layer == null or not layer.has("drops"):
		return
	var drops: Array = layer["drops"]
	var total: float = 0.0
	for e in drops: total += float(e["weight"])
	var roll = randf() * total
	for e in drops:
		roll -= float(e["weight"])
		if roll <= 0.0:
			var mid: String = e["material"]
			var mat = _get_mat(mid)
			if mat == null: return
			var rarity: int = int(mat.get("rarity", 1))
			var cv: int = int(mat.get("coin_value", 1))
			if rarity >= RARE_THRESHOLD:
				var spawn_depth = depth + randf_range(30, 100)
				world_view.spawn_rare_clickable(mid, _symbol_for(mid), rarity, cv, spawn_depth)
			else:
				coins += cv
				_spawn_float("%s +%d💰" % [_symbol_for(mid), cv])
			return

func _current_layer() -> Dictionary:
	var result: Dictionary = LAYERS[0] if LAYERS.size() > 0 else {}
	for layer in LAYERS:
		if depth >= float(layer["min_depth"]):
			result = layer
	return result

# ── Floating labels ───────────────────────────────────────────────────────────

func _spawn_float(text: String):
	var lbl = Label.new()
	lbl.text = text
	lbl.position = Vector2(randf_range(120, 480), 310)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.55, 1.0))
	float_container.add_child(lbl)
	var t = lbl.create_tween()
	t.tween_property(lbl, "position:y", lbl.position.y - 80.0, 1.0)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0)
	t.tween_callback(lbl.queue_free)

# ── Upgrade panel ─────────────────────────────────────────────────────────────

func _toggle_shop():
	if upgrade_panel.position.x > -100:
		_close_shop()
	else:
		_open_shop()

func _open_shop():
	_refresh_upgrade_buttons()
	var t = create_tween()
	t.tween_property(upgrade_panel, "position:x", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)

func _close_shop():
	var t = create_tween()
	t.tween_property(upgrade_panel, "position:x", -640.0, 0.20).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)

# ── Upgrade notification ──────────────────────────────────────────────────────

func _check_notifications():
	for upgrade in UPGRADES:
		var uid: String = upgrade["id"]
		if _notified.get(uid, false): continue
		if purchased.get(uid, false): continue
		if coins >= int(upgrade["cost"]):
			_notified[uid] = true
			_show_notif("⬆  Upgrade ready: %s" % upgrade["name"])
			break

func _show_notif(text: String):
	notif_label.text = text
	var banner = $UI/NotifBanner
	banner.modulate.a = 0.0
	banner.visible = true
	var t = create_tween()
	t.tween_property(banner, "modulate:a", 1.0, 0.3)
	t.tween_interval(3.0)
	t.tween_property(banner, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): banner.visible = false)

# ── UI ────────────────────────────────────────────────────────────────────────

func _update_ui():
	coin_label.text = "💰  %s" % _fmt(coins)
	depth_label.text = "▼  %s m" % _fmt_f(depth)
	production_label.text = "⚡  %s m/s" % _fmt_f(auto_drill)
	layer_label.text = "☰  %s" % _current_layer().get("name", "Surface")
	drill_label.text = "⛏  %s" % _get_drill_name()
	_check_notifications()
	_update_tunnel()
	world_view.scroll_to(depth)
	depth_ruler.update(depth)

const _TUNNEL_X  := 255.0
const _TUNNEL_W  := 90.0
const _CHAR_Y    := 340.0   # drill center on screen
const _DRILL_FOOT := 20.0   # offset from center to bit tip
const _PPM       := 2.0     # pixels per meter

func _update_tunnel():
	# Shaft = already-drilled hole from surface down to drill bit tip.
	# sky (above surface) and the drill character itself are unaffected.
	var surface_screen_y: float = _CHAR_Y - depth * _PPM
	var shaft_top: float    = max(0.0, surface_screen_y)
	var shaft_bottom: float = _CHAR_Y + _DRILL_FOOT
	var shaft_h: float      = max(0.0, shaft_bottom - shaft_top)
	tunnel_shaft.position = Vector2(_TUNNEL_X, shaft_top)
	tunnel_shaft.size     = Vector2(_TUNNEL_W, shaft_h)

func _get_drill_name() -> String:
	var name = "Basic Drill"
	for upg in UPGRADES:
		if upg["type"] == "drill_power" and purchased.get(upg["id"], false):
			name = upg["name"]
	return name

func _build_upgrade_ui():
	for upgrade in UPGRADES:
		var btn = Button.new()
		btn.name = upgrade["id"]
		btn.custom_minimum_size = Vector2(0, 52)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.pressed.connect(_on_upgrade_pressed.bind(upgrade))
		upgrade_list.add_child(btn)

func _visible_upgrade_ids() -> Array:
	var by_type: Dictionary = {}
	for upg in UPGRADES:
		if not by_type.has(upg["type"]): by_type[upg["type"]] = []
		by_type[upg["type"]].append(upg)
	var visible: Array = []
	for type_key in by_type:
		var showed_locked := false
		for upg in by_type[type_key]:
			if purchased.get(upg["id"], false): continue
			if coins >= int(upg["cost"]):
				visible.append(upg["id"])
			elif not showed_locked:
				visible.append(upg["id"])
				showed_locked = true
	return visible

func _refresh_upgrade_buttons():
	var vis = _visible_upgrade_ids()
	for upgrade in UPGRADES:
		var btn = upgrade_list.get_node_or_null(upgrade["id"])
		if btn == null: continue
		btn.visible = upgrade["id"] in vis
		if not btn.visible: continue
		var cost: int = int(upgrade["cost"])
		if coins >= cost:
			btn.text = "%s  %s\n💰 %s" % [upgrade["name"], upgrade["desc"], _fmt(cost)]
			btn.disabled = false
		else:
			btn.text = "🔒 %s\nNeed 💰 %s  (have %s)" % [upgrade["name"], _fmt(cost), _fmt(coins)]
			btn.disabled = true

func _on_upgrade_pressed(upgrade: Dictionary):
	var cost: int = int(upgrade["cost"])
	if coins < cost: return
	coins -= cost
	purchased[upgrade["id"]] = true
	match upgrade["type"]:
		"drill_power": drill_power += float(upgrade["value"])
		"auto_drill":  auto_drill  += float(upgrade["value"])
	_refresh_upgrade_buttons()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _symbol_for(mat_id: String) -> String:
	var mat = _get_mat(mat_id)
	return mat["symbol"] if mat else "?"

func _get_mat(mat_id: String):
	for mat in MATERIALS:
		if mat["id"] == mat_id: return mat
	return null

func _fmt(n: int) -> String:
	if n >= 1_000_000_000: return "%.1fB" % (float(n) / 1_000_000_000)
	if n >= 1_000_000:     return "%.1fM" % (float(n) / 1_000_000)
	if n >= 1_000:         return "%.1fK" % (float(n) / 1_000)
	return str(n)

func _fmt_f(n: float) -> String:
	if n >= 1_000_000_000: return "%.1fB" % (n / 1_000_000_000)
	if n >= 1_000_000:     return "%.1fM" % (n / 1_000_000)
	if n >= 1_000:         return "%.1fK" % (n / 1_000)
	return "%.1f" % n
