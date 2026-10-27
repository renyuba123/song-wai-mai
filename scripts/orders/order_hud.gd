extends CanvasLayer
class_name OrderHUD

## 订单 HUD：目标、距离、倒计时、种子、方向箭头、E 提示和结算面板。
## 全部用代码创建，避免把 UI 节点和美术资源耦合进主场景。

const PANEL_BG := Color(0.045, 0.06, 0.09, 0.84)
const TEXT_COLOR := Color(0.96, 0.97, 1.0, 1.0)
const MUTED_COLOR := Color(0.72, 0.78, 0.86, 1.0)
const ACCENT_COLOR := Color(1.0, 0.72, 0.28, 1.0)
const ERROR_COLOR := Color(1.0, 0.45, 0.38, 1.0)

var _root: Control
var _objective_label: Label
var _detail_label: Label
var _arrow_label: Label
var _hint_label: Label
var _prompt_label: Label
var _error_label: Label
var _result_layer: Control
var _result_title: Label
var _result_body: Label
var _result_hint: Label


func _ready() -> void:
	layer = 10
	_build()


func show_waiting(text: String = "正在生成订单…") -> void:
	_result_layer.visible = false
	_error_label.text = ""
	_error_label.visible = false
	_objective_label.text = text
	_detail_label.text = ""
	_arrow_label.text = ""
	_hint_label.text = ""
	_prompt_label.text = ""
	_prompt_label.visible = false


func show_active(order: DeliveryOrder, session: OrderSession) -> void:
	_result_layer.visible = false
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
		lines.append("倒计时已结束")
	_result_body.text = "\n".join(lines)
	_result_hint.text = "按 R 生成下一单"
	_objective_label.text = session.get_objective_text()
	_detail_label.text = ""
	_arrow_label.text = ""
	_hint_label.text = ""
	_prompt_label.text = ""
	_prompt_label.visible = false


func show_error(text: String) -> void:
	_result_layer.visible = false
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


func is_result_visible() -> bool:
	return _result_layer.visible


func get_result_title() -> String:
	return _result_title.text


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

	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(430, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

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

	_result_layer = Control.new()
	_result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.visible = false
	_root.add_child(_result_layer)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(shade)

	var result_panel := PanelContainer.new()
	result_panel.anchor_left = 0.5
	result_panel.anchor_right = 0.5
	result_panel.anchor_top = 0.5
	result_panel.anchor_bottom = 0.5
	result_panel.offset_left = -270
	result_panel.offset_right = 270
	result_panel.offset_top = -170
	result_panel.offset_bottom = 170
	result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.add_theme_stylebox_override("panel", _panel_style())
	_result_layer.add_child(result_panel)

	var result_margin := MarginContainer.new()
	result_margin.add_theme_constant_override("margin_left", 28)
	result_margin.add_theme_constant_override("margin_right", 28)
	result_margin.add_theme_constant_override("margin_top", 24)
	result_margin.add_theme_constant_override("margin_bottom", 24)
	result_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.add_child(result_margin)

	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 14)
	result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_margin.add_child(result_box)
	_result_title = _make_label(34, ACCENT_COLOR)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(_result_title)
	_result_body = _make_label(18, TEXT_COLOR)
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(_result_body)
	_result_hint = _make_label(18, MUTED_COLOR)
	_result_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(_result_hint)

	show_waiting()


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(1.0, 0.72, 0.28, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
