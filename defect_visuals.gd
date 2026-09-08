extends RefCounted
## Visual clues are separate from the generous inspection hitboxes.

static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, tilt: float = 0.0) -> void:
	var node := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	node.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	node.material_override = material
	node.position = at
	node.rotation.z = tilt
	parent.add_child(node)

static func build(parent: Node3D, id: String) -> void:
	var ivory := Color(0.72, 0.70, 0.62)
	var dark := Color(0.07, 0.06, 0.045)
	var wood := Color(0.36, 0.20, 0.10)
	match id:
		"tv_outlet", "kitchen_socket":
			box(parent, Vector3(0.22, 0.30, 0.035), Vector3.ZERO, ivory, 0.09)
			for x in [-0.055, 0.055]:
				box(parent, Vector3(0.024, 0.06, 0.008), Vector3(x, 0.02, -0.024), dark)
			box(parent, Vector3(0.02, 0.035, 0.008), Vector3(0, -0.07, -0.024), dark)
			box(parent, Vector3(0.012, 0.18, 0.012), Vector3(0.10, -0.18, -0.03), Color(0.3, 0.4, 0.12), 0.3)
		"window_sealed", "closet_deadend":
			for y in [-0.30, 0.30]:
				box(parent, Vector3(1.7, 0.11, 0.045), Vector3(0, y, 0.08), wood, 0.18 if y < 0 else -0.18)
				for x in [-0.65, 0.65]:
					box(parent, Vector3(0.025, 0.025, 0.015), Vector3(x, y, 0.115), dark)
		"tile_hollow":
			box(parent, Vector3(0.76, 0.94, 0.035), Vector3.ZERO, ivory)
			for i in range(7):
				box(parent, Vector3(0.016, 0.16, 0.012), Vector3(0.025 * sin(i * 2.0), -0.4 + i * 0.13, 0.027), dark, 0.25 if i % 2 == 0 else -0.35)
		"sink_leak":
			box(parent, Vector3(0.40, 0.06, 0.06), Vector3(0, 0.12, 0), Color.GRAY)
			for i in range(6):
				box(parent, Vector3(0.018, 0.055, 0.018), Vector3(0.05, 0.04 - i * 0.07, 0), Color(0.12, 0.33, 0.40))
				parent.get_child(parent.get_child_count() - 1).set_meta("water_drop", true)
		"rug_tilt":
			# Folded fabric remains attached to the existing carpet edge.
			box(parent, Vector3(0.48, 0.018, 0.36), Vector3.ZERO, Color(0.28, 0.24, 0.19), 0.06)
			for i in range(12):
				box(parent, Vector3(0.008, 0.008, 0.07), Vector3(-0.22 + i * 0.04, 0.004, 0.20), ivory)
		"bed_slope":
			box(parent, Vector3(0.65, 0.035, 0.45), Vector3.ZERO, Color(0.34, 0.29, 0.21), 0.07)
			for x in [-0.34, 0.34]:
				box(parent, Vector3(0.025, 0.06, 0.42), Vector3(x, 0.025, 0), wood, 0.11)
		"sofa_gap":
			box(parent, Vector3(0.75, 0.65, 0.035), Vector3.ZERO, Color(0.36, 0.37, 0.34))
			for y in [-0.22, 0.22]:
				box(parent, Vector3(0.87, 0.08, 0.04), Vector3(0, y, -0.04), wood, 0.10)
		"drain_missing":
			box(parent, Vector3(0.45, 0.012, 0.45), Vector3.ZERO, Color(0.38, 0.39, 0.35))
			for i in range(4):
				box(parent, Vector3(0.025, 0.018, 0.22), Vector3(-0.09 + i * 0.06, 0.015, 0), Color(0.48, 0.44, 0.34))
		"vent_wrong", "bath_vent":
			box(parent, Vector3(0.6, 0.26, 0.12), Vector3.ZERO, Color(0.46, 0.47, 0.43))
			for i in range(6):
				box(parent, Vector3(0.025, 0.18, 0.015), Vector3(-0.23 + i * 0.09, 0, -0.075), dark)
				box(parent, Vector3(0.025, 0.18, 0.015), Vector3(-0.23 + i * 0.09, 0, 0.075), dark)
		"cabinet_blocked", "bath_door":
			# Surface scuffs, not a second floating wooden post.
			for y in [-0.18, -0.05, 0.08, 0.21]:
				box(parent, Vector3(0.009, 0.07, 0.003), Vector3(-0.02, y, -0.002), ivory, 0.2)
