class_name GodotDevSceneSemantics
extends Node

@export_node_path("Node") var target_path: NodePath
@export var local_data: GodotDevLocalResource

var press_count := 0


func _on_pressed() -> void:
	press_count += 1


func load_dynamic_resource(path: String) -> Resource:
	return ResourceLoader.load(path)
