extends Node3D

## 裝潢蟑螂：一個用原生 Godot 節點組成的第一人稱驗屋垂直切片。
## 所有家具和問題都在執行時生成，方便快速增加關卡內容。

const ROUND_SECONDS := 180.0
const TARGET_ISSUES := 10
const PLAYER_SPEED := 4.2
const MOUSE_SENSITIVITY := 0.0022
const FURNITURE_COLLISION_MIN_HEIGHT := 0.18
const FURNITURE_COLLISION_MIN_FOOTPRINT := 0.075
const FURNITURE_COLLISION_MIN_SPAN := 0.42
const KITCHEN_ASSET_ORIGIN := Vector3(5.5, 0.0, 3.6)
const KITCHEN_ASSET_BASE_SCALE := 0.60
const KITCHEN_ASSET_SCALE := 0.72

var player: CharacterBody3D
var camera: Camera3D
var raycast: RayCast3D
var hud: CanvasLayer
var objective_label: Label
var timer_label: Label
var tool_label: Label
var prompt_label: Label
var toast_label: Label
var report_panel: ColorRect
var report_label: Label
var progress_bar: ProgressBar
var loading_label: Label

var current_tool := 0
var time_left := ROUND_SECONDS
var round_finished := false
var toast_until := 0.0
var issue_records: Array[Dictionary] = []
var issue_bodies: Dictionary = {}
var found_issues: Dictionary = {}
var issue_meshes: Dictionary = {}
var doors: Dictionary = {}
var paused := false
var pause_panel: ColorRect
var held_tools: Array[Node3D] = []
var inspection_audio: AudioStreamPlayer
var tool_motion: Tween
var loaded_rooms: Dictionary = {}
var room_load_queue: Array[Dictionary] = []
var room_request_id := ""
var room_request_path := ""
var room_request_progress: Array = []
var initial_room_ready := false
var progressive_loading := false
var hint_world_label: Label3D
var hint_until := 0.0
var imported_material_cache: Dictionary = {}
var contact_shadow_material: StandardMaterial3D
var generated_oak_texture: Texture2D
var generated_fabric_texture: Texture2D
var generated_oak_roughness_texture: Texture2D
var generated_fabric_roughness_texture: Texture2D
var generated_oak_normal_texture: Texture2D
var generated_fabric_normal_texture: Texture2D
var high_poly_lod_entries: Array[Dictionary] = []
var lod_refresh_elapsed := 0.0

var tool_names := ["手電筒", "水平儀", "空鼓槌", "驗電筆"]
var tool_descriptions := [
	"照出暗處的水痕與施工痕跡",
	"檢查地板、櫃體與門框是否歪斜",
	"敲出裡面其實是空的磁磚",
	"確認插座到底有沒有接地"
]

var palette := {
	"wall": Color(0.64, 0.61, 0.55),
	"wall_dark": Color(0.43, 0.44, 0.42),
	"floor": Color(0.16, 0.19, 0.24),
	"wood": Color(0.30, 0.15, 0.08),
	"wood_light": Color(0.52, 0.30, 0.12),
	"metal": Color(0.28, 0.34, 0.40),
	"fabric": Color(0.12, 0.23, 0.33),
	"green": Color(0.25, 0.55, 0.34),
	"red": Color(0.75, 0.18, 0.15),
	"yellow": Color(0.92, 0.66, 0.16),
	"blue": Color(0.18, 0.48, 0.80),
	"white": Color(0.72, 0.74, 0.72)
}


func _ready() -> void:
	_ensure_input_actions()
	# Web pointer lock must be requested by a real user gesture, never on load.
	if OS.has_feature("web"):
		Input.use_accumulated_input = false
	_load_generated_material_textures()
	_build_lighting()
	_build_world()
	_build_player()
	_build_ui()
	if _use_progressive_room_loading():
		_begin_progressive_room_loading()
	else:
		initial_room_ready = true
		_start_round()


func _process(delta: float) -> void:
	_poll_room_loading()
	lod_refresh_elapsed += delta
	if lod_refresh_elapsed >= 0.25:
		lod_refresh_elapsed = 0.0
		_update_high_poly_lods()
	if paused:
		return
	if not round_finished and initial_room_ready:
		for body in issue_bodies.values():
			for part in body.get_node("DefectVisual").get_children():
				if part.has_meta("water_drop"):
					part.position.y -= delta * 0.65
					if part.position.y < -0.40:
						part.position.y = 0.04
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0:
			_finish_round("時間到！")
		_update_hud()
		_update_hover_prompt()

	if toast_until > 0.0 and Time.get_ticks_msec() / 1000.0 > toast_until:
		toast_label.text = ""
	if hint_world_label != null and Time.get_ticks_msec() / 1000.0 > hint_until:
		hint_world_label.queue_free()
		hint_world_label = null
		hint_until = 0.0


func _physics_process(delta: float) -> void:
	if player == null or round_finished or paused or not initial_room_ready:
		return
	_animate_doors(delta)

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (player.transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()
	if direction != Vector3.ZERO:
		player.velocity.x = direction.x * PLAYER_SPEED
		player.velocity.z = direction.z * PLAYER_SPEED
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, PLAYER_SPEED * 8.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, PLAYER_SPEED * 8.0 * delta)

	if not player.is_on_floor():
		player.velocity.y -= 18.0 * delta
	else:
		player.velocity.y = -0.2
	player.move_and_slide()
	if player.position.y < -3.0:
		_reset_player()


func _input(event: InputEvent) -> void:
	if paused or round_finished:
		return
	# Capture before HUD Controls can consume the click. The first click only
	# enters mouse-look; it must not also inspect or accidentally open a door.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return
	# Some embedded browsers reject Pointer Lock entirely. Drag-to-look still
	# permits exploration there, without requiring browser security changes.
	var dragging_in_web := OS.has_feature("web") and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or dragging_in_web):
		player.rotate_y(-event.screen_relative.x * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x - event.screen_relative.y * MOUSE_SENSITIVITY, -1.35, 1.35)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not initial_room_ready:
		return
	if event.is_action_pressed("toggle_mouse") and not round_finished:
		_set_paused(not paused)
		return
	if paused:
		return
	if event.is_action_pressed("hint"):
		_show_hint()
		return
	if event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("interact") or event.is_action_pressed("use_tool"):
		_inspect_target()
	elif event.is_action_pressed("tool_1"):
		_select_tool(0)
	elif event.is_action_pressed("tool_2"):
		_select_tool(1)
	elif event.is_action_pressed("tool_3"):
		_select_tool(2)
	elif event.is_action_pressed("tool_4"):
		_select_tool(3)
	elif event.is_action_pressed("restart") and round_finished:
		_start_round()


func _build_lighting() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.07, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.50, 0.54)
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 0.22
	sun.shadow_enabled = true
	add_child(sun)

	for light_data in [
		{ "pos": Vector3(-5, 2.7, 3), "color": Color(1.0, 0.82, 0.65) },
		{ "pos": Vector3(5, 2.7, 3), "color": Color(1.0, 0.90, 0.74) },
		{ "pos": Vector3(-5, 2.7, -3), "color": Color(1.0, 0.78, 0.60) },
		{ "pos": Vector3(5, 2.7, -3), "color": Color(1.0, 0.93, 0.82) }
	]:
		var omni := OmniLight3D.new()
		omni.position = light_data["pos"]
		omni.light_color = light_data["color"]
		omni.light_energy = 0.38
		omni.omni_range = 6.0
		# Ambient room fill does not need six shadow renders per point light.
		# Directional light and the player's spotlight retain contact shadows.
		omni.shadow_enabled = false
		add_child(omni)

	# One shadow-casting key light gives the first room readable contact shadows
	# without making four shadow maps compete with the Web renderer.
	var living_key := SpotLight3D.new()
	living_key.name = "LivingRoomKeyLight"
	living_key.position = Vector3(-5.0, 2.85, 3.0)
	living_key.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	living_key.light_color = Color(1.0, 0.84, 0.68)
	living_key.light_energy = 0.62
	living_key.spot_range = 6.5
	living_key.spot_angle = 105.0
	living_key.shadow_enabled = true
	living_key.shadow_bias = 0.035
	add_child(living_key)


func _build_world() -> void:
	# 地板與外牆
	_add_box("Floor", Vector3(20.0, 0.2, 12.0), Vector3(0, -0.1, 0), _mat(palette["floor"]), true)
	_add_box("EntrancePorch", Vector3(4.0, 0.2, 3.0), Vector3(1.8, -0.1, 7.4), _mat(Color(0.20, 0.22, 0.24)), true)
	for side in [-0.2, 3.8]:
		_add_box("PorchSide", Vector3(0.12, 1.1, 2.8), Vector3(side, 0.55, 7.5), _mat(palette["metal"]), true)
	_add_box("PorchEnd", Vector3(4.0, 1.1, 0.12), Vector3(1.8, 0.55, 8.85), _mat(palette["metal"]), true)
	_add_box("BackWall", Vector3(20.0, 3.0, 0.25), Vector3(0, 1.5, -6), _mat(palette["wall"]), true)
	_add_box("FrontWallLeft", Vector3(10.9, 3.0, 0.25), Vector3(-4.55, 1.5, 6), _mat(palette["wall"]), true)
	_add_box("FrontWallRight", Vector3(7.3, 3.0, 0.25), Vector3(6.35, 1.5, 6), _mat(palette["wall"]), true)
	_add_box("LeftWall", Vector3(0.25, 3.0, 12.0), Vector3(-10, 1.5, 0), _mat(palette["wall"]), true)
	_add_box("RightWall", Vector3(0.25, 3.0, 12.0), Vector3(10, 1.5, 0), _mat(palette["wall"]), true)
	_add_box("Ceiling", Vector3(20.0, 0.16, 12.0), Vector3(0, 3.05, 0), _mat(Color(0.66, 0.65, 0.60)), false)

	# 隔間留出標準 1.3m 門洞，所有房門都能實際開關。
	# Keep the central divider continuous while leaving the full swept width of
	# both horizontal doorways clear. The old short boxes overlapped half of the
	# LivingDoor and BedroomDoor openings, so a real player capsule stopped at
	# the wall even though the door leaf itself had opened.
	_add_box("DividerLowerA", Vector3(0.22, 3.0, 3.05), Vector3(0, 1.5, -4.475), _mat(palette["wall_dark"]), true)
	_add_box("DividerLowerB", Vector3(0.22, 3.0, 3.60), Vector3(0, 1.5, 0.30), _mat(palette["wall_dark"]), true)
	_add_box("DividerUpperA", Vector3(0.22, 3.0, 2.35), Vector3(0, 1.5, 4.825), _mat(palette["wall_dark"]), true)
	_add_box("DividerLeftA", Vector3(1.85, 3.0, 0.22), Vector3(-9.075, 1.5, 0), _mat(palette["wall_dark"]), true)
	_add_box("DividerLeftB", Vector3(1.45, 3.0, 0.22), Vector3(-6.125, 1.5, 0), _mat(palette["wall_dark"]), true)
	_add_box("DividerRightA", Vector3(1.45, 3.0, 0.22), Vector3(6.125, 1.5, 0), _mat(palette["wall_dark"]), true)
	_add_box("DividerRightB", Vector3(1.85, 3.0, 0.22), Vector3(9.075, 1.5, 0), _mat(palette["wall_dark"]), true)
	_add_box("DividerCenterHorizontal", Vector3(10.8, 3.0, 0.22), Vector3(0, 1.5, 0), _mat(palette["wall_dark"]), true)

	_add_hinged_door("FrontEntrance", Vector3(0.95, 0, 6.0), 1.7, 0.0, -1.0, "大門", Color(0.27, 0.15, 0.09))
	_add_hinged_door("BedroomDoor", Vector3(0.0, 0, -1.95), 1.3, PI / 2.0, 1.0, "臥室門", Color(0.74, 0.34, 0.10))
	_add_hinged_door("LivingDoor", Vector3(0.0, 0, 3.25), 1.3, PI / 2.0, -1.0, "客廳門", Color(0.63, 0.27, 0.08))
	_add_hinged_door("LeftInnerDoor", Vector3(-8.15, 0, 0.0), 1.3, 0.0, 1.0, "內側房門", Color(0.70, 0.32, 0.09))
	_add_hinged_door("RightInnerDoor", Vector3(6.85, 0, 0.0), 1.3, 0.0, -1.0, "浴室門", Color(0.26, 0.50, 0.50))

	_add_room_sign("客廳 LIVING", Vector3(-7.7, 2.55, 5.78), Color(0.95, 0.72, 0.34))
	_add_room_sign("廚房 KITCHEN", Vector3(7.0, 2.55, 5.78), Color(0.46, 0.82, 1.0))
	_add_room_sign("臥室 BEDROOM", Vector3(-7.5, 2.55, -5.78), Color(0.78, 0.52, 0.95))
	_add_room_sign("浴室 BATHROOM", Vector3(7.0, 2.55, -5.78), Color(0.35, 0.94, 0.76))

	if _use_progressive_room_loading():
		# The entrance shell is deliberately complete before any heavy glTF is
		# requested. The living room is the first playable room; the remaining
		# rooms are requested one at a time after the round has started.
		return

	_build_living_room()
	_build_kitchen()
	_build_bedroom()
	_build_bathroom()
	loaded_rooms = {"客廳": true, "廚房": true, "臥室": true, "浴室": true}
	preload("res://room_finishes.gd").build(self)


func _use_progressive_room_loading() -> bool:
	# Headless QA needs a deterministic, fully-built world. Release and Web
	# builds use the streaming path so the entrance and first room appear first.
	return DisplayServer.get_name() != "headless"


func _begin_progressive_room_loading() -> void:
	progressive_loading = true
	initial_room_ready = false
	room_load_queue = [
		{"id": "kitchen", "room": "廚房", "path": "res://assets/models/kitchen/kitchen_core.gltf"},
		{"id": "bedroom", "room": "臥室", "path": ""},
		{"id": "bathroom", "room": "浴室", "path": "res://assets/models/bathroom/bathroom_core.gltf"}
	]
	_set_loading_text("正在準備入口與客廳…")
	_request_room("living", "客廳", "res://assets/models/living_room/living_room_2_core.gltf", true)


func _request_room(room_id: String, room_name: String, path: String, is_initial: bool = false) -> void:
	room_request_id = room_id
	room_request_path = path
	room_request_progress = []
	_set_loading_text(("正在載入" if is_initial else "背景載入") + "：「%s」…" % room_name)
	var error := ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if error != OK:
		push_error("Unable to stream room %s: %s" % [room_id, error])
		var fallback := load(path) as PackedScene
		_finish_room_request(fallback)


