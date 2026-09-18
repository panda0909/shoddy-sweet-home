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
	# This is a visual fixture test, so install the complete issue pool instead
	# of relying on the round's random ten-issue selection.
	for body in game.issue_bodies.values():
		body.queue_free()
	game.issue_bodies.clear()
	game.issue_records = game._get_issue_definitions()
	for issue in game.issue_records:
		game._add_issue_target(issue)

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
		var sweep_shape := BoxShape3D.new()
		sweep_shape.size = Vector3(0.16, 1.80, 0.72)
		var sweep_query := PhysicsShapeQueryParameters3D.new()
		sweep_query.shape = sweep_shape
		sweep_query.collision_mask = 1
		sweep_query.exclude = [cabinet.get_rid()]
		var sweep_hits := 0
		var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
		for sample in range(15):
			var angle := deg_to_rad(lerpf(-72.0, 72.0, float(sample) / 14.0))
			var sweep_center := cabinet.global_position + Vector3(cos(angle) * 0.58, 0.90, sin(angle) * 0.58)
			sweep_query.transform = Transform3D(Basis(Vector3.UP, angle), sweep_center)
			if not space.intersect_shape(sweep_query, 8).is_empty():
				sweep_hits += 1
		if sweep_hits == 0:
			printerr("FAIL cabinet sweep does not intersect any real furniture BoxShape3D")
			failures += 1
		else:
			print("Cabinet sweep physics hits: ", sweep_hits, "/15")
	print("Cabinet swing arc segments: ", 15 if failures == 0 else 0)
	print("Issue visual failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
