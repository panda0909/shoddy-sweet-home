extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for room in ["LivingRoomRealAsset", "KitchenRealAsset", "BathroomRealAsset"]:
		print(room)
		for mesh in game.get_node(room).find_children("*", "MeshInstance3D"):
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			if mesh.is_visible_in_tree() and bounds.size.length() > 0.7:
				print(mesh.name, " ", bounds)
	game.queue_free()
	quit()
