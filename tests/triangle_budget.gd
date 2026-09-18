extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	game._update_high_poly_lods()
	var failures := 0
	var budgets := {"LivingRoomRealAsset": 650000, "KitchenRealAsset": 700000, "BathroomRealAsset": 700000}
	for room_name in budgets:
		var room := game.get_node_or_null(room_name) as Node3D
		var triangles := 0
		if room != null:
			for child in room.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				if mesh != null and mesh.visible:
					triangles += game._mesh_triangle_count(mesh.mesh)
		var budget: int = budgets[room_name]
		print(room_name, " visible triangles=", triangles, " budget=", budget)
		if triangles > budget:
			printerr("FAIL triangle budget: ", room_name, " ", triangles, " > ", budget)
			failures += 1
	game.player.position = Vector3(1.0, 1.0, 0.7)
	game._update_high_poly_lods()
	var near_kitchen_triangles := 0
	var near_kitchen := game.get_node_or_null("KitchenRealAsset") as Node3D
	if near_kitchen != null:
		for child in near_kitchen.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh != null and mesh.visible:
				near_kitchen_triangles += game._mesh_triangle_count(mesh.mesh)
	print("Kitchen near-player triangles=", near_kitchen_triangles)
	if near_kitchen_triangles < 1000000:
		printerr("FAIL kitchen high-detail model was not restored near player")
		failures += 1
	print("Triangle budget failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
