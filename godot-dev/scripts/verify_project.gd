extends SceneTree

const Core := preload("contract_core.gd")
const SchemaValidator := preload("schema_validator.gd")

var _godot := ""
var _project_root := ""
var _script_root := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := Core.parse_args(OS.get_cmdline_user_args())
	_godot = OS.get_executable_path()
	_project_root = ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	_script_root = Core.globalize(get_script().resource_path.get_base_dir())
	var profile_path := String(args.get("profile", ""))
	var profile := _load_profile(profile_path)
	if profile.has("_errors"):
		_fail("验证配置无效：%s" % "; ".join(profile["_errors"]))
		return
	var changed := _argument_values(args.get("changed", []))
	var analysis_roots := changed.duplicate()
	if analysis_roots.is_empty():
		analysis_roots.append_array(_profile_scene_roots(profile))
		var configured_main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
		if not configured_main_scene.is_empty() and not analysis_roots.has(configured_main_scene):
			analysis_roots.append(configured_main_scene)
		analysis_roots.append("res://project.godot")
	var checks := []
	var report_root := "user://godot-dev/reports/project-verification"

	var dependency_report := report_root.path_join("dependencies.json")
	var dependency_args := ["--headless", "--path", _project_root, "--script", _script_root.path_join("collect_dependencies.gd"), "--"]
	for path in analysis_roots:
		dependency_args.append_array(["--changed", path])
	if changed.is_empty():
		dependency_args.append("--forward-only")
	dependency_args.append_array(["--report", dependency_report])
	checks.append(_run_check("dependencies", dependency_args, true))

	var affected := _affected_assets(dependency_report, analysis_roots)
	var builtin_manifest: String = get_script().resource_path.get_base_dir().path_join("../references/contracts/godot-4.7/manifest.json").simplify_path()
	checks.append(_run_check("builtin_contracts", ["--headless", "--path", _project_root, "--script", _script_root.path_join("validate_contract.gd"), "--", "--manifest", Core.globalize(builtin_manifest), "--require-complete"], true))
	var project_manifest := "res://docs/godot-dev/manifest.json"
	if FileAccess.file_exists(Core.globalize(project_manifest)):
		checks.append(_run_check("project_contracts", ["--headless", "--path", _project_root, "--script", _script_root.path_join("validate_contract.gd"), "--", "--manifest", Core.globalize(project_manifest)], true))
	else:
		checks.append(_skipped("project_contracts", "项目没有 docs/godot-dev/manifest.json。"))

	# 新克隆的项目尚未生成全局脚本类缓存。必须先完成编辑器扫描，
	# 后续资产加载与场景审计才能解析 class_name 类型。
	checks.append(_run_check("editor_scan", ["--headless", "--editor", "--path", _project_root, "--quit-after", "30"], true))

	var asset_files := _filter_extensions(affected, ["gd", "tres", "res", "gdshader", "svg", "png", "jpg", "jpeg", "webp", "wav", "ogg", "mp3", "ttf", "otf", "po", "csv"])
	if not asset_files.is_empty():
		var asset_args := ["--headless", "--path", _project_root, "--script", _script_root.path_join("validate_assets.gd"), "--"]
		for path in asset_files:
			asset_args.append_array(["--file", path])
		checks.append(_run_check("assets", asset_args, true))
	else:
		checks.append(_skipped("assets", "影响闭包没有可验证资产。"))

	var scenes: Array[String] = []
	if not changed.is_empty():
		scenes = _filter_extensions(affected, ["tscn", "scn"])
	else:
		scenes = _profile_scene_roots(profile)
	if scenes.is_empty():
		var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
		if not main_scene.is_empty():
			scenes.append(main_scene)
	if not scenes.is_empty():
		var scene_report := report_root.path_join("scenes.json")
		var scene_args := ["--headless", "--path", _project_root, "--script", _script_root.path_join("audit_scene.gd"), "--", "--strict", "--report", scene_report]
		for path in scenes:
			scene_args.append_array(["--file", path])
		checks.append(_run_check("scenes", scene_args, true))
		checks.append(_check_budgets(profile, scene_report))
	else:
		checks.append(_skipped("scenes", "未配置场景且项目没有主场景。"))
		checks.append(_skipped("budgets", "没有场景指标。"))

	checks.append(_run_main_scene(profile))
	checks.append_array(_run_render_cases(profile))
	checks.append_array(_run_export_presets(profile))

	var overall := "passed"
	for check in checks:
		if check["status"] == "failed" or (check["status"] == "blocked" and check.get("required", false)):
			overall = "failed"
	var report := {
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"status": overall,
		"changed": changed,
		"analysis_roots": analysis_roots,
		"affected": affected,
		"profile": profile_path,
		"checks": checks,
	}
	var report_path := String(args.get("report", "user://godot-dev/reports/project-verification.json"))
	if Core.write_json(report_path, report) != OK:
		_fail("无法写入项目验证报告：%s。" % report_path)
		return
	for check in checks:
		print("GODOT_DEV_PROJECT %s=%s" % [check["name"], check["status"]])
	print("项目验证完成：%s；报告 %s。" % [overall, report_path])
	quit(0 if overall == "passed" else 1)


