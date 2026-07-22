extends SceneTree

const Core := preload("contract_core.gd")
const SchemaValidator := preload("schema_validator.gd")
const COMMON_FIELDS := [
	"contract_version",
	"contract_id",
	"kind",
	"type_name",
	"engine_version",
	"engine_build_hash",
	"scope",
	"source_path",
	"source_hash",
	"inheritance_chain",
	"base_contract_hashes",
	"context_requirements",
	"authoring_mode",
	"properties",
	"serialization",
	"evidence",
	"validation",
	"status",
	"contract_hash",
]


func _init() -> void:
	var args := Core.parse_args(OS.get_cmdline_user_args())
	var require_complete := bool(args.get("require-complete", false))
	var received_input := args.has("contract") or args.has("manifest")
	var paths: Array[String] = []
	var manifest_entries := {}
	var manifest_contract_ids := {}
	if args.has("contract"):
		paths.append_array(_argument_values(args["contract"]))
	if args.has("manifest"):
		for manifest_path in _argument_values(args["manifest"]):
			var manifest_value: Variant = Core.read_json(manifest_path)
			if not manifest_value is Dictionary:
				_fail("无法读取清单 %s。" % manifest_path)
				return
			if int(manifest_value.get("contract_version", 0)) != Core.CONTRACT_VERSION:
				_fail("清单 contract_version 不受支持：%s。" % manifest_path)
				return
			if String(manifest_value.get("engine_version", "")) != Core.engine_version() or String(manifest_value.get("engine_build_hash", "")) != Core.engine_build_hash():
				_fail("清单引擎身份与当前 Godot 不一致：%s。" % manifest_path)
				return
			for entry in manifest_value.get("contracts", []):
				if not entry is Dictionary or not entry.has("path"):
					_fail("清单 %s 包含无效条目。" % manifest_path)
					return
				var entry_path := _resolve_entry_path(manifest_path, String(entry["path"]), entry)
				var contract_id := String(entry.get("contract_id", ""))
				if manifest_entries.has(entry_path):
					_fail("清单 %s 包含重复路径：%s。" % [manifest_path, entry_path])
					return
				if manifest_contract_ids.has(contract_id):
					_fail("清单 %s 包含重复 contract_id：%s。" % [manifest_path, contract_id])
					return
				paths.append(entry_path)
				manifest_entries[entry_path] = entry
				manifest_contract_ids[contract_id] = entry
	if paths.is_empty() and not received_input:
		_fail("需要 --contract <path> 或 --manifest <path>。")
		return

	var findings := PackedStringArray()
	for path in paths:
		_validate_one(path, findings, require_complete)
		if manifest_entries.has(path):
			_validate_manifest_entry(path, manifest_entries[path], findings)
			_validate_base_hashes(path, manifest_contract_ids, findings)
	findings.sort()
	for finding in findings:
		printerr("GODOT_DEV_CONTRACT %s" % finding)
	if findings.is_empty():
		print("契约校验通过：%d 个文件。" % paths.size())
		quit(0)
	else:
		printerr("契约校验失败：%d 项。" % findings.size())
		quit(1)


