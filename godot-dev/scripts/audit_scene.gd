extends SceneTree

const Core := preload("contract_core.gd")

var _contracts_by_type := {}
var _strict := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var version_error := Core.require_engine_47()
	if not version_error.is_empty():
		_fail(version_error)
		return
	var args := Core.parse_args(OS.get_cmdline_user_args())
	var files := _argument_values(args.get("file", []))
	if files.is_empty():
		_fail("需要至少一个 --file res://scene.tscn。")
		return
	_strict = bool(args.get("strict", false))
	var manifests := _argument_values(args.get("manifest", []))
	if manifests.is_empty():
		manifests.append(get_script().resource_path.get_base_dir().path_join("../references/contracts/godot-4.7/manifest.json").simplify_path())
	_load_contracts(manifests)

	var scenes := []
	var failure_count := 0
	for path in files:
		var result := await _audit_one(path)
		scenes.append(result)
		failure_count += result["errors"].size()
		for finding in result["errors"]:
			printerr("GODOT_DEV_SCENE %s：%s" % [path, finding])
		for warning in result["warnings"]:
			print("GODOT_DEV_SCENE_WARNING %s：%s" % [path, warning])

	var report := {
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"status": "passed" if failure_count == 0 else "failed",
		"scenes": scenes,
	}
	var report_path := String(args.get("report", "user://godot-dev/reports/scene-audit.json"))
	if Core.write_json(report_path, report) != OK:
		_fail("无法写入场景审计报告：%s。" % report_path)
		return
	print("场景审计完成：%d 个场景，%d 项失败。" % [files.size(), failure_count])
	quit(0 if failure_count == 0 else 1)


func _audit_one(path: String) -> Dictionary:
	var result := {
		"path": path,
		"status": "failed",
		"errors": [],
		"warnings": [],
		"metrics": {},
	}
	if path.get_extension().to_lower() != "tscn" and path.get_extension().to_lower() != "scn":
		result["errors"].append("场景审计只接受 .tscn 或 .scn。")
		return result
	var content := Core.read_text(path) if path.get_extension().to_lower() == "tscn" else ""
	if path.get_extension().to_lower() == "tscn":
		result["metrics"].merge(_text_metrics(content), true)
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null or not packed.can_instantiate():
		result["errors"].append("无法加载或实例化 PackedScene。")
		return result
	var instance := packed.instantiate()
	var comparison := packed.instantiate()
	if instance == null or comparison == null:
		if instance != null:
			instance.free()
		if comparison != null:
			comparison.free()
		result["errors"].append("PackedScene 实例为空。")
		return result

	var started := Time.get_ticks_usec()
	root.add_child(instance)
	await process_frame
	await process_frame
	result["metrics"].merge(_runtime_metrics(instance, started), true)
	_validate_tree(instance, result)
	_validate_local_resources(instance, comparison, result)
	_validate_animations(instance, result)
	root.remove_child(instance)
	instance.free()
	comparison.free()
	result["status"] = "passed" if result["errors"].is_empty() else "failed"
	return result


func _validate_tree(scene_root: Node, result: Dictionary) -> void:
	var unique_names := {}
	for node in _all_nodes(scene_root):
		if node != scene_root and node.owner == null:
			result["warnings"].append("节点没有 owner：%s。" % scene_root.get_path_to(node))
		if node.is_unique_name_in_owner():
			var owner_key := str(node.owner.get_instance_id() if node.owner != null else scene_root.get_instance_id())
			var key := "%s:%s" % [owner_key, node.name]
			if unique_names.has(key):
				result["errors"].append("同一 owner 范围内唯一名称重复：%s。" % node.name)
			unique_names[key] = true
		_validate_node_paths(node, scene_root, result)
		_validate_connections(node, result)


func _validate_node_paths(node: Node, scene_root: Node, result: Dictionary) -> void:
	var constraints := _path_constraints_for(node)
	for property in node.get_property_list():
		if int(property.get("type", TYPE_NIL)) != TYPE_NODE_PATH:
			continue
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name := String(property.get("name", ""))
		var path: NodePath = node.get(property_name)
		if path.is_empty():
			continue
		var resolution := String(constraints.get(property_name, "unclassified"))
		if resolution == "runtime" or resolution == "external":
			result["warnings"].append("NodePath 由%s上下文解析：%s.%s=%s。" % [resolution, scene_root.get_path_to(node), property_name, path])
			continue
		var node_part := NodePath(String(path).split(":", true, 1)[0])
		if node.get_node_or_null(node_part) != null:
			continue
		var message := "NodePath 无法在保存树解析：%s.%s=%s" % [scene_root.get_path_to(node), property_name, path]
		if resolution == "scene_tree" or _strict:
			result["errors"].append(message + "。")
		else:
			result["warnings"].append(message + "；契约未分类。")


