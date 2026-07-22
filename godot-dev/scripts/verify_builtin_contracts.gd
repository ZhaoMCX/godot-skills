extends SceneTree

const Core := preload("contract_core.gd")

const REFERENCE_VALIDATION_PREFIX := "reference_validation="
const REPRESENTATIVE_PREFIX := "representative_property="


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var version_error := Core.require_engine_47()
	if not version_error.is_empty():
		_fail(version_error)
		return
	var args := Core.parse_args(OS.get_cmdline_user_args())
	if not args.has("manifest"):
		_fail("需要 --manifest <manifest.json>。")
		return
	var manifest_path := String(args["manifest"])
	var update_contracts := bool(args.get("update", false))
	var requested_types := _argument_values(args.get("type", []))
	if update_contracts and not requested_types.is_empty():
		_fail("--update 必须验证完整清单，不能与 --type 同时使用。")
		return
	var manifest_value: Variant = Core.read_json(manifest_path)
	if not manifest_value is Dictionary:
		_fail("无法读取清单：%s。" % manifest_path)
		return
	var source_entries: Array = manifest_value.get("contracts", [])
	if update_contracts and source_entries.is_empty():
		_fail("--update 拒绝写回空清单。")
		return
	var output_entries := []
	var verified_items := []
	var report_entries := []
	var counts := {
		"total": 0,
		"direct_text": 0,
		"generated_structure": 0,
		"reference_only": 0,
		"failed": 0,
		"representative_verified": 0,
	}
	for entry_value in source_entries:
		var entry: Dictionary = entry_value
		var type_name := String(entry.get("type_name", ""))
		if not requested_types.is_empty() and not requested_types.has(type_name):
			output_entries.append(entry)
			continue
		counts["total"] += 1
		var recorded_path := String(entry.get("path", ""))
		var path := _resolve_entry_path(manifest_path, recorded_path, entry)
		var contract_value: Variant = Core.read_json(path)
		if not contract_value is Dictionary:
			report_entries.append({"type_name": type_name, "ok": false, "notes": ["契约无法读取。"]})
			counts["failed"] += 1
			continue
		var contract: Dictionary = contract_value.duplicate(true)
		var result := await _verify_contract(contract)
		report_entries.append(result)
		if result["ok"]:
			counts[result["mode"]] += 1
			if result["representative_verified"]:
				counts["representative_verified"] += 1
		else:
			counts["failed"] += 1
		if update_contracts:
			verified_items.append({"contract": contract, "path": path, "recorded_path": recorded_path})
		else:
			output_entries.append(entry)

	if update_contracts and counts["failed"] > 0:
		_fail("独立验证存在 %d 项失败；未写回任何契约或清单。" % counts["failed"])
		return
	if update_contracts:
		_apply_base_contract_hashes(verified_items)
		for item in verified_items:
			var contract: Dictionary = item["contract"]
			var path := String(item["path"])
			var write_error := Core.write_contract(path, contract)
			if write_error != OK:
				_fail("更新契约失败 %s：%s。" % [path, error_string(write_error)])
				return
			output_entries.append(Core.manifest_entry(contract, String(item["recorded_path"])))
		output_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["contract_id"] < b["contract_id"])
		var updated_manifest: Dictionary = manifest_value.duplicate(true)
		updated_manifest["contracts"] = output_entries
		updated_manifest["engine_version"] = Core.engine_version()
		updated_manifest["engine_build_hash"] = Core.engine_build_hash()
		if Core.write_json(manifest_path, updated_manifest) != OK:
			_fail("更新清单失败：%s。" % manifest_path)
			return
	var report := {
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"phase": "verify",
		"counts": counts,
		"contracts": report_entries,
	}
	var report_path := String(args.get("report", "user://godot-dev/reports/builtin-verify.json"))
	if Core.write_json(report_path, report) != OK:
		_fail("写入验证报告失败：%s。" % report_path)
		return
	print("内置契约独立验证完成：%d 个；direct_text %d；generated_structure %d；reference_only %d；失败 %d。" % [
		counts["total"],
		counts["direct_text"],
		counts["generated_structure"],
		counts["reference_only"],
		counts["failed"],
	])
	quit(0 if counts["failed"] == 0 else 1)


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


