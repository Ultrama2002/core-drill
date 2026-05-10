extends Node2D

var depth: float = 0.0
var drill_power: float = 1.0
var auto_drill: float = 0.0
var coins: int = 0

var energy: int = 100
var max_energy: int = 100
var energy_regen_rate: float = 10.0   # seconds per energy point (base = 10s)
var _energy_acc: float = 0.0

var MATERIALS: Array = []
var LAYERS: Array = []
var UPGRADES: Array = []
var purchased: Dictionary = {}

const BASE_DROP_INTERVAL := 12.0
const DROP_DEPTH_SCALE   := 0.018
const RARE_THRESHOLD := 3

var _drop_acc: float = 0.0
var _last_depth: float = 0.0
var _notified: Dictionary = {}
var _last_layer_name: String = ""

# ── Intro animation ───────────────────────────────────────────────────────────
var _intro_playing: bool  = false
var _intro_depth:   float = 0.0

# ── Translation system (manual CSV parser — no Godot import needed) ───────────
var _translations: Dictionary = {}   # { "en": { "BTN_DRILL": "DRILL!", ... }, ... }
var _current_locale: String = "en"

func _load_translations() -> void:
	var f = FileAccess.open("res://translations.csv", FileAccess.READ)
	if f == null:
		push_error("translations.csv not found")
		return
	var header: Array = Array(f.get_csv_line())
	# header[0] = "keys", header[1..] = locale codes
	var locales: Array = header.slice(1)
	for loc in locales:
		_translations[loc] = {}
	while not f.eof_reached():
		var row: Array = Array(f.get_csv_line())
		if row.size() < 2 or row[0].strip_edges().is_empty():
			continue
		var key: String = row[0].strip_edges()
		for i in locales.size():
			if i + 1 < row.size():
				_translations[locales[i]][key] = row[i + 1]
	f.close()

func _tr(key: String) -> String:
	var val: String = _translations.get(_current_locale, {}).get(key, "")
	if val.is_empty():
		val = _translations.get("en", {}).get(key, key)
	return val

# ── Button textures ───────────────────────────────────────────────────────────

