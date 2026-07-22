extends Node

signal completed(result: Resource)

@export var config: Resource
@export_node_path("Node") var target_path: NodePath