func _poll_room_loading() -> void:
	if room_request_path.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(room_request_path, room_request_progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_finish_room_request(ResourceLoader.load_threaded_get(room_request_path) as PackedScene)
		return
	push_error("Room stream failed: %s (%s)" % [room_request_id, status])
	_finish_room_request(load(room_request_path) as PackedScene)


func _finish_room_request(scene: PackedScene) -> void:
	var completed_id := room_request_id
	var completed_path := room_request_path
	room_request_id = ""
	room_request_path = ""
	room_request_progress = []
	if scene == null:
		push_error("Room scene is unavailable: " + completed_path)
	else:
		match completed_id:
			"living":
				_build_living_room(scene)
				loaded_rooms["客廳"] = true
				preload("res://room_finishes.gd").build(self)
				initial_room_ready = true
				_start_round()
				_set_loading_text("背景載入佇列啟動中…")
			"kitchen":
				_build_kitchen(scene)
				loaded_rooms["廚房"] = true
				_refresh_room_issue_targets("廚房")
			"bedroom":
				_build_bedroom()
				loaded_rooms["臥室"] = true
				_refresh_room_issue_targets("臥室")
			"bathroom":
				_build_bathroom(scene)
				loaded_rooms["浴室"] = true
				_refresh_room_issue_targets("浴室")

	if progressive_loading and initial_room_ready:
		_request_next_background_room()


func _request_next_background_room() -> void:
	if room_load_queue.is_empty():
		progressive_loading = false
		_set_loading_text("")
		return
	var next: Dictionary = room_load_queue.pop_front()
	if str(next["path"]).is_empty():
		# Bedroom is procedural and cheap, but still yield one frame so it does
		# not compete with the first interaction after the living room appears.
		_set_loading_text("背景載入：「%s」…" % next["room"])
		call_deferred("_finish_procedural_room", next)
		return
	_request_room(str(next["id"]), str(next["room"]), str(next["path"]))


func _finish_procedural_room(room_data: Dictionary) -> void:
	_build_bedroom()
	loaded_rooms[str(room_data["room"])] = true
	_refresh_room_issue_targets(str(room_data["room"]))
	_request_next_background_room()


func _set_loading_text(text_value: String) -> void:
	if loading_label != null:
		loading_label.text = text_value
		if not initial_room_ready:
			objective_label.text = "驗屋準備中…"
			timer_label.text = "載入中"



func _build_living_room(scene_override: PackedScene = null) -> void:
	var living_scene: PackedScene = scene_override
	if living_scene == null:
		living_scene = load("res://assets/models/living_room/living_room_2_core.gltf") as PackedScene
	if living_scene == null:
		_build_living_room_procedural()
		return

	var living_asset := living_scene.instantiate()
	living_asset.name = "LivingRoomRealAsset"
	living_asset.position = Vector3(-6.5, 0.0, 0.0)
	living_asset.scale = Vector3.ONE * 0.72
	add_child(living_asset)
	_remove_asset_shell(living_asset)
	_reposition_living_sofa(living_asset)
	_prepare_furniture(living_asset)
	_add_living_imported_details()
	_add_living_architecture_details()
	_add_living_window_details()


func _build_living_room_procedural() -> void:
	_add_box("Sofa", Vector3(4.2, 1.0, 1.2), Vector3(-6.4, 0.55, 3.8), _mat(palette["fabric"]), true)
	_add_box("SofaBack", Vector3(4.2, 1.5, 0.35), Vector3(-6.4, 1.1, 4.35), _mat(palette["fabric"]), true)
	_add_box("CoffeeTable", Vector3(2.2, 0.35, 1.1), Vector3(-6.0, 0.5, 2.0), _mat(palette["wood_light"]), true)
	_add_box("TVUnit", Vector3(3.2, 0.75, 0.55), Vector3(-7.9, 0.4, 5.15), _mat(palette["wood"]), true)
	_add_box("TV", Vector3(2.6, 1.45, 0.12), Vector3(-7.9, 1.45, 4.82), _mat(Color(0.025, 0.03, 0.04)), true)
	_add_box("PlantPot", Vector3(0.6, 0.5, 0.6), Vector3(-2.3, 0.25, 5.0), _mat(palette["yellow"]), true)
	_add_cylinder("Plant", 0.45, 1.5, Vector3(-2.3, 1.15, 5.0), _mat(palette["green"]), true)


func _add_living_imported_details() -> void:
	# Preserve the imported sofa silhouettes but add the close-up seams and table
	# edge from their actual bounds. This keeps the details attached if the hero
	# asset scale or room offset changes later.
	var seam_material := _mat(Color(0.18, 0.13, 0.18))
	var wood_material := _wood_mat(Color(0.42, 0.24, 0.12))
	var table_bounds := _find_living_mesh_bounds("73_Table")
	if table_bounds.has_volume():
		var table_center := table_bounds.get_center()
		var edge_y := table_bounds.end.y + 0.014
		_add_box("LivingDetail_CoffeeTableEdge_Front", Vector3(table_bounds.size.x + 0.035, 0.032, 0.032), Vector3(table_center.x, edge_y, table_bounds.position.z - 0.010), wood_material, false)
		_add_box("LivingDetail_CoffeeTableEdge_Back", Vector3(table_bounds.size.x + 0.035, 0.032, 0.032), Vector3(table_center.x, edge_y, table_bounds.end.z + 0.010), wood_material, false)
		_add_box("LivingDetail_CoffeeTableInset", Vector3(table_bounds.size.x * 0.72, 0.018, table_bounds.size.z * 0.58), Vector3(table_center.x, edge_y + 0.010, table_center.z), _mat(Color(0.16, 0.19, 0.20)), false)
	# The imported TV is mounted on the left wall with almost no visible
	# furniture below it. Build a shallow console and cable channel from the
	# actual TV bevel bounds so the wall assembly keeps its scale and orientation
	# when the living hero asset is moved.
	var tv_bounds := _find_living_mesh_bounds("60_TvBevel")
	if tv_bounds.has_volume():
		var tv_center := tv_bounds.get_center()
		var console_depth := 0.24
		var console_width := clampf(tv_bounds.size.z + 0.24, 0.72, 1.20)
		var console_x := tv_bounds.end.x + console_depth * 0.50 + 0.025
		_add_box("LivingDetail_TvConsole", Vector3(console_depth, 0.10, console_width), Vector3(console_x, tv_bounds.position.y - 0.10, tv_center.z), wood_material, false)
		_add_box("LivingDetail_TvConsoleInset", Vector3(console_depth + 0.012, 0.018, console_width * 0.72), Vector3(console_x + 0.008, tv_bounds.position.y - 0.038, tv_center.z), _mat(Color(0.12, 0.075, 0.045)), false)
		_add_box("LivingDetail_TvCableChannel", Vector3(0.035, tv_bounds.size.y * 0.62, 0.035), Vector3(tv_bounds.end.x + 0.035, tv_bounds.position.y - tv_bounds.size.y * 0.30, tv_center.z), _mat(Color(0.08, 0.09, 0.10)), false)

	var cushion_index := 0
	var living_asset := get_node_or_null("LivingRoomRealAsset") as Node3D
	if living_asset == null:
		return
	for cushion in living_asset.find_children("*", "MeshInstance3D", true, false):
		var mesh := cushion as MeshInstance3D
		var mesh_name := str(mesh.name).to_lower() if mesh != null else ""
		if mesh == null or "cushion" not in mesh_name:
			continue
		var cushion_bounds := mesh.global_transform * mesh.get_aabb()
		if cushion_bounds.size.x < 0.12 or cushion_bounds.size.y < 0.08:
			continue
		var seam_size := Vector3(cushion_bounds.size.x * 0.78, 0.014, 0.018)
		var seam_position := Vector3(cushion_bounds.get_center().x, cushion_bounds.end.y + 0.002, cushion_bounds.get_center().z)
		_add_box("LivingDetail_CushionSeam_%02d" % cushion_index, seam_size, seam_position, seam_material, false)
		cushion_index += 1
	if cushion_index == 0:
		return


func _add_living_architecture_details() -> void:
	# The imported fireplace is assembled from three thin scan surfaces. Add
	# manufactured hearth/mantel edges from those real bounds so the wall-side
	# furniture reads as one proportional architectural assembly.
	var marble := _mat(Color(0.14, 0.15, 0.16))
	marble.metallic = 0.12
	marble.roughness = 0.30
	var hearth_bounds := _find_living_mesh_bounds("117_BlackMarble")
	if hearth_bounds.has_volume():
		_add_box("LivingDetail_FireplaceHearthEdge", Vector3(hearth_bounds.size.x + 0.08, 0.035, hearth_bounds.size.z + 0.06), Vector3(hearth_bounds.get_center().x, hearth_bounds.end.y + 0.014, hearth_bounds.get_center().z), marble, false)
	var mantel_bounds := _find_living_mesh_bounds("118_WhitePaint")
	if mantel_bounds.has_volume():
		_add_box("LivingDetail_FireplaceMantelEdge", Vector3(mantel_bounds.size.x + 0.06, 0.035, mantel_bounds.size.z + 0.04), Vector3(mantel_bounds.get_center().x, mantel_bounds.end.y + 0.016, mantel_bounds.get_center().z), _mat(Color(0.76, 0.75, 0.70)), false)
	var side_bounds := _find_living_mesh_bounds("119_WhitePaint")
	if side_bounds.has_volume():
		_add_box("LivingDetail_FireplaceSideTrim", Vector3(side_bounds.size.x + 0.035, side_bounds.size.y * 0.94, 0.035), Vector3(side_bounds.get_center().x, side_bounds.get_center().y, side_bounds.position.z - 0.020), _mat(Color(0.70, 0.69, 0.65)), false)


func _add_living_window_details() -> void:
	# The source living scene's blind material is authored with an area-light /
	# alpha combination that renders as floating dark strips in Web Compatibility.
	# Rebuild the window from the source pane bounds with the same readable frame
	# language used by the rest of the playable house.
	var pane_bounds := _find_living_mesh_bounds("184_diffuse_00")
	if not pane_bounds.has_volume():
		return
	var glass_material := _glass_mat(Color(0.22, 0.54, 0.70), 0.55)
	var frame_material := _mat(Color(0.70, 0.66, 0.57))
	# Keep the hero sofa in the inspection-camera composition and move the
	# rebuilt window to the open wall reveal beside it.
	var window_center_x := pane_bounds.get_center().x - 2.0
	var window_min_x := pane_bounds.position.x - 2.0
	var window_max_x := pane_bounds.end.x - 2.0
	var center := Vector3(window_center_x, pane_bounds.get_center().y, pane_bounds.position.z - 0.025)
	var glass_size := Vector3(pane_bounds.size.x * 0.94, pane_bounds.size.y * 0.88, 0.045)
	_add_box("LivingWindowGlass", glass_size, center, glass_material, false)
	var frame_width := 0.075
	var frame_depth := 0.075
	_add_box("LivingWindowFrame_Top", Vector3(pane_bounds.size.x + 0.12, frame_width, frame_depth), Vector3(center.x, pane_bounds.end.y + 0.02, center.z - 0.008), frame_material, false)
	_add_box("LivingWindowFrame_Bottom", Vector3(pane_bounds.size.x + 0.12, frame_width, frame_depth), Vector3(center.x, pane_bounds.position.y - 0.02, center.z - 0.008), frame_material, false)
	_add_box("LivingWindowFrame_Left", Vector3(frame_width, pane_bounds.size.y + 0.04, frame_depth), Vector3(window_min_x - 0.02, center.y, center.z - 0.008), frame_material, false)
	_add_box("LivingWindowFrame_Right", Vector3(frame_width, pane_bounds.size.y + 0.04, frame_depth), Vector3(window_max_x + 0.02, center.y, center.z - 0.008), frame_material, false)
	_add_box("LivingWindowFrame_Center", Vector3(frame_width * 0.72, pane_bounds.size.y * 0.88, frame_depth * 0.84), Vector3(center.x, center.y, center.z - 0.010), frame_material, false)


func _reposition_living_sofa(asset: Node3D) -> void:
	# The imported sofa was authored in the center of the room, leaving more
	# than two metres behind it. Keep a believable 1.10m service gap to the
	# playable front wall and move the complete leather/cushion assembly before
	# furniture collision and contact-shadow generation.
	var sofa_names: Array = ["63_SofaLeather", "65_SofaLeather", "134_SofaLeather", "136_SofaLeather", "137_SofaLeather", "138_SofaLeather", "139_SofaLeather"]
	var sofa_bounds := _find_anchor_group_bounds(sofa_names)
	var wall_bounds := _find_anchor_bounds("FrontWallLeft")
	if not sofa_bounds.has_volume() or not wall_bounds.has_volume():
		return
	var desired_clearance := 1.10
	var delta_z := (wall_bounds.position.z - desired_clearance) - sofa_bounds.end.z
	var delta_x := 0.0
	if absf(delta_z) < 0.02 and absf(delta_x) < 0.02:
		return
	for mesh in asset.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := str(mesh.name)
		if "SofaLeather" in mesh_name or "Cushion" in mesh_name or mesh_name in ["73_Table", "144_TableLegs", "141_Carpet"]:
			mesh.global_position += Vector3(delta_x, 0, delta_z)


func _find_living_mesh_bounds(mesh_name: String) -> AABB:
	var living_asset := get_node_or_null("LivingRoomRealAsset") as Node3D
	if living_asset == null:
		return AABB()
	var mesh := living_asset.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh == null:
		return AABB()
	return mesh.global_transform * mesh.get_aabb()


func _build_kitchen(scene_override: PackedScene = null) -> void:
	var kitchen_scene: PackedScene = scene_override
	if kitchen_scene == null:
		kitchen_scene = load("res://assets/models/kitchen/kitchen_core.gltf") as PackedScene
	if kitchen_scene == null:
		_build_kitchen_procedural()
		return

	var kitchen_asset := kitchen_scene.instantiate()
	kitchen_asset.name = "KitchenRealAsset"
	kitchen_asset.position = KITCHEN_ASSET_ORIGIN
	kitchen_asset.rotation.y = PI
	kitchen_asset.scale = Vector3.ONE * KITCHEN_ASSET_SCALE
	add_child(kitchen_asset)
	_remove_asset_shell(kitchen_asset)
	_prepare_furniture(kitchen_asset)
	_add_kitchen_imported_details()


func _add_kitchen_imported_details() -> void:
	# Small high-contrast props make the imported kitchen readable at the
	# inspection distance without adding another texture set to the Web build.
	var steel := _mat(Color(0.52, 0.57, 0.58))
	steel.metallic = 0.72
	steel.roughness = 0.24
	var ceramic := _mat(Color(0.78, 0.80, 0.77))
	var dark := _mat(Color(0.07, 0.08, 0.08))
	var wood := _wood_mat(Color(0.63, 0.38, 0.18))
	# The sink used to be authored from a stale fixed point. Attach the whole
	# assembly to the real worktop bounds so the basin and the sink_leak anchor
	# remain coincident when the kitchen hero scale changes.
	var sink_worktop := _find_kitchen_mesh_bounds("123_Worktops")
	var sink_center := _kitchen_point(Vector3(6.35, 0.65, 4.55))
	var sink_surface_y := sink_center.y
	var sink_size := Vector2(0.72, 0.48)
	if sink_worktop.has_volume():
		sink_center = Vector3(sink_worktop.get_center().x, sink_worktop.end.y + 0.006, sink_worktop.get_center().z)
		sink_surface_y = sink_center.y
		sink_size = Vector2(minf(0.44, sink_worktop.size.x * 0.72), minf(0.48, sink_worktop.size.z * 0.42))
	var basin_size := Vector3(sink_size.x, 0.08, sink_size.y)
	_add_box("KitchenDetail_SinkBasin", basin_size, Vector3(sink_center.x, sink_surface_y - 0.035, sink_center.z), dark, false)
	_add_box("KitchenDetail_SinkRim", Vector3(sink_size.x + 0.12, 0.045, sink_size.y + 0.12), Vector3(sink_center.x, sink_surface_y + 0.005, sink_center.z), steel, false)
	_add_cylinder("KitchenDetail_FaucetStem", 0.035, 0.38, Vector3(sink_center.x, sink_surface_y + 0.20, sink_center.z - sink_size.y * 0.40), steel, false)
	_add_box("KitchenDetail_FaucetSpout", Vector3(0.24, 0.045, 0.045), Vector3(sink_center.x, sink_surface_y + 0.37, sink_center.z - sink_size.y * 0.16), steel, false)
	_add_cylinder("KitchenDetail_FaucetHandle", 0.025, 0.14, Vector3(sink_center.x + sink_size.x * 0.42, sink_surface_y + 0.20, sink_center.z - sink_size.y * 0.40), steel, false)
	for knob_index in range(4):
		_add_cylinder("KitchenDetail_CookerKnob_%d" % knob_index, 0.045, 0.025, _kitchen_point(Vector3(6.25 + knob_index * 0.18, 0.70, 3.62)), steel, false)
	_add_box("KitchenDetail_CuttingBoard", Vector3(0.48, 0.035, 0.34), _kitchen_point(Vector3(5.25, 0.66, 4.32)), wood, false)
	_add_cylinder("KitchenDetail_Cup", 0.09, 0.16, _kitchen_point(Vector3(5.68, 0.76, 4.12)), ceramic, false)
	_add_cylinder("KitchenDetail_CupHandle", 0.055, 0.025, _kitchen_point(Vector3(5.78, 0.76, 4.12)), ceramic, false)
	# Bind the refrigerator pull to the tall imported cabinet that also anchors
	# the cabinet-blocked inspection issue. The old authored point belonged to
	# the previous kitchen scale and appeared as a floating vertical bar.
	var fridge_bounds := _find_kitchen_mesh_bounds("253_CupboardUnits")
	if fridge_bounds.has_volume():
		var fridge_handle_height := clampf(fridge_bounds.size.y * 0.86, 0.48, 0.68)
		var fridge_handle_pos := Vector3(fridge_bounds.position.x - 0.035, fridge_bounds.get_center().y, fridge_bounds.get_center().z)
		_add_box("KitchenDetail_FridgeHandle", Vector3(0.045, fridge_handle_height, 0.045), fridge_handle_pos, steel, false)
	else:
		_add_box("KitchenDetail_FridgeHandle", Vector3(0.045, 0.60, 0.045), _kitchen_point(Vector3(6.27, 1.04, 2.72)), steel, false)
	# The extractor hood is a dense imported hero mesh, but its scan has no
	# readable duct transition. Build the trim from its real bounds so the
	# exhaust clue and the cabinet connection remain aligned after rescaling.
	var hood_bounds := _find_kitchen_mesh_bounds("255_ExtractorHood")
	if hood_bounds.has_volume():
		var hood_center := hood_bounds.get_center()
		var hood_trim := _mat(Color(0.22, 0.24, 0.24))
		hood_trim.metallic = 0.62
		hood_trim.roughness = 0.30
		_add_box("KitchenDetail_ExtractorHood_Rim", Vector3(hood_bounds.size.x + 0.08, 0.045, hood_bounds.size.z + 0.08), Vector3(hood_center.x, hood_bounds.position.y - 0.018, hood_center.z), hood_trim, false)
		_add_box("KitchenDetail_ExtractorHood_Duct", Vector3(hood_bounds.size.x * 0.56, maxf(0.16, hood_bounds.size.y * 0.72), hood_bounds.size.z * 0.48), Vector3(hood_center.x, hood_bounds.end.y + hood_bounds.size.y * 0.32, hood_center.z), hood_trim, false)
		_add_box("KitchenDetail_ExtractorHood_Flange", Vector3(hood_bounds.size.x * 0.68, 0.035, hood_bounds.size.z * 0.58), Vector3(hood_center.x, hood_bounds.end.y + hood_bounds.size.y * 0.70, hood_center.z), steel, false)
	# Derive the under-cabinet light from the actual upper cabinet bounds. The
	# previous authored point used the old 0.60 scale and left a long glowing
	# bar inside the cabinet run after the kitchen was enlarged to 0.72.
	var upper_cabinet_bounds := _find_kitchen_mesh_bounds("74_CupboardUnits")
	if upper_cabinet_bounds.has_volume():
		var light_size := Vector3(maxf(0.12, upper_cabinet_bounds.size.x * 0.78), 0.025, maxf(0.42, upper_cabinet_bounds.size.z * 0.82))
		var light_pos := Vector3(upper_cabinet_bounds.get_center().x, upper_cabinet_bounds.position.y - 0.018, upper_cabinet_bounds.get_center().z)
		_add_box("KitchenDetail_UnderCabinetLight", light_size, light_pos, _emissive_mat(Color(1.0, 0.72, 0.38), 0.75), false)
	else:
		_add_box("KitchenDetail_UnderCabinetLight", Vector3(0.20, 0.025, 0.80), _kitchen_point(Vector3(6.25, 1.08, 4.00)), _emissive_mat(Color(1.0, 0.72, 0.38), 0.75), false)
	_add_kitchen_dining_details()


func _add_kitchen_dining_details() -> void:
	# The table and chairs are part of the imported model. Derive the close-up
	# finish pieces from their actual world bounds so a future asset scale change
	# cannot leave trim, seat pads, or fasteners floating in the room.
	var table_bounds := _find_kitchen_mesh_bounds("63_Tabletop")
	if not table_bounds.has_volume():
		return
	var wood := _wood_mat(Color(0.58, 0.31, 0.14))
	var fabric := _mat(Color(0.13, 0.22, 0.25))
	var dark_wood := _wood_mat(Color(0.24, 0.10, 0.045))
	var steel := _mat(Color(0.48, 0.51, 0.50))
	var table_center := table_bounds.get_center()
	var edge_y := table_bounds.end.y + 0.018
	var edge_x := table_bounds.size.x + 0.045
	var edge_z := table_bounds.size.z + 0.045
	var edge_thickness := 0.036
	_add_box("KitchenDetail_TableEdge_Front", Vector3(edge_x, edge_thickness, edge_thickness), Vector3(table_center.x, edge_y, table_bounds.position.z - 0.012), dark_wood, false)
	_add_box("KitchenDetail_TableEdge_Back", Vector3(edge_x, edge_thickness, edge_thickness), Vector3(table_center.x, edge_y, table_bounds.end.z + 0.012), dark_wood, false)
	_add_box("KitchenDetail_TableEdge_Left", Vector3(edge_thickness, edge_thickness, edge_z), Vector3(table_bounds.position.x - 0.012, edge_y, table_center.z), dark_wood, false)
	_add_box("KitchenDetail_TableEdge_Right", Vector3(edge_thickness, edge_thickness, edge_z), Vector3(table_bounds.end.x + 0.012, edge_y, table_center.z), dark_wood, false)
	for corner_index in range(4):
		var corner_x := table_bounds.position.x + (table_bounds.size.x if corner_index % 2 == 1 else 0.0)
		var corner_z := table_bounds.position.z + (table_bounds.size.z if corner_index >= 2 else 0.0)
		_add_cylinder("KitchenDetail_TableBolt_%d" % corner_index, 0.014, 0.012, Vector3(corner_x, edge_y + 0.018, corner_z), steel, false)
	# Give the imported table a readable floor contact at each leg position.
	# These are render-only rubber/metal pads, deliberately kept separate from
	# the player's collision furniture so they cannot catch the capsule.
	var foot_material := _mat(Color(0.12, 0.13, 0.13))
	var foot_y := maxf(0.025, table_bounds.position.y - 0.56)
	for foot_index in range(4):
		var foot_x := table_bounds.position.x + 0.16 if foot_index % 2 == 0 else table_bounds.end.x - 0.16
		var foot_z := table_bounds.position.z + 0.16 if foot_index < 2 else table_bounds.end.z - 0.16
		_add_box("KitchenDetail_TableFootPad_%d" % foot_index, Vector3(0.16, 0.025, 0.16), Vector3(foot_x, foot_y, foot_z), foot_material, false)

	var cushion_index := 0
	for cushion in get_node("KitchenRealAsset").find_children("*", "MeshInstance3D", true, false):
		var mesh := cushion as MeshInstance3D
		if mesh == null or "cushion1" not in str(mesh.name).to_lower():
			continue
		var cushion_bounds := mesh.global_transform * mesh.get_aabb()
		if cushion_bounds.size.x < 0.12 or cushion_bounds.size.z < 0.12:
			continue
		var pad_size := Vector3(cushion_bounds.size.x * 0.88, 0.038, cushion_bounds.size.z * 0.88)
		var pad_position := Vector3(cushion_bounds.get_center().x, cushion_bounds.end.y + 0.021, cushion_bounds.get_center().z)
		_add_box("KitchenDetail_ChairPad_%02d" % cushion_index, pad_size, pad_position, fabric, false)
		_add_box("KitchenDetail_ChairPad_Piping_%02d" % cushion_index, Vector3(pad_size.x + 0.018, 0.012, 0.018), Vector3(pad_position.x, pad_position.y + 0.023, pad_position.z - pad_size.z * 0.5), dark_wood, false)
		cushion_index += 1
	if cushion_index == 0:
		# Keep the test scene useful even if a later kitchen asset renames its
		# cushion nodes: this fallback still stays attached to the table bounds.
		_add_box("KitchenDetail_ChairPad_Fallback", Vector3(0.30, 0.038, 0.26), Vector3(table_center.x - table_bounds.size.x * 0.35, edge_y - 0.20, table_bounds.end.z + 0.28), fabric, false)


func _find_kitchen_mesh_bounds(mesh_name: String) -> AABB:
	var kitchen_asset := get_node_or_null("KitchenRealAsset") as Node3D
	if kitchen_asset == null:
		return AABB()
	var mesh := kitchen_asset.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh == null:
		return AABB()
	return mesh.global_transform * mesh.get_aabb()


func _kitchen_point(base_point: Vector3) -> Vector3:
	# Detail props were authored against the original 0.60 room scale. Keep
	# their local relationship to the imported asset when the hero furniture is
	# enlarged for a more believable room proportion.
	return KITCHEN_ASSET_ORIGIN + (base_point - KITCHEN_ASSET_ORIGIN) * (KITCHEN_ASSET_SCALE / KITCHEN_ASSET_BASE_SCALE)


func _build_kitchen_procedural() -> void:
	_add_box("KitchenCounter", Vector3(7.0, 1.25, 1.0), Vector3(5.6, 0.62, 4.65), _mat(palette["wood_light"]), true)
	_add_box("CounterTop", Vector3(7.15, 0.12, 1.08), Vector3(5.6, 1.3, 4.65), _mat(palette["white"]), true)
	_add_box("UpperCabinet", Vector3(3.0, 1.1, 0.45), Vector3(3.0, 2.35, 5.55), _mat(palette["wood"]), true)
	_add_box("Fridge", Vector3(1.3, 2.5, 1.1), Vector3(8.6, 1.25, 2.8), _mat(palette["metal"]), true)
	_add_cylinder("Sink", 0.55, 0.12, Vector3(4.2, 1.42, 4.65), _mat(palette["metal"]), false)
	_add_box("Oven", Vector3(1.2, 1.2, 0.85), Vector3(7.1, 0.65, 4.65), _mat(Color(0.12, 0.14, 0.16)), true)
	_add_box("DiningTable", Vector3(2.4, 0.15, 1.3), Vector3(4.2, 2.0, 2.1), _mat(palette["wood_light"]), true)
	_add_box("DiningLeg", Vector3(0.18, 1.2, 0.18), Vector3(3.3, 1.4, 1.6), _mat(palette["wood"]), true)
	_add_box("DiningLeg2", Vector3(0.18, 1.2, 0.18), Vector3(5.1, 1.4, 1.6), _mat(palette["wood"]), true)


func _build_bedroom() -> void:
	# 臥室沒有使用單一灰盒：床、軟件、收納、工作區與窗邊飾品皆拆成可辨識的家具部件。
	_add_box("BedroomRug", Vector3(4.8, 0.05, 3.6), Vector3(-5.7, 0.03, -3.2), _mat(Color(0.19, 0.25, 0.30)), false)
	_add_box("BedBase", Vector3(3.4, 0.55, 2.6), Vector3(-6.2, 0.35, -3.3), _wood_mat(Color(0.92, 0.72, 0.50)), true)
	_add_box("BedHeadboard", Vector3(3.55, 1.25, 0.16), Vector3(-6.2, 1.15, -4.55), _wood_mat(Color(0.72, 0.48, 0.30)), true)
	_add_box("Mattress", Vector3(3.25, 0.42, 2.5), Vector3(-6.2, 0.83, -3.3), _fabric_mat(Color(0.72, 0.78, 0.84)), true)
	_add_box("Duvet", Vector3(3.12, 0.16, 1.45), Vector3(-6.2, 1.12, -2.85), _fabric_mat(Color(0.55, 0.70, 0.82)), false)
	_add_box("PillowLeft", Vector3(1.2, 0.18, 0.65), Vector3(-6.92, 1.15, -4.12), _fabric_mat(Color(0.88, 0.90, 0.88)), false)
	_add_box("PillowRight", Vector3(1.2, 0.18, 0.65), Vector3(-5.48, 1.15, -4.12), _fabric_mat(Color(0.88, 0.90, 0.88)), false)
	_add_box("BedThrow", Vector3(3.15, 0.09, 0.42), Vector3(-6.2, 1.22, -2.15), _fabric_mat(Color(0.82, 0.52, 0.32)), false)
	for bedside_index in range(2):
		var bedside_x: float = -8.25 if bedside_index == 0 else -4.15
		var bedside_side := "Left" if bedside_index == 0 else "Right"
		_add_box("BedsideTable_" + bedside_side, Vector3(0.72, 0.62, 0.62), Vector3(bedside_x, 0.31, -4.25), _wood_mat(Color(0.86, 0.62, 0.38)), true)
		_add_cylinder("BedsideLampBase_" + bedside_side, 0.10, 0.30, Vector3(bedside_x, 0.82, -4.25), _mat(palette["metal"]), false)
		_add_cylinder("BedsideLampShade_" + bedside_side, 0.24, 0.30, Vector3(bedside_x, 1.10, -4.25), _mat(Color(0.70, 0.54, 0.32)), false)
	_add_box("Closet", Vector3(2.3, 2.4, 0.65), Vector3(-1.9, 1.2, -4.8), _wood_mat(Color(0.88, 0.66, 0.42)), true)
	_add_box("ClosetDoorLeft", Vector3(1.06, 2.18, 0.04), Vector3(-2.47, 1.2, -4.44), _wood_mat(Color(0.74, 0.50, 0.30)), false)
	_add_box("ClosetDoorRight", Vector3(1.06, 2.18, 0.04), Vector3(-1.33, 1.2, -4.44), _wood_mat(Color(0.74, 0.50, 0.30)), false)
	_add_cylinder("ClosetHandleLeft", 0.035, 0.38, Vector3(-1.98, 1.2, -4.40), _mat(palette["metal"]), false)
	_add_cylinder("ClosetHandleRight", 0.035, 0.38, Vector3(-1.82, 1.2, -4.40), _mat(palette["metal"]), false)
	_add_box("Desk", Vector3(2.4, 0.85, 0.75), Vector3(-2.6, 0.45, -1.45), _wood_mat(Color(0.84, 0.60, 0.36)), true)
	_add_box("DeskTop", Vector3(2.55, 0.10, 0.85), Vector3(-2.6, 0.91, -1.45), _wood_mat(Color(0.94, 0.72, 0.46)), false)
	_add_box("Monitor", Vector3(0.92, 0.58, 0.06), Vector3(-2.9, 1.32, -1.76), _mat(Color(0.025, 0.035, 0.045)), false)
	_add_cylinder("MonitorStand", 0.07, 0.38, Vector3(-2.9, 1.08, -1.70), _mat(palette["metal"]), false)
	_add_box("DeskChairBack", Vector3(0.65, 0.72, 0.12), Vector3(-2.6, 0.88, -0.35), _fabric_mat(Color(0.45, 0.60, 0.70)), true)
	_add_cylinder("DeskChairSeat", 0.40, 0.12, Vector3(-2.6, 0.55, -0.55), _fabric_mat(Color(0.45, 0.60, 0.70)), true)
	_add_box("Bookcase", Vector3(0.72, 2.10, 0.36), Vector3(-9.1, 1.05, -4.65), _wood_mat(Color(0.70, 0.48, 0.30)), true)
	for book_index in range(6):
		var book_x: float = -9.34 + float(book_index % 3) * 0.23
		var book_y: float = 0.48 + float(book_index / 3) * 0.75
		_add_box("BedroomBook_" + str(book_index), Vector3(0.16, 0.48, 0.28), Vector3(book_x, book_y, -4.42), _mat(Color(0.24 + 0.09 * book_index, 0.18, 0.19 + 0.06 * (book_index % 2))), false)
	_add_box("WindowFrame", Vector3(2.5, 1.55, 0.16), Vector3(-7.7, 1.75, -5.82), _mat(palette["metal"]), true)
	_add_box("WindowGlass", Vector3(2.15, 1.2, 0.05), Vector3(-7.7, 1.75, -5.72), _mat(Color(0.22, 0.54, 0.70)), false)
	_add_box("CurtainLeft", Vector3(0.48, 1.65, 0.08), Vector3(-8.82, 1.72, -5.67), _mat(Color(0.25, 0.32, 0.42)), false)
	_add_box("CurtainRight", Vector3(0.48, 1.65, 0.08), Vector3(-6.58, 1.72, -5.67), _mat(Color(0.25, 0.32, 0.42)), false)
	_add_box("WallArtFrame", Vector3(1.35, 0.95, 0.06), Vector3(-4.0, 1.85, -5.75), _mat(Color(0.12, 0.09, 0.07)), false)
	_add_box("WallArt", Vector3(1.18, 0.77, 0.03), Vector3(-4.0, 1.85, -5.70), _mat(Color(0.28, 0.48, 0.52)), false)
	_add_cylinder("BedroomPlantPot", 0.27, 0.42, Vector3(-8.85, 0.22, -1.30), _mat(Color(0.38, 0.22, 0.12)), true)
	_add_cylinder("BedroomPlant", 0.38, 1.05, Vector3(-8.85, 0.85, -1.30), _mat(palette["green"]), false)
	# Put the escape-window clue beside the bed, accessible from its right aisle.
	for fixture in ["WindowFrame", "WindowGlass", "CurtainLeft", "CurtainRight"]:
		get_node(fixture).position.x += 3.7
	for fixture in ["WallArtFrame", "WallArt"]:
		get_node(fixture).position.x -= 3.7
	preload("res://bedroom_details.gd").apply(self)


func _build_bathroom(scene_override: PackedScene = null) -> void:
	var bathroom_scene: PackedScene = scene_override
	if bathroom_scene == null:
		bathroom_scene = load("res://assets/models/bathroom/bathroom_core.gltf") as PackedScene
	if bathroom_scene == null:
		_build_bathroom_procedural()
		return

	var bathroom_asset := bathroom_scene.instantiate()
	bathroom_asset.name = "BathroomRealAsset"
	bathroom_asset.position = Vector3(5.0, 0.0, -3.35)
	add_child(bathroom_asset)
	_remove_asset_shell(bathroom_asset)

	_prepare_furniture(bathroom_asset)
	preload("res://static_batch.gd").build(bathroom_asset)
	var bathroom_detail_root := Node3D.new()
	bathroom_detail_root.name = "BathroomDetailBatch"
	add_child(bathroom_detail_root)
	_add_bathroom_imported_details(bathroom_detail_root)
	# Batch on the next idle frame, after the newly-created root has entered the
	# scene tree; this keeps visibility checks valid in both headless QA and Web.
	call_deferred("_batch_bathroom_details", bathroom_detail_root)


func _batch_bathroom_details(detail_root: Node3D) -> void:
	if is_instance_valid(detail_root):
		preload("res://static_batch.gd").build(detail_root)


func _add_bathroom_imported_details(detail_root: Node3D) -> void:
	# The imported bathroom provides the vanity and tub, but leaves the wet
	# zone visually unfinished. Add the missing sanitaryware as separate,
	# readable pieces after batching so each prop keeps its own silhouette.
	var porcelain := _mat(Color(0.76, 0.78, 0.76))
	var seat_material := _mat(Color(0.58, 0.60, 0.58))
	var lid_material := _mat(Color(0.84, 0.85, 0.82))
	var button_material := _mat(Color(0.42, 0.44, 0.42))
	var steel := _mat(palette["metal"])
	var tray_material := _mat(Color(0.68, 0.70, 0.68))
	var glass_material := _glass_mat(Color(0.35, 0.62, 0.70), 0.12)
	var dark_shampoo := _mat(Color(0.24, 0.52, 0.70))
	var warm_shampoo := _mat(Color(0.75, 0.38, 0.28))
	var towel_material := _mat(Color(0.72, 0.48, 0.35))
	var towel_fold_material := _mat(Color(0.54, 0.33, 0.25))
	# The drain cover is also brushed metal; reuse the bathroom steel material
	# so it does not create a separate static-batch material group.
	var drain_material := steel
	var bowl_shadow_material := _mat(Color(0.34, 0.43, 0.43))
	var mirror_bounds := _find_bathroom_mesh_bounds("44_Mirror")
	if mirror_bounds.has_volume():
		var vanity_x := mirror_bounds.get_center().x
		var vanity_y := mirror_bounds.position.y - 0.12
		var vanity_z := mirror_bounds.end.z + 0.18
		var left_sink_x := vanity_x - mirror_bounds.size.x * 0.27
		var right_sink_x := vanity_x + mirror_bounds.size.x * 0.27
		_add_box("ImportedBath_VanityCounterEdge", Vector3(mirror_bounds.size.x + 0.16, 0.05, 0.56), Vector3(vanity_x, vanity_y, vanity_z), tray_material, false, detail_root)
		for sink_data in [["Left", left_sink_x], ["Right", right_sink_x]]:
			var sink_name: String = sink_data[0]
			var sink_x: float = sink_data[1]
			var basin_body := _add_cylinder("ImportedBath_VanityBasin" + sink_name, 0.18, 0.07, Vector3(sink_x, vanity_y + 0.055, vanity_z + 0.04), porcelain, false, detail_root)
			# A shallow ellipsoid reads as a ceramic basin while remaining a
			# render-only detail, so it cannot catch the player's capsule.
			var basin_mesh := basin_body.get_node("Mesh") as MeshInstance3D
			var basin_shape := SphereMesh.new()
			basin_shape.radius = 0.18
			basin_shape.height = 0.36
			basin_shape.radial_segments = 24
			basin_shape.rings = 12
			basin_mesh.mesh = basin_shape
			basin_mesh.scale = Vector3(1.0, 0.34, 1.18)
			basin_mesh.position.y = 0.035
			_add_cylinder("ImportedBath_VanityBasinInset" + sink_name, 0.125, 0.012, Vector3(sink_x, vanity_y + 0.145, vanity_z + 0.04), bowl_shadow_material, false, detail_root)
			_add_cylinder("ImportedBath_VanityFaucet" + sink_name, 0.025, 0.20, Vector3(sink_x, vanity_y + 0.19, vanity_z - 0.08), steel, false, detail_root)
			_add_box("ImportedBath_VanitySpout" + sink_name, Vector3(0.16, 0.025, 0.025), Vector3(sink_x, vanity_y + 0.29, vanity_z + 0.02), steel, false, detail_root)
		_add_box("ImportedBath_MirrorEdgeTop", Vector3(mirror_bounds.size.x + 0.06, 0.035, 0.035), Vector3(vanity_x, mirror_bounds.end.y + 0.018, mirror_bounds.end.z + 0.018), steel, false, detail_root)
		_add_box("ImportedBath_MirrorEdgeLeft", Vector3(0.035, mirror_bounds.size.y, 0.035), Vector3(mirror_bounds.position.x - 0.018, mirror_bounds.get_center().y, mirror_bounds.end.z + 0.018), steel, false, detail_root)
		_add_box("ImportedBath_MirrorEdgeRight", Vector3(0.035, mirror_bounds.size.y, 0.035), Vector3(mirror_bounds.end.x + 0.018, mirror_bounds.get_center().y, mirror_bounds.end.z + 0.018), steel, false, detail_root)
		# Cabinet pulls sit on the same bounds-derived vanity front as the
		# basins, so they cannot drift when the imported bathroom is rescaled.
		var handle_y := vanity_y - 0.26
		for handle_index in range(4):
			var handle_x := mirror_bounds.position.x + mirror_bounds.size.x * (0.18 + 0.21 * handle_index)
			_add_box("ImportedBath_VanityHandle_%d" % handle_index, Vector3(0.20, 0.025, 0.032), Vector3(handle_x, handle_y, vanity_z + 0.035), steel, false, detail_root)
	var toilet_base := _add_cylinder("ImportedBath_ToiletBase", 0.52, 0.62, Vector3(7.3, 0.31, -4.5), porcelain, true, detail_root)
	# Keep the box/cylinder collision predictable, but replace the visible
	# placeholder cylinder with a high-segment ceramic bowl silhouette.
	var toilet_mesh := toilet_base.get_node("Mesh") as MeshInstance3D
	var bowl_mesh := SphereMesh.new()
	bowl_mesh.radius = 0.50
	bowl_mesh.height = 1.0
	bowl_mesh.radial_segments = 32
	bowl_mesh.rings = 16
	toilet_mesh.mesh = bowl_mesh
	toilet_mesh.scale = Vector3(1.0, 0.70, 1.10)
	toilet_mesh.position.y = 0.05
	_add_box("ImportedBath_ToiletTank", Vector3(0.82, 0.80, 0.36), Vector3(7.3, 0.98, -4.78), porcelain, true, detail_root)
	_add_cylinder("ImportedBath_ToiletSeat", 0.40, 0.08, Vector3(7.3, 0.66, -4.5), seat_material, true, detail_root)
	_add_cylinder("ImportedBath_ToiletWater", 0.24, 0.018, Vector3(7.3, 0.705, -4.5), _mat(Color(0.20, 0.47, 0.55)), false, detail_root)
	_add_cylinder("ImportedBath_ToiletBowlRim", 0.46, 0.025, Vector3(7.3, 0.645, -4.5), porcelain, false, detail_root)
	_add_cylinder("ImportedBath_ToiletBowlInset", 0.31, 0.012, Vector3(7.3, 0.686, -4.5), bowl_shadow_material, false, detail_root)
	_add_box("ImportedBath_ToiletLid", Vector3(0.68, 0.045, 0.54), Vector3(7.3, 0.73, -4.70), lid_material, false, detail_root)
	_add_box("ImportedBath_ToiletHingeLeft", Vector3(0.07, 0.035, 0.045), Vector3(7.13, 0.765, -4.73), button_material, false, detail_root)
	_add_box("ImportedBath_ToiletHingeRight", Vector3(0.07, 0.035, 0.045), Vector3(7.47, 0.765, -4.73), button_material, false, detail_root)
	_add_cylinder("ImportedBath_FlushButton", 0.055, 0.025, Vector3(7.3, 1.39, -4.78), button_material, false, detail_root)
	_add_cylinder("ImportedBath_FlushButtonRing", 0.085, 0.012, Vector3(7.3, 1.405, -4.78), steel, false, detail_root)
	_add_box("ImportedBath_FlushLever", Vector3(0.035, 0.16, 0.035), Vector3(7.73, 1.18, -4.78), steel, false, detail_root)

	var shower_tray := _add_box("ImportedBath_ShowerTray", Vector3(2.8, 0.10, 2.2), Vector3(7.6, 0.08, -2.25), tray_material, true, detail_root)
	# Keep the entire glass/frame assembly attached to the tray. The old glass
	# used fixed world coordinates, so a future bathroom scale or translation
	# could leave the partition floating beside the wet zone.
	var shower_center := Vector3(7.6, 0.08, -2.25)
	var shower_size := Vector3(2.8, 0.10, 2.2)
	var tray_mesh := shower_tray.find_child("Mesh", true, false) as MeshInstance3D
	if tray_mesh != null:
		var tray_bounds := tray_mesh.global_transform * tray_mesh.get_aabb()
		if tray_bounds.has_volume():
			shower_center = tray_bounds.get_center()
			shower_size = tray_bounds.size
	var glass_x := shower_center.x + shower_size.x * 0.36
	var glass_z_size := shower_size.z * 1.08
	var frame_z_offset := shower_size.z * 0.55
	_add_box("ImportedBath_ShowerGlass", Vector3(0.07, 2.25, glass_z_size), Vector3(glass_x, 1.15, shower_center.z), glass_material, false, detail_root)
	_add_box("ImportedBath_ShowerFrame_Left", Vector3(0.10, 2.35, 0.08), Vector3(glass_x - 0.05, 1.18, shower_center.z - frame_z_offset), steel, false, detail_root)
	_add_box("ImportedBath_ShowerFrame_Right", Vector3(0.10, 2.35, 0.08), Vector3(glass_x - 0.05, 1.18, shower_center.z + frame_z_offset), steel, false, detail_root)
	_add_box("ImportedBath_ShowerFrame_Top", Vector3(0.10, 0.08, glass_z_size + 0.08), Vector3(glass_x - 0.05, 2.34, shower_center.z), steel, false, detail_root)
	_add_box("ImportedBath_ShowerFrame_Bottom", Vector3(0.10, 0.08, glass_z_size + 0.08), Vector3(glass_x - 0.05, 0.08, shower_center.z), steel, false, detail_root)
	# Keep the shower fittings in the wet zone, derived from the same tray.
	var shower_back_z := shower_center.z - shower_size.z * 0.37
	var shower_wall_x := shower_center.x - shower_size.x * 0.08
	_add_cylinder("ImportedBath_ShowerPipe", 0.045, 1.30, Vector3(shower_wall_x, 2.05, shower_back_z), steel, false, detail_root)
	_add_cylinder("ImportedBath_ShowerHead", 0.18, 0.10, Vector3(shower_wall_x, 2.68, shower_back_z), steel, false, detail_root)
	_add_cylinder("ImportedBath_ShowerHeadRose", 0.12, 0.018, Vector3(shower_wall_x, 2.735, shower_back_z), steel, false, detail_root)
	_add_box("ImportedBath_ShowerShelf", Vector3(0.70, 0.06, 0.24), Vector3(shower_center.x + shower_size.x * 0.24, 1.55, shower_back_z), steel, false, detail_root)
	_add_cylinder("ImportedBath_Shampoo", 0.08, 0.24, Vector3(shower_center.x + shower_size.x * 0.16, 1.70, shower_back_z), dark_shampoo, false, detail_root)
	_add_cylinder("ImportedBath_Shampoo2", 0.08, 0.24, Vector3(shower_center.x + shower_size.x * 0.32, 1.70, shower_back_z), warm_shampoo, false, detail_root)
	_add_cylinder("ImportedBath_ShowerControl", 0.07, 0.035, Vector3(shower_wall_x, 1.35, shower_back_z + 0.02), steel, false, detail_root)
	_add_box("ImportedBath_ShowerDrainCrossA", Vector3(0.18, 0.024, 0.025), Vector3(shower_center.x, 0.16, shower_center.z), steel, false, detail_root)
	_add_box("ImportedBath_ShowerDrainCrossB", Vector3(0.025, 0.024, 0.18), Vector3(shower_center.x, 0.16, shower_center.z), steel, false, detail_root)

	# The imported scene contains two stainless towel-rail mounts. Use their
	# world bounds as the source of truth instead of the old fixed wall point;
	# this keeps the rail and hanging towel on the same wall when the bathroom
	# asset is translated or rescaled.
	var towel_left_bounds := _find_bathroom_mesh_bounds("835_StainlessSmooth")
	var towel_right_bounds := _find_bathroom_mesh_bounds("834_StainlessSmooth")
	if towel_left_bounds.has_volume() and towel_right_bounds.has_volume():
		var towel_x := (towel_left_bounds.get_center().x + towel_right_bounds.get_center().x) * 0.5
		var towel_width := clampf(absf(towel_right_bounds.get_center().x - towel_left_bounds.get_center().x) + 0.12, 0.32, 0.95)
		var towel_mount_y := (towel_left_bounds.get_center().y + towel_right_bounds.get_center().y) * 0.5
		var towel_bar_y := towel_mount_y + 0.22
		var towel_wall_z := maxf(towel_left_bounds.end.z, towel_right_bounds.end.z) + 0.025
		_add_box("ImportedBath_TowelBar", Vector3(towel_width, 0.08, 0.08), Vector3(towel_x, towel_bar_y, towel_wall_z), steel, false, detail_root)
		_add_box("ImportedBath_Towel", Vector3(towel_width * 0.78, 0.58, 0.05), Vector3(towel_x, towel_bar_y - 0.30, towel_wall_z + 0.055), towel_material, false, detail_root)
		for towel_fold in range(3):
			_add_box("ImportedBath_TowelFold_%d" % towel_fold, Vector3(towel_width * 0.64, 0.018, 0.018), Vector3(towel_x, towel_bar_y - 0.22 - towel_fold * 0.14, towel_wall_z + 0.083), towel_fold_material, false, detail_root)
	else:
		_add_box("ImportedBath_TowelBar", Vector3(0.95, 0.08, 0.08), Vector3(3.7, 1.42, -5.76), steel, false, detail_root)
		_add_box("ImportedBath_Towel", Vector3(0.75, 0.58, 0.05), Vector3(3.7, 1.10, -5.70), towel_material, false, detail_root)
		for towel_fold in range(3):
			_add_box("ImportedBath_TowelFold_%d" % towel_fold, Vector3(0.62, 0.018, 0.018), Vector3(3.7, 1.18 - towel_fold * 0.14, -5.665), towel_fold_material, false, detail_root)
	_add_box("ImportedBath_DrainCover", Vector3(0.28, 0.02, 0.28), Vector3(shower_center.x, 0.145, shower_center.z), drain_material, false, detail_root)
	_add_box("ImportedBath_CeilingVent", Vector3(0.90, 0.05, 0.55), Vector3(6.15, 2.96, -3.60), steel, false, detail_root)


func _find_bathroom_mesh_bounds(mesh_name: String) -> AABB:
	var bathroom_asset := get_node_or_null("BathroomRealAsset") as Node3D
	if bathroom_asset == null:
		return AABB()
	var mesh := bathroom_asset.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh == null:
		return AABB()
	return mesh.global_transform * mesh.get_aabb()


func _prepare_furniture(asset: Node3D) -> void:
	_align_wall_fixtures(asset)
	for mesh in asset.find_children("*", "MeshInstance3D"):
		if not mesh.is_visible_in_tree():
			continue
		var imported_material_name := str(mesh.get_active_material(0).resource_name).to_lower() if mesh.get_active_material(0) != null else ""
		if asset.name == "LivingRoomRealAsset" and ("blind" in str(mesh.name).to_lower() or "blind" in imported_material_name):
			mesh.set_meta("hidden_imported_blind", true)
			mesh.hide()
			continue
		# Some source scenes contain invisible area-light cards exported as
		# `diffuse_00`. Compatibility renders those cards as black/brown planes;
		# the playable house already owns its real-time lights, so the cards must
		# not become visible furniture or collision candidates.
		if "diffuse_00" in str(mesh.name).to_lower() or "area_light" in imported_material_name:
			mesh.set_meta("hidden_imported_area_light", true)
			mesh.hide()
			continue
		_tune_imported_materials(mesh)
		# Old room-wide cornices/skirting no longer have supporting walls.
		if str(mesh.name) in ["120_WhitePaint", "123_WhitePaint", "124_WhitePaint", "126_WhitePaint", "127_WhitePaint", "128_WhitePaint", "129_WhitePaint", "130_WhitePaint", "131_WhitePaint", "219_Skirting"]:
			mesh.hide()
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if asset.name == "LivingRoomRealAsset" and "Picture" in str(mesh.name):
			var target_x: float = -9.78 if bounds.get_center().x < -6.0 else -0.24
			mesh.global_position.x += target_x - bounds.get_center().x
			if target_x > -1:
				mesh.global_position.z += 2.5
		# The render mesh is deliberately not used as the movement collider.
		# Imported furniture has many tiny bevels, legs and decorative triangles;
		# a trimesh collider makes the player's capsule snag on those edges.
		bounds = mesh.global_transform * mesh.get_aabb()
		_apply_imported_lod(asset, mesh, bounds)
		_add_high_poly_lod_proxy(asset, mesh, bounds)
		var blocks_door := false
		var blocking_passage := AABB()
		for data in doors.values():
			var hinge: Node3D = data["pivot"]
			var center: Vector3 = hinge.position + Basis(Vector3.UP, float(data["closed_angle"])) * Vector3(float(data["width"]) / 2.0, 1.1, 0)
			var passage := AABB(center - Vector3(0.85, 1.1, 0.85), Vector3(1.7, 2.2, 1.7))
			if bounds.intersects(passage):
				blocks_door = true
				blocking_passage = passage
				break
		if blocks_door:
			# Do not remove a whole piece of furniture just because an imported
			# bevel or trim overlaps the generous doorway safety volume. Room-shell
			# fragments can be hidden, but furniture remains visible and becomes
			# render-only at this exact piece so the player can still pass smoothly.
			if _is_door_clearance_shell(mesh):
				mesh.set_meta("hidden_for_door_clearance", true)
				mesh.hide()
			elif _can_reposition_door_clearance(mesh, bounds):
				mesh.global_position += _door_clearance_delta(bounds, blocking_passage)
				mesh.set_meta("repositioned_for_door_clearance", true)
			else:
				mesh.set_meta("door_clearance_visual_only", true)
			continue
		if _should_have_furniture_collision(mesh, bounds):
			_add_furniture_box_collision(asset, mesh, bounds)
			_add_contact_shadow(asset, mesh, bounds)


func _apply_imported_lod(asset: Node3D, mesh: MeshInstance3D, bounds: AABB) -> void:
	# Keep the high-detail hero furniture intact. Only small, non-colliding
	# decorations in the large imported living/kitchen scenes are culled after
	# the player is far enough away to make them sub-pixel on Web.
	if asset.name not in ["LivingRoomRealAsset", "KitchenRealAsset", "BathroomRealAsset"]:
		return
	if not _is_imported_lod_candidate(mesh, bounds):
		return
	mesh.visibility_range_end = 18.0
	mesh.visibility_range_end_margin = 2.0
	mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mesh.set_meta("distance_lod_applied", true)


func _add_high_poly_lod_proxy(asset: Node3D, mesh: MeshInstance3D, bounds: AABB) -> void:
	if asset.name not in ["LivingRoomRealAsset", "KitchenRealAsset", "BathroomRealAsset"]:
		return
	if _is_door_clearance_shell(mesh):
		return
	var triangles := _mesh_triangle_count(mesh.mesh)
	var proxy_threshold := 1200 if asset.name == "KitchenRealAsset" else (3000 if asset.name == "BathroomRealAsset" else 4000)
	if triangles < proxy_threshold:
		return
	var proxy := MeshInstance3D.new()
	proxy.name = "LODProxy_" + str(mesh.name)
	var box := BoxMesh.new()
	box.size = bounds.size
	proxy.mesh = box
	proxy.visible = false
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var source_material := mesh.get_active_material(0)
	if source_material != null:
		proxy.material_override = source_material
	add_child(proxy)
	proxy.global_position = bounds.get_center()
	var lod_distance := 15.0
	if asset.name == "KitchenRealAsset":
		# The kitchen source is the heaviest imported room. Keep the AABB proxy
		# active while the player is in the living room, then restore the full
		# model as soon as the player enters the kitchen inspection distance.
		lod_distance = 7.5
	elif asset.name == "BathroomRealAsset":
		# The bathroom has dense sanitaryware and foliage. Keep its proxy active
		# from the entrance until the player enters the inspection aisle.
		lod_distance = 7.0
	high_poly_lod_entries.append({
		"source": mesh,
		"proxy": proxy,
		"distance": lod_distance
	})
	mesh.set_meta("high_poly_lod_triangles", triangles)
	mesh.set_meta("high_poly_lod_distance", lod_distance)


func _mesh_triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var triangles := 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		if indices is PackedInt32Array and not indices.is_empty():
			triangles += indices.size() / 3
		elif vertices is PackedVector3Array:
			triangles += vertices.size() / 3
	return triangles


func _update_high_poly_lods() -> void:
	if player == null:
		return
	for entry in high_poly_lod_entries:
		var source := entry["source"] as MeshInstance3D
		var proxy := entry["proxy"] as MeshInstance3D
		if not is_instance_valid(source) or not is_instance_valid(proxy):
			continue
		var use_proxy := player.global_position.distance_to(source.global_position) > float(entry["distance"])
		source.visible = not use_proxy
		proxy.visible = use_proxy


func _is_imported_lod_candidate(mesh: MeshInstance3D, bounds: AABB) -> bool:
	if _should_have_furniture_collision(mesh, bounds):
		return false
	if bounds.size.length() > 1.15 or bounds.size.y > 0.95:
		return false
	var mesh_name := str(mesh.name).to_lower()
	for token in [
		"wall", "floor", "ceiling", "window", "picture", "painting", "mirror",
		"skirting", "frame", "door", "socket", "blind", "carpet", "rug"
	]:
		if token in mesh_name:
			return false
	return true


func _is_door_clearance_shell(mesh: MeshInstance3D) -> bool:
	# These are architectural fragments from the original room scan. They do
	# not belong to the furniture composition and have no valid wall to support
	# them after the room shell is replaced by the playable floor plan.
	var mesh_name := str(mesh.name).to_lower()
	for token in [
		"wall", "floor", "ceiling", "skirting", "cornice", "moulding",
		"trim", "shell", "room_shell", "doorframe", "door_frame"
	]:
		if token in mesh_name:
			return true
	return false


func _can_reposition_door_clearance(mesh: MeshInstance3D, bounds: AABB) -> bool:
	if bounds.size.length() > 1.25 or _should_have_furniture_collision(mesh, bounds):
		return false
	var mesh_name := str(mesh.name).to_lower()
	for token in [
		"lamp", "light", "picture", "painting", "plant", "book", "handle",
		"cable", "wire", "blind", "curtain", "decor", "tablemat", "plate"
	]:
		if token in mesh_name:
			return true
	return false


func _door_clearance_delta(bounds: AABB, passage: AABB) -> Vector3:
	var push_left := passage.position.x - bounds.end.x - 0.04
	var push_right := passage.end.x - bounds.position.x + 0.04
	var push_back := passage.position.z - bounds.end.z - 0.04
	var push_front := passage.end.z - bounds.position.z + 0.04
	var x_push := push_left if bounds.get_center().x < passage.get_center().x else push_right
	var z_push := push_back if bounds.get_center().z < passage.get_center().z else push_front
	if absf(x_push) < absf(z_push):
		return Vector3(x_push, 0, 0)
	return Vector3(0, 0, z_push)


func _tune_imported_materials(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	var mesh_name := str(mesh.name).to_lower()
	var roughness := 0.72
	var metallic := 0.0
	var clearcoat := 0.0
	var clearcoat_roughness := 0.35
	for surface in range(mesh.mesh.get_surface_count()):
		var source := mesh.get_active_material(surface)
		if not source is BaseMaterial3D:
			continue
		# glTF node names and material names are not always identical. Use both
		# so a mesh such as `65_ExtractorHood` still receives the metal finish
		# from its `ExtractorHood` material instead of inheriting a flat default.
		var source_name := str((source as BaseMaterial3D).resource_name).to_lower()
		var semantic_name := mesh_name + " " + source_name
		var surface_roughness := roughness
		var surface_metallic := metallic
		var surface_clearcoat := clearcoat
		var surface_clearcoat_roughness := clearcoat_roughness
		if _contains_any(semantic_name, ["metal", "steel", "chrome", "stainless", "iron", "gold", "handle", "burner", "extractor"]):
			surface_roughness = 0.28
			surface_metallic = 0.78
		elif _contains_any(semantic_name, ["glass", "window", "mirror"]):
			surface_roughness = 0.18
			surface_clearcoat = 0.35
			surface_clearcoat_roughness = 0.16
		elif _contains_any(semantic_name, ["wood", "table", "tabletop", "cupboard", "worktop", "drawer", "whitewood"]):
			surface_roughness = 0.56
			surface_clearcoat = 0.08
			surface_clearcoat_roughness = 0.28
		elif _contains_any(semantic_name, ["sofa", "cushion", "carpet", "blind", "towel", "foam", "rug"]):
			surface_roughness = 0.90
		elif _contains_any(semantic_name, ["ceramic", "porcelain", "marble", "tile", "tiles"]):
			surface_roughness = 0.34
			surface_clearcoat = 0.18
			surface_clearcoat_roughness = 0.22
		var cache_key := "%d:%.2f:%.2f:%.2f:%.2f" % [source.get_instance_id(), surface_roughness, surface_metallic, surface_clearcoat, surface_clearcoat_roughness]
		var tuned := imported_material_cache.get(cache_key) as BaseMaterial3D
		if tuned == null:
			tuned = source.duplicate() as BaseMaterial3D
			tuned.roughness = surface_roughness
			tuned.metallic = surface_metallic
			var standard := tuned as StandardMaterial3D
			if standard != null:
				standard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				standard.clearcoat = surface_clearcoat
				standard.clearcoat_roughness = surface_clearcoat_roughness
			imported_material_cache[cache_key] = tuned
		mesh.set_surface_override_material(surface, tuned)


func _contains_any(value: String, tokens: Array[String]) -> bool:
	for token in tokens:
		if token in value:
			return true
	return false


func _should_have_furniture_collision(mesh: MeshInstance3D, bounds: AABB) -> bool:
	# Decorative meshes should remain visible but never become invisible obstacles.
	# This list intentionally covers the repeated source-model naming conventions.
	var mesh_name := str(mesh.name).to_lower()
	for token in [
		"wall", "floor", "ceiling", "skirting", "picture", "painting", "mirror",
		"blind", "light", "lamp", "socket", "cable", "wire", "handle", "leaves",
		"stem", "book", "apple", "candle", "dish", "magazine", "letter", "radio",
		"pot", "mushroom", "carrot", "tomato", "pepper", "knife", "plate", "glass",
		"towel", "rug", "carpet", "vase", "foam", "paper", "frame"
	]:
		if token in mesh_name:
			return false

	var horizontal_area := absf(bounds.size.x * bounds.size.z)
	var horizontal_span := maxf(bounds.size.x, bounds.size.z)
	if bounds.size.y < FURNITURE_COLLISION_MIN_HEIGHT:
		return false
	if horizontal_span < FURNITURE_COLLISION_MIN_SPAN:
		return false
	if horizontal_area < FURNITURE_COLLISION_MIN_FOOTPRINT:
		return false
	# Ceiling fixtures and tall wall details are not part of the walkable furniture.
	if bounds.position.y > 2.55:
		return false
	return true


func _add_furniture_box_collision(asset: Node3D, source_mesh: MeshInstance3D, bounds: AABB) -> void:
	var body := StaticBody3D.new()
	body.name = "FurnitureCollision_" + str(source_mesh.name)
	body.set_meta("furniture_collision", true)
	body.set_meta("source_mesh", str(source_mesh.name))
	body.collision_layer = 1
	body.collision_mask = 0
	# Use a world-space AABB so rotation and nested imported transforms cannot
	# accidentally inherit a decorative mesh's local transform.
	# The room asset is a direct child of the gameplay scene. Keeping the
	# collider there avoids inheriting the imported asset's scale/rotation.
	asset.get_parent().add_child(body)
	body.global_position = bounds.get_center()

	var shape_node := CollisionShape3D.new()
	shape_node.name = "FurnitureBoxShape"
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	shape_node.shape = shape
	body.add_child(shape_node)


func _add_contact_shadow(asset: Node3D, source_mesh: MeshInstance3D, bounds: AABB) -> void:
	# A small unlit card at the furniture footprint restores the contact cue
	# lost when the imported scene is rendered with one affordable shadow light.
	# It is visual-only: no collision shape is ever attached to this node.
	if asset.name not in ["LivingRoomRealAsset", "KitchenRealAsset", "BathroomRealAsset"]:
		return
	var mesh_name := str(source_mesh.name).to_lower()
	var hero_tokens := [
		"sofa", "cushion", "table", "carpet", "cupboard", "cabinet", "toilet",
		"bathtub", "bath", "vanity", "chair", "fridge", "cooker", "oven", "bed"
	]
	var is_hero := false
	for token in hero_tokens:
		if token in mesh_name:
			is_hero = true
			break
	if not is_hero or bounds.size.y < 0.18:
		return
	if contact_shadow_material == null:
		contact_shadow_material = _mat(Color(0.015, 0.018, 0.022, 0.20))
		contact_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		contact_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		contact_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow_" + str(source_mesh.name)
	shadow.set_meta("contact_shadow", true)
	var shadow_mesh := BoxMesh.new()
	shadow_mesh.size = Vector3(
		clampf(bounds.size.x * 0.90, 0.18, 3.2),
		0.008,
		clampf(bounds.size.z * 0.90, 0.18, 3.2)
	)
	shadow.mesh = shadow_mesh
	shadow.material_override = contact_shadow_material
	asset.get_parent().add_child(shadow)
	shadow.global_position = Vector3(bounds.get_center().x, 0.008, bounds.get_center().z)


func _align_wall_fixtures(asset: Node3D) -> void:
	# Move complete fixture assemblies, including handles and trim, before collision generation.
	for mesh in asset.find_children("*", "MeshInstance3D"):
		var id: int = str(mesh.name).get_slice("_", 0).to_int()
		if asset.name == "BathroomRealAsset":
			if id in [3, 4, 5, 17, 56, 57, 58, 59, 60, 61, 62, 840, 841, 842, 850]:
				mesh.global_position.x -= 2.15
			if id in [52, 53]:
				mesh.global_position.z -= 2.20
		elif asset.name == "LivingRoomRealAsset":
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			if bounds.get_center().x < -7.5 and bounds.size.x < 1.0 and not "Picture" in str(mesh.name):
				mesh.global_position.x -= 1.6
			if id >= 146 and id <= 157:
				mesh.global_position += Vector3(4.0, 0, 2.5)
		elif asset.name == "KitchenRealAsset":
			if (id >= 203 and id <= 218 and id != 206 and id != 207) or (id >= 265 and id <= 272) or id == 295 or id == 1:
				mesh.global_position.z += 0.55


func _remove_asset_shell(asset: Node) -> void:
	# Imported room shells do not share the playable floor plan.
	# Retain furniture, sockets and ceiling lamps; use our visible collidable walls.
	var shell_names := ["01_Walls", "121_Walls", "125_Walls", "122_Floor",
		"125_Floor", "126_Ceiling", "127_Walls", "263_Walls", "264_Walls",
		"845_Floor", "847_GreyWall", "848_Wallpaper", "849_Ceiling"]
	for child in asset.get_children():
		if str(child.name) in shell_names and child is Node3D:
			child.hide()
		else:
			_remove_asset_shell(child)


func _build_bathroom_procedural() -> void:
	# 磁磚與深色填縫先建立空間的真實比例，再放入衛浴細節。
	_add_tile_floor(Vector3(0.25, 0.02, -5.75), Vector2i(10, 6), 0.95, 0.02)
	_add_tile_wall(Vector3(0.25, 0.20, -5.84), Vector2i(10, 3), 0.95, Vector3(0, 0, 0))
	_add_tile_wall(Vector3(9.84, 0.20, -5.75), Vector2i(6, 3), 0.95, Vector3(0, PI / 2.0, 0))

	# 浴室櫃：櫃體、檯面、洗手盆、龍頭與鏡櫃分件，避免單一方塊感。
	_add_box("BathVanity", Vector3(2.1, 0.82, 0.72), Vector3(2.3, 0.44, -4.72), _mat(Color(0.34, 0.36, 0.38)), true)
	_add_box("VanityTop", Vector3(2.18, 0.10, 0.78), Vector3(2.3, 0.90, -4.72), _mat(Color(0.72, 0.73, 0.70)), true)
	_add_cylinder("WashBasin", 0.42, 0.12, Vector3(2.3, 0.98, -4.72), _mat(Color(0.80, 0.82, 0.80)), false)
	_add_cylinder("Faucet", 0.07, 0.48, Vector3(2.3, 1.22, -4.72), _mat(palette["metal"]), true)
	_add_box("BathroomMirror", Vector3(1.7, 1.25, 0.06), Vector3(2.3, 1.85, -5.16), _mat(Color(0.40, 0.58, 0.64)), true)
	_add_box("MirrorShelf", Vector3(1.75, 0.08, 0.20), Vector3(2.3, 1.12, -5.10), _mat(palette["metal"]), true)
	_add_box("TowelBar", Vector3(0.95, 0.08, 0.08), Vector3(3.7, 1.42, -5.76), _mat(palette["metal"]), true)
	_add_box("Towel", Vector3(0.75, 0.58, 0.05), Vector3(3.7, 1.10, -5.70), _mat(Color(0.72, 0.48, 0.35)), true)

	# 馬桶由底座、水箱與座圈組成。
	_add_cylinder("ToiletBase", 0.52, 0.62, Vector3(7.3, 0.31, -4.5), _mat(Color(0.76, 0.78, 0.76)), true)
	_add_box("ToiletTank", Vector3(0.82, 0.80, 0.36), Vector3(7.3, 0.98, -4.78), _mat(Color(0.76, 0.78, 0.76)), true)
	_add_cylinder("ToiletSeat", 0.40, 0.08, Vector3(7.3, 0.66, -4.5), _mat(Color(0.58, 0.60, 0.58)), true)

	# 淋浴區與玻璃隔間。
	_add_box("ShowerTray", Vector3(2.8, 0.10, 2.2), Vector3(7.6, 0.08, -2.25), _mat(Color(0.68, 0.70, 0.68)), true)
	_add_box("ShowerGlass", Vector3(0.07, 2.25, 2.5), Vector3(8.6, 1.15, -2.5), _glass_mat(Color(0.35, 0.62, 0.70), 0.12), true)
	_add_box("ShowerFrame_Left", Vector3(0.10, 2.35, 0.08), Vector3(8.55, 1.18, -3.76), _mat(palette["metal"]), false)
	_add_box("ShowerFrame_Right", Vector3(0.10, 2.35, 0.08), Vector3(8.55, 1.18, -1.24), _mat(palette["metal"]), false)
	_add_box("ShowerFrame_Top", Vector3(0.10, 0.08, 2.60), Vector3(8.55, 2.34, -2.5), _mat(palette["metal"]), false)
	_add_box("ShowerFrame_Bottom", Vector3(0.10, 0.08, 2.60), Vector3(8.55, 0.08, -2.5), _mat(palette["metal"]), false)
	_add_cylinder("ShowerPipe", 0.045, 1.30, Vector3(7.35, 2.05, -5.18), _mat(palette["metal"]), true)
	_add_cylinder("ShowerHead", 0.18, 0.10, Vector3(7.35, 2.68, -5.18), _mat(palette["metal"]), true)

	_add_box("BathDoor", Vector3(1.7, 2.5, 0.12), Vector3(8.8, 1.25, -0.9), _mat(palette["wood_light"]), true)
	_add_box("BathDoorTrim", Vector3(1.92, 2.72, 0.08), Vector3(8.8, 1.36, -0.84), _mat(Color(0.20, 0.12, 0.08)), false)
	_add_box("BathCeilingVent", Vector3(1.0, 0.22, 0.65), Vector3(3.1, 2.88, -2.1), _mat(palette["metal"]), true)
	_add_box("BathMat", Vector3(1.5, 0.04, 0.65), Vector3(2.3, 0.04, -3.55), _mat(Color(0.25, 0.33, 0.36)), true)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	# 從客廳入口開始，第一眼就能看到已匯入的高細節家具，而非灰色中庭。
	player.position = Vector3(-4.45, 1.0, 1.15)
	player.rotation.y = PI / 2.0
	add_child(player)

	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	collider.shape = capsule
	collider.position.y = 0.9
	player.add_child(collider)
	# A smaller margin prevents the capsule from being kept artificially far
	# away from coarse furniture boxes, while floor snap keeps contact stable.
	player.safe_margin = 0.025
	player.floor_snap_length = 0.18

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 1.55, 0)
	camera.current = true
	camera.fov = 72.0
	player.add_child(camera)

	raycast = RayCast3D.new()
	raycast.name = "InspectionRay"
	raycast.target_position = Vector3(0, 0, -3.8)
	raycast.collision_mask = 3
	raycast.enabled = true
	camera.add_child(raycast)

	var flashlight := SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.position = Vector3(0.22, -0.16, -0.42)
	flashlight.rotation_degrees = Vector3(-2, 0, 0)
	flashlight.spot_range = 7.0
	flashlight.spot_angle = 28.0
	flashlight.light_energy = 0.72
	flashlight.light_color = Color(1.0, 0.88, 0.62)
	flashlight.shadow_enabled = true
	camera.add_child(flashlight)
	_build_held_tools()


func _build_ui() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	var top_bar := ColorRect.new()
	top_bar.color = Color(0.025, 0.035, 0.06, 0.88)
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(1280, 76)
	hud.add_child(top_bar)

	objective_label = _make_label(hud, "", Vector2(28, 14), 24, Color(1, 0.86, 0.40))
	objective_label.size = Vector2(540, 36)
	timer_label = _make_label(hud, "", Vector2(1040, 14), 26, Color(1, 1, 1))
	timer_label.size = Vector2(210, 36)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	tool_label = _make_label(hud, "", Vector2(28, 640), 18, Color(0.78, 0.90, 1.0))
	tool_label.size = Vector2(700, 50)
	tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	prompt_label = _make_label(hud, "", Vector2(390, 560), 22, Color(1, 1, 1))
	prompt_label.size = Vector2(500, 44)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	toast_label = _make_label(hud, "", Vector2(250, 485), 21, Color(1, 0.84, 0.46))
	toast_label.size = Vector2(780, 58)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(28, 54)
	progress_bar.size = Vector2(480, 10)
	progress_bar.max_value = TARGET_ISSUES
	progress_bar.show_percentage = false
	hud.add_child(progress_bar)
	loading_label = _make_label(hud, "", Vector2(530, 50), 14, Color(0.70, 0.86, 1.0))
	loading_label.size = Vector2(700, 24)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var help := _make_label(hud, "點一下鎖定視角；若無法鎖定，按住左鍵拖曳查看  |  WASD 移動  |  E 檢查  |  1-4 工具  |  H 線索  |  ESC 暫停", Vector2(28, 690), 14, Color(0.60, 0.64, 0.72))
	help.size = Vector2(900, 25)

	report_panel = ColorRect.new()
	report_panel.color = Color(0.025, 0.035, 0.07, 0.96)
	report_panel.position = Vector2(270, 105)
	report_panel.size = Vector2(740, 490)
	report_panel.visible = false
	hud.add_child(report_panel)

	report_label = _make_label(report_panel, "", Vector2(34, 28), 22, Color(0.92, 0.95, 1.0))
	report_label.size = Vector2(672, 405)
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var crosshair := _make_label(hud, "+", Vector2(628, 344), 24, Color.WHITE)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_panel = ColorRect.new()
	pause_panel.color = Color(0.025, 0.035, 0.06, 0.96)
	pause_panel.position = Vector2(360, 130)
	pause_panel.size = Vector2(560, 440)
	pause_panel.visible = false
	hud.add_child(pause_panel)
	_make_label(pause_panel, "暫停驗屋", Vector2(36, 25), 30, Color.WHITE)
	_make_label(pause_panel, "WASD 移動 · 滑鼠查看\nE 檢查問題／開關門 · 1–4 換工具\n找出十個問題完成驗屋；門口請先開門。", Vector2(36, 85), 18, Color.WHITE)
	for entry in [["繼續驗屋", _set_paused.bind(false)], ["重新開始", _start_round], ["離開遊戲", get_tree().quit]]:
		var button := Button.new()
		button.text = entry[0]
		button.position = Vector2(36, 205 + pause_panel.get_child_count() * 45 - 135)
		button.size = Vector2(488, 40)
		button.pressed.connect(entry[1])
		pause_panel.add_child(button)


func _set_paused(value: bool) -> void:
	paused = value
	if pause_panel != null:
		pause_panel.visible = value
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED)


