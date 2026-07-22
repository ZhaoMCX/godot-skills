extends SceneTree

func _init() -> void:
	var auditor := ProjectSettings.globalize_path("res://").path_join("../../scripts/audit_scene.gd").simplify_path()
	var valid_args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", auditor, "--"]
	for path in ["res://scene_composition_base.tscn", "res://scene_composition_inherited.tscn", "res://scene_instance_host.tscn", "res://runtime_contexts.tscn", "res://render_context.tscn"]:
		valid_args.append_array(["--file", path])
	valid_args.append("--strict")
	if _execute(valid_args) != 0:
		_fail("有效复杂场景审计失败。")
		return
	var invalid_path := "user://godot-dev/self-test/invalid-node-path.tscn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(invalid_path).get_base_dir())
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	if file == null:
		_fail("无法创建无效 NodePath 场景。")
		return
	file.store_string("""[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scene_semantics.gd" id="1"]

[node name="InvalidNodePath" type="Node"]

[node name="Probe" type="Node" parent="."]
script = ExtResource("1")
target_path = NodePath("../Missing")
""")
	file.close()
	if _execute(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", auditor, "--", "--file", invalid_path, "--strict"]) == 0:
		_fail("无效 NodePath 场景未被拒绝。")
		return
	print("复杂场景审计测试通过。")
	quit(0)


func _execute(arguments: PackedStringArray) -> int:
	var output := []
	return OS.execute(OS.get_executable_path(), arguments, output, true, false)


func _fail(message: String) -> void:
	printerr("GODOT_DEV_SCENE_TEST %s" % message)
	quit(1)
