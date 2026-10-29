extends CanvasLayer
class_name OrderProgressHUD

## Compact top-left readout for the current pickup or delivery leg.
## Reads OrderSession and PlayerController; it does not change either system.

const TEXT := Color(0.91, 0.95, 0.97)
const DISTANCE_TEXT := Color(0.80, 0.85, 0.89)
const HUD_FONT := preload("res://assets/fonts/BarlowCondensed-Light.ttf")

var _orders: OrderManager
var _player: PlayerController
var _session: OrderSession
var _phase := -1
var _phase_start_distance := 1.0
var _progress := 0.0

var _root: Control
var _fade_background: TextureRect
var _panel: PanelContainer
var _eta_label: Label
var _distance_label: Label


func _ready() -> void:
	layer = 12
	_build()
	_root.resized.connect(_layout)
	_layout()
	_fade_background.visible = false
	_panel.visible = false


func setup(orders: OrderManager, player: PlayerController) -> void:
	_orders = orders
	_player = player
	if _orders != null:
		_orders.order_started.connect(_on_order_started)
		_orders.order_finished.connect(func(_success: bool) -> void: _reset())
		_orders.returned_to_menu.connect(_reset)
	_refresh()


func get_progress_ratio() -> float:
	return _progress


func get_eta_text() -> String:
	return _eta_label.text if _eta_label != null else ""


func get_distance_text() -> String:
	return _distance_label.text if _distance_label != null else ""


func is_progress_visible() -> bool:
	return _panel != null and _panel.visible


func _process(_delta: float) -> void:
	_refresh()


func _on_order_started(_order: DeliveryOrder) -> void:
	_reset()
	_refresh()


func _refresh() -> void:
	if _panel == null or _orders == null or _player == null:
		return
	var current := _orders.get_session()
	if current == null or not current.is_active():
		_reset()
		return
	var distance := current.get_distance_to_target(_player.global_position)
	if not is_finite(distance):
		_reset()
		return
	if current != _session or current.state != _phase:
		_session = current
		_phase = current.state
		_phase_start_distance = maxf(distance, OrderSession.INTERACT_RADIUS_M)
	_progress = clampf(1.0 - distance / _phase_start_distance, 0.0, 1.0)
	if distance <= OrderSession.INTERACT_RADIUS_M:
		_progress = 1.0
	_eta_label.text = OrderHUD.format_time(current.time_remaining)
	_distance_label.text = _format_distance(distance)
	_fade_background.visible = true
	_panel.visible = true


func _reset() -> void:
	_session = null
	_phase = -1
	_progress = 0.0
	if _panel != null:
		_panel.visible = false
	if _fade_background != null:
		_fade_background.visible = false


func _format_distance(distance: float) -> String:
	if distance >= 1000.0:
		return "%.1f km" % (distance / 1000.0)
	return "%d m" % roundi(distance)


func _build() -> void:
	_root = Control.new()
	_root.name = "OrderProgressOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.11, 0.15, 0.19, 0.68))
	gradient.set_color(1, Color(0.11, 0.15, 0.19, 0.0))
	gradient.add_point(0.58, Color(0.11, 0.15, 0.19, 0.64))
	var fade_texture := GradientTexture2D.new()
	fade_texture.gradient = gradient
	fade_texture.width = 256
	fade_texture.height = 2
	fade_texture.fill_from = Vector2(0.0, 0.5)
	fade_texture.fill_to = Vector2(1.0, 0.5)
	_fade_background = TextureRect.new()
	_fade_background.name = "OrderFadeBackground"
	_fade_background.texture = fade_texture
	_fade_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade_background.stretch_mode = TextureRect.STRETCH_SCALE
	_fade_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade_background)

	_panel = PanelContainer.new()
	_panel.name = "OrderProgressPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	_eta_label = _label("0:00", 27, TEXT)
	_eta_label.name = "OrderTime"
	_eta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(_eta_label)
	_distance_label = _label("0 m", 14, DISTANCE_TEXT)
	_distance_label.name = "OrderDistance"
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(_distance_label)


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", HUD_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("outline_size", 2)
	return label


func _layout() -> void:
	if _root == null or _root.size.x <= 0.0 or _root.size.y <= 0.0:
		return
	var width := minf(clampf(_root.size.x * 0.19, 180.0, 220.0), _root.size.x - 28.0)
	_fade_background.position = Vector2(14.0, 18.0)
	_fade_background.size = Vector2(width, 63.0)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 14.0
	_panel.offset_right = 14.0 + width
	_panel.offset_top = 18.0
	_panel.offset_bottom = 81.0
