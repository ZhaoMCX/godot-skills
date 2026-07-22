extends SceneTree

func _init() -> void:
	var report_path := "user://godot-dev/reports/project-runner-test.json"
	var runner := ProjectSettings.globalize_path("res://").path_join("../../scripts/verify_project.gd").simplify_path()
	var output := []
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", runner, "--", "--changed", "res://scene_semantics.gd", "--profile", "res://validation_profile.json", "--report", report_path], output, true, false)
	if exit_code != 0:
		_fail("统一项目验证入口失败：\n%s" % "\n".join(output))
		return
	var report: Variant = _read_json(report_path)
	if not report is Dictionary or report.get("status", "") != "passed":
		_fail("统一报告不是 passed。")
		return
	var statuses := {}
	for check in report.get("checks", []):
		statuses[String(check.get("name", ""))] = String(check.get("status", ""))
	for required in ["dependencies", "builtin_contracts", "assets", "scenes", "editor_scan"]:
		if statuses.get(required, "") != "passed":
			_fail("统一报告缺少通过阶段：%s。" % required)
			return
	if statuses.get("exports", "") != "skipped":
		_fail("未配置导出必须标记 skipped。")
		return
	print("统一项目验证入口测试通过。")
	quit(0)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else null


func _fail(message: String) -> void:
	printerr("GODOT_DEV_PROJECT_TEST %s" % message)
	quit(1)
