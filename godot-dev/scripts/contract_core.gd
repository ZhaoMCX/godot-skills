extends RefCounted

const CONTRACT_VERSION := 2
const AUTHORING_MODES := [
	"direct_text",
	"generated_structure",
	"scene_template",
	"resource_saver_only",
	"reference_only",
]
const STATUSES := ["cataloged", "validated", "stale", "reference_only"]


static func parse_args(arguments: PackedStringArray) -> Dictionary:
	var result := {}
	var index := 0
	while index < arguments.size():
		var key := arguments[index]
		if not key.begins_with("--"):
			index += 1
			continue
		key = key.trim_prefix("--")
		var value: Variant = true
		if index + 1 < arguments.size() and not arguments[index + 1].begins_with("--"):
			value = arguments[index + 1]
			index += 1
		if result.has(key):
			if result[key] is Array:
				result[key].append(value)
			else:
				result[key] = [result[key], value]
		else:
			result[key] = value
		index += 1
	return result


static func engine_version() -> String:
	var info := Engine.get_version_info()
	return "%s.%s.%s" % [info.get("major", 0), info.get("minor", 0), info.get("patch", 0)]


static func engine_build_hash() -> String:
	return String(Engine.get_version_info().get("hash", ""))


static func require_engine_47() -> String:
	var version := engine_version()
	if not version.begins_with("4.7."):
		return "需要 Godot 4.7，实际为 %s" % version
	return ""


static func inheritance_chain(type_name: StringName) -> Array[String]:
	var result: Array[String] = []
	var current := type_name
	while not current.is_empty():
		result.append(String(current))
		current = ClassDB.get_parent_class(current)
	return result


static func stable_value_text(value: Variant) -> String:
	if value is Object:
		if value == null:
			return "null"
		return "<%s>" % value.get_class()
	return var_to_str(value)


static func property_entries_from_class(type_name: StringName) -> Array:
	var result := []
	for property in ClassDB.class_get_property_list(type_name, false):
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var entry := _normalize_property(property, null)
		entry["default_value_text"] = "<derive>"
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return result


static func property_entries_from_object(object: Object) -> Array:
	var result := []
	for property in object.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name := StringName(property.get("name", ""))
		result.append(_normalize_property(property, object.get(property_name)))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return result


static func signal_entries_from_class(type_name: StringName) -> Array:
	return _normalize_signals(ClassDB.class_get_signal_list(type_name, false))


static func signal_entries_from_object(object: Object) -> Array:
	return _normalize_signals(object.get_signal_list())


static func path_constraints_from_properties(properties: Array) -> Array:
	var result := []
	for property in properties:
		if String(property.get("type", "")) != "NodePath":
			continue
		result.append({
			"property": String(property.get("name", "")),
			"resolution": "scene_tree",
			"target_type": String(property.get("hint_string", "")),
		})
	return result


static func source_hash(path: String) -> String:
	if path.is_empty():
		return ""
	var absolute_path := globalize(path)
	if not FileAccess.file_exists(absolute_path):
		return ""
	return sha256_bytes(FileAccess.get_file_as_bytes(absolute_path))


static func contract_hash(contract: Dictionary) -> String:
	var hash_input := contract.duplicate(true)
	hash_input.erase("contract_hash")
	return sha256_bytes(JSON.stringify(canonical_variant(hash_input), "", true).to_utf8_buffer())


