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
	print("Imported decorative LOD meshes: ", lod_count)
	print("LOD visibility failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
