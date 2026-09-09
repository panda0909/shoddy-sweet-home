extends SceneTree

## Applies the Web texture profile after Godot has created the .import files.
## The source PNGs remain lossless; Basis Universal is generated only in the
## Godot import cache and is therefore safe to use for the Web export.
const MODEL_ROOTS := [
	"res://assets/models/living_room",
	"res://assets/models/kitchen",
	"res://assets/models/bathroom",
]

func _init() -> void:
	var changed := 0
	for root in MODEL_ROOTS:
		changed += _configure_directory(root)
	print("Configured Basis Universal Web texture imports: %d" % changed)
	quit()

func _configure_directory(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Unable to open texture directory: " + path)
		return 0

	var changed := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		var file_path := path.path_join(file_name)
		if dir.current_is_dir():
			changed += _configure_directory(file_path)
		elif file_name.ends_with(".png.import"):
			changed += _configure_import(file_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return changed

func _configure_import(path: String) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		push_error("Unable to read import config: " + path)
		return 0
	if config.get_value("remap", "importer", "") != "texture":
		return 0

	# Godot 4.7's mode 4 is Basis Universal. It is transcoded to a GPU
	# compressed format at load time and is the smallest 3D texture mode.
	config.set_value("params", "compress/mode", 4)
	config.set_value("params", "compress/uastc_level", 0)
	config.set_value("params", "compress/rdo_quality_loss", 0.5)
	config.set_value("params", "mipmaps/generate", true)
	config.set_value("params", "detect_3d/compress_to", 2)
	if config.save(path) != OK:
		push_error("Unable to write import config: " + path)
		return 0
	return 1
