extends Node3D
class_name OrderPhone

## 挂在相机前的接单手机。收到订单时出现在车把左侧，屏幕由 SubViewport
## 渲染成手机界面；Y/N 或直接点击屏幕按钮处理订单，倒计时结束自动拒单。
## 配送期间手机保留在左侧，显示当前目标和剩余时间。

signal accept_pressed
signal reject_pressed
signal offer_expired

enum Mode { NONE, OFFER, ACTIVE }

const OFFER_TIMEOUT_S := 10.0

const SCREEN_SIZE := Vector2i(720, 1280)
const SCREEN_LOGICAL_SIZE := Vector2(360, 640)
const SCREEN_QUAD_SIZE := Vector2(0.158, 0.252)
const PHONE_SIZE := Vector3(0.172, 0.272, 0.012)
const PHONE_SCALE := 0.41
const PHONE_POSITION := Vector3(-0.064, -0.124, -0.44)
const PHONE_ROTATION_DEGREES := Vector3(-6.0, 3.0, 0.0)

const SCREEN_BG := Color(0.93, 0.94, 0.95, 1.0)
const CARD_BG := Color(1.0, 1.0, 1.0, 1.0)
const TEXT_DARK := Color(0.08, 0.09, 0.11, 1.0)
const TEXT_MUTED := Color(0.49, 0.53, 0.58, 1.0)
const FOOTER_COLOR := Color(0.58, 0.61, 0.65, 1.0)
const ACCEPT_COLOR := Color(0.07, 0.60, 0.34, 1.0)
const REJECT_BG := Color(0.84, 0.86, 0.88, 1.0)
const MERCHANT_COLOR := Color(0.95, 0.54, 0.15, 1.0)
const COUNTDOWN_COLOR := Color(0.88, 0.35, 0.15, 1.0)

var _camera: Camera3D = null
var _screen: MeshInstance3D = null
var _viewport: SubViewport = null
var _mode := Mode.NONE
var _screen_text := ""
var _remaining_s := 0.0
var _expired_emitted := false
var _pointer_down := false
var _last_pixel := Vector2.ZERO

var _status_left: Label = null
var _status_right: Label = null

var _offer_card: Control = null
var _merchant_label: Label = null
var _merchant_detail: Label = null
var _customer_detail: Label = null
var _distance_label: Label = null
var _income_label: Label = null
var _footer_label: Label = null
var _accept_button: Button = null
var _reject_button: Button = null

var _active_card: Control = null
var _active_title: Label = null
var _active_objective: Label = null
var _active_detail: Label = null
var _active_distance: Label = null
var _active_time: Label = null
var _active_hint: Label = null


func _ready() -> void:
	scale = Vector3.ONE * PHONE_SCALE
	position = PHONE_POSITION
	rotation_degrees = PHONE_ROTATION_DEGREES
	_build_model()
	_build_screen()
	hide_phone()


func setup(camera: Camera3D) -> void:
	_camera = camera


func show_offer(order: DeliveryOrder, time_limit: float) -> void:
	if order == null:
		return
	_mode = Mode.OFFER
	_remaining_s = OFFER_TIMEOUT_S
	_expired_emitted = false
	_pointer_down = false
	_screen_text = format_offer_text(order, time_limit)
	if _merchant_label != null:
		var total_km := maxf(order.get_total_path_length_m(), 0.0) / 1000.0
		_merchant_label.text = "商家 · %s" % _site_name(order.merchant)
		_merchant_detail.text = _site_detail("取餐", order.merchant, "取餐点")
		_customer_detail.text = _site_detail("送达", order.customer, "送达站点")
		_distance_label.text = "%.1f km" % total_km
		_income_label.text = "¥ %d" % expected_income(order, time_limit)
		_status_left.text = "▂▄▆  %s" % Time.get_time_string_from_system().substr(0, 5)
		_status_right.text = "42  ▮"
	_update_countdown()
	_sync_mode()


func show_active(order: DeliveryOrder, session: OrderSession) -> void:
	if order == null or session == null:
		return
	_mode = Mode.ACTIVE
	_screen_text = "配送中"
	if _active_title != null:
		_status_left.text = "▂▄▆  %s" % Time.get_time_string_from_system().substr(0, 5)
		_status_right.text = "42  ▮"
		_active_title.text = "配送中"
		var start_position := Vector3.ZERO
		if order.start != null:
			start_position = order.start.position
		update_active(session, start_position)
	_sync_mode()