func _make_sb(tex: Texture2D, margin: int, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture               = tex
	sb.texture_margin_left   = margin
	sb.texture_margin_right  = margin
	sb.texture_margin_top    = margin
	sb.texture_margin_bottom = margin
	sb.modulate_color        = tint
	# Márgenes de contenido iguales → texto perfectamente centrado
	sb.content_margin_left   = 6.0
	sb.content_margin_right  = 6.0
	sb.content_margin_top    = 4.0
	sb.content_margin_bottom = 4.0
	return sb

func _style_menu_btn(btn: Button, tex_n: Texture2D, tex_p: Texture2D) -> void:
	# Acero gastado — tono cálido grisáceo, coherente con paleta industrial
	btn.add_theme_stylebox_override("normal",   _make_sb(tex_n, 10, Color(0.88, 0.82, 0.72, 1.0)))
	btn.add_theme_stylebox_override("hover",    _make_sb(tex_n, 10, Color(1.02, 0.96, 0.84, 1.0)))
	btn.add_theme_stylebox_override("pressed",  _make_sb(tex_p, 10, Color(0.72, 0.66, 0.58, 1.0)))
	btn.add_theme_stylebox_override("disabled", _make_sb(tex_n, 10, Color(0.48, 0.44, 0.40, 0.75)))
	btn.add_theme_color_override("font_color",          Color(0.13, 0.10, 0.06, 1.0))
	btn.add_theme_color_override("font_hover_color",    Color(0.08, 0.06, 0.04, 1.0))
	btn.add_theme_color_override("font_pressed_color",  Color(0.05, 0.03, 0.01, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.38, 0.34, 0.30, 0.9))

func _style_danger_btn(btn: Button, tex_n: Texture2D, tex_p: Texture2D) -> void:
	# Señal de peligro industrial — rojo ladrillo muy desaturado
	btn.add_theme_stylebox_override("normal",   _make_sb(tex_n, 10, Color(0.82, 0.40, 0.32, 1.0)))
	btn.add_theme_stylebox_override("hover",    _make_sb(tex_n, 10, Color(0.96, 0.48, 0.38, 1.0)))
	btn.add_theme_stylebox_override("pressed",  _make_sb(tex_p, 10, Color(0.64, 0.30, 0.24, 1.0)))
	btn.add_theme_stylebox_override("disabled", _make_sb(tex_n, 10, Color(0.44, 0.30, 0.28, 0.75)))
	btn.add_theme_color_override("font_color",          Color(0.92, 0.84, 0.82, 1.0))
	btn.add_theme_color_override("font_hover_color",    Color(0.98, 0.92, 0.90, 1.0))
	btn.add_theme_color_override("font_pressed_color",  Color(0.85, 0.76, 0.74, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.46, 0.44, 0.9))

func _setup_hud_panel(panel: PanelContainer, tex: Texture2D, tint: Color) -> void:
	var sb := StyleBoxTexture.new()
	sb.texture               = tex
	sb.texture_margin_left   = 8
	sb.texture_margin_right  = 8
	sb.texture_margin_top    = 8
	sb.texture_margin_bottom = 8
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 4   # +2px respecto al anterior → texto un poco más abajo
	sb.content_margin_bottom = 12  # sombra compensada
	sb.modulate_color        = tint
	panel.add_theme_stylebox_override("panel", sb)

# Recorre recursivamente un nodo y tinta todos los Labels con el color dado
func _tint_panel_labels(node: Node, color: Color) -> void:
	for child in node.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", color)
		_tint_panel_labels(child, color)

# Envuelve un Label en HBoxContainer con un TextureRect icono a su izquierda
func _add_icon_inline(label: Label, tex: Texture2D, tint: Color, icon_px: int = 18) -> void:
	if tex == null or not is_instance_valid(label):
		return
	var parent := label.get_parent()
	var idx    := label.get_index()
	var hbox   := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 5)
	parent.add_child(hbox)
	parent.move_child(hbox, idx)
	var tr := TextureRect.new()
	tr.texture             = tex
	tr.custom_minimum_size = Vector2(icon_px, icon_px)
	tr.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate            = tint
	hbox.add_child(tr)
	label.reparent(hbox)
	hbox.move_child(tr, 0)   # ícono siempre antes del texto

func _setup_bar(bar: ProgressBar, fill_color: Color, bg_color: Color, overlay_tex: Texture2D) -> void:
	# Fondo (zona vacía) — color sólido oscuro
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = bg_color
	bg_sb.corner_radius_top_left     = 3
	bg_sb.corner_radius_top_right    = 3
	bg_sb.corner_radius_bottom_left  = 3
	bg_sb.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bg_sb)

	# Relleno (zona llena) — color sólido vivo
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill_color
	fill_sb.corner_radius_top_left     = 3
	fill_sb.corner_radius_top_right    = 3
	fill_sb.corner_radius_bottom_left  = 3
	fill_sb.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", fill_sb)

	# NinePatchRect encima como overlay — sin deformación
	if overlay_tex:
		var np := NinePatchRect.new()
		np.texture              = overlay_tex
		np.patch_margin_left    = 6
		np.patch_margin_right   = 6
		np.patch_margin_top     = 3
		np.patch_margin_bottom  = 3
		np.layout_mode          = 1
		np.set_anchors_preset(Control.PRESET_FULL_RECT)
		np.grow_horizontal      = Control.GROW_DIRECTION_BOTH
		np.grow_vertical        = Control.GROW_DIRECTION_BOTH
		np.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		bar.add_child(np)

func _apply_menu_bg(panel: Control, tex: Texture2D) -> void:
	# Oculta el ColorRect "BG" hijo si existe (paneles deslizantes)
	var old_bg = panel.get_node_or_null("BG")
	if old_bg:
		old_bg.hide()
	var tr := TextureRect.new()
	tr.texture         = tex
	tr.layout_mode     = 1
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tr.grow_vertical   = Control.GROW_DIRECTION_BOTH
	tr.stretch_mode    = TextureRect.STRETCH_SCALE
	tr.modulate        = Color(0.48, 0.45, 0.42, 1.0)  # fondo oscuro
	panel.add_child(tr)
	panel.move_child(tr, 0)   # detrás de todo

