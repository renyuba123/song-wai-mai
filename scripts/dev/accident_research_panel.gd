extends CanvasLayer
class_name AccidentResearchPanel

## Debug-only accident recorder. F8 reveals the aggregate panel; every death is
## also appended as one JSON line so cause/context research can continue offline.

const PANEL_BG := Color(0.035, 0.045, 0.065, 0.96)
const TEXT_COLOR := Color(0.94, 0.97, 1.0, 1.0)
const MUTED_COLOR := Color(0.68, 0.76, 0.84, 1.0)
const ACCENT_COLOR := Color(1.0, 0.67, 0.28, 1.0)
const REAR_COLOR := Color(1.0, 0.4, 0.34, 1.0)

@export var write_jsonl := true
@export var log_path := "user://accident_research.jsonl"
@export var allow_toggle_in_release := true

var _panel: PanelContainer = null
var _summary_label: Label = null
var _latest_label: Label = null
var _records: Array[Dictionary] = []
var _cause_counts: Dictionary = {}
var _context_counts: Dictionary = {}


func _ready() -> void:
	layer = 50
	_build()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and _is_key(key_event, KEY_F8):
		if OS.is_debug_build() or allow_toggle_in_release:
			toggle_panel()
			get_viewport().set_input_as_handled()


func _is_key(event: InputEventKey, key: Key) -> bool:
	return (
		event.keycode == key
		or event.physical_keycode == key
		or event.key_label == key
	)


func record_death(cause: String, details: Dictionary) -> void:
	var normalized_cause := cause if not cause.is_empty() else "unknown"
	var context := String(details.get("context", "unknown"))
	_cause_counts[normalized_cause] = int(_cause_counts.get(normalized_cause, 0)) + 1
	_context_counts[context] = int(_context_counts.get(context, 0)) + 1
	var record := {
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"cause": normalized_cause,
		"context": context,
		"speed_mps": float(details.get("speed_mps", 0.0)),
		"impact_speed_mps": float(details.get("impact_speed_mps", 0.0)),
		"source": String(details.get("source", "")),
		"position": _position_to_array(details.get("position", Vector3.ZERO)),
	}
	_records.append(record)
	if write_jsonl:
		_append_jsonl(record)
	_refresh()


func toggle_panel() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	_refresh()


func show_panel() -> void:
	if _panel != null:
		_panel.visible = true
		_refresh()


func hide_panel() -> void:
	if _panel != null:
		_panel.visible = false


func is_panel_visible() -> bool:
	return _panel != null and _panel.visible


func get_total_deaths() -> int:
	return _records.size()


func get_cause_count(cause: String) -> int:
	return int(_cause_counts.get(cause, 0))


func get_context_count(context: String) -> int:
	return int(_context_counts.get(context, 0))


func get_records() -> Array[Dictionary]:
	return _records.duplicate(true)


func get_summary_text() -> String:
	return _summary_label.text if _summary_label != null else ""


func _refresh() -> void:
	if _summary_label == null:
		return
	var lines := [
		"交通事故研究  /  总死亡 %d" % get_total_deaths(),
		"后方来车碰撞      %d" % get_cause_count("rear_vehicle_collision"),
		"前方车辆碰撞      %d" % get_cause_count("front_vehicle_collision"),
		"侧方车辆碰撞      %d" % get_cause_count("side_vehicle_collision"),
		"建筑撞击          %d" % get_cause_count("building_collision"),
		"原因不明翻车      %d" % get_cause_count("unexplained_rollover"),
		"",
		"躲避行人情境      %d" % get_context_count("evading_pedestrian"),
		"普通骑行情境      %d" % get_context_count("normal_riding"),
	]
	_summary_label.text = "\n".join(lines)
	if _records.is_empty():
		_latest_label.text = "尚无事故记录"
		return
	var latest := _records[_records.size() - 1]
	_latest_label.text = "最近记录：%s / %s / %.1f m/s" % [
		String(latest.get("cause", "unknown")),
		String(latest.get("context", "unknown")),
		float(latest.get("speed_mps", 0.0)),
	]


func _build() -> void:
	var root := Control.new()
	root.name = "AccidentResearchOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "AccidentResearchPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -310
	_panel.offset_right = 310
	_panel.offset_top = -225
	_panel.offset_bottom = 225
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(1.0, 0.55, 0.28, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := _make_label("开发研究数据", 25, ACCENT_COLOR)
	box.add_child(title)
	var hint := _make_label("仅调试构建可见，研究用统计不进入日常玩法界面", 13, MUTED_COLOR)
	box.add_child(hint)
	_summary_label = _make_label("", 17, TEXT_COLOR)
	box.add_child(_summary_label)
	_latest_label = _make_label("", 14, MUTED_COLOR)
	box.add_child(_latest_label)
	_refresh()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _append_jsonl(record: Dictionary) -> void:
	var file: FileAccess = null
	if FileAccess.file_exists(log_path):
		file = FileAccess.open(log_path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		push_warning("无法写入交通事故研究日志：%s" % log_path)
		return
	file.store_line(JSON.stringify(record))
	file.close()


func _position_to_array(value: Variant) -> Array:
	if value is Vector3:
		var position := value as Vector3
		return [position.x, position.y, position.z]
	return []
