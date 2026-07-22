extends SceneTree

const Core := preload("contract_core.gd")

const REFERENCE_VALIDATION_PREFIX := "reference_validation="
const REPRESENTATIVE_PREFIX := "representative_property="
const SKIPPED_PROPERTY_NAMES := {
	"animation": true,
	"body_type": true,
	"data": true,
	"load_path": true,
	"resource_path": true,
	"script": true,
	"scene_file_path": true,
}
const CONTEXT_REFERENCE_TYPES := {
	"MissingNode": "占位节点只能由缺失脚本/扩展场景的加载流程创建。",
	"MissingResource": "占位资源只能由缺失脚本/扩展资源的加载流程创建。",
	"OpenXRRenderModel": "需要活动 OpenXR render model extension。",
	"OpenXRRenderModelManager": "需要活动 OpenXR render model extension。",
}
const NO_REPRESENTATIVE_TYPES := {
	"FontFile": true,
}
const NO_TREE_LIFECYCLE_TYPES := {
	"Bone2D": true,
	"OpenXRRenderModel": true,
	"OpenXRRenderModelManager": true,
}

var _verbose := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var version_error := Core.require_engine_47()
	if not version_error.is_empty():
		_fail(version_error)
		return
	var args := Core.parse_args(OS.get_cmdline_user_args())
	_verbose = bool(args.get("verbose", false))
	if not args.has("manifest") or not args.has("output-root"):
		_fail("需要 --manifest <manifest.json> 和 --output-root <目录>。")
		return
	var manifest_path := String(args["manifest"])
	var output_root := String(args["output-root"]).trim_suffix("/")
	var manifest_value: Variant = Core.read_json(manifest_path)
	if not manifest_value is Dictionary:
		_fail("无法读取内置契约清单：%s。" % manifest_path)
		return
	var requested_types := _argument_values(args.get("type", []))
	var entries: Array = manifest_value.get("contracts", [])
	var output_entries := []
	var derived_items := []
	var report_entries := []
	var counts := {
		"concrete_total": 0,
		"generated_save_reload": 0,
		"generated_unavailable": 0,
		"reference_only": 0,
		"reference_witness": 0,
		"representative_property": 0,
		"nested_resource": 0,
	}
	for entry_value in entries:
		if not entry_value is Dictionary:
			_fail("清单包含非对象条目。")
			return
		var entry: Dictionary = entry_value
		var type_name := String(entry.get("type_name", ""))
		if not requested_types.is_empty() and not requested_types.has(type_name):
			continue
		if _verbose:
			print("GODOT_DEV_BUILTIN_DERIVE_TYPE %s" % type_name)
		var source_path := _resolve_entry_path(manifest_path, String(entry.get("path", "")), entry)
		var source_contract_value: Variant = Core.read_json(source_path)
		if not source_contract_value is Dictionary:
			_fail("无法读取契约：%s。" % source_path)
			return
		var contract: Dictionary = source_contract_value.duplicate(true)
		var result := await _derive_contract(contract)
		report_entries.append(result["report"])
		for key in result["count_keys"]:
			counts[key] = int(counts.get(key, 0)) + 1
		var directory_name := "nodes" if contract["kind"] == "node" else "resources"
		var output_path := output_root.path_join(directory_name).path_join(String(entry["path"]).get_file())
		derived_items.append({"contract": contract, "output_path": output_path})

	_apply_base_contract_hashes(derived_items)
	for item in derived_items:
		var contract: Dictionary = item["contract"]
		var output_path := String(item["output_path"])
		var write_error := Core.write_contract(output_path, contract)
		if write_error != OK:
			_fail("写入推导契约失败 %s：%s。" % [output_path, error_string(write_error)])
			return
		var directory_name := "nodes" if contract["kind"] == "node" else "resources"
		var relative_path := directory_name.path_join(output_path.get_file())
		output_entries.append(Core.manifest_entry(contract, relative_path))

	output_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["contract_id"] < b["contract_id"])
	var output_manifest := {
		"contract_version": Core.CONTRACT_VERSION,
		"contracts": output_entries,
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"scope": "builtin",
	}
	if Core.write_json(output_root.path_join("manifest.json"), output_manifest) != OK:
		_fail("写入推导清单失败。")
		return
	var report := {
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"phase": "derive",
		"counts": counts,
		"contracts": report_entries,
	}
	var report_path := String(args.get("report", "user://godot-dev/reports/builtin-derive.json"))
	if Core.write_json(report_path, report) != OK:
		_fail("写入推导报告失败。")
		return
	print("内置契约推导完成：%d 个；保存/重载 %d；仅引用 %d；代表属性 %d；嵌套 Resource %d。" % [
		output_entries.size(),
		counts["generated_save_reload"],
		counts["reference_only"],
		counts["representative_property"],
		counts["nested_resource"],
	])
	quit(0)


