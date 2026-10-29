extends Control
class_name PhoneOrderNotification

signal order_accepted(order_id: String)
signal order_rejected(order_id: String)

const IN_DURATION := 0.32
const OUT_DURATION := 0.20
const FEEDBACK_DURATION := 1.5
const CARD_TOP := 150.0
const INK := Color("182c34")
const MUTED := Color("687c85")
const GREEN := Color("12805d")

var current_order_id := ""
var has_pending_order := false
var card: PanelContainer
var accept_button: Button
var reject_button: Button
var shop_label: Label
var pickup_label: Label
var destination_label: Label
var distance_label: Label
var reward_label: Label
var feedback: Label
var _tween: Tween
var _revision := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box

func _label(parent_node: Node, text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent_node.add_child(label)
	return label

func _build_ui() -> void:
	var background := Panel.new()
	background.name = "ScreenBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", _box(Color("e9edf1"), 34))
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var status := _label(self, "骑手工作台                         4G  ▰", 30)
	status.name = "StatusBar"
	status.position = Vector2(30, 26)
	var idle := _label(self, "等待新订单", 42, MUTED)
	idle.name = "IdleLabel"
	idle.position = Vector2(220, 520)
	card = PanelContainer.new()
	card.name = "PanelContainer"
	card.position = Vector2(24, CARD_TOP)
	card.size.x = 672
	card.minimum_size_changed.connect(_fit_card)
	var style := _box(Color.WHITE, 36)
	style.shadow_color = Color(0.1, 0.2, 0.25, 0.12)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 8)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.name = "VBoxContainer"
	content.add_theme_constant_override("separation", 20)
	margin.add_child(content)
	var title := _label(content, "新外卖订单", 52)
	title.name = "Header"
	_label(content, "NEW DELIVERY REQUEST", 27, MUTED)
	var divider := HSeparator.new()
	divider.custom_minimum_size.y = 8
	content.add_child(divider)
	shop_label = _label(content, "", 46)
	shop_label.name = "ShopLabel"
	shop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_label.custom_minimum_size.x = 580
	shop_label.max_lines_visible = 2
	shop_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pickup_label = _label(content, "", 36, MUTED)
	pickup_label.name = "PickupLabel"
	pickup_label.max_lines_visible = 2
	pickup_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pickup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	destination_label = _label(content, "", 36, MUTED)
	destination_label.name = "DestinationLabel"
	destination_label.max_lines_visible = 2
	destination_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	destination_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	distance_label = _label(content, "", 40)
	distance_label.name = "DistanceLabel"
	var earnings := HBoxContainer.new()
	earnings.name = "Earnings"
	content.add_child(earnings)
	var caption := _label(earnings, "预计收入", 36, MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_label = _label(earnings, "", 66, GREEN)
	reward_label.name = "RewardLabel"
	reward_label.clip_text = true
	reward_label.custom_minimum_size.x = 280
	reward_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var buttons := HBoxContainer.new()
	buttons.name = "ButtonContainer"
	buttons.add_theme_constant_override("separation", 18)
	content.add_child(buttons)
	reject_button = _button(buttons, "拒绝  N", false)
	reject_button.name = "RejectButton"
	accept_button = _button(buttons, "立即接单  Y", true)
	accept_button.name = "AcceptButton"
	reject_button.pressed.connect(reject_order)
	accept_button.pressed.connect(accept_order)
	feedback = _label(self, "", 50, GREEN)
	feedback.name = "Feedback"
	feedback.position = Vector2(30, 430)
	feedback.size = Vector2(660, 200)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback.hide()
	var hint := _label(self, "Y 接单   ·   N 拒单", 30, MUTED)
	hint.name = "KeyboardHint"
	hint.position = Vector2(200, 1000)
	card.hide()

func _button(parent_node: Node, text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 104)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 38)
	button.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color.WHITE if primary else INK)
	var color := GREEN if primary else Color("edf0f3")
	button.add_theme_stylebox_override("normal", _box(color, 20))
	button.add_theme_stylebox_override("hover", _box(color.lightened(0.08), 20))
	button.add_theme_stylebox_override("pressed", _box(color.darkened(0.08), 20))
	parent_node.add_child(button)
	return button

## Required: id, shop_name, pickup_address, destination_address,
## distance_m (meters), reward_yuan. Only one card exists, even on replacement.
func show_order(order_data: Dictionary) -> bool:
	if not is_node_ready():
		return false
	if not order_data.has_all(["id", "shop_name", "pickup_address", "destination_address", "distance_m", "reward_yuan"]):
		return false
	var id := str(order_data.id).strip_edges()
	if id.is_empty() or not (order_data.distance_m is float or order_data.distance_m is int) or not (order_data.reward_yuan is float or order_data.reward_yuan is int):
		return false
	var distance := float(order_data.distance_m)
	var reward := float(order_data.reward_yuan)
	if not is_finite(distance) or not is_finite(reward) or distance < 0.0 or reward < 0.0:
		return false
	_cancel_animation()
	current_order_id = id
	has_pending_order = true
	feedback.hide()
	get_node("IdleLabel").hide()
	# Bounded display strings avoid oversized cards; caller retains full data.
	shop_label.text = str(order_data.shop_name).left(24)
	pickup_label.text = "取餐 · " + str(order_data.pickup_address).left(30)
	destination_label.text = "送达 · " + str(order_data.destination_address).left(30)
	distance_label.text = "配送距离                 %.1f km" % (distance / 1000.0)
	reward_label.text = "¥ %.2f" % reward
	accept_button.disabled = false
	reject_button.disabled = false
	card.show()
	card.position = Vector2(24, -100)
	card.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(card, "position:y", CARD_TOP, IN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "modulate:a", 1.0, IN_DURATION)
	return true

func accept_order() -> void:
	_resolve(true)

func reject_order() -> void:
	_resolve(false)

func _resolve(accepted: bool) -> void:
	if not has_pending_order:
		return
	var id := current_order_id
	has_pending_order = false
	accept_button.disabled = true
	reject_button.disabled = true
	_cancel_animation()
	var revision := _revision
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(card, "modulate:a", 0.0, OUT_DURATION)
	_tween.tween_property(card, "position:y", CARD_TOP - 40, OUT_DURATION)
	_tween.chain().tween_callback(func() -> void:
		if revision != _revision:
			return
		card.hide()
		if accepted:
			feedback.text = "✓ 接单成功"
			feedback.show()
		else:
			get_node("IdleLabel").show()
	)
	if accepted:
		_tween.chain().tween_interval(FEEDBACK_DURATION)
		_tween.chain().tween_callback(func() -> void:
			if revision == _revision:
				feedback.hide()
				get_node("IdleLabel").show()
		)
		order_accepted.emit(id)
	else:
		order_rejected.emit(id)

func _cancel_animation() -> void:
	_revision += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()

func _fit_card() -> void:
	card.size = Vector2(672, card.get_combined_minimum_size().y)
