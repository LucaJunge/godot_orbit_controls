extends Camera3D

func _ready() -> void:
	self.look_at(Vector3(0, 0, 0), Vector3(0, 1, 0))
