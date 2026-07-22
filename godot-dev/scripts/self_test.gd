extends SceneTree

const Core := preload("contract_core.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var version_error := Core.require_engine_47()
	if not version_error.is_empty():
		_fail(version_error)
		return
	var directory_error := Core.ensure_parent_directory("user://godot-dev/self-test/resource.tres")
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("无法创建自测目录。")
		return
	if not _test_resources():
		return
	if not await _test_scenes():
		return
	if not _write_contract_fixtures():
		return
	print("godot-dev 自测通过：Godot %s。" % Core.engine_version())
	quit(0)


func _test_resources() -> bool:
	var resource := Resource.new()
	resource.set_meta("godot_dev", "ok")
	for resource_path in ["user://godot-dev/self-test/resource.tres", "user://godot-dev/self-test/resource.res"]:
		var resource_error := ResourceSaver.save(resource, resource_path)
		var loaded := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if resource_error != OK or loaded == null or loaded.get_meta("godot_dev", "") != "ok":
			_fail("Resource 保存/加载自测失败：%s。" % resource_path)
			return false
	return true


func _test_scenes() -> bool:
	var node := ColorRect.new()
	node.name = "GodotDevSelfTest"
	node.color = Color("2f9e44")
	node.size = Vector2(320, 180)
	var child := Node.new()
	child.name = "Child"
	node.add_child(child)
	child.owner = node
	child.renamed.connect(node.queue_redraw, CONNECT_PERSIST)
	var packed := PackedScene.new()
	if packed.pack(node) != OK:
		node.free()
		_fail("PackedScene.pack 自测失败。")
		return false
	for scene_path in ["user://godot-dev/self-test/scene.tscn", "user://godot-dev/self-test/scene.scn"]:
		var scene_error := ResourceSaver.save(packed, scene_path)
		if scene_error != OK:
			node.free()
			_fail("PackedScene 保存自测失败：%s。" % scene_path)
			return false
	node.free()
	for scene_path in ["user://godot-dev/self-test/scene.tscn", "user://godot-dev/self-test/scene.scn"]:
		var loaded := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		if loaded == null or not loaded.can_instantiate():
			_fail("PackedScene 加载自测失败：%s。" % scene_path)
			return false
		var instance := loaded.instantiate() as ColorRect
		if instance == null:
			_fail("PackedScene 实例化自测失败：%s。" % scene_path)
			return false
		root.add_child(instance)
		await process_frame
		await process_frame
		var loaded_child := instance.get_node_or_null("Child")
		if loaded_child == null or not loaded_child.renamed.is_connected(instance.queue_redraw):
			root.remove_child(instance)
			instance.free()
			_fail("PackedScene 持久 Signal 连接自测失败：%s。" % scene_path)
			return false
		root.remove_child(instance)
		instance.free()
	return true


func _write_contract_fixtures() -> bool:
	var contract := Core.builtin_contract(&"Resource", "resource")
	if contract["contract_hash"] != Core.contract_hash(contract):
		_fail("契约哈希自测失败。")
		return false
	var fixture_root := "user://godot-dev/self-test/contracts"
	if Core.write_contract(fixture_root.path_join("valid.resource-contract.json"), contract) != OK:
		_fail("有效契约样本写入失败。")
		return false

	var invalid_hash := contract.duplicate(true)
	invalid_hash["type_name"] = "ChangedAfterHash"
	if Core.write_json(fixture_root.path_join("invalid-hash.resource-contract.json"), invalid_hash) != OK:
		_fail("错误哈希契约样本写入失败。")
		return false

	var invalid_engine := contract.duplicate(true)
	invalid_engine["engine_build_hash"] = "different-build"
	Core.finalize_contract(invalid_engine)
	if Core.write_json(fixture_root.path_join("invalid-engine.resource-contract.json"), invalid_engine) != OK:
		_fail("错误引擎身份契约样本写入失败。")
		return false

	var invalid_direct := contract.duplicate(true)
	invalid_direct["authoring_mode"] = "direct_text"
	invalid_direct["status"] = "cataloged"
	invalid_direct["validation"]["independent_text"] = false
	invalid_direct["serialization"]["minimal_text"] = ""
	Core.finalize_contract(invalid_direct)
	if Core.write_json(fixture_root.path_join("invalid-direct.resource-contract.json"), invalid_direct) != OK:
		_fail("未验证直接文本契约样本写入失败。")
		return false

	var invalid_third_party := contract.duplicate(true)
	invalid_third_party["scope"] = "third-party"
	invalid_third_party.erase("package_id")
	invalid_third_party.erase("package_version")
	Core.finalize_contract(invalid_third_party)
	if Core.write_json(fixture_root.path_join("invalid-third-party.resource-contract.json"), invalid_third_party) != OK:
		_fail("第三方字段缺失契约样本写入失败。")
		return false

	var stale_source := contract.duplicate(true)
	stale_source["scope"] = "project"
	stale_source["source_path"] = "res://custom_resource.gd"
	stale_source["source_hash"] = "0".repeat(64)
	Core.finalize_contract(stale_source)
	if Core.write_json(fixture_root.path_join("stale-source.resource-contract.json"), stale_source) != OK:
		_fail("源码失效契约样本写入失败。")
		return false

	var malformed_path := Core.globalize(fixture_root.path_join("malformed.resource-contract.json"))
	var malformed_file := FileAccess.open(malformed_path, FileAccess.WRITE)
	if malformed_file == null:
		_fail("畸形 JSON 契约样本写入失败。")
		return false
	malformed_file.store_string("{\n")
	malformed_file.close()
	if not _write_valid_direct_contracts(fixture_root):
		return false
	return true


func _write_valid_direct_contracts(fixture_root: String) -> bool:
	var resource_sample_path := "res://custom_resource_direct.tres"
	var node_sample_path := "res://custom_node_direct.tscn"
	if not FileAccess.file_exists(Core.globalize(resource_sample_path)) or not FileAccess.file_exists(Core.globalize(node_sample_path)):
		return true

	var resource := ResourceLoader.load(resource_sample_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource == null:
		_fail("有效 direct_text Resource 样本加载失败。")
		return false
	var resource_source := "res://custom_resource.gd"
	var resource_contract := Core.builtin_contract(&"Resource", "resource")
	resource_contract["contract_id"] = "project:resource:GodotDevFixtureResource:direct-text-test"
	resource_contract["type_name"] = "GodotDevFixtureResource"
	resource_contract["scope"] = "project"
	resource_contract["source_path"] = resource_source
	resource_contract["source_hash"] = Core.source_hash(resource_source)
	resource_contract["inheritance_chain"] = ["GodotDevFixtureResource", "Resource", "RefCounted", "Object"]
	resource_contract["authoring_mode"] = "direct_text"
	resource_contract["properties"] = Core.property_entries_from_object(resource)
	resource_contract["serialization"] = {
		"format": "tres",
		"minimal_text": Core.read_text(resource_sample_path),
		"property_text_examples": {
			"mode": "mode = 1",
			"tags": "tags = Array[String]([\"alpha\", \"beta\"])",
			"title": "title = \"独立文本资源\"",
			"weight": "weight = 73",
		},
		"notes": ["由独立文本样本完成加载、值比较和往返保存。"],
	}
	resource_contract["validation"] = {
		"save_reload": true,
		"independent_text": true,
		"notes": [resource_sample_path],
	}
	resource_contract["status"] = "validated"
	Core.finalize_contract(resource_contract)
	if Core.write_contract(fixture_root.path_join("valid-direct.resource-contract.json"), resource_contract) != OK:
		_fail("有效 direct_text Resource 契约写入失败。")
		return false

	var packed := ResourceLoader.load(node_sample_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var instance := packed.instantiate() if packed != null and packed.can_instantiate() else null
	if instance == null:
		_fail("有效 direct_text Node 样本加载失败。")
		return false
	var node_source := "res://custom_node.gd"
	var node_contract := Core.builtin_contract(&"Node", "node")
	node_contract["contract_id"] = "project:node:GodotDevFixtureNode:direct-text-test"
	node_contract["type_name"] = "GodotDevFixtureNode"
	node_contract["scope"] = "project"
	node_contract["source_path"] = node_source
	node_contract["source_hash"] = Core.source_hash(node_source)
	node_contract["inheritance_chain"] = ["GodotDevFixtureNode", "Node", "Object"]
	node_contract["authoring_mode"] = "direct_text"
	node_contract["properties"] = Core.property_entries_from_object(instance)
	node_contract["signals"] = Core.signal_entries_from_object(instance)
	node_contract["serialization"] = {
		"format": "tscn-node",
		"minimal_text": Core.read_text(node_sample_path),
		"property_text_examples": {"target_path": "target_path = NodePath(\"Child\")"},
		"notes": ["由独立文本样本完成加载、实例化和 SceneTree 验证。"],
	}
	node_contract["validation"] = {
		"save_reload": true,
		"independent_text": true,
		"notes": [node_sample_path],
	}
	node_contract["status"] = "validated"
	Core.finalize_contract(node_contract)
	instance.free()
	if Core.write_contract(fixture_root.path_join("valid-direct.node-contract.json"), node_contract) != OK:
		_fail("有效 direct_text Node 契约写入失败。")
		return false
	return true


func _fail(message: String) -> void:
	printerr("GODOT_DEV_SELF_TEST %s" % message)
	quit(1)
