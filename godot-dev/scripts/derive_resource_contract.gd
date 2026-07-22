extends SceneTree

const Core := preload("contract_core.gd")


func _init() -> void:
	var version_error := Core.require_engine_47()
	if not version_error.is_empty():
		_fail(version_error)
		return
	var args := Core.parse_args(OS.get_cmdline_user_args())
	for required in ["type", "scope", "output"]:
		if not args.has(required):
			_fail("缺少 --%s。" % required)
			return
	var type_name := String(args["type"])
	var source_path := String(args.get("source", ""))
	var scope := String(args["scope"])
	if not ["builtin", "third-party", "project"].has(scope):
		_fail("--scope 必须是 builtin、third-party 或 project。")
		return
	if scope == "third-party" and (not args.has("package-id") or not args.has("package-version")):
		_fail("第三方契约必须提供 --package-id 和 --package-version。")
		return

	var instance: Variant = _create_instance(type_name, source_path)
	if instance == null or not instance is Resource:
		_fail("无法创建 Resource 类型 %s。" % type_name)
		return
	var sample_path := "user://godot-dev/experiments/%s.tres" % type_name.to_snake_case()
	var directory_error := Core.ensure_parent_directory(sample_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("无法创建实验目录：%s" % error_string(directory_error))
		return
	var save_error := ResourceSaver.save(instance, sample_path)
	var reloaded: Resource = null
	if save_error == OK:
		reloaded = ResourceLoader.load(sample_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var save_reload_ok := save_error == OK and reloaded != null and reloaded.is_class(instance.get_class())
	var contract := {
		"contract_version": Core.CONTRACT_VERSION,
		"contract_id": _contract_id(scope, type_name, args),
		"kind": "resource",
		"type_name": type_name,
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"scope": scope,
		"source_path": source_path,
		"source_hash": Core.source_hash(source_path),
		"inheritance_chain": _object_inheritance(instance, type_name),
		"base_contract_hashes": {},
		"context_requirements": [],
		"authoring_mode": "generated_structure" if save_reload_ok else "resource_saver_only",
		"properties": Core.property_entries_from_object(instance),
		"serialization": {
			"format": "tres",
			"minimal_text": Core.read_text(sample_path) if save_reload_ok else "",
			"property_text_examples": {},
			"notes": ["这是 Godot 保存的最小样本；代表值属性必须按固定推导流程补充文本示例。"],
		},
		"constraints": ["只保存 PROPERTY_USAGE_STORAGE 属性。", "direct_text 需要独立手写样本验证后才能启用。"],
		"evidence": {
			"official_docs": ["https://docs.godotengine.org/en/4.7/classes/class_%s.html" % instance.get_class().to_lower()],
			"official_source": [source_path] if not source_path.is_empty() else [],
			"reflection": ["Object.get_property_list %s" % Core.engine_version()],
			"experiments": [sample_path] if save_reload_ok else [],
		},
		"validation": {
			"save_reload": save_reload_ok,
			"independent_text": false,
			"notes": [] if save_reload_ok else ["ResourceSaver 或重新加载失败：%s" % error_string(save_error)],
		},
		"status": "cataloged",
	}
	if scope == "third-party":
		contract["package_id"] = String(args["package-id"])
		contract["package_version"] = String(args["package-version"])
	Core.finalize_contract(contract)
	var output_path := String(args["output"])
	var write_error := Core.write_contract(output_path, contract)
	if write_error != OK:
		_fail("写入契约失败：%s" % error_string(write_error))
		return
	var manifest_path := String(args.get("manifest", "res://docs/godot-dev/manifest.json"))
	var manifest_error := Core.update_manifest(manifest_path, contract, output_path)
	if manifest_error != OK:
		_fail("更新清单失败：%s" % error_string(manifest_error))
		return
	print("已推导 Resource 契约：%s" % output_path)
	quit(0)


func _create_instance(type_name: String, source_path: String) -> Variant:
	if not source_path.is_empty():
		var script := load(source_path) as Script
		if script == null or not script.can_instantiate():
			return null
		return script.new()
	if not ClassDB.class_exists(type_name) or not ClassDB.can_instantiate(type_name):
		return null
	return ClassDB.instantiate(type_name)


func _object_inheritance(object: Object, type_name: String) -> Array[String]:
	var result: Array[String] = [type_name]
	var script := object.get_script() as Script
	if script != null and not String(script.get_global_name()).is_empty():
		var global_name := String(script.get_global_name())
		if not result.has(global_name):
			result.append(global_name)
	for parent_name in Core.inheritance_chain(object.get_class()):
		if not result.has(parent_name):
			result.append(parent_name)
	return result


func _contract_id(scope: String, type_name: String, args: Dictionary) -> String:
	if scope == "third-party":
		return "third-party:%s@%s:resource:%s" % [args["package-id"], args["package-version"], type_name]
	return "%s:resource:%s" % [scope, type_name]


func _fail(message: String) -> void:
	printerr("GODOT_DEV_RESOURCE %s" % message)
	quit(1)