func _setup_ui_style() -> void:
	var tex_drill_n: Texture2D = load("res://assets/UI/DrillBTN.png")
	var tex_drill_p: Texture2D = load("res://assets/UI/DrillBTNPressed.png")
	var tex_menu_n:  Texture2D = load("res://assets/UI/MenuBTN.png")
	var tex_menu_p:  Texture2D = load("res://assets/UI/MenuBTNPressed.png")
	var tex_side_bg:    Texture2D = load("res://assets/UI/SideMenu.png")
	var tex_options_bg: Texture2D = load("res://assets/UI/OptionsMenu.png")

	# ── Drill button ──────────────────────────────────────────────────────────
	if tex_drill_n and tex_drill_p:
		tap_button.add_theme_stylebox_override("normal",   _make_sb(tex_drill_n, 12, Color(1.0, 1.0, 1.0, 1.0)))
		tap_button.add_theme_stylebox_override("hover",    _make_sb(tex_drill_n, 12, Color(1.1, 1.1, 1.1, 1.0)))
		tap_button.add_theme_stylebox_override("pressed",  _make_sb(tex_drill_p, 12, Color(1.0, 1.0, 1.0, 1.0)))
		tap_button.add_theme_stylebox_override("disabled", _make_sb(tex_drill_n, 12, Color(0.45, 0.40, 0.35, 0.7)))
		tap_button.add_theme_color_override("font_color",          Color(0.10, 0.07, 0.05, 1.0))
		tap_button.add_theme_color_override("font_hover_color",    Color(0.05, 0.05, 0.10, 1.0))
		tap_button.add_theme_color_override("font_pressed_color",  Color(0.00, 0.00, 0.00, 1.0))
		tap_button.add_theme_color_override("font_disabled_color", Color(0.40, 0.35, 0.30, 0.8))

	# ── Fondos ───────────────────────────────────────────────────────────────
	# SideMenu.png → HUD derecho (profundidad, coins, energía, botones)
	if tex_side_bg:
		var hud := $UI/HUD as ColorRect
		hud.color = Color(0.0, 0.0, 0.0, 0.0)   # transparentar el rect base
		_apply_menu_bg(hud, tex_side_bg)

	# OptionsMenu.png → panel de configuración
	if tex_options_bg:
		_apply_menu_bg(settings_panel, tex_options_bg)

	# ── Botones de menú ───────────────────────────────────────────────────────
	if tex_menu_n and tex_menu_p:
		_style_menu_btn(shop_button,     tex_menu_n, tex_menu_p)
		_style_menu_btn(settings_button, tex_menu_n, tex_menu_p)
		for btn_name in ["BtnEN", "BtnES", "BtnZH", "BtnPT", "BtnFR", "BtnDE"]:
			var btn = $UI/SettingsPanel/Content/LangRow.get_node_or_null(btn_name)
			if btn:
				_style_menu_btn(btn, tex_menu_n, tex_menu_p)
		for child in upgrade_list.get_children():
			if child is Button:
				_style_menu_btn(child, tex_menu_n, tex_menu_p)

		# Rojos: cerrar y salir
		_style_danger_btn($UI/SettingsPanel/Content/ExitBtn, tex_menu_n, tex_menu_p)
		_style_danger_btn($UI/UpgradePanel/Header/CloseBtn,  tex_menu_n, tex_menu_p)
		_style_danger_btn($UI/SettingsPanel/Header/CloseBtn, tex_menu_n, tex_menu_p)

	# ── Barras de energía: color plano abajo + PNG encima como overlay ────────
	var tex_ebar:  Texture2D = load("res://assets/UI/EnergyBar.png")
	var tex_rebar: Texture2D = load("res://assets/UI/RecharchBar.png")

	_setup_bar(energy_bar,  Color(0.15, 0.88, 0.28, 1.0), Color(0.04, 0.18, 0.07, 0.9), tex_ebar)
	_setup_bar(energy_timer, Color(1.00, 0.82, 0.08, 1.0), Color(0.18, 0.14, 0.03, 0.9), tex_rebar)

	# ── Frames del HUD (9-slice con Coins.png tintado por sección) ───────────
	var tex_coins: Texture2D = load("res://assets/UI/Coins.png")
	if tex_coins:
		# Paleta industrial: latón envejecido / acero pizarra / óxido / cobre gastado
		var c_brass  := Color(0.82, 0.66, 0.30, 1.0)   # latón — panel monedas
		var c_steel  := Color(0.48, 0.58, 0.72, 1.0)   # acero pizarra — panel profundidad
		var c_rust   := Color(0.70, 0.50, 0.32, 1.0)   # óxido hierro — panel capa
		var c_copper := Color(0.78, 0.44, 0.20, 1.0)   # cobre gastado — panel energía

		_setup_hud_panel($UI/HUD/VBox/CoinPanel,   tex_coins, c_brass)
		_setup_hud_panel($UI/HUD/VBox/DepthPanel,  tex_coins, c_steel)
		_setup_hud_panel($UI/HUD/VBox/LayerPanel,  tex_coins, c_rust)
		_setup_hud_panel($UI/HUD/VBox/EnergyPanel, tex_coins, c_copper)

		# Texto = color de base del panel oscurecido ~50% → misma familia de tono, sin contraste agresivo
		_tint_panel_labels($UI/HUD/VBox/CoinPanel,   c_brass.darkened(0.50))
		_tint_panel_labels($UI/HUD/VBox/DepthPanel,  c_steel.darkened(0.50))
		_tint_panel_labels($UI/HUD/VBox/LayerPanel,  c_rust.darkened(0.50))
		_tint_panel_labels($UI/HUD/VBox/EnergyPanel, c_copper.darkened(0.50))

		# Íconos HUD — mismo tono oscurecido que el texto del panel
		var tex_coins_icon: Texture2D = load("res://assets/UI/CoinsIcon..png")
		var tex_depth_icon: Texture2D = load("res://assets/UI/DepthIcon..png")
		_add_icon_inline(coin_label,  tex_coins_icon, c_brass.darkened(0.50),  20)
		_add_icon_inline(depth_label, tex_depth_icon, c_steel.darkened(0.50),  18)

	# Íconos panel de configuración — tono neutro cálido sobre fondo oscuro
	var tex_config_icon: Texture2D = load("res://assets/UI/ConfigIcon..png")
	var tex_volume_icon: Texture2D = load("res://assets/UI/VolumeIcon..png")
	var tex_music_icon:  Texture2D = load("res://assets/UI/sprite_png/Music.png")
	var settings_tint := Color(0.80, 0.74, 0.62, 1.0)   # latón suave sobre fondo oscuro
	_add_icon_inline($UI/SettingsPanel/Header/TitleLabel,    tex_config_icon, settings_tint, 20)
	_add_icon_inline($UI/SettingsPanel/Content/VolumeTitle,  tex_volume_icon, settings_tint, 16)
	_add_icon_inline(music_label,                            tex_music_icon,  settings_tint, 14)

	# ── Sliders de volumen ────────────────────────────────────────────────────
	_setup_sliders()

	# (barras de energía configuradas en _setup_ui_style via _setup_bar)

