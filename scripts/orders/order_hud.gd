extends CanvasLayer
class_name OrderHUD

## 订单 HUD：开始界面、待接订单、目标、距离、倒计时、种子、方向箭头、
## E 提示和结算面板。全部用代码创建，避免把 UI 节点和美术资源耦合进主场景。
##
## 开始和结算界面重做为全屏标题页 / 结算卡：深蓝夜景、金色描边、
## 路线背景和分段统计。游戏中的左上角状态面板保持照片复刻风格。

signal start_pressed
signal next_order_pressed
signal menu_pressed

const MenuBackdropScript = preload("res://scripts/ui/menu_backdrop.gd")

const PANEL_BG := Color(0.045, 0.06, 0.09, 0.84)
const STATUS_BG := Color(0.035, 0.06, 0.11, 0.80)
const STATUS_BORDER := Color(0.85, 0.68, 0.32, 0.75)
const TEXT_COLOR := Color(0.96, 0.97, 1.0, 1.0)
const OFFER_TEXT_COLOR := Color(0.98, 0.90, 0.72, 1.0)
const MUTED_COLOR := Color(0.72, 0.78, 0.86, 1.0)
const ACCENT_COLOR := Color(1.0, 0.72, 0.28, 1.0)
const ERROR_COLOR := Color(1.0, 0.45, 0.38, 1.0)

const GOLD := Color(1.0, 0.72, 0.30, 1.0)
const GOLD_BRIGHT := Color(1.0, 0.83, 0.50, 1.0)
const GOLD_DIM := Color(0.95, 0.72, 0.36, 0.32)
const MINT := Color(0.34, 0.90, 0.70, 1.0)
const CORAL := Color(1.0, 0.43, 0.36, 1.0)
const INK_TEXT := Color(0.035, 0.060, 0.095, 1.0)
const MUTED_UI := Color(0.62, 0.71, 0.82, 1.0)
const CARD_BG := Color(0.035, 0.070, 0.115, 0.96)
const GLASS_BG := Color(0.055, 0.105, 0.165, 0.82)

var _root: Control
var _status_panel: PanelContainer
var _objective_label: Label
var _detail_label: Label
var _arrow_label: Label
var _hint_label: Label
var _prompt_label: Label
var _error_label: Label

var _start_layer: Control
var _start_backdrop: MenuBackdrop
var _start_page_margin: MarginContainer
var _start_content: VBoxContainer
var _start_title: Label
var _start_subtitle: Label
var _start_feature_row: HFlowContainer
var _start_controls_panel: PanelContainer
var _start_controls_grid: GridContainer
var _start_touch_hint: Label
var _start_seed_label: Label
var _start_action_hint: Label
var _start_button: Button

var _offer_active := false
var _offer_text := ""

var _result_layer: Control
var _result_backdrop: MenuBackdrop
var _result_card: PanelContainer
var _result_eyebrow: Label
var _result_badge: PanelContainer
var _result_icon: Label
var _result_title: Label
var _result_route: Label
var _result_stat_values: Array[Label] = []
var _result_income: Label
var _result_body: Label
var _result_hint: Label
var _result_next_button: Button
var _result_menu_button: Button

var _right_column: VBoxContainer
var _wallet_panel: PanelContainer
var _wallet_balance_label: Label
var _wallet_rows: Array[Label] = []
var _self_check_panel: PanelContainer
var _self_check_values: Array[Label] = []

var _wallet: DeliveryWallet = null
var _player: PlayerController = null
var _self_check_visible := true
var _key_event_count := 0
var _last_key_text := ""
var _last_key_msec := 0

var _bold_font: FontVariation
var _responsive_pending := false


func _ready() -> void:
	layer = 10
	_ensure_fonts()
	_build()
	_root.resized.connect(_request_responsive_layout)
	_request_responsive_layout()


## 订阅配送账户；账户每次变化都会刷新右上角收支面板。
func bind_wallet(wallet: DeliveryWallet) -> void:
	if _wallet == wallet:
		return
	if _wallet != null and _wallet.changed.is_connected(_refresh_wallet):
		_wallet.changed.disconnect(_refresh_wallet)
	_wallet = wallet
	if _wallet != null:
		_wallet.changed.connect(_refresh_wallet)
	_refresh_wallet()


## 输入自检面板读取玩家的可控状态、速度和车头朝向。
func bind_player(player: PlayerController) -> void:
	_player = player
	refresh_self_check()


