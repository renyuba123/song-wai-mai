extends CanvasLayer
class_name PauseController

## 配送中的暂停菜单：Esc 冻结场景树、释放鼠标并停玩家输入，
## 再按 Esc 或“继续”恢复；“重开本单”“返回主菜单”直接复用
## OrderManager 现有接口，不另写一套状态切换。

const PANEL_BG := Color(0.045, 0.06, 0.09, 0.84)
const TEXT_COLOR := Color(0.96, 0.97, 1.0, 1.0)
const MUTED_COLOR := Color(0.72, 0.78, 0.86, 1.0)
const ACCENT_COLOR := Color(1.0, 0.72, 0.28, 1.0)

var _orders: OrderManager = null
var _player: PlayerController = null
var _overlay: Control = null
var _seed_label: Label = null
var _resume_button: Button = null
var _controls_before_pause := false


func _ready() -> void:
	# 暂停时根节点仍要处理 Esc，内部遮罩在暂停期间才处理按钮。
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func setup(orders: OrderManager, player: PlayerController) -> void:
	_orders = orders
	_player = player


func can_pause() -> bool:
	## 只在配送进行中允许暂停；菜单、接单、结算和开始界面都返回 false。
	if _orders == null or _player == null or not _player.controls_enabled:
		return false
	if not _player.is_physics_processing():
		# 上帝视角等调试状态会关闭玩家物理，不要在那种状态下抢鼠标。
		return false
	var session := _orders.get_session()
	if session == null or not session.is_active():
		return false
	var hud := _orders.get_hud()
	if hud != null and hud.is_any_modal_visible():
		return false
	return true


func is_pause_visible() -> bool:
	return _overlay != null and _overlay.visible


func open_pause() -> bool:
	if is_pause_visible() or not can_pause():
		return false
	_controls_before_pause = _player.controls_enabled
	_player.set_controls_enabled(false)
	_refresh_seed_text()
	_overlay.visible = true
	_resume_button.grab_focus()
	get_tree().paused = true
	return true


func close_pause() -> void:
	if not is_pause_visible():
		return
	_exit_pause()
	_restore_controls(_controls_before_pause)


func resume() -> void:
	close_pause()


func restart_order() -> void:
	## handle_restart 在活动会话下重开同一单，并自己恢复玩家控制与位置。
	if not is_pause_visible() or _orders == null:
		return
	_exit_pause()
	if not _orders.handle_restart():
		_restore_controls(_controls_before_pause)


func return_to_menu() -> void:
	## return_to_start_menu 自己会关闭玩家控制并切回开始界面。
	if not is_pause_visible() or _orders == null:
		return
	_exit_pause()
	_orders.return_to_start_menu()


func get_seed_text() -> String:
	var city_text := "—"
	var order_text := "—"
	if _orders != null:
		var order := _orders.get_current_order()
		if order != null:
			city_text = str(order.city_seed)
			order_text = str(order.order_seed)
		else:
			order_text = str(_orders.get_order_seed())
	return "城市种子 %s · 订单种子 %s" % [city_text, order_text]


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if is_pause_visible():
		close_pause()
	else:
		# 开始菜单/接单/结算下按 Esc 不打开暂停层，也不让事件继续传给其它输入。
		open_pause()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	## 场景卸载或测试失败时不要把整个进程留在暂停状态。
	if is_pause_visible() and get_tree() != null:
		get_tree().paused = false


func _exit_pause() -> void:
	_overlay.visible = false
	if is_inside_tree():
		get_tree().paused = false


func _restore_controls(enabled: bool) -> void:
	if _player == null:
		return
	if enabled and not _player.controls_enabled:
		_player.set_controls_enabled(true)


func _refresh_seed_text() -> void:
	if _seed_label != null:
		_seed_label.text = get_seed_text()


func _build() -> void:
	_overlay = Control.new()
	_overlay.name = "PauseOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_overlay.visible = false
	add_child(_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -190
	panel.offset_bottom = 190
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style())
	_overlay.add_child(panel)

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

	var title := _make_label(28, ACCENT_COLOR)
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_seed_label = _make_label(16, MUTED_COLOR)
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_seed_label)

	var hint := _make_label(14, MUTED_COLOR)
	hint.text = "Esc 或“继续”返回游戏"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	_resume_button = _make_button("继续")
	_resume_button.pressed.connect(resume)
	box.add_child(_resume_button)

	var restart_button := _make_button("重开本单")
	restart_button.pressed.connect(restart_order)
	box.add_child(restart_button)

	var menu_button := _make_button("返回主菜单")
	menu_button.pressed.connect(return_to_menu)
	box.add_child(menu_button)


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