func _apply_base_contract_hashes(items: Array) -> void:
	var by_id := {}
	for item in items:
		var contract: Dictionary = item["contract"]
		by_id[String(contract["contract_id"])] = contract
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["contract"].get("inheritance_chain", []).size() < b["contract"].get("inheritance_chain", []).size()
	)
	for item in items:
		var contract: Dictionary = item["contract"]
		var chain: Array = contract.get("inheritance_chain", [])
		contract["base_contract_hashes"] = {}
		if chain.size() > 1:
			var base_id := "godot-4.7:%s:%s" % [contract["kind"], chain[1]]
			if by_id.has(base_id):
				contract["base_contract_hashes"][base_id] = by_id[base_id]["contract_hash"]
		Core.finalize_contract(contract)


func _derive_contract(contract: Dictionary) -> Dictionary:
	var type_name := String(contract["type_name"])
	var kind := String(contract["kind"])
	contract["contract_version"] = Core.CONTRACT_VERSION
	contract["engine_version"] = Core.engine_version()
	contract["engine_build_hash"] = Core.engine_build_hash()
	contract["base_contract_hashes"] = {}
	contract["context_requirements"] = _context_requirements(type_name)
	if kind == "node":
		contract["path_constraints"] = Core.path_constraints_from_properties(contract.get("properties", []))
	var count_keys := []
	var report := {
		"type_name": type_name,
		"kind": kind,
		"class_exists": ClassDB.class_exists(type_name),
		"can_instantiate": ClassDB.can_instantiate(type_name) if ClassDB.class_exists(type_name) else false,
		"save_reload": false,
		"representative_property": "",
		"nested_resource_property": "",
		"reference_witness": "",
		"notes": [],
	}
	if not report["class_exists"]:
		contract["status"] = "stale"
		contract["validation"] = {
			"save_reload": false,
			"independent_text": false,
			"notes": ["Godot %s 中不存在该 ClassDB 类型。" % Core.engine_version()],
		}
		Core.finalize_contract(contract)
		return {"report": report, "count_keys": count_keys}
	if CONTEXT_REFERENCE_TYPES.has(type_name):
		count_keys.append("generated_unavailable")
		contract["authoring_mode"] = "reference_only"
		contract["status"] = "cataloged"
		contract["serialization"]["minimal_text"] = ""
		contract["serialization"]["property_text_examples"] = {}
		contract["serialization"]["notes"] = [String(CONTEXT_REFERENCE_TYPES[type_name])]
		contract["validation"] = {
			"save_reload": false,
			"independent_text": false,
			"notes": ["context_reference_boundary=%s" % String(CONTEXT_REFERENCE_TYPES[type_name])],
		}
		contract["evidence"]["experiments"] = ["ClassDB 实例边界已验证；不在缺少所需上下文时触发生命周期副作用。"]
		Core.finalize_contract(contract)
		return {"report": report, "count_keys": count_keys}
	if type_name == "PackedScene":
		count_keys.append("concrete_total")
		var packed_result := _derive_packed_scene_contract(contract)
		report["save_reload"] = packed_result["ok"]
		if packed_result["ok"]:
			count_keys.append("generated_save_reload")
		else:
			count_keys.append("generated_unavailable")
		report["notes"].append_array(packed_result["notes"])
		return {"report": report, "count_keys": count_keys}

	if not report["can_instantiate"]:
		count_keys.append("reference_only")
		var witness := _find_concrete_witness(type_name, kind)
		report["reference_witness"] = witness
		if not witness.is_empty():
			count_keys.append("reference_witness")
		contract["authoring_mode"] = "reference_only"
		contract["status"] = "reference_only"
		contract["serialization"]["minimal_text"] = ""
		contract["serialization"]["property_text_examples"] = {}
		contract["serialization"]["notes"] = ["ClassDB 明确不可实例化；通过具体子类验证继承和引用边界。"]
		var reference_note := {
			"class_exists": true,
			"can_instantiate": false,
			"witness": witness,
			"witness_inherits": not witness.is_empty() and ClassDB.is_parent_class(witness, type_name),
		}
		contract["validation"] = {
			"save_reload": false,
			"independent_text": false,
			"notes": [REFERENCE_VALIDATION_PREFIX + JSON.stringify(reference_note, "", true)],
		}
		contract["evidence"]["reflection"] = ["ClassDB %s %s：存在、不可实例化。" % [Core.engine_version(), type_name]]
		contract["evidence"]["experiments"] = ["具体子类见证：%s" % witness] if not witness.is_empty() else ["没有可实例化的具体子类；仅允许作为类型边界引用。"]
		Core.finalize_contract(contract)
		return {"report": report, "count_keys": count_keys}

	count_keys.append("concrete_total")
	var object: Object = ClassDB.instantiate(type_name)
	if object == null or (kind == "resource" and not object is Resource) or (kind == "node" and not object is Node):
		contract["status"] = "stale"
		contract["validation"] = {
			"save_reload": false,
			"independent_text": false,
			"notes": ["ClassDB.can_instantiate=true，但实例类型与契约 kind 不一致。"],
		}
		if object != null:
			_release_object(object)
		Core.finalize_contract(contract)
		return {"report": report, "count_keys": count_keys}

	contract["properties"] = Core.property_entries_from_object(object)
	if kind == "node":
		contract["signals"] = Core.signal_entries_from_object(object)
		contract["path_constraints"] = Core.path_constraints_from_properties(contract["properties"])
	contract["inheritance_chain"] = Core.inheritance_chain(type_name)
	var experiment_root := "user://godot-dev/builtin-derive/%s" % kind
	var minimal_path := experiment_root.path_join("%s-minimal.%s" % [type_name.to_snake_case(), "tres" if kind == "resource" else "tscn"])
	var generated := await _save_reload_object(object, kind, type_name, minimal_path, true)
	report["save_reload"] = generated["ok"]
	if generated["ok"]:
		count_keys.append("generated_save_reload")
	else:
		count_keys.append("generated_unavailable")
		report["notes"].append_array(generated["notes"])

	var minimal_text := _normalize_generated_text(Core.read_text(minimal_path)) if generated["ok"] else ""
	var property_examples := {}
	var validation_notes := []
	if NO_TREE_LIFECYCLE_TYPES.has(type_name):
		validation_notes.append("lifecycle_context=需要所属系统提供的有效父子上下文；孤立节点不进入 SceneTree。")
	if generated["ok"]:
		var representative := {"ok": false} if NO_REPRESENTATIVE_TYPES.has(type_name) else await _derive_representative_property(type_name, kind, experiment_root)
		if representative["ok"]:
			count_keys.append("representative_property")
			report["representative_property"] = representative["name"]
			property_examples[representative["name"]] = representative["line"]
			validation_notes.append(REPRESENTATIVE_PREFIX + JSON.stringify({
				"name": representative["name"],
				"expected": representative["expected"],
			}, "", true))
		else:
			validation_notes.append("没有找到可安全设置且能稳定往返的非默认标量存储属性。")
		var nested := await _derive_nested_resource(type_name, kind, experiment_root)
		if nested["ok"]:
			count_keys.append("nested_resource")
			report["nested_resource_property"] = nested["name"]
			validation_notes.append("nested_resource=%s:%s" % [nested["name"], nested["class_name"]])
		else:
			validation_notes.append("该类型没有可安全构造并稳定往返的嵌套 Resource 属性。")

	contract["serialization"] = {
		"format": "tres" if kind == "resource" else "tscn-node",
		"minimal_text": minimal_text,
		"property_text_examples": property_examples,
		"notes": ["最小文本由 Godot %s 保存实验生成；独立验证阶段只读取本契约重建新文件。" % Core.engine_version()],
	}
	contract["authoring_mode"] = "generated_structure" if generated["ok"] else "reference_only"
	contract["status"] = "cataloged"
	contract["validation"] = {
		"save_reload": generated["ok"],
		"independent_text": false,
		"notes": validation_notes + generated["notes"],
	}
	contract["evidence"]["reflection"] = ["Object.get_property_list %s；ClassDB.can_instantiate=true。" % Core.engine_version()]
	contract["evidence"]["experiments"] = [minimal_path] if generated["ok"] else ["生成结构保存失败；只允许引用现有资源。"]
	_apply_animation_contract_rules(contract)
	_release_object(object)
	Core.finalize_contract(contract)
	return {"report": report, "count_keys": count_keys}