func toggle_self_check() -> void:
	_self_check_visible = not _self_check_visible
	_self_check_panel.visible = _self_check_visible
	refresh_self_check()


func is_self_check_visible() -> bool:
	return _self_check_panel.visible


func is_wallet_panel_visible() -> bool:
	return _wallet_panel.visible and _right_column.visible


func get_right_column_rect() -> Rect2:
	return _right_column.get_global_rect()


func get_balance_text() -> String:
	return _wallet_balance_label.text


func get_wallet_row_text(index: int) -> String:
	if index < 0 or index >= _wallet_rows.size():
		return ""
	return _wallet_rows[index].text


func get_self_check_value(index: int) -> String:
	if index < 0 or index >= _self_check_values.size():
		return ""
	return _self_check_values[index].text


func show_start_menu(city_seed: int) -> void:
	_offer_active = false
	_offer_text = ""
	_set_offer_panel(false)
	_set_menu_visible(true, false)
	_status_panel.visible = false
	_set_right_column_visible(false)
	_prompt_label.visible = false
	clear_error()
	_start_seed_label.text = "城市种子 %d" % city_seed
	_start_action_hint.text = (
		"点击开始接单 · 左侧摇杆骑行，右侧拖动视角"
		if TouchControls.is_touch_device()
		else "按 Enter / E 开始 · 配送中按 Esc 暂停"
	)
	_start_button.grab_focus()
	_request_responsive_layout()
	_animate_in(_start_content)


func hide_start_menu() -> void:
	_start_layer.visible = false
	_start_backdrop.set_active(false)


func show_offer(order: DeliveryOrder, time_limit: float) -> void:
	## 接单详情在三维手机屏幕上；HUD 只保留左上角的新订单提醒。
	if order == null:
		return
	_offer_active = true
	_offer_text = OrderPhone.format_offer_text(order, time_limit)
	_set_offer_panel(true)
	_set_menu_visible(false, false)
	_status_panel.visible = true
	_set_right_column_visible(true)
	_objective_label.text = "手机收到新订单 · Y 接单 / N 拒单"
	_detail_label.text = ""
	_arrow_label.text = ""
	_arrow_label.visible = false
	_hint_label.text = ""
	_hint_label.visible = false
	_prompt_label.text = ""
	_prompt_label.visible = false
	clear_error()


func hide_offer() -> void:
	_offer_active = false


func show_waiting(text: String = "正在生成订单…") -> void:
	_offer_active = false
	_set_offer_panel(false)
	_set_menu_visible(false, false)
	_status_panel.visible = true
	_set_right_column_visible(true)
	_error_label.text = ""
	_error_label.visible = false
	_objective_label.text = text
	_detail_label.text = ""
	_arrow_label.text = ""
	_arrow_label.visible = false
	_hint_label.text = ""
	_hint_label.visible = false
	_prompt_label.text = ""
	_prompt_label.visible = false