func _validate_connections(node: Node, result: Dictionary) -> void:
	for signal_info in node.get_signal_list():
		var signal_name := StringName(signal_info.get("name", ""))
		for connection in node.get_signal_connection_list(signal_name):
			if (int(connection.get("flags", 0)) & CONNECT_PERSIST) == 0:
				continue
			var callable: Callable = connection.get("callable", Callable())
			if not callable.is_valid() or callable.get_object() == null or not callable.get_object().has_method(callable.get_method()):
				result["errors"].append("持久 Signal 目标无效：%s.%s。" % [node.name, signal_name])


func _validate_local_resources(first: Node, second: Node, result: Dictionary) -> void:
	for first_node in _all_nodes(first):
		var relative := first.get_path_to(first_node)
		var second_node := second.get_node_or_null(relative)
		if second_node == null:
			continue
		for property in first_node.get_property_list():
			if int(property.get("type", TYPE_NIL)) != TYPE_OBJECT:
				continue
			var property_name := String(property.get("name", ""))
			var resource := first_node.get(property_name) as Resource
			if resource == null or not resource.resource_local_to_scene:
				continue
			var other := second_node.get(property_name) as Resource
			if other == null or is_same(resource, other):
				result["errors"].append("resource_local_to_scene 未产生实例独立资源：%s.%s。" % [relative, property_name])


func _validate_animations(scene_root: Node, result: Dictionary) -> void:
	for node in _all_nodes(scene_root):
		if node is AnimationTree:
			var player_path: NodePath = node.anim_player
			if not player_path.is_empty() and node.get_node_or_null(player_path) == null:
				result["errors"].append("AnimationTree.anim_player 无法解析：%s。" % player_path)
		if not node is AnimationPlayer:
			continue
		var animation_root := node.get_node_or_null(node.root_node)
		if animation_root == null:
			result["errors"].append("AnimationPlayer.root_node 无法解析：%s。" % node.root_node)
			continue
		for library_name in node.get_animation_library_list():
			var library: AnimationLibrary = node.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				var animation: Animation = library.get_animation(animation_name)
				for track_index in animation.get_track_count():
					var track_path: NodePath = animation.track_get_path(track_index)
					var node_part := NodePath(String(track_path).split(":", true, 1)[0])
					if not node_part.is_empty() and animation_root.get_node_or_null(node_part) == null:
						result["errors"].append("动画轨道路径无法解析：%s/%s -> %s。" % [library_name, animation_name, track_path])


func _path_constraints_for(node: Node) -> Dictionary:
	var type_names := [node.get_class()]
	var script := node.get_script() as Script
	if script != null and not String(script.get_global_name()).is_empty():
		type_names.push_front(String(script.get_global_name()))
	for type_name in type_names:
		if not _contracts_by_type.has(type_name):
			continue
		var result := {}
		for constraint in _contracts_by_type[type_name].get("path_constraints", []):
			result[String(constraint.get("property", ""))] = String(constraint.get("resolution", "scene_tree"))
		return result
	return {}


func _load_contracts(manifests: Array[String]) -> void:
	for manifest_path in manifests:
		var manifest_value: Variant = Core.read_json(manifest_path)
		if not manifest_value is Dictionary:
			continue
		for entry in manifest_value.get("contracts", []):
			var contract_value: Variant = Core.read_json(String(entry.get("path", "")))
			if contract_value is Dictionary:
				_contracts_by_type[String(contract_value.get("type_name", ""))] = contract_value


func _text_metrics(content: String) -> Dictionary:
	var metrics := {"external_resources": 0, "sub_resources": 0, "saved_nodes": 0, "saved_connections": 0, "editable_instances": 0}
	for line in content.split("\n"):
		if line.begins_with("[ext_resource "):
			metrics["external_resources"] += 1
		elif line.begins_with("[sub_resource "):
			metrics["sub_resources"] += 1
		elif line.begins_with("[node "):
			metrics["saved_nodes"] += 1
		elif line.begins_with("[connection "):
			metrics["saved_connections"] += 1
		elif line.begins_with("[editable path="):
			metrics["editable_instances"] += 1
	return metrics


func _runtime_metrics(scene_root: Node, started_usec: int) -> Dictionary:
	var nodes := _all_nodes(scene_root)
	var max_depth := 0
	for node in nodes:
		var depth := 0
		var current := node
		while current != scene_root and current != null:
			depth += 1
			current = current.get_parent()
		max_depth = maxi(max_depth, depth)
	return {"runtime_nodes": nodes.size(), "max_depth": max_depth, "instantiation_usec": Time.get_ticks_usec() - started_usec}


func _all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_all_nodes(child))
	return result


func _argument_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	elif value != null and String(value) != "":
		result.append(String(value))
	return result


func _fail(message: String) -> void:
	printerr("GODOT_DEV_SCENE %s" % message)
	quit(1)
