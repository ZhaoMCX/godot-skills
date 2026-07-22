extends SceneTree

const Core := preload("contract_core.gd")
const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "gdshader", "godot"]


func _init() -> void:
	var args := Core.parse_args(OS.get_cmdline_user_args())
	var changed := _argument_values(args.get("changed", []))
	var forward_only := bool(args.get("forward-only", false))
	var strict_cycles := bool(args.get("strict-cycles", false))
	var graph := _build_graph()
	var reverse := _reverse_graph(graph["dependencies"])
	var affected: Array = _affected_closure(changed, graph["dependencies"], reverse, not forward_only) if not changed.is_empty() else graph["dependencies"].keys()
	affected.sort()
	var affected_lookup := {}
	for path in affected:
		affected_lookup[path] = true
	var relevant_missing := []
	for missing in graph["missing"]:
		if affected_lookup.has(missing["from"]):
			relevant_missing.append(missing)
	var cycles := []
	for cycle in _find_cycles(graph["dependencies"]):
		if _cycle_intersects(cycle, affected_lookup):
			cycles.append(cycle)
	var relevant_dynamic := []
	for dynamic_reference in graph["dynamic_references"]:
		if affected_lookup.has(dynamic_reference["path"]):
			relevant_dynamic.append(dynamic_reference)
	var errors := []
	for missing in relevant_missing:
		errors.append("静态引用不存在：%s -> %s" % [missing["from"], missing["to"]])
	if strict_cycles:
		for cycle in cycles:
			errors.append("循环静态依赖：%s" % " -> ".join(cycle))
	var report := {
		"engine_version": Core.engine_version(),
		"engine_build_hash": Core.engine_build_hash(),
		"status": "passed" if errors.is_empty() else "failed",
		"changed": changed,
		"affected": affected,
		"dependencies": graph["dependencies"],
		"reverse_dependencies": reverse,
		"dynamic_references": relevant_dynamic,
		"missing": relevant_missing,
		"cycles": cycles,
		"errors": errors,
	}
	var report_path := String(args.get("report", "user://godot-dev/reports/dependencies.json"))
	if Core.write_json(report_path, report) != OK:
		_fail("无法写入依赖报告：%s。" % report_path)
		return
	for error in errors:
		printerr("GODOT_DEV_DEPENDENCY %s" % error)
	for dynamic_reference in relevant_dynamic:
		print("GODOT_DEV_DEPENDENCY_WARNING 动态引用无法静态闭包：%s:%s" % [dynamic_reference["path"], dynamic_reference["line"]])
	print("依赖分析完成：%d 个文件，影响闭包 %d 个，失败 %d 项。" % [graph["dependencies"].size(), affected.size(), errors.size()])
	quit(0 if errors.is_empty() else 1)


func _build_graph() -> Dictionary:
	var dependencies := {}
	var dynamic_references := []
	var missing := []
	var files := _collect_files("res://")
	var resource_path_regex := RegEx.new()
	resource_path_regex.compile("\\bpath=\\\"([^\\\"]+)\\\"")
	var script_load_regex := RegEx.new()
	script_load_regex.compile("(?:ResourceLoader\\.)?(?:load|preload)\\s*\\(\\s*[\\\"']([^\\\"']+)[\\\"']\\s*\\)")
	var configured_path_regex := RegEx.new()
	configured_path_regex.compile("[\\\"']\\*?(res://[^\\\"']+)[\\\"']")
	var shader_include_regex := RegEx.new()
	shader_include_regex.compile("^\\s*#include\\s+[\\\"']([^\\\"']+)[\\\"']")
	var uid_regex := RegEx.new()
	uid_regex.compile("uid://[a-z0-9]+")
	var dynamic_regex := RegEx.new()
	dynamic_regex.compile("(?:load|preload)\\s*\\(\\s*[^\\\"']")
	var dynamic_concat_regex := RegEx.new()
	dynamic_concat_regex.compile("(?:load|preload)\\s*\\(\\s*[\\\"'][^\\\"']*[\\\"']\\s*\\+")
	for path in files:
		var content := Core.read_text(path)
		var found := {}
		var line_number := 0
		var extension := path.get_extension().to_lower()
		for line in content.split("\n"):
			line_number += 1
			var source_line := _strip_gdscript_comment(line) if extension == "gd" else line
			if extension == "tscn" or extension == "tres":
				if source_line.strip_edges().begins_with("[ext_resource"):
					for match in resource_path_regex.search_all(source_line):
						_add_reference(found, path, match.get_string(1))
					for match in uid_regex.search_all(source_line):
						var uid_text := String(match.get_string())
						var uid := ResourceUID.text_to_id(uid_text)
						if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
							found[ResourceUID.get_id_path(uid)] = true
			elif extension == "gd":
				for match in script_load_regex.search_all(source_line):
					_add_reference(found, path, match.get_string(1))
				if dynamic_regex.search(source_line) != null or dynamic_concat_regex.search(source_line) != null:
					dynamic_references.append({"path": path, "line": line_number, "text": source_line.strip_edges()})
			elif extension == "godot":
				for match in configured_path_regex.search_all(source_line):
					_add_reference(found, path, match.get_string(1))
				for match in uid_regex.search_all(source_line):
					var uid_text := String(match.get_string())
					var uid := ResourceUID.text_to_id(uid_text)
					if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
						found[ResourceUID.get_id_path(uid)] = true
			elif extension == "gdshader":
				var include_match := shader_include_regex.search(source_line)
				if include_match != null:
					_add_reference(found, path, include_match.get_string(1))
		var refs: Array = found.keys()
		refs.erase(path)
		refs.sort()
		dependencies[path] = refs
		for reference in refs:
			if String(reference).begins_with("res://") and not FileAccess.file_exists(String(reference)):
				missing.append({"from": path, "to": reference})
	return {"dependencies": dependencies, "dynamic_references": dynamic_references, "missing": missing}


