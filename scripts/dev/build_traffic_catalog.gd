extends SceneTree
func bounds(node: Node, xform := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	if node is Node3D:
		xform *= node.transform
	if node is MeshInstance3D and node.mesh:
		result = xform * node.mesh.get_aabb()
	for child in node.get_children():
		var next := bounds(child, xform)
		if next.size.length() > 0:
			result = next if result.size.length() == 0 else result.merge(next)
	return result
func _initialize() -> void:
	var output := "# Generated from all eleven car GLBs.\nextends RefCounted\nconst MODELS = [\n"
	for id in [10, 13, 14, 15, 16, 18, 19, 20, 21, 22, 23]:
		var path := "res://assets/models/汽车模型/Asset_%04d.glb" % id
		var scene: PackedScene = load(path)
		var node := scene.instantiate()
		var box := bounds(node)
		output += '\t{"path": "%s", "bounds": AABB(Vector3%s, Vector3%s)},\n' % [path, str(box.position), str(box.size)]
		node.free()
	output += "]\n"
	FileAccess.open("res://scripts/traffic/traffic_model_catalog.gd", FileAccess.WRITE).store_string(output)
	quit()
