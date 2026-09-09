extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	var failures := 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._input(click)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not game.found_issues.is_empty():
		failures += 1
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(120, 60)
	var yaw: float = game.player.rotation.y
	game._input(motion)
	if is_equal_approx(yaw, game.player.rotation.y) or game.camera.rotation.x == 0:
		failures += 1
	game._set_paused(true)
	yaw = game.player.rotation.y
	game._input(motion)
	if not is_equal_approx(yaw, game.player.rotation.y):
		failures += 1
	game._set_paused(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._input(click)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		failures += 1
	print("Mouse capture / look / pause / recapture failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
