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
		"KitchenDetail_ExtractorHood_Rim", "KitchenDetail_ExtractorHood_Duct", "KitchenDetail_ExtractorHood_Flange",
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
	var sink_worktop: AABB = game._find_kitchen_mesh_bounds("123_Worktops")
	var sink := game.get_node_or_null("KitchenDetail_SinkBasin") as Node3D
	if not sink_worktop.has_volume() or sink == null or sink.global_position.distance_to(sink_worktop.get_center()) > 0.40:
		printerr("FAIL sink is not attached to real worktop bounds")
		failures += 1
	var table_bounds: AABB = game._find_kitchen_mesh_bounds("63_Tabletop")
	var table_edge := game.get_node_or_null("KitchenDetail_TableEdge_Front") as Node3D
	if not table_bounds.has_volume() or table_edge == null:
		printerr("FAIL dining table bounds-attached edge")
		failures += 1
	var upper_cabinet_bounds: AABB = game._find_kitchen_mesh_bounds("74_CupboardUnits")
	var cabinet_light := game.get_node_or_null("KitchenDetail_UnderCabinetLight") as Node3D
	if not upper_cabinet_bounds.has_volume() or cabinet_light == null:
		printerr("FAIL missing upper-cabinet light anchor")
		failures += 1
	elif cabinet_light.global_position.y >= upper_cabinet_bounds.position.y or absf(cabinet_light.global_position.x - upper_cabinet_bounds.get_center().x) > 0.25 or absf(cabinet_light.global_position.z - upper_cabinet_bounds.get_center().z) > 0.25:
		printerr("FAIL under-cabinet light is not attached to upper cabinet bounds: ", cabinet_light.global_position)
		failures += 1
	var hood_bounds: AABB = game._find_kitchen_mesh_bounds("255_ExtractorHood")
	var hood_rim := game.get_node_or_null("KitchenDetail_ExtractorHood_Rim") as Node3D
	var hood_rim_expected := Vector3(hood_bounds.get_center().x, hood_bounds.position.y - 0.018, hood_bounds.get_center().z) if hood_bounds.has_volume() else Vector3.ZERO
	if not hood_bounds.has_volume() or hood_rim == null or hood_rim.global_position.distance_to(hood_rim_expected) > 0.05:
		printerr("FAIL extractor hood trim is not attached to real hood bounds")
		failures += 1
	print("Kitchen detail nodes: ", required.size(), "; dining pads: ", dining_pads.size())
	print("Kitchen detail failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
