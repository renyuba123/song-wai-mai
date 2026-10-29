extends CanvasLayer
class_name DeliveryPhoneHUD

## Compact bottom-right phone using the 3D phone's order data and colors.
## Native labels stay sharp at GTA-style HUD scale.

const FRAME_COLOR := Color(0.035, 0.045, 0.06, 0.96)
const MUTED_COLOR := Color(0.66, 0.72, 0.79)
const MONEY_COLOR := Color(0.872, 0.789, 0.277, 1.0)

var _orders: OrderManager
var _economy: EconomyHUD
var _diagnostics: InputDiagnosticsHUD
var _phone: OrderPhone
var _game_active := false

var _root: Control
var _frame: PanelContainer
var _content: Control
var _balance: Label
var _screen_slot: Control
var _screen_title: Label
var _screen_primary: Label
var _screen_secondary: Label
var _screen_distance: Label
var _screen_time: Label
var _screen_hint: Label
var _diagnostics_page: Panel
var _diagnostics_text: Label
var _route: Label
var _income: Label
var _compensation: Label


func _ready() -> void:
	layer = 11
	_build()
	_root.resized.connect(_layout)
	_layout()


func setup(orders: OrderManager, economy: EconomyHUD, diagnostics: InputDiagnosticsHUD) -> void:
	_orders = orders
	_economy = economy
	_diagnostics = diagnostics
	_phone = orders.get_phone() if orders != null else null
	_refresh()


func set_game_active(active: bool) -> void:
	_game_active = active
	_refresh()


func is_phone_ui_visible() -> bool:
	return _frame != null and _frame.visible


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _frame == null:
		return
	var showing_diagnostics := _diagnostics != null and _diagnostics.is_enabled()
	_frame.visible = _game_active or showing_diagnostics
	if not _frame.visible:
		return
	_diagnostics_page.visible = showing_diagnostics
	if showing_diagnostics:
		_diagnostics_text.text = "输入自检 · F9 关闭\n\n%s" % _diagnostics.get_diagnostics_text()
	else:
		_refresh_order_screen()
	if _economy != null:
		_balance.text = "余额  ¥%d" % _economy.get_balance()
		_income.text = "本单 +¥%d   累计 ¥%d" % [
			_economy.get_current_order_income(), _economy.get_total_income()
		]
		_compensation.text = "累计赔偿  -¥%d" % _economy.get_total_compensation()
	if _orders != null and _orders.get_current_order() != null:
		var order := _orders.get_current_order()
		var arrow := _orders.get_hud().get_arrow_text()
		_route.text = "方向 %s   城市 %d" % [
			arrow if not arrow.is_empty() else "—", order.city_seed]
	else:
		_route.text = "等待订单"


func _refresh_order_screen() -> void:
	_screen_title.text = "等待订单"
	_screen_primary.text = "正在生成新订单…"
	_screen_secondary.text = ""
	_screen_distance.text = ""
	_screen_time.text = ""
	_screen_hint.text = ""
	if _orders == null or _phone == null:
		return
	var order := _orders.get_current_order()
	if order == null:
		return
	if _phone.is_offer_visible():
		_screen_title.text = "新外卖订单"
		_screen_primary.text = "取餐  %s" % OrderHUD.site_label(order.merchant)
		_screen_secondary.text = "送达  %s" % OrderHUD.site_label(order.customer)
		_screen_distance.text = "总路程  %.1f km" % (order.get_total_path_length_m() / 1000.0)
		_screen_time.text = "预计 ¥%d · %d 秒" % [
			_phone.get_expected_income(),
			ceili(_phone.get_remaining_s())
		]
		_screen_hint.text = "Y 接单   N 拒单"
		return
	var session := _orders.get_session()
	if session == null or not session.is_active():
		return
	_screen_title.text = "配送中"
	_screen_primary.text = session.get_objective_text()
	_screen_secondary.text = ""
	_screen_distance.text = "距离  %d m" % roundi(
		session.get_distance_to_target(_orders.get_player_position())
	)
	_screen_time.text = "剩余  %s" % OrderHUD.format_time(session.time_remaining)
	_screen_hint.text = "E 交互   R 重开"


