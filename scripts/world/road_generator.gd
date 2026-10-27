extends RefCounted
class_name RoadGenerator

## 根据地图尺寸、随机种子和道路密度生成 RoadNetwork。
## 只负责数据，不创建任何网格或碰撞体。

const MAIN := RoadNetwork.MAIN
const SECONDARY := RoadNetwork.SECONDARY
const LOCAL := RoadNetwork.LOCAL
const MIN_JUNCTION_SPACING := RoadNetwork.MIN_JUNCTION_SPACING


static func generate(map_size: Vector2, seed_value: int, density: float, widths: Vector3, allow_difficult: bool = false) -> RoadNetwork:
	# An axis interval is half the arterial interval. Branches occupy the
	# half-axis intervals, so 600 m is the densest valid arterial spacing.
	var arterial_step: float = snappedf(clampf(800.0 - density * 200.0, 600.0, 800.0), 10.0)
	var network := RoadNetwork.new()
	network.map_size = map_size
	network.seed_value = seed_value
	network.density = density
	network.widths = widths
	network.allow_difficult = allow_difficult
	network.arterial_step = arterial_step
	network.x_axes = _axes(map_size.x, arterial_step)
	network.y_axes = _axes(map_size.y, arterial_step)
	var x_axes := network.x_axes
	var y_axes := network.y_axes
	var lookup := {}
	# The seed controls the order in which independent blocks are constructed.
	# Positions are deterministic and rule-driven; a later decorative layer can
	# use the same seed without changing the legal road topology.
	var cells := []
	for xi in range(x_axes.size() - 1):
		for yi in range(y_axes.size() - 1):
			cells.append(Vector2i(xi, yi))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var item: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = item
	for cell in cells:
		if not network.edges.is_empty() and rng.randf() > 0.55 + 0.45 * density:
			continue
		var xi: int = cell.x
		var yi: int = cell.y
		var left: Dictionary = x_axes[xi]
		var right: Dictionary = x_axes[xi + 1]
		var bottom: Dictionary = y_axes[yi]
		var top: Dictionary = y_axes[yi + 1]
		# Each full cell has exactly one secondary side on each axis.
		var sx: float = left.pos if left.kind == SECONDARY else right.pos
		var sy: float = bottom.pos if bottom.kind == SECONDARY else top.pos
		var mx: float = (left.pos + right.pos) * 0.5
		var my: float = (bottom.pos + top.pos) * 0.5
		var centre := _node(network, lookup, Vector2(mx, my))
		var on_horizontal := _node(network, lookup, Vector2(mx, sy))
		var on_vertical := _node(network, lookup, Vector2(sx, my))
		_edge(network, centre, on_horizontal, LOCAL)
		_edge(network, centre, on_vertical, LOCAL)
	# Each axis is split at every crossing and every branch attachment.
	for y_axis in y_axes:
		var positions: Array[float] = [-map_size.x * 0.5, map_size.x * 0.5]
		for x_axis in x_axes:
			positions.append(x_axis.pos)
		if y_axis.kind == SECONDARY:
			for xi in range(x_axes.size() - 1):
				var midpoint: float = (x_axes[xi].pos + x_axes[xi + 1].pos) * 0.5
				if lookup.has(Vector2i(roundi(midpoint * 100.0), roundi(y_axis.pos * 100.0))):
					positions.append(midpoint)
		positions.sort()
		for i in range(positions.size() - 1):
			var a := _node(network, lookup, Vector2(positions[i], y_axis.pos))
			var b := _node(network, lookup, Vector2(positions[i + 1], y_axis.pos))
			_edge(network, a, b, y_axis.kind)
	for x_axis in x_axes:
		var positions: Array[float] = [-map_size.y * 0.5, map_size.y * 0.5]
		for y_axis in y_axes:
			positions.append(y_axis.pos)
		if x_axis.kind == SECONDARY:
			for yi in range(y_axes.size() - 1):
				var midpoint: float = (y_axes[yi].pos + y_axes[yi + 1].pos) * 0.5
				if lookup.has(Vector2i(roundi(x_axis.pos * 100.0), roundi(midpoint * 100.0))):
					positions.append(midpoint)
		positions.sort()
		for i in range(positions.size() - 1):
			var a := _node(network, lookup, Vector2(x_axis.pos, positions[i]))
			var b := _node(network, lookup, Vector2(x_axis.pos, positions[i + 1]))
			_edge(network, a, b, x_axis.kind)
	return network


static func _axes(size: float, step: float) -> Array[Dictionary]:
	var axes: Array[Dictionary] = []
	var half_step := step * 0.5
	var largest := int(floor((size * 0.5 - MIN_JUNCTION_SPACING) / half_step))
	for n in range(-largest, largest + 1):
		axes.append({"pos": n * half_step, "kind": MAIN if n % 2 == 0 else SECONDARY})
	return axes


static func _node(network: RoadNetwork, lookup: Dictionary, position: Vector2) -> int:
	var key := Vector2i(roundi(position.x * 100.0), roundi(position.y * 100.0))
	if lookup.has(key):
		return lookup[key]
	var id: int = network.nodes.size()
	lookup[key] = id
	network.nodes.append(position)
	return id


static func _edge(network: RoadNetwork, a: int, b: int, kind: int) -> void:
	network.edges.append({"a": a, "b": b, "kind": kind})