func _reset_player() -> void:
	player.position = Vector3(-2.0, 0.05, 1.0)
	player.rotation = Vector3(0, PI / 2.0, 0)
	player.velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO


func _build_held_tools() -> void:
	inspection_audio = AudioStreamPlayer.new()
	inspection_audio.volume_db = -18.0
	add_child(inspection_audio)
	for index in range(4):
		var tool := Node3D.new()
		tool.position = Vector3(0.32, -0.28, -0.65)
		camera.add_child(tool)
		held_tools.append(tool)
		var colors := [Color.DIM_GRAY, Color.GOLDENROD, Color.SADDLE_BROWN, Color.ORANGE_RED]
		_add_door_frame_piece(tool, "Grip", Vector3(0.045, 0.22, 0.045), Vector3.ZERO, _mat(colors[index]))
		match index:
			0:
				_add_door_frame_piece(tool, "Lens", Vector3(0.095, 0.08, 0.12), Vector3(0, 0.13, -0.02), _mat(Color.LIGHT_GRAY))
			1:
				_add_door_frame_piece(tool, "Level", Vector3(0.28, 0.065, 0.055), Vector3(0, 0.12, 0), _mat(Color.GOLDENROD))
				_add_door_frame_piece(tool, "Bubble", Vector3(0.06, 0.024, 0.059), Vector3(0, 0.12, 0), _mat(Color.GREEN_YELLOW))
			2:
				_add_door_frame_piece(tool, "HammerHead", Vector3(0.15, 0.075, 0.075), Vector3(0, 0.14, 0), _mat(Color.GRAY))
			3:
				_add_door_frame_piece(tool, "Probe", Vector3(0.015, 0.12, 0.015), Vector3(0, 0.15, 0), _mat(Color.SILVER))