func show_active(order: DeliveryOrder, session: OrderSession) -> void:
	_offer_active = false
	_set_offer_panel(false)
	_set_menu_visible(false, false)
	_status_panel.visible = true
	_set_right_column_visible(true)
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
	_arrow_label.visible = true
	_hint_label.visible = true
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
	_offer_active = false
	_set_offer_panel(false)
	_set_menu_visible(false, true)
	_status_panel.visible = false
	_set_right_column_visible(false)
	_result_title.text = "订单完成" if session.is_success() else "订单失败"
	var tone := MINT if session.is_success() else CORAL
	_result_title.add_theme_color_override("font_color", tone)
	_result_icon.text = "✓" if session.is_success() else "!"
	_result_icon.add_theme_color_override("font_color", tone)
	_result_badge.add_theme_stylebox_override(
		"panel",
		_badge_style(Color(tone.r, tone.g, tone.b, 0.14), Color(tone.r, tone.g, tone.b, 0.55))
	)
	_result_eyebrow.text = "配送成功 · DELIVERY COMPLETE" if session.is_success() else "配送失败 · DELIVERY FAILED"
	_result_eyebrow.add_theme_color_override("font_color", tone)
	_result_route.text = "取餐 · %s\n送达 · %s" % [
		OrderHUD.site_label(order.merchant),
		OrderHUD.site_label(order.customer),
	]

	var total_length := order.get_total_path_length_m()
	_result_stat_values[0].text = "%d m" % roundi(maxf(total_length, 0.0))
	_result_stat_values[1].text = format_time(session.get_elapsed_s())
	if session.is_success():
		_result_stat_values[2].text = format_time(session.time_remaining)
		_result_stat_values[2].add_theme_color_override("font_color", MINT)
	else:
		_result_stat_values[2].text = "未完成"
		_result_stat_values[2].add_theme_color_override("font_color", CORAL)
	_result_income.text = (
		"本单收入  ¥%.2f" % OrderPhone.calculate_fee(order)
		if session.is_success()
		else "本单收入  ¥0.00"
	)
	_result_income.add_theme_color_override("font_color", GOLD if session.is_success() else MUTED_UI)

	var lines := [
		"城市种子 %d · 订单种子 %d" % [order.city_seed, order.order_seed],
	]
	if session.is_success():
		lines.append("剩余时间 %s" % format_time(session.time_remaining))
	else:
		lines.append(session.get_failure_text())
	_result_body.text = "\n".join(lines)
	_result_body.add_theme_color_override("font_color", MUTED_UI if session.is_success() else CORAL)
	_result_hint.text = "按 R 开始下一单"
	_result_next_button.text = "下一单（R）"
	_result_next_button.grab_focus()
	_objective_label.text = session.get_objective_text()
	_detail_label.text = ""
	_arrow_label.text = ""
	_arrow_label.visible = false
	_hint_label.text = ""
	_hint_label.visible = false
	_prompt_label.text = ""
	_prompt_label.visible = false
	_request_responsive_layout()
	_animate_in(_result_card)


func show_error(text: String) -> void:
	_offer_active = false
	_set_offer_panel(false)
	_set_menu_visible(false, false)
	_status_panel.visible = true
	_set_right_column_visible(true)
	_objective_label.text = "订单未开始"
	_detail_label.text = ""
	_arrow_label.text = ""
	_arrow_label.visible = false
	_hint_label.text = ""
	_hint_label.visible = false
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
	return _offer_text


func get_start_button_text() -> String:
	return _start_button.text


func get_start_title_text() -> String:
	return _start_title.text


func get_start_subtitle_text() -> String:
	return _start_subtitle.text


func get_start_seed_text() -> String:
	return _start_seed_label.text


func get_start_content_rect() -> Rect2:
	return _start_content.get_global_rect()


func get_result_card_rect() -> Rect2:
	return _result_card.get_global_rect()


func get_result_income_text() -> String:
	return _result_income.text


func is_start_menu_visible() -> bool:
	return _start_layer.visible


func is_offer_visible() -> bool:
	return _offer_active


func is_result_visible() -> bool:
	return _result_layer.visible


func is_any_modal_visible() -> bool:
	## 开始菜单、接单或结算面板挡在前面时，暂停层不应抢走 Esc。
	return _start_layer.visible or _offer_active or _result_layer.visible


func get_result_title() -> String:
	return _result_title.text


func get_result_body() -> String:
	return _result_body.text


func get_result_route_text() -> String:
	return _result_route.text


func get_result_stat_text(index: int) -> String:
	if index < 0 or index >= _result_stat_values.size():
		return ""
	return _result_stat_values[index].text


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


## 金额展示：整数不补小数，避免“余额 500”变成“余额 500.00”。
static func format_money(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.2f" % value


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_status_panel = PanelContainer.new()
	_status_panel.position = Vector2(24, 24)
	_status_panel.custom_minimum_size = Vector2(430, 0)
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_theme_stylebox_override("panel", _status_style())
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

	_build_right_column()
	_build_start_layer()
	_build_result_layer()
	show_waiting()


func _build_right_column() -> void:
	## 右上角两块的公共列：上面是配送收支，下面是输入自检。
	_right_column = VBoxContainer.new()
	_right_column.name = "RightPanels"
	_right_column.anchor_left = 1.0
	_right_column.anchor_right = 1.0
	_right_column.offset_left = -364.0
	_right_column.offset_right = -24.0
	_right_column.offset_top = 24.0
	_right_column.offset_bottom = 24.0
	_right_column.add_theme_constant_override("separation", 10)
	_right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_right_column)
	_build_wallet_panel()
	_build_self_check_panel()
	_refresh_wallet()
	refresh_self_check()