func update_active(session: OrderSession, player_position: Vector3) -> void:
	if _mode != Mode.ACTIVE or session == null or not session.is_active():
		return
	if _active_objective == null:
		return
	var target := session.get_target_site()
	_active_objective.text = session.get_objective_text()
	_active_detail.text = _site_detail(
		"商家" if session.state == OrderSession.State.TO_MERCHANT else "顾客",
		target,
		"取餐点" if session.state == OrderSession.State.TO_MERCHANT else "送达站点"
	)
	_active_distance.text = "距离 %d m" % roundi(
		session.get_distance_to_target(player_position)
	)
	_active_time.text = "剩余 %s" % OrderHUD.format_time(session.time_remaining)
	var can_interact := session.can_interact(player_position)
	_active_hint.text = (
		session.get_interact_prompt() if can_interact
		else "沿路线前往目标 · E 交互 · R 重新开始本单"
	)
	_screen_text = "\n".join([
		"配送中",
		session.get_objective_text(),
		_active_detail.text,
		_active_distance.text,
		_active_time.text,
	])


func hide_phone() -> void:
	_mode = Mode.NONE
	_pointer_down = false
	_screen_text = ""
	_sync_mode()


func hide_offer() -> void:
	## 保留旧名字给现有调用方；手机在配送中也会显示，统一按隐藏处理。
	hide_phone()


func advance(delta: float) -> void:
	if _mode != Mode.OFFER or delta <= 0.0:
		return
	_remaining_s = maxf(0.0, _remaining_s - delta)
	_update_countdown()
	if _remaining_s > 0.0:
		return
	_mode = Mode.NONE
	_sync_mode()
	if not _expired_emitted:
		_expired_emitted = true
		offer_expired.emit()


func is_offer_visible() -> bool:
	return _mode == Mode.OFFER and visible


func is_active_visible() -> bool:
	return _mode == Mode.ACTIVE and visible


func is_phone_visible() -> bool:
	return _mode != Mode.NONE and visible


func get_remaining_s() -> float:
	return _remaining_s


func get_screen_text() -> String:
	return _screen_text


func get_screen_size() -> Vector2i:
	return SCREEN_SIZE


## 接单时显示的收入按限时估满额（假设全部剩余时间都拿到）；
## 结算和收支面板用实际剩余时间调用同一个 DeliveryIncome 公式。
static func expected_income(order: DeliveryOrder, time_limit: float) -> int:
	if order == null:
		return DeliveryIncome.calculate(0.0, 0.0)
	return DeliveryIncome.calculate(order.get_total_path_length_m(), time_limit)


static func format_offer_text(order: DeliveryOrder, time_limit: float) -> String:
	if order == null:
		return ""
	var total_km := maxf(order.get_total_path_length_m(), 0.0) / 1000.0
	return "\n".join([
		"新外卖订单",
		"取餐：%s" % OrderHUD.site_label(order.merchant),
		"送达：%s" % OrderHUD.site_label(order.customer),
		"总路程 %.1f km" % total_km,
		"预计收入 ¥%d" % expected_income(order, time_limit),
		"限时 %s · 城市种子 %d · 订单种子 %d" % [
			OrderHUD.format_time(time_limit), order.city_seed, order.order_seed
		],
	])


static func _site_name(site: CitySite) -> String:
	if site == null:
		return "未知站点"
	if not site.display_name.is_empty():
		return site.display_name
	return OrderHUD.site_label(site)


static func _site_detail(prefix: String, site: CitySite, fallback: String) -> String:
	if site != null and site.lot_id >= 0:
		return "%s · 地块 %d %s" % [prefix, site.lot_id, fallback]
	return "%s · %s" % [prefix, fallback]


func _update_countdown() -> void:
	if _footer_label == null:
		return
	_footer_label.text = "Y 接单 · N 拒单 · 剩余 %d 秒" % ceili(_remaining_s)
	_footer_label.add_theme_color_override(
		"font_color", COUNTDOWN_COLOR if _remaining_s <= 3.0 else FOOTER_COLOR
	)


func _sync_mode() -> void:
	visible = _mode != Mode.NONE
	if _offer_card != null:
		_offer_card.visible = _mode == Mode.OFFER
	if _active_card != null:
		_active_card.visible = _mode == Mode.ACTIVE
	if _viewport != null:
		_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
		)


