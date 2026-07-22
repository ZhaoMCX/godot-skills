extends SceneTree

const Core := preload("contract_core.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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

	var node := _create_node(type_name, source_path)
	if node == null:
		_fail("无法创建 Node 类型 %s。" % type_name)
		return
	if node.name.is_empty():
		node.name = type_name
	var official_doc_type := type_name if source_path.is_empty() else String(node.get_class())
	var packed := PackedScene.new()
	var pack_error := packed.pack(node)
	var sample_path := "user://godot-dev/experiments/%s.tscn" % type_name.to_snake_case()
	var directory_error := Core.ensure_parent_directory(sample_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		node.free()
		_fail("无法创建实验目录：%s" % error_string(directory_error))
		return
	var save_error := ERR_CANT_CREATE
	if pack_error == OK:
		save_error = ResourceSaver.save(packed, sample_path)
	node.free()

	var loaded := ResourceLoader.load(sample_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene if save_error == OK else null
	var instantiated: Node = loaded.instantiate() if loaded != null and loaded.can_instantiate() else null
	var save_reload_ok := instantiated != null
	var properties := []
	var signals := []
	var inheritance: Array[String] = []
	if instantiated != null:
		properties = Core.property_entries_from_object(instantiated)
		signals = Core.signal_entries_from_object(instantiated)
		inheritance = _object_inheritance(instantiated, type_name)
		root.add_child(instantiated)
		await process_frame
		await process_frame
		root.remove_child(instantiated)
		instantiated.free()
	else:
		inheritance = Core.inheritance_chain(type_name)

	var contract := {
		"contract_version": Core.CONTRACT_VERSION,
		"contract_id": _contract_id(scope, type_name, args),
		"kind": "node",
		"type_name": type_name,
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"scope": scope,
		"source_path": source_path,
		"source_hash": Core.source_hash(source_path),
		"inheritance_chain": inheritance,
		"base_contract_hashes": {},
		"context_requirements": [],
		"authoring_mode": "generated_structure" if save_reload_ok else "reference_only",
		"properties": properties,
		"serialization": {
			"format": "tscn-node",
			"minimal_text": Core.read_text(sample_path) if save_reload_ok else "",
			"property_text_examples": {},
			"notes": ["这是单节点最小 PackedScene 样本，不是业务 Scene 契约。"],
		},
		"signals": signals,
		"path_constraints": Core.path_constraints_from_properties(properties),
		"child_constraints": ["具体子节点要求需由文档、源码或代表性场景实验补充。"],
		"lifecycle_constraints": ["节点加入 SceneTree 两帧后验证；工具脚本和外部服务依赖需单独记录。"],
		"evidence": {
			"official_docs": ["https://docs.godotengine.org/en/4.7/classes/class_%s.html" % official_doc_type.to_lower()],
			"official_source": [source_path] if not source_path.is_empty() else [],
			"reflection": ["Object.get_property_list/Object.get_signal_list %s" % Core.engine_version()],
			"experiments": [sample_path] if save_reload_ok else [],
		},
		"validation": {
			"save_reload": save_reload_ok,
			"independent_text": false,
			"notes": [] if save_reload_ok else ["PackedScene pack/save/reload 失败。"],
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
	print("已推导 Node 契约：%s" % output_path)
	quit(0)


func _create_node(type_name: String, source_path: String) -> Node:
	if not source_path.is_empty():
		var script := load(source_path) as Script
		if script == null or not script.can_instantiate():
			return null
		return script.new() as Node
	if not ClassDB.class_exists(type_name) or not ClassDB.can_instantiate(type_name):
		return null
	return ClassDB.instantiate(type_name) as Node


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
		return "third-party:%s@%s:node:%s" % [args["package-id"], args["package-version"], type_name]
	return "%s:node:%s" % [scope, type_name]


func _fail(message: String) -> void:
	printerr("GODOT_DEV_NODE %s" % message)
	quit(1)
