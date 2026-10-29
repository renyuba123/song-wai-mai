extends CanvasLayer
class_name RiderStatusHUD

## Minimal crash overlay. It stays invisible during normal riding and only
## appears after the rider-ground death condition has fired.

const PANEL_BG := Color(0.11, 0.025, 0.025, 0.92)
const ERROR_COLOR := Color(1.0, 0.39, 0.32, 1.0)
const TEXT_COLOR := Color(0.98, 0.95, 0.94, 1.0)

var _panel: PanelContainer = null
var _cause_label: Label = null
var _detail_label: Label = null


func _ready() -> void:
	layer = 30
	_build()
	_panel.visible = false


func show_death(cause: String, details: Dictionary) -> void:
	if _panel == null:
		return
	_panel.visible = true
	_cause_label.text = "骑手倒地：%s" % _cause_text(cause)
	var context := String(details.get("context", "normal_riding"))
	var speed := float(details.get("speed_mps", 0.0))
	_detail_label.text = "%s  /  倒地速度 %.1f m/s\n按 R 重新开始当前订单" % [
		_context_text(context), speed
	]


func hide_status() -> void:
	if _panel != null:
		_panel.visible = false


func is_visible_status() -> bool:
	return _panel != null and _panel.visible


func get_cause_text() -> String:
	return _cause_label.text if _cause_label != null else ""


func _build() -> void:
	var root := Control.new()
	root.name = "RiderStatusOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "RiderStatusPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -270
	_panel.offset_right = 270
	_panel.offset_top = -178
	_panel.offset_bottom = -92
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = ERROR_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	_cause_label = _make_label("", 22, ERROR_COLOR)
	_cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_cause_label)
	_detail_label = _make_label("", 14, TEXT_COLOR)
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


static func _cause_text(cause: String) -> String:
	match cause:
		"rear_vehicle_collision":
			return "后方车辆追撞"
		"front_vehicle_collision":
			return "迎面车辆碰撞"
		"side_vehicle_collision":
			return "侧方车辆碰撞"
		"building_collision":
			return "撞击建筑"
		"unexplained_rollover":
			return "车辆翻转"
		"test_impact":
			return "测试冲击"
	return "事故翻车"


static func _context_text(context: String) -> String:
	if context == "evading_pedestrian":
		return "躲避行人时发生"
	return "普通骑行时发生"