static func canonical_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		for key in keys:
			result[String(key)] = canonical_variant(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(canonical_variant(item))
		return result
	if value is StringName:
		return String(value)
	return value


static func sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	var update_error := context.update(bytes)
	if update_error != OK:
		return ""
	return context.finish().hex_encode()


static func finalize_contract(contract: Dictionary) -> Dictionary:
	var normalized: Dictionary = canonical_variant(contract)
	contract.clear()
	contract.merge(normalized, true)
	contract["contract_hash"] = contract_hash(contract)
	return contract


static func read_json(path: String) -> Variant:
	var absolute_path := globalize(path)
	if not FileAccess.file_exists(absolute_path):
		return null
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return null
	var content := file.get_as_text()
	file.close()
	return JSON.parse_string(content)


static func read_text(path: String) -> String:
	var absolute_path := globalize(path)
	if not FileAccess.file_exists(absolute_path):
		return ""
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	return content


static func write_json(path: String, value: Variant) -> Error:
	var absolute_path := globalize(path)
	var make_error := ensure_parent_directory(path)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return make_error
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  ", true) + "\n")
	file.flush()
	file.close()
	return OK


static func write_contract(path: String, contract: Dictionary) -> Error:
	var first_error := write_json(path, contract)
	if first_error != OK:
		return first_error
	var serialized: Variant = read_json(path)
	if not serialized is Dictionary:
		return ERR_PARSE_ERROR
	contract.clear()
	contract.merge(serialized, true)
	finalize_contract(contract)
	return write_json(path, contract)


static func ensure_parent_directory(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(globalize(path).get_base_dir())


static func globalize(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func builtin_contract(type_name: StringName, kind: String) -> Dictionary:
	var can_instantiate := ClassDB.can_instantiate(type_name)
	var contract := {
		"contract_version": CONTRACT_VERSION,
		"contract_id": "godot-4.7:%s:%s" % [kind, type_name],
		"kind": kind,
		"type_name": String(type_name),
		"engine_version": engine_version(),
		"engine_build_hash": engine_build_hash(),
		"scope": "builtin",
		"source_path": "",
		"source_hash": "",
		"inheritance_chain": inheritance_chain(type_name),
		"base_contract_hashes": {},
		"context_requirements": [],
		"authoring_mode": "generated_structure" if can_instantiate else "reference_only",
		"properties": property_entries_from_class(type_name),
		"serialization": {
			"format": "tres" if kind == "resource" else "tscn-node",
			"minimal_text": "",
			"property_text_examples": {},
			"notes": ["目录契约没有单类型保存实验；先执行推导再决定能否直接文本编写。"],
		},
		"evidence": {
			"official_docs": ["https://docs.godotengine.org/en/4.7/classes/class_%s.html" % String(type_name).to_lower()],
			"official_source": [],
			"reflection": ["ClassDB %s %s" % [engine_version(), type_name]],
			"experiments": [],
		},
		"validation": {
			"save_reload": false,
			"independent_text": false,
			"notes": ["目录契约只完成反射；直接文本编写前必须执行单类型推导。"],
		},
		"status": "cataloged" if can_instantiate else "reference_only",
	}
	if kind == "resource":
		contract["constraints"] = ["只保存 PROPERTY_USAGE_STORAGE 属性。"]
	else:
		contract["signals"] = signal_entries_from_class(type_name)
		contract["path_constraints"] = []
		contract["child_constraints"] = ["具体子节点要求需由官方文档、源码或保存实验补充。"]
		contract["lifecycle_constraints"] = ["加入 SceneTree 后验证；仅实例化成功不足以证明行为正确。"]
	return finalize_contract(contract)


static func manifest_entry(contract: Dictionary, path: String) -> Dictionary:
	return {
		"contract_id": contract["contract_id"],
		"kind": contract["kind"],
		"type_name": contract["type_name"],
		"path": path.replace("\\", "/"),
		"engine_version": contract["engine_version"],
		"engine_build_hash": contract["engine_build_hash"],
		"scope": contract["scope"],
		"source_hash": contract["source_hash"],
		"contract_hash": contract["contract_hash"],
		"authoring_mode": contract["authoring_mode"],
		"status": contract["status"],
		"dependencies": contract["base_contract_hashes"].keys(),
	}


static func update_manifest(manifest_path: String, contract: Dictionary, contract_path: String) -> Error:
	var manifest_value: Variant = read_json(manifest_path)
	var manifest: Dictionary
	if manifest_value is Dictionary:
		manifest = manifest_value
	else:
		manifest = {
			"contract_version": CONTRACT_VERSION,
			"contracts": [],
			"engine_version": engine_version(),
			"engine_build_hash": engine_build_hash(),
			"scope": contract.get("scope", "project"),
		}
	var entries: Array = manifest.get("contracts", [])
	var next_entries := []
	for entry in entries:
		if entry.get("contract_id", "") != contract["contract_id"]:
			next_entries.append(entry)
	next_entries.append(manifest_entry(contract, contract_path))
	next_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["contract_id"] < b["contract_id"])
	manifest["contracts"] = next_entries
	manifest["contract_version"] = CONTRACT_VERSION
	manifest["engine_version"] = engine_version()
	manifest["engine_build_hash"] = engine_build_hash()
	return write_json(manifest_path, manifest)


static func _normalize_property(property: Dictionary, default_value: Variant) -> Dictionary:
	return {
		"name": String(property.get("name", "")),
		"type": type_string(int(property.get("type", TYPE_NIL))),
		"class_name": String(property.get("class_name", "")),
		"hint": int(property.get("hint", PROPERTY_HINT_NONE)),
		"hint_string": String(property.get("hint_string", "")),
		"usage": int(property.get("usage", 0)),
		"default_value_text": stable_value_text(default_value),
	}


static func _normalize_signals(signals: Array) -> Array:
	var result := []
	for signal_info in signals:
		var arguments := []
		for argument in signal_info.get("args", []):
			arguments.append({
				"name": String(argument.get("name", "")),
				"type": type_string(int(argument.get("type", TYPE_NIL))),
				"class_name": String(argument.get("class_name", "")),
			})
		result.append({"name": String(signal_info.get("name", "")), "arguments": arguments})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return result
