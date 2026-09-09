extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	for body in game.issue_bodies.values():
		body.queue_free()
	game.issue_bodies.clear()
	game.issue_records = game._get_issue_definitions()
	game._start_round()
	game._show_hint()
	if game.hint_world_label == null:
		printerr("FAIL hint feedback")
		game.queue_free()
		await process_frame
		quit(1)
	var inspected := 0
	for issue in game._get_issue_definitions():
		game._add_issue_target(issue)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var failures := 0
	# Flood-fill using swept player capsules, starting at the real spawn.
	# Every accepted edge represents a continuous unobstructed quarter-metre step.
	var start: Vector3 = game.player.position
	var visited := {Vector2i.ZERO: true}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var from := start + Vector3(cell.x * 0.25, 0, cell.y * 0.25)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if visited.has(next):
				continue
			var to := start + Vector3(next.x * 0.25, 0, next.y * 0.25)
			if absf(to.x) > 9.5 or absf(to.z) > 5.5:
				continue
			var collision := KinematicCollision3D.new()
			if game.player.test_move(Transform3D(Basis.IDENTITY, from), to - from, collision):
				var obstacle: Object = collision.get_collider()
				if not obstacle.has_meta("door_id") or game._is_door_open(str(obstacle.get_meta("door_id"))):
					continue
				game.player.position = from
				game.camera.position = Vector3(0, 1.55, 0)
				game.camera.look_at(obstacle.global_position)
				game.raycast.force_raycast_update()
				game._inspect_target()
				if not game._is_door_open(str(obstacle.get_meta("door_id"))):
					continue
				for frame in range(45):
					game._animate_doors(1.0 / 30.0)
					await physics_frame
				print("PASS interact-open ", obstacle.get_meta("door_id"))
				if game.player.test_move(Transform3D(Basis.IDENTITY, from), to - from):
					continue
			visited[next] = true
			queue.append(next)
	print("Connected walkable samples: ", queue.size())
	var rooms := [0, 0, 0, 0]
	for cell in queue:
		var point := start + Vector3(cell.x * 0.25, 0, cell.y * 0.25)
		rooms[(0 if point.x < 0 else 1) + (2 if point.z < 0 else 0)] += 1
	print("Rooms living/kitchen/bedroom/bathroom: ", rooms)
	for id in game.issue_bodies:
		var target: Node3D = game.issue_bodies[id]
		var reachable := false
		for cell in queue:
			for unused in range(1):
				var eye: Vector3 = start + Vector3(cell.x * 0.25, 1.55, cell.y * 0.25)
				if eye.distance_to(target.position) > 3.7:
					continue
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = game.player.get_node("CollisionShape3D").shape
				query.transform.origin = eye - Vector3(0, 0.63, 0)
				query.collision_mask = 1
				query.exclude = [game.player.get_rid()]
				if not space.intersect_shape(query, 1).is_empty():
					continue
				var ray := PhysicsRayQueryParameters3D.create(eye, target.position, 3, [game.player.get_rid()])
				var result := space.intersect_ray(ray)
				if result.get("collider") == target:
					reachable = true
					if inspected < 10:
						game.player.position = eye - Vector3(0, 1.55, 0)
						game.camera.global_position = eye
						game.camera.look_at(target.position)
						game.raycast.force_raycast_update()
						var required: int = target.get_meta("required_tool")
						game._select_tool(maxi(0, required))
						game._inspect_target()
						if not game.found_issues.has(id):
							printerr("FAIL interaction ", id)
							failures += 1
						inspected += 1
					break
			if reachable:
				break
		print("PASS " if reachable else "FAIL ", id)
		if not reachable:
			failures += 1
	if not game.round_finished or game.found_issues.size() != 10 or not game.report_panel.visible:
		printerr("FAIL ten-issue report")
		failures += 1
	else:
		print("PASS ten-issue interaction and report")
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