func _build() -> void:
	_root = Control.new()
	_root.name = "DeliveryPhoneOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_frame = PanelContainer.new()
	_frame.name = "PhoneFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = FRAME_COLOR
	frame_style.border_color = Color(0.23, 0.29, 0.35)
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(22)
	_frame.add_theme_stylebox_override("panel", frame_style)
	_root.add_child(_frame)

	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_content)
	_balance = _label(15, MONEY_COLOR)
	_balance.name = "PhoneBalance"
	_content.add_child(_balance)

	_screen_slot = Control.new()
	_screen_slot.name = "PhoneScreen"
	_screen_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_slot.clip_contents = true
	_content.add_child(_screen_slot)
	var screen_background := ColorRect.new()
	screen_background.color = OrderPhone.SCREEN_BG
	screen_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_slot.add_child(screen_background)
	_screen_title = _label(17, OrderPhone.TEXT_DARK)
	_screen_title.name = "PhoneOrderTitle"
	_screen_slot.add_child(_screen_title)
	_screen_primary = _label(14, OrderPhone.TEXT_DARK)
	_screen_primary.name = "PhoneObjective"
	_screen_primary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen_slot.add_child(_screen_primary)
	_screen_secondary = _label(12, OrderPhone.TEXT_MUTED)
	_screen_secondary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen_slot.add_child(_screen_secondary)
	_screen_distance = _label(14, OrderPhone.TEXT_DARK)
	_screen_slot.add_child(_screen_distance)
	_screen_time = _label(14, OrderPhone.ACCEPT_COLOR)
	_screen_slot.add_child(_screen_time)
	_screen_hint = _label(11, OrderPhone.TEXT_MUTED)
	_screen_slot.add_child(_screen_hint)

	_diagnostics_page = Panel.new()
	_diagnostics_page.name = "PhoneDiagnostics"
	_diagnostics_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_diagnostics_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color(0.055, 0.09, 0.12)
	debug_style.set_corner_radius_all(9)
	_diagnostics_page.add_theme_stylebox_override("panel", debug_style)
	_screen_slot.add_child(_diagnostics_page)
	_diagnostics_text = _label(11, Color(0.82, 0.94, 0.89))
	_diagnostics_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnostics_text.offset_left = 12
	_diagnostics_text.offset_top = 16
	_diagnostics_text.anchor_right = 1.0
	_diagnostics_text.offset_right = -12
	_diagnostics_text.anchor_bottom = 1.0
	_diagnostics_text.offset_bottom = -12
	_diagnostics_page.add_child(_diagnostics_text)

	_route = _label(12, MUTED_COLOR)
	_route.name = "PhoneRouteMeta"
	_route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_route)
	_income = _label(12, MONEY_COLOR)
	_income.name = "PhoneIncome"
	_content.add_child(_income)
	_compensation = _label(11, MUTED_COLOR)
	_compensation.name = "PhoneCompensation"
	_content.add_child(_compensation)
	_frame.visible = false


func _layout() -> void:
	if _root == null or _root.size.x <= 0.0 or _root.size.y <= 0.0:
		return
	var width := clampf(_root.size.x * 0.145, 190.0, 280.0)
	var height := clampf(_root.size.y * 0.47, 330.0, 500.0)
	height = minf(height, _root.size.y - 24.0)
	var unit := width / 190.0
	_frame.position = Vector2(_root.size.x - width - 12.0, _root.size.y - height - 8.0)
	_frame.size = Vector2(width, height)
	_content.size = Vector2(width - 6.0, height - 6.0)
	_balance.position = Vector2(12, 8) * unit
	_balance.size = Vector2(width - 24 * unit, 23 * unit)
	_screen_slot.position = Vector2(8, 35) * unit
	_screen_slot.size = Vector2(_content.size.x - 16.0 * unit, height - 113.0 * unit)
	var screen_width := _screen_slot.size.x
	var screen_height := _screen_slot.size.y
	_screen_title.position = Vector2(9, 10) * unit
	_screen_title.size = Vector2(screen_width - 18 * unit, 25 * unit)
	_screen_primary.position = Vector2(9, 39) * unit
	_screen_primary.size = Vector2(screen_width - 18 * unit, 53 * unit)
	_screen_secondary.position = Vector2(9, 94) * unit
	_screen_secondary.size = Vector2(screen_width - 18 * unit, 40 * unit)
	_screen_distance.position = Vector2(9 * unit, screen_height - 77 * unit)
	_screen_distance.size = Vector2(screen_width - 18 * unit, 24 * unit)
	_screen_time.position = Vector2(9 * unit, screen_height - 53 * unit)
	_screen_time.size = Vector2(screen_width - 18 * unit, 24 * unit)
	_screen_hint.position = Vector2(9 * unit, screen_height - 28 * unit)
	_screen_hint.size = Vector2(screen_width - 18 * unit, 21 * unit)
	_route.position = Vector2(12 * unit, height - 75 * unit)
	_route.size = Vector2(width - 24 * unit, 22 * unit)
	_income.position = Vector2(12 * unit, height - 51 * unit)
	_income.size = Vector2(width - 24 * unit, 22 * unit)
	_compensation.position = Vector2(12 * unit, height - 28 * unit)
	_compensation.size = Vector2(width - 24 * unit, 20 * unit)
	for entry in [[_balance, 15], [_screen_title, 17], [_screen_primary, 14],
		[_screen_secondary, 12], [_screen_distance, 14], [_screen_time, 14],
		[_screen_hint, 11], [_route, 12], [_income, 12], [_compensation, 11],
		[_diagnostics_text, 11]]:
		(entry[0] as Label).add_theme_font_size_override("font_size", roundi(entry[1] * unit))


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