func _validate_one(path: String, findings: PackedStringArray, require_complete: bool) -> void:
	var value: Variant = Core.read_json(path)
	if not value is Dictionary:
		findings.append("无法解析 JSON：%s" % path)
		return
	var contract: Dictionary = value
	var schema_file := "resource-contract.schema.json" if contract.get("kind", "") == "resource" else "node-contract.schema.json"
	var script_path: String = get_script().resource_path
	var schema_path: String = script_path.get_base_dir().path_join("../references").path_join(schema_file).simplify_path()
	for schema_finding in SchemaValidator.validate(contract, schema_path):
		findings.append("Schema %s：%s" % [path, schema_finding])
	for field in COMMON_FIELDS:
		if not contract.has(field):
			findings.append("缺少字段 %s：%s" % [field, path])
	var kind := String(contract.get("kind", ""))
	if kind == "resource":
		for field in ["constraints"]:
			if not contract.has(field):
				findings.append("Resource 契约缺少 %s：%s" % [field, path])
	elif kind == "node":
		for field in ["signals", "path_constraints", "child_constraints", "lifecycle_constraints"]:
			if not contract.has(field):
				findings.append("Node 契约缺少 %s：%s" % [field, path])
	else:
		findings.append("未知 kind %s：%s" % [kind, path])
	if int(contract.get("contract_version", 0)) != Core.CONTRACT_VERSION:
		findings.append("不支持的 contract_version：%s" % path)
	if String(contract.get("engine_version", "")) != Core.engine_version():
		findings.append("engine_version 与当前 Godot 不一致：%s（记录 %s，当前 %s）" % [path, contract.get("engine_version", ""), Core.engine_version()])
	if String(contract.get("engine_build_hash", "")) != Core.engine_build_hash():
		findings.append("engine_build_hash 与当前 Godot 不一致：%s（记录 %s，当前 %s）" % [path, contract.get("engine_build_hash", ""), Core.engine_build_hash()])
	if not Core.AUTHORING_MODES.has(contract.get("authoring_mode", "")):
		findings.append("无效 authoring_mode：%s" % path)
	if not Core.STATUSES.has(contract.get("status", "")):
		findings.append("无效 status：%s" % path)
	var actual_contract_hash := Core.contract_hash(contract)
	if String(contract.get("contract_hash", "")) != actual_contract_hash:
		findings.append("contract_hash 不匹配：%s（记录 %s，实际 %s）" % [path, contract.get("contract_hash", ""), actual_contract_hash])
	var validation: Dictionary = contract.get("validation", {})
	var serialization: Dictionary = contract.get("serialization", {})
	if not ["tres", "tscn-node"].has(serialization.get("format", "")):
		findings.append("serialization.format 无效：%s" % path)
	if contract.get("authoring_mode", "") == "direct_text":
		if contract.get("status", "") != "validated" or not validation.get("save_reload", false) or not validation.get("independent_text", false):
			findings.append("direct_text 必须经过独立文本验证：%s" % path)
		if String(serialization.get("minimal_text", "")).is_empty():
			findings.append("direct_text 缺少最小文本样本：%s" % path)
	if contract.get("status", "") == "validated" and ["generated_structure", "resource_saver_only"].has(contract.get("authoring_mode", "")) and not validation.get("save_reload", false):
		findings.append("已验证的生成模式必须通过保存重载：%s" % path)
	if contract.get("status", "") == "reference_only" and contract.get("authoring_mode", "") != "reference_only":
		findings.append("reference_only 状态必须使用 reference_only 编写模式：%s" % path)
	if require_complete and ["cataloged", "stale"].has(contract.get("status", "")):
		findings.append("完整验证不允许 %s 状态：%s" % [contract.get("status", ""), path])
	var source_path := String(contract.get("source_path", ""))
	if not source_path.is_empty():
		var actual_hash := Core.source_hash(source_path)
		if actual_hash.is_empty():
			findings.append("契约源码不存在：%s -> %s" % [path, source_path])
		elif actual_hash != String(contract.get("source_hash", "")):
			findings.append("契约源码已变化：%s -> %s" % [path, source_path])
	if contract.get("scope", "") == "third-party":
		if String(contract.get("package_id", "")).is_empty() or String(contract.get("package_version", "")).is_empty():
			findings.append("第三方契约缺少包标识或版本：%s" % path)


func _validate_manifest_entry(path: String, entry: Dictionary, findings: PackedStringArray) -> void:
	var contract_value: Variant = Core.read_json(path)
	if not contract_value is Dictionary:
		return
	var contract: Dictionary = contract_value
	for field in ["contract_id", "kind", "type_name", "engine_version", "engine_build_hash", "scope", "source_hash", "contract_hash", "authoring_mode", "status"]:
		if entry.get(field, null) != contract.get(field, null):
			findings.append("清单字段 %s 与契约不一致：%s" % [field, path])


func _validate_base_hashes(path: String, entries_by_id: Dictionary, findings: PackedStringArray) -> void:
	var contract_value: Variant = Core.read_json(path)
	if not contract_value is Dictionary:
		return
	var base_hashes: Dictionary = contract_value.get("base_contract_hashes", {})
	for base_id in base_hashes:
		if not entries_by_id.has(base_id):
			findings.append("基类契约不在同一清单：%s -> %s" % [path, base_id])
			continue
		var entry: Dictionary = entries_by_id[base_id]
		if String(base_hashes[base_id]) != String(entry.get("contract_hash", "")):
			findings.append("基类契约哈希已失效：%s -> %s" % [path, base_id])


func _argument_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	else:
		result.append(String(value))
	return result


func _resolve_entry_path(manifest_path: String, entry_path: String, entry: Dictionary) -> String:
	if entry_path.begins_with("res://") or entry_path.begins_with("user://") or entry_path.is_absolute_path():
		return entry_path
	if FileAccess.file_exists(Core.globalize(entry_path)):
		return entry_path
	var directory := Core.globalize(manifest_path).get_base_dir()
	var kind_directory := "nodes" if entry.get("kind", "") == "node" else "resources"
	var candidate := directory.path_join(kind_directory).path_join(entry_path.get_file()).simplify_path()
	return candidate if FileAccess.file_exists(candidate) else entry_path


func _fail(message: String) -> void:
	printerr("GODOT_DEV_CONTRACT %s" % message)
	quit(1)