func _build_wallet_panel() -> void:
	_wallet_panel = PanelContainer.new()
	_wallet_panel.name = "WalletPanel"
	_wallet_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wallet_panel.add_theme_stylebox_override("panel", _right_panel_style())
	_right_column.add_child(_wallet_panel)

	var margin := _panel_margin()
	_wallet_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := _make_label(13, MUTED_UI, false, 3)
	title.text = "配送收支"
	box.add_child(title)

	var balance_row := HBoxContainer.new()
	balance_row.add_theme_constant_override("separation", 8)
	balance_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(balance_row)
	var balance_caption := _make_label(18, TEXT_COLOR, true)
	balance_caption.text = "余额"
	balance_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	balance_row.add_child(balance_caption)
	_wallet_balance_label = _make_label(32, MINT, true)
	_wallet_balance_label.text = "0"
	balance_row.add_child(_wallet_balance_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grid)
	_add_wallet_row(grid, "本单收入")
	_add_wallet_row(grid, "累计收入")
	_add_wallet_row(grid, "累计赔偿")


func _build_self_check_panel() -> void:
	_self_check_panel = PanelContainer.new()
	_self_check_panel.name = "SelfCheckPanel"
	_self_check_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_self_check_panel.add_theme_stylebox_override("panel", _right_panel_style())
	_self_check_panel.visible = _self_check_visible
	_right_column.add_child(_self_check_panel)

	var margin := _panel_margin()
	_self_check_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := _make_label(12, GOLD_BRIGHT, true, 3)
	title.text = "输入自检 · F9 隐藏"
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grid)
	_add_self_check_row(grid, "窗口焦点")
	_add_self_check_row(grid, "输入激活")
	_add_self_check_row(grid, "键盘输入")
	_add_self_check_row(grid, "角色状态")


func _add_wallet_row(grid: GridContainer, caption: String) -> void:
	var caption_label := _make_label(13, MUTED_UI, false, 3)
	caption_label.text = caption
	grid.add_child(caption_label)
	var value := _make_label(14, MUTED_UI, true, 3)
	value.text = "0"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	_wallet_rows.append(value)


func _add_self_check_row(grid: GridContainer, caption: String) -> void:
	var caption_label := _make_label(12, MUTED_UI, false, 3)
	caption_label.text = caption
	grid.add_child(caption_label)
	var value := _make_label(12, MUTED_UI, true, 3)
	value.text = "—"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	_self_check_values.append(value)


func _refresh_wallet() -> void:
	if _wallet_rows.size() < 3 or _wallet_balance_label == null:
		return
	var balance := DeliveryWallet.STARTING_BALANCE
	var order_income := 0.0
	var total_income := 0.0
	var compensation := 0.0
	if _wallet != null:
		balance = _wallet.balance
		order_income = _wallet.order_income
		total_income = _wallet.total_income
		compensation = _wallet.total_compensation
	_wallet_balance_label.text = format_money(balance)
	_wallet_rows[0].text = "+%s" % format_money(order_income)
	_wallet_rows[1].text = format_money(total_income)
	_wallet_rows[2].text = "-%s" % format_money(compensation)
	_wallet_rows[0].add_theme_color_override(
		"font_color", GOLD if order_income > 0.0 else MUTED_UI
	)
	_wallet_rows[2].add_theme_color_override(
		"font_color", CORAL if compensation > 0.0 else MUTED_UI
	)


## 刷新输入自检的每一行；每帧调用，开销只是几个字符串。
func refresh_self_check() -> void:
	if _self_check_values.is_empty():
		return
	var window := get_window()
	var focused := window != null and window.has_focus()
	_set_self_check_value(0, "已获得" if focused else "未获得", focused)

	var has_player := _player != null
	var controllable := has_player and _player.controls_enabled
	var input_text := "未接入"
	if has_player:
		input_text = "已连接" if controllable else "已暂停"
	_set_self_check_value(1, input_text, controllable)

	# 手机竖屏时面板只有两百来像素宽，只保留最关键的信息。
	var compact := get_viewport().get_visible_rect().size.x < 560.0
	var keyboard := "尚未收到按键"
	if _key_event_count > 0:
		if compact:
			keyboard = "%d 次 · %s" % [_key_event_count, _last_key_text]
		else:
			var age := Time.get_ticks_msec() - _last_key_msec
			keyboard = "%d 次 · 最近 %s %d ms" % [_key_event_count, _last_key_text, age]
	_set_self_check_value(2, keyboard, _key_event_count > 0)

	var speed := 0.0
	var heading := 0.0
	if has_player:
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
		heading = fposmod(rad_to_deg(_player.rotation.y), 360.0)
	var state := "未接入"
	if has_player:
		if controllable:
			state = "可控制 · %.1f m/s" % speed if compact else "可控制 · %.1f m/s · 车头 %d°" % [speed, roundi(heading)]
		else:
			state = "菜单中 · %.1f m/s" % speed
	_set_self_check_value(3, state, controllable)


