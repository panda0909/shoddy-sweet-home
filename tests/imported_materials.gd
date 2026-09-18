extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	for frame in range(1200):
		await process_frame
		if game.loaded_rooms.size() == 4 and not game.progressive_loading:
			break

	var failures := 0
	var checks := [
		["KitchenRealAsset/65_ExtractorHood", "metal"],
		["KitchenRealAsset/63_Tabletop", "wood"],
		["KitchenRealAsset/182_MicrowaveGlass", "glass"],
		["LivingRoomRealAsset/63_SofaLeather", "fabric"],
		["BathroomRealAsset/44_Mirror", "glass"]
	]
	for check in checks:
		var mesh := _find_mesh(game, str(check[0]).get_slice("/", 1))
		if mesh == null:
			printerr("FAIL missing imported material probe: ", check[0])
			failures += 1
			continue
		var material := mesh.get_surface_override_material(0) as BaseMaterial3D
		if material == null:
			material = mesh.get_active_material(0) as BaseMaterial3D
		if material == null:
			printerr("FAIL imported material was not assigned: ", check[0])
			failures += 1
			continue
		var kind: String = check[1]
		if kind == "metal" and material.metallic < 0.60:
			printerr("FAIL metal semantic tuning: ", check[0], " metallic=", material.metallic)
			failures += 1
		elif kind == "glass" and (material.roughness > 0.30 or material.clearcoat < 0.20):
			printerr("FAIL glass semantic tuning: ", check[0], " roughness=", material.roughness, " clearcoat=", material.clearcoat)
			failures += 1
		elif kind == "wood" and (material.roughness < 0.45 or material.clearcoat < 0.04):
			printerr("FAIL wood semantic tuning: ", check[0], " roughness=", material.roughness, " clearcoat=", material.clearcoat)
			failures += 1
		elif kind == "fabric" and material.roughness < 0.75:
			printerr("FAIL fabric semantic tuning: ", check[0], " roughness=", material.roughness)
			failures += 1

	print("Imported material probes: ", checks.size())
	print("Imported material failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _find_mesh(root_node: Node, target_name: String) -> MeshInstance3D:
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		if str(node.name) == target_name:
			return node as MeshInstance3D
	return null