func _unhandled_input(event: InputEvent) -> void:
	if _mode != Mode.OFFER:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var inside := _screen_point(event.position) != null
		if inside or _pointer_down:
			_pointer_down = event.pressed
			_push_pointer(event.position, event.pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var inside := _screen_point(event.position) != null
		if inside or _pointer_down:
			_pointer_down = event.pressed
			_push_pointer(event.position, event.pressed)
			get_viewport().set_input_as_handled()


## 把屏幕空间坐标投到手机屏幕上；命中时返回 SubViewport 内像素坐标。
func _screen_point(screen_position: Vector2) -> Variant:
	if _screen == null:
		return null
	var camera := _camera
	if camera == null:
		camera = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var normal := _screen.global_transform.basis.z.normalized()
	# Godot 的 Plane.d 是 normal·point，不是平面方程的负常数项。
	var plane := Plane(normal, normal.dot(_screen.global_position))
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return null
	var hit_position: Vector3 = hit
	var local: Vector3 = _screen.global_transform.affine_inverse() * hit_position
	var half := SCREEN_QUAD_SIZE * 0.5
	if absf(local.x) > half.x or absf(local.y) > half.y:
		return null
	return Vector2(
		(local.x / SCREEN_QUAD_SIZE.x + 0.5) * SCREEN_SIZE.x,
		(0.5 - local.y / SCREEN_QUAD_SIZE.y) * SCREEN_SIZE.y
	)


func _push_pointer(screen_position: Vector2, pressed: bool) -> void:
	var pixel: Variant = _screen_point(screen_position)
	if pixel == null:
		if not pressed and _pointer_down == false and _last_pixel != Vector2.ZERO:
			pixel = _last_pixel
		else:
			return
	var pixel_position: Vector2 = pixel
	_last_pixel = pixel_position
	var event := InputEventMouseButton.new()
	event.position = pixel_position
	event.global_position = pixel_position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_viewport.push_input(event, true)


func _build_model() -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	var mesh := BoxMesh.new()
	mesh.size = PHONE_SIZE
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.04, 0.055, 1.0)
	material.roughness = 0.42
	material.metallic = 0.18
	body.material_override = material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

	var camera_bar := MeshInstance3D.new()
	camera_bar.name = "CameraDot"
	var dot := SphereMesh.new()
	dot.radius = 0.004
	dot.height = 0.008
	dot.radial_segments = 12
	dot.rings = 6
	camera_bar.mesh = dot
	var dot_material := StandardMaterial3D.new()
	dot_material.albedo_color = Color(0.02, 0.02, 0.03, 1.0)
	camera_bar.material_override = dot_material
	camera_bar.position = Vector3(0.0, PHONE_SIZE.y * 0.5 - 0.010, PHONE_SIZE.z * 0.5 + 0.002)
	camera_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(camera_bar)


func _build_screen() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ScreenViewport"
	_viewport.size = SCREEN_SIZE
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_build_screen_ui()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = SCREEN_QUAD_SIZE
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	_screen.mesh = quad
	_screen.material_override = material
	_screen.position = Vector3(0.0, 0.0, PHONE_SIZE.z * 0.5 + 0.001)
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_screen)


func _build_screen_ui() -> void:
	# 屏幕纹理按 2 倍分辨率绘制，缩小到手机大小后文字边缘更干净。
	var root := Control.new()
	root.name = "ScreenUI"
	root.size = SCREEN_LOGICAL_SIZE
	root.scale = Vector2(2.0, 2.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(root)

	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = SCREEN_BG
	background_style.set_corner_radius_all(18)
	background.add_theme_stylebox_override("panel", background_style)
	root.add_child(background)

	_status_left = _make_label(11, TEXT_MUTED)
	_status_left.anchor_right = 1.0
	_status_left.offset_left = 18
	_status_left.offset_right = -18
	_status_left.offset_top = 10
	_status_left.offset_bottom = 30
	root.add_child(_status_left)
	_status_right = _make_label(11, TEXT_MUTED)
	_status_right.anchor_right = 1.0
	_status_right.offset_left = 18
	_status_right.offset_right = -18
	_status_right.offset_top = 10
	_status_right.offset_bottom = 30
	_status_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_status_right)

	_build_offer_ui(root)
	_build_active_ui(root)

	_footer_label = _make_label(12, FOOTER_COLOR)
	_footer_label.anchor_left = 0.0
	_footer_label.anchor_right = 1.0
	_footer_label.anchor_top = 1.0
	_footer_label.anchor_bottom = 1.0
	_footer_label.offset_top = -48
	_footer_label.offset_bottom = -26
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_footer_label)


