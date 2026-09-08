extends RefCounted
## Combine opaque static surfaces by material. Original physics bodies stay intact.
static func build(root: Node3D) -> void:
	var groups: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D"):
		var source: MeshInstance3D = node
		if not source.is_visible_in_tree() or source.mesh == null:
			continue
		var eligible := true
		for surface in range(source.mesh.get_surface_count()):
			var material := source.get_active_material(surface)
			if not material is StandardMaterial3D or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				eligible = false
				break
		if not eligible:
			continue
		for surface in range(source.mesh.get_surface_count()):
			var material := source.get_active_material(surface)
			var key: int = material.get_instance_id()
			if not groups.has(key):
				groups[key] = {"material": material, "surfaces": []}
			groups[key]["surfaces"].append([source, surface])
		originals.append(source)
	var batches := 0
	for key in groups:
		var group: Dictionary = groups[key]
		var builder := SurfaceTool.new()
		for entry in group["surfaces"]:
			var source: MeshInstance3D = entry[0]
			builder.append_from(source.mesh, entry[1], root.global_transform.affine_inverse() * source.global_transform)
		builder.set_material(group["material"])
		var mesh := builder.commit()
		var instance := MeshInstance3D.new()
		instance.name = "StaticBatch_" + str(batches)
		instance.mesh = mesh
		root.add_child(instance)
		batches += 1
	for source in originals:
		source.hide()
	print("Static batching: ", originals.size(), " objects -> ", batches, " material groups")