func _start_round() -> void:
	if OS.has_feature("web"):
		paused = false
		pause_panel.hide()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_set_paused(false)
	_reset_player()
	for door_id in doors:
		doors[door_id]["is_open"] = false
		var pivot: Node3D = doors[door_id]["pivot"]
		pivot.rotation.y = float(doors[door_id]["closed_angle"])
	for body in issue_bodies.values():
		if is_instance_valid(body):
			body.queue_free()
	issue_bodies.clear()
	issue_meshes.clear()
	found_issues.clear()
	report_panel.visible = false
	round_finished = false
	time_left = ROUND_SECONDS
	current_tool = 0

	var all_issues := _get_issue_definitions()
	var by_room: Dictionary = {}
	for issue in all_issues:
		var room: String = issue["room"]
		if not by_room.has(room):
			by_room[room] = []
		by_room[room].append(issue)

	issue_records.clear()
	var rooms := ["客廳", "廚房", "臥室", "浴室"]
	for room in rooms:
		var pool: Array = by_room[room]
		pool.shuffle()
		for index in range(mini(2, pool.size())):
			issue_records.append(pool[index])

	var remaining: Array = all_issues.duplicate()
	remaining.shuffle()
	for issue in issue_records:
		remaining.erase(issue)
	while issue_records.size() < TARGET_ISSUES and not remaining.is_empty():
		issue_records.append(remaining.pop_back())

	for issue in issue_records:
		_add_issue_target(issue)

	_select_tool(0)
	_show_toast("驗屋開始！這間房子看起來很正常，這正是最可疑的地方。按 H 可取得區域線索。", 4.0)


