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
		"KitchenDetail_SinkBasin", "KitchenDetail_SinkRim", "KitchenDetail_FaucetStem",
		"KitchenDetail_FaucetSpout", "KitchenDetail_FaucetHandle", "KitchenDetail_CuttingBoard",
		"KitchenDetail_Cup", "KitchenDetail_FridgeHandle", "KitchenDetail_UnderCabinetLight",
		"KitchenDetail_TableEdge_Front", "KitchenDetail_TableEdge_Back",
		"KitchenDetail_TableEdge_Left", "KitchenDetail_TableEdge_Right"
	]
	var failures := 0
	for node_name in required:
		if game.get_node_or_null(node_name) == null:
			printerr("FAIL missing kitchen detail: ", node_name)
			failures += 1
	for node in game.find_children("KitchenDetail_*", "StaticBody3D", true, false):
		if node.get_node_or_null("CollisionShape3D") != null:
			printerr("FAIL kitchen detail became a movement collider: ", node.name)
			failures += 1
	var dining_pads: Array = game.find_children("KitchenDetail_ChairPad_*", "StaticBody3D", true, false)
	if dining_pads.is_empty():
		printerr("FAIL no bounds-attached dining chair pads")
		failures += 1
	print("Kitchen detail nodes: ", required.size(), "; dining pads: ", dining_pads.size())
	print("Kitchen detail failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
