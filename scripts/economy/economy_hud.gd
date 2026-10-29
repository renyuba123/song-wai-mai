extends CanvasLayer
class_name EconomyHUD

## Persistent delivery economy display. Values are intentionally kept in coins
## rather than a real currency so research builds can tune them quickly.

signal balance_changed(balance: int)
signal compensation_added(amount: int, total_compensation: int)

const BASE_DELIVERY_INCOME := 180
const DISTANCE_INCOME_PER_M := 1.2
const TIME_BONUS_PER_SECOND := 0.8
const PANEL_BG := Color(0.035, 0.055, 0.075, 0.92)
const TEXT_COLOR := Color(0.95, 0.97, 1.0, 1.0)
const MUTED_COLOR := Color(0.68, 0.76, 0.84, 1.0)
const INCOME_COLOR := Color(0.25, 0.91, 0.66, 1.0)
const EXPENSE_COLOR := Color(1.0, 0.48, 0.38, 1.0)

@export var starting_balance := 500

var _balance := 0
var _current_order_income := 0
var _total_income := 0
var _total_compensation := 0
var _balance_label: Label = null
var _order_label: Label = null
var _summary_label: Label = null


func _ready() -> void:
	layer = 9
	_balance = starting_balance
	_build()
	_refresh()


func begin_order() -> void:
	_current_order_income = 0
	_refresh()


func record_successful_delivery(distance_m: float, remaining_s: float) -> int:
	var distance_bonus := roundi(maxf(distance_m, 0.0) * DISTANCE_INCOME_PER_M)
	var time_bonus := roundi(maxf(remaining_s, 0.0) * TIME_BONUS_PER_SECOND)
	var income := BASE_DELIVERY_INCOME + distance_bonus + time_bonus
	_total_income += income
	_current_order_income = income
	_balance += income
	_refresh()
	balance_changed.emit(_balance)
	return income


func add_compensation(amount: int) -> void:
	var applied := maxi(amount, 0)
	if applied == 0:
		return
	_total_compensation += applied
	_balance -= applied
	_refresh()
	compensation_added.emit(applied, _total_compensation)
	balance_changed.emit(_balance)


func reset_economy() -> void:
	_balance = starting_balance
	_current_order_income = 0
	_total_income = 0
	_total_compensation = 0
	_refresh()
	balance_changed.emit(_balance)


func get_balance() -> int:
	return _balance


func get_current_order_income() -> int:
	return _current_order_income


func get_total_income() -> int:
	return _total_income


func get_total_compensation() -> int:
	return _total_compensation


func get_summary_text() -> String:
	return "本单收入 %d\n累计收入 %d\n累计赔偿 %d" % [
		_current_order_income, _total_income, _total_compensation
	]


func _refresh() -> void:
	if _balance_label == null:
		return
	_balance_label.text = "余额  %d" % _balance
	_balance_label.add_theme_color_override(
		"font_color", INCOME_COLOR if _balance >= 0 else EXPENSE_COLOR
	)
	_order_label.text = "本单收入  +%d" % _current_order_income
	_order_label.add_theme_color_override("font_color", INCOME_COLOR)
	_summary_label.text = "累计收入  %d\n累计赔偿  -%d" % [
		_total_income, _total_compensation
	]


func _build() -> void:
	var root := Control.new()
	root.name = "EconomyOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "EconomyPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -286
	panel.offset_right = -24
	panel.offset_top = 24
	panel.offset_bottom = 170
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(0.24, 0.88, 0.96, 0.52)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := _make_label("配送收支", 14, MUTED_COLOR)
	box.add_child(title)
	_balance_label = _make_label("", 28, TEXT_COLOR)
	box.add_child(_balance_label)
	_order_label = _make_label("", 15, INCOME_COLOR)
	box.add_child(_order_label)
	_summary_label = _make_label("", 14, MUTED_COLOR)
	box.add_child(_summary_label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	return label