func _get_issue_definitions() -> Array[Dictionary]:
	return [
		_issue("rug_tilt", "客廳地毯坡向牆角", "客廳", 1, 2, Vector3(-6.0, 0.05, 2.0), Vector3(2.6, 0.06, 1.4), "地毯正在替地板偷偷校正水平。"),
		_issue("tv_outlet", "電視插座沒有接地", "客廳", 3, 3, Vector3(-7.9, 1.25, 5.55), Vector3(0.55, 0.32, 0.12), "這個插座比電視節目還刺激。"),
		_issue("sofa_gap", "沙發後方封死檢修孔", "客廳", 0, 2, Vector3(-3.0, 1.05, 5.72), Vector3(1.25, 1.0, 0.10), "設計師把維修的未來一起封進牆裡。"),
		_issue("sink_leak", "水槽下方正在漏水", "廚房", 0, 3, Vector3(4.2, 0.86, 4.65), Vector3(0.9, 0.45, 0.65), "櫥櫃裡面有一個小型室內瀑布。"),
		_issue("vent_wrong", "抽油煙機排向櫃子", "廚房", 0, 2, Vector3(7.5, 2.4, 5.52), Vector3(1.4, 0.45, 0.25), "油煙沒有消失，只是搬進櫃子。"),
		_issue("kitchen_socket", "廚房插座位置過低", "廚房", 3, 2, Vector3(2.2, 0.9, 5.35), Vector3(0.55, 0.32, 0.10), "這個插座很適合讓延長線泡湯。"),
		_issue("cabinet_blocked", "冰箱門會撞到櫃子", "廚房", -1, 2, Vector3(8.8, 1.3, 3.5), Vector3(0.15, 1.8, 0.9), "冰箱不是打不開，只是需要先搬家。"),
		_issue("bed_slope", "床底地板明顯傾斜", "臥室", 1, 2, Vector3(-6.2, 1.08, -3.3), Vector3(3.0, 0.08, 2.2), "每天早上醒來，枕頭都已經先下床了。"),
		_issue("window_sealed", "逃生窗被裝潢封死", "臥室", -1, 3, Vector3(-7.7, 1.75, -5.62), Vector3(2.0, 1.1, 0.08), "這扇窗唯一能做的事，是讓你看見外面的自由。"),
		_issue("closet_deadend", "衣櫃門完全打不開", "臥室", -1, 1, Vector3(-1.9, 1.2, -4.42), Vector3(1.7, 1.75, 0.10), "衣服不是收納在裡面，是被判刑在裡面。"),
		_issue("drain_missing", "淋浴區沒有排水孔", "浴室", -1, 3, Vector3(4.8, 0.03, -2.8), Vector3(0.9, 0.04, 0.9), "這間浴室採用『水自己想辦法』的排水系統。"),
		_issue("tile_hollow", "牆磚大面積空鼓", "浴室", 2, 2, Vector3(7.3, 1.45, -5.75), Vector3(0.8, 1.0, 0.07), "這面牆裡面比屋主的承諾還空。"),
		_issue("bath_door", "浴室門會撞到洗手台", "浴室", -1, 2, Vector3(8.8, 1.25, -0.82), Vector3(1.3, 2.1, 0.08), "這扇門的設計理念是每天撞一次。"),
		_issue("bath_vent", "排風扇把濕氣吹回浴室", "浴室", 0, 2, Vector3(3.1, 2.72, -2.1), Vector3(0.9, 0.26, 0.55), "濕氣離開浴室三秒後，決定回來住。")
	]