func _context_requirements(type_name: String) -> Array:
	if CONTEXT_REFERENCE_TYPES.has(type_name):
		return [{
			"id": type_name.to_snake_case(),
			"mode": "external",
			"description": String(CONTEXT_REFERENCE_TYPES[type_name]),
		}]
	if type_name == "Bone2D":
		return [{
			"id": "skeleton_2d_hierarchy",
			"mode": "local",
			"description": "需要 Skeleton2D 父级和有效 Bone2D 层级。",
		}]
	if type_name == "PackedScene":
		return [{
			"id": "packed_scene_owner_tree",
			"mode": "local",
			"description": "通过有 owner 的节点树和 PackedScene.pack() 生成。",
		}]
	return []


func _save_reload_object(object: Object, kind: String, type_name: String, path: String, enter_tree: bool) -> Dictionary:
	var notes := []
	var directory_error := Core.ensure_parent_directory(path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "notes": ["无法创建实验目录：%s。" % error_string(directory_error)]}
	if kind == "resource":
		var resource := object as Resource
		var save_error := ResourceSaver.save(resource, path)
		if save_error != OK:
			return {"ok": false, "notes": ["ResourceSaver.save 失败：%s。" % error_string(save_error)]}
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		return {
			"ok": loaded != null and loaded.is_class(type_name),
			"loaded": loaded,
			"notes": notes if loaded != null and loaded.is_class(type_name) else ["Resource 重载类型不一致。"],
		}

	var node := object as Node
	_prepare_node_context(node, type_name)
	if node.name.is_empty():
		node.name = type_name
	var packed := PackedScene.new()
	var pack_error := packed.pack(node)
	if pack_error != OK:
		return {"ok": false, "notes": ["PackedScene.pack 失败：%s。" % error_string(pack_error)]}
	var save_error := ResourceSaver.save(packed, path)
	if save_error != OK:
		return {"ok": false, "notes": ["PackedScene 保存失败：%s。" % error_string(save_error)]}
	var loaded_scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var instance := loaded_scene.instantiate() if loaded_scene != null and loaded_scene.can_instantiate() else null
	if instance == null or not instance.is_class(type_name):
		if instance != null:
			instance.free()
		return {"ok": false, "notes": ["PackedScene 重载或实例类型不一致。"]}
	if enter_tree and not NO_TREE_LIFECYCLE_TYPES.has(type_name):
		root.add_child(instance)
		await process_frame
		await process_frame
		root.remove_child(instance)
	instance.free()
	return {"ok": true, "loaded": loaded_scene, "notes": notes}


