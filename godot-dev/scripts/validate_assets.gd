extends SceneTree

const Core := preload("contract_core.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := Core.parse_args(OS.get_cmdline_user_args())
	if not args.has("file"):
		_fail("至少提供一个 --file <res://path>。")
		return
	var files := _argument_values(args["file"])
	var findings := PackedStringArray()
	for path in files:
		await _validate_path(path, findings)
	findings.sort()
	for finding in findings:
		printerr("GODOT_DEV_ASSET %s" % finding)
	if findings.is_empty():
		print("资产校验通过：%d 个文件。" % files.size())
		quit(0)
	else:
		printerr("资产校验失败：%d 项。" % findings.size())
		quit(1)


func _validate_path(path: String, findings: PackedStringArray) -> void:
	if not path.begins_with("res://") and not path.begins_with("user://"):
		findings.append("ResourceLoader 路径必须是 res:// 或 user://：%s" % path)
		return
	var extension := path.get_extension().to_lower()
	if extension == "gd":
		var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Script
		if script == null:
			findings.append("脚本无法加载：%s" % path)
		return
	if not ["tres", "res", "tscn", "scn"].has(extension):
		var imported := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if imported == null:
			findings.append("导入资产或 Shader 无法加载；请先运行编辑器扫描：%s" % path)
		return
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource == null:
		findings.append("资源无法加载：%s" % path)
		return
	if extension == "tscn" or extension == "scn":
		var packed := resource as PackedScene
		if packed == null or not packed.can_instantiate():
			findings.append("场景无法实例化：%s" % path)
			return
		var instance := packed.instantiate()
		if instance == null:
			findings.append("场景实例为空：%s" % path)
			return
		root.add_child(instance)
		await process_frame
		await process_frame
		root.remove_child(instance)
		instance.free()
		return
	if extension == "tres":
		var roundtrip_path := "user://godot-dev/roundtrip/%s" % path.get_file()
		var directory_error := Core.ensure_parent_directory(roundtrip_path)
		if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
			findings.append("无法创建往返目录 %s：%s" % [path, error_string(directory_error)])
			return
		var save_error := ResourceSaver.save(resource, roundtrip_path)
		if save_error != OK:
			findings.append("资源往返保存失败 %s：%s" % [path, error_string(save_error)])
			return
		if resource is AnimationNodeBlendSpace2D and not _normalize_blend_space_2d_triangle_order(roundtrip_path):
			findings.append("BlendSpace2D 往返文本无法把 triangles 规范到 blend_point_* 之后：%s" % path)
			return
		var reloaded := ResourceLoader.load(roundtrip_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if reloaded == null or reloaded.get_class() != resource.get_class():
			findings.append("资源往返加载类型不一致：%s" % path)


func _normalize_blend_space_2d_triangle_order(path: String) -> bool:
	var content := Core.read_text(path)
	if content.is_empty() or not content.contains("triangles = "):
		return true
	var triangle_line := ""
	var normalized := PackedStringArray()
	for line in content.split("\n"):
		if line.begins_with("triangles = "):
			triangle_line = line
		else:
			normalized.append(line)
	if triangle_line.is_empty():
		return true
	while not normalized.is_empty() and normalized[normalized.size() - 1].is_empty():
		normalized.remove_at(normalized.size() - 1)
	normalized.append(triangle_line)
	normalized.append("")
	var file := FileAccess.open(Core.globalize(path), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\n".join(normalized))
	file.close()
	return true


func _argument_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	else:
		result.append(String(value))
	return result


func _fail(message: String) -> void:
	printerr("GODOT_DEV_ASSET %s" % message)
	quit(1)