func _set_self_check_value(index: int, text: String, ok: bool) -> void:
	if index < 0 or index >= _self_check_values.size():
		return
	var label := _self_check_values[index]
	label.text = text
	label.add_theme_color_override("font_color", MINT if ok else CORAL)


func _set_right_column_visible(value: bool) -> void:
	if _right_column == null:
		return
	_right_column.visible = value


func _process(_delta: float) -> void:
	if _self_check_panel != null and _self_check_panel.visible:
		refresh_self_check()


func _input(event: InputEvent) -> void:
	## 只做统计和 F9 开关，不拦截其他输入。
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	_key_event_count += 1
	_last_key_text = OS.get_keycode_string(key.physical_keycode)
	_last_key_msec = Time.get_ticks_msec()
	if key.physical_keycode == KEY_F9:
		toggle_self_check()
		get_viewport().set_input_as_handled()


func _build_start_layer() -> void:
	_start_layer = Control.new()
	_start_layer.name = "StartScreen"
	_start_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_start_layer.visible = false
	_root.add_child(_start_layer)

	_start_backdrop = MenuBackdropScript.new()
	_start_backdrop.name = "StartBackdrop"
	_start_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_layer.add_child(_start_backdrop)

	_start_page_margin = MarginContainer.new()
	_start_page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_page_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_layer.add_child(_start_page_margin)

	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_page_margin.add_child(page)

	_start_content = VBoxContainer.new()
	_start_content.add_theme_constant_override("separation", 14)
	_start_content.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_start_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_start_content)

	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	brand.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_content.add_child(brand)
	var brand_dot := ColorRect.new()
	brand_dot.color = GOLD
	brand_dot.custom_minimum_size = Vector2(8, 8)
	brand_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(brand_dot)
	var brand_label := _make_label(14, GOLD)
	brand_label.text = "城市外卖  ·  NIGHT SHIFT"
	brand.add_child(brand_label)

	_start_title = _make_label(76, GOLD_BRIGHT, true, 8)
	_start_title.text = "大城市送外卖"
	_start_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	_start_title.add_theme_constant_override("shadow_offset_x", 0)
	_start_title.add_theme_constant_override("shadow_offset_y", 4)
	_start_content.add_child(_start_title)

	var accent_line := ColorRect.new()
	accent_line.color = GOLD
	accent_line.custom_minimum_size = Vector2(72, 3)
	accent_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_content.add_child(accent_line)

	_start_subtitle = _make_label(21, TEXT_COLOR, false, 4)
	_start_subtitle.text = "在程序化生成的城市里接单、取餐、送达。\n穿过真实车流，按时完成每一单。"
	_start_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_content.add_child(_start_subtitle)

	_start_feature_row = HFlowContainer.new()
	_start_feature_row.add_theme_constant_override("h_separation", 8)
	_start_feature_row.add_theme_constant_override("v_separation", 8)
	_start_feature_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_feature_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_content.add_child(_start_feature_row)
	_start_feature_row.add_child(_make_chip("程序化城市"))
	_start_feature_row.add_child(_make_chip("实时车流"))
	_start_feature_row.add_child(_make_chip("第一人称配送"))

	_start_controls_panel = PanelContainer.new()
	_start_controls_panel.add_theme_stylebox_override("panel", _glass_style())
	_start_controls_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_start_controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_content.add_child(_start_controls_panel)

	var controls_margin := MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_left", 18)
	controls_margin.add_theme_constant_override("margin_right", 18)
	controls_margin.add_theme_constant_override("margin_top", 12)
	controls_margin.add_theme_constant_override("margin_bottom", 12)
	controls_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_controls_panel.add_child(controls_margin)

	_start_controls_grid = GridContainer.new()
	_start_controls_grid.columns = 2
	_start_controls_grid.add_theme_constant_override("h_separation", 22)
	_start_controls_grid.add_theme_constant_override("v_separation", 7)
	_start_controls_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_margin.add_child(_start_controls_grid)
	_add_control_row("油门 · 刹车", "W / S · 摇杆上下")
	_add_control_row("车把 · 转向", "A / D · 摇杆左右")
	_add_control_row("视角", "鼠标 / 右侧拖动")
	_add_control_row("交互", "E 取餐 / 送达")
	_add_control_row("暂停 · 重开", "Esc · R")
	_add_control_row("提示面板", "F9 显示 / 隐藏")

	_start_touch_hint = _make_label(16, MUTED_UI)
	_start_touch_hint.text = "左侧摇杆：上下油门、左右转向\n右侧拖动视角 · E 取餐 / 送达"
	_start_touch_hint.visible = false
	_start_content.add_child(_start_touch_hint)

	if TelemetryClient.is_web_build():
		var notice := _make_label(13, MUTED_UI)
		notice.name = "TelemetryNotice"
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		notice.text = "本体验会匿名记录游玩过程数据，仅用于展览效果分析，\n不含姓名与账号。"
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_start_content.add_child(notice)

	var footer := HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 16)
	footer.add_theme_constant_override("v_separation", 8)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_content.add_child(footer)

	var seed_chip := PanelContainer.new()
	seed_chip.add_theme_stylebox_override("panel", _chip_style())
	seed_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(seed_chip)
	var seed_margin := MarginContainer.new()
	seed_margin.add_theme_constant_override("margin_left", 12)
	seed_margin.add_theme_constant_override("margin_right", 12)
	seed_margin.add_theme_constant_override("margin_top", 6)
	seed_margin.add_theme_constant_override("margin_bottom", 6)
	seed_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed_chip.add_child(seed_margin)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed_margin.add_child(seed_row)
	var seed_dot := ColorRect.new()
	seed_dot.color = MINT
	seed_dot.custom_minimum_size = Vector2(6, 6)
	seed_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seed_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed_row.add_child(seed_dot)
	_start_seed_label = _make_label(14, MUTED_UI)
	_start_seed_label.text = "城市种子 —"
	seed_row.add_child(_start_seed_label)

	_start_action_hint = _make_label(14, MUTED_UI)
	_start_action_hint.text = "按 Enter / E 开始"
	_start_action_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_start_action_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_start_action_hint)

	_start_button = _make_button("开始接单  →", true)
	_start_button.custom_minimum_size = Vector2(320, 64)
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_start_button.pressed.connect(func() -> void: start_pressed.emit())
	_start_content.add_child(_start_button)

	var button_hint := _make_label(13, MUTED_UI)
	button_hint.text = "送达后结算收入 · 按 R 继续下一单"
	button_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_content.add_child(button_hint)