func _derive_representative_property(type_name: String, kind: String, experiment_root: String) -> Dictionary:
	var candidate_names := _ordered_property_names(type_name)
	for property_name in candidate_names:
		var object: Object = ClassDB.instantiate(type_name)
		if object == null:
			break
		var property_info := _property_info(object, property_name)
		var candidate := _representative_value(property_info, object.get(property_name))
		if not candidate["ok"]:
			_release_object(object)
			continue
		object.set(property_name, candidate["value"])
		var actual: Variant = object.get(property_name)
		if Core.stable_value_text(actual) == Core.stable_value_text(candidate["original"]):
			_release_object(object)
			continue
		var extension := "tres" if kind == "resource" else "tscn"
		var path := experiment_root.path_join("%s-property-%s.%s" % [type_name.to_snake_case(), property_name.to_snake_case(), extension])
		var saved := await _save_reload_object(object, kind, type_name, path, false)
		_release_object(object)
		if not saved["ok"]:
			continue
		var line := _find_property_line(Core.read_text(path), property_name)
		if line.is_empty():
			continue
		var loaded_object: Object
		if kind == "resource":
			loaded_object = saved["loaded"]
		else:
			var packed := saved["loaded"] as PackedScene
			loaded_object = packed.instantiate() if packed != null else null
		if loaded_object == null:
			continue
		var expected := Core.stable_value_text(loaded_object.get(property_name))
		if kind == "node":
			loaded_object.free()
		return {"ok": true, "name": property_name, "line": line, "expected": expected}
	return {"ok": false}


