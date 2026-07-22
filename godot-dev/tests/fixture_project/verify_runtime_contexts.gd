extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://runtime_contexts.tscn") as PackedScene
	var instance := packed.instantiate() if packed != null else null
	if instance == null:
		_fail("运行上下文场景无法实例化。")
		return
	root.add_child(instance)
	await process_frame
	await process_frame
	var skeleton := instance.get_node_or_null("SkeletonContext/Skeleton2D") as Skeleton2D
	if skeleton == null or skeleton.get_bone_count() != 2:
		_cleanup(instance)
		_fail("Skeleton2D/Bone2D 上下文不完整。")
		return
	var spawner := instance.get_node_or_null("MultiplayerContext/MultiplayerSpawner") as MultiplayerSpawner
	if spawner == null or spawner.spawn_path != NodePath("../SpawnRoot"):
		_cleanup(instance)
		_fail("MultiplayerSpawner 上下文不完整。")
		return
	var tile_map := instance.get_node_or_null("TileMapContext/TileMapLayer") as TileMapLayer
	if tile_map == null or tile_map.tile_set == null:
		_cleanup(instance)
		_fail("TileMapLayer/TileSet 上下文不完整。")
		return
	_cleanup(instance)

	var base := load("res://scene_composition_base.tscn") as PackedScene
	var first := base.instantiate()
	var second := base.instantiate()
	var first_resource: Resource = first.get_node("SignalTarget").local_data
	var second_resource: Resource = second.get_node("SignalTarget").local_data
	if first_resource == second_resource:
		first.free()
		second.free()
		_fail("resource_local_to_scene 没有为双实例复制资源。")
		return
	first.free()
	second.free()
	print("运行上下文测试通过。")
	quit(0)


func _cleanup(instance: Node) -> void:
	root.remove_child(instance)
	instance.free()


func _fail(message: String) -> void:
	printerr("GODOT_DEV_CONTEXT_TEST %s" % message)
	quit(1)
