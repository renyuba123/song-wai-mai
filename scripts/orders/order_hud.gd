extends CanvasLayer
class_name OrderHUD

## 订单 HUD：开始界面、待接订单、目标、距离、倒计时、种子、方向箭头、
## E 提示和结算面板。全部用代码创建，避免把 UI 节点和美术资源耦合进主场景。

signal start_pressed
signal accept_pressed
signal next_order_pressed
signal menu_pressed

const PANEL_BG := Color(0.045, 0.06, 0.09, 0.84)
const TEXT_COLOR := Color(0.96, 0.97, 1.0, 1.0)
const MUTED_COLOR := Color(0.72, 0.78, 0.86, 1.0)
const ACCENT_COLOR := Color(1.0, 0.72, 0.28, 1.0)
const ERROR_COLOR := Color(1.0, 0.45, 0.38, 1.0)

var _root: Control
var _status_panel: PanelContainer
var _objective_label: Label
var _detail_label: Label
var _arrow_label: Label
var _hint_label: Label
var _prompt_label: Label
var _error_label: Label

var _start_layer: Control
var _start_seed_label: Label
var _start_button: Button

var _offer_layer: Control
var _offer_body: Label
var _offer_hint: Label
var _accept_button: Button

var _result_layer: Control
var _result_title: Label
var _result_body: Label
var _result_hint: Label
var _result_next_button: Button
var _result_menu_button: Button


func _ready() -> void:
	layer = 10
	_build()


func show_start_menu(city_seed: int) -> void:
	_start_layer.visible = true
	_offer_layer.visible = false
	_result_layer.visible = false
	_status_panel.visible = false
	_prompt_label.visible = false
	clear_error()
	_start_seed_label.text = "城市种子 %d" % city_seed
	_start_button.grab_focus()


func hide_start_menu() -> void:
	_start_layer.visible = false


func show_offer(order: DeliveryOrder, time_limit: float) -> void:
	if order == null:
		return
	_start_layer.visible = false
	_offer_layer.visible = true
	_result_layer.visible = false
	_status_panel.visible = false
	_prompt_label.visible = false
	clear_error()
	var pickup_length := maxf(order.pickup_path_length_m, 0.0)
	var delivery_length := maxf(order.delivery_path_length_m, 0.0)
	_offer_body.text = "\n".join([
		"取餐：%s" % site_label(order.merchant),
		"送达：%s" % site_label(order.customer),
		"取餐路程 %d m · 送达路程 %d m" % [
			roundi(pickup_length), roundi(delivery_length)
		],
		"限时 %s · 城市种子 %d · 订单种子 %d" % [
			format_time(time_limit), order.city_seed, order.order_seed
		],
	])
	_offer_hint.text = "按 E 或点击“接单”，倒计时开始"
	_accept_button.grab_focus()


func hide_offer() -> void:
	_offer_layer.visible = false


func show_waiting(text: String = "正在生成订单…") -> void:
	_offer_layer.visible = false
	_result_layer.visible = false
	_status_panel.visible = true
	_error_label.text = ""
	_error_label.visible = false
	_objective_label.text = text
	_detail_label.text = ""
	_arrow_label.text = ""
	_hint_label.text = ""
	_prompt_label.text = ""
	_prompt_label.visible = false


func show_active(order: DeliveryOrder, session: OrderSession) -> void:
	_offer_layer.visible = false
	_result_layer.visible = false
	_status_panel.visible = true
	_error_label.text = ""
	_error_label.visible = false
	if order == null or session == null:
		show_waiting()
		return
	_objective_label.text = session.get_objective_text()
	_detail_label.text = ""
	_hint_label.text = "城市种子 %d · 订单种子 %d · R 重新开始本单" % [
		order.city_seed, order.order_seed
	]
	_arrow_label.text = ""
	_prompt_label.text = ""
	_prompt_label.visible = false