func _derive_nested_resource(type_name: String, kind: String, experiment_root: String) -> Dictionary:
	var probe: Object = ClassDB.instantiate(type_name)
	if probe == null:
		return {"ok": false}
	for property in probe.get_property_list():
		var usage := int(property.get("usage", 0))
		var property_name := String(property.get("name", ""))
		if (usage & PROPERTY_USAGE_STORAGE) == 0 or SKIPPED_PROPERTY_NAMES.has(property_name) or property_name.contains("/"):
			continue
		if int(property.get("type", TYPE_NIL)) != TYPE_OBJECT:
			continue
		var property_class_name := String(property.get("class_name", ""))
		var resource_type := _concrete_resource_type(property_class_name)
		if resource_type.is_empty():
			continue
		var nested := _create_nested_resource(resource_type)
		if nested == null:
			continue
		probe.set(property_name, nested)
		var actual := probe.get(property_name) as Resource
		if actual == null:
			continue
		var extension := "tres" if kind == "resource" else "tscn"
		var path := experiment_root.path_join("%s-nested-%s.%s" % [type_name.to_snake_case(), property_name.to_snake_case(), extension])
		var saved := await _save_reload_object(probe, kind, type_name, path, false)
		if not saved["ok"]:
			continue
		var loaded_object: Object
		if kind == "resource":
			loaded_object = saved["loaded"]
		else:
			loaded_object = (saved["loaded"] as PackedScene).instantiate()
		var loaded_nested := loaded_object.get(property_name) as Resource if loaded_object != null else null
		if loaded_nested != null and loaded_nested.is_class(resource_type):
			if kind == "node":
				loaded_object.free()
			_release_object(probe)
			return {"ok": true, "name": property_name, "class_name": resource_type}
		if kind == "node" and loaded_object != null:
			loaded_object.free()
	_release_object(probe)
	return {"ok": false}


func _ordered_property_names(type_name: String) -> Array[String]:
	var result: Array[String] = []
	for property in ClassDB.class_get_property_list(type_name, true):
		var property_name := String(property.get("name", ""))
		if _is_scalar_storage_property(property, type_name) and not result.has(property_name):
			result.append(property_name)
	var object: Object = ClassDB.instantiate(type_name)
	if object != null:
		for property in object.get_property_list():
			var property_name := String(property.get("name", ""))
			if _is_scalar_storage_property(property, type_name) and not result.has(property_name):
				result.append(property_name)
		_release_object(object)
	return result


func _is_scalar_storage_property(property: Dictionary, type_name: String) -> bool:
	var usage := int(property.get("usage", 0))
	var property_name := String(property.get("name", ""))
	if (usage & PROPERTY_USAGE_STORAGE) == 0 or SKIPPED_PROPERTY_NAMES.has(property_name) or property_name.contains("/"):
		return false
	if type_name == "CameraAttributesPractical" and property_name.begins_with("dof_blur"):
		return false
	var variant_type := int(property.get("type", TYPE_NIL))
	if [TYPE_STRING, TYPE_STRING_NAME].has(variant_type) and property_name != "resource_name":
		return false
	return [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_TRANSFORM2D, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION, TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR, TYPE_NODE_PATH].has(variant_type)