# ── Sliders de volumen ───────────────────────────────────────────────────────

func _setup_sliders() -> void:
	var tex_track: Texture2D = load("res://assets/UI/Slide.png")
	var tex_grab:  Texture2D = load("res://assets/UI/SlideBTN.png")

	for slider in [master_slider, music_slider, sfx_slider]:
		slider.custom_minimum_size = Vector2(0, 28)

		if tex_track:
			# Riel de fondo (zona vacía)
			var track_sb := StyleBoxTexture.new()
			track_sb.texture               = tex_track
			track_sb.texture_margin_left   = 6
			track_sb.texture_margin_right  = 6
			track_sb.texture_margin_top    = 6
			track_sb.texture_margin_bottom = 6
			track_sb.modulate_color        = Color(0.40, 0.36, 0.30, 1.0)  # acero oscuro
			slider.add_theme_stylebox_override("slider", track_sb)

			# Zona rellenada (izquierda del grabber) — latón industrial
			var fill_sb := StyleBoxTexture.new()
			fill_sb.texture               = tex_track
			fill_sb.texture_margin_left   = 6
			fill_sb.texture_margin_right  = 6
			fill_sb.texture_margin_top    = 6
			fill_sb.texture_margin_bottom = 6
			fill_sb.modulate_color        = Color(0.90, 0.72, 0.28, 1.0)  # latón envejecido
			slider.add_theme_stylebox_override("grabber_area",           fill_sb)
			slider.add_theme_stylebox_override("grabber_area_highlight", fill_sb)

		if tex_grab:
			slider.add_theme_icon_override("grabber",           tex_grab)
			slider.add_theme_icon_override("grabber_highlight", tex_grab)
			slider.add_theme_icon_override("grabber_disabled",  tex_grab)

