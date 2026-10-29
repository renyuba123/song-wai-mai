extends Control
class_name MenuBackdrop

## 开始/结算界面共用背景：深蓝夜景、城市剪影、透视网格和一条缓慢流动的
## 配送路线。全部用 _draw() 画，不依赖额外贴图，窗口尺寸变化时重建。

const ACCENT := Color(1.0, 0.72, 0.30, 1.0)
const ACCENT_SOFT := Color(1.0, 0.78, 0.42, 0.24)
const GRID := Color(0.52, 0.70, 0.90, 0.055)
const SKY_TOP := Color(0.018, 0.035, 0.062, 0.97)
const SKY_BOTTOM := Color(0.035, 0.075, 0.120, 0.97)

var _elapsed := 0.0
var _active := true
var _draw_size := Vector2.ZERO
var _back: Array[Vector4] = []
var _front: Array[Vector4] = []
var _route := PackedVector2Array()
var _route_lengths := PackedFloat32Array()
var _route_total := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)
	set_process(true)
	_rebuild()


func set_active(active: bool) -> void:
	_active = active
	set_process(active)
	if active:
		queue_redraw()


func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree():
		return
	_elapsed += delta
	queue_redraw()


func _rebuild() -> void:
	_draw_size = size
	if _draw_size.x < 1.0 or _draw_size.y < 1.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029
	_back.clear()
	_front.clear()
	var x := -40.0
	while x < _draw_size.x + 80.0:
		var width := rng.randf_range(54.0, 150.0)
		_back.append(Vector4(x, width, rng.randf_range(70.0, 250.0), rng.randf()))
		x += width + rng.randf_range(6.0, 30.0)
	x = -60.0
	while x < _draw_size.x + 100.0:
		var width := rng.randf_range(70.0, 190.0)
		_front.append(Vector4(x, width, rng.randf_range(40.0, 170.0), rng.randf()))
		x += width + rng.randf_range(24.0, 70.0)
	_route = PackedVector2Array([
		Vector2(0.04, 0.84) * _draw_size,
		Vector2(0.20, 0.74) * _draw_size,
		Vector2(0.20, 0.50) * _draw_size,
		Vector2(0.47, 0.40) * _draw_size,
		Vector2(0.61, 0.20) * _draw_size,
		Vector2(0.96, 0.13) * _draw_size,
	])
	_route_lengths.resize(maxi(_route.size() - 1, 0))
	_route_total = 0.0
	for index in _route_lengths.size():
		_route_total += _route[index].distance_to(_route[index + 1])
		_route_lengths[index] = _route_total
	queue_redraw()


func _draw() -> void:
	if _draw_size.x < 1.0 or _draw_size.y < 1.0:
		return
	_draw_sky()
	_draw_grid()
	_draw_skyline(_back, 0.10, 0.0)
	_draw_skyline(_front, 0.20, 8.0)
	_draw_side_darkening()
	_draw_route()
	_draw_edges()


func _draw_sky() -> void:
	const BANDS := 48
	for band in BANDS:
		var t := float(band) / float(BANDS - 1)
		var color := SKY_TOP.lerp(SKY_BOTTOM, t)
		draw_rect(
			Rect2(0.0, _draw_size.y * t, _draw_size.x, _draw_size.y / BANDS + 1.0),
			color
		)
	# 左上角的一团冷光，把标题区域从背景里托出来。
	draw_circle(Vector2(_draw_size.x * 0.16, _draw_size.y * 0.18), _draw_size.y * 0.44, Color(0.18, 0.30, 0.48, 0.10))
	draw_circle(Vector2(_draw_size.x * 0.78, _draw_size.y * 0.70), _draw_size.y * 0.34, Color(0.12, 0.24, 0.40, 0.08))


func _draw_grid() -> void:
	var horizon := Vector2(_draw_size.x * 0.68, _draw_size.y * 0.40)
	for line in 16:
		var t := float(line) / 15.0
		var bottom := Vector2(_draw_size.x * (-0.35 + t * 1.9), _draw_size.y * 1.04)
		draw_line(horizon, bottom, GRID, 1.0)
	for line in 9:
		var t := pow(float(line) / 8.0, 1.8)
		var y := lerpf(horizon.y, _draw_size.y * 1.02, t)
		draw_line(Vector2(0.0, y), Vector2(_draw_size.x, y), GRID, 1.0)