func _issue(issue_id: String, title: String, room: String, required_tool: int, severity: int, pos: Vector3, size: Vector3, joke: String) -> Dictionary:
	# Keep fixtures on the revised walls, clear of the entrance and door swing.
	match issue_id:
		"tv_outlet":
			pos = Vector3(-9.72, 0.85, 2.6)
			size = Vector3(0.12, 0.35, 0.4)
		"sofa_gap":
			# The repair opening belongs on the wall immediately behind the sofa,
			# not on the unrelated side wall used by the old placeholder. Derive
			# both the horizontal placement and height from the actual sofa group.
			var sofa_bounds := _find_anchor_group_bounds(["63_SofaLeather", "65_SofaLeather", "134_SofaLeather", "136_SofaLeather", "137_SofaLeather", "138_SofaLeather", "139_SofaLeather"])
			var front_wall_bounds := _find_anchor_bounds("FrontWallLeft")
			if sofa_bounds.has_volume() and front_wall_bounds.has_volume():
				pos = Vector3(sofa_bounds.get_center().x, clampf(sofa_bounds.end.y + 0.42, 0.85, 1.35), front_wall_bounds.position.z - 0.035)
				size = Vector3(clampf(sofa_bounds.size.x * 0.52, 1.10, 1.60), 0.90, 0.10)
			else:
				pos = Vector3(-6.55, 1.05, 5.84)
				size = Vector3(1.45, 0.90, 0.10)
			title = "檢修孔被木條封死"
		"sink_leak":
			pos = Vector3(6.39, 0.43, 4.6)
			size = Vector3(0.18, 0.8, 0.6)
			title = "櫥櫃側管線漏水"
		"vent_wrong":
			pos = Vector3(6.58, 1.48, 3.65)
			size = Vector3(0.32, 0.35, 0.65)
		"cabinet_blocked":
			pos = Vector3(6.43, 0.40, 2.70)
			size = Vector3(0.16, 0.65, 0.3)
			title = "冰箱門會撞到櫃子"
			joke = "每次開門，都順便替門板磨一次皮。地產廣告沒說這是附贈功能。"
		"bed_slope":
			pos = Vector3(-4.6, 0.07, -3.3)
			size = Vector3(0.7, 0.14, 0.9)
		"rug_tilt":
			pos = Vector3(-5.65, 0.055, 2.45)
			size = Vector3(0.65, 0.1, 0.5)
		"drain_missing":
			title = "地排被填縫劑封住"
		"window_sealed":
			pos = Vector3(-4.0, 2.15, -5.62)
			size = Vector3(2.0, 0.6, 0.10)
		"kitchen_socket":
			pos = Vector3(3.15, 0.45, 5.83)
		"bath_vent":
			pos = Vector3(3.1, 2.5, -5.78)
		"bath_door":
			pos = Vector3(8.8, 1.25, -0.17)
			title = "浴室門框施工刮傷"
			joke = "門框的歲月痕跡，比房子的屋齡還長。"
			size = Vector3(0.35, 0.8, 0.12)
	# Resolve against imported furniture after scale/placement, not guessed room coordinates.
	var anchor_names := {
		"tv_outlet": "78_Socket",
		"sink_leak": "261_CupboardUnits",
		"vent_wrong": "255_ExtractorHood",
		"cabinet_blocked": "253_CupboardUnits",
		"kitchen_socket": "195_WallSocket",
		"bed_slope": "BedBase",
		"window_sealed": "WindowGlass",
		"rug_tilt": "141_Carpet",
		"drain_missing": "ImportedBath_DrainCover",
		"tile_hollow": "BackWall",
		"bath_vent": "ImportedBath_CeilingVent"
	}
	if anchor_names.has(issue_id):
		var bounds := _find_anchor_bounds(str(anchor_names[issue_id]))
		if bounds.size.length() > 0.0:
			pos = bounds.get_center()
			if issue_id == "rug_tilt":
				pos = Vector3(bounds.end.x - 0.25, bounds.end.y + 0.012, bounds.end.z - 0.20)
			elif issue_id == "tv_outlet":
				# The socket is a tiny source mesh; enlarge the inspection area
				# around its actual wall position without moving the visual clue.
				pos = bounds.get_center() + Vector3(0, 0.58, -0.12)
				size = Vector3(0.16, 0.35, 0.24)
			elif issue_id == "kitchen_socket":
				pos = bounds.get_center() + Vector3(-0.06, 0, 0)
				size = Vector3(0.16, 0.35, 0.24)
			elif issue_id == "bed_slope":
				pos = Vector3(bounds.end.x - 0.10, bounds.position.y + 0.02, bounds.get_center().z)
				size = Vector3(0.72, 0.14, 0.90)
			elif issue_id == "window_sealed":
				pos = bounds.get_center() + Vector3(0, 0.18, 0.04)
				size = Vector3(minf(2.0, bounds.size.x), 0.60, 0.10)
			elif issue_id == "drain_missing":
				pos = bounds.get_center() + Vector3(0, 0.018, 0)
				size = Vector3(0.48, 0.04, 0.48)
			elif issue_id == "tile_hollow":
				# BackWall is the room's actual wall plane; keep the clue on
				# its bathroom-side surface instead of floating in the room.
				pos = Vector3(7.3, 1.45, bounds.end.z + 0.035)
				size = Vector3(0.80, 1.0, 0.07)
			elif issue_id == "bath_vent":
				pos = bounds.get_center() + Vector3(0, 0.02, 0.02)
			else:
				pos.x = bounds.position.x - 0.035
				if issue_id == "sink_leak":
					pos.y = 0.38
	if issue_id == "bath_door":
		pos = get_node("RightInnerDoorFrame").to_global(Vector3(1.30, 1.25, -0.09))
		size = Vector3(0.16, 0.8, 0.16)
	if issue_id == "closet_deadend":
		var closet_door := get_node_or_null("ClosetDoorLeft") as Node3D
		if closet_door != null:
			pos = closet_door.position + Vector3(0.50, 0, 0.045)
	return {
		"id": issue_id,
		"title": title,
		"room": room,
		"tool": required_tool,
		"severity": severity,
		"pos": pos,
		"size": size,
		"joke": joke
	}