# ── Fuente retro ─────────────────────────────────────────────────────────────

func _fnt(node: Control, size: int, font: Font) -> void:
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", size)

func _setup_font() -> void:
	var font: Font = load("res://assets/fonts/PressStart2P-Regular.ttf")
	if font == null:
		return

	# HUD labels
	_fnt(coin_label,       13, font)
	_fnt(depth_label,      11, font)
	_fnt(production_label, 10, font)
	_fnt(layer_label,      10, font)
	_fnt(drill_label,      10, font)
	_fnt(energy_label,     10, font)
	_fnt(next_layer_label, 10, font)

	# HUD buttons
	_fnt(tap_button,       13, font)
	_fnt(shop_button,      10, font)
	_fnt(settings_button,  10, font)

	# UpgradePanel
	_fnt($UI/UpgradePanel/Header/TitleLabel, 12, font)
	_fnt($UI/UpgradePanel/Header/CloseBtn,   12, font)
	for child in upgrade_list.get_children():
		if child is Button:
			_fnt(child, 10, font)

	# SettingsPanel
	_fnt($UI/SettingsPanel/Header/TitleLabel,      12, font)
	_fnt($UI/SettingsPanel/Header/CloseBtn,        12, font)
	_fnt($UI/SettingsPanel/Content/VolumeTitle,    11, font)
	_fnt(master_label,                             10, font)
	_fnt(music_label,                              10, font)
	_fnt(sfx_label,                                10, font)
	_fnt($UI/SettingsPanel/Content/LangTitle,      11, font)
	_fnt($UI/SettingsPanel/Content/ExitBtn,        10, font)
	for btn_name in ["BtnEN", "BtnES", "BtnZH", "BtnPT", "BtnFR", "BtnDE"]:
		var btn = $UI/SettingsPanel/Content/LangRow.get_node_or_null(btn_name)
		if btn:
			_fnt(btn, 10, font)

# ── Localization ──────────────────────────────────────────────────────────────

func _refresh_static_ui() -> void:
	tap_button.text      = _tr("BTN_DRILL")
	shop_button.text     = _tr("BTN_SHOP")
	settings_button.text = _tr("BTN_SETTINGS")
	$UI/SettingsPanel/Content/ExitBtn.text             = _tr("BTN_EXIT")
	$UI/UpgradePanel/Header/TitleLabel.text             = _tr("TITLE_UPGRADES")
	$UI/SettingsPanel/Header/TitleLabel.text            = _tr("TITLE_SETTINGS")
	$UI/SettingsPanel/Content/VolumeTitle.text          = _tr("SETTINGS_VOLUME")
	$UI/SettingsPanel/Content/LangTitle.text            = _tr("SETTINGS_LANG")
	master_label.text = _tr("VOL_MASTER").format([int(master_slider.value)])
	music_label.text  = _tr("VOL_MUSIC").format([int(music_slider.value)])
	sfx_label.text    = _tr("VOL_SFX").format([int(sfx_slider.value)])

func _set_lang(locale: String) -> void:
	_current_locale = locale
	_refresh_static_ui()

# ── @onready refs ─────────────────────────────────────────────────────────────

