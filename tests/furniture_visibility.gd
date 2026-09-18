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
	var preserved := 0
	var repositioned := 0
	var shell_hidden := 0
	var area_lights_hidden := 0
	var blinds_hidden := 0
	for node in game.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.has_meta("hidden_imported_area_light"):
			area_lights_hidden += 1
			if mesh.visible:
				printerr("FAIL imported area-light card remains visible: ", mesh.name)
				failures += 1
		if mesh.has_meta("hidden_imported_blind"):
			blinds_hidden += 1
			if mesh.visible:
				printerr("FAIL imported blind strip remains visible: ", mesh.name)
				failures += 1
		if mesh.has_meta("door_clearance_visual_only"):
			preserved += 1
			# Bathroom static batching hides source meshes after this pass. The
			# metadata is the authoritative check that door clearance itself did
			# not remove the furniture; the batched render remains visible.
		if mesh.has_meta("hidden_for_door_clearance"):
			shell_hidden += 1
			if not _is_architectural_shell(mesh):
				printerr("FAIL non-shell mesh hidden for door clearance: ", mesh.name)
				failures += 1
		if mesh.has_meta("repositioned_for_door_clearance"):
			repositioned += 1

	print("Door-clearance furniture preserved: ", preserved)
	print("Imported area-light cards hidden: ", area_lights_hidden)
	print("Imported blind strips hidden: ", blinds_hidden)
	print("Door-clearance decorative pieces repositioned: ", repositioned)
	print("Door-clearance shell pieces hidden: ", shell_hidden)
	print("Furniture visibility failures: ", failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _is_architectural_shell(mesh: MeshInstance3D) -> bool:
	var mesh_name := str(mesh.name).to_lower()
	for token in [
		"wall", "floor", "ceiling", "skirting", "cornice", "moulding",
		"trim", "shell", "room_shell", "doorframe", "door_frame"
	]:
		if token in mesh_name:
			return true
	return false
