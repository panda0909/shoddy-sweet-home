extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame

	var stats := {
		"furniture_bodies": 0,
		"furniture_boxes": 0,
		"concave_shapes": 0,
		"tiny_furniture_boxes": 0
	}
	_inspect_node(game, stats)

	var failures := 0
	if int(stats["furniture_bodies"]) == 0:
		printerr("FAIL no generated furniture colliders")
		failures += 1
	if int(stats["furniture_boxes"]) != int(stats["furniture_bodies"]):
		printerr("FAIL furniture collider is not a single box per body")
		failures += 1
	if int(stats["concave_shapes"]) != 0:
		printerr("FAIL concave/trimesh collision remains: ", stats["concave_shapes"])
		failures += 1
	if int(stats["tiny_furniture_boxes"]) != 0:
		printerr("FAIL tiny furniture collider remains: ", stats["tiny_furniture_boxes"])
		failures += 1

	print("Furniture collision bodies: ", stats["furniture_bodies"])
	print("Furniture box shapes: ", stats["furniture_boxes"])
	print("Concave shapes: ", stats["concave_shapes"])
	print("Tiny furniture boxes: ", stats["tiny_furniture_boxes"])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _inspect_node(node: Node, stats: Dictionary) -> void:
	if node is StaticBody3D and node.has_meta("furniture_collision"):
		stats["furniture_bodies"] = int(stats["furniture_bodies"]) + 1
		var shape_node := node.get_node_or_null("FurnitureBoxShape") as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			stats["furniture_boxes"] = int(stats["furniture_boxes"]) + 1
			var shape_size: Vector3 = (shape_node.shape as BoxShape3D).size
			if shape_size.x * shape_size.z < 0.075 or shape_size.y < 0.18:
				stats["tiny_furniture_boxes"] = int(stats["tiny_furniture_boxes"]) + 1
	for child in node.get_children():
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			stats["concave_shapes"] = int(stats["concave_shapes"]) + 1
		_inspect_node(child, stats)