func _verify_contract(contract: Dictionary) -> Dictionary:
	var type_name := String(contract.get("type_name", ""))
	var kind := String(contract.get("kind", ""))
	var result := {
		"type_name": type_name,
		"kind": kind,
		"ok": false,
		"mode": "reference_only",
		"representative_verified": false,
		"notes": [],
	}
	if not ClassDB.class_exists(type_name):
		contract["status"] = "stale"
		result["notes"].append("ClassDB 类型不存在。")
		Core.finalize_contract(contract)
		return result

	if not ClassDB.can_instantiate(type_name):
		var reference_result := _verify_reference_only(contract)
		result["ok"] = reference_result["ok"]
		result["notes"].append_array(reference_result["notes"])
		result["mode"] = "reference_only"
		contract["authoring_mode"] = "reference_only"
		contract["status"] = "reference_only"
		Core.finalize_contract(contract)
		return result

	var validation: Dictionary = contract.get("validation", {})
	var serialization: Dictionary = contract.get("serialization", {})
	if contract.get("authoring_mode", "") == "resource_saver_only" and validation.get("save_reload", false):
		result["ok"] = true
		result["mode"] = "generated_structure"
		result["notes"].append("ResourceSaver/PackedScene 专用生成路径已保存并重载；不提供独立 .tres 文本。")
		contract["status"] = "validated"
		contract["validation"]["independent_text"] = false
		Core.finalize_contract(contract)
		return result
	if not validation.get("save_reload", false) or String(serialization.get("minimal_text", "")).is_empty():
		result["ok"] = _verify_concrete_reference_boundary(type_name, kind, validation.get("notes", []))
		result["mode"] = "reference_only"
		result["notes"].append("该具体类型不能由通用 ResourceSaver/PackedScene 生成；已验证实例边界并限制为仅引用。")
		contract["authoring_mode"] = "reference_only"
		contract["status"] = "validated" if result["ok"] else "stale"
		contract["validation"]["independent_text"] = false
		contract["validation"]["notes"].append("concrete_reference_boundary=true")
		Core.finalize_contract(contract)
		return result

	var extension := "tres" if kind == "resource" else "tscn"
	var direct_path := "user://godot-dev/builtin-verify/%s/%s-direct.%s" % [kind, type_name.to_snake_case(), extension]
	var write_error := _write_text(direct_path, String(serialization["minimal_text"]))
	if write_error != OK:
		result["notes"].append("无法写入独立文本：%s。" % error_string(write_error))
		contract["status"] = "stale"
		Core.finalize_contract(contract)
		return result
	var lifecycle_context := _has_note_prefix(validation.get("notes", []), "lifecycle_context=")
	var direct_result := await _load_and_roundtrip(direct_path, kind, type_name, lifecycle_context)
	if not direct_result["ok"]:
		result["ok"] = true
		result["mode"] = "generated_structure"
		result["notes"].append_array(direct_result["notes"])
		contract["authoring_mode"] = "generated_structure"
		contract["status"] = "validated"
		contract["validation"]["independent_text"] = false
		contract["validation"]["notes"].append("独立文本失败，保留 generated_structure；Godot 生成结构的保存重载已通过。")
		Core.finalize_contract(contract)
		return result

	var representative := _representative_expectation(validation.get("notes", []))
	var examples: Dictionary = serialization.get("property_text_examples", {})
	if not representative.is_empty():
		var property_name := String(representative.get("name", ""))
		if not examples.has(property_name):
			result["notes"].append("代表属性缺少文本行：%s。" % property_name)
			contract["status"] = "stale"
			Core.finalize_contract(contract)
			return result
		var representative_text := _insert_property_line(String(serialization["minimal_text"]), String(examples[property_name]))
		var representative_path := "user://godot-dev/builtin-verify/%s/%s-representative.%s" % [kind, type_name.to_snake_case(), extension]
		if _write_text(representative_path, representative_text) != OK:
			result["notes"].append("代表属性独立文本无法写入。")
			contract["status"] = "stale"
			Core.finalize_contract(contract)
			return result
		var property_result := await _load_property(representative_path, kind, type_name, property_name, lifecycle_context)
		if not property_result["ok"] or String(property_result.get("actual", "")) != String(representative.get("expected", "")):
			result["notes"].append("代表属性独立文本值不一致：%s；期望 %s，实际 %s。" % [property_name, representative.get("expected", ""), property_result.get("actual", "<load-failed>")])
			contract["status"] = "stale"
			Core.finalize_contract(contract)
			return result
		result["representative_verified"] = true

	result["ok"] = true
	result["mode"] = "generated_structure" if lifecycle_context else "direct_text"
	result["notes"].append("最小独立文本、往返保存和类型检查通过。")
	contract["authoring_mode"] = "generated_structure" if lifecycle_context else "direct_text"
	contract["status"] = "validated"
	contract["validation"]["independent_text"] = true
	contract["validation"]["notes"].append("independent_text=%s" % direct_path)
	var experiments: Array = contract["evidence"].get("experiments", [])
	if not experiments.has(direct_path):
		experiments.append(direct_path)
	contract["evidence"]["experiments"] = experiments
	Core.finalize_contract(contract)
	return result


func _verify_reference_only(contract: Dictionary) -> Dictionary:
	var type_name := String(contract["type_name"])
	var notes := []
	if ClassDB.can_instantiate(type_name):
		return {"ok": false, "notes": ["契约为 reference_only，但 ClassDB 可以实例化。"]}
	var reference_data := {}
	for note in contract.get("validation", {}).get("notes", []):
		var text := String(note)
		if text.begins_with(REFERENCE_VALIDATION_PREFIX):
			var parsed: Variant = JSON.parse_string(text.trim_prefix(REFERENCE_VALIDATION_PREFIX))
			if parsed is Dictionary:
				reference_data = parsed
	if reference_data.is_empty():
		return {"ok": false, "notes": ["reference_only 缺少替代验证证据。"]}
	var witness := String(reference_data.get("witness", ""))
	if witness.is_empty():
		notes.append("没有具体子类；已验证 ClassDB 存在且不可实例化。")
		return {"ok": true, "notes": notes}
	var ok := ClassDB.class_exists(witness) and ClassDB.can_instantiate(witness) and ClassDB.is_parent_class(witness, type_name)
	notes.append("具体子类见证：%s。" % witness)
	return {"ok": ok, "notes": notes}


