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

	var lod_count := 0
	var failures := 0
	for node in game.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.has_meta("distance_lod_applied"):
			continue
		lod_count += 1
		if mesh.visibility_range_end <= mesh.visibility_range_begin:
			printerr("FAIL invalid LOD range: ", mesh.name)
			failures += 1
		if mesh.has_meta("furniture_collision"):
			printerr("FAIL LOD mesh became a furniture collider: ", mesh.name)
			failures += 1
	if lod_count < 10:
		printerr("FAIL too few imported decorative LOD meshes: ", lod_count)
		failures += 1
	if game.high_poly_lod_entries.is_empty():
		printerr("FAIL no high-poly proxy LOD entries")
		failures += 1
	else:
		var entry: Dictionary = game.high_poly_lod_entries[0]
		game.player.position = Vector3(9.0, 1.0, 5.0)
		game._update_high_poly_lods()
		var source := entry["source"] as MeshInstance3D
		var proxy := entry["proxy"] as MeshInstance3D
		if source.visible or not proxy.visible:
			printerr("FAIL high-poly proxy was not selected at distance")
			failures += 1
		game.player.position = Vector3(-4.45, 1.0, 1.15)
		game._update_high_poly_lods()
		if not source.visible or proxy.visible:
			printerr("FAIL high-poly source was not restored near player")
			failures += 1
	var kitchen_lod_entries := 0
	for entry in game.high_poly_lod_entries:
		var source := entry["source"] as MeshInstance3D
		if source != null and source.get_parent() is Node3D and source.get_parent().get_parent() is Node3D:
			var ancestor: Node = source
			while ancestor != null and ancestor.name != "KitchenRealAsset":
				ancestor = ancestor.get_parent()
			if ancestor != null and is_equal_approx(float(entry["distance"]), 7.5):
				kitchen_lod_entries += 1
		if source != null and source.has_meta("high_poly_lod_distance") and float(source.get_meta("high_poly_lod_distance")) < 7.5:
			printerr("FAIL unexpected sub-7.5m LOD distance: ", source.name)
			failures += 1
	if kitchen_lod_entries == 0:
		printerr("FAIL kitchen high-poly LOD budget was not configured")
		failures += 1
	print("Imported decorative LOD meshes: ", lod_count)
	print("High-poly proxy LOD entries: ", game.high_poly_lod_entries.size())
	print("LOD visibility failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
