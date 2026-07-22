extends Resource

enum Mode {
	IDLE,
	ACTIVE,
}

@export var title := "自定义资源"
@export var mode := Mode.IDLE
@export_range(0, 100, 1) var weight := 25
@export var tags: Array[String] = []