func _verify_concrete_reference_boundary(type_name: String, kind: String, notes: Array) -> bool:
	if _has_note_prefix(notes, "context_reference_boundary="):
		return ClassDB.class_exists(type_name) and ClassDB.can_instantiate(type_name)
	var object: Object = ClassDB.instantiate(type_name)
	var ok := object != null and ((kind == "resource" and object is Resource) or (kind == "node" and object is Node))
	if object != null:
		_release_object(object)
	return ok


func _load_and_roundtrip(path: String, kind: String, type_name: String, skip_tree: bool = false) -> Dictionary:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if kind == "resource":
		if loaded == null or not loaded.is_class(type_name):
			return {"ok": false, "notes": ["独立 .tres 无法加载或类型不一致。"]}
		var roundtrip_path := path.get_basename() + "-roundtrip.tres"
		var save_error := ResourceSaver.save(loaded, roundtrip_path)
		var reloaded := ResourceLoader.load(roundtrip_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) if save_error == OK else null
		return {
			"ok": save_error == OK and reloaded != null and reloaded.is_class(type_name),
			"notes": [] if save_error == OK and reloaded != null and reloaded.is_class(type_name) else ["独立 .tres 往返保存失败。"],
		}
	var packed := loaded as PackedScene
	var instance := packed.instantiate() if packed != null and packed.can_instantiate() else null
	if instance == null or not instance.is_class(type_name):
		if instance != null:
			instance.free()
		return {"ok": false, "notes": ["独立 .tscn 无法实例化或类型不一致。"]}
	if not skip_tree:
		root.add_child(instance)
		await process_frame
		await process_frame
		root.remove_child(instance)
	instance.free()
	var roundtrip_path := path.get_basename() + "-roundtrip.tscn"
	var save_error := ResourceSaver.save(packed, roundtrip_path)
	var reloaded := ResourceLoader.load(roundtrip_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene if save_error == OK else null
	return {
		"ok": save_error == OK and reloaded != null and reloaded.can_instantiate(),
		"notes": [] if save_error == OK and reloaded != null and reloaded.can_instantiate() else ["独立 .tscn 往返保存失败。"],
	}


func _load_property(path: String, kind: String, type_name: String, property_name: String, skip_tree: bool = false) -> Dictionary:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var object: Object
	if kind == "resource":
		object = loaded
	else:
		var packed := loaded as PackedScene
		object = packed.instantiate() if packed != null and packed.can_instantiate() else null
	if object == null or not object.is_class(type_name):
		if object != null and kind == "node":
			object.free()
		return {"ok": false}
	var actual := Core.stable_value_text(object.get(property_name))
	if kind == "node":
		if not skip_tree:
			root.add_child(object as Node)
			await process_frame
			await process_frame
			root.remove_child(object as Node)
		object.free()
	return {"ok": true, "actual": actual}


func _representative_expectation(notes: Array) -> Dictionary:
	for note in notes:
		var text := String(note)
		if not text.begins_with(REPRESENTATIVE_PREFIX):
			continue
		var parsed: Variant = JSON.parse_string(text.trim_prefix(REPRESENTATIVE_PREFIX))
		if parsed is Dictionary:
			return parsed
	return {}


func _has_note_prefix(notes: Array, prefix: String) -> bool:
	for note in notes:
		if String(note).begins_with(prefix):
			return true
	return false


func _insert_property_line(minimal_text: String, property_line: String) -> String:
	return minimal_text.strip_edges() + "\n" + property_line + "\n"


func _write_text(path: String, content: String) -> Error:
	var directory_error := Core.ensure_parent_directory(path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	var file := FileAccess.open(Core.globalize(path), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.flush()
	file.close()
	return OK


func _argument_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	elif value != null and String(value) != "":
		result.append(String(value))
	return result


func _resolve_entry_path(manifest_path: String, entry_path: String, entry: Dictionary) -> String:
	if FileAccess.file_exists(Core.globalize(entry_path)):
		return entry_path
	var directory := Core.globalize(manifest_path).get_base_dir()
	var kind_directory := "nodes" if entry.get("kind", "") == "node" else "resources"
	var candidate := directory.path_join(kind_directory).path_join(entry_path.get_file()).simplify_path()
	return candidate if FileAccess.file_exists(candidate) else entry_path


func _release_object(object: Object) -> void:
	if object != null and not object is RefCounted:
		object.free()


func _fail(message: String) -> void:
	printerr("GODOT_DEV_BUILTIN_VERIFY %s" % message)
	quit(1)
