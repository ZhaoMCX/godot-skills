extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var resource := ResourceLoader.load("res://custom_resource_direct.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource == null:
		_fail("独立文本 Resource 无法加载。")
		return
	if resource.get("title") != "独立文本资源":
		_fail("独立文本 Resource 的 title 不匹配。")
		return
	if resource.get("mode") != 1 or resource.get("weight") != 73:
		_fail("独立文本 Resource 的枚举或范围整数不匹配。")
		return
	var tags: Array = resource.get("tags")
	if tags != ["alpha", "beta"] or not tags.is_typed() or tags.get_typed_builtin() != TYPE_STRING:
		_fail("独立文本 Resource 的 Array[String] 不匹配。")
		return

	var packed := ResourceLoader.load("res://custom_node_direct.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null or not packed.can_instantiate():
		_fail("独立文本 Node 场景无法加载。")
		return
	var instance := packed.instantiate()
	if instance == null or instance.get_script() == null:
		_fail("独立文本 Node 脚本没有恢复。")
		return
	if instance.get("target_path") != NodePath("Child") or instance.get_node_or_null("Child") == null:
		instance.free()
		_fail("独立文本 NodePath 或子节点不匹配。")
		return
	root.add_child(instance)
	await process_frame
	await process_frame
	root.remove_child(instance)
	instance.free()
	print("独立文本 Resource/Node 验证通过。")
	quit(0)


func _fail(message: String) -> void:
	printerr("GODOT_DEV_DIRECT_TEXT %s" % message)
	quit(1)