@onready var bg_music      = $BGMusic
@onready var sfx_drill     = $SfxDrill
@onready var sfx_coin      = $SfxCoin
@onready var sfx_upgrade   = $SfxUpgrade
@onready var sfx_noenergy  = $SfxNoEnergy
@onready var sfx_newlayer  = $SfxNewLayer
@onready var sfx_blip      = $SfxBlip

@onready var world_view       = $WorldView
@onready var drill_char       = $DrillLayer/DrillChar
@onready var float_container  = $FloatContainer
@onready var coin_label       = $UI/HUD/VBox/CoinPanel/CoinLabel
@onready var depth_label      = $UI/HUD/VBox/DepthPanel/DepthVBox/DepthLabel
@onready var production_label = $UI/HUD/VBox/DepthPanel/DepthVBox/ProductionLabel
@onready var layer_label      = $UI/HUD/VBox/LayerPanel/LayerVBox/LayerLabel
@onready var drill_label      = $UI/HUD/VBox/LayerPanel/LayerVBox/DrillLabel
@onready var energy_label     = $UI/HUD/VBox/EnergyPanel/EnergyVBox/EnergyLabel
@onready var energy_bar       = $UI/HUD/VBox/EnergyPanel/EnergyVBox/EnergyBar
@onready var energy_timer     = $UI/HUD/VBox/EnergyPanel/EnergyVBox/EnergyTimer
@onready var next_layer_label = $UI/HUD/VBox/EnergyPanel/EnergyVBox/NextLayerLabel
@onready var settings_button  = $UI/HUD/VBox/SettingsButton
@onready var settings_panel   = $UI/SettingsPanel
@onready var master_label     = $UI/SettingsPanel/Content/MasterLabel
@onready var master_slider    = $UI/SettingsPanel/Content/MasterSlider
@onready var music_label      = $UI/SettingsPanel/Content/MusicLabel
@onready var music_slider     = $UI/SettingsPanel/Content/MusicSlider
@onready var sfx_label        = $UI/SettingsPanel/Content/SFXLabel
@onready var sfx_slider       = $UI/SettingsPanel/Content/SFXSlider
@onready var upgrade_list     = $UI/UpgradePanel/ScrollContainer/UpgradeList
@onready var tap_button       = $UI/HUD/TapButton
@onready var shop_button      = $UI/HUD/VBox/ShopButton
@onready var upgrade_panel    = $UI/UpgradePanel
@onready var depth_ruler      = $UI/DepthRuler
@onready var notif_label      = $UI/NotifBanner/NotifLabel
@onready var tunnel_shaft     = $TunnelLayer/TunnelShaft

func _ready():
	_load_translations()
	_load_data()
	_setup_audio()
	world_view.setup(LAYERS)
	world_view.rare_collected.connect(_on_rare_collected)
	upgrade_panel.position.x  = -640.0
	settings_panel.position.x = -640.0
	tap_button.pressed.connect(_on_tap)
	shop_button.pressed.connect(_toggle_shop)
	settings_button.pressed.connect(_toggle_settings)
	$UI/UpgradePanel/Header/CloseBtn.pressed.connect(_close_shop)
	$UI/SettingsPanel/Header/CloseBtn.pressed.connect(_close_settings)
	_build_upgrade_ui()
	_setup_ui_style()
	_setup_font()
	_refresh_static_ui()
	_play_intro()

# ── Audio ────────────────────────────────────────────────────────────────────