func _representative_value(property: Dictionary, current: Variant) -> Dictionary:
	var variant_type := int(property.get("type", TYPE_NIL))
	var value: Variant
	match variant_type:
		TYPE_BOOL:
			value = not bool(current)
		TYPE_INT:
			value = _representative_number(property, float(current), true)
		TYPE_FLOAT:
			value = _representative_number(property, float(current), false)
		TYPE_STRING:
			value = "godot_dev_sample"
		TYPE_STRING_NAME:
			value = &"godot_dev_sample"
		TYPE_VECTOR2:
			value = Vector2(1.25, 2.5)
		TYPE_VECTOR2I:
			value = Vector2i(1, 2)
		TYPE_RECT2:
			value = Rect2(1, 2, 3, 4)
		TYPE_RECT2I:
			value = Rect2i(1, 2, 3, 4)
		TYPE_VECTOR3:
			value = Vector3(1.25, 2.5, 3.75)
		TYPE_VECTOR3I:
			value = Vector3i(1, 2, 3)
		TYPE_TRANSFORM2D:
			value = Transform2D(0.25, Vector2(2, 3))
		TYPE_VECTOR4:
			value = Vector4(1, 2, 3, 4)
		TYPE_VECTOR4I:
			value = Vector4i(1, 2, 3, 4)
		TYPE_PLANE:
			value = Plane(Vector3.UP, 2.0)
		TYPE_QUATERNION:
			value = Quaternion(Vector3.UP, 0.25)
		TYPE_AABB:
			value = AABB(Vector3(1, 2, 3), Vector3(4, 5, 6))
		TYPE_BASIS:
			value = Basis(Vector3.UP, 0.25)
		TYPE_TRANSFORM3D:
			value = Transform3D(Basis(Vector3.UP, 0.25), Vector3(1, 2, 3))
		TYPE_PROJECTION:
			value = Projection.create_perspective(1.0, 1.5, 0.1, 10.0)
		TYPE_COLOR:
			value = Color(0.25, 0.5, 0.75, 1.0)
		TYPE_NODE_PATH:
			value = NodePath("GodotDevTarget")
		TYPE_PACKED_BYTE_ARRAY:
			value = PackedByteArray([1, 2, 3])
		TYPE_PACKED_INT32_ARRAY:
			value = PackedInt32Array([1, 2, 3])
		TYPE_PACKED_INT64_ARRAY:
			value = PackedInt64Array([1, 2, 3])
		TYPE_PACKED_FLOAT32_ARRAY:
			value = PackedFloat32Array([1.25, 2.5])
		TYPE_PACKED_FLOAT64_ARRAY:
			value = PackedFloat64Array([1.25, 2.5])
		TYPE_PACKED_STRING_ARRAY:
			value = PackedStringArray(["alpha", "beta"])
		TYPE_PACKED_VECTOR2_ARRAY:
			value = PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
		TYPE_PACKED_VECTOR3_ARRAY:
			value = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
		TYPE_PACKED_COLOR_ARRAY:
			value = PackedColorArray([Color.RED, Color.BLUE])
		TYPE_PACKED_VECTOR4_ARRAY:
			value = PackedVector4Array([Vector4(1, 2, 3, 4)])
		_:
			return {"ok": false}
	return {"ok": Core.stable_value_text(value) != Core.stable_value_text(current), "value": value, "original": current}


func _representative_number(property: Dictionary, current: float, integer: bool) -> Variant:
	var hint := int(property.get("hint", PROPERTY_HINT_NONE))
	var hint_string := String(property.get("hint_string", ""))
	if hint == PROPERTY_HINT_ENUM:
		var options := hint_string.split(",")
		if options.size() > 1:
			var candidate := 0 if int(current) != 0 else 1
			return candidate
	if hint == PROPERTY_HINT_RANGE:
		var parts := hint_string.split(",")
		if parts.size() >= 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			var minimum := float(parts[0])
			var maximum := float(parts[1])
			var candidate := clampf(current + (1.0 if integer else 0.5), minimum, maximum)
			if is_equal_approx(candidate, current):
				candidate = minimum if not is_equal_approx(minimum, current) else maximum
			return int(candidate) if integer else candidate
	return int(current + 1.0) if integer else current + 0.5


func _property_info(object: Object, property_name: String) -> Dictionary:
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return property
	return {}


func _find_property_line(text: String, property_name: String) -> String:
	var prefix := property_name + " = "
	for line in text.split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


func _normalize_generated_text(text: String) -> String:
	var lines := PackedStringArray()
	var unique_id_regex := RegEx.new()
	unique_id_regex.compile(" unique_id=\\d+")
	for line in text.split("\n"):
		if line.begins_with("[gd_resource") or line.begins_with("[gd_scene"):
			var uid_start := line.find(" uid=\"")
			if uid_start >= 0:
				var uid_end := line.find("\"", uid_start + 6)
				if uid_end >= 0:
					line = line.erase(uid_start, uid_end - uid_start + 1)
		line = unique_id_regex.sub(line, "", true)
		lines.append(line)
	return "\n".join(lines).strip_edges() + "\n"