func _build_offer_ui(root: Control) -> void:
	_offer_card = PanelContainer.new()
	_offer_card.name = "OfferCard"
	_offer_card.anchor_right = 1.0
	_offer_card.offset_left = 18
	_offer_card.offset_right = -18
	_offer_card.offset_top = 74
	_offer_card.offset_bottom = 540
	_offer_card.add_theme_stylebox_override("panel", _card_style())
	root.add_child(_offer_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offer_card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := _make_label(38, TEXT_DARK, true)
	title.text = "新外卖订单"
	box.add_child(title)

	var subtitle := _make_label(16, TEXT_MUTED)
	subtitle.text = "待接单 · 请确认取餐和送达信息"
	box.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 4.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)

	var merchant_row := HBoxContainer.new()
	merchant_row.add_theme_constant_override("separation", 10)
	merchant_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(merchant_row)
	var dot := ColorRect.new()
	dot.color = MERCHANT_COLOR
	dot.custom_minimum_size = Vector2(4.0, 18.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	merchant_row.add_child(dot)
	_merchant_label = _make_label(24, TEXT_DARK, true)
	merchant_row.add_child(_merchant_label)

	_merchant_detail = _make_label(16, TEXT_MUTED)
	box.add_child(_merchant_detail)
	_customer_detail = _make_label(16, TEXT_MUTED)
	box.add_child(_customer_detail)

	var stat_gap := Control.new()
	stat_gap.custom_minimum_size = Vector2(0.0, 5.0)
	stat_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stat_gap)

	var distance_row := HBoxContainer.new()
	distance_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(distance_row)
	var distance_caption := _make_label(22, TEXT_DARK, true)
	distance_caption.text = "总路程"
	distance_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	distance_row.add_child(distance_caption)
	_distance_label = _make_label(22, TEXT_DARK, true)
	distance_row.add_child(_distance_label)

	var income_row := HBoxContainer.new()
	income_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(income_row)
	var income_caption := _make_label(17, TEXT_MUTED)
	income_caption.text = "预计收入"
	income_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	income_row.add_child(income_caption)
	_income_label = _make_label(30, ACCEPT_COLOR, true)
	income_row.add_child(_income_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(buttons)

	_reject_button = _make_button("拒绝  N", REJECT_BG, TEXT_DARK, 88, 21)
	_reject_button.name = "RejectButton"
	_reject_button.size_flags_stretch_ratio = 0.92
	_reject_button.pressed.connect(func() -> void: reject_pressed.emit())
	buttons.add_child(_reject_button)

	_accept_button = _make_button("立即接单  Y", ACCEPT_COLOR, Color.WHITE, 88, 21)
	_accept_button.name = "AcceptButton"
	_accept_button.size_flags_stretch_ratio = 1.08
	_accept_button.pressed.connect(func() -> void: accept_pressed.emit())
	buttons.add_child(_accept_button)


func _build_active_ui(root: Control) -> void:
	_active_card = PanelContainer.new()
	_active_card.name = "ActiveCard"
	_active_card.anchor_right = 1.0
	_active_card.offset_left = 18
	_active_card.offset_right = -18
	_active_card.offset_top = 74
	_active_card.offset_bottom = 540
	_active_card.add_theme_stylebox_override("panel", _card_style())
	root.add_child(_active_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_active_card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_active_title = _make_label(34, TEXT_DARK, true)
	box.add_child(_active_title)

	_active_objective = _make_label(22, TEXT_DARK, true)
	_active_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_active_objective)

	_active_detail = _make_label(16, TEXT_MUTED)
	_active_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_active_detail)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_active_distance = _make_label(22, TEXT_DARK, true)
	box.add_child(_active_distance)
	_active_time = _make_label(22, ACCEPT_COLOR, true)
	box.add_child(_active_time)

	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer2)

	_active_hint = _make_label(14, TEXT_MUTED)
	_active_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_active_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_active_hint)


func _make_label(font_size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		# 项目只有常规字重，用同色描边模拟加粗，接近照片里的标题效果。
		label.add_theme_color_override("font_outline_color", color)
		label.add_theme_constant_override("outline_size", 1)
	return label


func _make_button(
	text: String, background: Color, text_color: Color, height: int, font_size: int
) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	var normal := StyleBoxFlat.new()
	normal.bg_color = background
	normal.set_corner_radius_all(10)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = background.lightened(0.06)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = background.darkened(0.08)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.set_corner_radius_all(16)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	# 屏幕纹理经过 3D 色调映射后白色和浅灰很接近，用淡阴影把卡片分出来。
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.10)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 2.0)
	return style