func _find_anchor_bounds(anchor_name: String) -> AABB:
	var anchor := find_child(anchor_name, true, false)
	if anchor is MeshInstance3D:
		var mesh_anchor := anchor as MeshInstance3D
		return mesh_anchor.global_transform * mesh_anchor.get_aabb()
	if anchor is Node3D:
		var child_mesh := anchor.find_child("Mesh", true, false) as MeshInstance3D
		if child_mesh != null:
			return child_mesh.global_transform * child_mesh.get_aabb()
	return AABB()


func _find_anchor_group_bounds(anchor_names: Array) -> AABB:
	var combined := AABB()
	var found := false
	for anchor_name in anchor_names:
		var candidate := _find_anchor_bounds(anchor_name)
		if not candidate.has_volume():
			continue
		combined = candidate if not found else combined.merge(candidate)
		found = true
	return combined if found else AABB()


func _add_issue_target(issue: Dictionary) -> void:
	# 問題標記保留辨識度，但不再像漂浮的霓虹色方塊破壞室內氣氛。
	var material_color := Color(0.38, 0.16, 0.09)
	if issue["tool"] == 0:
		material_color = Color(0.16, 0.34, 0.38)
	elif issue["tool"] == 1:
		material_color = Color(0.42, 0.33, 0.12)
	elif issue["tool"] == 2:
		material_color = Color(0.31, 0.18, 0.34)
	elif issue["tool"] == 3:
		material_color = Color(0.45, 0.14, 0.10)

	var body := _add_box("Issue_" + issue["id"], issue["size"], issue["pos"], _issue_mat(material_color), true)
	# Inspection overlays must never act as invisible furniture or block doorways.
	var room_loaded := bool(loaded_rooms.get(str(issue["room"]), false))
	body.collision_layer = 2 if room_loaded else 0
	body.collision_mask = 0
	body.visible = room_loaded
	body.set_meta("issue_id", issue["id"])
	body.set_meta("issue_title", issue["title"])
	body.set_meta("issue_room", issue["room"])
	body.set_meta("required_tool", issue["tool"])
	issue_bodies[issue["id"]] = body
	var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	mesh.hide()
	var visual := Node3D.new()
	visual.name = "DefectVisual"
	body.add_child(visual)
	if issue["id"] == "tv_outlet":
		visual.rotation.y = -PI / 2.0
	if issue["id"] == "bath_vent":
		visual.rotation.x = PI / 2.0
	if issue["id"] in ["sink_leak", "vent_wrong", "cabinet_blocked"]:
		visual.rotation.y = PI / 2.0
	preload("res://defect_visuals.gd").build(visual, str(issue["id"]))
	issue_meshes[issue["id"]] = mesh


func _refresh_room_issue_targets(room_name: String) -> void:
	# Imported furniture can move an issue anchor. Resolve selected targets again
	# after the room arrives, then enable only that room's inspection colliders.
	var refreshed_by_id := {}
	for issue in _get_issue_definitions():
		refreshed_by_id[str(issue["id"])] = issue
	for index in range(issue_records.size()):
		var selected: Dictionary = issue_records[index]
		if str(selected["room"]) != room_name or not refreshed_by_id.has(str(selected["id"])):
			continue
		var refreshed: Dictionary = refreshed_by_id[str(selected["id"])]
		selected["pos"] = refreshed["pos"]
		selected["size"] = refreshed["size"]
		issue_records[index] = selected
		var body := issue_bodies.get(str(selected["id"])) as StaticBody3D
		if body == null:
			continue
		body.position = refreshed["pos"]
		var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			(shape.shape as BoxShape3D).size = refreshed["size"]
		body.collision_layer = 0 if found_issues.has(str(selected["id"])) else 2
		body.visible = not found_issues.has(str(selected["id"]))


func _inspect_target() -> void:
	if round_finished:
		return
	var body := _get_hovered_body()
	if body == null:
		_show_toast("沒有瞄準任何東西。這面牆目前沒有申訴意願。", 2.0)
		return

	if body.has_meta("door_id"):
		_toggle_door(str(body.get_meta("door_id")))
		return
	_play_inspection_feedback()

	if not body.has_meta("issue_id"):
		if body.has_meta("inspect_text"):
			_show_toast(str(body.get_meta("inspect_text")), 2.0)
		else:
			_show_toast("看起來沒問題。先別急著把它拆掉。", 1.8)
		return

	var issue_id: String = str(body.get_meta("issue_id"))
	if found_issues.has(issue_id):
		_show_toast("這個問題已經記錄了，別對同一塊磁磚重複收費。", 2.0)
		return

	var required_tool: int = int(body.get_meta("required_tool"))
	if required_tool >= 0 and required_tool != current_tool:
		_show_toast("這個問題需要「%s」確認。現在拿的是「%s」。" % [tool_names[required_tool], tool_names[current_tool]], 2.5)
		return

	var issue := _find_issue(issue_id)
	if issue.is_empty():
		return

	found_issues[issue_id] = true
	var mesh: MeshInstance3D = issue_meshes[issue_id]
	if mesh != null:
		# 找到後移除大片偵測面，只留下報告文字；避免螢光方塊遮住室內模型。
		mesh.visible = false
	_add_found_label(body, "✓ " + issue["title"])
	var readings := ["照明檢查：發現異常施工痕跡", "水平檢查：超出本關卡容許範圍", "敲擊檢查：空腔回音", "驗電檢查：接線異常"]
	var reading: String = "目視確認：安裝異常" if required_tool < 0 else readings[required_tool]
	_show_toast("%s · %s\n%s" % [issue["title"], reading, issue["joke"]], 4.0)
	if found_issues.size() >= TARGET_ISSUES:
		_finish_round("全部問題都抓到了！")


func _find_issue(issue_id: String) -> Dictionary:
	for issue in issue_records:
		if issue["id"] == issue_id:
			return issue
	return {}


