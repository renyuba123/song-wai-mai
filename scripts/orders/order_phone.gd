extends Node3D
class_name OrderPhone

## 挂在相机前的接单手机。收到订单时出现在视线下方，屏幕由 SubViewport
## 渲染成手机界面；Y/N 或直接点击屏幕按钮处理订单，倒计时结束自动拒单。

signal accept_pressed
signal reject_pressed
signal offer_expired

const OFFER_TIMEOUT_S := 10.0
const SCREEN_SIZE := Vector2i(360, 640)
const SCREEN_QUAD_SIZE := Vector2(0.16, 0.2844)
const PHONE_SIZE := Vector3(0.175, 0.32, 0.014)
const PHONE_POSITION := Vector3(0.0, -0.14, -0.44)
const PHONE_ROTATION_DEGREES := Vector3(-8.0, 0.0, 0.0)

const BASE_FEE := 4.5
const FEE_PER_KM := 0.38

const SCREEN_BG := Color(0.965, 0.973, 0.984, 1.0)
const CARD_BG := Color(1.0, 1.0, 1.0, 1.0)
const TEXT_DARK := Color(0.09, 0.11, 0.14, 1.0)
const TEXT_MUTED := Color(0.42, 0.46, 0.52, 1.0)
const ACCEPT_COLOR := Color(0.16, 0.72, 0.35, 1.0)
const REJECT_COLOR := Color(0.90, 0.92, 0.95, 1.0)
const COUNTDOWN_COLOR := Color(0.93, 0.45, 0.16, 1.0)
const CUSTOMER_COLOR := Color(0.12, 0.48, 0.86, 1.0)

var _camera: Camera3D = null
var _screen: MeshInstance3D = null
var _viewport: SubViewport = null
var _screen_text := ""
var _offer_active := false
var _remaining_s := 0.0
var _expired_emitted := false
var _pointer_down := false
var _last_pixel := Vector2.ZERO

var _status_time: Label = null
var _merchant_label: Label = null
var _customer_label: Label = null
var _distance_label: Label = null
var _fee_label: Label = null
var _limit_label: Label = null
var _countdown_label: Label = null
var _accept_button: Button = null
var _reject_button: Button = null


func _ready() -> void:
	visible = false
	position = PHONE_POSITION
	rotation_degrees = PHONE_ROTATION_DEGREES
	_build_model()
	_build_screen()
	_set_offer_visible(false)


func setup(camera: Camera3D) -> void:
	_camera = camera


func show_offer(order: DeliveryOrder, time_limit: float) -> void:
	if order == null:
		return
	_offer_active = true
	_remaining_s = OFFER_TIMEOUT_S
	_expired_emitted = false
	_pointer_down = false
	_screen_text = format_offer_text(order, time_limit)
	if _merchant_label != null:
		_merchant_label.text = _site_name(order.merchant)
		_customer_label.text = _site_name(order.customer)
		var total_km := maxf(order.get_total_path_length_m(), 0.0) / 1000.0
		_distance_label.text = "%.1f km" % total_km
		_fee_label.text = "¥%.2f" % calculate_fee(order)
		_limit_label.text = "限时 %s · 城市 %d · 订单 %d" % [
			OrderHUD.format_time(time_limit), order.city_seed, order.order_seed
		]
		_status_time.text = Time.get_time_string_from_system().substr(0, 5)
	_update_countdown()
	_set_offer_visible(true)
	# 首帧就渲染屏幕，避免刚出现时是一张空白贴图。
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func hide_offer() -> void:
	_offer_active = false
	_pointer_down = false
	_set_offer_visible(false)


func advance(delta: float) -> void:
	if not _offer_active or delta <= 0.0:
		return
	_remaining_s = maxf(0.0, _remaining_s - delta)
	_update_countdown()
	if _remaining_s > 0.0:
		return
	_offer_active = false
	_set_offer_visible(false)
	if not _expired_emitted:
		_expired_emitted = true
		offer_expired.emit()


func is_offer_visible() -> bool:
	return _offer_active and visible


func get_remaining_s() -> float:
	return _remaining_s


func get_screen_text() -> String:
	return _screen_text


func get_screen_size() -> Vector2i:
	return SCREEN_SIZE