func _build_result_layer() -> void:
	_result_layer = Control.new()
	_result_layer.name = "ResultScreen"
	_result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_layer.visible = false
	_root.add_child(_result_layer)

	_result_backdrop = MenuBackdropScript.new()
	_result_backdrop.name = "ResultBackdrop"
	_result_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(_result_backdrop)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.42)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(center)

	_result_card = PanelContainer.new()
	_result_card.name = "ResultCard"
	_result_card.custom_minimum_size = Vector2(720, 0)
	_result_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_card.add_theme_stylebox_override("panel", _result_panel_style())
	center.add_child(_result_card)

	var margin := MarginContainer.new()
	margin.name = "ResultMargin"
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_result_eyebrow = _make_label(13, GOLD)
	_result_eyebrow.text = "配送结算 · DELIVERY REPORT"
	_result_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_eyebrow)

	var badge_row := HBoxContainer.new()
	badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(badge_row)
	_result_badge = PanelContainer.new()
	_result_badge.custom_minimum_size = Vector2(72, 72)
	_result_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_badge.add_theme_stylebox_override("panel", _badge_style(Color(MINT.r, MINT.g, MINT.b, 0.14), Color(MINT.r, MINT.g, MINT.b, 0.55)))
	badge_row.add_child(_result_badge)
	_result_icon = _make_label(38, MINT, true)
	_result_icon.text = "✓"
	_result_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_badge.add_child(_result_icon)

	_result_title = _make_label(50, MINT, true, 6)
	_result_title.text = "订单完成"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)

	_result_route = _make_label(17, TEXT_COLOR, false, 3)
	_result_route.text = "商家  →  顾客"
	_result_route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_result_route)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)
	_make_stat("总路程", stats)
	_make_stat("用时", stats)
	_make_stat("剩余时间", stats)

	_result_income = _make_label(22, GOLD, true)
	_result_income.text = "本单收入  ¥0.00"
	_result_income.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_income)

	_result_body = _make_label(14, MUTED_UI, false, 3)
	_result_body.text = "城市种子 — · 订单种子 —"
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_result_body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(buttons)
	_result_next_button = _make_button("下一单（R）", true)
	_result_next_button.custom_minimum_size = Vector2(220, 54)
	_result_next_button.pressed.connect(func() -> void: next_order_pressed.emit())
	buttons.add_child(_result_next_button)
	_result_menu_button = _make_button("返回主菜单", false)
	_result_menu_button.custom_minimum_size = Vector2(200, 54)
	_result_menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_result_menu_button)

	_result_hint = _make_label(13, MUTED_UI)
	_result_hint.text = "按 R 开始下一单"
	_result_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_hint)