func _find_concrete_witness(type_name: String, kind: String) -> String:
	var candidates: Array[String] = []
	for candidate in ClassDB.get_class_list():
		if candidate == type_name or not ClassDB.can_instantiate(candidate):
			continue
		if not ClassDB.is_parent_class(candidate, type_name):
			continue
		if kind == "resource" and not ClassDB.is_parent_class(candidate, &"Resource"):
			continue
		if kind == "node" and not ClassDB.is_parent_class(candidate, &"Node"):
			continue
		candidates.append(String(candidate))
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _concrete_resource_type(property_class_name: String) -> String:
	if property_class_name.is_empty() or not ClassDB.class_exists(property_class_name) or not ClassDB.is_parent_class(property_class_name, &"Resource"):
		return ""
	if ClassDB.can_instantiate(property_class_name):
		return property_class_name
	return _find_concrete_witness(property_class_name, "resource")


func _create_nested_resource(resource_type: String) -> Resource:
	var concrete_type := resource_type
	if ClassDB.is_parent_class(resource_type, &"Texture2D") and resource_type == "Texture2D":
		concrete_type = "GradientTexture1D"
	elif ClassDB.is_parent_class(resource_type, &"Mesh") and resource_type == "Mesh":
		concrete_type = "ArrayMesh"
	elif ClassDB.is_parent_class(resource_type, &"Shape2D") and resource_type == "Shape2D":
		concrete_type = "RectangleShape2D"
	elif ClassDB.is_parent_class(resource_type, &"Shape3D") and resource_type == "Shape3D":
		concrete_type = "BoxShape3D"
	elif ClassDB.is_parent_class(resource_type, &"Font") and resource_type == "Font":
		concrete_type = "SystemFont"
	var resource := ClassDB.instantiate(concrete_type) as Resource
	if resource is GradientTexture1D:
		(resource as GradientTexture1D).gradient = Gradient.new()
	elif resource is Shader:
		(resource as Shader).code = "shader_type spatial;"
	return resource


func _prepare_node_context(node: Node, type_name: String) -> void:
	if type_name == "ShapeCast2D":
		(node as ShapeCast2D).shape = RectangleShape2D.new()
	elif type_name == "ShapeCast3D":
		(node as ShapeCast3D).shape = BoxShape3D.new()