## 配送费只由订单路程决定，保证同一订单每次显示一样。
static func calculate_fee(order: DeliveryOrder) -> float:
	if order == null:
		return BASE_FEE
	var total_km := maxf(order.get_total_path_length_m(), 0.0) / 1000.0
	return snappedf(BASE_FEE + total_km * FEE_PER_KM, 0.01)


static func format_offer_text(order: DeliveryOrder, time_limit: float) -> String:
	if order == null:
		return ""
	var total_km := maxf(order.get_total_path_length_m(), 0.0) / 1000.0
	return "\n".join([
		"新外卖订单",
		"取餐：%s" % OrderHUD.site_label(order.merchant),
		"送达：%s" % OrderHUD.site_label(order.customer),
		"总路程 %.1f km · 配送费 ¥%.2f" % [total_km, calculate_fee(order)],
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


func _update_countdown() -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = "剩余 %d 秒" % ceili(_remaining_s)
	_countdown_label.add_theme_color_override(
		"font_color", COUNTDOWN_COLOR if _remaining_s <= 3.0 else TEXT_MUTED
	)


func _set_offer_visible(active: bool) -> void:
	visible = active
	if _viewport != null:
		_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		)


func _unhandled_input(event: InputEvent) -> void:
	if not _offer_active:
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
	camera_bar.position = Vector3(0.0, PHONE_SIZE.y * 0.5 - 0.014, PHONE_SIZE.z * 0.5 + 0.002)
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
	var root := Control.new()
	root.name = "ScreenUI"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var status := HBoxContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(status)
	_status_time = _make_label(15, TEXT_MUTED)
	_status_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_status_time)
	var carrier := _make_label(15, TEXT_MUTED)
	carrier.text = "外卖骑手"
	carrier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(carrier)

	var title := _make_label(32, TEXT_DARK)
	title.text = "新外卖订单"
	box.add_child(title)

	var subtitle := _make_label(15, TEXT_MUTED)
	subtitle.text = "请确认取餐和送达信息"
	box.add_child(subtitle)

	box.add_child(_make_site_card("取餐", true))
	box.add_child(_make_site_card("送达", false))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)
	var distance_box := _make_stat_box("总路程", stats)
	_distance_label = distance_box
	var fee_box := _make_stat_box("配送费", stats)
	_fee_label = fee_box
	_fee_label.add_theme_color_override("font_color", ACCEPT_COLOR)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_limit_label = _make_label(14, TEXT_MUTED)
	_limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_limit_label)

	_countdown_label = _make_label(19, TEXT_MUTED)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_countdown_label)

	_accept_button = _make_button("Y 接单", ACCEPT_COLOR, Color.WHITE, 68, 28)
	_accept_button.name = "AcceptButton"
	_accept_button.pressed.connect(func() -> void: accept_pressed.emit())
	box.add_child(_accept_button)

	_reject_button = _make_button("N 拒单", REJECT_COLOR, TEXT_DARK, 50, 20)
	_reject_button.name = "RejectButton"
	_reject_button.pressed.connect(func() -> void: reject_pressed.emit())
	box.add_child(_reject_button)


func _make_site_card(prefix: String, merchant: bool) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _card_style())
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 3)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(card)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title_row)
	var prefix_label := _make_label(14, TEXT_MUTED)
	prefix_label.text = prefix
	prefix_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(prefix_label)
	var role := _make_label(14, ACCEPT_COLOR if merchant else CUSTOMER_COLOR)
	role.text = "商家" if merchant else "顾客"
	title_row.add_child(role)

	var value := _make_label(23, TEXT_DARK)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(value)
	if merchant:
		_merchant_label = value
	else:
		_customer_label = value
	return panel


func _make_stat_box(caption: String, parent: HBoxContainer) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _card_style())
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(card)
	var caption_label := _make_label(14, TEXT_MUTED)
	caption_label.text = caption
	card.add_child(caption_label)
	var value := _make_label(24, TEXT_DARK)
	card.add_child(value)
	parent.add_child(panel)
	return value


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
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
	normal.set_corner_radius_all(14)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = background.lightened(0.08)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = background.darkened(0.1)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.set_corner_radius_all(12)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