func _play_inspection_feedback() -> void:
	if held_tools.is_empty():
		return
	if tool_motion != null and tool_motion.is_valid():
		tool_motion.kill()
	for tool in held_tools:
		tool.rotation.x = 0
	var active: Node3D = held_tools[current_tool]
	tool_motion = create_tween()
	tool_motion.tween_property(active, "rotation:x", -0.4, 0.08)
	tool_motion.tween_property(active, "rotation:x", 0.0, 0.18)
	# Locally synthesized inspection sounds; no external audio license needed.
	var samples := PackedByteArray()
	var count := 6615
	samples.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / 22050.0
		var frequency: float = [480.0, 700.0, 165.0, 1100.0][current_tool]
		var envelope: float = exp(-t * (30.0 if current_tool == 2 else 14.0))
		var signal_value: float = sin(TAU * frequency * t) * envelope * 0.5
		if current_tool == 2:
			signal_value += sin(TAU * 437.0 * t) * envelope * 0.15
		samples.encode_s16(i * 2, int(signal_value * 32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	sound.data = samples
	inspection_audio.stream = sound
	if DisplayServer.get_name() != "headless":
		inspection_audio.play()


func _get_hovered_body() -> StaticBody3D:
	if raycast != null and raycast.is_colliding():
		return raycast.get_collider() as StaticBody3D
	return null


func _update_hover_prompt() -> void:
	if prompt_label == null or round_finished:
		return
	var body := _get_hovered_body()
	if body == null:
		prompt_label.text = ""
		return
	if body.has_meta("door_id"):
		var is_open: bool = _is_door_open(str(body.get_meta("door_id")))
		var action_text: String = "關門" if is_open else "開門"
		prompt_label.text = "[E / 左鍵] %s  ·  %s" % [action_text, str(body.get_meta("door_name"))]
	elif body.has_meta("issue_id"):
		var required_tool: int = int(body.get_meta("required_tool"))
		var tool_hint: String = "觀察即可" if required_tool < 0 else "需要：" + tool_names[required_tool]
		prompt_label.text = "[E / 左鍵] 檢查可疑處  ·  %s" % tool_hint
	else:
		prompt_label.text = "[E / 左鍵] 檢查"


func _update_hud() -> void:
	var found_count := found_issues.size()
	objective_label.text = "驗屋任務：找出 %d 個問題  [%d/%d]" % [TARGET_ISSUES, found_count, TARGET_ISSUES]
	timer_label.text = "剩餘 %02d:%02d" % [int(time_left) / 60, int(time_left) % 60]
	tool_label.text = "工具 %d/4：%s  —  %s\n[1] 手電筒  [2] 水平儀  [3] 空鼓槌  [4] 驗電筆" % [current_tool + 1, tool_names[current_tool], tool_descriptions[current_tool]]
	progress_bar.value = found_count
	if time_left < 30.0:
		timer_label.modulate = Color(1.0, 0.32, 0.25)
	else:
		timer_label.modulate = Color.WHITE


func _finish_round(reason: String) -> void:
	if round_finished:
		return
	round_finished = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var found_count := found_issues.size()
	var score := 0
	for issue in issue_records:
		if found_issues.has(issue["id"]):
			score += 100 + int(issue["severity"]) * 50
	var rating := "實習驗屋員"
	if found_count >= 5:
		rating = "民間抓漏王"
	if found_count >= 8:
		rating = "屋主剋星"
	if found_count >= 10:
		rating = "傳說級裝潢蟑螂"
	report_panel.visible = true
	report_label.text = "驗屋報告\n\n%s\n\n找到問題：%d / %d\n驗屋分數：%d\n評級：%s\n\n%s\n\n按 R 重新驗屋，或按 ESC 釋放滑鼠。" % [reason, found_count, TARGET_ISSUES, score, rating, _report_joke(found_count)]
	prompt_label.text = ""


func _report_joke(found_count: int) -> String:
	if found_count >= TARGET_ISSUES:
		return "建議：不要把這份報告交給建商看，他們可能會先把房子交給你。"
	if found_count >= 7:
		return "你抓到了大部分問題。剩下的問題現在正在抓你。"
	if found_count >= 4:
		return "這間房子還有救，但可能需要先找另一間房子住。"
	return "恭喜，你至少找到了幾個問題。其他問題正在牆裡開會。"


func _select_tool(index: int) -> void:
	current_tool = clampi(index, 0, tool_names.size() - 1)
	for tool_index in range(held_tools.size()):
		held_tools[tool_index].visible = tool_index == current_tool
	if camera != null:
		camera.get_node("Flashlight").visible = current_tool == 0
	if tool_label != null:
		_update_hud()


func _show_toast(message: String, duration: float) -> void:
	if toast_label == null:
		return
	toast_label.text = message
	toast_until = Time.get_ticks_msec() / 1000.0 + duration


func _show_hint() -> void:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for issue in issue_records:
		var issue_id := str(issue["id"])
		if found_issues.has(issue_id):
			continue
		var body := issue_bodies.get(issue_id) as StaticBody3D
		if body == null or not body.visible:
			continue
		var distance := player.global_position.distance_to(body.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = issue
	if nearest.is_empty():
		_show_toast("目前沒有可提示的問題。再檢查一次工具與已開啟的房間。", 3.0)
		return

	var issue_id := str(nearest["id"])
	var required_tool := int(nearest["tool"])
	var tool_hint: String = "目視確認即可" if required_tool < 0 else "建議使用：" + tool_names[required_tool]
	_show_toast("線索：%s\n%s" % [_issue_hint(issue_id), tool_hint], 5.0)
	if hint_world_label != null and is_instance_valid(hint_world_label):
		hint_world_label.queue_free()
	hint_world_label = Label3D.new()
	hint_world_label.text = "! 線索"
	hint_world_label.font = preload("res://assets/fonts/NotoSansCJKtc-Subset.otf")
	hint_world_label.font_size = 30
	hint_world_label.modulate = Color(1.0, 0.72, 0.18)
	hint_world_label.outline_size = 10
	hint_world_label.outline_modulate = Color(0.08, 0.04, 0.01)
	hint_world_label.no_depth_test = true
	hint_world_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint_world_label.position = (issue_bodies[issue_id] as Node3D).global_position + Vector3(0, 0.62, 0)
	add_child(hint_world_label)
	hint_until = Time.get_ticks_msec() / 1000.0 + 5.0


func _issue_hint(issue_id: String) -> String:
	var hints := {
		"rug_tilt": "客廳：查看地毯邊緣與地板接縫",
		"tv_outlet": "客廳：查看電視附近的牆面插座",
		"sofa_gap": "客廳：查看沙發後方靠牆的位置",
		"sink_leak": "廚房：查看水槽下方的櫥櫃側面",
		"vent_wrong": "廚房：查看抽油煙機與上方櫃體",
		"kitchen_socket": "廚房：查看檯面附近偏低的插座",
		"cabinet_blocked": "廚房：查看冰箱與櫃門相鄰的邊緣",
		"bed_slope": "臥室：查看床底附近的地板",
		"window_sealed": "臥室：查看床側的逃生窗",
		"closet_deadend": "臥室：查看衣櫃門板與門把",
		"drain_missing": "浴室：查看淋浴區地面中央",
		"tile_hollow": "浴室：查看後牆的大面積牆磚",
		"bath_door": "浴室：查看門框靠近洗手台的一側",
		"bath_vent": "浴室：查看天花板上的排風扇"
	}
	return str(hints.get(issue_id, "附近有一個可疑的施工細節"))


func _add_found_label(parent: Node3D, text_value: String) -> void:
	var label := Label3D.new()
	label.font = preload("res://assets/fonts/NotoSansCJKtc-Subset.otf")
	label.text = text_value
	label.position = Vector3(0, 0.55, 0)
	label.font_size = 32
	label.modulate = Color(0.35, 1.0, 0.48)
	label.outline_size = 8
	label.outline_modulate = Color(0.02, 0.05, 0.02)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)


func _add_room_sign(text_value: String, pos: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.font = preload("res://assets/fonts/NotoSansCJKtc-Subset.otf")
	label.text = text_value
	label.position = pos
	label.font_size = 30
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color(0.04, 0.04, 0.06)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)


func _add_hinged_door(door_id: String, hinge_pos: Vector3, width: float, closed_angle: float, swing_direction: float, display_name: String, color: Color) -> void:
	# 門扇與碰撞體都掛在同一個鉸鏈 Pivot 下，開門時視覺與阻擋範圍會同步旋轉。
	var pivot := Node3D.new()
	pivot.name = door_id + "Pivot"
	pivot.position = hinge_pos
	pivot.rotation.y = closed_angle
	add_child(pivot)

	var leaf := StaticBody3D.new()
	leaf.name = door_id
	leaf.position = Vector3(width * 0.5, 1.1, 0.0)
	leaf.set_meta("door_id", door_id)
	leaf.set_meta("door_name", display_name)
	pivot.add_child(leaf)

	var door_size := Vector3(width, 2.2, 0.12)
	var door_mesh := MeshInstance3D.new()
	door_mesh.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = door_size
	door_mesh.mesh = box_mesh
	door_mesh.material_override = _door_mat(color)
	leaf.add_child(door_mesh)

	# 可辨識的雙層嵌板，讓室內門即使在暗區也不會退化成一片灰色平面。
	var panel_color := color.lightened(0.26)
	_add_door_panel(leaf, "UpperInsetFront", width * 0.72, 0.72, Vector3(0.0, 1.48, -0.078), panel_color)
	_add_door_panel(leaf, "LowerInsetFront", width * 0.72, 0.52, Vector3(0.0, 0.55, -0.078), panel_color)
	_add_door_panel(leaf, "UpperInsetBack", width * 0.72, 0.72, Vector3(0.0, 1.48, 0.078), panel_color)
	_add_door_panel(leaf, "LowerInsetBack", width * 0.72, 0.52, Vector3(0.0, 0.55, 0.078), panel_color)

	var door_collision := CollisionShape3D.new()
	var door_shape := BoxShape3D.new()
	door_shape.size = door_size
	door_collision.shape = door_shape
	leaf.add_child(door_collision)

	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.045
	handle_mesh.bottom_radius = 0.045
	handle_mesh.height = 0.28
	handle.mesh = handle_mesh
	handle.material_override = _mat(Color(0.62, 0.48, 0.22))
	handle.position = Vector3(width * 0.30, 0.0, -0.11)
	handle.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	leaf.add_child(handle)

	# 門框必須是固定物件，不能跟著門扇 Pivot 一起旋轉。
	var frame := Node3D.new()
	frame.name = door_id + "Frame"
	frame.position = hinge_pos
	frame.rotation.y = closed_angle
	add_child(frame)

	# 門框只作視覺收邊，門洞本身保持暢通。
	var frame_color := _door_mat(color.lightened(0.48))
	_add_door_frame_piece(frame, "FrameLeft", Vector3(0.12, 2.45, 0.16), Vector3(0.0, 1.22, 0.0), frame_color)
	_add_door_frame_piece(frame, "FrameRight", Vector3(0.12, 2.45, 0.16), Vector3(width, 1.22, 0.0), frame_color)
	_add_door_frame_piece(frame, "FrameTop", Vector3(width + 0.12, 0.12, 0.16), Vector3(width * 0.5, 2.38, 0.0), frame_color)

	doors[door_id] = {
		"pivot": pivot,
		"width": width,
		"closed_angle": closed_angle,
		"open_delta": swing_direction * PI / 2.0,
		"is_open": false,
		"name": display_name
	}


func _add_door_frame_piece(parent: Node3D, node_name: String, size: Vector3, local_pos: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var minimum := minf(size.x, minf(size.y, size.z))
	# Door trim, desk legs and curtain pleats share this path. Preserve a plain
	# box for paper-thin trim, but give structural pieces a small manufactured
	# radius so close views do not expose razor-sharp procedural corners.
	mesh.mesh = bedroom_details_rounded(size, minf(0.025, minimum * 0.24)) if minimum >= 0.035 else _plain_box_mesh(size)
	mesh.material_override = material
	mesh.position = local_pos
	parent.add_child(mesh)


func bedroom_details_rounded(size: Vector3, radius: float) -> ArrayMesh:
	var base := BoxMesh.new()
	base.size = size
	base.subdivide_width = 8
	base.subdivide_height = 8
	base.subdivide_depth = 8
	var arrays := base.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var r := minf(radius, minf(size.x, minf(size.y, size.z)) * 0.45)
	var core := size * 0.5 - Vector3.ONE * r
	for index in range(vertices.size()):
		var vertex := vertices[index]
		var nearest := Vector3(clampf(vertex.x, -core.x, core.x), clampf(vertex.y, -core.y, core.y), clampf(vertex.z, -core.z, core.z))
		normals[index] = (vertex - nearest).normalized()
		vertices[index] = nearest + normals[index] * r
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var rounded_mesh := ArrayMesh.new()
	rounded_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return rounded_mesh


func _plain_box_mesh(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


func _add_door_panel(parent: Node3D, node_name: String, width: float, height: float, local_pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(width, height, 0.026)
	mesh.mesh = panel_mesh
	mesh.material_override = _door_mat(color)
	mesh.position = local_pos - Vector3(0, 1.1, 0)
	parent.add_child(mesh)


func _is_door_open(door_id: String) -> bool:
	if not doors.has(door_id):
		return false
	var door_data: Dictionary = doors[door_id]
	return bool(door_data["is_open"])


func _toggle_door(door_id: String) -> void:
	if not doors.has(door_id):
		return
	var door_data: Dictionary = doors[door_id]
	var is_open: bool = not bool(door_data["is_open"])
	if is_open:
		var hinge: Node3D = door_data["pivot"]
		var relative: Vector3 = Basis(Vector3.UP, -float(door_data["closed_angle"])) * (player.position - hinge.position)
		door_data["open_delta"] = (1.0 if relative.z >= 0 else -1.0) * PI / 2.0
	door_data["is_open"] = is_open
	doors[door_id] = door_data
	var state_text: String = "已開啟" if is_open else "已關上"
	_show_toast(str(door_data["name"]) + state_text + "。", 1.5)


func _animate_doors(delta: float) -> void:
	for door_id in doors:
		var door_data: Dictionary = doors[door_id]
		var pivot: Node3D = door_data["pivot"] as Node3D
		if pivot == null:
			continue
		var target_angle: float = float(door_data["closed_angle"])
		if bool(door_data["is_open"]):
			target_angle += float(door_data["open_delta"])
		var next_angle: float = lerp_angle(pivot.rotation.y, target_angle, minf(1.0, delta * 7.0))
		if player != null and absf(angle_difference(pivot.rotation.y, next_angle)) > 0.0001:
			var obstructed := false
			for sample in range(1, 9):
				var sample_angle: float = lerp_angle(pivot.rotation.y, next_angle, float(sample) / 8.0)
				var local_player: Vector3 = Basis(Vector3.UP, -sample_angle) * (player.global_position - pivot.global_position)
				if local_player.x > -0.35 and local_player.x < float(door_data["width"]) + 0.35 and absf(local_player.z) < 0.43:
					obstructed = true
					break
			if obstructed:
				continue
		pivot.rotation.y = next_angle


func _add_box(node_name: String, size: Vector3, pos: Vector3, material: Material, collision: bool, parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	(parent if parent != null else self).add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = material
	body.add_child(mesh)
	if collision:
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
	return body


func _add_collision_box(node_name: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	add_child(body)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _add_cylinder(node_name: String, radius: float, height: float, pos: Vector3, material: Material, collision: bool, parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	(parent if parent != null else self).add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	mesh.mesh = cylinder
	mesh.material_override = material
	body.add_child(mesh)
	if collision:
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		shape_node.shape = shape
		body.add_child(shape_node)
	return body


func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
	var material := _mat(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _glass_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var material := _mat(Color(color.r, color.g, color.b, alpha))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.12
	material.metallic = 0.05
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.emission_enabled = true
	material.emission = color.lightened(0.15)
	material.emission_energy_multiplier = 0.10
	return material


func _load_generated_material_textures() -> void:
	# 程序化臥室使用低解析度可重複貼圖；匯入家具仍保留各自的原始材質。
	generated_oak_texture = load("res://assets/materials/generated_oak_albedo.png") as Texture2D
	generated_fabric_texture = load("res://assets/materials/generated_fabric_albedo.png") as Texture2D
	generated_oak_roughness_texture = load("res://assets/materials/generated_oak_roughness.png") as Texture2D
	generated_fabric_roughness_texture = load("res://assets/materials/generated_fabric_roughness.png") as Texture2D
	generated_oak_normal_texture = _make_runtime_normal_texture(0.095, 3.0, 0.16)
	generated_fabric_normal_texture = _make_runtime_normal_texture(0.18, 5.5, 0.12)


func _make_runtime_normal_texture(frequency: float, detail: float, strength: float) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55
	noise.fractal_lacunarity = detail
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	texture.as_normal_map = true
	texture.bump_strength = strength
	return texture


func _wood_mat(color: Color) -> StandardMaterial3D:
	var material := _mat(color)
	if generated_oak_texture != null:
		material.albedo_texture = generated_oak_texture
	if generated_oak_roughness_texture != null:
		material.roughness_texture = generated_oak_roughness_texture
	if generated_oak_normal_texture != null:
		material.normal_enabled = true
		material.normal_texture = generated_oak_normal_texture
		material.normal_scale = 0.18
	material.roughness = 0.58
	return material


func _fabric_mat(color: Color) -> StandardMaterial3D:
	var material := _mat(color)
	if generated_fabric_texture != null:
		material.albedo_texture = generated_fabric_texture
	if generated_fabric_roughness_texture != null:
		material.roughness_texture = generated_fabric_roughness_texture
	if generated_fabric_normal_texture != null:
		material.normal_enabled = true
		material.normal_texture = generated_fabric_normal_texture
		material.normal_scale = 0.12
	material.roughness = 0.88
	return material


func _door_mat(color: Color) -> StandardMaterial3D:
	# 門片是室內辨識物，保留少量自發光以免低照度下被壓成灰黑色。
	var material := _mat(color)
	material.roughness = 0.42
	material.emission_enabled = true
	material.emission = color.darkened(0.70)
	return material


func _issue_mat(color: Color) -> StandardMaterial3D:
	# 施工問題在未檢查前是低透明度覆層；它是提示，不是另一件家具。
	var material := _mat(Color(color.r, color.g, color.b, 0.34))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	return material


func _make_label(parent: Node, text_value: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _add_tile_floor(origin: Vector3, grid_size: Vector2i, tile_size: float, gap: float) -> void:
	var tile_material_a := _mat(Color(0.34, 0.38, 0.40))
	var tile_material_b := _mat(Color(0.30, 0.34, 0.37))
	var step := tile_size + gap
	for x in range(grid_size.x):
		for z in range(grid_size.y):
			var tile_pos := origin + Vector3(x * step, 0.0, z * step)
			var material: Material = tile_material_a if (x + z) % 2 == 0 else tile_material_b
			_add_box("BathroomFloorTile_%d_%d" % [x, z], Vector3(tile_size, 0.035, tile_size), tile_pos, material, false)


func _add_tile_wall(origin: Vector3, grid_size: Vector2i, tile_size: float, rotation: Vector3) -> void:
	var tile_material_a := _mat(Color(0.56, 0.65, 0.67))
	var tile_material_b := _mat(Color(0.50, 0.60, 0.63))
	var step := tile_size + 0.02
	var side_wall := absf(rotation.y) > 0.1
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var tile_pos: Vector3
			var tile_size_3d: Vector3
			if side_wall:
				tile_pos = origin + Vector3(0.0, y * step, x * step)
				tile_size_3d = Vector3(0.035, tile_size, tile_size)
			else:
				tile_pos = origin + Vector3(x * step, y * step, 0.0)
				tile_size_3d = Vector3(tile_size, tile_size, 0.035)
			var material: Material = tile_material_a if (x + y) % 2 == 0 else tile_material_b
			_add_box("BathroomWallTile_%d_%d_%s" % [x, y, "side" if side_wall else "back"], tile_size_3d, tile_pos, material, false)


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_backward", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("interact", KEY_E)
	_add_key_action("toggle_mouse", KEY_ESCAPE)
	_add_key_action("restart", KEY_R)
	_add_key_action("tool_1", KEY_1)
	_add_key_action("tool_2", KEY_2)
	_add_key_action("tool_3", KEY_3)
	_add_key_action("tool_4", KEY_4)
	_add_key_action("hint", KEY_H)
	if not InputMap.has_action("use_tool"):
		InputMap.add_action("use_tool")
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("use_tool", mouse_event)


func _add_key_action(action_name: String, key: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var event := InputEventKey.new()
	event.keycode = key
	InputMap.action_add_event(action_name, event)