func _run_check(name: String, arguments: PackedStringArray, required: bool) -> Dictionary:
	var output := []
	var started := Time.get_ticks_msec()
	var exit_code := OS.execute(_godot, arguments, output, true, false)
	var text := "\n".join(output)
	var forbidden := _forbidden_log_findings(text)
	var status := "passed" if exit_code == 0 and forbidden.is_empty() else "failed"
	return {
		"name": name,
		"status": status,
		"required": required,
		"exit_code": exit_code,
		"duration_msec": Time.get_ticks_msec() - started,
		"command": PackedStringArray(arguments),
		"findings": forbidden,
		"output": text,
	}


func _run_main_scene(profile: Dictionary) -> Dictionary:
	var required := bool(profile.get("run_main", true))
	var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene.is_empty():
		return _skipped("main_scene", "项目没有 application/run/main_scene。")
	if not required:
		return _skipped("main_scene", "验证配置关闭主场景运行。")
	return _run_check("main_scene", ["--headless", "--path", _project_root, "--quit-after", "10"], true)


func _run_render_cases(profile: Dictionary) -> Array:
	var results := []
	var cases: Array = profile.get("render_cases", [])
	if cases.is_empty():
		return [_skipped("render", "未配置真实渲染案例。")]
	for index in cases.size():
		var item: Dictionary = cases[index]
		var required := bool(item.get("required", false))
		var output_path := String(item.get("output", "user://godot-dev/captures/render-%d.png" % index))
		var arguments := ["--path", _project_root, "--audio-driver", "Dummy", "--script", _script_root.path_join("capture_scene.gd"), "--", "--scene", String(item.get("scene", "")), "--output", output_path, "--frames", str(item.get("frames", 3))]
		var result := _run_check("render:%s" % item.get("scene", index), arguments, required)
		if result["status"] == "failed" and not required:
			result["status"] = "blocked"
		results.append(result)
	return results


func _run_export_presets(profile: Dictionary) -> Array:
	var results := []
	var presets: Array = profile.get("export_presets", [])
	if presets.is_empty():
		return [_skipped("exports", "未配置导出预设。")]
	if not FileAccess.file_exists(_project_root.path_join("export_presets.cfg")):
		for item in presets:
			results.append(_blocked("export:%s" % item.get("name", ""), "项目缺少 export_presets.cfg。", bool(item.get("required", false))))
		return results
	for item in presets:
		var preset := String(item.get("name", ""))
		var required := bool(item.get("required", false))
		var output_path := ProjectSettings.globalize_path("user://godot-dev/exports/%s.pck" % preset.to_snake_case())
		var result := _run_check("export:%s" % preset, ["--headless", "--path", _project_root, "--export-pack", preset, output_path], required)
		if result["status"] == "failed" and not required:
			result["status"] = "blocked"
		results.append(result)
	return results


func _check_budgets(profile: Dictionary, report_path: String) -> Dictionary:
	var budgets: Dictionary = profile.get("budgets", {})
	if budgets.is_empty():
		return _skipped("budgets", "未配置性能预算，只保留场景指标。")
	var report_value: Variant = Core.read_json(report_path)
	if not report_value is Dictionary:
		return _blocked("budgets", "无法读取场景指标报告。", true)
	var findings := []
	var field_map := {"max_nodes": "runtime_nodes", "max_depth": "max_depth", "max_external_resources": "external_resources", "max_sub_resources": "sub_resources", "max_instantiation_usec": "instantiation_usec"}
	for scene in report_value.get("scenes", []):
		for budget_name in field_map:
			if not budgets.has(budget_name):
				continue
			var actual := int(scene.get("metrics", {}).get(field_map[budget_name], 0))
			if actual > int(budgets[budget_name]):
				findings.append("%s 的 %s=%d 超过预算 %d" % [scene.get("path", ""), field_map[budget_name], actual, budgets[budget_name]])
	return {"name": "budgets", "status": "passed" if findings.is_empty() else "failed", "required": true, "findings": findings}


func _load_profile(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var value: Variant = Core.read_json(path)
	if not value is Dictionary:
		return {"_errors": ["无法读取 JSON：%s" % path]}
	var schema_path: String = get_script().resource_path.get_base_dir().path_join("../references/validation-profile.schema.json").simplify_path()
	var findings := SchemaValidator.validate(value, schema_path)
	if not findings.is_empty():
		value["_errors"] = findings
	return value


func _affected_assets(report_path: String, changed: Array[String]) -> Array[String]:
	var value: Variant = Core.read_json(report_path)
	if value is Dictionary:
		var affected: Array[String] = []
		for item in value.get("affected", []):
			affected.append(String(item))
		return affected
	return changed


func _profile_scene_roots(profile: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for path in profile.get("scene_roots", []):
		result.append(String(path))
	return result


func _filter_extensions(paths: Array[String], extensions: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for path in paths:
		if extensions.has(path.get_extension().to_lower()) and not result.has(path):
			result.append(path)
	result.sort()
	return result


func _forbidden_log_findings(output: String) -> Array:
	var findings := []
	for marker in ["SCRIPT ERROR:", "ERROR:", "ObjectDB instances were leaked", "RIDs of type", "resources still in use at exit", "orphans"]:
		if output.contains(marker):
			findings.append(marker)
	return findings


func _skipped(name: String, reason: String) -> Dictionary:
	return {"name": name, "status": "skipped", "required": false, "findings": [reason]}


func _blocked(name: String, reason: String, required: bool) -> Dictionary:
	return {"name": name, "status": "blocked", "required": required, "findings": [reason]}


func _argument_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	elif value != null and String(value) != "":
		result.append(String(value))
	return result


func _fail(message: String) -> void:
	printerr("GODOT_DEV_PROJECT %s" % message)
	quit(1)