func update_active(
	order: DeliveryOrder,
	session: OrderSession,
	player_position: Vector3,
	player_yaw: float
) -> void:
	if order == null or session == null or not session.is_active():
		return
	var target := session.get_target_position()
	_objective_label.text = session.get_objective_text()
	_detail_label.text = "距目标 %d m · 剩余 %s" % [
		roundi(session.get_distance_to_target(player_position)),
		format_time(session.time_remaining),
	]
	_hint_label.text = "城市种子 %d · 订单种子 %d · R 重新开始本单" % [
		order.city_seed, order.order_seed
	]
	_arrow_label.text = direction_arrow(player_position, player_yaw, target)
	var can_interact := session.can_interact(player_position)
	_prompt_label.text = session.get_interact_prompt() if can_interact else ""
	_prompt_label.visible = can_interact


func show_result(order: DeliveryOrder, session: OrderSession) -> void:
	if order == null or session == null:
		return
	_start_layer.visible = false
	_offer_layer.visible = false
	_status_panel.visible = false
	_result_layer.visible = true
	_result_title.text = "订单完成" if session.is_success() else "订单失败"
	_result_title.add_theme_color_override(
		"font_color", ACCENT_COLOR if session.is_success() else ERROR_COLOR
	)
	var total_length := order.get_total_path_length_m()
	var lines := [
		"城市种子 %d · 订单种子 %d" % [order.city_seed, order.order_seed],
		"总路程 %d m · 用时 %s" % [
			roundi(maxf(total_length, 0.0)),
			format_time(session.get_elapsed_s()),
		],
	]
	if session.is_success():
		lines.append("剩余时间 %s" % format_time(session.time_remaining))
	else:
		lines.append(session.get_failure_text())
	_result_body.text = "\n".join(lines)
	_result_hint.text = "按 R 开始下一单"
	_result_next_button.text = "下一单（R）"
	_result_next_button.grab_focus()
	_objective_label.text = session.get_objective_text()
	_detail_label.text = ""
	_arrow_label.text = ""
	_hint_label.text = ""
	_prompt_label.text = ""
	_prompt_label.visible = false


func show_error(text: String) -> void:
	_offer_layer.visible = false
	_result_layer.visible = false
	_status_panel.visible = true
	_objective_label.text = "订单未开始"
	_detail_label.text = ""
	_arrow_label.text = ""
	_hint_label.text = ""
	_prompt_label.text = ""
	_prompt_label.visible = false
	_error_label.text = text
	_error_label.visible = not text.is_empty()


func clear_error() -> void:
	_error_label.text = ""
	_error_label.visible = false


func get_objective_text() -> String:
	return _objective_label.text


func get_detail_text() -> String:
	return _detail_label.text


func get_prompt_text() -> String:
	return _prompt_label.text


func get_arrow_text() -> String:
	return _arrow_label.text


func get_error_text() -> String:
	return _error_label.text


func get_offer_text() -> String:
	return _offer_body.text


func get_start_button_text() -> String:
	return _start_button.text


func is_start_menu_visible() -> bool:
	return _start_layer.visible


func is_offer_visible() -> bool:
	return _offer_layer.visible


func is_result_visible() -> bool:
	return _result_layer.visible


func is_any_modal_visible() -> bool:
	## 开始菜单、接单或结算面板挡在前面时，暂停层不应抢走 Esc。
	return _start_layer.visible or _offer_layer.visible or _result_layer.visible


func get_result_title() -> String:
	return _result_title.text


func get_result_body() -> String:
	return _result_body.text


static func site_label(site: CitySite) -> String:
	if site == null:
		return "未知站点"
	var prefix := "商家" if site.kind == CitySite.Kind.MERCHANT else "顾客"
	if not site.display_name.is_empty():
		# 有店名时先显示店名，再补角色，方便和三维标牌对上。
		return "%s（%s）" % [site.display_name, prefix]
	var raw := String(site.id)
	var parts := raw.split("_")
	var suffix := parts[parts.size() - 1] if parts.size() > 1 else raw
	if suffix.is_empty():
		suffix = "???"
	return "%s #%s" % [prefix, suffix]


static func direction_arrow(
	player_position: Vector3,
	player_yaw: float,
	target_position: Vector3
) -> String:
	if not target_position.is_finite():
		return ""
	var delta := Vector2(
		target_position.x - player_position.x,
		target_position.z - player_position.z
	)
	if delta.length_squared() < 0.0001:
		return "•"
	var forward := Vector2(-sin(player_yaw), -cos(player_yaw))
	var right := Vector2(cos(player_yaw), -sin(player_yaw))
	var angle := atan2(delta.dot(right), delta.dot(forward))
	var index := int(round(angle / (PI / 4.0)))
	var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	return arrows[posmod(index, 8)]