func _derive_packed_scene_contract(contract: Dictionary) -> Dictionary:
	var node := Node.new()
	node.name = "GodotDevPackedScene"
	var packed := PackedScene.new()
	var pack_error := packed.pack(node)
	node.free()
	var sample_path := "user://godot-dev/builtin-derive/resource/packed_scene-minimal.tscn"
	var save_error := ResourceSaver.save(packed, sample_path) if pack_error == OK else pack_error
	var loaded := ResourceLoader.load(sample_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene if save_error == OK else null
	var ok := loaded != null and loaded.can_instantiate()
	var packed_properties := []
	for property in Core.property_entries_from_object(packed):
		if property.get("name", "") != "_bundled":
			packed_properties.append(property)
	contract["properties"] = packed_properties
	contract["inheritance_chain"] = Core.inheritance_chain(&"PackedScene")
	contract["authoring_mode"] = "resource_saver_only"
	contract["status"] = "validated" if ok else "stale"
	contract["serialization"] = {
		"format": "tres",
		"minimal_text": "",
		"property_text_examples": {},
		"notes": ["PackedScene 的文本载体是 .tscn，不作为 .tres 从零手写；通过 PackedScene.pack 与 ResourceSaver 生成。内部 _bundled 含非确定 node_ids，不作为可编辑属性写入契约。"],
	}
	contract["validation"] = {
		"save_reload": ok,
		"independent_text": false,
		"notes": ["packed_scene_tscn=%s" % sample_path] if ok else ["PackedScene pack/save/reload 失败。"],
	}
	contract["evidence"]["experiments"] = [sample_path]
	Core.finalize_contract(contract)
	return {"ok": ok, "notes": contract["validation"]["notes"]}


func _apply_animation_contract_rules(contract: Dictionary) -> void:
	var type_name := String(contract["type_name"])
	var fixture_root := "tests/fixture_project/"
	var examples: Dictionary = contract["serialization"].get("property_text_examples", {})
	var notes: Array = contract["serialization"].get("notes", [])
	var experiments: Array = contract["evidence"].get("experiments", [])
	match type_name:
		"AnimationTree":
			examples["tree_root"] = "tree_root = ExtResource(\"1_state_machine\")"
			examples["anim_player"] = "anim_player = NodePath(\"../AnimationPlayer\")"
			notes.append("AnimationTree 本身保存于 .tscn；tree_root 引用 AnimationNode Resource，完整装配与推进由专项场景验证。")
			experiments.append(fixture_root + "animation_tree_direct.tscn")
		"Animation", "AnimationLibrary":
			notes.append("Animation track 字典和 AnimationLibrary._data 的完整文本由 AnimationTree 专项场景验证。")
			experiments.append(fixture_root + "animation_tree_direct.tscn")
		"AnimationNodeAnimation":
			examples["animation"] = "animation = &\"idle\""
			experiments.append(fixture_root + "animation_tree_state_machine.tres")
		"AnimationNodeStateMachine":
			examples["states/<name>/node"] = "states/idle/node = SubResource(\"AnimationNodeAnimation_idle\")"
			examples["states/<name>/position"] = "states/idle/position = Vector2(240, 100)"
			examples["transitions"] = "transitions = [&\"idle\", &\"run\", SubResource(\"Transition_idle_run\")]"
			notes.append("每条 transitions 记录依次为 from、to、AnimationNodeStateMachineTransition 子资源。")
			experiments.append(fixture_root + "animation_tree_state_machine.tres")
		"AnimationNodeStateMachineTransition":
			if not examples.has("xfade_time"):
				examples["xfade_time"] = "xfade_time = 0.1"
			experiments.append(fixture_root + "animation_tree_state_machine.tres")
		"AnimationNodeBlendTree":
			examples["nodes/<name>/node"] = "nodes/idle/node = SubResource(\"AnimationNodeAnimation_idle\")"
			examples["nodes/<name>/position"] = "nodes/idle/position = Vector2(240, 100)"
			examples["node_connections"] = "node_connections = [&\"output\", 0, &\"idle\"]"
			experiments.append(fixture_root + "animation_tree_blend_tree.tres")
		"AnimationNodeBlendSpace1D":
			examples["blend_point_0/node"] = "blend_point_0/node = SubResource(\"AnimationNodeAnimation_idle\")"
			examples["blend_point_0/pos"] = "blend_point_0/pos = 0.0"
			examples["blend_point_0/name"] = "blend_point_0/name = &\"idle\""
			experiments.append(fixture_root + "animation_tree_blend_space_1d.tres")
		"AnimationNodeBlendSpace2D":
			examples["blend_point_0/node"] = "blend_point_0/node = SubResource(\"AnimationNodeAnimation_idle\")"
			examples["blend_point_0/pos"] = "blend_point_0/pos = Vector2(0, 0)"
			examples["blend_point_0/name"] = "blend_point_0/name = &\"idle\""
			examples["triangles"] = "triangles = PackedInt32Array(0, 1, 2)"
			notes.append("Godot 4.7.1 的 ResourceSaver 会把 triangles 写到 blend_point_* 之前并导致重载越界；文本中必须把 triangles 放在所有 blend_point_* 行之后，validate_assets.gd 会规范往返文件。")
			experiments.append(fixture_root + "animation_tree_blend_space_2d.tres")
		_:
			return
	contract["serialization"]["property_text_examples"] = examples
	contract["serialization"]["notes"] = notes
	contract["evidence"]["experiments"] = experiments


func _argument_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	elif value != null and String(value) != "":
		result.append(String(value))
	return result


## 相对清单目录解析契约文件，使技能位于项目内或全局目录时使用同一清单。
func _resolve_entry_path(manifest_path: String, entry_path: String, entry: Dictionary) -> String:
	if entry_path.begins_with("res://") or entry_path.begins_with("user://") or entry_path.is_absolute_path():
		return entry_path
	var directory := Core.globalize(manifest_path).get_base_dir()
	var candidate := directory.path_join(entry_path).simplify_path()
	if FileAccess.file_exists(candidate):
		return candidate
	var kind_directory := "nodes" if entry.get("kind", "") == "node" else "resources"
	return directory.path_join(kind_directory).path_join(entry_path.get_file()).simplify_path()


func _release_object(object: Object) -> void:
	if object != null and not object is RefCounted:
		object.free()


func _fail(message: String) -> void:
	printerr("GODOT_DEV_BUILTIN_DERIVE %s" % message)
	quit(1)
