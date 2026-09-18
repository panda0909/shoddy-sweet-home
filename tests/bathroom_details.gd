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

	var required := [
		"ImportedBath_ToiletBase", "ImportedBath_ToiletTank", "ImportedBath_ToiletSeat",
		"ImportedBath_ToiletWater", "ImportedBath_ToiletHingeLeft", "ImportedBath_ToiletHingeRight",
		"ImportedBath_ShowerTray", "ImportedBath_ShowerGlass", "ImportedBath_ShowerPipe",
		"ImportedBath_ShowerHead", "ImportedBath_ShowerFrame_Left", "ImportedBath_ShowerFrame_Top",
		"ImportedBath_ShowerShelf", "ImportedBath_ShowerControl", "ImportedBath_ShowerDrainCrossA", "ImportedBath_ShowerDrainCrossB", "ImportedBath_TowelBar",
		"ImportedBath_DrainCover", "ImportedBath_VanityCounterEdge",
		"ImportedBath_VanityBasinLeft", "ImportedBath_VanityBasinRight",
		"ImportedBath_VanityFaucetLeft", "ImportedBath_VanityFaucetRight",
		"ImportedBath_VanityHandle_0", "ImportedBath_VanityHandle_3",
		"ImportedBath_MirrorEdgeTop", "ImportedBath_MirrorEdgeLeft", "ImportedBath_MirrorEdgeRight"
	]
	var failures := 0
	var detail_root: Node = game.get_node_or_null("BathroomDetailBatch")
	var detail_batches: Array = detail_root.find_children("StaticBatch_*", "MeshInstance3D", true, false) if detail_root != null else []
	if detail_root == null or detail_batches.size() < 3:
		printerr("FAIL bathroom details were not batched: ", detail_batches.size())
		failures += 1
	for node_name in required:
		if game.find_child(node_name, true, false) == null:
			printerr("FAIL missing imported bathroom detail: ", node_name)
			failures += 1
	for node_name in ["ImportedBath_ToiletBase", "ImportedBath_ToiletTank", "ImportedBath_ToiletSeat", "ImportedBath_ShowerTray"]:
		var node: Node = game.find_child(node_name, true, false)
		if node == null or node.find_child("CollisionShape3D", true, false) == null:
			printerr("FAIL missing bathroom collision: ", node_name)
			failures += 1
	for node_name in required:
		var detail: Node = game.find_child(node_name, true, false)
		if detail != null and detail.find_child("CollisionShape3D", true, false) != null and ("Vanity" in node_name or "MirrorEdge" in node_name):
			printerr("FAIL bathroom finish detail blocks movement: ", node_name)
			failures += 1
	var door_leaf := game.find_child("RightInnerDoor", true, false) as StaticBody3D
	var door_mesh := door_leaf.get_node_or_null("Mesh") as MeshInstance3D if door_leaf != null else null
	var vanity := game.find_child("ImportedBath_VanityCounterEdge", true, false) as StaticBody3D
	var vanity_mesh := vanity.get_node_or_null("Mesh") as MeshInstance3D if vanity != null else null
	if door_mesh == null or vanity_mesh == null:
		printerr("FAIL missing bathroom door or vanity bounds probe")
		failures += 1
	else:
		var vanity_bounds: AABB = vanity_mesh.global_transform * vanity_mesh.get_aabb()
		for opened in [false, true]:
			game.doors["RightInnerDoor"]["is_open"] = opened
			game._animate_doors(1.0)
			var door_bounds: AABB = door_mesh.global_transform * door_mesh.get_aabb()
			if door_bounds.intersects(vanity_bounds):
				printerr("FAIL bathroom door sweep overlaps vanity; open=", opened)
				failures += 1
	print("Imported bathroom detail nodes: ", required.size())
	print("Bathroom detail failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
