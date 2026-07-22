extends SceneTree

const Core := preload("contract_core.gd")


func _init() -> void:
	var version_error := Core.require_engine_47()
	if not version_error.is_empty():
		_fail(version_error)
		return

	var args := Core.parse_args(OS.get_cmdline_user_args())
	if not args.has("output"):
		_fail("缺少 --output <references/contracts/godot-4.7>。")
		return
	var output_root := String(args["output"])
	var manifest_entries := []
	var class_names := ClassDB.get_class_list()
	class_names.sort()
	for type_name in class_names:
		var api_type := ClassDB.class_get_api_type(type_name)
		if api_type != ClassDB.API_CORE and api_type != ClassDB.API_EDITOR:
			continue
		var kind := ""
		if ClassDB.is_parent_class(type_name, &"Resource"):
			kind = "resource"
		elif ClassDB.is_parent_class(type_name, &"Node"):
			kind = "node"
		else:
			continue
		var contract := Core.builtin_contract(type_name, kind)
		var directory_name := "resources" if kind == "resource" else "nodes"
		var suffix := "resource-contract.json" if kind == "resource" else "node-contract.json"
		var file_name := "%s.%s" % [String(type_name).to_snake_case(), suffix]
		var contract_path := output_root.path_join(directory_name).path_join(file_name)
		var write_error := Core.write_contract(contract_path, contract)
		if write_error != OK:
			_fail("写入失败 %s：%s" % [contract_path, error_string(write_error)])
			return
		manifest_entries.append(Core.manifest_entry(contract, contract_path))

	manifest_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["contract_id"] < b["contract_id"])
	var manifest := {
		"contract_version": Core.CONTRACT_VERSION,
		"contracts": manifest_entries,
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"scope": "builtin",
	}
	var manifest_error := Core.write_json(output_root.path_join("manifest.json"), manifest)
	if manifest_error != OK:
		_fail("写入 manifest.json 失败：%s" % error_string(manifest_error))
		return
	print("生成 %d 个 Godot %s 内置契约。" % [manifest_entries.size(), Core.engine_version()])
	quit(0)


func _fail(message: String) -> void:
	printerr("GODOT_DEV_CATALOG %s" % message)
	quit(1)
