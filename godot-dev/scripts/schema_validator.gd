extends RefCounted


static func validate(value: Variant, schema_path: String) -> PackedStringArray:
	var findings := PackedStringArray()
	var cache := {}
	var schema: Variant = _read_json(schema_path)
	if not schema is Dictionary:
		findings.append("无法读取 JSON Schema：%s" % schema_path)
		return findings
	_validate_value(value, schema, "$", schema_path, cache, findings)
	return findings


static func _validate_value(value: Variant, schema: Dictionary, value_path: String, schema_path: String, cache: Dictionary, findings: PackedStringArray) -> void:
	if schema.has("$ref"):
		var resolved := _resolve_reference(String(schema["$ref"]), schema_path, cache)
		if resolved.is_empty():
			findings.append("%s 无法解析 Schema 引用 %s" % [value_path, schema["$ref"]])
			return
		_validate_value(value, resolved["schema"], value_path, resolved["path"], cache, findings)
		return
	if schema.has("type") and not _matches_type(value, String(schema["type"])):
		findings.append("%s 类型应为 %s，实际为 %s" % [value_path, schema["type"], type_string(typeof(value))])
		return
	if schema.has("const") and value != schema["const"]:
		findings.append("%s 不等于常量 %s" % [value_path, var_to_str(schema["const"])])
	if schema.has("enum") and not (schema["enum"] as Array).has(value):
		findings.append("%s 不在枚举 %s 中" % [value_path, var_to_str(schema["enum"])])

	if value is Dictionary:
		_validate_object(value, schema, value_path, schema_path, cache, findings)
	elif value is Array:
		_validate_array(value, schema, value_path, schema_path, cache, findings)
	elif value is String:
		_validate_string(value, schema, value_path, findings)


static func _validate_object(value: Dictionary, schema: Dictionary, value_path: String, schema_path: String, cache: Dictionary, findings: PackedStringArray) -> void:
	for required_key in schema.get("required", []):
		if not value.has(required_key):
			findings.append("%s 缺少必填字段 %s" % [value_path, required_key])
	var properties: Dictionary = schema.get("properties", {})
	for key in value:
		var key_text := String(key)
		if properties.has(key_text):
			_validate_value(value[key], properties[key_text], "%s.%s" % [value_path, key_text], schema_path, cache, findings)
			continue
		var additional: Variant = schema.get("additionalProperties", true)
		if additional is bool and not additional:
			findings.append("%s 包含未声明字段 %s" % [value_path, key_text])
		elif additional is Dictionary:
			_validate_value(value[key], additional, "%s.%s" % [value_path, key_text], schema_path, cache, findings)


static func _validate_array(value: Array, schema: Dictionary, value_path: String, schema_path: String, cache: Dictionary, findings: PackedStringArray) -> void:
	if not schema.has("items"):
		return
	var item_schema: Dictionary = schema["items"]
	for index in value.size():
		_validate_value(value[index], item_schema, "%s[%d]" % [value_path, index], schema_path, cache, findings)


static func _validate_string(value: String, schema: Dictionary, value_path: String, findings: PackedStringArray) -> void:
	if schema.has("minLength") and value.length() < int(schema["minLength"]):
		findings.append("%s 长度小于 %d" % [value_path, schema["minLength"]])
	if schema.has("pattern"):
		var regex := RegEx.new()
		if regex.compile(String(schema["pattern"])) != OK or regex.search(value) == null:
			findings.append("%s 不匹配正则 %s" % [value_path, schema["pattern"]])


static func _matches_type(value: Variant, expected: String) -> bool:
	match expected:
		"object":
			return value is Dictionary
		"array":
			return value is Array
		"string":
			return value is String
		"integer":
			return value is int or (value is float and is_equal_approx(value, roundf(value)))
		"number":
			return value is int or value is float
		"boolean":
			return value is bool
		"null":
			return value == null
		_:
			return false


static func _resolve_reference(reference: String, current_schema_path: String, cache: Dictionary) -> Dictionary:
	var parts := reference.split("#", true, 1)
	var document_path := current_schema_path if parts[0].is_empty() else current_schema_path.get_base_dir().path_join(parts[0]).simplify_path()
	var document: Variant
	if cache.has(document_path):
		document = cache[document_path]
	else:
		document = _read_json(document_path)
		cache[document_path] = document
	if not document is Dictionary:
		return {}
	var target: Variant = document
	var pointer := parts[1] if parts.size() > 1 else ""
	if pointer.begins_with("/"):
		for raw_token in pointer.trim_prefix("/").split("/"):
			var token := raw_token.replace("~1", "/").replace("~0", "~")
			if not target is Dictionary or not target.has(token):
				return {}
			target = target[token]
	if not target is Dictionary:
		return {}
	return {"schema": target, "path": document_path}


static func _read_json(path: String) -> Variant:
	var absolute_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if not FileAccess.file_exists(absolute_path):
		return null
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return null
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value
