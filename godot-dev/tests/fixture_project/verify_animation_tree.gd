extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--generate"):
		if not _generate_reference_assets():
			quit(1)
			return
		print("AnimationTree API 参考资产生成完成。")
		quit(0)
		return
	if args.has("--verify-direct"):
		if not await _verify_direct_assets():
			quit(1)
			return
		print("AnimationTree 独立文本结构与运行行为验证通过。")
		quit(0)
		return
	_fail("需要 --generate 或 --verify-direct。")


func _verify_direct_assets() -> bool:
	var state_machine := _load_resource("res://animation_tree_state_machine.tres") as AnimationNodeStateMachine
	if state_machine == null or not state_machine.has_node(&"idle") or not state_machine.has_node(&"run"):
		_fail("独立文本状态机缺少 idle/run 状态。")
		return false
	if not state_machine.has_transition(&"idle", &"run") or not state_machine.has_transition(&"run", &"idle"):
		_fail("独立文本状态机缺少双向 Transition。")
		return false
	var idle_transition := _find_transition(state_machine, &"idle", &"run")
	if idle_transition == null or not is_equal_approx(idle_transition.xfade_time, 0.1):
		_fail("状态机 Transition 的 xfade_time 不匹配。")
		return false

	var blend_tree := _load_resource("res://animation_tree_blend_tree.tres") as AnimationNodeBlendTree
	if blend_tree == null or not blend_tree.has_node(&"idle") or not blend_tree.has_node(&"output"):
		_fail("独立文本 BlendTree 节点不完整。")
		return false
	var connections: Array = blend_tree.get("node_connections")
	if connections != [&"output", 0, &"idle"]:
		_fail("独立文本 BlendTree 的 output 连接不匹配。")
		return false

	var blend_space_1d := _load_resource("res://animation_tree_blend_space_1d.tres") as AnimationNodeBlendSpace1D
	if blend_space_1d == null or blend_space_1d.get_blend_point_count() != 2:
		_fail("独立文本 BlendSpace1D 点数量不匹配。")
		return false
	if not is_equal_approx(blend_space_1d.get_blend_point_position(0), 0.0) or not is_equal_approx(blend_space_1d.get_blend_point_position(1), 1.0):
		_fail("独立文本 BlendSpace1D 点位置不匹配。")
		return false

	var blend_space_2d := _load_resource("res://animation_tree_blend_space_2d.tres") as AnimationNodeBlendSpace2D
	if blend_space_2d == null or blend_space_2d.get_blend_point_count() != 3 or blend_space_2d.get_triangle_count() != 1:
		_fail("独立文本 BlendSpace2D 点或三角形数量不匹配。")
		return false
	if blend_space_2d.get_blend_point_position(1) != Vector2(1, 0):
		_fail("独立文本 BlendSpace2D 点位置不匹配。")
		return false

	for resource_path in [
		"res://animation_tree_state_machine.tres",
		"res://animation_tree_blend_tree.tres",
		"res://animation_tree_blend_space_1d.tres",
		"res://animation_tree_blend_space_2d.tres",
	]:
		var resource := _load_resource(resource_path)
		var roundtrip_path := "user://godot-dev/animation-tree-roundtrip/%s" % resource_path.get_file()
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(roundtrip_path).get_base_dir()) != OK:
			_fail("无法创建 AnimationTree 往返目录。")
			return false
		if ResourceSaver.save(resource, roundtrip_path) != OK:
			_fail("AnimationTree 资源往返失败：%s。" % resource_path)
			return false
		if resource_path.ends_with("animation_tree_blend_space_2d.tres") and not _normalize_blend_space_2d_triangle_order(roundtrip_path):
			return false
		if _load_resource(roundtrip_path) == null:
			_fail("AnimationTree 资源重载失败：%s。" % resource_path)
			return false

	var packed := ResourceLoader.load("res://animation_tree_direct.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var instance := packed.instantiate() if packed != null and packed.can_instantiate() else null
	if instance == null:
		_fail("AnimationTree 独立文本场景无法实例化。")
		return false
	root.add_child(instance)
	await process_frame
	await process_frame
	var actor := instance.get_node_or_null("Actor") as Node2D
	var player := instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var tree := instance.get_node_or_null("AnimationTree") as AnimationTree
	if actor == null or player == null or tree == null or not player.has_animation(&"idle") or not player.has_animation(&"run"):
		root.remove_child(instance)
		instance.free()
		_fail("AnimationTree 场景节点或 AnimationLibrary 不完整。")
		return false
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if playback == null:
		root.remove_child(instance)
		instance.free()
		_fail("AnimationTree 状态机 playback 参数不存在。")
		return false
	playback.start(&"idle")
	tree.advance(0.0)
	tree.advance(0.5)
	var idle_position := actor.position.x
	if playback.get_current_node() != &"idle" or idle_position <= 0.0 or idle_position >= 10.0:
		root.remove_child(instance)
		instance.free()
		_fail("AnimationTree idle 状态或动画推进不正确：current=%s position=%s。" % [playback.get_current_node(), idle_position])
		return false
	playback.travel(&"run")
	tree.advance(0.11)
	var travel_current := playback.get_current_node()
	if travel_current != &"run":
		root.remove_child(instance)
		instance.free()
		_fail("AnimationTree travel 没有进入 run：current=%s。" % travel_current)
		return false
	playback.start(&"run")
	tree.advance(0.0)
	tree.advance(0.5)
	var run_current := playback.get_current_node()
	var run_position := actor.position.x
	if run_current != &"run" or run_position <= idle_position:
		root.remove_child(instance)
		instance.free()
		_fail("AnimationTree run 状态切换或动画推进不正确：current=%s position=%s idle=%s。" % [run_current, run_position, idle_position])
		return false
	root.remove_child(instance)
	instance.free()
	return true


func _load_resource(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)


func _find_transition(state_machine: AnimationNodeStateMachine, from: StringName, to: StringName) -> AnimationNodeStateMachineTransition:
	for index in state_machine.get_transition_count():
		if state_machine.get_transition_from(index) == from and state_machine.get_transition_to(index) == to:
			return state_machine.get_transition(index)
	return null


func _normalize_blend_space_2d_triangle_order(path: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		_fail("无法读取 BlendSpace2D 文本：%s。" % path)
		return false
	var lines := Array(file.get_as_text().split("\n"))
	file.close()
	var triangle_line := ""
	var normalized := PackedStringArray()
	for line_value in lines:
		var line := String(line_value)
		if line.begins_with("triangles = "):
			triangle_line = line
		else:
			normalized.append(line)
	if triangle_line.is_empty():
		_fail("BlendSpace2D 文本缺少 triangles 属性：%s。" % path)
		return false
	while not normalized.is_empty() and normalized[normalized.size() - 1].is_empty():
		normalized.remove_at(normalized.size() - 1)
	normalized.append(triangle_line)
	normalized.append("")
	file = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_fail("无法写回 BlendSpace2D 文本：%s。" % path)
		return false
	file.store_string("\n".join(normalized))
	file.close()
	return true


func _generate_reference_assets() -> bool:
	var root_path := "user://godot-dev/animation-tree-reference"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path)) != OK:
		_fail("无法创建 AnimationTree 参考资产目录。")
		return false

	var state_machine := AnimationNodeStateMachine.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = &"run"
	state_machine.add_node(&"idle", idle_node, Vector2(240, 100))
	state_machine.add_node(&"run", run_node, Vector2(440, 100))
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = 0.1
	state_machine.add_transition(&"idle", &"run", transition)
	state_machine.add_transition(&"run", &"idle", transition.duplicate(true))
	if ResourceSaver.save(state_machine, root_path.path_join("animation_tree_state_machine.tres")) != OK:
		_fail("状态机参考资产保存失败。")
		return false

	var blend_tree := AnimationNodeBlendTree.new()
	var blend_idle := AnimationNodeAnimation.new()
	blend_idle.animation = &"idle"
	blend_tree.add_node(&"idle", blend_idle, Vector2(240, 100))
	blend_tree.connect_node(&"output", 0, &"idle")
	if ResourceSaver.save(blend_tree, root_path.path_join("animation_tree_blend_tree.tres")) != OK:
		_fail("BlendTree 参考资产保存失败。")
		return false

	var blend_space_1d := AnimationNodeBlendSpace1D.new()
	var walk_1d := AnimationNodeAnimation.new()
	walk_1d.animation = &"idle"
	var run_1d := AnimationNodeAnimation.new()
	run_1d.animation = &"run"
	blend_space_1d.min_space = 0.0
	blend_space_1d.max_space = 1.0
	blend_space_1d.add_blend_point(walk_1d, 0.0, -1, &"idle")
	blend_space_1d.add_blend_point(run_1d, 1.0, -1, &"run")
	if ResourceSaver.save(blend_space_1d, root_path.path_join("animation_tree_blend_space_1d.tres")) != OK:
		_fail("BlendSpace1D 参考资产保存失败。")
		return false

	var blend_space_2d := AnimationNodeBlendSpace2D.new()
	blend_space_2d.auto_triangles = false
	var idle_2d := AnimationNodeAnimation.new()
	idle_2d.animation = &"idle"
	var run_x := AnimationNodeAnimation.new()
	run_x.animation = &"run"
	var run_y := AnimationNodeAnimation.new()
	run_y.animation = &"run"
	blend_space_2d.min_space = Vector2(-1, -1)
	blend_space_2d.max_space = Vector2(1, 1)
	blend_space_2d.add_blend_point(idle_2d, Vector2.ZERO, -1, &"idle")
	blend_space_2d.add_blend_point(run_x, Vector2(1, 0), -1, &"run_x")
	blend_space_2d.add_blend_point(run_y, Vector2(0, 1), -1, &"run_y")
	blend_space_2d.add_triangle(0, 1, 2)
	var blend_space_2d_path := root_path.path_join("animation_tree_blend_space_2d.tres")
	if ResourceSaver.save(blend_space_2d, blend_space_2d_path) != OK:
		_fail("BlendSpace2D 参考资产保存失败。")
		return false
	if not _normalize_blend_space_2d_triangle_order(blend_space_2d_path):
		return false

	var scene_root := Node2D.new()
	scene_root.name = "AnimationTreeFixture"
	var actor := Node2D.new()
	actor.name = "Actor"
	scene_root.add_child(actor)
	actor.owner = scene_root
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	scene_root.add_child(player)
	player.owner = scene_root
	var library := AnimationLibrary.new()
	var idle_animation := _make_position_animation(Vector2.ZERO, Vector2(10, 0))
	var run_animation := _make_position_animation(Vector2.ZERO, Vector2(100, 0))
	library.add_animation(&"idle", idle_animation)
	library.add_animation(&"run", run_animation)
	player.add_animation_library(&"", library)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = state_machine
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.active = true
	scene_root.add_child(tree)
	tree.owner = scene_root
	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	var save_error := ResourceSaver.save(packed, root_path.path_join("animation_tree_direct.tscn")) if pack_error == OK else pack_error
	scene_root.free()
	if save_error != OK:
		_fail("AnimationTree 场景参考资产保存失败。")
		return false
	return true


func _make_position_animation(from: Vector2, to: Vector2) -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Actor:position"))
	animation.track_insert_key(track, 0.0, from)
	animation.track_insert_key(track, 1.0, to)
	return animation


func _fail(message: String) -> void:
	printerr("GODOT_DEV_ANIMATION_TREE %s" % message)
	quit(1)
