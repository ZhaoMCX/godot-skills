extends SceneTree

const Core := preload("contract_core.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("--headless 会禁用渲染；截图请使用可渲染显示驱动运行此脚本。")
		return
	var args := Core.parse_args(OS.get_cmdline_user_args())
	if not args.has("scene"):
		_fail("缺少 --scene <res://path.tscn>。")
		return
	var scene_path := String(args["scene"])
	var output_path := String(args.get("output", "user://godot-dev/captures/%s.png" % scene_path.get_basename().get_file()))
	var frame_count := maxi(1, int(args.get("frames", 3)))
	var packed := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null or not packed.can_instantiate():
		_fail("场景无法加载或实例化：%s" % scene_path)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	for frame in frame_count:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		root.remove_child(instance)
		instance.free()
		_fail("Viewport 没有可保存的图像；Headless 渲染驱动可能不支持截图。")
		return
	var absolute_output := Core.globalize(output_path)
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		_fail("无法创建截图目录：%s" % error_string(make_error))
		return
	var save_error := image.save_png(absolute_output)
	root.remove_child(instance)
	instance.free()
	if save_error != OK:
		_fail("保存截图失败：%s" % error_string(save_error))
		return
	print("截图已保存：%s" % output_path)
	quit(0)


func _fail(message: String) -> void:
	printerr("GODOT_DEV_CAPTURE %s" % message)
	quit(1)
