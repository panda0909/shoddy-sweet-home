extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame

	var failures := 0
	var wood_parts := [
		"BedBase", "BedHeadboard", "Closet", "ClosetDoorLeft", "ClosetDoorRight",
		"DeskTop", "Bookcase", "BedsideTable_Left", "BedsideTable_Right"
	]
	for id in wood_parts:
		var part := game.get_node_or_null(id) as Node3D
		var mesh := part.get_node_or_null("Mesh") as MeshInstance3D if part != null else null
		var material := mesh.material_override as StandardMaterial3D if mesh != null else null
		if material == null or material.albedo_texture == null or material.roughness_texture == null:
			printerr("FAIL wood PBR material: ", id)
			failures += 1
		if material == null or not material.normal_enabled or material.normal_texture == null:
			printerr("FAIL wood normal detail: ", id)
			failures += 1

	for id in ["BedsideTable_Left", "BedsideTable_Right", "Desk", "DeskTop", "Mattress", "Duvet", "BedroomRug", "BedroomPlantPot"]:
		if game.get_node_or_null(id) == null:
			printerr("FAIL missing bedroom prop: ", id)
			failures += 1

	for id in ["PipingFront", "PipingBack", "PipingLeft", "PipingRight"]:
		if game.get_node_or_null("Mattress/" + id) == null:
			printerr("FAIL missing mattress detail: ", id)
			failures += 1

	for child in game.get_children():
		failures += _count_concave(child)

	print("Bedroom detail failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _count_concave(node: Node) -> int:
	var failures := 0
	for child in node.get_children():
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			printerr("FAIL concave bedroom collision: ", child.get_path())
			failures += 1
		failures += _count_concave(child)
	return failures
