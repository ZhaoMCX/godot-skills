extends SceneTree

func _init() -> void:
	var report_path := "user://godot-dev/reports/dependency-test.json"
	var collector := ProjectSettings.globalize_path("res://").path_join("../../scripts/collect_dependencies.gd").simplify_path()
	var output := []
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", collector, "--", "--changed", "res://scene_semantics.gd", "--report", report_path], output, true, false)
	if exit_code != 0:
		_fail("依赖收集器执行失败。")
		return
	var report: Variant = _read_json(report_path)
	if not report is Dictionary:
		_fail("依赖报告无法读取。")
		return
	var affected: Array = report.get("affected", [])
	for expected in ["res://scene_composition_base.tscn", "res://scene_composition_inherited.tscn", "res://scene_instance_host.tscn"]:
		if not affected.has(expected):
			_fail("影响闭包缺少 %s。" % expected)
			return
	if report.get("dynamic_references", []).is_empty():
		_fail("动态 load 覆盖缺口没有被报告。")
		return
	print("依赖闭包测试通过：%d 个受影响文件。" % affected.size())
	quit(0)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else null


func _fail(message: String) -> void:
	printerr("GODOT_DEV_DEPENDENCY_TEST %s" % message)
	quit(1)