func _add_control_row(caption: String, keys: String) -> void:
	var caption_label := _make_label(14, MUTED_UI)
	caption_label.text = caption
	_start_controls_grid.add_child(caption_label)
	var key_label := _make_label(15, TEXT_COLOR, true)
	key_label.text = keys
	_start_controls_grid.add_child(key_label)


func _make_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _chip_style())
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(margin)
	var label := _make_label(13, GOLD_BRIGHT)
	label.text = text
	margin.add_child(label)
	return chip


func _make_stat(caption: String, parent: HBoxContainer) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 84)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _stat_style())
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var caption_label := _make_label(12, MUTED_UI)
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption_label)
	var value := _make_label(25, TEXT_COLOR, true)
	value.text = "—"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)
	_result_stat_values.append(value)
	return panel


func _set_menu_visible(start_visible: bool, result_visible: bool) -> void:
	_start_layer.visible = start_visible
	_result_layer.visible = result_visible
	_start_backdrop.set_active(start_visible)
	_result_backdrop.set_active(result_visible)


func _animate_in(control: Control) -> void:
	if not is_inside_tree() or control == null:
		return
	control.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, 0.26)


func _request_responsive_layout() -> void:
	if _responsive_pending:
		return
	_responsive_pending = true
	call_deferred("_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_responsive_pending = false
	if _root == null:
		return
	var viewport := _root.get_viewport_rect().size
	if viewport.x < 1.0 or viewport.y < 1.0:
		return
	var narrow := viewport.x < 560.0
	var compact := viewport.x < 900.0 or viewport.y < 760.0
	# 右上角两块在小屏上收窄，避免挡住画面中间。
	var right_width := clampf(viewport.x * 0.32, 210.0, 340.0)
	_right_column.offset_left = -(right_width + 24.0)
	_right_column.offset_right = -24.0
	var side := 24 if narrow else (46 if compact else 96)
	var top := 24 if narrow else (36 if compact else 56)
	_set_margin(_start_page_margin, side, side, top, top)
	var content_width := minf(760.0, viewport.x - side * 2.0)
	_start_content.custom_minimum_size.x = content_width
	_start_subtitle.custom_minimum_size.x = content_width
	_start_title.add_theme_font_size_override("font_size", 44 if narrow else (58 if compact else 76))
	_start_subtitle.add_theme_font_size_override("font_size", 16 if narrow else (18 if compact else 21))
	_start_content.add_theme_constant_override("separation", 10 if compact else 14)
	_start_feature_row.visible = not compact
	_start_controls_panel.visible = not narrow and not TouchControls.is_touch_device()
	_start_touch_hint.visible = not _start_controls_panel.visible
	_start_button.custom_minimum_size.x = content_width if narrow else 320.0
	_start_button.custom_minimum_size.y = 54.0 if compact else 64.0

	var card_side := 18 if narrow else (28 if compact else 44)
	_result_card.custom_minimum_size.x = minf(720.0, viewport.x - card_side * 2.0)
	var result_margin := _result_card.get_node_or_null("ResultMargin") as MarginContainer
	if result_margin != null:
		var pad := 20 if narrow else (26 if compact else 36)
		_set_margin(result_margin, pad, pad, 20 if compact else 26, 20 if compact else 26)
	_result_title.add_theme_font_size_override("font_size", 36 if narrow else (42 if compact else 50))
	_result_route.add_theme_font_size_override("font_size", 14 if narrow else (16 if compact else 17))
	_result_badge.custom_minimum_size = Vector2(60, 60) if compact else Vector2(72, 72)
	_result_icon.add_theme_font_size_override("font_size", 30 if compact else 38)


func _set_margin(container: MarginContainer, left: int, right: int, top: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_bottom", bottom)


func _ensure_fonts() -> void:
	if _bold_font != null:
		return
	var base := load("res://assets/fonts/NotoSansSC-Regular.ttf") as Font
	if base == null:
		return
	_bold_font = FontVariation.new()
	_bold_font.base_font = base
	_bold_font.variation_embolden = 0.55


func _make_label(font_size: int, color: Color, bold := false, outline := 4) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold and _bold_font != null:
		label.add_theme_font_override("font", _bold_font)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		label.add_theme_constant_override("outline_size", outline)
	return label


func _make_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 21 if primary else 19)
	if _bold_font != null:
		button.add_theme_font_override("font", _bold_font)
	if primary:
		button.add_theme_stylebox_override("normal", _button_style(GOLD, Color(0, 0, 0, 0), 12, 0))
		button.add_theme_stylebox_override("hover", _button_style(GOLD_BRIGHT, Color(0, 0, 0, 0), 12, 0))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.88, 0.60, 0.20), Color(0, 0, 0, 0), 12, 0))
		button.add_theme_stylebox_override("focus", _button_style(GOLD_BRIGHT, GOLD_BRIGHT, 12, 2))
		button.add_theme_color_override("font_color", INK_TEXT)
		button.add_theme_color_override("font_hover_color", INK_TEXT)
		button.add_theme_color_override("font_pressed_color", INK_TEXT)
		button.add_theme_color_override("font_focus_color", INK_TEXT)
	else:
		button.add_theme_stylebox_override("normal", _button_style(Color(1, 1, 1, 0.035), GOLD_DIM, 12, 1))
		button.add_theme_stylebox_override("hover", _button_style(Color(GOLD.r, GOLD.g, GOLD.b, 0.12), GOLD, 12, 1))
		button.add_theme_stylebox_override("pressed", _button_style(Color(GOLD.r, GOLD.g, GOLD.b, 0.18), GOLD, 12, 1))
		button.add_theme_stylebox_override("focus", _button_style(Color(GOLD.r, GOLD.g, GOLD.b, 0.10), GOLD_BRIGHT, 12, 2))
		button.add_theme_color_override("font_color", GOLD_BRIGHT)
		button.add_theme_color_override("font_hover_color", TEXT_COLOR)
		button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
		button.add_theme_color_override("font_focus_color", TEXT_COLOR)
	return button