func _add_reference(found: Dictionary, source_path: String, raw_reference: String) -> void:
	var reference := raw_reference.strip_edges()
	if reference.is_empty() or reference.begins_with("user://"):
		return
	if not reference.begins_with("res://") and not reference.begins_with("uid://"):
		reference = source_path.get_base_dir().path_join(reference).simplify_path()
	if reference.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(reference)
		if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
			reference = ResourceUID.get_id_path(uid)
		else:
			return
	found[reference] = true


func _strip_gdscript_comment(line: String) -> String:
	var quote := ""
	var escaped := false
	for index in line.length():
		var character := line.substr(index, 1)
		if escaped:
			escaped = false
			continue
		if character == "\\" and not quote.is_empty():
			escaped = true
			continue
		if character == "\"" or character == "'":
			if quote.is_empty():
				quote = character
			elif quote == character:
				quote = ""
			continue
		if character == "#" and quote.is_empty():
			return line.left(index)
	return line


func _collect_files(directory: String) -> Array[String]:
	var result: Array[String] = []
	var access := DirAccess.open(directory)
	if access == null:
		return result
	access.list_dir_begin()
	var name := access.get_next()
	while not name.is_empty():
		if name.begins_with("."):
			name = access.get_next()
			continue
		var path := directory.path_join(name)
		if access.current_is_dir():
			result.append_array(_collect_files(path))
		elif TEXT_EXTENSIONS.has(name.get_extension().to_lower()):
			result.append(path)
		name = access.get_next()
	access.list_dir_end()
	result.sort()
	return result


func _reverse_graph(dependencies: Dictionary) -> Dictionary:
	var reverse := {}
	for source in dependencies:
		if not reverse.has(source):
			reverse[source] = []
		for target in dependencies[source]:
			if not reverse.has(target):
				reverse[target] = []
			if not reverse[target].has(source):
				reverse[target].append(source)
	for target in reverse:
		reverse[target].sort()
	return reverse


func _affected_closure(changed: Array[String], dependencies: Dictionary, reverse: Dictionary, include_reverse: bool) -> Array:
	var visited := {}
	var queue: Array = changed.duplicate()
	while not queue.is_empty():
		var path := String(queue.pop_front())
		if visited.has(path):
			continue
		visited[path] = true
		for dependency in dependencies.get(path, []):
			queue.append(dependency)
		if include_reverse:
			for parent in reverse.get(path, []):
				queue.append(parent)
	return visited.keys()


func _cycle_intersects(cycle: Array, affected_lookup: Dictionary) -> bool:
	for path in cycle:
		if affected_lookup.has(path):
			return true
	return false


func _find_cycles(dependencies: Dictionary) -> Array:
	var cycles := []
	var state := {}
	var stack: Array[String] = []
	for path in dependencies:
		_visit_cycle(String(path), dependencies, state, stack, cycles)
	return cycles


func _visit_cycle(path: String, dependencies: Dictionary, state: Dictionary, stack: Array[String], cycles: Array) -> void:
	if int(state.get(path, 0)) == 2:
		return
	if int(state.get(path, 0)) == 1:
		var start := stack.find(path)
		if start >= 0:
			var cycle := stack.slice(start)
			cycle.append(path)
			if not cycles.has(cycle):
				cycles.append(cycle)
		return
	state[path] = 1
	stack.append(path)
	for target in dependencies.get(path, []):
		if dependencies.has(target):
			_visit_cycle(String(target), dependencies, state, stack, cycles)
	stack.pop_back()
	state[path] = 2


func _argument_values(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	elif value != null and String(value) != "":
		result.append(String(value))
	return result


func _fail(message: String) -> void:
	printerr("GODOT_DEV_DEPENDENCY %s" % message)
	quit(1)
