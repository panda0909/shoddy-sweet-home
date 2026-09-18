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


static func floor_arc(parent: Node3D, radius: float, start_degrees: float, end_degrees: float, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var steps := maxi(2, int(absf(end_degrees - start_degrees) / 10.0))
	for i in range(steps + 1):
		var angle := deg_to_rad(lerpf(start_degrees, end_degrees, float(i) / float(steps)))
		var node := MeshInstance3D.new()
		var segment := BoxMesh.new()
		segment.size = Vector3(0.025, 0.012, 0.18)
		node.mesh = segment
		node.material_override = material
		node.position = Vector3(cos(angle) * radius, 0.012, sin(angle) * radius)
		node.rotation.y = -angle
		parent.add_child(node)

static func build(parent: Node3D, id: String) -> void:
	var ivory := Color(0.72, 0.70, 0.62)
	var dark := Color(0.07, 0.06, 0.045)
	var wood := Color(0.36, 0.20, 0.10)
	match id:
		"kitchen_socket":
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
		"cabinet_wear":
			# The clue is a worn lacquer finish, not a floating debug decal:
			# expose a darker rubbed edge, a warm wood underlayer, paint chips,
			# then a loose cluster of shallow scratches around the handle path.
			var lacquer_shadow := Color(0.12, 0.055, 0.025)
			var exposed_wood := Color(0.48, 0.24, 0.09)
			var fresh_chip := Color(0.68, 0.38, 0.14)
			box(parent, Vector3(0.018, 0.50, 0.008), Vector3(0.105, 0.0, 0.001), lacquer_shadow, 0.015)
			box(parent, Vector3(0.010, 0.43, 0.009), Vector3(0.094, 0.01, -0.004), exposed_wood, -0.018)
			for chip in [
				[Vector3(0.070, 0.22, -0.006), Vector3(0.035, 0.018, 0.008), -0.18],
				[Vector3(0.080, 0.10, -0.006), Vector3(0.022, 0.014, 0.008), 0.28],
				[Vector3(0.072, -0.19, -0.006), Vector3(0.028, 0.016, 0.008), -0.35]
			]:
				box(parent, chip[1], chip[0], fresh_chip, float(chip[2]))
			var scratches := [
				[Vector3(-0.018, -0.22, -0.006), Vector3(0.014, 0.082, 0.008), 0.14],
				[Vector3(-0.032, -0.13, -0.006), Vector3(0.012, 0.052, 0.008), -0.20],
				[Vector3(-0.010, -0.04, -0.006), Vector3(0.013, 0.097, 0.008), 0.10],
				[Vector3(-0.036, 0.065, -0.006), Vector3(0.011, 0.062, 0.008), -0.28],
				[Vector3(-0.014, 0.16, -0.006), Vector3(0.014, 0.074, 0.008), 0.22]
			]
			for scratch in scratches:
				box(parent, scratch[1], scratch[0], lacquer_shadow, float(scratch[2]))
			# Pale rub marks make the repeated handle contact readable at a
			# distance without turning the whole cabinet into a glowing marker.
			for rub in [
				[Vector3(0.032, 0.205, -0.007), Vector3(0.010, 0.045, 0.008), 0.06],
				[Vector3(0.040, 0.14, -0.007), Vector3(0.009, 0.032, 0.008), -0.10],
				[Vector3(0.036, 0.075, -0.007), Vector3(0.009, 0.040, 0.008), 0.12]
			]:
				box(parent, rub[1], rub[0], Color(0.76, 0.56, 0.30), float(rub[2]))
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
			if id == "cabinet_blocked":
				# The red floor arc shows the refrigerator/cabinet door sweep.
				# It is visual-only; the real passage remains governed by the
				# furniture BoxShape3D and the inspection hitbox.
				floor_arc(parent, 0.58, -72.0, 72.0, Color(0.92, 0.20, 0.12, 0.72))
		"bath_vanity":
			# A floor sweep plus two low scuffs makes the door/vanity conflict
			# readable without adding another collision shape.
			floor_arc(parent, 0.62, -78.0, 78.0, Color(0.92, 0.20, 0.12, 0.72))
			box(parent, Vector3(0.34, 0.025, 0.018), Vector3(0, -0.015, 0.28), wood, 0.12)
			box(parent, Vector3(0.28, 0.025, 0.018), Vector3(0.16, -0.015, 0.20), wood, -0.16)
