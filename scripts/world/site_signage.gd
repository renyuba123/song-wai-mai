extends Node3D
class_name SiteSignage

## 城市站点的三维店名牌：每个商家/顾客门前悬浮一块朝向镜头的 Label3D。
## 当前订单目标加“★”并放大，其余站点降低透明度，方便在街景中快速辨认。

const HEIGHT_M := 3.2
const VIEW_DISTANCE_M := 160.0
const FADE_MARGIN_M := 40.0
const BASE_ALPHA := 0.78
const DIM_ALPHA := 0.32
const ACTIVE_SCALE := 1.15

const MERCHANT_COLOR := Color(1.0, 0.76, 0.34, 1.0)
const CUSTOMER_COLOR := Color(0.58, 0.86, 1.0, 1.0)

var _labels: Dictionary = {}
var _names: Dictionary = {}
var _colors: Dictionary = {}
var _active_id := ""


func build(city: CityContent) -> void:
	for child in get_children():
		child.queue_free()
	_labels.clear()
	_names.clear()
	_colors.clear()
	_active_id = ""
	if city == null:
		return
	for site in city.sites:
		if site == null or site.spawn_point == null or site.display_name.is_empty():
			continue
		var label := Label3D.new()
		label.name = "Site_%s" % site.id
		label.font_size = 64
		label.pixel_size = 0.01
		label.outline_size = 12
		label.outline_modulate = Color(0.02, 0.03, 0.08, 0.95)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.double_sided = true
		label.no_depth_test = false
		label.visibility_range_end = VIEW_DISTANCE_M
		label.visibility_range_end_margin = FADE_MARGIN_M
		label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		label.position = site.spawn_point.position + Vector3(0.0, HEIGHT_M, 0.0)
		add_child(label)
		var id := String(site.id)
		_labels[id] = label
		_names[id] = site.display_name
		_colors[id] = (
			MERCHANT_COLOR if site.kind == CitySite.Kind.MERCHANT else CUSTOMER_COLOR
		)
	_apply_active()


func set_active_target(site_id: StringName) -> void:
	var next := String(site_id)
	if next == _active_id:
		return
	_active_id = next
	_apply_active()


func get_label_count() -> int:
	return _labels.size()


func get_label_text(site_id: StringName) -> String:
	var label: Label3D = _labels.get(String(site_id))
	return label.text if label != null else ""


func get_active_target() -> String:
	return _active_id


func _apply_active() -> void:
	for id in _labels:
		var label: Label3D = _labels[id]
		var base_color: Color = _colors[id]
		var color := base_color
		if _active_id.is_empty():
			color.a = BASE_ALPHA
			label.text = String(_names[id])
			label.scale = Vector3.ONE
			label.no_depth_test = false
		elif id == _active_id:
			color.a = 1.0
			label.text = "★ " + String(_names[id])
			label.scale = Vector3.ONE * ACTIVE_SCALE
			# 当前目标像任务标记一样始终可见，避免被信标或建筑挡住。
			label.no_depth_test = true
		else:
			color.a = DIM_ALPHA
			label.text = String(_names[id])
			label.scale = Vector3.ONE
			label.no_depth_test = false
		label.modulate = color