func _setup_audio():
	var music: AudioStreamMP3 = load("res://assets/ost/Lv1.mp3")
	music.loop = true
	bg_music.stream = music
	bg_music.play()

	sfx_drill.stream    = load("res://assets/SFX/ManualDrill1.wav")
	sfx_coin.stream     = load("res://assets/SFX/pickupCoin.wav")
	sfx_upgrade.stream  = load("res://assets/SFX/powerUp.wav")
	sfx_noenergy.stream = load("res://assets/SFX/noBattery.wav")
	sfx_newlayer.stream = load("res://assets/SFX/nextLevel.wav")
	sfx_blip.stream     = load("res://assets/SFX/blipSelect.wav")

	# Blip on all UI buttons
	shop_button.pressed.connect(func(): sfx_blip.play())
	settings_button.pressed.connect(func(): sfx_blip.play())
	$UI/UpgradePanel/Header/CloseBtn.pressed.connect(func(): sfx_blip.play())
	$UI/SettingsPanel/Header/CloseBtn.pressed.connect(func(): sfx_blip.play())

	# Volume sliders
	master_slider.value_changed.connect(_on_master_volume)
	music_slider.value_changed.connect(_on_music_volume)
	sfx_slider.value_changed.connect(_on_sfx_volume)
	_on_master_volume(master_slider.value)
	_on_music_volume(music_slider.value)
	_on_sfx_volume(sfx_slider.value)

	# Language buttons
	$UI/SettingsPanel/Content/LangRow/BtnEN.pressed.connect(func(): _set_lang("en"))
	$UI/SettingsPanel/Content/LangRow/BtnES.pressed.connect(func(): _set_lang("es"))
	$UI/SettingsPanel/Content/LangRow/BtnZH.pressed.connect(func(): _set_lang("zh"))
	$UI/SettingsPanel/Content/LangRow/BtnPT.pressed.connect(func(): _set_lang("pt"))
	$UI/SettingsPanel/Content/LangRow/BtnFR.pressed.connect(func(): _set_lang("fr"))
	$UI/SettingsPanel/Content/LangRow/BtnDE.pressed.connect(func(): _set_lang("de"))

	# Exit
	$UI/SettingsPanel/Content/ExitBtn.pressed.connect(func(): get_tree().quit())

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
	# Energy regen
	if energy < max_energy:
		_energy_acc += delta
		if _energy_acc >= energy_regen_rate:
			_energy_acc -= energy_regen_rate
			energy = min(energy + 1, max_energy)
	_try_drop(depth - _last_depth)
	_last_depth = depth
	world_view.tick_drops(depth)
	_update_ui()

func _on_tap():
	if energy <= 0:
		sfx_noenergy.play()
		return
	energy -= 1
	depth += drill_power
	_try_drop(drill_power)
	drill_char.tap()
	sfx_drill.play()

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
	_spawn_float("%s +%d" % [sym, coin_value])
	sfx_coin.play()

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
				_spawn_float("%s +%d" % [_symbol_for(mid), cv])
				sfx_coin.play()
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
	_close_settings()          # ← close settings first so they never overlap
	_refresh_upgrade_buttons()
	var t = create_tween()
	t.tween_property(upgrade_panel, "position:x", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)

func _close_shop():
	var t = create_tween()
	t.tween_property(upgrade_panel, "position:x", -640.0, 0.20).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)

# ── Settings panel ────────────────────────────────────────────────────────────

func _toggle_settings():
	if settings_panel.position.x > -100:
		_close_settings()
	else:
		_open_settings()

func _open_settings():
	_close_shop()              # ← close shop first so they never overlap
	var t = create_tween()
	t.tween_property(settings_panel, "position:x", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)

func _close_settings():
	var t = create_tween()
	t.tween_property(settings_panel, "position:x", -640.0, 0.20).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)

# ── Volume ────────────────────────────────────────────────────────────────────

func _vol_to_db(v: float) -> float:
	return linear_to_db(v / 100.0) if v > 0.0 else -80.0

func _on_master_volume(v: float):
	AudioServer.set_bus_volume_db(0, _vol_to_db(v))
	master_label.text = _tr("VOL_MASTER").format([int(v)])

func _on_music_volume(v: float):
	bg_music.volume_db = _vol_to_db(v)
	music_label.text = _tr("VOL_MUSIC").format([int(v)])

func _on_sfx_volume(v: float):
	var db: float = _vol_to_db(v)
	for p in [sfx_drill, sfx_coin, sfx_upgrade, sfx_noenergy, sfx_newlayer, sfx_blip]:
		p.volume_db = db
	sfx_label.text = _tr("VOL_SFX").format([int(v)])

# ── Upgrade notification ──────────────────────────────────────────────────────