func _draw_skyline(buildings: Array[Vector4], alpha: float, lift: float) -> void:
	var base := _draw_size.y + lift
	for building in buildings:
		var rect := Rect2(building.x, base - building.z, building.y, building.z)
		draw_rect(rect, Color(0.015, 0.035, 0.065, alpha))
		draw_line(
			Vector2(rect.position.x, rect.position.y),
			Vector2(rect.end.x, rect.position.y),
			Color(0.55, 0.75, 0.95, alpha * 0.35),
			1.0
		)
		if building.w < 0.42:
			continue
		var columns := maxi(1, int(building.y / 26.0))
		var rows := maxi(1, int(building.z / 30.0))
		for column in columns:
			for row in rows:
				if _hash01(building.w, column, row) < 0.62:
					continue
				var point := Vector2(
					rect.position.x + 9.0 + column * 24.0,
					rect.position.y + 12.0 + row * 26.0
				)
				if point.x > rect.end.x - 5.0 or point.y > rect.end.y - 6.0:
					continue
				draw_rect(Rect2(point, Vector2(3.0, 2.0)), Color(1.0, 0.78, 0.40, alpha * 0.75))


func _draw_side_darkening() -> void:
	const BANDS := 36
	for band in BANDS:
		var t := float(band) / float(BANDS - 1)
		var alpha := 0.86 * pow(1.0 - t, 2.1)
		draw_rect(
			Rect2(_draw_size.x * 0.72 * t, 0.0, _draw_size.x * 0.72 / BANDS + 1.0, _draw_size.y),
			Color(0.012, 0.025, 0.045, alpha)
		)
	for band in 12:
		var t := float(band) / 11.0
		draw_rect(
			Rect2(0.0, _draw_size.y * (0.66 + t * 0.34), _draw_size.x, _draw_size.y * 0.34 / 12.0 + 1.0),
			Color(0.01, 0.02, 0.04, 0.36 * t)
		)


func _draw_route() -> void:
	if _route.size() < 2:
		return
	for index in _route.size() - 1:
		draw_dashed_line(_route[index], _route[index + 1], ACCENT_SOFT, 1.6, 9.0)
	for point in _route:
		draw_circle(point, 9.0, Color(1.0, 0.72, 0.30, 0.06))
		draw_circle(point, 3.2, Color(1.0, 0.78, 0.44, 0.50))
	var pulse := fposmod(_elapsed * 0.045, 1.0)
	var point := _point_on_route(pulse * _route_total)
	draw_circle(point, 15.0, Color(1.0, 0.70, 0.28, 0.055))
	draw_circle(point, 6.0, Color(1.0, 0.82, 0.50, 0.22))
	draw_circle(point, 2.6, Color(1.0, 0.90, 0.68, 0.95))


func _draw_edges() -> void:
	for band in 10:
		var t := float(band) / 9.0
		draw_rect(
			Rect2(0.0, 0.0, _draw_size.x, _draw_size.y * 0.10 / 10.0 + 1.0),
			Color(0.0, 0.0, 0.0, 0.20 * (1.0 - t))
		)
		draw_rect(
			Rect2(0.0, _draw_size.y * (0.90 + t * 0.10), _draw_size.x, _draw_size.y * 0.10 / 10.0 + 1.0),
			Color(0.0, 0.0, 0.0, 0.30 * t)
		)


func _point_on_route(distance: float) -> Vector2:
	if _route.size() < 2 or _route_total <= 0.0:
		return Vector2.ZERO
	var travelled := 0.0
	for index in _route.size() - 1:
		var segment := _route[index].distance_to(_route[index + 1])
		if travelled + segment >= distance:
			var t := (distance - travelled) / maxf(segment, 0.001)
			return _route[index].lerp(_route[index + 1], t)
		travelled += segment
	return _route[_route.size() - 1]


func _hash01(seed_value: float, x: int, y: int) -> float:
	var value := sin(seed_value * 127.1 + x * 311.7 + y * 74.7) * 43758.5453
	return value - floorf(value)
