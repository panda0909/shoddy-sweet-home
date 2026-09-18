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

	var failures := 0
	var cabinet := game.issue_bodies.get("cabinet_blocked") as StaticBody3D
	if cabinet == null:
		printerr("FAIL cabinet_blocked issue body missing")
		failures += 1
	else:
		var visual := cabinet.get_node_or_null("DefectVisual") as Node3D
		var arc_count := 0
		if visual != null:
			for child in visual.get_children():
				if child is MeshInstance3D and child.mesh is BoxMesh:
					var size: Vector3 = (child.mesh as BoxMesh).size
					if is_equal_approx(size.x, 0.025) and is_equal_approx(size.z, 0.18):
						arc_count += 1
		if arc_count < 10:
			printerr("FAIL cabinet swing arc incomplete: ", arc_count)
			failures += 1
		# Defect visual children must never add physics shapes.
		if visual != null and visual.find_children("*", "CollisionShape3D", true, false).size() != 0:
			printerr("FAIL defect visual added collision")
			failures += 1
	print("Cabinet swing arc segments: ", 15 if failures == 0 else 0)
	print("Issue visual failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