func _check_notifications():
	for upgrade in UPGRADES:
		var uid: String = upgrade["id"]
		if _notified.get(uid, false): continue
		if purchased.get(uid, false): continue
		if coins >= int(upgrade["cost"]):
			_notified[uid] = true
			_show_notif("Upgrade ready: %s" % upgrade["name"])
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
	coin_label.text = "%s" % _fmt(coins)
	depth_label.text = "%s m" % _fmt_f(depth)
	production_label.text = "%s m/s" % _fmt_f(auto_drill)
	var layer_name: String = _current_layer().get("name", "Surface")
	if layer_name != _last_layer_name and _last_layer_name != "":
		sfx_newlayer.play()
	_last_layer_name = layer_name
	var layer_key: String = layer_name.to_upper().replace(" ", "_")
	layer_label.text = _tr(layer_key)
	drill_label.text = _get_drill_name()
	energy_label.text = "%d / %d" % [energy, max_energy]
	energy_bar.max_value = max_energy
	energy_bar.value = energy
	tap_button.disabled = (energy <= 0)
	# Yellow regen bar: full when waiting, empty when energy is full
	if energy >= max_energy:
		energy_timer.value = 0.0
	else:
		energy_timer.value = 100.0 * (1.0 - _energy_acc / energy_regen_rate)

	# Meters to next layer
	var next_depth: float = -1.0
	for layer in LAYERS:
		var ld: float = float(layer["min_depth"])
		if ld > depth:
			if next_depth < 0.0 or ld < next_depth:
				next_depth = ld
	if next_depth > 0.0:
		next_layer_label.text = "%s m" % _fmt_f(next_depth - depth)
	else:
		next_layer_label.text = "MAX"

	_check_notifications()
	_update_tunnel()
	var _scroll_d: float = _intro_depth if _intro_playing else depth
	world_view.scroll_to(_scroll_d)
	depth_ruler.update(_scroll_d)

const _TUNNEL_X   := 255.0
const _TUNNEL_W   := 90.0
const _CHAR_Y     := 340.0
const _DRILL_FOOT := 20.0
const _PPM        := 2.0

func _update_tunnel():
	var d: float = _intro_depth if _intro_playing else depth
	var surface_screen_y: float = _CHAR_Y - d * _PPM
	var shaft_top: float    = max(0.0, surface_screen_y - 32.0)
	var shaft_bottom: float = _CHAR_Y + _DRILL_FOOT
	var shaft_h: float      = max(0.0, shaft_bottom - shaft_top)
	tunnel_shaft.set_shaft(Vector2(_TUNNEL_X, shaft_top), _TUNNEL_W, shaft_h)

func _get_drill_name() -> String:
	var name = "Basic Drill"
	for upg in UPGRADES:
		if upg["type"] == "drill_power" and purchased.get(upg["id"], false):
			name = upg["name"]
	return name

func _play_intro() -> void:
	_intro_playing = true
	_intro_depth   = 0.0

	# Overlay negro que cubre toda la pantalla (encima de la UI)
	var overlay := ColorRect.new()
	overlay.color           = Color(0.0, 0.0, 0.0, 1.0)
	overlay.layout_mode     = 1
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical   = Control.GROW_DIRECTION_BOTH
	overlay.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(overlay)

	var t := create_tween()
	t.tween_interval(0.35)                         # pausa inicial en negro
	# Fade a transparente + descenso del "cielo" al taladro — en paralelo
	t.tween_property(overlay, "color:a", 0.0, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "_intro_depth", depth, 2.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		_intro_playing = false
		overlay.queue_free()
	)

func _build_upgrade_ui():
	for upgrade in UPGRADES:
		var btn = Button.new()
		btn.name = upgrade["id"]
		btn.custom_minimum_size = Vector2(0, 76)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.pressed.connect(func(): sfx_blip.play())
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
	sfx_upgrade.play()
	match upgrade["type"]:
		"drill_power":  drill_power += float(upgrade["value"])
		"auto_drill":   auto_drill  += float(upgrade["value"])
		"energy_max":
			max_energy += int(upgrade["value"])
			energy = min(energy + int(upgrade["value"]), max_energy)
			energy_bar.max_value = max_energy
		"energy_regen":
			energy_regen_rate = max(2.0, energy_regen_rate - float(upgrade["value"]))
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