func _button_style(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _status_style() -> StyleBoxFlat:
	## 照参考照片：左上角深蓝底、金色描边的圆角面板。
	var style := StyleBoxFlat.new()
	style.bg_color = STATUS_BG
	style.border_color = STATUS_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	return style


func _right_panel_style() -> StyleBoxFlat:
	## 右上角两块和左上角状态面板同一套深蓝底、金色描边。
	var style := StyleBoxFlat.new()
	style.bg_color = STATUS_BG
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	return style


func _panel_margin() -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return margin


func _glass_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = GLASS_BG
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style


func _chip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.065)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(99)
	return style


func _stat_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.70, 0.82, 0.96, 0.045)
	style.border_color = Color(0.70, 0.82, 0.96, 0.10)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style


func _result_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.50)
	style.shadow_size = 28
	style.shadow_offset = Vector2(0, 12)
	return style


func _badge_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(36)
	return style


func _set_offer_panel(enabled: bool) -> void:
	## 接单时把左上角面板放大成照片里的单行提醒；其他状态恢复常规尺寸。
	if enabled:
		_status_panel.position = Vector2(24, 26)
		_status_panel.custom_minimum_size = Vector2(460, 150)
		_status_panel.size = Vector2(460, 150)
		_objective_label.add_theme_font_size_override("font_size", 20)
		_objective_label.add_theme_color_override("font_color", OFFER_TEXT_COLOR)
		_detail_label.visible = false
		return
	_status_panel.position = Vector2(24, 24)
	_status_panel.custom_minimum_size = Vector2(430, 0)
	_status_panel.size = Vector2(430, 0)
	_objective_label.add_theme_font_size_override("font_size", 24)
	_objective_label.add_theme_color_override("font_color", TEXT_COLOR)
	_detail_label.visible = true