static func format_time(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	return "%d:%02d" % [floori(total / 60.0), total % 60]


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_status_panel = PanelContainer.new()
	_status_panel.position = Vector2(24, 24)
	_status_panel.custom_minimum_size = Vector2(430, 0)
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(_status_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_objective_label = _make_label(24, TEXT_COLOR)
	box.add_child(_objective_label)
	_detail_label = _make_label(16, MUTED_COLOR)
	box.add_child(_detail_label)
	_arrow_label = _make_label(28, ACCENT_COLOR)
	_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_arrow_label)
	_hint_label = _make_label(14, MUTED_COLOR)
	box.add_child(_hint_label)

	_prompt_label = _make_label(22, TEXT_COLOR)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = -300
	_prompt_label.offset_right = 300
	_prompt_label.offset_top = -120
	_prompt_label.offset_bottom = -78
	_root.add_child(_prompt_label)

	_error_label = _make_label(16, ERROR_COLOR)
	_error_label.anchor_top = 1.0
	_error_label.anchor_bottom = 1.0
	_error_label.offset_left = 24
	_error_label.offset_right = 900
	_error_label.offset_top = -70
	_error_label.offset_bottom = -38
	_root.add_child(_error_label)

	_build_start_layer()
	_build_offer_layer()
	_build_result_layer()
	show_waiting()


func _build_start_layer() -> void:
	var modal := _build_modal(Vector2(620, 430), 40, ACCENT_COLOR)
	_start_layer = modal["layer"]
	var box: VBoxContainer = modal["box"]
	var title: Label = modal["title"]
	title.text = "大城市送外卖"
	var body: Label = modal["body"]
	body.text = "在程序化生成的城市里取餐、送达。\n按时完成每一单。"
	var hint: Label = modal["hint"]
	hint.text = "WASD 移动 · 鼠标视角 · E 取餐/送达 · R 重新开始"
	_start_seed_label = _make_label(15, MUTED_COLOR)
	_start_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_start_seed_label)
	_start_button = _make_button("开始游戏")
	_start_button.pressed.connect(func() -> void: start_pressed.emit())
	box.add_child(_start_button)


func _build_offer_layer() -> void:
	var modal := _build_modal(Vector2(620, 420), 34, ACCENT_COLOR)
	_offer_layer = modal["layer"]
	var box: VBoxContainer = modal["box"]
	var title: Label = modal["title"]
	title.text = "新的外卖订单"
	_offer_body = modal["body"]
	_offer_hint = modal["hint"]
	_offer_hint.text = "按 E 或点击“接单”，倒计时开始"
	_accept_button = _make_button("接单")
	_accept_button.pressed.connect(func() -> void: accept_pressed.emit())
	box.add_child(_accept_button)


func _build_result_layer() -> void:
	var modal := _build_modal(Vector2(620, 430), 34, ACCENT_COLOR)
	_result_layer = modal["layer"]
	var box: VBoxContainer = modal["box"]
	_result_title = modal["title"]
	_result_body = modal["body"]
	_result_hint = modal["hint"]
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(buttons)
	_result_next_button = _make_button("下一单（R）")
	_result_next_button.pressed.connect(func() -> void: next_order_pressed.emit())
	buttons.add_child(_result_next_button)
	_result_menu_button = _make_button("返回主菜单")
	_result_menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_result_menu_button)


func _build_modal(size: Vector2, title_size: int, title_color: Color) -> Dictionary:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.visible = false
	_root.add_child(layer)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.58)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := _make_label(title_size, title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := _make_label(19, TEXT_COLOR)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(size.x - 56.0, 0.0)
	box.add_child(body)
	var hint := _make_label(16, MUTED_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(size.x - 56.0, 0.0)
	box.add_child(hint)
	return {
		"layer": layer,
		"panel": panel,
		"box": box,
		"title": title,
		"body": body,
		"hint": hint,
	}


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 22)
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(1.0, 0.72, 0.28, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
